import AppKit

enum ScreenLocator {
    static func targetScreen() -> NSScreen {
        if AppSettings.shared.followMouseScreen {
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    /// Frame for the panel when fully dropped down from the top of `screen`.
    static func visibleFrame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let height = (area.height * AppSettings.shared.heightRatio).rounded()
        return NSRect(x: area.minX, y: area.maxY - height, width: area.width, height: height)
    }

    /// Same size, parked just above the screen edge for the slide-in animation.
    static func hiddenFrame(on screen: NSScreen) -> NSRect {
        var frame = visibleFrame(on: screen)
        frame.origin.y = screen.frame.maxY
        return frame
    }
}
