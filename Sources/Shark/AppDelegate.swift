import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var panelController: PanelController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PanelController()
        panelController = controller
        statusItemController = StatusItemController(panelController: controller)

        HotkeyController.shared.onTrigger = { [weak controller] in controller?.toggle() }
        HotkeyController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyController.shared.unregister()
        panelController?.session.terminateAll()
    }
}
