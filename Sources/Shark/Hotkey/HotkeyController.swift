import AppKit
import Carbon.HIToolbox

/// Registers the global toggle shortcut through Carbon, which — unlike a CGEvent tap —
/// works without Accessibility permission.
final class HotkeyController {
    static let shared = HotkeyController()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isHandlerInstalled = false

    /// Set to false when registration fails, so the UI can surface a conflict.
    private(set) var isRegistered = false

    var onTrigger: (() -> Void)?

    private let signature: OSType = 0x53_48_52_4B // 'SHRK'

    private init() {}

    func start() {
        installHandlerIfNeeded()
        register(AppSettings.shared.hotkey)

        NotificationCenter.default.addObserver(
            forName: .sharkHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.register(AppSettings.shared.hotkey)
        }
    }

    @discardableResult
    func register(_ combo: HotkeyCombo) -> Bool {
        unregister()
        guard combo.keyCode != 0 || combo.modifiers != 0 else { return false }

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        isRegistered = (status == noErr && ref != nil)
        hotKeyRef = ref
        return isRegistered
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        isRegistered = false
    }

    private func installHandlerIfNeeded() {
        guard !isHandlerInstalled else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            return controller.handle(event: event)
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        isHandlerInstalled = true
    }

    private func handle(event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        return noErr
    }
}
