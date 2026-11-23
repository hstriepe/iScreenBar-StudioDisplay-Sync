import AppKit

// Light modes: panel mode picker, Favorites menu entries, Mode Center, and app-switch modes. Data in ModeStore.
extension StatusIndicator {
    @objc func presetChanged(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let mode = ModeStore.mode(id: id) else { return }
        applyMode(mode)
    }

    func applyMode(_ mode: LightMode) {
        isBrightnessFollowEnabled = false
        brightnessFollowSwitch.state = .off
        UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(mode.brightness)
        _ = lamp.setTemperature(mode.temperature)
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        ModeStore.selectedModeID = mode.id
        refreshControls()
        refreshModeButtonTitle()
        log("Applied mode: \(mode.name)")
        lamp.requestStatus()
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
            controller.currentLampSettings = { [weak self] in
                guard let lamp = self?.lamp, let brightness = lamp.currentBrightness,
                      let temperature = lamp.currentTemperature else { return nil }
                return (brightness, temperature, lamp.isVideoModeEnabled == true)
            }
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
        guard let modeID = ModeStore.bindings[bundleID], let mode = ModeStore.mode(id: modeID) else { return }
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(mode.brightness)
        _ = lamp.setTemperature(mode.temperature)
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        log("Applied app mode for \(bundleID): \(mode.name)")
    }
}
