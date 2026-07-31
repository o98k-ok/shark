import os

/// A menu-bar agent has no console, so show/hide transitions are logged where
/// `log stream --predicate 'subsystem == "com.o98k.shark"'` can see them.
enum PanelLog {
    static let logger = Logger(subsystem: "com.o98k.shark", category: "panel")
}
