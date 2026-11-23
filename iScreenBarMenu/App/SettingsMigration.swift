import Foundation

// Up to 0.4 the app was "iScreen Menu" with bundle ID org.windholm.iScreenMenu. Copy its settings once into the
// current domain (keys already set here win); the old domain is left in place. Runs before anything reads defaults.
func importPreRenameSettingsIfNeeded() {
    let oldDomain = "org.windholm.iScreenMenu"
    let doneKey = "importedPreRenameSettings"
    let defaults = UserDefaults.standard
    guard let currentDomain = Bundle.main.bundleIdentifier, currentDomain != oldDomain,
          !defaults.bool(forKey: doneKey) else { return }
    defaults.set(true, forKey: doneKey)
    guard let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
    let current = defaults.persistentDomain(forName: currentDomain) ?? [:]
    var copied = 0
    for (key, value) in old where current[key] == nil {
        defaults.set(value, forKey: key)
        copied += 1
    }
    log("Imported \(copied) settings from \(oldDomain)")
}

// Up to 0.8 there was one custom mode (`savedCustomMode`) next to three hard-coded presets, and app bindings stored
// their own copy of the light settings (`appModes`). Build the mode list once from those; the old keys stay in place.
func migrateLightModesIfNeeded() {
    let defaults = UserDefaults.standard
    guard defaults.data(forKey: ModeStore.modesKey) == nil else { return }
    var modes = ModeStore.defaultModes()
    if let data = defaults.data(forKey: "savedCustomMode"),
       let saved = try? JSONDecoder().decode(SavedMode.self, from: data) {
        modes.append(LightMode(name: saved.name, brightness: saved.brightness,
                               temperature: saved.temperature, videoMode: saved.videoMode))
    }
    var bindings: [String: UUID] = [:]
    if let data = defaults.data(forKey: "appModes"),
       let old = try? JSONDecoder().decode([String: SavedMode].self, from: data) {
        for (bundleID, saved) in old.sorted(by: { $0.key < $1.key }) {
            let matches: (LightMode) -> Bool = { mode in
                mode.name == saved.name && mode.brightness == saved.brightness
                    && mode.temperature == saved.temperature && mode.videoMode == saved.videoMode
            }
            if let existing = modes.first(where: matches) {
                bindings[bundleID] = existing.id
            } else {
                let mode = LightMode(name: saved.name, brightness: saved.brightness,
                                     temperature: saved.temperature, videoMode: saved.videoMode)
                modes.append(mode)
                bindings[bundleID] = mode.id
            }
        }
    }
    ModeStore.modes = modes
    ModeStore.bindings = bindings
    ModeStore.selectedModeID = modes.first?.id
    log("Migrated light modes: \(modes.count) modes, \(bindings.count) app bindings")
}
