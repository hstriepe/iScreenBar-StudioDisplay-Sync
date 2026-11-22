import AppKit

extension StatusIndicator {
    @objc func powerChanged() {
        let requested = powerSwitch.state == .on
        if !lamp.setPower(on: requested) { powerSwitch.state = requested ? .off : .on }
        updateIcon(healthy: isHealthy && lamp.isConnected)
        lamp.requestStatus()
    }

    @objc func brightnessChanged() {
        let value = Int(brightnessSlider.doubleValue.rounded())
        brightnessValueLabel.stringValue = "\(value)%"
        _ = lamp.setBrightness(value)
        lamp.requestStatus()
    }

    @objc func temperatureChanged() {
        let value = Int((temperatureSlider.doubleValue / 100).rounded()) * 100
        temperatureSlider.doubleValue = Double(value)
        temperatureValueLabel.stringValue = "\(value)K"
        _ = lamp.setTemperature(value)
        lamp.requestStatus()
    }

    @objc func timeTemperatureChanged() {
        isTimeTemperatureEnabled = timeTemperatureSwitch.state == .on
        UserDefaults.standard.set(isTimeTemperatureEnabled, forKey: "timeTemperatureEnabled")
        lastScheduledTemperature = nil
        lastScheduledTemperatureChangeAt = .distantPast
        refreshControls()
        if isTimeTemperatureEnabled {
            applyScheduledTemperatureIfNeeded(isAsleep: isAsleep, force: true)
            log("Time-based color temperature on")
        } else {
            log("Time-based color temperature off; keeping current temperature")
        }
    }

    func applyScheduledTemperatureIfNeeded(isAsleep: Bool, force: Bool = false) {
        guard isTimeTemperatureEnabled,
              !isAsleep,
              lamp.isConnected,
              lamp.isPowerOn == true else { return }
        let target = scheduledTemperature(at: Date())
        guard force || target != lastScheduledTemperature || lamp.currentTemperature != target else { return }
        guard force || Date().timeIntervalSince(lastScheduledTemperatureChangeAt) >= 60 else { return }
        if lamp.setTemperature(target) {
            lastScheduledTemperature = target
            lastScheduledTemperatureChangeAt = Date()
            log("Time-based color temperature set to \(target)K")
        }
    }

    private func scheduledTemperature(at date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let value: Double
        switch minute {
        case 0..<(6 * 60):
            value = 3000
        case (6 * 60)..<(10 * 60):
            value = interpolate(minute: minute, from: 6 * 60, to: 10 * 60, start: 3000, end: 5500)
        case (10 * 60)..<(16 * 60):
            value = 5500
        case (16 * 60)..<(21 * 60):
            value = interpolate(minute: minute, from: 16 * 60, to: 21 * 60, start: 5500, end: 3500)
        default:
            value = interpolate(minute: minute, from: 21 * 60, to: 24 * 60, start: 3500, end: 3000)
        }
        return max(2700, min(6500, Int((value / 50).rounded()) * 50))
    }

    private func interpolate(minute: Int, from: Int, to: Int, start: Double, end: Double) -> Double {
        let progress = Double(minute - from) / Double(to - from)
        return start + (end - start) * max(0, min(1, progress))
    }

    @objc func autoLightChanged() {
        let requested = autoLightSwitch.state == .on
        if !lamp.setAutoLight(enabled: requested) {
            autoLightSwitch.state = requested ? .off : .on
            return
        }
        autoLightChangePendingUntil = Date().addingTimeInterval(1)
        pendingAutoLightState = requested
        if requested, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            update(isAsleep: isAsleep, healthy: isHealthy)
            log("Turned off Studio Display brightness follow; using lamp auto-light")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.lamp.requestStatus()
        }
    }

    @objc func presenceChanged() {
        let requested = presenceSwitch.state == .on
        if !lamp.setPresenceDetection(enabled: requested, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
            presenceSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc func presenceDelayChanged() {
        let seconds = selectedPresenceDelaySeconds()
        presenceDelaySeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "presenceDelaySeconds")
        log("Presence delay set to \(seconds) s")
        if lamp.isPresenceDetectionEnabled == true {
            let requested = presenceSwitch.state == .on
            if !lamp.setPresenceDetection(enabled: requested, delaySeconds: seconds, sensitivity: presenceSensitivity) {
                log("Presence delay not accepted by lamp; local setting kept")
            }
            lamp.requestStatus()
        }
    }

    @objc func presenceSensitivityChanged() {
        presenceSensitivity = presenceSensitivityPopup.selectedItem?.tag ?? 2
        UserDefaults.standard.set(presenceSensitivity, forKey: "presenceSensitivity")
        log("Presence sensitivity set to \(presenceSensitivity)")
        if lamp.isPresenceDetectionEnabled == true {
            if !lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
                log("Presence sensitivity not accepted by lamp; local setting kept")
            }
            lamp.requestStatus()
        }
    }

    @objc func videoModeChanged() {
        let requested = videoModeSwitch.state == .on
        if !lamp.setVideoMode(enabled: requested) {
            videoModeSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc func brightnessFollowChanged() {
        let requested = brightnessFollowSwitch.state == .on
        if requested, lamp.isAutoLightEnabled == true {
            guard lamp.setAutoLight(enabled: false) else {
                brightnessFollowSwitch.state = .off
                log("Failed to turn off auto-light; Studio Display brightness follow not enabled")
                return
            }
            autoLightSwitch.state = .off
            autoLightChangePendingUntil = Date().addingTimeInterval(1)
            pendingAutoLightState = false
            lamp.requestStatus()
            log("Turned off auto-light; using Studio Display brightness follow")
        }
        isBrightnessFollowEnabled = requested
        UserDefaults.standard.set(isBrightnessFollowEnabled, forKey: "brightnessFollowEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isBrightnessFollowEnabled ? "Studio Display brightness follow on" : "Studio Display brightness follow off")
    }

    @objc func displayBrightnessLockChanged() {
        isDisplayBrightnessLockEnabled = displayBrightnessLockSwitch.state == .on
        UserDefaults.standard.set(isDisplayBrightnessLockEnabled, forKey: "displayBrightnessLockEnabled")
        log(isDisplayBrightnessLockEnabled
            ? "MacBook / Studio Display brightness lock on"
            : "MacBook / Studio Display brightness lock off")
        refreshControls()
    }

    @objc func powerSyncChanged() {
        isPowerSyncEnabled = powerSyncSwitch.state == .on
        UserDefaults.standard.set(isPowerSyncEnabled, forKey: "powerSyncEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isPowerSyncEnabled ? "Sleep sync on" : "Sleep sync off")
        refreshControls()
    }

    @objc func presenceWakeChanged() {
        isPresenceWakeEnabled = presenceWakeSwitch.state == .on
        UserDefaults.standard.set(isPresenceWakeEnabled, forKey: "presenceWakeEnabled")
        // Presence paused by an earlier display sleep goes back on now; turning it off lets the poll loop pause it again.
        if isPresenceWakeEnabled { restorePresenceAfterScreenWake(reason: "Wake Screen turned on") }
        log(isPresenceWakeEnabled ? "Wake screen on presence on" : "Wake screen on presence off")
        refreshControls()
    }

    func selectPresenceDelay(_ seconds: Int) {
        if let item = presenceDelayPopup.menu?.item(withTag: seconds) {
            presenceDelayPopup.select(item)
            return
        }
        if let fallback = presenceDelayPopup.itemArray.first(where: { $0.tag == 180 }) {
            presenceDelayPopup.select(fallback)
        }
    }

    private func selectedPresenceDelaySeconds() -> Int {
        return presenceDelayPopup.selectedItem?.tag ?? presenceDelaySeconds
    }
}
