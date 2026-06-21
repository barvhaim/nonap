import Foundation

/// Discovering and probing running processes for the "Keep awake until a
/// process exits" feature.
///
/// We shell out to `ps` for the one-time candidate listing — simple, needs no
/// privileges, and works identically under `swift run` and inside the `.app`
/// bundle — and use `kill(pid, 0)` for the cheap repeated liveness check while
/// a watch is running.
enum ProcessWatch {

    /// A discovered process: its pid and short executable name.
    struct Candidate { let pid: pid_t; let name: String }

    /// AI coding agents and local-inference runtimes — the processes most
    /// people open this menu to watch. Listed first, in this order.
    private static let agentNeedles = [
        "claude", "cursor", "codex", "chatgpt", "ollama", "llama",
    ]

    /// IDE extension-host bundles: each entry maps a recognisable substring in
    /// the full executable path to the friendly label used in the process menu.
    /// These processes host coding-agent extensions (Claude Code, Copilot, etc.)
    /// but have names with spaces and parens that defeat the needle matcher.
    /// Insiders listed first so its path isn't swallowed by the shorter VS Code entry.
    private static let extensionHosts: [(bundle: String, label: String)] = [
        ("Visual Studio Code - Insiders.app", "VS Code Insiders"),
        ("Visual Studio Code.app",            "VS Code"),
        ("Cursor.app",                        "Cursor"),
    ]

    /// If `comm` (full executable path) and `name` (basename) identify an IDE
    /// extension-host process — Electron's "Helper (Plugin)" variant launched
    /// from a known IDE bundle — returns the friendly label (e.g. "VS Code").
    /// Uses the full path to avoid false positives from unrelated apps whose
    /// basename happens to end with "Helper (Plugin)".
    private static func extensionHostLabel(comm: String, name: String) -> String? {
        guard name.hasSuffix("Helper (Plugin)") else { return nil }
        return extensionHosts.first { comm.contains($0.bundle) }?.label
    }

    /// More generic long-running dev jobs (builds, transfers, runtimes). Listed
    /// after the agents.
    private static let toolNeedles = [
        "node", "python", "ruby", "java", "cargo", "make", "ssh", "rsync", "docker",
    ]

    /// All executable names we treat as candidates. Agents first so a match's
    /// position in this array doubles as its menu priority.
    private static let needles = agentNeedles + toolNeedles

    /// Whether `name` is the tool named by `needle`: an exact match, or the
    /// needle as a prefix immediately followed by a digit (so `python3`,
    /// `node18`, `llama2` count) — but NOT a loose substring. Substring matching
    /// was the source of false positives: `rsync` inside `colorsyncd`, `cursor`
    /// inside `CursorUIViewService`, `ssh` inside `ssh-agent`. A *letter* after
    /// the needle means it's a different word, so we reject it.
    private static func isTool(_ name: String, _ needle: String) -> Bool {
        let lower = name.lowercased()
        if lower == needle { return true }
        guard lower.hasPrefix(needle) else { return false }
        return lower[lower.index(lower.startIndex, offsetBy: needle.count)].isNumber
    }

    /// Whether a process basename names any of our tools.
    private static func matches(_ name: String) -> Bool {
        needles.contains { isTool(name, $0) }
    }

    /// Whether the process with `pid` is still alive. `kill(_, 0)` sends no
    /// signal; it returns 0 if the pid exists, or -1 with `ESRCH` if it's gone.
    /// `EPERM` means it exists but we may not signal it — still "alive".
    static func isAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Candidate processes whose command name matches one of `needles`, deduped
    /// by name (lowest pid kept, so the menu shows one "node"/"python" row).
    /// Ordered with AI coding agents first (then generic dev tools), and
    /// alphabetically by name within each group.
    static func candidates() -> [Candidate] {
        guard let out = run(["/bin/ps", "-axo", "pid=,comm="]) else { return [] }

        var all: [Candidate] = []
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sp = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[..<sp]),
                  pid != getpid() else { continue }
            // `comm` is the full executable path; take the basename.
            let comm = String(trimmed[trimmed.index(after: sp)...])
                .trimmingCharacters(in: .whitespaces)
            let name = (comm as NSString).lastPathComponent
            if let label = extensionHostLabel(comm: comm, name: name) {
                // Extension hosts run agent workloads (Claude Code, Copilot, etc.)
                // but can't be matched by basename alone — use a friendly label.
                all.append(Candidate(pid: pid, name: "\(label) Extension Host"))
            } else {
                guard matches(name) else { continue }
                all.append(Candidate(pid: pid, name: name))
            }
        }

        // Dedupe case-insensitively (so `Codex` and `codex` collapse to one
        // row) keeping the lowest pid.
        var byName: [String: Candidate] = [:]
        for c in all {
            let key = c.name.lowercased()
            if let existing = byName[key], existing.pid <= c.pid { continue }
            byName[key] = c
        }
        // Sort by needle rank (agents before tools), then name, then pid.
        return byName.values.sorted {
            let r0 = rank($0.name), r1 = rank($1.name)
            if r0 != r1 { return r0 < r1 }
            return $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name
        }
    }

    /// The index of the first `needles` entry this name matches; lower sorts
    /// first. Extension-host display names (e.g. "VS Code Extension Host") sort
    /// in the agent tier, right after "claude". Unmatched names sort last.
    private static func rank(_ name: String) -> Int {
        if name.hasSuffix("Extension Host") { return 1 }
        return needles.firstIndex { isTool(name, $0) } ?? needles.count
    }

    /// Run a command and return its stdout, or nil if it couldn't launch.
    private static func run(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
