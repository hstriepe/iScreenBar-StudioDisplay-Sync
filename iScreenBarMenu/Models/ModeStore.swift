import Foundation

// UserDefaults persistence for light modes, app → mode bindings, and the selected mode (ADR 0010).
enum ModeStore {
    static let modesKey = "lightModes"
    static let bindingsKey = "appModeBindings"
    static let selectedKey = "selectedModeID"

    static var modes: [LightMode] {
        get {
            guard let data = UserDefaults.standard.data(forKey: modesKey) else { return [] }
            return (try? JSONDecoder().decode([LightMode].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: modesKey)
            // Drop bindings and the selection that point at deleted modes.
            let ids = Set(newValue.map(\.id))
            let bound = bindings
            let kept = bound.filter { ids.contains($0.value) }
            if kept.count != bound.count { bindings = kept }
            if let selected = selectedModeID, !ids.contains(selected) { selectedModeID = nil }
        }
    }

    /// Bundle ID → mode id.
    static var bindings: [String: UUID] {
        get {
            guard let data = UserDefaults.standard.data(forKey: bindingsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: UUID].self, from: data)) ?? [:]
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: bindingsKey)
        }
    }

    static var selectedModeID: UUID? {
        get { UserDefaults.standard.string(forKey: selectedKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: selectedKey) }
    }

    static func mode(id: UUID) -> LightMode? {
        modes.first { $0.id == id }
    }

    static func defaultModes() -> [LightMode] {
        [LightMode(name: String(localized: "Favorite"), brightness: 47, temperature: 5500, videoMode: false),
         LightMode(name: String(localized: "Night Work"), brightness: 30, temperature: 4000, videoMode: false),
         LightMode(name: String(localized: "Wind Down"), brightness: 20, temperature: 3000, videoMode: false)]
    }
}
