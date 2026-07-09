import AppKit

// Entry point. Sleepy runs as a menu-bar (accessory) app with no Dock icon.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
