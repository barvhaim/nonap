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
        releaseAssertions()
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
    }

    private func releaseAssertions() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
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
