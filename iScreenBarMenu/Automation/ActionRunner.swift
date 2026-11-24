import Foundation

/// Runs mode and lamp actions out of process with `/usr/bin/osascript`: Shortcuts through Shortcuts Events, scripts
/// from their file (`shortcuts list` only fills the Shortcut pop-up).
/// Actions run one after another on a background queue (so their order is kept), each with a time limit; results go
/// to the log only. An action that is still running or waiting isn't started again under the same key, which stops a
/// Shortcut that re-applies its own mode from looping (ADR 0011).
final class ActionRunner {
    static let shared = ActionRunner()

    private static let timeout: TimeInterval = 60
    private static let listTimeout: TimeInterval = 15
    private let queue = DispatchQueue(label: "org.windholm.iScreenBarMenu.actions")
    /// Keys of actions queued or running. Main thread only.
    private var pendingKeys: Set<String> = []
    /// Shortcut names from the last `shortcuts list`; nil until loaded. Main thread only.
    private(set) var shortcutNames: [String]?
    private var shortcutListCallbacks: [([String]) -> Void] = []

    /// True while any action is queued or running. Main thread only.
    var isBusy: Bool { !pendingKeys.isEmpty }

    /// Runs `action` (Shortcut first, then script). `key` identifies the trigger, e.g. "mode <id>" or "lamp-on".
    func run(_ action: ModeAction?, key: String, label: String) {
        guard let action, !action.isEmpty else { return }
        guard !pendingKeys.contains(key) else {
            log("Action for \(label) is still running; not started again")
            return
        }
        pendingKeys.insert(key)
        queue.async { [weak self] in
            if let name = action.shortcutName {
                // Through Shortcuts Events (background, no window): `shortcuts run` can bring the Shortcuts app to the
                // front, which would count as an app switch. The name is passed as an argument, not in the source.
                Self.execute("/usr/bin/osascript",
                             ["-e", "on run argv",
                              "-e", "tell application id \"com.apple.shortcuts.events\" to run shortcut (item 1 of argv)",
                              "-e", "end run", name],
                             description: "Shortcut “\(name)” (\(label))")
            }
            if let path = action.scriptPath {
                if FileManager.default.fileExists(atPath: path) {
                    Self.execute("/usr/bin/osascript", [path], description: "Script \(path) (\(label))")
                } else {
                    log("Script \(path) (\(label)) not found; skipped")
                }
            }
            DispatchQueue.main.async { self?.pendingKeys.remove(key) }
        }
    }

    /// The user's shortcuts (cached after the first load; `refresh` reloads). Completion runs on the main thread.
    func loadShortcutNames(refresh: Bool = false, completion: @escaping ([String]) -> Void) {
        if let shortcutNames, !refresh {
            completion(shortcutNames)
            return
        }
        shortcutListCallbacks.append(completion)
        guard shortcutListCallbacks.count == 1 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Self.execute("/usr/bin/shortcuts", ["list"], description: "Shortcut list",
                                      captureOutput: true, timeout: Self.listTimeout, logSuccess: false) ?? ""
            let names = output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                guard let self else { return }
                self.shortcutNames = names
                let callbacks = self.shortcutListCallbacks
                self.shortcutListCallbacks = []
                callbacks.forEach { $0(names) }
            }
        }
    }

    /// Runs a tool and waits for it (call off the main thread). Returns stdout when `captureOutput`, else "" on
    /// success; nil if it couldn't start or failed.
    @discardableResult
    private static func execute(_ tool: String, _ arguments: [String], description: String,
                                captureOutput: Bool = false, timeout: TimeInterval = ActionRunner.timeout,
                                logSuccess: Bool = true) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        // Only one pipe is read (stdout when listing, stderr otherwise), so a full pipe can't block the tool.
        let pipe = Pipe()
        if captureOutput {
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = pipe
        }
        if logSuccess { log("Running \(description)") }
        do {
            try process.run()
        } catch {
            log("\(description) could not start: \(error.localizedDescription)")
            return nil
        }
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            log("\(description) still running after \(Int(timeout)) s; stopping it")
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let detail = captureOutput || text.isEmpty ? "" : ": \(text)"
            log("\(description) failed (status \(process.terminationStatus))\(detail)")
            return nil
        }
        if logSuccess { log("\(description) finished") }
        return captureOutput ? text : ""
    }
}
