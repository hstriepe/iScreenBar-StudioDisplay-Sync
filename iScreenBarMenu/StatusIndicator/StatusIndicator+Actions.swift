import Foundation

/// How long a reported lamp power change must hold before the Lamp On / Lamp Off action runs.
private let lampActionSettleTime: TimeInterval = 2

// Mode actions and Lamp On / Lamp Off actions: Shortcuts and AppleScripts run by ActionRunner (ADR 0011).
extension StatusIndicator {
    /// Runs a mode's Shortcut and script. Skipped while the display sleeps or the session is locked.
    func runModeActions(_ mode: LightMode, restoring: Bool = false) {
        guard let actions = mode.actions, !actions.isEmpty else { return }
        let label = restoring ? "restored mode \(mode.name)" : "mode \(mode.name)"
        guard !isAsleep, !isConsoleSessionLocked() else {
            log("Actions for \(label) skipped: display asleep or session locked")
            return
        }
        ActionRunner.shared.run(actions, key: "mode \(mode.id)", label: label)
    }

    /// Called every poll. Runs the Lamp On / Lamp Off action when the lamp's reported power state changed and the new
    /// state held for `lampActionSettleTime`. The first report after launch or a reconnect only sets the baseline.
    func checkLampPowerActions() {
        guard lamp.isConnected, let reported = lamp.reportedPowerOn else {
            lampPowerBaseline = nil
            lampPowerCandidate = nil
            return
        }
        guard let baseline = lampPowerBaseline else {
            lampPowerBaseline = reported
            return
        }
        // After the app turned the lamp on itself, wait for a report sent after that command.
        guard lamp.statusRevision > lampPowerIgnoreThroughRevision else { return }
        guard reported != baseline else {
            lampPowerCandidate = nil
            return
        }
        guard let candidate = lampPowerCandidate, candidate.on == reported else {
            lampPowerCandidate = (reported, Date())
            return
        }
        guard Date().timeIntervalSince(candidate.since) >= lampActionSettleTime else { return }
        lampPowerBaseline = reported
        lampPowerCandidate = nil
        runLampAction(on: reported)
    }

    /// A mode turned the lamp on: run the Lamp On action now, before the mode's own actions, instead of after the
    /// settle time.
    func lampTurnedOnByApp() {
        guard lampPowerBaseline == false else { return }
        lampPowerBaseline = true
        lampPowerCandidate = nil
        lampPowerIgnoreThroughRevision = lamp.statusRevision
        runLampAction(on: true)
    }

    private func runLampAction(on: Bool) {
        let key = on ? ModeAction.lampOnKey : ModeAction.lampOffKey
        guard let action = ModeAction.stored(forKey: key) else { return }
        var context: [String] = []
        if isAsleep { context.append("display asleep") }
        if isConsoleSessionLocked() { context.append("session locked") }
        let label = "lamp \(on ? "on" : "off")" + (context.isEmpty ? "" : ", " + context.joined(separator: ", "))
        ActionRunner.shared.run(action, key: key, label: label)
    }
}
