import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Run as a menu-bar accessory: no Dock icon, no main window.
// (Belt-and-suspenders alongside LSUIElement in the bundled Info.plist.)
app.setActivationPolicy(.accessory)
app.run()
