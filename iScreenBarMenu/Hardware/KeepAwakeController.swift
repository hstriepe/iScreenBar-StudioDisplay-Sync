import Foundation

/// Two-layer keep-awake (as in NotchNotes): caffeinate holds the idle assertion,
/// pmset disablesleep covers forced sleep paths such as lid close. Both are tied to the app PID.
final class KeepAwakeController {
    private var caffeinateProcess: Process?
    private var sleepGuardProcess: Process?
    private var readyFileURL: URL?
    private var stopFileURL: URL?

    var isActive: Bool {
        caffeinateProcess?.isRunning == true &&
            (sleepGuardProcess?.isRunning == true || readyFileURL.map {
                FileManager.default.fileExists(atPath: $0.path)
            } == true)
    }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        if active {
            guard !isActive else { return true }
            setActive(false)

            let token = UUID().uuidString
            let base = "iScreenBar-KeepAwake-\(ProcessInfo.processInfo.processIdentifier)-\(token)"
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let ready = temporaryDirectory.appendingPathComponent(base).appendingPathExtension("ready")
            let stop = temporaryDirectory.appendingPathComponent(base).appendingPathExtension("stop")
            let pid = ProcessInfo.processInfo.processIdentifier
            let readyPath = Self.shellQuote(ready.path)
            let stopPath = Self.shellQuote(stop.path)
            let command = [
                "owned=0",
                "cleanup() { if [ \"$owned\" = 1 ]; then /usr/bin/pmset -a disablesleep 0; fi; /bin/rm -f \(readyPath) \(stopPath); }",
                "trap cleanup 0",
                "trap 'exit 1' 1 2 15",
                "if ! /usr/bin/pmset -g | /usr/bin/grep -Eq 'SleepDisabled[[:space:]]+1'; then /usr/bin/pmset -a disablesleep 1 || exit 1; owned=1; fi",
                "/usr/bin/pmset -g | /usr/bin/grep -Eq 'SleepDisabled[[:space:]]+1' || exit 1",
                "/usr/bin/touch \(readyPath) || exit 1",
                "while /bin/kill -0 \(pid) 2>/dev/null && [ ! -e \(stopPath) ]; do /bin/sleep 1; done"
            ].joined(separator: "; ")
            let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "with timeout of 2147483647 seconds\n do shell script \"\(escaped)\" with administrator privileges\nend timeout"

            let guardProcess = Process()
            guardProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            guardProcess.arguments = ["-e", appleScript]
            guardProcess.standardOutput = FileHandle.nullDevice
            guardProcess.standardError = FileHandle.nullDevice

            let caffeinate = Process()
            caffeinate.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            // Prevent system, disk, and idle sleep, but let the display sleep normally.
            caffeinate.arguments = ["-ims", "-w", String(pid)]
            do {
                try guardProcess.run()
                try caffeinate.run()
                sleepGuardProcess = guardProcess
                caffeinateProcess = caffeinate
                readyFileURL = ready
                stopFileURL = stop
                guardProcess.terminationHandler = { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.readyFileURL == ready,
                              !FileManager.default.fileExists(atPath: ready.path) else { return }
                        if let caffeinate = self.caffeinateProcess, caffeinate.isRunning {
                            caffeinate.terminate()
                        }
                        self.caffeinateProcess = nil
                        self.sleepGuardProcess = nil
                        self.readyFileURL = nil
                        self.stopFileURL = nil
                        log("Keep-awake authorization was cancelled or failed to start")
                    }
                }
                return true
            } catch {
                if guardProcess.isRunning { guardProcess.terminate() }
                if caffeinate.isRunning { caffeinate.terminate() }
                try? FileManager.default.removeItem(at: ready)
                try? FileManager.default.removeItem(at: stop)
                log("Could not start keep-awake: \(error.localizedDescription)")
                return false
            }
        }

        if let stopFileURL {
            FileManager.default.createFile(atPath: stopFileURL.path, contents: Data())
        }
        if let caffeinateProcess, caffeinateProcess.isRunning { caffeinateProcess.terminate() }
        caffeinateProcess = nil
        sleepGuardProcess = nil
        readyFileURL = nil
        stopFileURL = nil
        return true
    }

    deinit { _ = setActive(false) }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
