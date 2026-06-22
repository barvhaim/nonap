import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let controller = NoNapController()
    private var statusItem: NSStatusItem!

    // Items whose state/enablement changes at runtime.
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var modeItems: [KeepAwakeMode: NSMenuItem] = [:]
    private var loginItem: NSMenuItem!

    /// The "Keep awake until ▸" submenu, repopulated on open with the current
    /// list of running candidate processes.
    private var watchMenu: NSMenu!

    /// A process the user can choose to watch (carried via `representedObject`).
    private struct WatchTarget { let pid: pid_t; let name: String }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard. macOS only blocks a second launch of the *same*
        // bundle on disk; multiple copies (a mounted DMG, a stray build, a Trash
        // copy) share our bundle id and would each spawn their own menu-bar icon.
        // If another NoNap is already running, bow out so the user sees one icon.
        if hasOtherRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()

        controller.onStateChange = { [weak self] in
            self?.refreshUI()
        }
        controller.onAutoStop = { finished in
            let body = finished.map { "\($0) finished — your Mac can sleep now." }
                ?? "Your timer ended — your Mac can sleep now."
            Notifier.post(title: "NoNap stopped", body: body)
        }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    /// True if another process with our bundle identifier is already running.
    /// Compares against `NSRunningApplication` rather than the on-disk path, so
    /// duplicate copies of NoNap.app (DMG, stray build, Trash) all count as the
    /// same app and only the first to launch survives.
    private func hasOtherRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != me.processIdentifier }
    }

    // MARK: - Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // We drive item enablement ourselves in refreshUI().
        menu.autoenablesItems = false

        startItem = menu.addItem(withTitle: "Start NoNap",
                                 action: #selector(startNoNap), keyEquivalent: "")
        startItem.target = self

        stopItem = menu.addItem(withTitle: "Stop NoNap",
                                action: #selector(stopNoNap), keyEquivalent: "")
        stopItem.target = self

        menu.addItem(.separator())

        // "Start for ▸" submenu: presets plus a typed Custom… option.
        let timedItem = menu.addItem(withTitle: "Start for", action: nil, keyEquivalent: "")
        let timedMenu = NSMenu()
        timedMenu.autoenablesItems = false
        for preset in Self.timedPresets {
            let item = timedMenu.addItem(withTitle: preset.label,
                                         action: #selector(startTimedFromItem(_:)),
                                         keyEquivalent: "")
            item.target = self
            item.representedObject = preset.seconds
        }
        timedMenu.addItem(.separator())
        let customItem = timedMenu.addItem(withTitle: "Custom…",
                                           action: #selector(startCustom),
                                           keyEquivalent: "")
        customItem.target = self
        timedItem.submenu = timedMenu

        // "Keep awake until ▸" submenu: running candidate processes plus a
        // typed Watch PID… option. Rebuilt on open (see menuNeedsUpdate).
        let watchItem = menu.addItem(withTitle: "Keep awake until", action: nil, keyEquivalent: "")
        let watchMenu = NSMenu()
        watchMenu.autoenablesItems = false
        watchMenu.delegate = self
        watchItem.submenu = watchMenu
        self.watchMenu = watchMenu

        menu.addItem(.separator())

        let modeItem = menu.addItem(withTitle: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in KeepAwakeMode.allCases {
            let item = modeMenu.addItem(withTitle: mode.title,
                                        action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeItems[mode] = item
        }
        modeItem.submenu = modeMenu

        menu.addItem(.separator())

        loginItem = menu.addItem(withTitle: "Launch at login",
                                 action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self

        let quitItem = menu.addItem(withTitle: "Quit",
                                    action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        return menu
    }

    /// Timed-session presets shown in the "Start for ▸" submenu.
    private static let timedPresets: [(label: String, seconds: TimeInterval)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("45 minutes", 45 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 120 * 60),
        ("4 hours", 240 * 60),
        ("8 hours", 480 * 60),
    ]

    // MARK: - Actions

    @objc private func startNoNap() { controller.start() }
    @objc private func stopNoNap() { controller.stop() }

    @objc private func startTimedFromItem(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        Notifier.requestAuthorizationIfNeeded()
        controller.startTimed(seconds)
    }

    /// Prompt for a free-form duration (e.g. "90m", "2h30m") and start a timer.
    @objc private func startCustom() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Keep awake for…"
        alert.informativeText = "Enter a duration, e.g. 90m, 2h, or 1h30m."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "90m"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let seconds = Self.parseDuration(field.stringValue), seconds > 0 else {
            NSSound.beep()
            return
        }
        Notifier.requestAuthorizationIfNeeded()
        controller.startTimed(seconds)
    }

    // MARK: - Keep-awake-until-a-process-exits

    /// Repopulate the "Keep awake until ▸" submenu with the processes running
    /// right now, each time it's opened (a build-time snapshot would be stale).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === watchMenu else { return }
        menu.removeAllItems()

        for candidate in ProcessWatch.candidates() {
            let item = menu.addItem(withTitle: "\(candidate.name) (\(candidate.pid))",
                                    action: #selector(startWatchFromItem(_:)),
                                    keyEquivalent: "")
            item.target = self
            item.representedObject = WatchTarget(pid: candidate.pid, name: candidate.name)
            item.isEnabled = !controller.isActive
        }
        if menu.numberOfItems == 0 {
            let none = menu.addItem(withTitle: "No candidate processes",
                                    action: nil, keyEquivalent: "")
            none.isEnabled = false
        }

        menu.addItem(.separator())
        let custom = menu.addItem(withTitle: "Watch PID…",
                                  action: #selector(watchCustomPID), keyEquivalent: "")
        custom.target = self
        custom.isEnabled = !controller.isActive
    }

    @objc private func startWatchFromItem(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? WatchTarget else { return }
        Notifier.requestAuthorizationIfNeeded()
        if !controller.startWatching(pid: target.pid, label: target.name) {
            NSSound.beep()   // it exited between listing and selection
        }
    }

    /// Prompt for a PID to watch. Reuses the startCustom() NSAlert pattern.
    @objc private func watchCustomPID() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Keep awake until a process exits"
        alert.informativeText = "Enter the PID of the process to watch."
        alert.addButton(withTitle: "Watch")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "12345"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let pid = pid_t(text), pid > 0, ProcessWatch.isAlive(pid) else {
            NSSound.beep()
            return
        }
        Notifier.requestAuthorizationIfNeeded()
        controller.startWatching(pid: pid, label: "PID \(pid)")
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = KeepAwakeMode(rawValue: raw) else { return }
        controller.mode = mode
    }

    @objc private func toggleLaunchAtLogin() {
        try? LoginItem.set(!LoginItem.isEnabled)
        refreshUI()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    /// Parse durations like "90m", "2h", "2h30m", "1h 30m", or a bare number
    /// (interpreted as minutes). Returns seconds, or nil if nothing parsed.
    static func parseDuration(_ input: String) -> TimeInterval? {
        let s = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Bare number → minutes.
        if let bare = Double(s) { return bare * 60 }

        var total: TimeInterval = 0
        var matched = false
        var number = ""
        for ch in s {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else if ch == "h" || ch == "m" {
                guard let value = Double(number) else { return nil }
                total += value * (ch == "h" ? 3600 : 60)
                number = ""
                matched = true
            } else if ch == " " {
                continue
            } else {
                return nil   // unexpected character
            }
        }
        // Trailing digits with no unit are invalid in unit mode.
        if !number.isEmpty { return nil }
        return matched ? total : nil
    }

    // MARK: - UI refresh

    private func refreshUI() {
        if let button = statusItem.button {
            button.image = statusIcon(active: controller.isActive)
            button.imagePosition = .imageLeading
            // Next to the icon: a countdown during a timed session, or the
            // watched process's name while waiting on it; nothing otherwise.
            if controller.isActive, let remaining = controller.remainingTime() {
                button.title = " " + formatted(remaining)
            } else if controller.isActive, let name = controller.watchedName {
                button.title = " " + name
            } else {
                button.title = ""
            }
            button.toolTip = controller.isActive ? "NoNap: Active" : "NoNap: Off"
        }

        for (mode, item) in modeItems {
            item.state = (mode == controller.mode) ? .on : .off
        }

        startItem.isEnabled = !controller.isActive
        stopItem.isEnabled = controller.isActive

        loginItem.state = LoginItem.isEnabled ? .on : .off
        loginItem.isEnabled = LoginItem.isSupported
    }

    /// A single composited icon: the coffee cup (tinted to the menu-bar text
    /// color so it's always visible) plus a status dot — solid green when
    /// active, a faint hollow ring when off. Drawn as a non-template image so
    /// the green dot keeps its color.
    private func statusIcon(active: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let cupBase = NSImage(systemSymbolName: "cup.and.saucer.fill",
                              accessibilityDescription: "NoNap")?
            .withSymbolConfiguration(config)

        let image = NSImage(size: size, flipped: false) { _ in
            // Tint the cup to the standard menu-bar label color (adapts to
            // light/dark appearance) by drawing it as a template-style fill.
            if let cup = cupBase {
                let cupSize = cup.size
                let rect = NSRect(x: 1,
                                  y: (size.height - cupSize.height) / 2,
                                  width: cupSize.width,
                                  height: cupSize.height)
                NSColor.labelColor.set()
                cup.draw(in: rect)
                rect.fill(using: .sourceAtop)   // recolor the opaque cup pixels
            }

            // Status dot in the top-right corner.
            let d: CGFloat = 7
            let dotRect = NSRect(x: size.width - d - 0.5,
                                 y: size.height - d - 0.5,
                                 width: d, height: d)
            let dot = NSBezierPath(ovalIn: dotRect)
            if active {
                NSColor.systemGreen.setFill()
                dot.fill()
            } else {
                NSColor.tertiaryLabelColor.setStroke()
                dot.lineWidth = 1.2
                dot.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
