import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = NoNapController()
    private var statusItem: NSStatusItem!

    // Items whose state/enablement changes at runtime.
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var modeItems: [KeepAwakeMode: NSMenuItem] = [:]
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()

        controller.onStateChange = { [weak self] in
            self?.refreshUI()
        }
        controller.onTimedExpiry = {
            Notifier.post(title: "NoNap stopped",
                          body: "Your timer ended — your Mac can sleep now.")
        }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
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
            // Show the remaining time next to the icon only during a timed session.
            if controller.isActive, let remaining = controller.remainingTime() {
                button.title = " " + formatted(remaining)
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
