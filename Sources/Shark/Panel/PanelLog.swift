import os

/// A menu-bar agent has no console, so show/hide transitions are logged where
/// `log show --predicate 'subsystem == "com.o98k.shark"'` can see them. They are
/// logged at notice level on purpose: info level is memory-only, and the bugs
/// worth chasing here are intermittent ones reported hours after the fact.
enum PanelLog {
    static let logger = Logger(subsystem: "com.o98k.shark", category: "panel")
}
