import AppKit
import UniformTypeIdentifiers

// Mode Center: lists the light modes (add, edit, delete, apply) and the app → mode associations (add, change, remove).
// All data lives in ModeStore; the tables are reloaded from it after every change.
final class ModeCenterWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    /// The lamp's current settings and toggles as an unnamed mode; nil while the lamp hasn't reported.
    var currentLampSettings: () -> LightMode? = { nil }
    var applyMode: (LightMode) -> Void = { _ in }
    /// Called after modes or bindings changed (so the panel can refresh its mode title).
    var modesChanged: () -> Void = {}

    private let modesTable = NSTableView()
    private let appsTable = NSTableView()
    private let modeButtons = NSSegmentedControl()
    private let appButtons = NSSegmentedControl()
    private let moveButtons = NSSegmentedControl()
    private let editButton = NSButton()
    private let applyButton = NSButton()
    private var modes: [LightMode] = []
    private var apps: [(bundleID: String, modeID: UUID)] = []

    // Edit sheet controls (valid while the sheet is open).
    private let nameField = NSTextField()
    private let brightnessSlider = NSSlider(value: 50, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let brightnessLabel = NSTextField(labelWithString: "")
    private let temperatureSlider = NSSlider(value: 4000, minValue: 2700, maxValue: 6500, target: nil, action: nil)
    private let temperatureLabel = NSTextField(labelWithString: "")
    private let videoCheckbox = NSButton(checkboxWithTitle: String(localized: "Video Mode"), target: nil, action: nil)
    private let matchScreenCheckbox = NSButton(checkboxWithTitle: String(localized: "Match Screen"), target: nil, action: nil)
    private let autoLightCheckbox = NSButton(checkboxWithTitle: String(localized: "Auto Light"), target: nil, action: nil)
    private let presenceCheckbox = NSButton(checkboxWithTitle: String(localized: "Presence"), target: nil, action: nil)
    private let autoTemperatureCheckbox = NSButton(checkboxWithTitle: String(localized: "Auto Temp"), target: nil, action: nil)

    private static let modeColumn = NSUserInterfaceItemIdentifier("mode")
    private static let brightnessColumn = NSUserInterfaceItemIdentifier("brightness")
    private static let temperatureColumn = NSUserInterfaceItemIdentifier("temperature")
    private static let videoColumn = NSUserInterfaceItemIdentifier("video")
    private static let togglesColumn = NSUserInterfaceItemIdentifier("toggles")
    private static let appColumn = NSUserInterfaceItemIdentifier("app")
    private static let appModeColumn = NSUserInterfaceItemIdentifier("appMode")
    private static let modeRowType = NSPasteboard.PasteboardType("org.windholm.iScreenBarMenu.mode-row")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Mode Center")
        window.minSize = NSSize(width: 580, height: 440)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ModeCenterWindow2")
        super.init(window: window)
        window.contentView = makeContentView()
        if !window.setFrameUsingName("ModeCenterWindow2") { window.center() }
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        let selectedID = selectedMode?.id
        modes = ModeStore.modes
        apps = ModeStore.bindings.map { (bundleID: $0.key, modeID: $0.value) }
            .sorted { Self.appName($0.bundleID).localizedCaseInsensitiveCompare(Self.appName($1.bundleID)) == .orderedAscending }
        modesTable.reloadData()
        appsTable.reloadData()
        // Keep the row that was selected; otherwise select the active mode (or the first one).
        let preferredID = selectedID ?? ModeStore.selectedModeID
        if let row = modes.firstIndex(where: { $0.id == preferredID }) ?? (modes.isEmpty ? nil : 0) {
            modesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        updateButtons()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        configureTable(modesTable, columns: [
            (Self.modeColumn, String(localized: "Name"), 150),
            (Self.brightnessColumn, String(localized: "Brightness"), 80),
            (Self.temperatureColumn, String(localized: "Color Temp"), 90),
            (Self.videoColumn, String(localized: "Video"), 50),
            (Self.togglesColumn, String(localized: "Also Sets"), 170)
        ])
        modesTable.target = self
        modesTable.doubleAction = #selector(editSelectedMode)
        modesTable.registerForDraggedTypes([Self.modeRowType])
        modesTable.draggingDestinationFeedbackStyle = .gap
        configureTable(appsTable, columns: [
            (Self.appColumn, String(localized: "App"), 240),
            (Self.appModeColumn, String(localized: "Mode"), 200)
        ])
        appsTable.rowHeight = 26

        configureAddRemove(modeButtons, action: #selector(modeButtonsClicked(_:)),
                           addHelp: String(localized: "Add a mode from the current lamp settings"),
                           removeHelp: String(localized: "Delete the selected mode"))
        configureAddRemove(appButtons, action: #selector(appButtonsClicked(_:)),
                           addHelp: String(localized: "Choose an app and associate it with the selected mode"),
                           removeHelp: String(localized: "Remove the selected association"))
        moveButtons.segmentCount = 2
        moveButtons.trackingMode = .momentary
        moveButtons.segmentStyle = .smallSquare
        moveButtons.setImage(NSImage(systemSymbolName: "chevron.up", accessibilityDescription: String(localized: "Move Up")), forSegment: 0)
        moveButtons.setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: String(localized: "Move Down")), forSegment: 1)
        moveButtons.setWidth(28, forSegment: 0)
        moveButtons.setWidth(28, forSegment: 1)
        moveButtons.setToolTip(String(localized: "Move Up"), forSegment: 0)
        moveButtons.setToolTip(String(localized: "Move Down"), forSegment: 1)
        moveButtons.target = self
        moveButtons.action = #selector(moveButtonsClicked(_:))
        editButton.title = String(localized: "Edit…")
        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editSelectedMode)
        applyButton.title = String(localized: "Apply")
        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applySelectedMode)
        applyButton.keyEquivalent = "\r"

        let modesBar = NSStackView(views: [modeButtons, moveButtons, spacer(), editButton, applyButton])
        modesBar.orientation = .horizontal
        let appsHint = NSTextField(wrappingLabelWithString: String(localized: "The mode is applied when the app comes to the front."))
        appsHint.font = UIStyle.captionFont
        appsHint.textColor = .secondaryLabelColor
        let appsBar = NSStackView(views: [appButtons, appsHint])
        appsBar.orientation = .horizontal
        appsBar.spacing = 12

        let modesScroll = scrollView(for: modesTable)
        let appsScroll = scrollView(for: appsTable)
        let stack = NSStackView(views: [sectionLabel(String(localized: "Modes")), modesScroll, modesBar,
                                        sectionLabel(String(localized: "App Associations")), appsScroll, appsBar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: modesBar)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            modesScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            appsScroll.widthAnchor.constraint(equalTo: modesScroll.widthAnchor),
            modesBar.widthAnchor.constraint(equalTo: modesScroll.widthAnchor),
            appsBar.widthAnchor.constraint(equalTo: modesScroll.widthAnchor),
            modesScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            appsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
            appsScroll.heightAnchor.constraint(equalTo: modesScroll.heightAnchor, multiplier: 0.8)
        ])
        return content
    }

    private func configureTable(_ table: NSTableView, columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)]) {
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = 50
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    }

    private func configureAddRemove(_ control: NSSegmentedControl, action: Selector, addHelp: String, removeHelp: String) {
        control.segmentCount = 2
        control.trackingMode = .momentary
        control.segmentStyle = .smallSquare
        control.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "Add")), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: String(localized: "Remove")), forSegment: 1)
        control.setWidth(28, forSegment: 0)
        control.setWidth(28, forSegment: 1)
        control.setToolTip(addHelp, forSegment: 0)
        control.setToolTip(removeHelp, forSegment: 1)
        control.target = self
        control.action = action
    }

    private func scrollView(for table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scroll
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }

    private func updateButtons() {
        let hasMode = selectedMode != nil
        modeButtons.setEnabled(hasMode && modes.count > 1, forSegment: 1)
        let row = modesTable.selectedRow
        moveButtons.setEnabled(hasMode && row > 0, forSegment: 0)
        moveButtons.setEnabled(hasMode && row < modes.count - 1, forSegment: 1)
        editButton.isEnabled = hasMode
        applyButton.isEnabled = hasMode
        appButtons.setEnabled(!modes.isEmpty, forSegment: 0)
        appButtons.setEnabled(appsTable.selectedRow >= 0, forSegment: 1)
    }

    private var selectedMode: LightMode? {
        let row = modesTable.selectedRow
        return modes.indices.contains(row) ? modes[row] : nil
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === modesTable ? modes.count : apps.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        if tableView === modesTable {
            guard modes.indices.contains(row) else { return nil }
            let mode = modes[row]
            switch identifier {
            case Self.modeColumn: return textCell(mode.name)
            case Self.brightnessColumn: return textCell("\(mode.brightness)%")
            case Self.temperatureColumn: return textCell("\(mode.temperature)K")
            case Self.togglesColumn: return textCell(mode.toggleSummary)
            default: return textCell(mode.videoMode ? String(localized: "On") : "–")
            }
        }
        guard apps.indices.contains(row) else { return nil }
        let entry = apps[row]
        if identifier == Self.appColumn {
            return appCell(entry.bundleID)
        }
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = UIStyle.bodyFont
        for mode in modes {
            popup.addItem(withTitle: mode.name)
            popup.lastItem?.representedObject = mode.id
        }
        if let index = modes.firstIndex(where: { $0.id == entry.modeID }) {
            popup.selectItem(at: index)
        }
        popup.tag = row
        popup.target = self
        popup.action = #selector(appModeChanged(_:))
        return popup
    }

    // MARK: - Reordering (Modes table only)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === modesTable else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.modeRowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === modesTable, info.draggingSource as? NSTableView === modesTable else { return [] }
        if dropOperation == .on { tableView.setDropRow(row, dropOperation: .above) }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === modesTable,
              let value = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.modeRowType),
              let source = Int(value) else { return false }
        // Dropping above row `row`: after removing the source, rows below it shift up by one.
        return moveMode(from: source, to: source < row ? row - 1 : row)
    }

    @objc private func moveButtonsClicked(_ sender: NSSegmentedControl) {
        let row = modesTable.selectedRow
        moveMode(from: row, to: sender.selectedSegment == 0 ? row - 1 : row + 1)
    }

    @discardableResult
    private func moveMode(from source: Int, to destination: Int) -> Bool {
        var all = modes
        guard all.indices.contains(source), all.indices.contains(destination), source != destination else { return false }
        let mode = all.remove(at: source)
        all.insert(mode, at: destination)
        // Persist the full stored list in the table's order (the table always shows every mode).
        ModeStore.modes = all
        log("Moved mode \(mode.name) to position \(destination + 1)")
        modes = all
        modesTable.reloadData()
        modesTable.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        modesTable.scrollRowToVisible(destination)
        updateButtons()
        modesChanged()
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    private func textCell(_ text: String) -> NSView {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = UIStyle.bodyFont
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func appCell(_ bundleID: String) -> NSView {
        let cell = NSTableCellView()
        let icon = NSImageView(image: Self.appIcon(bundleID))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let field = NSTextField(labelWithString: Self.appName(bundleID))
        field.font = UIStyle.bodyFont
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = bundleID
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(field)
        cell.imageView = icon
        cell.textField = field
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = appURL(bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func appIcon(_ bundleID: String) -> NSImage {
        if let url = appURL(bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    // MARK: - Mode actions

    @objc private func modeButtonsClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            addMode()
        } else {
            deleteSelectedMode()
        }
    }

    private func addMode() {
        var mode = currentLampSettings()
            ?? LightMode(name: "", brightness: 50, temperature: 4000, videoMode: false,
                         matchScreen: false, autoLight: false, presence: false, autoTemperature: false)
        mode.id = UUID()
        mode.name = String(localized: "New Mode")
        edit(mode, isNew: true)
    }

    @objc private func editSelectedMode() {
        guard let mode = selectedMode else { return }
        edit(mode, isNew: false)
    }

    @objc private func applySelectedMode() {
        guard let mode = selectedMode else { return }
        applyMode(mode)
    }

    private func deleteSelectedMode() {
        guard let mode = selectedMode, let window, modes.count > 1 else { return }
        let boundCount = apps.filter { $0.modeID == mode.id }.count
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete “\(mode.name)”?")
        alert.informativeText = boundCount > 0
            ? String(localized: "Its app associations are removed too.")
            : String(localized: "This can't be undone.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            ModeStore.modes = ModeStore.modes.filter { $0.id != mode.id }
            log("Deleted mode: \(mode.name)")
            self.reload()
            self.modesChanged()
        }
    }

    private func edit(_ mode: LightMode, isNew: Bool) {
        guard let window else { return }
        nameField.stringValue = mode.name
        brightnessSlider.integerValue = mode.brightness
        temperatureSlider.integerValue = mode.temperature
        videoCheckbox.state = mode.videoMode ? .on : .off
        // Modes from before 0.10 have no saved toggles; start from the lamp's current state.
        let current = currentLampSettings()
        setToggleCheckboxes(matchScreen: mode.matchScreen ?? current?.matchScreen ?? false,
                            autoLight: mode.autoLight ?? current?.autoLight ?? false,
                            presence: mode.presence ?? current?.presence ?? false,
                            autoTemperature: mode.autoTemperature ?? current?.autoTemperature ?? false)
        sliderChanged(nil)

        let alert = NSAlert()
        alert.messageText = isNew ? String(localized: "New Mode") : String(localized: "Edit Mode")
        alert.informativeText = String(localized: "A mode sets the lamp's brightness, color temperature, and video mode, and turns the checked features on and the others off.")
        alert.accessoryView = makeEditorView()
        alert.addButton(withTitle: isNew ? String(localized: "Add") : String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = nameField
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = self.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let edited = LightMode(id: mode.id,
                                   name: name.isEmpty ? String(localized: "New Mode") : name,
                                   brightness: self.brightnessSlider.integerValue,
                                   temperature: self.roundedTemperature,
                                   videoMode: self.videoCheckbox.state == .on,
                                   matchScreen: self.matchScreenCheckbox.state == .on,
                                   autoLight: self.autoLightCheckbox.state == .on,
                                   presence: self.presenceCheckbox.state == .on,
                                   autoTemperature: self.autoTemperatureCheckbox.state == .on)
            var all = ModeStore.modes
            if let index = all.firstIndex(where: { $0.id == mode.id }) {
                all[index] = edited
            } else {
                all.append(edited)
            }
            ModeStore.modes = all
            log(isNew ? "Added mode: \(edited.name)" : "Edited mode: \(edited.name)")
            self.reload()
            if let row = self.modes.firstIndex(where: { $0.id == edited.id }) {
                self.modesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.modesTable.scrollRowToVisible(row)
            }
            self.modesChanged()
        }
    }

    private var roundedTemperature: Int {
        Int((temperatureSlider.doubleValue / 100).rounded()) * 100
    }

    private func makeEditorView() -> NSView {
        nameField.placeholderString = String(localized: "Name")
        brightnessSlider.target = self
        brightnessSlider.action = #selector(sliderChanged(_:))
        temperatureSlider.target = self
        temperatureSlider.action = #selector(sliderChanged(_:))
        for label in [brightnessLabel, temperatureLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.alignment = .right
        }
        let useCurrent = NSButton(title: String(localized: "Use Current Lamp Settings"), target: self,
                                  action: #selector(useCurrentLampSettings))
        useCurrent.bezelStyle = .rounded
        useCurrent.controlSize = .small
        useCurrent.isEnabled = currentLampSettings() != nil
        for checkbox in [matchScreenCheckbox, autoLightCheckbox, presenceCheckbox, autoTemperatureCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(toggleCheckboxChanged(_:))
        }
        matchScreenCheckbox.toolTip = String(localized: "Lamp brightness follows the Studio Display, starting from this brightness")
        autoLightCheckbox.toolTip = String(localized: "The lamp sets its own brightness; the brightness above is not used")
        autoTemperatureCheckbox.toolTip = String(localized: "Color temperature follows the time of day; the color temperature above is not used")
        let lampToggles = NSGridView(views: [[videoCheckbox, autoLightCheckbox], [matchScreenCheckbox, presenceCheckbox],
                                             [autoTemperatureCheckbox, NSGridCell.emptyContentView]])
        lampToggles.rowSpacing = 4
        lampToggles.columnSpacing = 16

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "Name")), nameField, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: String(localized: "Brightness")), brightnessSlider, brightnessLabel],
            [NSTextField(labelWithString: String(localized: "Color Temp")), temperatureSlider, temperatureLabel],
            [NSTextField(labelWithString: String(localized: "Features")), lampToggles, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, useCurrent, NSGridCell.emptyContentView]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 200
        grid.column(at: 2).width = 52
        grid.row(at: 0).mergeCells(in: NSRange(location: 1, length: 2))
        grid.row(at: 3).mergeCells(in: NSRange(location: 1, length: 2))
        grid.row(at: 3).yPlacement = .top
        grid.row(at: 4).cell(at: 1).xPlacement = .leading
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        return grid
    }

    @objc private func sliderChanged(_ sender: Any?) {
        brightnessLabel.stringValue = "\(brightnessSlider.integerValue)%"
        temperatureLabel.stringValue = "\(roundedTemperature)K"
    }

    private func setToggleCheckboxes(matchScreen: Bool, autoLight: Bool, presence: Bool, autoTemperature: Bool) {
        autoLightCheckbox.state = autoLight ? .on : .off
        matchScreenCheckbox.state = matchScreen && !autoLight ? .on : .off
        presenceCheckbox.state = presence ? .on : .off
        autoTemperatureCheckbox.state = autoTemperature ? .on : .off
        updateEditorAvailability()
    }

    // Auto Light and Match Screen exclude each other; sliders the mode won't use are dimmed.
    @objc private func toggleCheckboxChanged(_ sender: NSButton) {
        if sender === autoLightCheckbox, sender.state == .on { matchScreenCheckbox.state = .off }
        if sender === matchScreenCheckbox, sender.state == .on { autoLightCheckbox.state = .off }
        updateEditorAvailability()
    }

    private func updateEditorAvailability() {
        let autoLight = autoLightCheckbox.state == .on
        brightnessSlider.isEnabled = !autoLight
        brightnessLabel.textColor = autoLight ? .tertiaryLabelColor : .labelColor
        let autoTemperature = autoTemperatureCheckbox.state == .on
        temperatureSlider.isEnabled = !autoTemperature
        temperatureLabel.textColor = autoTemperature ? .tertiaryLabelColor : .labelColor
    }

    @objc private func useCurrentLampSettings() {
        guard let current = currentLampSettings() else { return }
        brightnessSlider.integerValue = current.brightness
        temperatureSlider.integerValue = current.temperature
        videoCheckbox.state = current.videoMode ? .on : .off
        setToggleCheckboxes(matchScreen: current.matchScreen == true, autoLight: current.autoLight == true,
                            presence: current.presence == true, autoTemperature: current.autoTemperature == true)
        sliderChanged(nil)
    }

    // MARK: - App association actions

    @objc private func appButtonsClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            addAppAssociation()
        } else {
            removeSelectedAppAssociation()
        }
    }

    private func addAppAssociation() {
        guard let window, let mode = selectedMode ?? modes.first else { return }
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose an app to use “\(mode.name)”")
        panel.prompt = String(localized: "Associate")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                let alert = NSAlert()
                alert.messageText = String(localized: "This app can't be associated")
                alert.informativeText = String(localized: "It has no bundle identifier.")
                alert.beginSheetModal(for: window)
                return
            }
            var bindings = ModeStore.bindings
            bindings[bundleID] = mode.id
            ModeStore.bindings = bindings
            log("Associated \(bundleID) with mode: \(mode.name)")
            self.reload()
            if let row = self.apps.firstIndex(where: { $0.bundleID == bundleID }) {
                self.appsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.appsTable.scrollRowToVisible(row)
            }
            self.updateButtons()
            self.modesChanged()
        }
    }

    private func removeSelectedAppAssociation() {
        let row = appsTable.selectedRow
        guard apps.indices.contains(row) else { return }
        let bundleID = apps[row].bundleID
        var bindings = ModeStore.bindings
        bindings[bundleID] = nil
        ModeStore.bindings = bindings
        log("Removed app association: \(bundleID)")
        reload()
        modesChanged()
    }

    @objc private func appModeChanged(_ sender: NSPopUpButton) {
        guard apps.indices.contains(sender.tag),
              let modeID = sender.selectedItem?.representedObject as? UUID else { return }
        let bundleID = apps[sender.tag].bundleID
        var bindings = ModeStore.bindings
        bindings[bundleID] = modeID
        ModeStore.bindings = bindings
        log("Associated \(bundleID) with mode: \(sender.titleOfSelectedItem ?? "")")
        apps[sender.tag].modeID = modeID
        modesChanged()
    }
}
