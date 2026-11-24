import Foundation

// A Shortcut and/or an AppleScript file run by a mode or by the lamp turning on or off (ADR 0011).
// Both parts are optional; when both are set the Shortcut runs first.
struct ModeAction: Codable, Equatable {
    var shortcutName: String?
    var scriptPath: String?

    init(shortcutName: String? = nil, scriptPath: String? = nil) {
        self.shortcutName = shortcutName.flatMap { $0.isEmpty ? nil : $0 }
        self.scriptPath = scriptPath.flatMap { $0.isEmpty ? nil : $0 }
    }

    var isEmpty: Bool { shortcutName == nil && scriptPath == nil }

    /// Display name of the script file (without extension), or nil.
    var scriptName: String? {
        scriptPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }

    /// "▶ Shortcut", "▶ Script" entries for tables and logs.
    var summaryParts: [String] {
        [shortcutName, scriptName].compactMap { $0 }.map { "▶ \($0)" }
    }

    // Lamp On / Lamp Off actions (global, not per mode).
    static let lampOnKey = "lampOnAction"
    static let lampOffKey = "lampOffAction"

    static func stored(forKey key: String) -> ModeAction? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let action = try? JSONDecoder().decode(ModeAction.self, from: data), !action.isEmpty else { return nil }
        return action
    }

    static func store(_ action: ModeAction?, forKey key: String) {
        if let action, !action.isEmpty, let data = try? JSONEncoder().encode(action) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
