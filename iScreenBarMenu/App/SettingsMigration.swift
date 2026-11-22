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
