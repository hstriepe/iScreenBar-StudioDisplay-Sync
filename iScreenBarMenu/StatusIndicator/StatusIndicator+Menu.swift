import AppKit

extension StatusIndicator {
    // MARK: - Status menu (right-click / Control-click)

    func buildStatusMenu() -> NSMenu {
        refreshControls()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let lampConnected = lamp.isConnected

        menu.addItem(toggleItem(String(localized: "Light"), control: powerSwitch))

        let brightnessMenu = NSMenu()
        brightnessMenu.autoenablesItems = false
        for value in [25, 50, 75, 100] {
            let entry = actionItem("\(value)%", action: #selector(menuBrightnessChanged(_:)), tag: value)
            entry.state = lamp.currentBrightness == value ? .on : .off
            entry.isEnabled = lampConnected
            brightnessMenu.addItem(entry)
        }
        menu.addItem(submenuItem(String(localized: "Brightness"), brightnessMenu))

        let temperatureMenu = NSMenu()
        temperatureMenu.autoenablesItems = false
        temperatureMenu.addItem(toggleItem(String(localized: "Auto Temp"), control: timeTemperatureSwitch))
        temperatureMenu.addItem(.separator())
        for value in [2700, 4000, 5000, 6500] {
            let entry = actionItem("\(value)K", action: #selector(menuTemperatureChanged(_:)), tag: value)
            entry.state = !isTimeTemperatureEnabled && lamp.currentTemperature == value ? .on : .off
            entry.isEnabled = temperatureSlider.isEnabled
            temperatureMenu.addItem(entry)
        }
        menu.addItem(submenuItem(String(localized: "Color Temperature"), temperatureMenu))

        let lampMenu = NSMenu()
        lampMenu.autoenablesItems = false
        for control in [autoLightSwitch, presenceSwitch, videoModeSwitch] {
            lampMenu.addItem(toggleItem(control.title, control: control))
        }
        lampMenu.addItem(.separator())
        for control in [brightnessFollowSwitch, displayBrightnessLockSwitch, powerSyncSwitch] {
            lampMenu.addItem(toggleItem(control.title, control: control))
        }
        let presenceWakeItem = toggleItem(String(localized: "Wake Screen on Presence"), control: presenceWakeSwitch)
        presenceWakeItem.indentationLevel = 1
        lampMenu.addItem(presenceWakeItem)
        menu.addItem(submenuItem(String(localized: "Lamp"), lampMenu))

        updateAmbientControlAvailability()
        menu.addItem(toggleItem(String(localized: "Ambient Rules"), control: ambientEnableSwitch))

        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        if showsDisplaySection {
            addDisplayControls(to: displayMenu)
        } else {
            displayMenu.addItem(toggleItem("Studio Display", control: studioPowerSwitch))
        }
        menu.addItem(submenuItem(String(localized: "Displays"), displayMenu))

        let favoritesMenu = NSMenu()
        favoritesMenu.autoenablesItems = false
        for (index, title) in modeNames().enumerated() {
            let entry = actionItem(title, action: #selector(presetChanged(_:)), tag: index)
            entry.state = title == modeButton.title ? .on : .off
            entry.isEnabled = lampConnected
            favoritesMenu.addItem(entry)
        }
        favoritesMenu.addItem(.separator())
        favoritesMenu.addItem(actionItem(String(localized: "Mode Center…"), action: #selector(showModeCenter)))
        menu.addItem(submenuItem(String(localized: "Favorites"), favoritesMenu))

        menu.addItem(toggleItem(String(localized: "Keep Awake"), control: keepAwakeSwitch))

        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Control Panel…"), action: #selector(openPanelFromMenu)))

        menu.addItem(.separator())
        let login = actionItem(String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(actionItem(String(localized: "Help…"), action: #selector(showHelp)))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit iScreenBar Menu"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func addDisplayControls(to displayMenu: NSMenu) {
        displayMenu.addItem(toggleItem(String(localized: "Built-in Display"), control: displayPowerSwitch))
        let rotateMenu = NSMenu()
        rotateMenu.autoenablesItems = false
        let currentRotation = displayController.builtinDisplay().map { Int(CGDisplayRotation($0).rounded()) }
        for degrees in [0, 90, 180, 270] {
            let entry = actionItem("\(degrees)°", action: #selector(menuRotationChanged(_:)), tag: degrees)
            entry.state = currentRotation == degrees ? .on : .off
            entry.isEnabled = displayRotateButton.isEnabled
            rotateMenu.addItem(entry)
        }
        let rotateItem = submenuItem(String(localized: "Rotate Built-in"), rotateMenu)
        rotateItem.isEnabled = displayRotateButton.isEnabled
        displayMenu.addItem(rotateItem)
        displayMenu.addItem(toggleItem("Studio Display", control: studioPowerSwitch))
        displayMenu.addItem(.separator())
        let preset = loadRotationPreset()
        let applyPreset = actionItem(String(localized: "Apply “\(preset.name)”"), action: #selector(applyRotationPreset))
        applyPreset.isEnabled = rotationModeButton.isEnabled
        displayMenu.addItem(applyPreset)
        displayMenu.addItem(toggleItem(String(localized: "Apply Automatically When Studio Display Connects"),
                                       control: displayAutoPresetSwitch))
    }

    private func actionItem(_ title: String, action: Selector, tag: Int = 0) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        return entry
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = submenu
        return entry
    }

    // Mirrors a panel toggle; choosing it flips the control and runs the control's own handler.
    func toggleItem(_ title: String, control: NSButton) -> NSMenuItem {
        let entry = actionItem(title, action: #selector(menuToggleChanged(_:)))
        entry.representedObject = control
        entry.state = control.state
        entry.isEnabled = control.isEnabled
        return entry
    }

    @objc private func menuToggleChanged(_ sender: NSMenuItem) {
        guard let control = sender.representedObject as? NSButton, let action = control.action else { return }
        control.state = control.state == .on ? .off : .on
        NSApp.sendAction(action, to: control.target, from: control)
    }

    @objc private func menuBrightnessChanged(_ sender: NSMenuItem) {
        brightnessSlider.doubleValue = Double(sender.tag)
        brightnessChanged()
    }

    @objc private func menuTemperatureChanged(_ sender: NSMenuItem) {
        temperatureSlider.doubleValue = Double(sender.tag)
        temperatureChanged()
    }

    @objc func openPanelFromMenu() {
        // Wait for the menu to finish closing before anchoring the popover to the status button.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.togglePanel()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LoginItem.isEnabled
        guard LoginItem.setEnabled(enable) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Change Launch at Login")
            alert.informativeText = String(localized: "The login item in ~/Library/LaunchAgents couldn't be updated.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        log(enable ? "Launch at login on (LaunchAgent written)" : "Launch at login off (LaunchAgent removed)")
    }

    @objc func showAbout() {
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc func showHelp() {
        if popover.isShown { popover.performClose(nil) }
        let controller = helpWindowController ?? HelpWindowController()
        helpWindowController = controller
        controller.present()
    }

    @objc func quitApp() {
        log("Quit requested")
        NSApp.terminate(nil)
    }
}
