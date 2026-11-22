import Foundation

// Launch at login is the same user LaunchAgent that scripts/install.sh writes (not SMAppService):
// it keeps the stdout log redirect and avoids a second login mechanism that could start a duplicate instance.
enum LoginItem {
    // The LaunchAgent label is the bundle ID (scripts/install.sh uses the same value).
    static let label = Bundle.main.bundleIdentifier ?? "org.windholm.iScreenBarMenu"
    // Earlier labels: local.qiu.iScreenBarStudioSync (before the bundle ID change),
    // org.windholm.iScreenMenu (before the rename to iScreenBar Menu, 0.4 and earlier).
    private static let legacyLabels = ["local.qiu.iScreenBarStudioSync", "org.windholm.iScreenMenu"]

    private static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var plistURL: URL { agentURL(for: label) }
    private static var logURL: URL {
        homeDirectory.appendingPathComponent("Library/Logs/iScreenBarMenu.log")
    }

    private static func agentURL(for label: String) -> URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let fileManager = FileManager.default
        if !enabled {
            guard isEnabled else { return true }
            do {
                try fileManager.removeItem(at: plistURL)
                return true
            } catch {
                log("Failed to remove LaunchAgent: \(error.localizedDescription)")
                return false
            }
        }
        guard let executable = Bundle.main.executablePath else { return false }
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Restart after a crash, but a normal Quit (exit 0) stays quit.
            "KeepAlive": ["SuccessfulExit": false],
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path
        ]
        do {
            try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            return true
        } catch {
            log("Failed to write LaunchAgent: \(error.localizedDescription)")
            return false
        }
    }

    // Earlier installs used another label (local.qiu.iScreenBarStudioSync also had KeepAlive=true, which relaunches
    // the app after Quit; org.windholm.iScreenMenu points at the old app's executable). Remove those files and carry
    // the login preference over to the current label.
    // A job that is already loaded is not touched; scripts/install.sh boots it out.
    static func replaceLegacyAgentIfNeeded() {
        for legacyLabel in legacyLabels where legacyLabel != label {
            let legacyURL = agentURL(for: legacyLabel)
            guard FileManager.default.fileExists(atPath: legacyURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: legacyURL)
            } catch {
                log("Failed to remove legacy LaunchAgent \(legacyLabel): \(error.localizedDescription)")
                continue
            }
            let enabled = isEnabled || setEnabled(true)
            log(enabled
                ? "Replaced legacy LaunchAgent \(legacyLabel) with \(label)"
                : "Removed legacy LaunchAgent \(legacyLabel); new one could not be written")
        }
    }
}
