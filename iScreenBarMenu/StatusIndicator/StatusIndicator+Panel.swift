import AppKit

extension StatusIndicator {
    func configurePanel() {
        powerSwitch.target = self
        powerSwitch.action = #selector(powerChanged)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = false
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        temperatureSlider.isContinuous = false
        temperatureSlider.numberOfTickMarks = 5
        temperatureSlider.tickMarkPosition = .below
        timeTemperatureSwitch.target = self
        timeTemperatureSwitch.action = #selector(timeTemperatureChanged)
        timeTemperatureSwitch.toolTip = String(localized: "Adjust color temperature automatically by time of day")
        autoLightSwitch.target = self
        autoLightSwitch.action = #selector(autoLightChanged)
        autoLightSwitch.toolTip = String(localized: "Turn the lamp's auto-light on or off with the official HID command")
        presenceSwitch.target = self
        presenceSwitch.action = #selector(presenceChanged)
        for seconds in presenceDelayOptions {
            let title = String(localized: "\(seconds / 60) min")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = seconds
            presenceDelayPopup.menu?.addItem(item)
        }
        presenceDelayPopup.target = self
        presenceDelayPopup.action = #selector(presenceDelayChanged)
        selectPresenceDelay(presenceDelaySeconds)
        for (title, value) in [(String(localized: "Low"), 0), (String(localized: "Medium"), 1), (String(localized: "High"), 2)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = value
            presenceSensitivityPopup.menu?.addItem(item)
        }
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        presenceSensitivityPopup.target = self
        presenceSensitivityPopup.action = #selector(presenceSensitivityChanged)
        presenceWakeSwitch.target = self
        presenceWakeSwitch.action = #selector(presenceWakeChanged)
        presenceWakeSwitch.toolTip = String(localized: "Wake the display when presence detection turns the lamp back on. Needs Presence and Sleep Sync")
        videoModeSwitch.target = self
        videoModeSwitch.action = #selector(videoModeChanged)
        modeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        modeButton.imagePosition = .imageTrailing
        modeButton.alignment = .left
        modeButton.bezelStyle = .rounded
        modeButton.controlSize = .large
        modeButton.font = UIStyle.bodyFont
        modeButton.target = self
        modeButton.action = #selector(showModeMenu)
        bindAppButton.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bindAppButton.imagePosition = .imageLeading
        bindAppButton.bezelStyle = .roundRect
        bindAppButton.controlSize = .small
        bindAppButton.target = self
        bindAppButton.action = #selector(bindCurrentModeToApp)
        brightnessFollowSwitch.target = self
        brightnessFollowSwitch.action = #selector(brightnessFollowChanged)
        displayBrightnessLockSwitch.target = self
        displayBrightnessLockSwitch.action = #selector(displayBrightnessLockChanged)
        displayBrightnessLockSwitch.toolTip = String(localized: "Locks the current brightness difference between the MacBook display and Studio Display; adjusting either one moves both")
        powerSyncSwitch.target = self
        powerSyncSwitch.action = #selector(powerSyncChanged)
        keepAwakeSwitch.target = self
        keepAwakeSwitch.action = #selector(keepAwakeChanged)
        keepAwakeSwitch.toolTip = String(localized: "Prevents sleep on battery, on power, or with the lid closed; needs administrator authorization the first time")
        captureBrightButton.target = self
        captureBrightButton.action = #selector(captureBrightThreshold)
        captureBrightButton.setButtonType(.momentaryPushIn)
        captureBrightButton.toolTip = String(localized: "Click to save the current ambient value as the bright (light off) point")
        captureDarkButton.target = self
        captureDarkButton.action = #selector(captureDarkThreshold)
        captureDarkButton.setButtonType(.momentaryPushIn)
        captureDarkButton.toolTip = String(localized: "Click to save the current ambient value as the dim (light on) point")
        ambientEnableSwitch.target = self
        ambientEnableSwitch.action = #selector(ambientEnableChanged)
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
        }
        ambientStatusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        ambientStatusLabel.textColor = .secondaryLabelColor
        displayPowerSwitch.target = self
        displayPowerSwitch.action = #selector(displayPowerChanged)
        studioPowerSwitch.target = self
        studioPowerSwitch.action = #selector(studioPowerChanged)
        studioPowerSwitch.toolTip = String(localized: "Pure black overlay; doesn't disconnect the display or change window layout. Double-click the black screen or click the button again to restore")
        displayRotateButton.setButtonType(.momentaryPushIn)
        displayRotateButton.target = self
        displayRotateButton.action = #selector(displayRotationChanged)
        displayAutoPresetSwitch.target = self
        displayAutoPresetSwitch.action = #selector(displayAutoPresetChanged)
        rotationModeButton.title = loadRotationPreset().name
        rotationModeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        rotationModeButton.imagePosition = .imageTrailing
        rotationModeButton.alignment = .left
        rotationModeButton.bezelStyle = .rounded
        rotationModeButton.controlSize = .large
        rotationModeButton.font = UIStyle.bodyFont
        rotationModeButton.target = self
        rotationModeButton.action = #selector(showRotationModeMenu)

        [brightnessSlider, temperatureSlider].forEach { $0.controlSize = .small }
        [presenceDelayPopup, presenceSensitivityPopup].forEach { $0.controlSize = .small }
        brightnessValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        brightnessValueLabel.textColor = .secondaryLabelColor
        temperatureValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        temperatureValueLabel.textColor = .secondaryLabelColor

        let brightnessRow = sliderRow(symbol: "sun.max", title: String(localized: "Brightness"), slider: brightnessSlider, valueLabel: brightnessValueLabel)
        let temperatureRow = sliderRow(symbol: "thermometer.medium", title: String(localized: "Color Temp"), slider: temperatureSlider, valueLabel: temperatureValueLabel)
        let delayField = optionField(symbol: "clock", title: String(localized: "Away Delay"), control: presenceDelayPopup)
        let sensitivityField = optionField(symbol: "gauge", title: String(localized: "Sensitivity"), control: presenceSensitivityPopup)
        let presenceOptions = NSStackView(views: [delayField, sensitivityField])
        presenceOptions.orientation = .horizontal
        presenceOptions.alignment = .top
        presenceOptions.spacing = 12
        delayField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        sensitivityField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let featureTitle = sectionLabel(String(localized: "Quick Controls"))
        let featureGrid = NSGridView(views: [
            [powerSwitch, autoLightSwitch, presenceSwitch],
            [videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch],
            [timeTemperatureSwitch, displayBrightnessLockSwitch, keepAwakeSwitch]
        ])
        featureGrid.rowSpacing = 6
        featureGrid.columnSpacing = 6
        featureGrid.xPlacement = .fill
        for button in [powerSwitch, autoLightSwitch, presenceSwitch, videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch, timeTemperatureSwitch, displayBrightnessLockSwitch, keepAwakeSwitch] {
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let featureContainer = NSStackView(views: [featureTitle, featureGrid])
        featureContainer.orientation = .vertical
        featureContainer.alignment = .leading
        featureContainer.spacing = UIStyle.sectionSpacing

        let adjustmentTitle = sectionLabel(String(localized: "Light Adjustment"))
        let adjustmentContainer = NSStackView(views: [adjustmentTitle, brightnessRow, temperatureRow])
        adjustmentContainer.orientation = .vertical
        adjustmentContainer.alignment = .leading
        adjustmentContainer.spacing = 8

        let presetTitle = sectionLabel(String(localized: "Light Presets"))
        modeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        modeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let rotationPresetTitle = sectionLabel(String(localized: "Rotation Preset"))
        rotationModeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        rotationModeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let presetContainer = NSStackView(views: [presetTitle, modeButton, rotationPresetTitle, rotationModeButton])
        presetContainer.orientation = .vertical
        presetContainer.alignment = .leading
        presetContainer.spacing = UIStyle.sectionSpacing

        let presenceTitle = sectionLabel(String(localized: "Presence Detection"))
        let presenceWakeLabel = NSTextField(labelWithString: String(localized: "Wake Screen"))
        presenceWakeLabel.font = UIStyle.bodyFont
        presenceWakeLabel.textColor = .secondaryLabelColor
        let presenceHeader = NSStackView(views: [presenceTitle, flexibleSpace(), presenceWakeLabel, presenceWakeSwitch])
        presenceHeader.orientation = .horizontal
        presenceHeader.alignment = .centerY
        presenceHeader.spacing = 6
        presenceHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        let presenceContainer = NSStackView(views: [presenceHeader, presenceOptions])
        presenceContainer.orientation = .vertical
        presenceContainer.alignment = .leading
        presenceContainer.spacing = UIStyle.sectionSpacing

        let ambientTitle = sectionLabel(String(localized: "Ambient Light Calibration"))
        let ambientEnableLabel = NSTextField(labelWithString: String(localized: "Enable"))
        ambientEnableLabel.font = UIStyle.bodyFont
        ambientEnableLabel.textColor = .secondaryLabelColor
        let ambientHeader = NSStackView(views: [ambientTitle, flexibleSpace(), ambientEnableLabel, ambientEnableSwitch])
        ambientHeader.orientation = .horizontal
        ambientHeader.alignment = .centerY
        ambientHeader.spacing = 6
        ambientHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        for button in [captureBrightButton, captureDarkButton] {
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.widthAnchor.constraint(equalToConstant: 34).isActive = true
        }
        let brightCapture = NSStackView(views: [captureBrightButton, brightThresholdLabel])
        brightCapture.orientation = .horizontal
        brightCapture.alignment = .centerY
        brightCapture.spacing = 4
        let darkCapture = NSStackView(views: [captureDarkButton, darkThresholdLabel])
        darkCapture.orientation = .horizontal
        darkCapture.alignment = .centerY
        darkCapture.spacing = 4
        let ambientActions = NSStackView(views: [brightCapture, darkCapture])
        ambientActions.orientation = .horizontal
        ambientActions.alignment = .centerY
        ambientActions.spacing = 12
        ambientActions.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        ambientStatusLabel.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        let ambientContainer = NSStackView(views: [ambientHeader, ambientActions, ambientStatusLabel])
        ambientContainer.orientation = .vertical
        ambientContainer.alignment = .leading
        ambientContainer.spacing = 6

        let displayGrid = NSGridView(views: [[displayPowerSwitch, displayRotateButton], [studioPowerSwitch, NSView()]])
        displayGrid.rowSpacing = 6
        displayGrid.columnSpacing = 6
        displayGrid.xPlacement = .fill
        for button in [displayPowerSwitch, studioPowerSwitch, displayRotateButton] {
            button.widthAnchor.constraint(equalToConstant: 153).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let displayTitle = sectionLabel(String(localized: "Displays & Rotation"))
        let displayContainer = NSStackView(views: [displayTitle, displayGrid])
        displayContainer.orientation = .vertical
        displayContainer.alignment = .leading
        displayContainer.spacing = UIStyle.sectionSpacing

        let autoPresetLabel = NSTextField(labelWithString: String(localized: "Enable Preset"))
        autoPresetLabel.font = UIStyle.bodyFont
        autoPresetLabel.textColor = .secondaryLabelColor
        let rotationPresetHeader = NSStackView(views: [rotationPresetTitle, flexibleSpace(), autoPresetLabel, displayAutoPresetSwitch])
        rotationPresetHeader.orientation = .horizontal
        rotationPresetHeader.alignment = .centerY
        rotationPresetHeader.spacing = 6
        rotationPresetHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        presetContainer.setViews([presetTitle, modeButton, rotationPresetHeader, rotationModeButton], in: .top)

        let aboutButton = NSButton(title: String(localized: "About…"), target: self, action: #selector(showAbout))
        let helpButton = NSButton(title: String(localized: "Help…"), target: self, action: #selector(showHelp))
        let quitButton = NSButton(title: String(localized: "Quit"), target: self, action: #selector(quitApp))
        for button in [aboutButton, helpButton, quitButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = UIStyle.captionFont
        }
        let footer = NSStackView(views: [flexibleSpace(), aboutButton, helpButton, quitButton])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true

        let displaySeparator = separator()
        displaySectionViews = [displaySeparator, displayContainer]
        rotationPresetViews = [rotationPresetHeader, rotationModeButton]
        let stack = NSStackView(views: [featureContainer, separator(), adjustmentContainer,
                                       separator(), ambientContainer, separator(), presenceContainer, displaySeparator, displayContainer,
                                       separator(), presetContainer, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: UIStyle.outerInset, bottom: 14, right: UIStyle.outerInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [brightnessRow, temperatureRow, presenceOptions] {
            view.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        }

        // Panel height fits the content (localized labels can change row heights); recomputed on open.
        panelStack = stack
        updateDisplaySectionVisibility()
        let panelHeight = ceil(stack.fittingSize.height)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: UIStyle.panelWidth, height: panelHeight))
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: controller.view.bottomAnchor)
        ])
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: UIStyle.panelWidth, height: panelHeight)
        log("Control panel height: \(Int(panelHeight)) pt")
        popover.behavior = .transient
    }

    private func sliderRow(symbol: String, title: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let label = rowLabel(title)
        // Label column fits the widest localized slider title; the slider absorbs the difference.
        label.widthAnchor.constraint(equalToConstant: sliderLabelWidth).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 216 - sliderLabelWidth).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let row = NSStackView(views: [symbolView(symbol), label, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func optionField(symbol: String, title: String, control: NSView) -> NSStackView {
        let heading = NSStackView(views: [symbolView(symbol), rowLabel(title)])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 6
        let field = NSStackView(views: [heading, control])
        field.orientation = .vertical
        field.alignment = .leading
        field.spacing = 5
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return field
    }

    private func optionsRow(symbol: String, title: String, controls: [NSView]) -> NSStackView {
        let row = NSStackView(views: [symbolView(symbol), rowLabel(title), flexibleSpace()] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func symbolView(_ name: String) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.symbolConfiguration = .init(pointSize: UIStyle.iconSize, weight: .regular)
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.bodyFont
        return label
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.captionFont
        label.textColor = .secondaryLabelColor
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func separator() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        return divider
    }

    /// Display and rotation controls only act on a built-in display (or a second screen). A desktop Mac with
    /// just the Studio Display has nothing to switch or rotate, so the section is hidden there.
    var showsDisplaySection: Bool {
        displayController.builtinDisplay() != nil || displayController.externalDisplays().count > 1
    }

    private func updateDisplaySectionVisibility() {
        let hidden = !showsDisplaySection
        var changed = false
        for view in displaySectionViews + rotationPresetViews where view.isHidden != hidden {
            view.isHidden = hidden
            changed = true
        }
        // The panel is sized when it opens; resize it if a display was added or removed while it is open.
        if changed, popover.isShown, let panelStack {
            popover.contentSize = NSSize(width: UIStyle.panelWidth, height: ceil(panelStack.fittingSize.height))
        }
    }

    func refreshControls() {
        updateDisplaySectionVisibility()
        let displayControlsAllowed = isDisplaySessionSafe && !isConsoleSessionLocked()
        let studioID = displayController.studioTarget()
        studioPowerSwitch.state = studioID != nil && !displayController.isStudioCovered ? .on : .off
        studioPowerSwitch.isEnabled = displayControlsAllowed && studioID != nil
        powerSwitch.state = lamp.isPowerOn == true ? .on : .off
        let autoLightChangePending = autoLightChangePendingUntil.map { Date() < $0 } ?? false
        if isAmbientPresenceLockActive {
            autoLightSwitch.title = autoLightWasEnabledBeforeAmbientLock ? String(localized: "Auto Light Paused") : String(localized: "Auto Light")
            autoLightSwitch.state = autoLightWasEnabledBeforeAmbientLock ? .on : .off
            autoLightSwitch.toolTip = autoLightWasEnabledBeforeAmbientLock
                ? String(localized: "Was on; paused while the ambient off-lock is active and restored automatically afterward")
                : String(localized: "Auto light can't be turned on while the ambient off-lock is active")
        } else if autoLightChangePending, let pendingAutoLightState {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightSwitch.state = pendingAutoLightState ? .on : .off
            autoLightSwitch.toolTip = pendingAutoLightState ? String(localized: "Turning auto light on…") : String(localized: "Turning auto light off…")
        } else if lamp.isAutoLightEnabled == true {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .on
            autoLightSwitch.toolTip = String(localized: "Turn off auto light")
        } else {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .off
            autoLightSwitch.toolTip = String(localized: "Turn on auto light")
        }
        if isAmbientPresenceLockActive || isScreenSleepPresenceLockActive {
            let wasEnabled = presenceWasEnabledBeforeAmbientLock || presenceWasEnabledBeforeScreenSleep
            presenceSwitch.title = wasEnabled ? String(localized: "Presence Paused") : String(localized: "Presence")
            presenceSwitch.state = wasEnabled ? .on : .off
            presenceSwitch.toolTip = wasEnabled
                ? String(localized: "Was on; paused while the light-off lock is active and restored automatically afterward")
                : String(localized: "Presence detection can't be turned on while the light-off lock is active")
        } else {
            presenceSwitch.title = String(localized: "Presence")
            presenceSwitch.state = lamp.isPresenceDetectionEnabled == true ? .on : .off
            presenceSwitch.toolTip = String(localized: "Turn the lamp's presence detection on or off")
        }
        videoModeSwitch.state = lamp.isVideoModeEnabled == true ? .on : .off
        brightnessFollowSwitch.state = isBrightnessFollowEnabled ? .on : .off
        displayBrightnessLockSwitch.state = isDisplayBrightnessLockEnabled ? .on : .off
        displayBrightnessLockSwitch.isEnabled = displayControlsAllowed && studioDisplayID() != nil && activeBuiltinDisplayID() != nil
        powerSyncSwitch.state = isPowerSyncEnabled ? .on : .off
        presenceWakeSwitch.state = isPresenceWakeEnabled ? .on : .off
        keepAwakeSwitch.state = keepAwakeController.isActive ? .on : .off
        timeTemperatureSwitch.state = isTimeTemperatureEnabled ? .on : .off
        updateAmbientStatusLabel()
        if let builtin = displayController.builtinDisplay() {
            let online = CGDisplayIsOnline(builtin) != 0
            displayPowerSwitch.state = online ? .on : .off
            displayPowerSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable
            displayRotateButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            rotationModeButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            displayRotateButton.title = online ? String(localized: "Rotate \(Int(CGDisplayRotation(builtin).rounded()))°") : String(localized: "Rotate —")
        } else {
            displayPowerSwitch.state = .off
            displayPowerSwitch.isEnabled = false
            displayRotateButton.isEnabled = false
            rotationModeButton.isEnabled = false
            displayRotateButton.title = String(localized: "Rotate —")
        }
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .on : .off
        displayAutoPresetSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable && displayController.builtinDisplay() != nil
        rotationModeButton.title = loadRotationPreset().name
        selectPresenceDelay(presenceDelaySeconds)
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        if let brightness = lamp.currentBrightness {
            brightnessSlider.doubleValue = Double(brightness)
            brightnessValueLabel.stringValue = "\(brightness)%"
        }
        if let temperature = lamp.currentTemperature {
            temperatureSlider.doubleValue = Double(temperature)
            temperatureValueLabel.stringValue = "\(temperature)K"
        }
        let enabled = lamp.isConnected
        powerSwitch.isEnabled = enabled
        autoLightSwitch.isEnabled = enabled && !isAmbientPresenceLockActive
        brightnessSlider.isEnabled = enabled
        temperatureSlider.isEnabled = enabled && !isTimeTemperatureEnabled
        timeTemperatureSwitch.isEnabled = enabled
        presenceSwitch.isEnabled = enabled && !isAmbientPresenceLockActive && !isScreenSleepPresenceLockActive
        videoModeSwitch.isEnabled = enabled
        powerSyncSwitch.isEnabled = enabled
        updateAmbientControlAvailability()
        presenceDelayPopup.isEnabled = enabled
        presenceSensitivityPopup.isEnabled = enabled
        // Turning it off stays possible even without Sleep Sync, so the setting is never stuck on.
        presenceWakeSwitch.isEnabled = enabled && (isPowerSyncEnabled || isPresenceWakeEnabled)
    }

    func updateIcon(healthy: Bool) {
        let iconColor: NSColor
        if !healthy {
            iconColor = .systemRed
        } else if lamp.isPowerOn == true {
            iconColor = .systemYellow
        } else {
            iconColor = .systemGray
        }
        // 15 pt is ~2 px larger than the default status-item symbol size.
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        let symbol = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: String(localized: "iScreenBar status"))?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        item.button?.attributedTitle = NSAttributedString(string: "")
        item.button?.image = symbol
    }
}
