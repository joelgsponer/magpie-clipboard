import AppKit

struct LaunchableApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?

    var id: String { url.path }
}

/// Catalogue of launchable applications, built by walking the standard
/// application folders (two levels deep, so vendor sub-folders like
/// /Applications/Utilities or /Applications/Adobe count). Launch counts are
/// kept so the apps you actually use float to the top of an empty query.
@MainActor
final class AppIndex: ObservableObject {
    static let shared = AppIndex()

    @Published private(set) var apps: [LaunchableApp] = []
    @Published private(set) var scanning = false

    private var lastScan: Date?
    private var iconCache: [String: NSImage] = [:]
    private var launchCounts: [String: Int]

    private static let countsKey = "launcherLaunchCounts"
    private static let staleAfter: TimeInterval = 120

    private init() {
        launchCounts = UserDefaults.standard.dictionary(forKey: Self.countsKey) as? [String: Int] ?? [:]
    }

    func refreshIfStale(force: Bool = false) {
        if !force, let lastScan, Date().timeIntervalSince(lastScan) < Self.staleAfter { return }
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async {
                self.apps = found
                self.lastScan = Date()
                self.scanning = false
                NSLog("Magpie: app index scanned \(found.count) apps")
            }
        }
    }

    func icon(for app: LaunchableApp) -> NSImage {
        if let cached = iconCache[app.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[app.id] = icon
        return icon
    }

    func launchCount(for app: LaunchableApp) -> Int {
        launchCounts[app.id] ?? 0
    }

    func isRunning(_ app: LaunchableApp) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func launch(_ app: LaunchableApp) {
        launchCounts[app.id, default: 0] += 1
        UserDefaults.standard.set(launchCounts, forKey: Self.countsKey)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error { NSLog("Magpie: launch \(app.name) failed: \(error)") }
        }
    }

    func reveal(_ app: LaunchableApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    // MARK: - Scan

    nonisolated private static let roots: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // Safari (and whatever else Apple moves there) lives in the app
        // cryptex; /Applications/Safari.app is only a *hidden* symlink to
        // it, which skipsHiddenFiles drops.
        "/System/Cryptexes/App/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    nonisolated private static func scan() -> [LaunchableApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [LaunchableApp] = []

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return }
            let bundleID = Bundle(url: url)?.bundleIdentifier
            if let bundleID, seen.contains("id:" + bundleID) { return }
            seen.insert(path)
            if let bundleID { seen.insert("id:" + bundleID) }
            var name = fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            result.append(LaunchableApp(url: url, name: name, bundleID: bundleID))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    add(url)
                    enumerator.skipDescendants()
                    continue
                }
                if enumerator.level >= 2 { enumerator.skipDescendants() }
            }
        }

        // Finder lives outside every root above.
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
