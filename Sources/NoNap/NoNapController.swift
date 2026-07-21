import Foundation
import IOKit.pwr_mgt

/// Owns the keep-awake state: the IOKit power assertions, the selected mode,
/// and any running auto-stop timer. All access is on the main actor since the
/// UI observes it directly.
@MainActor
final class NoNapController {

    /// Called after any state change (start/stop/mode-switch/countdown tick)
    /// so the UI can refresh in one place.
    var onStateChange: (() -> Void)?

    /// Called when a session ends on its own — a timer elapsed or a watched
    /// process exited — never on a manual Stop, so the UI can notify the user.
    /// The argument names what finished (a watched process), or nil for a
    /// plain timer.
    var onAutoStop: ((_ finished: String?) -> Void)?

    private static let modeDefaultsKey = "keepAwakeMode"
    private static let lidClosedDefaultsKey = "keepAwakeLidClosed"

    /// Currently-held assertion ids (one for `.system`/`.display`, two for `.both`).
    private var assertionIDs: [IOPMAssertionID] = []

    /// One-shot timer that stops a timed session, plus a repeating ticker that
    /// drives the live countdown in the menu-bar title.
    private var stopTimer: DispatchSourceTimer?
    private var tickTimer: DispatchSourceTimer?

    /// Repeating timer that polls a watched pid; nil unless watching a process.
    private var watchTimer: DispatchSourceTimer?

    /// When a timed session ends; nil for an indefinite session.
    private(set) var endDate: Date?

    /// Short name of the process being watched, shown in the menu-bar title;
    /// nil unless a process-watch session is active.
    private(set) var watchedName: String?

    /// User preference: also prevent lid-close (clamshell) sleep while a session
    /// is active. Persisted, like `mode`. Applying it runs `pmset disablesleep`
    /// (see `Clamshell`); that only happens while `isActive`, never on its own.
    private(set) var lidClosedPreference = false

    /// Whether we currently hold `pmset disablesleep 1`. Tracks the applied
    /// state so we release exactly what we set.
    private var lidClosedApplied = false

    /// On battery, refuse to keep awake with the lid closed below this fraction,
    /// to avoid overheating a closed MacBook.
    static let lowBatteryThreshold = 0.20

    var isActive: Bool { !assertionIDs.isEmpty }

    /// The selected mode, persisted to `UserDefaults`. Changing it while active
    /// re-applies the assertions immediately.
    var mode: KeepAwakeMode {
        didSet {
            guard mode != oldValue else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            applyModeChange()
            onStateChange?()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.modeDefaultsKey)
        self.mode = raw.flatMap(KeepAwakeMode.init(rawValue:)) ?? .system
        self.lidClosedPreference = UserDefaults.standard.bool(forKey: Self.lidClosedDefaultsKey)
    }

    // MARK: - Public actions

    /// Begin keeping the Mac awake indefinitely with the current mode.
    func start() {
        cancelTimers()
        endDate = nil
        createAssertions()
        onStateChange?()
    }

    /// Begin keeping the Mac awake for `seconds`, then auto-stop.
    func startTimed(_ seconds: TimeInterval) {
        cancelTimers()
        createAssertions()
        endDate = Date().addingTimeInterval(seconds)
        scheduleStop(after: seconds)
        scheduleTick()
        onStateChange?()
    }

    /// Begin keeping the Mac awake until the process `pid` exits, then auto-stop.
    /// `label` is the process's short name, shown in the menu bar and the
    /// end-of-session notification. Returns false (and does nothing) if the pid
    /// is already gone, so the caller can surface that.
    @discardableResult
    func startWatching(pid: pid_t, label: String) -> Bool {
        guard ProcessWatch.isAlive(pid) else { return false }
        cancelTimers()
        endDate = nil
        watchedName = label
        createAssertions()
        scheduleWatch(pid: pid)
        onStateChange?()
        return true
    }

    /// Why a session ended — affects whether/how the user is notified.
    /// `.expired` carries an optional label naming what finished (a watched
    /// process); nil means a plain timer elapsed.
    private enum StopReason {
        case manual
        case expired(finished: String?)
    }

    /// Stop keeping awake and release all assertions (user-initiated).
    func stop() {
        stop(reason: .manual)
    }

    private func stop(reason: StopReason) {
        let wasAuto = endDate != nil || watchedName != nil
        cancelTimers()
        endDate = nil
        watchedName = nil
        releaseAssertions()   // also clears disablesleep if we set it
        onStateChange?()
        if case .expired(let finished) = reason, wasAuto {
            onAutoStop?(finished)
        }
    }

    /// Remaining time for a timed session, or nil if indefinite/inactive.
    func remainingTime() -> TimeInterval? {
        guard let endDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    // MARK: - Keep awake with the lid closed (pmset disablesleep)

    enum LidResult {
        case ok
        /// Enabling needs the one-time sudoers setup first.
        case notSetUp
        /// Refused: on battery below `lowBatteryThreshold`.
        case batteryTooLow
        case failed(String)
    }

    /// Set the lid-closed preference. Enabling requires the one-time setup
    /// (`Clamshell.isSetUp()`); without it, returns `.notSetUp` and changes
    /// nothing so the caller can offer setup. If a session is active, the pmset
    /// change is applied immediately — silently, since setup grants passwordless
    /// sudo. While inactive it's just remembered for the next session.
    @discardableResult
    func setLidClosedPreference(_ on: Bool) -> LidResult {
        guard on != lidClosedPreference else { return .ok }

        if on {
            guard Clamshell.isSetUp() else { return .notSetUp }
            if isActive, isBatteryTooLow() { return .batteryTooLow }
            if isActive {
                switch Clamshell.setDisableSleep(true) {
                case .ok:            lidClosedApplied = true
                case .notSetUp:      return .notSetUp
                case .cancelled:     return .ok   // shouldn't occur silently
                case .failed(let m): return .failed(m)
                }
            }
        } else {
            clearLidClosed()
        }

        lidClosedPreference = on
        UserDefaults.standard.set(on, forKey: Self.lidClosedDefaultsKey)
        onStateChange?()
        return .ok
    }

    /// Best-effort restore of `disablesleep 0` on termination. Not guaranteed on
    /// crash/force-quit — the documented limitation.
    func shutdownCleanup() {
        clearLidClosed()
    }

    private func isBatteryTooLow() -> Bool {
        !Clamshell.isOnAC()
            && (Clamshell.batteryFraction() ?? 1) < Self.lowBatteryThreshold
    }

    /// Apply `disablesleep 1` when starting a session, if the preference is on
    /// and battery allows. Silent (passwordless sudo); failure leaves it unapplied.
    private func applyLidClosed() {
        guard lidClosedPreference, !lidClosedApplied, !isBatteryTooLow() else { return }
        if case .ok = Clamshell.setDisableSleep(true) {
            lidClosedApplied = true
        }
    }

    /// Release `disablesleep` if we're holding it. Idempotent.
    private func clearLidClosed() {
        guard lidClosedApplied else { return }
        _ = Clamshell.setDisableSleep(false)
        lidClosedApplied = false
    }

    // MARK: - Assertions

    private func createAssertions() {
        releaseAssertions()
        for type in mode.assertionTypes {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NoNap keeping Mac awake" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionIDs.append(id)
            }
        }
        applyLidClosed()
    }

    private func releaseAssertions() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
        clearLidClosed()
    }

    /// Re-apply assertions for the current mode if a session is active.
    private func applyModeChange() {
        guard isActive else { return }
        createAssertions()
    }

    // MARK: - Timers

    private func scheduleStop(after seconds: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            self?.stop(reason: .expired(finished: nil))
        }
        timer.resume()
        stopTimer = timer
    }

    /// Poll the watched pid; when it's gone, auto-stop via the same `.expired`
    /// path a timer uses (so the end-of-session notification fires).
    /// Note: pids can be reused, so if the watched process dies and the OS
    /// reassigns its number within the poll window we'd keep watching the new
    /// occupant — an accepted limitation for a 5s poll on a tiny tool.
    private func scheduleWatch(pid: pid_t) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !ProcessWatch.isAlive(pid) {
                self.stop(reason: .expired(finished: self.watchedName))
            }
        }
        timer.resume()
        watchTimer = timer
    }

    private func scheduleTick() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.onStateChange?()
        }
        timer.resume()
        tickTimer = timer
    }

    private func cancelTimers() {
        stopTimer?.cancel()
        stopTimer = nil
        tickTimer?.cancel()
        tickTimer = nil
        watchTimer?.cancel()
        watchTimer = nil
    }
}
