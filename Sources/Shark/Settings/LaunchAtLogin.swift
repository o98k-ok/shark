import ServiceManagement

/// Login-item registration. Requires a real `.app` bundle; running the bare
/// SwiftPM binary throws, which the menu surfaces instead of silently ignoring.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
