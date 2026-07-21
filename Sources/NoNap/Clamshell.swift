import Foundation
import IOKit.ps

/// "Keep awake with the lid closed" via `pmset -a disablesleep`.
///
/// `disablesleep` needs root and — unlike the IOKit assertions in
/// `NoNapController` (auto-released when our process dies) — is system-wide and
/// sticky: it survives a crash and must be explicitly set back to `0`.
///
/// A one-time setup (`installSudoers`) whitelists exactly the two pmset commands
/// for passwordless sudo in `/etc/sudoers.d/nonap`. After that, both enabling and
/// disabling run silently via `sudo -n` — no password prompt, so unattended
/// auto-stop (a timer or watched process ending) can never block on a dialog.
///
/// Like `LoginItem` / `Notifier`, this needs a real `.app` bundle; under
/// `swift run` the calls degrade to no-ops instead of crashing.
enum Clamshell {

    enum Result {
        case ok
        /// The sudoers entry isn't installed yet — the caller should offer setup.
        case notSetUp
        /// User dismissed the setup password dialog (AppleScript error -128).
        case cancelled
        case failed(String)
    }

    /// AppleScript's "User canceled" error number.
    private static let userCancelledErr = -128

    private static let sudoersPath = "/etc/sudoers.d/nonap"

    private static var available: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// The exact commands we whitelist. Fully qualified, no wildcards.
    private static var pmsetOn: String  { "/usr/bin/pmset -a disablesleep 1" }
    private static var pmsetOff: String { "/usr/bin/pmset -a disablesleep 0" }

    // MARK: - Runtime toggle (silent, via sudo -n)

    /// Set `disablesleep` on/off silently. A no-op returning `.ok` when
    /// unsupported (`swift run`). Returns `.notSetUp` if the sudoers entry is
    /// missing (so a `sudo -n` would otherwise want a password).
    static func setDisableSleep(_ on: Bool) -> Result {
        guard available else { return .ok }
        let (status, _) = run("/usr/bin/sudo",
                              ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"])
        switch status {
        case 0:   return .ok
        case nil: return .failed("Could not run sudo.")
        default:  return .notSetUp   // -n failed: almost always "password required"
        }
    }

    /// Whether passwordless sudo for our pmset commands actually works. Verifies
    /// with `sudo -n -l <cmd>` (lists whether the command is allowed without
    /// running it or prompting), so it's correct even if the file exists for a
    /// different user or is malformed.
    static func isSetUp() -> Bool {
        guard available else { return false }
        guard FileManager.default.fileExists(atPath: sudoersPath) else { return false }
        let (status, _) = run("/usr/bin/sudo",
                              ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        return status == 0
    }

    // MARK: - One-time setup (single admin prompt)

    /// Install the sudoers entry via one admin prompt. Writes a temp file,
    /// validates it with `visudo -cf`, then atomically installs it 0440 root:wheel.
    /// Never edits the live sudoers file directly.
    static func installSudoers() -> Result {
        guard available else { return .ok }

        let user = NSUserName()
        let line = "\(user) ALL=(root) NOPASSWD: \(pmsetOn), \(pmsetOff)\n"

        let tmp = NSTemporaryDirectory() + "nonap-sudoers-\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try line.write(toFile: tmp, atomically: true, encoding: .utf8)
        } catch {
            return .failed("Could not stage the sudoers file.")
        }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Validate, then install — as one privileged shell step.
        let shell = "/usr/sbin/visudo -cf '\(tmp)' && "
            + "/usr/bin/install -m 0440 -o root -g wheel '\(tmp)' '\(sudoersPath)'"
        let source = "do shell script \"\(shell)\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            return .failed("Could not build the setup script.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == userCancelledErr { return .cancelled }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                ?? "Setup failed (error \(code))."
            return .failed(message)
        }
        return .ok
    }

    /// Run a command, returning its exit status (nil if it couldn't launch).
    private static func run(_ path: String, _ args: [String]) -> (Int32?, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (nil, "")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - Power source

    static func isOnAC() -> Bool {
        guard let type = providingPowerSourceType() else { return false }
        return type == kIOPMACPowerKey
    }

    /// Battery charge as a 0…1 fraction, or nil if there's no battery (desktop
    /// Mac) or it can't be read.
    static func batteryFraction() -> Double? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
                as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Double,
                  let max = desc[kIOPSMaxCapacityKey] as? Double,
                  max > 0
            else { continue }
            return current / max
        }
        return nil
    }

    private static func providingPowerSourceType() -> String? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }
        return IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
    }
}
