import AppKit

// MARK: - Automation (AppleScript, App Intents, Control Center)

// Same path as the menu's toggleItem: set the panel control, then run its own action,
// so automation gets the same side effects, saving, and mutual exclusions.
extension StatusIndicator: AutomationTarget {
    func automationControl(for feature: AutomationFeature) -> NSButton {
        switch feature {
        case .light: return powerSwitch
        case .autoTemperature: return timeTemperatureSwitch
        case .autoLight: return autoLightSwitch
        case .presence: return presenceSwitch
        case .videoMode: return videoModeSwitch
        case .matchScreen: return brightnessFollowSwitch
        case .linkScreens: return displayBrightnessLockSwitch
        case .sleepSync: return powerSyncSwitch
        case .wakeScreen: return presenceWakeSwitch
        case .keepAwake: return keepAwakeSwitch
        case .builtinDisplay: return displayPowerSwitch
        }
    }

    func requiresLamp(_ feature: AutomationFeature) -> Bool {
        switch feature {
        case .light, .autoTemperature, .autoLight, .presence, .videoMode, .sleepSync, .wakeScreen: return true
        case .matchScreen, .linkScreens, .keepAwake, .builtinDisplay: return false
        }
    }

    var isLampConnected: Bool { lamp.isConnected }
    var lampBrightness: Int? { lamp.isConnected ? lamp.currentBrightness : nil }
    var lampTemperature: Int? { lamp.isConnected ? lamp.currentTemperature : nil }
    var isLampPowerOn: Bool { lamp.isPowerOn == true }
    var isAutoTemperatureOn: Bool { isTimeTemperatureEnabled }
    var isKeepAwakeActive: Bool { keepAwakeController.isActive }
    var favoriteNames: [String] { modeNames() }
    var rotationPresetName: String { loadRotationPreset().name }

    func isOn(_ feature: AutomationFeature) -> Bool {
        refreshControls()
        return automationControl(for: feature).state == .on
    }

    func setFeature(_ feature: AutomationFeature, on: Bool) throws {
        refreshControls()
        if requiresLamp(feature), !lamp.isConnected { throw AutomationError.lampNotConnected }
        let control = automationControl(for: feature)
        guard control.isEnabled, let action = control.action else { throw AutomationError.unavailable(feature.localizedName) }
        let target: NSControl.StateValue = on ? .on : .off
        guard control.state != target else { return }
        control.state = target
        NSApp.sendAction(action, to: control.target, from: control)
        guard control.state == target else { throw AutomationError.failed(feature.localizedName) }
        log("Automation: \(feature.rawValue) \(on ? "on" : "off")")
    }

    func setBrightness(_ value: Int) throws {
        refreshControls()
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        guard brightnessSlider.isEnabled else { throw AutomationError.unavailable(String(localized: "Brightness")) }
        brightnessSlider.doubleValue = Double(max(1, min(100, value)))
        brightnessChanged()
        log("Automation: brightness \(Int(brightnessSlider.doubleValue))%")
    }

    func setTemperature(_ kelvin: Int) throws {
        refreshControls()
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        guard !isTimeTemperatureEnabled else { throw AutomationError.autoTemperatureOn }
        guard temperatureSlider.isEnabled else { throw AutomationError.unavailable(String(localized: "Color Temperature")) }
        temperatureSlider.doubleValue = Double(max(2700, min(6500, kelvin)))
        temperatureChanged()
        log("Automation: color temperature \(Int(temperatureSlider.doubleValue))K")
    }

    func applyFavorite(named name: String) throws {
        let names = modeNames()
        // Built-in favorites also match their English names, whatever the UI language.
        let englishBuiltins = ["Favorite", "Night Work", "Wind Down"]
        let index = names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
            ?? englishBuiltins.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        guard let index else { throw AutomationError.unknownFavorite(name) }
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        let entry = NSMenuItem(title: names[index], action: nil, keyEquivalent: "")
        entry.tag = index
        presetChanged(entry)
    }

    func applyRotationPresetFromAutomation() throws {
        refreshControls()
        guard rotationModeButton.isEnabled else { throw AutomationError.unavailable(String(localized: "Rotation preset")) }
        applyRotationPreset()
        log("Automation: applied rotation preset")
    }

    func showControlPanel() {
        NSApp.activate(ignoringOtherApps: true)
        openPanelFromMenu()
    }
}
