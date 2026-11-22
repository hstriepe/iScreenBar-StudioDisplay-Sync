import AppIntents
import AppKit
import Foundation
import WidgetKit

// Automation surface shared by AppleScript (ScriptingSupport.swift), App Intents (below),
// and the Control Center extension (Darwin notifications, Shared/ControlActions.swift).
// Everything runs on the main thread against the one StatusIndicator in main.swift.

/// Settings that automation can read and turn on or off. Each maps to a control panel button.
enum AutomationFeature: String, CaseIterable {
    case light
    case autoTemperature
    case autoLight
    case presence
    case videoMode
    case matchScreen
    case linkScreens
    case sleepSync
    case wakeScreen
    case keepAwake
    case builtinDisplay

    var localizedName: String {
        switch self {
        case .light: return String(localized: "Light")
        case .autoTemperature: return String(localized: "Auto Temp")
        case .autoLight: return String(localized: "Auto Light")
        case .presence: return String(localized: "Presence")
        case .videoMode: return String(localized: "Video Mode")
        case .matchScreen: return String(localized: "Match Screen")
        case .linkScreens: return String(localized: "Link Screens")
        case .sleepSync: return String(localized: "Sleep Sync")
        case .wakeScreen: return String(localized: "Wake Screen")
        case .keepAwake: return String(localized: "Keep Awake")
        case .builtinDisplay: return String(localized: "Built-in Display")
        }
    }
}

enum AutomationError: Error, LocalizedError, CustomLocalizedStringResourceConvertible {
    case notReady
    case lampNotConnected
    case autoTemperatureOn
    case unavailable(String)
    case failed(String)
    case unknownFavorite(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return String(localized: "iScreenBar Menu isn't ready yet.")
        case .lampNotConnected:
            return String(localized: "The iScreenBar isn't connected.")
        case .autoTemperatureOn:
            return String(localized: "Turn off Auto Temp to set the color temperature.")
        case .unavailable(let name):
            return String(localized: "“\(name)” isn't available right now.")
        case .failed(let name):
            return String(localized: "Couldn't change “\(name)”.")
        case .unknownFavorite(let name):
            return String(localized: "There's no favorite named “\(name)”.")
        }
    }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: errorDescription ?? "")
    }
}

/// Implemented by StatusIndicator in main.swift. Call on the main thread only.
protocol AutomationTarget: AnyObject {
    var isLampConnected: Bool { get }
    var lampBrightness: Int? { get }
    var lampTemperature: Int? { get }
    /// Cheap reads for the widget state (no panel refresh).
    var isLampPowerOn: Bool { get }
    var isAutoTemperatureOn: Bool { get }
    var isKeepAwakeActive: Bool { get }
    var favoriteNames: [String] { get }
    var rotationPresetName: String { get }
    func isOn(_ feature: AutomationFeature) -> Bool
    func setFeature(_ feature: AutomationFeature, on: Bool) throws
    func setBrightness(_ value: Int) throws
    func setTemperature(_ kelvin: Int) throws
    func applyFavorite(named name: String) throws
    func applyRotationPresetFromAutomation() throws
    func showControlPanel()
}

/// Set once in main.swift right after the StatusIndicator is created.
var automationTarget: AutomationTarget?

func requireAutomationTarget() throws -> AutomationTarget {
    guard let automationTarget else { throw AutomationError.notReady }
    return automationTarget
}

func lampStatusSummary(_ target: AutomationTarget) -> String {
    guard target.isLampConnected else { return String(localized: "The iScreenBar isn't connected.") }
    let power = target.isOn(.light) ? String(localized: "Light on") : String(localized: "Light off")
    let brightness = target.lampBrightness.map { "\($0)%" } ?? "--%"
    let temperature = target.lampTemperature.map { "\($0)K" } ?? "----K"
    return "\(power) · \(brightness) · \(temperature)"
}

// MARK: - Control Center actions

// The Control Center extension is sandboxed and can't drive the lamp, so it posts a Darwin
// notification per action. Shared/ControlActions.swift defines the actions and their names.
// If the system runs a control's intent in this process instead, it lands here directly.
@MainActor
func performControlAction(_ action: ControlAction) async {
    guard let target = automationTarget else { return }
    do {
        switch action {
        case .toggleLight:
            try target.setFeature(.light, on: !target.isOn(.light))
        case .toggleKeepAwake:
            try target.setFeature(.keepAwake, on: !target.isOn(.keepAwake))
        case .applyRotationPreset:
            try target.applyRotationPresetFromAutomation()
        case .showControlPanel:
            target.showControlPanel()
        case .brightnessUp, .brightnessDown:
            guard target.isLampConnected else { throw AutomationError.lampNotConnected }
            guard let current = target.lampBrightness else { throw AutomationError.unavailable(String(localized: "Brightness")) }
            let step = action == .brightnessUp ? LampState.brightnessStep : -LampState.brightnessStep
            try target.setBrightness(max(1, min(100, current + step)))
        case .warmer, .cooler:
            guard target.isLampConnected else { throw AutomationError.lampNotConnected }
            guard let current = target.lampTemperature else { throw AutomationError.unavailable(String(localized: "Color Temperature")) }
            let step = action == .cooler ? LampState.temperatureStep : -LampState.temperatureStep
            try target.setTemperature(max(2700, min(6500, current + step)))
        case .setBrightness(let value):
            try target.setBrightness(value)
        case .setTemperature(let kelvin):
            try target.setTemperature(kelvin)
        }
        log("Control Center: \(action.identifier)")
    } catch {
        log("Control Center: \(action.identifier) failed: \(error.localizedDescription)")
        NSSound.beep()
    }
    publishLampState()
}

func installControlActionObserver() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    for action in ControlAction.allCases {
        CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
            guard let raw = name?.rawValue as String?,
                  let action = ControlAction(notificationName: raw) else { return }
            Task { @MainActor in await performControlAction(action) }
        }, action.notificationName as CFString, nil, .deliverImmediately)
    }
}

// MARK: - Widget state

private var publishedLampState: LampState?

/// Publishes the lamp snapshot for the widget and reloads it when something changed.
/// Called from the main loop and after Control Center actions; cheap when nothing changed.
@MainActor
func publishLampState() {
    guard let target = automationTarget else { return }
    let state = LampState(isAppRunning: true,
                          isConnected: target.isLampConnected,
                          isPowerOn: target.isLampPowerOn,
                          isAutoTemperatureOn: target.isAutoTemperatureOn,
                          isKeepAwakeOn: target.isKeepAwakeActive,
                          brightness: target.lampBrightness,
                          temperature: target.lampTemperature)
    guard state != publishedLampState else { return }
    guard state.publish() else {
        log("Widget: couldn't publish lamp state")
        return
    }
    publishedLampState = state
    WidgetCenter.shared.reloadTimelines(ofKind: LampState.widgetKind)
}

/// On quit: the widget shows "not running" instead of stale values.
func clearPublishedLampState() {
    LampState().publish()
    WidgetCenter.shared.reloadTimelines(ofKind: LampState.widgetKind)
}

// MARK: - App Intents (Shortcuts, Spotlight, Siri)

enum SwitchState: String, AppEnum {
    case on
    case off
    case toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "State"
    static var caseDisplayRepresentations: [SwitchState: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .toggle: "Toggle",
    ]

    func resolved(current: Bool) -> Bool {
        switch self {
        case .on: return true
        case .off: return false
        case .toggle: return !current
        }
    }
}

extension AutomationFeature: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Setting"
    static var caseDisplayRepresentations: [AutomationFeature: DisplayRepresentation] = [
        .light: DisplayRepresentation(title: "Light", image: .init(systemName: "power")),
        .autoTemperature: DisplayRepresentation(title: "Auto Temp", image: .init(systemName: "circle.lefthalf.filled")),
        .autoLight: DisplayRepresentation(title: "Auto Light", image: .init(systemName: "sun.max")),
        .presence: DisplayRepresentation(title: "Presence", image: .init(systemName: "figure.seated.side")),
        .videoMode: DisplayRepresentation(title: "Video Mode", image: .init(systemName: "video")),
        .matchScreen: DisplayRepresentation(title: "Match Screen", image: .init(systemName: "display")),
        .linkScreens: DisplayRepresentation(title: "Link Screens", image: .init(systemName: "rectangle.on.rectangle")),
        .sleepSync: DisplayRepresentation(title: "Sleep Sync", image: .init(systemName: "moon.zzz")),
        .wakeScreen: DisplayRepresentation(title: "Wake Screen", image: .init(systemName: "figure.walk.arrival")),
        .keepAwake: DisplayRepresentation(title: "Keep Awake", image: .init(systemName: "cup.and.saucer")),
        .builtinDisplay: DisplayRepresentation(title: "Built-in Display", image: .init(systemName: "laptopcomputer")),
    ]
}

struct FavoriteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Favorite"
    static var defaultQuery = FavoriteQuery()

    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct FavoriteQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FavoriteEntity] {
        let names = automationTarget?.favoriteNames ?? []
        return identifiers.filter(names.contains).map(FavoriteEntity.init(id:))
    }

    @MainActor
    func suggestedEntities() async throws -> [FavoriteEntity] {
        (automationTarget?.favoriteNames ?? []).map(FavoriteEntity.init(id:))
    }
}

struct SetLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Light"
    static var description = IntentDescription("Turns the iScreenBar lamp on or off, or toggles it.")

    @Parameter(title: "State", default: .toggle)
    var state: SwitchState

    init() {}
    init(state: SwitchState) { self.state = state }

    static var parameterSummary: some ParameterSummary {
        Summary("Turn light \(\.$state)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let target = try requireAutomationTarget()
        try target.setFeature(.light, on: state.resolved(current: target.isOn(.light)))
        return .result()
    }
}

struct SetSettingIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn Setting On or Off"
    static var description = IntentDescription("Turns an iScreenBar Menu setting on or off, or toggles it, like its control panel button.")

    @Parameter(title: "Setting")
    var feature: AutomationFeature

    @Parameter(title: "State", default: .toggle)
    var state: SwitchState

    static var parameterSummary: some ParameterSummary {
        Summary("Turn \(\.$feature) \(\.$state)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let target = try requireAutomationTarget()
        try target.setFeature(feature, on: state.resolved(current: target.isOn(feature)))
        return .result()
    }
}

struct GetSettingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Setting"
    static var description = IntentDescription("Returns whether an iScreenBar Menu setting is on.")

    @Parameter(title: "Setting")
    var feature: AutomationFeature

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$feature)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let target = try requireAutomationTarget()
        return .result(value: target.isOn(feature))
    }
}

struct SetBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Lamp Brightness"
    static var description = IntentDescription("Sets the iScreenBar brightness in percent.")

    @Parameter(title: "Brightness", inclusiveRange: (1, 100))
    var brightness: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set lamp brightness to \(\.$brightness)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAutomationTarget().setBrightness(brightness)
        return .result()
    }
}

struct SetColorTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Color Temperature"
    static var description = IntentDescription("Sets the iScreenBar color temperature in kelvin (2700–6500). Auto Temp must be off.")

    @Parameter(title: "Kelvin", inclusiveRange: (2700, 6500))
    var kelvin: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set color temperature to \(\.$kelvin) K")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAutomationTarget().setTemperature(kelvin)
        return .result()
    }
}

struct ApplyFavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Favorite"
    static var description = IntentDescription("Turns the lamp on with a saved favorite's brightness and color temperature.")

    @Parameter(title: "Favorite")
    var favorite: FavoriteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$favorite)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAutomationTarget().applyFavorite(named: favorite.id)
        return .result()
    }
}

struct ApplyRotationPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Rotation Preset"
    static var description = IntentDescription("Applies the saved built-in display rotation preset.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAutomationTarget().applyRotationPresetFromAutomation()
        return .result()
    }
}

struct ShowControlPanelIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Control Panel"
    static var description = IntentDescription("Opens the iScreenBar Menu control panel below the menu bar icon.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireAutomationTarget().showControlPanel()
        return .result()
    }
}

struct GetLampStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Lamp Status"
    static var description = IntentDescription("Returns the iScreenBar power, brightness, and color temperature.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = lampStatusSummary(try requireAutomationTarget())
        return .result(value: summary, dialog: "\(summary)")
    }
}

struct IScreenBarMenuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetLightIntent(state: .toggle),
            phrases: ["Toggle the \(.applicationName) light", "Toggle light in \(.applicationName)"],
            shortTitle: "Toggle Light",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ApplyFavoriteIntent(),
            phrases: ["Apply a favorite in \(.applicationName)"],
            shortTitle: "Apply Favorite",
            systemImageName: "star"
        )
        AppShortcut(
            intent: GetLampStatusIntent(),
            phrases: ["Get \(.applicationName) lamp status"],
            shortTitle: "Lamp Status",
            systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: ApplyRotationPresetIntent(),
            phrases: ["Apply the \(.applicationName) rotation preset"],
            shortTitle: "Rotation Preset",
            systemImageName: "rotate.right"
        )
        AppShortcut(
            intent: ShowControlPanelIntent(),
            phrases: ["Show the \(.applicationName) control panel"],
            shortTitle: "Control Panel",
            systemImageName: "slider.horizontal.3"
        )
    }
}
