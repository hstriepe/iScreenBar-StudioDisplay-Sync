import AppKit

extension StatusIndicator {
    @objc func captureBrightThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureBrightButton.state = .off
            ambientStatusLabel.stringValue = String(localized: "Can't read the Studio Display light sensor right now")
            NSSound.beep()
            return
        }
        ambientCloseThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientCloseThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureBrightButton, valueLabel: brightThresholdLabel)
        log("Captured ambient off point: \(currentAmbientSourceName) score \(value)")
    }

    @objc func captureDarkThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureDarkButton.state = .off
            ambientStatusLabel.stringValue = String(localized: "Can't read the Studio Display light sensor right now")
            NSSound.beep()
            return
        }
        ambientOpenThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientOpenThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureDarkButton, valueLabel: darkThresholdLabel)
        log("Captured ambient on point: \(currentAmbientSourceName) score \(value)")
    }

    private func flashCaptureSuccess(button: FeatureButton, valueLabel: NSTextField) {
        button.state = .on
        valueLabel.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak button, weak valueLabel] in
            button?.state = .off
            valueLabel?.textColor = .secondaryLabelColor
        }
    }

    @objc func ambientEnableChanged() {
        areAmbientRulesEnabled = ambientEnableSwitch.state == .on
        UserDefaults.standard.set(areAmbientRulesEnabled, forKey: "ambientRulesEnabled")
        updateAmbientStatusLabel()
        log(areAmbientRulesEnabled ? "Enabled saved ambient light rules" : "Disabled ambient light rules; calibration kept")
    }

    func updateDisplayAmbientProxy(_ value: Int?, sourceName: String) {
        let availabilityChanged = (currentDisplayAmbientProxy == nil) != (value == nil)
        currentDisplayAmbientProxy = value
        currentAmbientSourceName = sourceName
        if availabilityChanged { updateAmbientControlAvailability() }
        if popover.isShown { updateAmbientStatusLabel() }
    }

    // Capture needs a sensor reading; the rules switch also needs at least one saved threshold.
    // Kept separate from refreshControls so the menu and an open panel follow the sensor as soon as it appears or drops out.
    func updateAmbientControlAvailability() {
        let hasReading = currentDisplayAmbientProxy != nil
        captureBrightButton.isEnabled = hasReading
        captureDarkButton.isEnabled = hasReading
        ambientEnableSwitch.isEnabled = hasReading && (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
    }

    @discardableResult
    func suspendPresenceForAmbientLock() -> Bool {
        if isAmbientPresenceLockActive {
            maintainPresenceSuspendedForAmbientLock()
            return true
        }
        isAmbientPresenceLockActive = true
        presenceWasEnabledBeforeAmbientLock = presenceWasEnabledBeforeAmbientLock || lamp.isPresenceDetectionEnabled == true
        autoLightWasEnabledBeforeAmbientLock = autoLightWasEnabledBeforeAmbientLock || lamp.isAutoLightEnabled == true
        if autoLightWasEnabledBeforeAmbientLock {
            guard lamp.setAutoLight(enabled: false) else {
                isAmbientPresenceLockActive = false
                autoLightWasEnabledBeforeAmbientLock = false
                return false
            }
            UserDefaults.standard.set(true, forKey: "ambientSuspendedAutoLightWasEnabled")
            log("Ambient off-lock temporarily paused auto-light")
        }
        if presenceWasEnabledBeforeAmbientLock {
            guard lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                            sensitivity: presenceSensitivity) else {
                if autoLightWasEnabledBeforeAmbientLock {
                    _ = lamp.setAutoLight(enabled: true)
                    UserDefaults.standard.removeObject(forKey: "ambientSuspendedAutoLightWasEnabled")
                }
                isAmbientPresenceLockActive = false
                presenceWasEnabledBeforeAmbientLock = false
                autoLightWasEnabledBeforeAmbientLock = false
                return false
            }
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
            log("Ambient off-lock temporarily paused presence detection")
        }
        refreshControls()
        return true
    }

    func maintainPresenceSuspendedForAmbientLock() {
        guard isAmbientPresenceLockActive else { return }
        // While the lamp is off, the firmware ignores the "write manual brightness" action that exits auto-light.
        // An off-lock left by an older version only remembers the intent to restore; if the lamp turns itself on, pause again immediately.
        if lamp.isPowerOn == true, lamp.isAutoLightEnabled == true {
            autoLightWasEnabledBeforeAmbientLock = true
            if lamp.setAutoLight(enabled: false) {
                UserDefaults.standard.set(true, forKey: "ambientSuspendedAutoLightWasEnabled")
                log("Auto-light still on during ambient lock; paused temporarily")
            }
        }
        if lamp.isPresenceDetectionEnabled == true {
            presenceWasEnabledBeforeAmbientLock = true
            if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
                log("Presence detection still on during ambient lock; paused temporarily")
            }
        }
    }

    func restorePresenceAfterAmbientLock() {
        guard isAmbientPresenceLockActive || presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock else { return }
        let shouldRestorePresence = presenceWasEnabledBeforeAmbientLock
        let shouldRestoreAutoLight = autoLightWasEnabledBeforeAmbientLock
        isAmbientPresenceLockActive = false
        presenceWasEnabledBeforeAmbientLock = false
        autoLightWasEnabledBeforeAmbientLock = false
        UserDefaults.standard.removeObject(forKey: "ambientSuspendedPresenceWasEnabled")
        UserDefaults.standard.removeObject(forKey: "ambientSuspendedAutoLightWasEnabled")
        if shouldRestorePresence, isScreenSleepPresenceLockActive {
            presenceWasEnabledBeforeScreenSleep = true
            UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
        } else if shouldRestorePresence {
            if lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                log("Ambient off-lock released; presence detection restored")
            } else {
                log("Ambient off-lock released, but restoring presence detection failed")
            }
        }
        if shouldRestoreAutoLight {
            if lamp.setAutoLight(enabled: true) {
                log("Ambient off-lock released; auto-light restored")
            } else {
                log("Ambient off-lock released, but restoring auto-light failed")
            }
        }
        refreshControls()
    }

    func suspendPresenceForScreenSleep() {
        // Wake Screen: presence detection keeps running so the lamp turning itself on can wake the display (ADR 0008).
        guard !isPresenceWakeEnabled else { return }
        if isScreenSleepPresenceLockActive {
            if lamp.isPresenceDetectionEnabled == true {
                presenceWasEnabledBeforeScreenSleep = true
                if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                             sensitivity: presenceSensitivity) {
                    UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
                    log("Presence detection still on while screen is off; paused again")
                }
            }
            return
        }
        // If the ambient off-lock already paused it, the ambient lock restores it, so wake does not turn it on early.
        guard !isAmbientPresenceLockActive else { return }
        isScreenSleepPresenceLockActive = true
        presenceWasEnabledBeforeScreenSleep = lamp.isPresenceDetectionEnabled == true
        guard presenceWasEnabledBeforeScreenSleep else { return }
        if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                     sensitivity: presenceSensitivity) {
            UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
            log("Sleep sync temporarily paused presence detection")
        } else {
            isScreenSleepPresenceLockActive = false
            presenceWasEnabledBeforeScreenSleep = false
            log("Failed to pause presence detection on screen sleep")
        }
        refreshControls()
    }

    /// `reason` starts the log line; the default fits the normal call after the display wakes.
    func restorePresenceAfterScreenWake(reason: String = "Screen awake") {
        guard isScreenSleepPresenceLockActive || presenceWasEnabledBeforeScreenSleep else { return }
        let shouldRestore = presenceWasEnabledBeforeScreenSleep
        isScreenSleepPresenceLockActive = false
        presenceWasEnabledBeforeScreenSleep = false
        UserDefaults.standard.removeObject(forKey: "screenSleepSuspendedPresenceWasEnabled")
        if shouldRestore, isAmbientPresenceLockActive {
            presenceWasEnabledBeforeAmbientLock = true
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
        }
        if shouldRestore, !isAmbientPresenceLockActive {
            if lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                log("\(reason); presence detection restored")
            } else {
                log("\(reason), but restoring presence detection failed")
            }
        }
        refreshControls()
    }

    var hasPendingAmbientPresenceRestore: Bool {
        return presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock
    }

    func updateAmbientStatusLabel() {
        brightThresholdLabel.stringValue = ambientCloseThreshold.map(String.init) ?? "--"
        darkThresholdLabel.stringValue = ambientOpenThreshold.map(String.init) ?? "--"
        captureBrightButton.state = .off
        captureDarkButton.state = .off
        ambientEnableSwitch.state = areAmbientRulesEnabled ? .on : .off
        updateAmbientControlAvailability()
        let currentText = currentDisplayAmbientProxy.map { String(localized: "Ambient \($0)") } ?? String(localized: "Ambient --")
        if currentDisplayAmbientProxy != nil, ambientCloseThreshold == nil, ambientOpenThreshold == nil {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Capture a threshold to enable")
        } else if let close = ambientCloseThreshold, let open = ambientOpenThreshold, open >= close {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Thresholds overlap; may toggle repeatedly")
        } else if !areAmbientRulesEnabled, ambientCloseThreshold != nil || ambientOpenThreshold != nil {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Saved, not enabled")
        } else {
            ambientStatusLabel.stringValue = currentText
        }
    }

    var isAmbientLinkEnabled: Bool {
        return areAmbientRulesEnabled && (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
    }
}
