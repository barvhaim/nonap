import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let controller = NoNapController()
    private var statusItem: NSStatusItem!

    // Items whose state/enablement changes at runtime.
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var modeItems: [KeepAwakeMode: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()

        controller.onStateChange = { [weak self] in
            self?.refreshUI()
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

        let thirtyMin = menu.addItem(withTitle: "Start for 30 minutes",
                                     action: #selector(startTimed30), keyEquivalent: "")
        thirtyMin.target = self
        let oneHour = menu.addItem(withTitle: "Start for 1 hour",
                                   action: #selector(startTimed60), keyEquivalent: "")
        oneHour.target = self
        let twoHours = menu.addItem(withTitle: "Start for 2 hours",
                                    action: #selector(startTimed120), keyEquivalent: "")
        twoHours.target = self

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

        let quitItem = menu.addItem(withTitle: "Quit",
                                    action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        return menu
    }

    // MARK: - Actions

    @objc private func startNoNap() { controller.start() }
    @objc private func stopNoNap() { controller.stop() }
    @objc private func startTimed30() { controller.startTimed(30 * 60) }
    @objc private func startTimed60() { controller.startTimed(60 * 60) }
    @objc private func startTimed120() { controller.startTimed(120 * 60) }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = KeepAwakeMode(rawValue: raw) else { return }
        controller.mode = mode
    }

    @objc private func quit() { NSApp.terminate(nil) }

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
