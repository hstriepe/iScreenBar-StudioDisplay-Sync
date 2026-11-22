import AppIntents
import Foundation

// Compiled into both the app and the Control Center extension.
// Each target defines `performControlAction(_:)`: the app runs the action directly
// (Automation.swift); the sandboxed extension posts the action's Darwin notification,
// which the running app observes.

enum ControlAction: String, CaseIterable {
    case toggleLight
    case toggleKeepAwake
    case applyRotationPreset
    case showControlPanel

    private static let prefix = "org.windholm.iScreenBarMenu.control."

    var notificationName: String { Self.prefix + rawValue }

    init?(notificationName: String) {
        guard notificationName.hasPrefix(Self.prefix) else { return nil }
        self.init(rawValue: String(notificationName.dropFirst(Self.prefix.count)))
    }
}

// Hidden from Shortcuts; the app's own intents in Automation.swift cover the same actions.

struct ToggleLightControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Light"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        performControlAction(.toggleLight)
        return .result()
    }
}

struct ToggleKeepAwakeControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Keep Awake"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        performControlAction(.toggleKeepAwake)
        return .result()
    }
}

struct ApplyRotationPresetControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Rotation Preset"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        performControlAction(.applyRotationPreset)
        return .result()
    }
}

struct ShowControlPanelControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Control Panel"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        performControlAction(.showControlPanel)
        return .result()
    }
}
