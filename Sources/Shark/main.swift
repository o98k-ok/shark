import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
// Menu-bar agent: no Dock tile, no main menu.
application.setActivationPolicy(.accessory)
application.run()
