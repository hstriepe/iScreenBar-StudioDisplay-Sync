import AppIntents
import Foundation

// Compiled into both the app and the Control Center / widget extension.
// Each target defines `performControlAction(_:)`: the app runs the action directly
// (Automation.swift); the sandboxed extension posts the action's Darwin notification,
// which the running app observes. Darwin notifications carry no payload, so every
// value the widget can set has its own name (e.g. `…control.brightness.60`).

enum ControlAction: Hashable, CaseIterable {
    case toggleLight
    case toggleKeepAwake
    case applyRotationPreset
    case showControlPanel
    case brightnessUp
    case brightnessDown
    case warmer
    case cooler
    case setBrightness(Int)
    case setTemperature(Int)

    static var allCases: [ControlAction] {
        [.toggleLight, .toggleKeepAwake, .applyRotationPreset, .showControlPanel,
         .brightnessUp, .brightnessDown, .warmer, .cooler]
            + LampState.brightnessSteps.map { .setBrightness($0) }
            + LampState.temperatureSteps.map { .setTemperature($0) }
    }

    private static let prefix = "org.windholm.iScreenBarMenu.control."

    /// Name used in notifications and logs.
    var identifier: String {
        switch self {
        case .toggleLight: return "toggleLight"
        case .toggleKeepAwake: return "toggleKeepAwake"
        case .applyRotationPreset: return "applyRotationPreset"
        case .showControlPanel: return "showControlPanel"
        case .brightnessUp: return "brightnessUp"
        case .brightnessDown: return "brightnessDown"
        case .warmer: return "warmer"
        case .cooler: return "cooler"
        case .setBrightness(let value): return "brightness.\(value)"
        case .setTemperature(let kelvin): return "temperature.\(kelvin)"
        }
    }

    var notificationName: String { Self.prefix + identifier }

    init?(notificationName: String) {
        guard let action = Self.allCases.first(where: { $0.notificationName == notificationName }) else { return nil }
        self = action
    }
}

// Hidden from Shortcuts; the app's own intents in Automation.swift cover the same actions.

struct ToggleLightControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Light"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.toggleLight)
        return .result()
    }
}

struct ToggleKeepAwakeControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Keep Awake"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.toggleKeepAwake)
        return .result()
    }
}

struct ApplyRotationPresetControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Rotation Preset"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.applyRotationPreset)
        return .result()
    }
}

struct ShowControlPanelControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Control Panel"
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.showControlPanel)
        return .result()
    }
}

enum StepDirection: String, AppEnum {
    case up
    case down

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static var caseDisplayRepresentations: [StepDirection: DisplayRepresentation] = [
        .up: "Up",
        .down: "Down",
    ]
}

struct StepBrightnessControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Step Brightness"
    static var isDiscoverable = false

    @Parameter(title: "Direction")
    var direction: StepDirection

    init() {}
    init(_ direction: StepDirection) { self.direction = direction }

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(direction == .up ? .brightnessUp : .brightnessDown)
        return .result()
    }
}

struct StepTemperatureControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Step Color Temperature"
    static var isDiscoverable = false

    /// Up = cooler (higher Kelvin), down = warmer.
    @Parameter(title: "Direction")
    var direction: StepDirection

    init() {}
    init(_ direction: StepDirection) { self.direction = direction }

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(direction == .up ? .cooler : .warmer)
        return .result()
    }
}

struct SetBrightnessControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Brightness"
    static var isDiscoverable = false

    @Parameter(title: "Brightness")
    var value: Int

    init() {}
    init(_ value: Int) { self.value = value }

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.setBrightness(value))
        return .result()
    }
}

struct SetTemperatureControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Color Temperature"
    static var isDiscoverable = false

    @Parameter(title: "Color Temperature")
    var kelvin: Int

    init() {}
    init(_ kelvin: Int) { self.kelvin = kelvin }

    @MainActor
    func perform() async throws -> some IntentResult {
        await performControlAction(.setTemperature(kelvin))
        return .result()
    }
}
