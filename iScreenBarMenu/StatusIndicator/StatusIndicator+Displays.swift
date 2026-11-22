import AppKit

extension StatusIndicator {
    @objc func keepAwakeChanged() {
        let requested = keepAwakeSwitch.state == .on
        guard keepAwakeController.setActive(requested) else {
            keepAwakeSwitch.state = .off
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Turn On Keep Awake")
            alert.informativeText = String(localized: "macOS couldn't start caffeinate. Please try again later.")
            alert.runModal()
            return
        }
        keepAwakeSwitch.state = keepAwakeController.isActive ? .on : .off
        handleKeepAwakeLidDisplayState()
        log(keepAwakeController.isActive ? "Keep-awake on" : "Restored default system sleep")
    }

    func handleKeepAwakeLidDisplayState() {
        guard displayController.lidClosed() else {
            didRequestDisplaySleepForCurrentLidClosure = false
            return
        }
        guard keepAwakeController.isActive,
              displayController.externalDisplays().isEmpty,
              !didRequestDisplaySleepForCurrentLidClosure else { return }

        // With disablesleep, a closed lid falls back to the displaysleep timer; with no external display, request display sleep now.
        didRequestDisplaySleepForCurrentLidClosure = true
        let success = requestSystemDisplaySleep()
        log(success
            ? "Lid closed during keep-awake; requested built-in display off"
            : "Lid closed during keep-awake; display sleep request failed")
    }

    func migrateDisplayPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: "rotationPreset") == nil else { return }
        if let old = UserDefaults(suiteName: "local.qiu.builtin-display-rotation"),
           old.bool(forKey: "DisplayPresetSaved") {
            let preset = DisplayPreset(name: String(localized: "My Rotation Preset"),
                                       builtinEnabled: old.bool(forKey: "DisplayPresetBuiltinEnabled"),
                                       rotation: old.integer(forKey: "DisplayPresetRotation"),
                                       builtinPrimary: old.bool(forKey: "DisplayPresetBuiltinPrimary"))
            saveRotationPreset(preset)
            return
        }
        saveRotationPreset(DisplayPreset(name: String(localized: "Portrait Dual"), builtinEnabled: true, rotation: 90, builtinPrimary: false))
    }

    private func saveRotationPreset(_ preset: DisplayPreset) {
        if let data = try? JSONEncoder().encode(preset) {
            UserDefaults.standard.set(data, forKey: "rotationPreset")
            rotationModeButton.title = preset.name
        }
    }

    func loadRotationPreset() -> DisplayPreset {
        if let data = UserDefaults.standard.data(forKey: "rotationPreset"),
           let preset = try? JSONDecoder().decode(DisplayPreset.self, from: data) { return preset }
        return DisplayPreset(name: String(localized: "Portrait Dual"), builtinEnabled: true, rotation: 90, builtinPrimary: false)
    }

    private func saveDisplayBaselineIfNeeded() {
        guard UserDefaults.standard.data(forKey: "displayAutoBaseline") == nil,
              let baseline = displayController.currentPreset(name: String(localized: "Before Auto-Apply")) else { return }
        if let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: "displayAutoBaseline")
        }
    }

    private func restoreDisplayBaseline(clear: Bool) {
        guard let data = UserDefaults.standard.data(forKey: "displayAutoBaseline"),
              let baseline = try? JSONDecoder().decode(DisplayPreset.self, from: data) else {
            _ = displayController.enableBuiltin(); return
        }
        _ = displayController.apply(baseline)
        if clear { UserDefaults.standard.removeObject(forKey: "displayAutoBaseline") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc func displayPowerChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        let requested = displayPowerSwitch.state == .on
        let success = requested ? displayController.enableBuiltin() : displayController.disableBuiltin()
        if success {
            isBuiltinManuallyDisabled = !requested
        } else {
            displayPowerSwitch.state = requested ? .off : .on
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc func studioPowerChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { refreshControls(); return }
        let enabled = studioPowerSwitch.state == .on
        guard displayController.setStudioEnabled(enabled) else {
            refreshControls()
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Switch Studio Display")
            alert.informativeText = String(localized: "No available Studio Display found.")
            alert.runModal()
            return
        }
        if !enabled { popover.performClose(nil) }
        refreshControls()
    }

    @objc func displaySessionBecameUnsafe(_ notification: Notification) {
        _ = displayController.setStudioEnabled(true)
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        pendingDisplayPolicyWorkItem = nil
        log("Locked or display asleep; paused built-in display configuration")
        if notification.name == NSWorkspace.sessionDidResignActiveNotification {
            // Chrome/web video may hold a NoDisplaySleepAssertion that keeps the display on for minutes after locking.
            // Request display sleep only once the session is confirmed locked; display configuration after unlock is unaffected.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard isConsoleSessionLocked() else { return }
                log(requestSystemDisplaySleep()
                    ? "Mac locked; requested immediate display sleep"
                    : "Mac locked, but display sleep request failed")
            }
        }
    }

    @objc func displaySessionBecameActive() {
        scheduleDisplaySessionActivation()
    }

    func scheduleDisplaySessionActivation() {
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isDisplaySessionSafe = true
            let pendingState = self.pendingDisplayConnectionState
            self.pendingDisplayConnectionState = nil
            if let pendingState {
                self.scheduleDisplayPolicy(forExternalConnection: pendingState)
            }
            self.refreshControls()
            log("Display session settled; built-in manual control resumed")
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func scheduleDisplayPolicy(forExternalConnection connected: Bool) {
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let externalStillConnected = studioDisplayID() != nil
            guard externalStillConnected == connected else { return }
            if !connected {
                // After an external disconnect the built-in display is the only fallback: even while the session is switching or locked,
                // bring the built-in display online first so the "unsafe" guard does not drop the disconnect event.
                self.isBuiltinManuallyDisabled = false
                let enabled = self.displayController.enableBuiltin()
                if enabled {
                    self.requestBuiltinWakeAfterExternalDisconnect()
                    if self.isDisplaySessionSafe, !isConsoleSessionLocked() {
                        _ = self.displayController.restoreBuiltinDefault()
                    }
                } else {
                    self.pendingDisplayConnectionState = false
                    self.scheduleDisplaySessionActivation()
                    log("External display disconnected; built-in restore not effective yet, retry scheduled")
                }
                self.refreshControls()
                return
            }
            guard self.isDisplaySessionSafe, !isConsoleSessionLocked() else {
                self.pendingDisplayConnectionState = true
                return
            }
            if connected {
                if self.isDisplayAutoPresetEnabled {
                    self.saveDisplayBaselineIfNeeded()
                    _ = self.displayController.apply(self.automaticRotationPreset())
                    log("Studio Display connected: auto preset on, applying saved rotation")
                } else {
                    if !self.isBuiltinManuallyDisabled {
                        _ = self.displayController.enableBuiltin()
                    }
                    self.resetBuiltinRotationWhenPresetDisabled()
                }
            }
            self.refreshControls()
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func requestBuiltinWakeAfterExternalDisconnect() {
        pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
        pendingBuiltinWakeWorkItems.removeAll()

        let delays: [TimeInterval] = [0, 1.5, 4, 8, 15]
        for (index, delay) in delays.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, studioDisplayID() == nil else { return }
                self.isBuiltinManuallyDisabled = false
                let enabled = self.displayController.enableBuiltin(force: true)
                let lidOpen = !self.displayController.lidClosed()
                let wakeRequested = lidOpen && requestSystemDisplayWake()
                if self.displayController.builtinIsAwake() {
                    log("External display disconnected; system reports built-in online/active/awake (picture not verified)")
                    self.pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
                    self.pendingBuiltinWakeWorkItems.removeAll()
                } else if index == delays.count - 1 {
                    log("External display disconnected; built-in restore unconfirmed: online=\(enabled), lidClosed=\(!lidOpen), wakeRequested=\(wakeRequested)")
                }
                self.refreshControls()
            }
            pendingBuiltinWakeWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func automaticRotationPreset() -> DisplayPreset {
        var preset = loadRotationPreset()
        preset.builtinEnabled = !isBuiltinManuallyDisabled
        return preset
    }

    @objc func displayRotationChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        guard let builtin = displayController.builtinDisplay(), CGDisplayIsOnline(builtin) != 0 else { return }
        let current = Int(CGDisplayRotation(builtin).rounded())
        rotateBuiltinWithConfirmation(to: current == 0 ? 90 : (current == 90 ? 270 : 0))
    }

    @objc func menuRotationChanged(_ sender: NSMenuItem) {
        rotateBuiltinWithConfirmation(to: sender.tag)
    }

    private func rotateBuiltinWithConfirmation(to next: Int) {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        guard let builtin = displayController.builtinDisplay(), CGDisplayIsOnline(builtin) != 0 else { return }
        let current = Int(CGDisplayRotation(builtin).rounded())
        guard next != current else { return }
        popover.performClose(nil)
        guard displayController.rotateBuiltin(to: next) else {
            log("Built-in rotation failed; skipping confirmation")
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Keep Built-in Display Rotation?")
        alert.informativeText = String(localized: "Reverting to \(current)° in 5 seconds unless you confirm.")
        alert.addButton(withTitle: String(localized: "Keep Rotation"))
        alert.addButton(withTitle: String(localized: "Revert"))
        // Repeated Return presses must not confirm the rotation by accident; Esc always reverts.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var expired = false
        let countdown = Timer(timeInterval: 0.1, repeats: true) { _ in
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                expired = true
                NSApplication.shared.abortModal()
            } else {
                alert.informativeText = String(localized: "Reverting to \(current)° in \(Int(ceil(remaining))) seconds unless you confirm.")
            }
        }
        // runModal uses its own run-loop mode; a normal scheduledTimer does not fire meanwhile.
        RunLoop.main.add(countdown, forMode: .modalPanel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        countdown.invalidate()
        alert.window.orderOut(nil)
        let confirmed = response == .alertFirstButtonReturn && !expired &&
            ProcessInfo.processInfo.systemUptime < deadline
        if !confirmed {
            let restored = displayController.rotateBuiltin(to: current)
            log(restored ? "Built-in rotation not confirmed; requested revert to \(current)°" : "Built-in rotation revert failed")
        } else {
            log("Built-in rotation confirmed at \(next)°")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc func displayAutoPresetChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        isDisplayAutoPresetEnabled = displayAutoPresetSwitch.state == .on
        UserDefaults.standard.set(isDisplayAutoPresetEnabled, forKey: "displayAutoPresetEnabled")
        if isDisplayAutoPresetEnabled {
            saveDisplayBaselineIfNeeded()
            if !displayController.externalDisplays().isEmpty { _ = displayController.apply(automaticRotationPreset()) }
            log("Rotation auto preset on")
        } else {
            // Turning the preset off returns to landscape explicitly; the old baseline may already be 270°, so it must not be reapplied.
            UserDefaults.standard.removeObject(forKey: "displayAutoBaseline")
            resetBuiltinRotationWhenPresetDisabled()
            log("Rotation auto preset off; future connections stay at 0°")
        }
        refreshControls()
    }

    private func resetBuiltinRotationWhenPresetDisabled() {
        guard !isDisplayAutoPresetEnabled,
              let builtin = displayController.builtinDisplay(),
              CGDisplayIsOnline(builtin) != 0 else { return }
        if Int(CGDisplayRotation(builtin).rounded()) != 0 {
            let requested = displayController.rotateBuiltin(to: 0)
            log("Auto preset off; built-in landscape request: \(requested)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.isDisplayAutoPresetEnabled,
                  let id = self.displayController.builtinDisplay() else { return }
            log("Auto preset off; built-in rotation readback: \(Int(CGDisplayRotation(id).rounded()))°")
            self.refreshControls()
        }
    }

    @objc func showRotationModeMenu() {
        let menu = NSMenu()
        let preset = loadRotationPreset()
        let apply = NSMenuItem(title: String(localized: "Apply “\(preset.name)”"), action: #selector(applyRotationPreset), keyEquivalent: "")
        apply.target = self; menu.addItem(apply)
        let save = NSMenuItem(title: String(localized: "Save Current as Rotation Preset…"), action: #selector(saveCurrentRotationPreset), keyEquivalent: "")
        save.target = self; menu.addItem(save)
        menu.addItem(.separator())
        let automatic = NSMenuItem(title: String(localized: "Apply Automatically When Studio Display Connects"), action: #selector(toggleRotationPresetAutomation), keyEquivalent: "")
        automatic.target = self; automatic.state = isDisplayAutoPresetEnabled ? .on : .off
        menu.addItem(automatic)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: rotationModeButton.bounds.height + 4), in: rotationModeButton)
    }

    @objc func applyRotationPreset() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        if !displayController.apply(loadRotationPreset()) { log("Failed to apply rotation preset") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func saveCurrentRotationPreset() {
        guard let current = displayController.currentPreset(name: String(localized: "My Rotation Preset")) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Rotation Preset")
        alert.informativeText = String(localized: "Saves the built-in display on/off state, rotation, and main display role.")
        let field = NSTextField(string: loadRotationPreset().name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save")); alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var preset = current
        preset.name = field.stringValue.isEmpty ? String(localized: "My Rotation Preset") : field.stringValue
        saveRotationPreset(preset)
        log("Saved rotation preset: \(preset.name)")
    }

    @objc private func toggleRotationPresetAutomation() {
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .off : .on
        displayAutoPresetChanged()
    }

    func handleStudioDisplayConnection(connected: Bool) {
        pendingDisplayConnectionState = connected
        if connected {
            pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
            pendingBuiltinWakeWorkItems.removeAll()
        }
        if !connected {
            // Skip the 5-second session settle period; enable the built-in display first, restore rotation and main display later.
            isBuiltinManuallyDisabled = false
            requestBuiltinWakeAfterExternalDisconnect()
            log("External display disconnected; scheduled forced built-in enable with separate retries")
        }
        guard isDisplaySessionSafe else { return }
        pendingDisplayConnectionState = nil
        scheduleDisplayPolicy(forExternalConnection: connected)
    }
}
