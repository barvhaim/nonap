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

    private static let modeDefaultsKey = "keepAwakeMode"

    /// Currently-held assertion ids (one for `.system`/`.display`, two for `.both`).
    private var assertionIDs: [IOPMAssertionID] = []

    /// One-shot timer that stops a timed session, plus a repeating ticker that
    /// drives the live countdown in the menu-bar title.
    private var stopTimer: DispatchSourceTimer?
    private var tickTimer: DispatchSourceTimer?

    /// When a timed session ends; nil for an indefinite session.
    private(set) var endDate: Date?

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

    /// Stop keeping awake and release all assertions.
    func stop() {
        cancelTimers()
        endDate = nil
        releaseAssertions()
        onStateChange?()
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
            self?.stop()
        }
        timer.resume()
        stopTimer = timer
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
    }
}
