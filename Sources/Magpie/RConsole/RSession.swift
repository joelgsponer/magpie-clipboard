import AppKit
import Foundation

struct REntry: Identifiable, Equatable {
    let id = UUID()
    let code: String
    var output: String = ""
    var plot: NSImage?
    var plotURL: URL?
    var isDone = false
}

/// One long-lived R process. Each command is wrapped in `.magpie_run()`,
/// which evaluates it in the global environment, prints visible results,
/// reports errors and warnings inline, closes any plot device (so the PNG
/// is flushed), and ends with a sentinel line so the app knows the command
/// finished. Plots go to PNG files in a temp directory via `options(device)`.
@MainActor
final class RSession: ObservableObject {
    static let shared = RSession()

    enum Status: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var entries: [REntry] = []
    @Published private(set) var status: Status = .stopped
    @Published private(set) var isRunning = false
    @Published private(set) var versionString = "R"
    @Published private(set) var latestPlot: NSImage?
    @Published private(set) var latestPlotURL: URL?
    @Published private(set) var history: [String] = []

    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var queue: [String] = []
    private let plotDir: URL
    private var seenPlots = Set<String>()
    private static let done = "<<MAGPIE_DONE>>"
    private static let ready = "<<MAGPIE_READY>>"

    private init() {
        plotDir = FileManager.default.temporaryDirectory.appendingPathComponent("magpie-rplots-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: plotDir, withIntermediateDirectories: true)
    }

    var isAlive: Bool { process?.isRunning == true }

    // MARK: - Locating R

    static func resolve() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/R",
            "/usr/local/bin/R",
            "/Library/Frameworks/R.framework/Resources/bin/R",
            "/opt/R/bin/R",
        ]
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return hit }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "command -v R"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fm.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - Lifecycle

    func startIfNeeded() {
        guard !isAlive, status != .starting else { return }
        start()
    }

    func restart() {
        stop()
        entries.removeAll()
        latestPlot = nil
        latestPlotURL = nil
        start()
    }

    func clear() {
        entries.removeAll()
    }

    func stop() {
        queue.removeAll()
        isRunning = false
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        stdin = nil
        status = .stopped
    }

    private func start() {
        guard let exe = Self.resolve() else {
            status = .failed("R was not found. Install it (brew install r) or from CRAN.")
            return
        }
        status = .starting
        ChatManager.ensureHome()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = ["--vanilla", "--quiet", "--no-echo"]
        proc.currentDirectoryURL = ChatManager.home
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\((exe as NSString).deletingLastPathComponent):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["MAGPIE_PLOT_DIR"] = plotDir.path
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        proc.environment = env

        let input = Pipe()
        let output = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = output
        buffer = Data()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        proc.terminationHandler = { [weak self] p in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.process = nil
                self.stdin = nil
                self.isRunning = false
                self.status = .failed("R exited (status \(p.terminationStatus)). ⌘R restarts it.")
            }
        }

        do {
            try proc.run()
        } catch {
            status = .failed("Could not start R: \(error.localizedDescription)")
            return
        }
        process = proc
        stdin = input.fileHandleForWriting
        write(Self.bootstrap)
    }

    private static let bootstrap = """
    options(width = 100, warn = 1)
    .magpie_plot_dir <- Sys.getenv("MAGPIE_PLOT_DIR")
    .magpie_plot_n <- 0
    options(device = function(...) {
      .magpie_plot_n <<- .magpie_plot_n + 1
      grDevices::png(filename = file.path(.magpie_plot_dir, sprintf("plot-%04d.png", .magpie_plot_n)),
                     width = 1600, height = 1000, res = 200, bg = "white")
    })
    .magpie_run <- function(code) {
      withCallingHandlers(
        tryCatch({
          res <- withVisible(eval(parse(text = code), envir = globalenv()))
          if (res$visible) print(res$value)
        }, error = function(e) cat("Error: ", conditionMessage(e), "\\n", sep = "")),
        warning = function(w) { cat("Warning: ", conditionMessage(w), "\\n", sep = ""); invokeRestart("muffleWarning") },
        message = function(m) { cat(conditionMessage(m)); invokeRestart("muffleMessage") }
      )
      while (grDevices::dev.cur() > 1) grDevices::dev.off()
      cat("\(done)\\n")
    }
    cat("\(ready) ", R.version.string, "\\n", sep = "")

    """

    // MARK: - Running code

    func run(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if history.last != trimmed { history.append(trimmed) }
        entries.append(REntry(code: trimmed))
        queue.append(trimmed)
        startIfNeeded()
        pump()
    }

    private func pump() {
        guard !isRunning, status == .ready, let next = queue.first else { return }
        queue.removeFirst()
        isRunning = true
        write(".magpie_run(\"\(Self.escape(next))\")\n")
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": continue
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    private func write(_ text: String) {
        guard let stdin, let data = text.data(using: .utf8) else { return }
        try? stdin.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
            handle(line: line)
        }
    }

    private func handle(line: String) {
        if line.hasPrefix(Self.ready) {
            versionString = String(line.dropFirst(Self.ready.count)).trimmingCharacters(in: .whitespaces)
            status = .ready
            pump()
            return
        }
        if line == Self.done {
            if let idx = entries.lastIndex(where: { !$0.isDone }) {
                entries[idx].isDone = true
                entries[idx].output = entries[idx].output.trimmingCharacters(in: .newlines)
                if let (image, url) = newestPlot() {
                    entries[idx].plot = image
                    entries[idx].plotURL = url
                    latestPlot = image
                    latestPlotURL = url
                }
            }
            isRunning = false
            pump()
            return
        }
        if let idx = entries.lastIndex(where: { !$0.isDone }) {
            entries[idx].output += line + "\n"
        }
    }

    private func newestPlot() -> (NSImage, URL)? {
        let files = (try? FileManager.default.contentsOfDirectory(at: plotDir, includingPropertiesForKeys: nil)) ?? []
        let fresh = files.filter { $0.pathExtension == "png" && !seenPlots.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for f in fresh { seenPlots.insert(f.lastPathComponent) }
        guard let last = fresh.last, let image = NSImage(contentsOf: last) else { return nil }
        return (image, last)
    }

    // MARK: - Clipboard

    /// Straight to the pasteboard, not through Paster.copyText: the watcher
    /// should ingest it so the plot shows up in clipboard history as an image.
    func copyLatestPlot() {
        guard let url = latestPlotURL, let data = try? Data(contentsOf: url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    var lastOutput: String? {
        entries.last(where: { $0.isDone && !$0.output.isEmpty })?.output
    }
}
