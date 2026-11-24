import Foundation

// A saved light setting ("mode") shown in Favorites and Mode Center. Stored in ModeStore; app bindings refer to it by id.
// The toggle fields are optional: modes saved before 0.10 don't have them and keep the old behavior until edited
// (Match Screen and Auto Light off, Presence and Auto Temp left as they are). ADR 0010.
struct LightMode: Codable, Equatable {
    var id: UUID
    var name: String
    var brightness: Int
    var temperature: Int
    var videoMode: Bool
    var matchScreen: Bool?
    var autoLight: Bool?
    var presence: Bool?
    var autoTemperature: Bool?
    /// Shortcut and/or AppleScript run after the mode is applied (0.12, ADR 0011); nil in older stored modes.
    var actions: ModeAction?

    init(id: UUID = UUID(), name: String, brightness: Int, temperature: Int, videoMode: Bool,
         matchScreen: Bool? = nil, autoLight: Bool? = nil, presence: Bool? = nil, autoTemperature: Bool? = nil,
         actions: ModeAction? = nil) {
        self.id = id
        self.name = name
        self.brightness = max(1, min(100, brightness))
        self.temperature = max(2700, min(6500, temperature))
        self.videoMode = videoMode
        // Auto Light and Match Screen are mutually exclusive; Auto Light wins.
        self.autoLight = autoLight
        self.matchScreen = autoLight == true ? false : matchScreen
        self.presence = presence
        self.autoTemperature = autoTemperature
        self.actions = actions?.isEmpty == true ? nil : actions
    }

    /// Short summary of the saved toggles and actions for the Mode Center table.
    var toggleSummary: String {
        var parts: [String] = []
        if autoLight == true { parts.append(String(localized: "Auto Light")) }
        if matchScreen == true { parts.append(String(localized: "Match Screen")) }
        if presence == true { parts.append(String(localized: "Presence")) }
        if autoTemperature == true { parts.append(String(localized: "Auto Temp")) }
        parts += actions?.summaryParts ?? []
        return parts.isEmpty ? "–" : parts.joined(separator: ", ")
    }
}
