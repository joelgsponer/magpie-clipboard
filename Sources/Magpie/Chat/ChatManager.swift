import AppKit
import AVFoundation
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    /// Tools the assistant invoked while producing this reply ("Bash", "Read").
    var toolNotes: [String] = []
    var isStreaming = false
    var error: String?
    var costUSD: Double?
}

struct ChatModel: Identifiable, Hashable {
    let id: String     // what `--model` receives
    let label: String

    static let all: [ChatModel] = [
        ChatModel(id: "haiku", label: "Haiku 4.5"),
        ChatModel(id: "sonnet", label: "Sonnet 5"),
        ChatModel(id: "opus", label: "Opus 5"),
        ChatModel(id: "claude-fable-5-1", label: "Fable 5.1"),
    ]
    static let defaultID = "sonnet"
}

/// One persistent Claude Code conversation, driven through `claude -p` with
/// `--resume` so context carries across turns. The session lives as long as
/// Magpie does or until the user starts a new chat; hiding the panel does
/// not end it. Streams `stream-json` events so text appears as it is
/// generated and tool calls are visible while they run.
@MainActor
final class ChatManager: ObservableObject {
    static let shared = ChatManager()

    static let fullPermissionsKey = "chatFullPermissions"
    static let voiceOutputKey = "chatVoiceOutput"
    static let modelKey = "chatModel"

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isBusy = false
    @Published private(set) var sessionID: String?
    @Published private(set) var totalCostUSD: Double = 0
    @Published private(set) var cliPath: String?
    @Published private(set) var isSpeaking = false

    @Published var fullPermissions: Bool {
        didSet { UserDefaults.standard.set(fullPermissions, forKey: Self.fullPermissionsKey) }
    }
    @Published var voiceOutput: Bool {
        didSet {
            UserDefaults.standard.set(voiceOutput, forKey: Self.voiceOutputKey)
            if !voiceOutput { stopSpeaking() }
        }
    }
    @Published var modelID: String {
        didSet { UserDefaults.standard.set(modelID, forKey: Self.modelKey) }
    }

    private var process: Process?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?

    private init() {
        let d = UserDefaults.standard
        fullPermissions = d.bool(forKey: Self.fullPermissionsKey)
        voiceOutput = d.bool(forKey: Self.voiceOutputKey)
        modelID = d.string(forKey: Self.modelKey) ?? ChatModel.defaultID
        let delegate = SpeechDelegate { [weak self] speaking in
            Task { @MainActor in self?.isSpeaking = speaking }
        }
        speechDelegate = delegate
        synthesizer.delegate = delegate
    }

    // MARK: - Public

    func resolveCLI() {
        guard cliPath == nil else { return }
        DispatchQueue.global().async {
            let path = ClaudeCLI.resolve()
            DispatchQueue.main.async { self.cliPath = path }
        }
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        guard let cli = cliPath ?? ClaudeCLI.resolve() else {
            messages.append(ChatMessage(role: .assistant, text: "", error: "The `claude` command was not found. Set its path under Settings › Screen Capture."))
            return
        }
        cliPath = cli
        stopSpeaking()

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        isBusy = true
        launch(executable: cli, prompt: text)
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        process.terminate()
        finish(error: "Stopped.", cost: nil)
    }

    func newChat() {
        cancel()
        stopSpeaking()
        messages.removeAll()
        sessionID = nil
        totalCostUSD = 0
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    // MARK: - Process

    /// The short part of the instructions. The rest lives in
    /// `~/Magpie/CLAUDE.md`, where the user can edit it.
    private static let systemPrompt = """
    You are running inside Magpie's cockpit panel, a small floating chat on the user's Mac. \
    Be brief and direct. Your working directory is the user's Magpie folder; read its CLAUDE.md.
    """

    /// Where the assistant lives: `~/Magpie`. Claude Code runs there, so its
    /// `CLAUDE.md` is picked up as project instructions and `.claude/skills/`
    /// can hold skills — and it is a place the agent may write files.
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Magpie", isDirectory: true)
    }

    /// Creates the folder, an editable CLAUDE.md, and the skills directory
    /// on first use. Never overwrites a CLAUDE.md the user has changed.
    static func ensureHome() {
        let fm = FileManager.default
        let home = Self.home
        try? fm.createDirectory(at: home.appendingPathComponent(".claude/skills", isDirectory: true), withIntermediateDirectories: true)
        let claudeMD = home.appendingPathComponent("CLAUDE.md")
        guard !fm.fileExists(atPath: claudeMD.path) else { return }
        try? seedCLAUDEMD.write(to: claudeMD, atomically: true, encoding: .utf8)
    }

    private static let seedCLAUDEMD = """
    # Magpie cockpit assistant

    You are the assistant behind ⌘Space T in Magpie, a menu-bar cockpit on this Mac.
    This folder (`~/Magpie`) is yours: write notes, scripts, and scratch files here
    rather than elsewhere unless asked. Skills go in `.claude/skills/`.

    ## Style

    - Brief and direct: a few sentences or a short list. Code blocks only for
      commands or code the user might copy.
    - Do the task rather than describing how, whenever tools are available.
    - If a tool needs permissions that are off, say so in one line and give the
      command the user could run themselves.

    ## Quick recipes

    - Weather: `curl -s 'wttr.in/<place>?format=3'` (`?format=v2` for a forecast);
      no place given → `curl -s 'wttr.in?format=3'`.
    - System: `sw_vers`, `uptime`, `df -h /`, `top -l 1 | head -15`, `pmset -g batt`,
      `system_profiler SPHardwareDataType`.
    - Network: `ipconfig getifaddr en0`, `networksetup -getairportnetwork en0`.
    - Open a Magpie tool: `open magpie://<clipboard|emoji|dictation|capture|apps|search|calculator|audio|chat>`.
    """

    private func launch(executable: String, prompt: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)

        var args = [
            "-p", prompt,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", modelID,
            "--append-system-prompt", Self.systemPrompt,
        ]
        if let sessionID { args += ["--resume", sessionID] }
        if fullPermissions { args.append("--dangerously-skip-permissions") }
        proc.arguments = args

        Self.ensureHome()
        proc.currentDirectoryURL = Self.home
        proc.standardInput = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        let binDir = (executable as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        stdoutBuffer = Data()
        stderrBuffer = Data()

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.stderrBuffer.append(data) }
        }
        proc.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let trailingOut = out.fileHandleForReading.readDataToEndOfFile()
            let trailingErr = err.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self, self.process === p else { return }
                self.consume(trailingOut)
                self.stderrBuffer.append(trailingErr)
                self.processExited(status: p.terminationStatus)
            }
        }

        process = proc
        do {
            try proc.run()
        } catch {
            finish(error: "Could not start claude: \(error.localizedDescription)", cost: nil)
        }
    }

    private func consume(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = stdoutBuffer[stdoutBuffer.startIndex..<nl]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            handle(event: obj)
        }
    }

    private func handle(event: [String: Any]) {
        let type = event["type"] as? String ?? ""
        switch type {
        case "system":
            if event["subtype"] as? String == "init", let id = event["session_id"] as? String {
                sessionID = id
            }

        case "stream_event":
            guard let inner = event["event"] as? [String: Any] else { return }
            switch inner["type"] as? String ?? "" {
            case "content_block_start":
                guard let block = inner["content_block"] as? [String: Any] else { return }
                switch block["type"] as? String ?? "" {
                case "tool_use":
                    let name = block["name"] as? String ?? "tool"
                    mutateCurrent { $0.toolNotes.append(name) }
                case "text":
                    mutateCurrent { if !$0.text.isEmpty { $0.text += "\n\n" } }
                default:
                    break
                }
            case "content_block_delta":
                guard let delta = inner["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String else { return }
                mutateCurrent { $0.text += text }
            default:
                break
            }

        case "result":
            let cost = event["total_cost_usd"] as? Double
            let isError = event["is_error"] as? Bool ?? false
            let resultText = event["result"] as? String ?? ""
            if let id = event["session_id"] as? String { sessionID = id }
            var error: String?
            if isError {
                error = resultText.isEmpty ? (event["subtype"] as? String ?? "error") : resultText
            }
            mutateCurrent { msg in
                if msg.text.isEmpty, !isError { msg.text = resultText }
            }
            finish(error: error, cost: cost)

        default:
            break
        }
    }

    private func processExited(status: Int32) {
        guard isBusy else { return }
        // A clean run ends via the "result" event; reaching here still busy
        // means the process died without one.
        let stderr = String(data: stderrBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = stderr.split(separator: "\n").last.map(String.init) ?? "exit \(status)"
        finish(error: "claude exited early: \(detail)", cost: nil)
    }

    private func finish(error: String?, cost: Double?) {
        process = nil
        isBusy = false
        if let cost {
            totalCostUSD += cost
        }
        mutateCurrent { msg in
            msg.isStreaming = false
            msg.costUSD = cost
            if let error, msg.error == nil { msg.error = error }
        }
        if voiceOutput, let last = messages.last, last.role == .assistant, !last.text.isEmpty, error == nil {
            speak(last.text)
        }
    }

    private func mutateCurrent(_ body: (inout ChatMessage) -> Void) {
        guard let idx = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        body(&messages[idx])
    }

    // MARK: - Speech

    private func speak(_ markdown: String) {
        let utterance = AVSpeechUtterance(string: Self.plainText(markdown))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Enough markdown stripping that read-aloud does not say "asterisk".
    static func plainText(_ md: String) -> String {
        var out: [String] = []
        var inFence = false
        for rawLine in md.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            line = line.replacingOccurrences(of: #"^\s*(#{1,6}\s+|[-*+]\s+|\d+\.\s+|>\s*)"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"[`*_]"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onChange: (Bool) -> Void
    init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { onChange(true) }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onChange(false) }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onChange(false) }
}
