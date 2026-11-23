import AppKit

final class StatusIndicator: NSObject, NSMenuDelegate {
    let presenceDelayOptions = [180, 300, 600]
    let item: NSStatusItem
    let lamp: LampController
    let popover = NSPopover()
    let powerSwitch = FeatureButton(title: String(localized: "Light"), symbol: "power", accentColor: activeControlColor)
    let brightnessSlider = InteractiveSlider(value: 50, minValue: 1, maxValue: 100, activeColor: .systemBlue)
    let brightnessValueLabel = NSTextField(labelWithString: "50%")
    let temperatureSlider = InteractiveSlider(value: 5000, minValue: 2700, maxValue: 6500, activeColor: .systemYellow)
    let temperatureValueLabel = NSTextField(labelWithString: "5000K")
    let timeTemperatureSwitch = FeatureButton(title: String(localized: "Auto Temp"), symbol: "circle.lefthalf.filled", accentColor: activeControlColor)
    let autoLightSwitch = FeatureButton(title: String(localized: "Auto Light"), symbol: "sun.max", accentColor: activeControlColor)
    let presenceSwitch = FeatureButton(title: String(localized: "Presence"), symbol: "figure.seated.side", accentColor: activeControlColor)
    let presenceDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let presenceSensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let presenceWakeSwitch = AccentSwitch()
    var presenceDelaySeconds = 180
    var presenceSensitivity = 2
    let videoModeSwitch = FeatureButton(title: String(localized: "Video Mode"), symbol: "video", accentColor: activeControlColor)
    let modeButton = NSButton(title: String(localized: "Favorite"), target: nil, action: nil)
    let rotationModeButton = NSButton(title: String(localized: "Portrait Dual"), target: nil, action: nil)
    var modeCenterController: ModeCenterWindowController?
    var helpWindowController: HelpWindowController?
    var panelStack: NSStackView?
    var displaySectionViews: [NSView] = []
    var rotationPresetViews: [NSView] = []
    let brightnessFollowSwitch = FeatureButton(title: String(localized: "Match Screen"), symbol: "display", accentColor: activeControlColor)
    let displayBrightnessLockSwitch = FeatureButton(title: String(localized: "Link Screens"), symbol: "rectangle.on.rectangle", accentColor: activeControlColor)
    let powerSyncSwitch = FeatureButton(title: String(localized: "Sleep Sync"), symbol: "moon.zzz", accentColor: activeControlColor)
    let keepAwakeSwitch = FeatureButton(title: String(localized: "Keep Awake"), symbol: "cup.and.saucer", accentColor: activeControlColor)
    let keepAwakeController = KeepAwakeController()
    let captureBrightButton = FeatureButton(title: String(localized: "Bright: Off"), symbol: "sun.max.fill", accentColor: .systemOrange)
    let captureDarkButton = FeatureButton(title: String(localized: "Dim: On"), symbol: "moon.fill", accentColor: .systemBlue)
    let ambientEnableSwitch = AccentSwitch()
    let brightThresholdLabel = NSTextField(labelWithString: "--")
    let darkThresholdLabel = NSTextField(labelWithString: "--")
    let ambientStatusLabel = NSTextField(labelWithString: String(localized: "Ambient light not calibrated yet"))
    let displayPowerSwitch: FeatureButton = {
        let button = FeatureButton(title: String(localized: "Built-in"), symbol: "display", accentColor: activeControlColor)
        button.image = displayPowerIcon()
        return button
    }()
    let displayRotateButton = FeatureButton(title: String(localized: "Rotate \(0)°"), symbol: "arrow.clockwise", accentColor: activeControlColor)
    let studioPowerSwitch = FeatureButton(title: "Studio Display", symbol: "display", accentColor: activeControlColor)
    let displayAutoPresetSwitch = AccentSwitch()
    let displayController = DisplayController()
    var isBrightnessFollowEnabled: Bool
    /// Set when Match Screen should re-lock its offset to the lamp's new brightness (a mode was applied while on).
    var brightnessFollowReanchorRequested = false
    var isDisplayBrightnessLockEnabled: Bool
    var isPowerSyncEnabled: Bool
    var isPresenceWakeEnabled: Bool
    var isTimeTemperatureEnabled: Bool
    var ambientCloseThreshold: Int?
    var ambientOpenThreshold: Int?
    var currentDisplayAmbientProxy: Int?
    var currentAmbientSourceName = "display"
    var ambientThresholdSource: String?
    var areAmbientRulesEnabled: Bool
    var isDisplayAutoPresetEnabled: Bool
    var isHealthy = true
    var isAsleep: Bool
    var autoLightChangePendingUntil: Date?
    var pendingAutoLightState: Bool?
    var lastScheduledTemperature: Int?
    var lastScheduledTemperatureChangeAt = Date.distantPast
    var lastFrontmostBundleID: String?
    var isAmbientPresenceLockActive = false
    var presenceWasEnabledBeforeAmbientLock = false
    var autoLightWasEnabledBeforeAmbientLock = false
    var isScreenSleepPresenceLockActive = false
    var presenceWasEnabledBeforeScreenSleep = false
    var isDisplaySessionSafe = false
    var pendingDisplayConnectionState: Bool?
    var pendingDisplayPolicyWorkItem: DispatchWorkItem?
    var pendingBuiltinWakeWorkItems: [DispatchWorkItem] = []
    var didRequestDisplaySleepForCurrentLidClosure = false

    var isBuiltinManuallyDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: "builtinManuallyDisabled") }
        set { UserDefaults.standard.set(newValue, forKey: "builtinManuallyDisabled") }
    }

    lazy var sliderLabelWidth: CGFloat = {
        let titles = [String(localized: "Brightness"), String(localized: "Color Temp")]
        let widest = titles.map { ceil(rowLabel($0).fittingSize.width) }.max() ?? 32
        return min(max(32, widest), 96)
    }()

    init(isAsleep: Bool, lamp: LampController) {
        self.lamp = lamp
        self.isAsleep = isAsleep
        isBrightnessFollowEnabled = UserDefaults.standard.bool(forKey: "brightnessFollowEnabled")
        isDisplayBrightnessLockEnabled = UserDefaults.standard.bool(forKey: "displayBrightnessLockEnabled")
        isPowerSyncEnabled = UserDefaults.standard.object(forKey: "powerSyncEnabled") as? Bool ?? true
        isPresenceWakeEnabled = UserDefaults.standard.bool(forKey: "presenceWakeEnabled")
        isTimeTemperatureEnabled = UserDefaults.standard.bool(forKey: "timeTemperatureEnabled")
        ambientCloseThreshold = UserDefaults.standard.object(forKey: "ambientCloseThreshold") as? Int
        ambientOpenThreshold = UserDefaults.standard.object(forKey: "ambientOpenThreshold") as? Int
        ambientThresholdSource = UserDefaults.standard.string(forKey: "ambientThresholdSource")
        areAmbientRulesEnabled = UserDefaults.standard.object(forKey: "ambientRulesEnabled") as? Bool
            ?? (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
        UserDefaults.standard.removeObject(forKey: "ambientLinkEnabled")
        if ambientThresholdSource != "studioDisplayALS-v1" {
            ambientCloseThreshold = nil
            ambientOpenThreshold = nil
            areAmbientRulesEnabled = false
        }
        presenceWasEnabledBeforeAmbientLock = UserDefaults.standard.bool(forKey: "ambientSuspendedPresenceWasEnabled")
        autoLightWasEnabledBeforeAmbientLock = UserDefaults.standard.bool(forKey: "ambientSuspendedAutoLightWasEnabled")
        isAmbientPresenceLockActive = presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock
        presenceWasEnabledBeforeScreenSleep = UserDefaults.standard.bool(forKey: "screenSleepSuspendedPresenceWasEnabled")
        isScreenSleepPresenceLockActive = presenceWasEnabledBeforeScreenSleep
        isDisplayAutoPresetEnabled = UserDefaults.standard.bool(forKey: "displayAutoPresetEnabled")
        presenceDelaySeconds = UserDefaults.standard.object(forKey: "presenceDelaySeconds") as? Int ?? 180
        if !presenceDelayOptions.contains(presenceDelaySeconds) {
            presenceDelaySeconds = 180
        }
        presenceSensitivity = UserDefaults.standard.object(forKey: "presenceSensitivity") as? Int ?? 2
        presenceSensitivity = max(0, min(2, presenceSensitivity))
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        installHiddenMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        migrateDisplayPresetIfNeeded()
        LoginItem.replaceLegacyAgentIfNeeded()
        configurePanel()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe(_:)),
                                           name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe(_:)),
                                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        scheduleDisplaySessionActivation()
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        self.isAsleep = isAsleep
        isHealthy = healthy
        handleKeepAwakeLidDisplayState()
        if lamp.isAutoLightEnabled == true, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            log("Lamp auto-light is on; turned off Studio Display brightness follow")
        }
        updateIcon(healthy: healthy)
        let displayState = isAsleep ? "Studio Display asleep" : "Studio Display awake"
        let brightnessStatus = isBrightnessFollowEnabled ? "brightness follow on" : "brightness follow off"
        let powerStatus = isPowerSyncEnabled ? "sleep sync on" : "sleep sync off"
        let status = healthy ? String(localized: "sync OK") : String(localized: "sync error")
        _ = (displayState, brightnessStatus, powerStatus)
        let brightnessText = healthy ? lamp.currentBrightness.map { "\($0)%" } ?? "--%" : "--%"
        let temperatureText = healthy ? lamp.currentTemperature.map { "\($0)K" } ?? "----K" : "----K"
        item.button?.toolTip = "\(brightnessText) · \(temperatureText)"
        item.button?.setAccessibilityLabel("iScreenBar Menu \(status)")
        if displayController.isStudioCovered,
           (displayController.studioTarget() == nil || isConsoleSessionLocked()) {
            _ = displayController.setStudioEnabled(true)
        }
        if popover.isShown { refreshControls() }
    }

    // Left-click opens the control panel; right-click or Control-click opens the standard menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        lamp.requestStatus()
        let menu = buildStatusMenu()
        menu.delegate = self
        item.menu = menu
        button.performClick(nil)
    }

    // Detach the menu once it closes so the next click reaches statusItemClicked again.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === item.menu else { return }
        DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
    }

    @objc func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            lamp.requestStatus()
            refreshControls()
            if let panelStack {
                popover.contentSize = NSSize(width: UIStyle.panelWidth, height: ceil(panelStack.fittingSize.height))
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func applicationWillTerminate() {
        pendingDisplayPolicyWorkItem?.cancel()
        _ = displayController.setStudioEnabled(true)
        _ = keepAwakeController.setActive(false)
        clearPublishedLampState()
    }
}
