import Foundation

struct GitHubRepo: Identifiable, Hashable, Codable {
    let nameWithOwner: String
    let description: String
    let isPrivate: Bool
    let pushedAt: Date?

    var id: String { nameWithOwner }
    var owner: String { String(nameWithOwner.split(separator: "/").first ?? "") }
    var name: String { String(nameWithOwner.split(separator: "/").last ?? "") }
}

/// Locates and runs the `gh` CLI. Same PATH problem as `claude`: a GUI app
/// inherits launchd's PATH, so the binary is looked up explicitly and cached.
enum GitHubCLI {
    static let cacheKey = "ghCLIPathCache"

    static func resolve() -> String? {
        let fm = FileManager.default
        if let cached = UserDefaults.standard.string(forKey: cacheKey), fm.isExecutableFile(atPath: cached) {
            return cached
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "\(home)/.local/bin/gh",
            "\(home)/.nix-profile/bin/gh",
        ]
        var found = candidates.first { fm.isExecutableFile(atPath: $0) }
        if found == nil {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: shell)
            proc.arguments = ["-lc", "command -v gh"]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = FileHandle.nullDevice
            proc.standardInput = FileHandle.nullDevice
            if (try? proc.run()) != nil {
                proc.waitUntilExit()
                let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if fm.isExecutableFile(atPath: path) { found = path }
            }
        }
        if let found { UserDefaults.standard.set(found, forKey: cacheKey) }
        return found
    }

    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
        var errorLine: String {
            stderr.split(separator: "\n").last.map(String.init) ?? "gh exited with \(status)"
        }
    }

    /// Runs off the main thread; the completion lands back on it.
    static func run(_ args: [String], completion: @escaping @MainActor (Output) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let exe = resolve() else {
                DispatchQueue.main.async {
                    completion(Output(status: 127, stdout: "", stderr: "The gh command was not found. Install GitHub CLI (brew install gh) and run gh auth login."))
                }
                return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            proc.standardInput = FileHandle.nullDevice
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\((exe as NSString).deletingLastPathComponent):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["GH_PROMPT_DISABLED"] = "1"
            env["NO_COLOR"] = "1"
            proc.environment = env
            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err
            do {
                try proc.run()
            } catch {
                DispatchQueue.main.async {
                    completion(Output(status: 126, stdout: "", stderr: error.localizedDescription))
                }
                return
            }
            let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            proc.waitUntilExit()
            let result = Output(status: proc.terminationStatus, stdout: stdout, stderr: stderr)
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// The repositories you can file issues against: owned, collaborator, and
/// organisation repos, newest push first. Cached on disk so the picker is
/// instant; refreshed in the background when older than ten minutes.
@MainActor
final class GitHubRepos: ObservableObject {
    static let shared = GitHubRepos()

    @Published private(set) var repos: [GitHubRepo] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private var lastFetch: Date?
    private var useCounts: [String: Int]

    private static let cacheKey = "githubRepoCache"
    private static let cacheDateKey = "githubRepoCacheDate"
    private static let useCountsKey = "githubRepoUseCounts"
    private static let staleAfter: TimeInterval = 600

    private init() {
        useCounts = UserDefaults.standard.dictionary(forKey: Self.useCountsKey) as? [String: Int] ?? [:]
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([GitHubRepo].self, from: data) {
            repos = cached
            lastFetch = UserDefaults.standard.object(forKey: Self.cacheDateKey) as? Date
        }
    }

    func useCount(_ repo: GitHubRepo) -> Int { useCounts[repo.id] ?? 0 }

    func recordUse(_ repo: GitHubRepo) {
        useCounts[repo.id, default: 0] += 1
        UserDefaults.standard.set(useCounts, forKey: Self.useCountsKey)
    }

    func refreshIfStale(force: Bool = false) {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < Self.staleAfter { return }
        guard !loading else { return }
        loading = true
        error = nil
        GitHubCLI.run([
            "api", "--paginate",
            "user/repos?affiliation=owner,collaborator,organization_member&per_page=100&sort=pushed",
            "--jq", ".[] | {n: .full_name, d: (.description // \"\"), p: .private, t: .pushed_at}",
        ]) { [weak self] output in
            guard let self else { return }
            self.loading = false
            guard output.ok else {
                self.error = output.errorLine
                return
            }
            let iso = ISO8601DateFormatter()
            var seen = Set<String>()
            var parsed: [GitHubRepo] = []
            for line in output.stdout.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let name = obj["n"] as? String, !seen.contains(name) else { continue }
                seen.insert(name)
                parsed.append(GitHubRepo(
                    nameWithOwner: name,
                    description: obj["d"] as? String ?? "",
                    isPrivate: obj["p"] as? Bool ?? false,
                    pushedAt: (obj["t"] as? String).flatMap { iso.date(from: $0) }
                ))
            }
            self.repos = parsed
            self.lastFetch = Date()
            if let data = try? JSONEncoder().encode(parsed) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
                UserDefaults.standard.set(Date(), forKey: Self.cacheDateKey)
            }
        }
    }

    struct CreatedIssue {
        let url: URL
        var number: String { url.lastPathComponent }
    }

    func createIssue(in repo: GitHubRepo, title: String, body: String, completion: @escaping @MainActor (Result<CreatedIssue, Error>) -> Void) {
        var args = ["issue", "create", "-R", repo.nameWithOwner, "--title", title]
        args += ["--body", body.isEmpty ? "" : body]
        GitHubCLI.run(args) { output in
            let urlLine = output.stdout.split(separator: "\n").last(where: { $0.contains("://") }).map(String.init) ?? ""
            if output.ok, let url = URL(string: urlLine.trimmingCharacters(in: .whitespaces)) {
                completion(.success(CreatedIssue(url: url)))
            } else {
                completion(.failure(GitHubError(message: output.errorLine)))
            }
        }
    }
}

struct GitHubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
