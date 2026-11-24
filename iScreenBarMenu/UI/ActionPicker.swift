import AppKit
import UniformTypeIdentifiers

/// Controls for choosing a `ModeAction`: a Shortcut pop-up and a script file row (name, Choose…, Clear).
/// The caller places `shortcutPopup` and `scriptRow` in its own layout (mode editor, Mode Center Lamp Actions).
final class ActionPicker: NSObject {
    let shortcutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let scriptRow: NSStackView
    /// Called after the user changed the Shortcut or the script.
    var onChange: () -> Void = {}

    private let scriptLabel = NSTextField(labelWithString: "")
    private let clearButton: NSButton
    private var shortcutName: String?
    private var scriptPath: String?

    override init() {
        let choose = NSButton(title: String(localized: "Choose…"), target: nil, action: nil)
        clearButton = NSButton(title: String(localized: "Clear"), target: nil, action: nil)
        scriptRow = NSStackView(views: [scriptLabel, choose, clearButton])
        super.init()
        for button in [choose, clearButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.setContentHuggingPriority(.required, for: .horizontal)
        }
        choose.action = #selector(chooseScript)
        choose.toolTip = String(localized: "Choose an AppleScript file to run")
        clearButton.action = #selector(clearScript)
        scriptLabel.font = UIStyle.bodyFont
        scriptLabel.lineBreakMode = .byTruncatingMiddle
        scriptLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scriptLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scriptRow.orientation = .horizontal
        scriptRow.spacing = 6
        shortcutPopup.controlSize = .small
        shortcutPopup.font = UIStyle.bodyFont
        shortcutPopup.target = self
        shortcutPopup.action = #selector(shortcutChosen)
        shortcutPopup.toolTip = String(localized: "Shortcut to run")
    }

    var action: ModeAction? {
        let action = ModeAction(shortcutName: shortcutName, scriptPath: scriptPath)
        return action.isEmpty ? nil : action
    }

    func set(_ action: ModeAction?) {
        shortcutName = action?.shortcutName
        scriptPath = action?.scriptPath
        rebuildShortcutMenu(names: ActionRunner.shared.shortcutNames)
        updateScriptRow()
        ActionRunner.shared.loadShortcutNames { [weak self] names in self?.rebuildShortcutMenu(names: names) }
    }

    /// "None", then the user's shortcuts. A saved name that isn't in the list (renamed, deleted, or the list is
    /// still loading) is kept as its own item so nothing is lost silently.
    private func rebuildShortcutMenu(names: [String]?) {
        shortcutPopup.removeAllItems()
        let menu = shortcutPopup.menu ?? NSMenu()
        menu.addItem(Self.item(String(localized: "No Shortcut"), name: nil))
        var listed = names ?? []
        if let shortcutName, !listed.contains(shortcutName) { listed.insert(shortcutName, at: 0) }
        if !listed.isEmpty { menu.addItem(.separator()) }
        for name in listed {
            let missing = names != nil && name == shortcutName && !(names ?? []).contains(name)
            let title = missing ? String(localized: "\(name) (not found)") : name
            menu.addItem(Self.item(title, name: name))
        }
        if names == nil {
            let loading = NSMenuItem(title: String(localized: "Loading Shortcuts…"), action: nil, keyEquivalent: "")
            loading.isEnabled = false
            menu.addItem(loading)
        } else if names?.isEmpty == true {
            let none = NSMenuItem(title: String(localized: "No Shortcuts Found"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        shortcutPopup.autoenablesItems = false
        let index = shortcutPopup.itemArray.firstIndex { ($0.representedObject as? String) == shortcutName } ?? 0
        shortcutPopup.selectItem(at: shortcutName == nil ? 0 : index)
    }

    private static func item(_ title: String, name: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = name
        return item
    }

    private func updateScriptRow() {
        if let scriptPath {
            scriptLabel.stringValue = ModeAction(scriptPath: scriptPath).scriptName ?? scriptPath
            scriptLabel.textColor = FileManager.default.fileExists(atPath: scriptPath) ? .labelColor : .systemRed
            scriptLabel.toolTip = scriptPath
        } else {
            scriptLabel.stringValue = String(localized: "No Script")
            scriptLabel.textColor = .secondaryLabelColor
            scriptLabel.toolTip = nil
        }
        clearButton.isEnabled = scriptPath != nil
    }

    @objc private func shortcutChosen() {
        shortcutName = shortcutPopup.selectedItem?.representedObject as? String
        onChange()
    }

    @objc private func chooseScript() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose an AppleScript to run")
        panel.prompt = String(localized: "Choose")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = ["scpt", "scptd", "applescript"].compactMap { UTType(filenameExtension: $0) }
        if let scriptPath {
            panel.directoryURL = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Scripts", isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scriptPath = url.path
        updateScriptRow()
        onChange()
    }

    @objc private func clearScript() {
        scriptPath = nil
        updateScriptRow()
        onChange()
    }
}
