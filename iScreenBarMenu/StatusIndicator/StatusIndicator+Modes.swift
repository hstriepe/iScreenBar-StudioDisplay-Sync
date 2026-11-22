import AppKit

extension StatusIndicator {
    @objc func presetChanged(_ sender: NSMenuItem) {
        let index = sender.tag
        let preset: (brightness: Int, temperature: Int, video: Bool)
        if (index == 0 || index >= 3),
           let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let saved = try? JSONDecoder().decode(SavedMode.self, from: data) {
            preset = (saved.brightness, saved.temperature, saved.videoMode)
        } else {
            switch index {
            case 1: preset = (30, 4000, false)
            case 2: preset = (20, 3000, false)
            default: preset = (47, 5500, false)
            }
        }
        isBrightnessFollowEnabled = false
        brightnessFollowSwitch.state = .off
        UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(preset.brightness)
        _ = lamp.setTemperature(preset.temperature)
        _ = lamp.setVideoMode(enabled: preset.video)
        refreshControls()
        modeButton.title = sender.title
        log("Applied mode preset: \(sender.title)")
        lamp.requestStatus()
    }

    @objc func showModeMenu() {
        let menu = NSMenu()
        for (index, title) in modeNames().enumerated() {
            let item = NSMenuItem(title: title, action: #selector(presetChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if title == modeButton.title { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let center = NSMenuItem(title: String(localized: "Mode Center…"), action: #selector(showModeCenter), keyEquivalent: "")
        center.target = self
        menu.addItem(center)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeButton.bounds.height + 4), in: modeButton)
    }

    func modeNames() -> [String] {
        var names = [String(localized: "Favorite"), String(localized: "Night Work"), String(localized: "Wind Down")]
        if let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let mode = try? JSONDecoder().decode(SavedMode.self, from: data),
           !names.contains(mode.name) {
            names.append(mode.name)
        }
        return names
    }

    @objc func showModeCenter() {
        if let window = modeCenterWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 270),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Mode Center")
        let title = NSTextField(labelWithString: String(localized: "Mode Center"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: String(localized: "Quickly switch between lighting presets"))
        subtitle.font = UIStyle.bodyFont
        subtitle.textColor = .secondaryLabelColor
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 1
        rows.wantsLayer = true
        rows.layer?.cornerRadius = 10
        rows.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for (index, name) in modeNames().enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(modeCenterPresetChanged(_:)))
            button.tag = index
            button.isBordered = false
            button.setAccessibilityTitle(name)
            button.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: name)
            label.font = UIStyle.bodyFont
            label.translatesAutoresizingMaskIntoConstraints = false
            let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            chevron.translatesAutoresizingMaskIntoConstraints = false
            let row = NSView()
            row.addSubview(button)
            row.addSubview(label)
            row.addSubview(chevron)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 44),
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.heightAnchor.constraint(equalToConstant: 14)
            ])
            rows.addArrangedSubview(row)
        }
        let add = NSButton(title: String(localized: "New Scene Mode"), target: self, action: #selector(saveCurrentMode))
        add.bezelStyle = .rounded
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        let bind = NSButton(title: String(localized: "Bind App"), target: self, action: #selector(bindCurrentModeToApp))
        bind.bezelStyle = .rounded
        bind.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bind.imagePosition = .imageLeading
        let leadingSpace = NSView()
        let trailingSpace = NSView()
        leadingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [leadingSpace, add, bind, trailingSpace])
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.distribution = .fill
        actions.widthAnchor.constraint(equalToConstant: 512).isActive = true
        leadingSpace.widthAnchor.constraint(equalTo: trailingSpace.widthAnchor).isActive = true
        let stack = NSStackView(views: [title, subtitle, rows, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            rows.widthAnchor.constraint(equalToConstant: 512)
        ])
        window.contentView = content
        window.isReleasedWhenClosed = false
        if let screen = item.button?.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                          y: visible.midY - frame.height / 2))
        } else {
            window.center()
        }
        modeCenterWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func modeCenterPresetChanged(_ sender: NSButton) {
        let item = NSMenuItem(title: modeNames()[sender.tag], action: nil, keyEquivalent: "")
        item.tag = sender.tag
        presetChanged(item)
    }

    @objc private func saveCurrentMode() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else {
            log("Lamp status not available yet; cannot save mode")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save New Mode")
        alert.informativeText = String(localized: "Saves the current brightness, color temperature, and video mode.")
        let field = NSTextField(string: String(localized: "My Mode"))
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let mode = SavedMode(name: field.stringValue.isEmpty ? String(localized: "My Mode") : field.stringValue,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: "savedCustomMode")
            modeButton.title = mode.name
            log("Saved mode: \(mode.name)")
            modeCenterWindow?.close()
            modeCenterWindow = nil
        }
    }

    @objc func bindCurrentModeToApp() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an App to Bind")
        panel.prompt = String(localized: "Bind")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let mode = SavedMode(name: url.deletingPathExtension().lastPathComponent,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        var mappings = loadAppModes()
        mappings[bundleID] = mode
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "appModes")
            bindAppButton.title = String(localized: "Bound: \(mode.name)")
            log("Bound app mode: \(mode.name)")
        }
    }

    func applyModeForFrontmostAppIfNeeded() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundleID != lastFrontmostBundleID else { return }
        lastFrontmostBundleID = bundleID
        guard let mode = loadAppModes()[bundleID] else { return }
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(mode.brightness)
        _ = lamp.setTemperature(mode.temperature)
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        log("Applied app mode: \(mode.name)")
    }

    private func loadAppModes() -> [String: SavedMode] {
        guard let data = UserDefaults.standard.data(forKey: "appModes") else { return [:] }
        return (try? JSONDecoder().decode([String: SavedMode].self, from: data)) ?? [:]
    }
}
