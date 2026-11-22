import AppKit
import Foundation

// AppleScript support (iScreenMenu.sdef). Properties are KVC keys on NSApplication;
// commands use method handlers via <responds-to>. Cocoa Scripting calls these on the
// main thread. Errors go back to the script through the current NSScriptCommand.

private let scriptErrorEventFailed = -10000 // errAEEventFailed

private func reportScriptError(_ error: Error) {
    let message = error.localizedDescription
    log("AppleScript: \(message)")
    guard let command = NSScriptCommand.current() else { return }
    command.scriptErrorNumber = scriptErrorEventFailed
    command.scriptErrorString = message
}

private func scriptTarget() -> AutomationTarget? {
    do {
        return try requireAutomationTarget()
    } catch {
        reportScriptError(error)
        return nil
    }
}

private func scriptRun(_ body: (AutomationTarget) throws -> Void) {
    guard let target = scriptTarget() else { return }
    do {
        try body(target)
    } catch {
        reportScriptError(error)
    }
}

private func scriptIsOn(_ feature: AutomationFeature) -> Bool {
    scriptTarget()?.isOn(feature) ?? false
}

private func scriptSet(_ feature: AutomationFeature, _ on: Bool) {
    scriptRun { try $0.setFeature(feature, on: on) }
}

extension NSApplication {
    // MARK: Read-only

    @objc var scriptLampConnected: Bool { scriptTarget()?.isLampConnected ?? false }

    @objc var scriptLampStatus: String { scriptTarget().map(lampStatusSummary) ?? "" }

    @objc var scriptFavorites: [String] { scriptTarget()?.favoriteNames ?? [] }

    @objc var scriptRotationPreset: String { scriptTarget()?.rotationPresetName ?? "" }

    // MARK: Lamp values

    @objc var scriptBrightness: Int {
        get {
            guard let target = scriptTarget() else { return 0 }
            guard target.isLampConnected else { reportScriptError(AutomationError.lampNotConnected); return 0 }
            return target.lampBrightness ?? 0
        }
        set { scriptRun { try $0.setBrightness(newValue) } }
    }

    @objc var scriptColorTemperature: Int {
        get {
            guard let target = scriptTarget() else { return 0 }
            guard target.isLampConnected else { reportScriptError(AutomationError.lampNotConnected); return 0 }
            return target.lampTemperature ?? 0
        }
        set { scriptRun { try $0.setTemperature(newValue) } }
    }

    // MARK: Settings (same as the control panel buttons)

    @objc var scriptLight: Bool {
        get { scriptIsOn(.light) }
        set { scriptSet(.light, newValue) }
    }

    @objc var scriptAutoTemperature: Bool {
        get { scriptIsOn(.autoTemperature) }
        set { scriptSet(.autoTemperature, newValue) }
    }

    @objc var scriptAutoLight: Bool {
        get { scriptIsOn(.autoLight) }
        set { scriptSet(.autoLight, newValue) }
    }

    @objc var scriptPresence: Bool {
        get { scriptIsOn(.presence) }
        set { scriptSet(.presence, newValue) }
    }

    @objc var scriptVideoMode: Bool {
        get { scriptIsOn(.videoMode) }
        set { scriptSet(.videoMode, newValue) }
    }

    @objc var scriptMatchScreen: Bool {
        get { scriptIsOn(.matchScreen) }
        set { scriptSet(.matchScreen, newValue) }
    }

    @objc var scriptLinkScreens: Bool {
        get { scriptIsOn(.linkScreens) }
        set { scriptSet(.linkScreens, newValue) }
    }

    @objc var scriptSleepSync: Bool {
        get { scriptIsOn(.sleepSync) }
        set { scriptSet(.sleepSync, newValue) }
    }

    @objc var scriptKeepAwake: Bool {
        get { scriptIsOn(.keepAwake) }
        set { scriptSet(.keepAwake, newValue) }
    }

    @objc var scriptBuiltinDisplay: Bool {
        get { scriptIsOn(.builtinDisplay) }
        set { scriptSet(.builtinDisplay, newValue) }
    }

    // MARK: Commands

    @objc func handleQuitScriptCommand(_ command: NSScriptCommand) -> Any? {
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return nil
    }

    @objc func handleToggleLightScriptCommand(_ command: NSScriptCommand) -> Any? {
        scriptRun { try $0.setFeature(.light, on: !$0.isOn(.light)) }
        return nil
    }

    @objc func handleApplyFavoriteScriptCommand(_ command: NSScriptCommand) -> Any? {
        let name = (command.directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        scriptRun { try $0.applyFavorite(named: name) }
        return nil
    }

    @objc func handleApplyRotationPresetScriptCommand(_ command: NSScriptCommand) -> Any? {
        scriptRun { try $0.applyRotationPresetFromAutomation() }
        return nil
    }

    @objc func handleShowControlPanelScriptCommand(_ command: NSScriptCommand) -> Any? {
        scriptRun { $0.showControlPanel() }
        return nil
    }
}
