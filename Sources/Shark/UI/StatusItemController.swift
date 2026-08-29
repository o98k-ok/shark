import AppKit

/// The menu-bar control surface: toggle, split commands and the light settings.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panelController: PanelController
    private let menu = NSMenu()
    private lazy var hotkeyRecorder = HotkeyRecorderPanel()

    private let fontSizes: [CGFloat] = [11, 12, 13, 14, 16, 18, 20, 24]
    private let opacities: [CGFloat] = [0.7, 0.8, 0.9, 1.0]
    private let heightRatios: [CGFloat] = [0.3, 0.4, 0.5, 0.6]

    init(panelController: PanelController) {
        self.panelController = panelController
        super.init()

        if let image = NSImage(named: "MenuBar") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "Shark"
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "chevron.left.forwardslash.chevron.right",
                accessibilityDescription: "Shark"
            )
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        if !HotkeyController.shared.isRegistered {
            let warning = item(
                "⚠︎ Hotkey unavailable — in use by another app",
                #selector(editShortcut),
                value: ShortcutTarget.globalToggle.id
            )
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        menu.addItem(item(labelled(.globalToggle), #selector(toggle)))
        menu.addItem(.separator())

        let split = item(labelled(.pane(.split)), #selector(splitPane))
        split.isEnabled = panelController.session.canSplit
        menu.addItem(split)

        let close = item(labelled(.pane(.closePane)), #selector(closePane))
        close.isEnabled = panelController.session.isSplit
        menu.addItem(close)

        let focus = item(labelled(.pane(.focusOther)), #selector(focusOtherPane))
        focus.isEnabled = panelController.session.isSplit
        menu.addItem(focus)

        let clear = item(labelled(.pane(.clear)), #selector(clearPane))
        clear.isEnabled = panelController.session.hasPanes
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(submenu("Appearance", appearanceMenu()))
        menu.addItem(submenu("Panel Height", heightMenu()))
        menu.addItem(submenu("Window Level", levelMenu()))
        menu.addItem(submenu("Shortcuts", shortcutsMenu()))

        menu.addItem(.separator())
        menu.addItem(toggleItem("Launch at Login", isOn: LaunchAtLogin.isEnabled, action: #selector(toggleLaunchAtLogin)))
        menu.addItem(toggleItem("Hide on Deactivate", isOn: settings.hideOnDeactivate, action: #selector(toggleHideOnDeactivate)))
        menu.addItem(toggleItem("Copy on Select", isOn: settings.copyOnSelect, action: #selector(toggleCopyOnSelect)))
        menu.addItem(toggleItem("Follow Mouse Screen", isOn: settings.followMouseScreen, action: #selector(toggleFollowMouseScreen)))

        menu.addItem(.separator())
        menu.addItem(item("Quit Shark", #selector(quit), key: "q"))
    }

    private func appearanceMenu() -> NSMenu {
        let settings = AppSettings.shared
        let root = NSMenu()

        let fonts = NSMenu()
        for family in monospacedFamilies {
            let entry = item(family, #selector(selectFont), value: family)
            entry.state = (family == settings.fontName) ? .on : .off
            fonts.addItem(entry)
        }
        root.addItem(submenu("Font", fonts))

        let sizes = NSMenu()
        for size in fontSizes {
            let entry = item("\(Int(size))", #selector(selectFontSize), value: size)
            entry.state = (abs(size - settings.fontSize) < 0.01) ? .on : .off
            sizes.addItem(entry)
        }
        sizes.addItem(.separator())
        sizes.addItem(item("Increase", #selector(increaseFontSize), key: "+"))
        sizes.addItem(item("Decrease", #selector(decreaseFontSize), key: "-"))
        root.addItem(submenu("Font Size", sizes))

        let themes = NSMenu()
        for theme in ThemeCatalog.all {
            let entry = item(theme.name, #selector(selectTheme), value: theme.id)
            entry.state = (theme.id == settings.themeID) ? .on : .off
            themes.addItem(entry)
        }
        root.addItem(submenu("Theme", themes))

        let opacityMenu = NSMenu()
        for value in opacities {
            let entry = item("\(Int(value * 100))%", #selector(selectOpacity), value: value)
            entry.state = (abs(value - settings.opacity) < 0.01) ? .on : .off
            opacityMenu.addItem(entry)
        }
        root.addItem(submenu("Opacity", opacityMenu))

        return root
    }

    private func shortcutsMenu() -> NSMenu {
        let menu = NSMenu()
        for target in ShortcutTarget.all {
            menu.addItem(item(labelled(target) + "…", #selector(editShortcut), value: target.id))
        }
        menu.addItem(.separator())
        menu.addItem(item("Reset to Defaults", #selector(resetShortcuts)))
        return menu
    }

    private func labelled(_ target: ShortcutTarget) -> String {
        "\(target.title)  (\(KeyCodeFormatter.describe(AppSettings.shared.combo(for: target))))"
    }

    private func heightMenu() -> NSMenu {
        let menu = NSMenu()
        for ratio in heightRatios {
            let entry = item("\(Int(ratio * 100))%", #selector(selectHeight), value: ratio)
            entry.state = (abs(ratio - AppSettings.shared.heightRatio) < 0.01) ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    private func levelMenu() -> NSMenu {
        let menu = NSMenu()
        for level in PanelLevel.allCases {
            let entry = item(level.title, #selector(selectLevel), value: level.rawValue)
            entry.state = (level == AppSettings.shared.panelLevel) ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    private var monospacedFamilies: [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies
            .filter { manager.fontNamed($0, hasTraits: .fixedPitchFontMask) }
            .sorted()
    }

    // MARK: - Item helpers

    private func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        value: Any? = nil
    ) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        entry.representedObject = value
        return entry
    }

    private func toggleItem(_ title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let entry = item(title, action)
        entry.state = isOn ? .on : .off
        return entry
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }

    // MARK: - Actions

    @objc private func toggle() { panelController.toggle() }
    @objc private func splitPane() { panelController.session.splitLeftRight() }
    @objc private func closePane() { panelController.session.closeFocusedPane() }
    @objc private func focusOtherPane() { panelController.session.focusOtherPane() }
    @objc private func clearPane() { panelController.session.clearFocusedPane() }

    @objc private func selectFont(_ sender: NSMenuItem) {
        guard let family = sender.representedObject as? String else { return }
        AppSettings.shared.fontName = family
    }

    @objc private func selectFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? CGFloat else { return }
        AppSettings.shared.fontSize = size
    }

    @objc private func increaseFontSize() { AppSettings.shared.fontSize += 1 }
    @objc private func decreaseFontSize() { AppSettings.shared.fontSize -= 1 }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppSettings.shared.themeID = id
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? CGFloat else { return }
        AppSettings.shared.opacity = value
    }

    @objc private func selectHeight(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? CGFloat else { return }
        AppSettings.shared.heightRatio = value
    }

    @objc private func selectLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = PanelLevel(rawValue: raw) else { return }
        AppSettings.shared.panelLevel = level
    }

    @objc private func editShortcut(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let target = ShortcutTarget.all.first(where: { $0.id == id }) else { return }

        panelController.suppressAutoHide = true
        hotkeyRecorder.present(target: target) { [weak self] in
            self?.panelController.resumeAfterAuxiliaryUI()
        }
    }

    @objc private func resetShortcuts() {
        AppSettings.shared.resetShortcuts()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        } catch {
            presentError(error, context: "Could not change the login item.")
        }
    }

    @objc private func toggleHideOnDeactivate() {
        AppSettings.shared.hideOnDeactivate.toggle()
    }

    @objc private func toggleCopyOnSelect() {
        AppSettings.shared.copyOnSelect.toggle()
    }

    @objc private func toggleFollowMouseScreen() {
        AppSettings.shared.followMouseScreen.toggle()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func presentError(_ error: Error, context: String) {
        let alert = NSAlert()
        alert.messageText = context
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        panelController.suppressAutoHide = true
    }

    func menuDidClose(_ menu: NSMenu) {
        // The chosen item's action runs after dismissal; resume once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.hotkeyRecorder.isPresented else { return }
            self.panelController.resumeAfterAuxiliaryUI()
        }
    }
}
