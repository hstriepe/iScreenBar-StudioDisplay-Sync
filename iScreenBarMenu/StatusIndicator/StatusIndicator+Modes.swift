import AppKit

// Light modes: panel mode picker, Favorites menu entries, Mode Center, and app-switch modes. Data in ModeStore.
extension StatusIndicator {
    @objc func presetChanged(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let mode = ModeStore.mode(id: id) else { return }
        applyMode(mode)
    }

    /// Applies a mode: lamp on, saved toggles through their panel buttons (so persistence and lock rules apply),
    /// then brightness, color temperature, and video mode. Modes without saved toggles behave as before 0.10.
    func applyMode(_ mode: LightMode) {
        refreshControls()
        _ = lamp.setPower(on: true)
        let autoLight = mode.autoLight == true
        let matchScreen = !autoLight && mode.matchScreen == true
        // Stop following first so the follow loop doesn't overwrite the mode's brightness.
        if !matchScreen { setToggle(brightnessFollowSwitch, on: false) }
        if autoLight {
            setToggle(autoLightSwitch, on: true)
        } else {
            _ = lamp.setBrightness(mode.brightness)
            if autoLightSwitch.state == .on || mode.autoLight == false { setToggle(autoLightSwitch, on: false) }
        }
        if let autoTemperature = mode.autoTemperature { setToggle(timeTemperatureSwitch, on: autoTemperature) }
        if !isTimeTemperatureEnabled { _ = lamp.setTemperature(mode.temperature) }
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        if let presence = mode.presence { setToggle(presenceSwitch, on: presence) }
        if matchScreen {
            if isBrightnessFollowEnabled {
                brightnessFollowReanchorRequested = true
            } else {
                setToggle(brightnessFollowSwitch, on: true)
            }
        }
        ModeStore.selectedModeID = mode.id
        refreshControls()
        refreshModeButtonTitle()
        log("Applied mode: \(mode.name)")
        lamp.requestStatus()
    }

    /// Sets a panel toggle and runs its own action, like clicking it. Disabled controls (e.g. Presence during a
    /// light-off lock) are left alone.
    private func setToggle(_ control: NSButton, on: Bool) {
        let target: NSControl.StateValue = on ? .on : .off
        guard control.state != target, let action = control.action else { return }
        guard control.isEnabled else {
            log("Mode: \(control.title) unavailable; left \(control.state == .on ? "on" : "off")")
            return
        }
        control.state = target
        NSApp.sendAction(action, to: control.target, from: control)
    }

    /// The lamp's current settings and toggles as an unnamed mode; nil while the lamp hasn't reported.
    func currentLampMode() -> LightMode? {
        guard let brightness = lamp.currentBrightness, let temperature = lamp.currentTemperature else { return nil }
        return LightMode(name: "", brightness: brightness, temperature: temperature,
                         videoMode: lamp.isVideoModeEnabled == true,
                         matchScreen: isBrightnessFollowEnabled, autoLight: lamp.isAutoLightEnabled == true,
                         presence: presenceSwitch.state == .on, autoTemperature: isTimeTemperatureEnabled)
    }

    /// One menu item per mode (checked = selected mode); used by the panel picker and the Favorites submenu.
    func modeMenuItems(enabled: Bool) -> [NSMenuItem] {
        let selected = ModeStore.selectedModeID
        return ModeStore.modes.map { mode in
            let item = NSMenuItem(title: mode.name, action: #selector(presetChanged(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id
            item.state = mode.id == selected ? .on : .off
            item.isEnabled = enabled
            return item
        }
    }

    @objc func showModeMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        modeMenuItems(enabled: true).forEach(menu.addItem)
        menu.addItem(.separator())
        let center = NSMenuItem(title: String(localized: "Mode Center…"), action: #selector(showModeCenter), keyEquivalent: "")
        center.target = self
        menu.addItem(center)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeButton.bounds.height + 4), in: modeButton)
    }

    func refreshModeButtonTitle() {
        let modes = ModeStore.modes
        let selected = ModeStore.selectedModeID.flatMap { id in modes.first { $0.id == id } }
        modeButton.title = selected?.name ?? String(localized: "Choose a Mode")
    }

    @objc func showModeCenter() {
        popover.performClose(nil)
        let controller = modeCenterController ?? ModeCenterWindowController()
        if modeCenterController == nil {
            controller.currentLampSettings = { [weak self] in self?.currentLampMode() }
            controller.applyMode = { [weak self] mode in self?.applyMode(mode) }
            controller.modesChanged = { [weak self] in self?.refreshModeButtonTitle() }
            modeCenterController = controller
        }
        controller.show()
    }

    func applyModeForFrontmostAppIfNeeded() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundleID != lastFrontmostBundleID else { return }
        lastFrontmostBundleID = bundleID
        guard let modeID = ModeStore.bindings[bundleID], let mode = ModeStore.mode(id: modeID),
              lamp.isConnected else { return }
        log("Frontmost app \(bundleID) has mode \(mode.name)")
        applyMode(mode)
    }
}
