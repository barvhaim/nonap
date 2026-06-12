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

    /// Executable-name substrings that look like long-running agent/dev jobs —
    /// the kinds of process you'd want to outlast (AI coding agents, local
    /// inference, builds, transfers).
    private static let needles = [
        "claude", "cursor", "codex", "node", "python", "ollama", "llama",
        "ruby", "java", "cargo", "make", "ssh", "rsync", "docker",
    ]

    /// Whether the process with `pid` is still alive. `kill(_, 0)` sends no
    /// signal; it returns 0 if the pid exists, or -1 with `ESRCH` if it's gone.
    /// `EPERM` means it exists but we may not signal it — still "alive".
    static func isAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Candidate processes whose command name matches one of `needles`, deduped
    /// by name (lowest pid kept, so the menu shows one "node"/"python" row) and
    /// sorted by name then pid.
    static func candidates() -> [Candidate] {
        guard let out = run(["/bin/ps", "-axo", "pid=,comm="]) else { return [] }

        var all: [Candidate] = []
        for line in out.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sp = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[..<sp]) else { continue }
            // `comm` is the full executable path; take the basename.
            let comm = String(trimmed[trimmed.index(after: sp)...])
                .trimmingCharacters(in: .whitespaces)
            let name = (comm as NSString).lastPathComponent
            let lower = name.lowercased()
            guard pid != getpid(), needles.contains(where: lower.contains) else { continue }
            all.append(Candidate(pid: pid, name: name))
        }

        // Dedupe by name keeping the lowest pid, then sort name → pid.
        var byName: [String: Candidate] = [:]
        for c in all {
            if let existing = byName[c.name], existing.pid <= c.pid { continue }
            byName[c.name] = c
        }
        return byName.values.sorted {
            $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name
        }
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
