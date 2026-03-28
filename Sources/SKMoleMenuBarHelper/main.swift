import AppKit

let app = NSApplication.shared
let delegate = MenuBarHelperAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
