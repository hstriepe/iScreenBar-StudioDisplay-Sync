import AppKit
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// The 0.25 s main loop: display sleep → lamp sync, brightness follow and dual-display lock,
/// ambient rules, presence wake, lamp connect/disconnect. Formerly top-level state in main.swift.
final class DisplayLampSync {
    private let lamp: LampController
    private let statusIndicator: StatusIndicator
    private let displayBrightnessReader: DisplayBrightnessReader
    private let studioAmbientSensor: StudioDisplayAmbientSensor
    private var pollingTimer: Timer?

    private var displayID: CGDirectDisplayID?
    private var wasAsleep: Bool
    private var wasConsoleSessionLocked: Bool
    private var helperTurnedLampOff = false
    private var ambientTurnedLampOff: Bool
    private var ambientCloseCandidateSince: Date?
    private var ambientOpenCandidateSince: Date?
    private var ambientProxySamples: [(Date, Int)] = []
    private var ambientProxySourceName: String?
    private var lastLoggedAmbientProxy: Int?
    private var presenceWakeRequestedAt: Date?
    /// When the lamp was first seen off during the current display sleep (nil while awake or while the lamp is on).
    private var lampOffSince: Date?
    private var presenceUserActivityAssertion: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    private var wasBrightnessFollowEnabled: Bool
    private var wasDisplayBrightnessLockEnabled: Bool
    private var wasPowerSyncEnabled: Bool
    private var wasAmbientLinkEnabled: Bool
    private var wasAmbientCloseThreshold: Int?
    private var brightnessOffset: Int?
    private var anchorStatusRevision: Int?
    private var lastDisplayBrightness: Int?
    private var displayBrightnessOffset: Int?
    private var lastBuiltinDisplayBrightness: Int?
    private var lastStudioDisplayBrightnessForLock: Int?
    private var displayBrightnessWriteSuppressedUntil = Date.distantPast
    private var lastStatusRequest = Date.distantPast
    private var wasLampConnected: Bool

    /// `wasConsoleSessionLocked` and `ambientTurnedLampOff` are read before the StatusIndicator is created,
    /// as the top-level code did.
    init(lamp: LampController, statusIndicator: StatusIndicator, displayID: CGDirectDisplayID?, isAsleep: Bool,
         wasConsoleSessionLocked: Bool, ambientTurnedLampOff: Bool,
         displayBrightnessReader: DisplayBrightnessReader, studioAmbientSensor: StudioDisplayAmbientSensor) {
        self.lamp = lamp
        self.statusIndicator = statusIndicator
        self.displayID = displayID
        self.wasAsleep = isAsleep
        self.wasConsoleSessionLocked = wasConsoleSessionLocked
        self.ambientTurnedLampOff = ambientTurnedLampOff
        self.displayBrightnessReader = displayBrightnessReader
        self.studioAmbientSensor = studioAmbientSensor
        wasBrightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
        wasDisplayBrightnessLockEnabled = statusIndicator.isDisplayBrightnessLockEnabled
        wasPowerSyncEnabled = statusIndicator.isPowerSyncEnabled
        wasAmbientLinkEnabled = statusIndicator.isAmbientLinkEnabled
        wasAmbientCloseThreshold = statusIndicator.ambientCloseThreshold
        wasLampConnected = lamp.isConnected
    }

    /// Clears state left by the previous run, then starts the poll timer and runs the first poll.
    func start() {
        if !wasAmbientLinkEnabled, ambientTurnedLampOff || statusIndicator.hasPendingAmbientPresenceRestore {
            if ambientTurnedLampOff, !wasAsleep { _ = lamp.setPower(on: true) }
            setAmbientLampLock(false)
            statusIndicator.restorePresenceAfterAmbientLock()
            log("Cleared light-off and presence pause state left by previous ambient rules")
        }
        if wasBrightnessFollowEnabled {
            anchorStatusRevision = lamp.statusRevision
            lamp.requestStatus()
            log("Studio Display brightness follow on; locking current brightness difference")
        }

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollDisplayAndLamp()
            MainActor.assumeIsolated { publishLampState() }
        }
        timer.tolerance = 0.05
        pollingTimer = timer
        pollDisplayAndLamp()
        MainActor.assumeIsolated { publishLampState() }
    }

    /// Declares local user activity, which wakes a sleeping display like a key press (without unlocking).
    private func declarePresenceUserActivity() -> Bool {
        let result = IOPMAssertionDeclareUserActivity("iScreenBar presence detected" as CFString,
                                                      kIOPMUserActiveLocal, &presenceUserActivityAssertion)
        if result != kIOReturnSuccess {
            log(String(format: "IOPMAssertionDeclareUserActivity failed: 0x%08X", result))
        }
        return result == kIOReturnSuccess
    }

    private func releasePresenceUserActivity() {
        guard presenceUserActivityAssertion != IOPMAssertionID(kIOPMNullAssertionID) else { return }
        IOPMAssertionRelease(presenceUserActivityAssertion)
        presenceUserActivityAssertion = IOPMAssertionID(kIOPMNullAssertionID)
    }

    private func setAmbientLampLock(_ active: Bool) {
        ambientTurnedLampOff = active
        if active {
            UserDefaults.standard.set(true, forKey: "ambientLampLockActive")
        } else {
            UserDefaults.standard.removeObject(forKey: "ambientLampLockActive")
        }
    }

    private func pollDisplayAndLamp() {
        statusIndicator.applyModeForFrontmostAppIfNeeded()
        statusIndicator.checkLampPowerActions()
        let consoleSessionLocked = isConsoleSessionLocked()
        if consoleSessionLocked != wasConsoleSessionLocked {
            if consoleSessionLocked {
                log(requestSystemDisplaySleep()
                    ? "Poll: Mac locked; requested immediate display sleep"
                    : "Poll: Mac locked, but display sleep request failed")
            } else {
                log("Mac unlocked")
            }
            wasConsoleSessionLocked = consoleSessionLocked
        }
        let detectedDisplayID = studioDisplayID()
        if detectedDisplayID != displayID {
            displayID = detectedDisplayID
            brightnessOffset = nil
            lastDisplayBrightness = nil
            lastBuiltinDisplayBrightness = nil
            lastStudioDisplayBrightnessForLock = nil
            anchorStatusRevision = nil
            if let displayID {
                wasAsleep = CGDisplayIsAsleep(displayID) != 0
                log("Studio Display connected: ID=\(displayID), resolution=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
            } else {
                wasAsleep = false
                log("Studio Display disconnected; waiting for reconnect")
            }
            statusIndicator.handleStudioDisplayConnection(connected: displayID != nil)
        }
        let isAsleep = displayID.map { CGDisplayIsAsleep($0) != 0 } ?? false
        let brightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
        let displayBrightnessLockEnabled = statusIndicator.isDisplayBrightnessLockEnabled
        let powerSyncEnabled = statusIndicator.isPowerSyncEnabled
        let ambientLinkEnabled = statusIndicator.isAmbientLinkEnabled
        let ambientCloseThreshold = statusIndicator.ambientCloseThreshold
        let rawAmbientSource = (value: studioAmbientSensor.rawIlluminance(), name: "Studio Display light sensor")
        if ambientProxySourceName != rawAmbientSource.name {
            ambientProxySamples.removeAll()
            ambientProxySourceName = rawAmbientSource.name
            lastLoggedAmbientProxy = nil
            log("Ambient source switched to \(rawAmbientSource.name)")
        }
        let sampleTime = Date()
        if let value = rawAmbientSource.value {
            ambientProxySamples.append((sampleTime, value))
        }
        let sampleCutoff = sampleTime.addingTimeInterval(-10)
        ambientProxySamples.removeAll { $0.0 < sampleCutoff }
        let sortedAmbientValues = ambientProxySamples.map { $0.1 }.sorted()
        let displayAmbientProxy = sortedAmbientValues.isEmpty ? nil : sortedAmbientValues[sortedAmbientValues.count / 2]
        if let displayAmbientProxy, lastLoggedAmbientProxy != displayAmbientProxy {
            log("Ambient score: \(displayAmbientProxy) (\(rawAmbientSource.name), 10 s median)")
            lastLoggedAmbientProxy = displayAmbientProxy
        }
        statusIndicator.updateDisplayAmbientProxy(displayAmbientProxy, sourceName: rawAmbientSource.name)

        // Sleep sync has top priority: while the screen is off, ambient light, presence detection, or the lamp's own logic
        // must not turn the lamp back on. Checking continuously also covers the lamp turning itself on after the screen goes off.
        // Exception (ADR 0008): with Wake Screen on, the lamp's presence detection turning it on wakes the display instead.
        let lampOffSinceBeforeThisTick = lampOffSince
        if !isAsleep || lamp.isPowerOn == true {
            lampOffSince = nil
        } else if lamp.isPowerOn == false, lampOffSince == nil {
            lampOffSince = Date()
        }
        // The sleep transition itself (first asleep tick, lamp still on from before) is handled below.
        if powerSyncEnabled, isAsleep, wasAsleep {
            statusIndicator.suspendPresenceForScreenSleep()
            if lamp.isPowerOn == true {
                // Only an off → on change counts, after the lamp stayed off and the app sent it nothing for the quiet period.
                let lampTurnedItselfOn = lampOffSinceBeforeThisTick.map { offSince in
                    Date().timeIntervalSince(max(offSince, lamp.lastStateCommandAt)) >= presenceWakeQuietPeriod
                } ?? false
                let mayWakeDisplay = statusIndicator.isPresenceWakeEnabled && lamp.isPresenceDetectionEnabled == true &&
                    !ambientTurnedLampOff && lampTurnedItselfOn
                if let requestedAt = presenceWakeRequestedAt,
                   Date().timeIntervalSince(requestedAt) < presenceWakeTimeout {
                    // Waiting for the display to wake.
                } else if presenceWakeRequestedAt == nil, mayWakeDisplay, declarePresenceUserActivity() {
                    presenceWakeRequestedAt = Date()
                    log("Presence detection turned the lamp on; waking the display")
                } else {
                    // Timed out, wake request failed, or not a presence wake: turn the lamp off and start over,
                    // so the next time the lamp turns itself on can wake the display again.
                    let wakeTimedOut = presenceWakeRequestedAt != nil
                    if wakeTimedOut {
                        presenceWakeRequestedAt = nil
                        releasePresenceUserActivity()
                    }
                    let turnedOff = lamp.setPower(on: false)
                    helperTurnedLampOff = helperTurnedLampOff || turnedOff
                    if wakeTimedOut {
                        log("Display stayed asleep after the presence wake request; sleep sync turned the lamp off")
                    } else if mayWakeDisplay {
                        log("Presence detection turned the lamp on, but the display wake request failed; sleep sync turned the lamp off")
                    } else if turnedOff {
                        log("Sleep sync overrode lamp turning itself back on")
                    }
                    statusIndicator.update(isAsleep: true, healthy: turnedOff)
                }
            }
        }
        if !isAsleep, presenceWakeRequestedAt != nil {
            presenceWakeRequestedAt = nil
            releasePresenceUserActivity()
        }

        if wasAmbientCloseThreshold != nil, ambientCloseThreshold == nil, ambientTurnedLampOff {
            if !isAsleep { _ = lamp.setPower(on: true) }
            setAmbientLampLock(false)
            statusIndicator.restorePresenceAfterAmbientLock()
            ambientCloseCandidateSince = nil
            log("Bright-off rule disabled; released off-lock and restored presence detection")
        }
        wasAmbientCloseThreshold = ambientCloseThreshold

        if ambientLinkEnabled != wasAmbientLinkEnabled {
            ambientCloseCandidateSince = nil
            ambientOpenCandidateSince = nil
            if !ambientLinkEnabled, ambientTurnedLampOff {
                if !isAsleep { _ = lamp.setPower(on: true) }
                setAmbientLampLock(false)
                statusIndicator.restorePresenceAfterAmbientLock()
                log("Ambient link off; released ambient light-off state")
            }
            wasAmbientLinkEnabled = ambientLinkEnabled
        }

        if ambientLinkEnabled, !isAsleep, let displayAmbientProxy {
            if ambientTurnedLampOff {
                statusIndicator.maintainPresenceSuspendedForAmbientLock()
                ambientCloseCandidateSince = nil
                let reachedOpenPoint = statusIndicator.ambientOpenThreshold.map { displayAmbientProxy <= $0 } ?? false
                // Keep the user-calibrated "dim: on" point as a fast trigger; ordinary dimming recovers with narrow hysteresis and a delay.
                // Once timing starts, brief fluctuations are allowed; only rising clearly above the off point again cancels it,
                // so momentary Studio Display sensor spikes don't keep resetting the turn-on timer.
                let gradualMargin = statusIndicator.ambientCloseThreshold.map {
                    max(8, min(20, Int((Double($0) * 0.04).rounded())))
                }
                let gradualOpenPoint = statusIndicator.ambientCloseThreshold.flatMap { close in
                    gradualMargin.map { close - $0 }
                }
                let gradualCancelPoint = statusIndicator.ambientCloseThreshold.flatMap { close in
                    gradualMargin.map { close + $0 }
                }
                let reachedGradualOpenPoint = gradualOpenPoint.map { displayAmbientProxy <= $0 } ?? false
                let mayContinueGradualOpening = ambientOpenCandidateSince != nil &&
                    (gradualCancelPoint.map { displayAmbientProxy < $0 } ?? false)
                let shouldBeginOpening = reachedOpenPoint || reachedGradualOpenPoint || mayContinueGradualOpening
                if reachedOpenPoint {
                    if ambientOpenCandidateSince == nil { ambientOpenCandidateSince = Date() }
                    if let since = ambientOpenCandidateSince, Date().timeIntervalSince(since) >= 30 {
                        if lamp.setPower(on: true) {
                            setAmbientLampLock(false)
                            ambientOpenCandidateSince = nil
                            statusIndicator.restorePresenceAfterAmbientLock()
                            log("Ambient below on point; released ambient off-lock")
                        }
                    } else if lamp.isPowerOn == true {
                        _ = lamp.setPower(on: false)
                    }
                } else if shouldBeginOpening {
                    if ambientOpenCandidateSince == nil {
                        ambientOpenCandidateSince = Date()
                        if let gradualOpenPoint {
                            log("Ambient stayed below gradual on point \(gradualOpenPoint); starting delayed confirmation")
                        }
                    }
                    if let since = ambientOpenCandidateSince,
                       Date().timeIntervalSince(since) >= 45,
                       statusIndicator.ambientCloseThreshold.map({ displayAmbientProxy < $0 }) == true {
                        if lamp.setPower(on: true) {
                            setAmbientLampLock(false)
                            ambientOpenCandidateSince = nil
                            statusIndicator.restorePresenceAfterAmbientLock()
                            log("Ambient kept dimming; gradually restored iScreenBar")
                        }
                    } else if lamp.isPowerOn == true {
                        _ = lamp.setPower(on: false)
                    }
                } else {
                    ambientOpenCandidateSince = nil
                    if lamp.isPowerOn == true, lamp.setPower(on: false) {
                        log("Ambient off-lock overrode lamp turning itself back on")
                    }
                }
            } else if lamp.isPowerOn == true {
                ambientOpenCandidateSince = nil
                if let closeThreshold = statusIndicator.ambientCloseThreshold,
                   displayAmbientProxy >= closeThreshold {
                    if ambientCloseCandidateSince == nil { ambientCloseCandidateSince = Date() }
                    if let since = ambientCloseCandidateSince, Date().timeIntervalSince(since) >= 30 {
                        if statusIndicator.suspendPresenceForAmbientLock(), lamp.setPower(on: false) {
                            setAmbientLampLock(true)
                            ambientCloseCandidateSince = nil
                            log("Ambient above off point; turned iScreenBar off")
                        } else {
                            statusIndicator.restorePresenceAfterAmbientLock()
                        }
                    }
                } else {
                    ambientCloseCandidateSince = nil
                }
            } else {
                ambientCloseCandidateSince = nil
                if let closeThreshold = statusIndicator.ambientCloseThreshold,
                   displayAmbientProxy >= closeThreshold {
                    setAmbientLampLock(true)
                    ambientOpenCandidateSince = nil
                    _ = statusIndicator.suspendPresenceForAmbientLock()
                    log("Lamp off and ambient still above off point; off-lock restored")
                } else if let openThreshold = statusIndicator.ambientOpenThreshold,
                   displayAmbientProxy <= openThreshold {
                    if ambientOpenCandidateSince == nil { ambientOpenCandidateSince = Date() }
                    if let since = ambientOpenCandidateSince, Date().timeIntervalSince(since) >= 30 {
                        if lamp.setPower(on: true) {
                            setAmbientLampLock(false)
                            ambientOpenCandidateSince = nil
                            log("Ambient below on point; turned iScreenBar on")
                        }
                    }
                } else {
                    ambientOpenCandidateSince = nil
                }
            }
        } else {
            ambientCloseCandidateSince = nil
            ambientOpenCandidateSince = nil
        }

        if powerSyncEnabled != wasPowerSyncEnabled {
            if powerSyncEnabled, isAsleep {
                statusIndicator.suspendPresenceForScreenSleep()
                helperTurnedLampOff = lamp.setPower(on: false)
            } else if !powerSyncEnabled {
                if helperTurnedLampOff { _ = lamp.setPower(on: true) }
                helperTurnedLampOff = false
                statusIndicator.restorePresenceAfterScreenWake()
            }
            wasPowerSyncEnabled = powerSyncEnabled
            statusIndicator.update(isAsleep: isAsleep, healthy: true)
        }

        if brightnessFollowEnabled != wasBrightnessFollowEnabled || statusIndicator.brightnessFollowReanchorRequested {
            statusIndicator.brightnessFollowReanchorRequested = false
            brightnessOffset = nil
            lastDisplayBrightness = nil
            if brightnessFollowEnabled {
                anchorStatusRevision = lamp.statusRevision
                lamp.requestStatus()
            } else {
                anchorStatusRevision = nil
            }
            wasBrightnessFollowEnabled = brightnessFollowEnabled
            statusIndicator.update(isAsleep: isAsleep, healthy: true)
        }

        if displayBrightnessLockEnabled != wasDisplayBrightnessLockEnabled {
            displayBrightnessOffset = nil
            lastBuiltinDisplayBrightness = nil
            lastStudioDisplayBrightnessForLock = nil
            displayBrightnessWriteSuppressedUntil = Date.distantPast
            wasDisplayBrightnessLockEnabled = displayBrightnessLockEnabled
        }

        if isAsleep != wasAsleep {
            if isAsleep {
                log("Studio Display went to sleep")
                if powerSyncEnabled {
                    statusIndicator.suspendPresenceForScreenSleep()
                    helperTurnedLampOff = lamp.setPower(on: false)
                    statusIndicator.update(isAsleep: true, healthy: helperTurnedLampOff)
                } else {
                    statusIndicator.update(isAsleep: true, healthy: true)
                }
            } else {
                log("Studio Display woke")
                if helperTurnedLampOff, !ambientTurnedLampOff {
                    let restored = lamp.setPower(on: true)
                    statusIndicator.update(isAsleep: false, healthy: restored)
                    helperTurnedLampOff = false
                } else {
                    helperTurnedLampOff = false
                    statusIndicator.update(isAsleep: false, healthy: true)
                }
                statusIndicator.restorePresenceAfterScreenWake()
            }
            wasAsleep = isAsleep
        }

        statusIndicator.applyScheduledTemperatureIfNeeded(isAsleep: isAsleep)

        if displayBrightnessLockEnabled,
           !isAsleep,
           !isConsoleSessionLocked(),
           let studioID = displayID,
           let builtinID = activeBuiltinDisplayID(),
           let studioBrightness = displayBrightnessReader.percent(for: studioID),
           let builtinBrightness = displayBrightnessReader.percent(for: builtinID) {
            if displayBrightnessOffset == nil || lastBuiltinDisplayBrightness == nil || lastStudioDisplayBrightnessForLock == nil {
                let isNewLock = displayBrightnessOffset == nil
                if isNewLock {
                    displayBrightnessOffset = builtinBrightness - studioBrightness
                }
                lastBuiltinDisplayBrightness = builtinBrightness
                lastStudioDisplayBrightnessForLock = studioBrightness
                if isNewLock {
                    log("Locked dual-display brightness difference: MacBook \(builtinBrightness)% / Studio Display \(studioBrightness)%")
                }
            } else if Date() >= displayBrightnessWriteSuppressedUntil,
                      let offset = displayBrightnessOffset,
                      let previousBuiltin = lastBuiltinDisplayBrightness,
                      let previousStudio = lastStudioDisplayBrightnessForLock {
                let builtinDelta = builtinBrightness - previousBuiltin
                let studioDelta = studioBrightness - previousStudio
                if builtinDelta != 0 || studioDelta != 0 {
                    if abs(builtinDelta) > abs(studioDelta) {
                        let targetStudio = max(0, min(100, builtinBrightness - offset))
                        if targetStudio == studioBrightness || displayBrightnessReader.setPercent(targetStudio, for: studioID) {
                            lastBuiltinDisplayBrightness = builtinBrightness
                            lastStudioDisplayBrightnessForLock = targetStudio
                            displayBrightnessWriteSuppressedUntil = Date().addingTimeInterval(0.6)
                        }
                    } else {
                        let targetBuiltin = max(0, min(100, studioBrightness + offset))
                        if targetBuiltin == builtinBrightness || displayBrightnessReader.setPercent(targetBuiltin, for: builtinID) {
                            lastBuiltinDisplayBrightness = targetBuiltin
                            lastStudioDisplayBrightnessForLock = studioBrightness
                            displayBrightnessWriteSuppressedUntil = Date().addingTimeInterval(0.6)
                        }
                    }
                }
            }
        } else {
            lastBuiltinDisplayBrightness = nil
            lastStudioDisplayBrightnessForLock = nil
        }

        if brightnessFollowEnabled, !isAsleep, let displayID,
           let displayBrightness = displayBrightnessReader.percent(for: displayID) {
            if let anchorRevision = anchorStatusRevision,
               lamp.statusRevision > anchorRevision,
               let lampBrightness = lamp.currentBrightness {
                if lamp.isAutoLightEnabled == true {
                    log("Lamp auto-light still running; brightness follow takes effect after auto-light is off")
                    brightnessOffset = nil
                    lastDisplayBrightness = displayBrightness
                } else {
                    brightnessOffset = lampBrightness - displayBrightness
                    lastDisplayBrightness = displayBrightness
                    log("Locked brightness difference: iScreenBar \(lampBrightness)% / Studio Display \(displayBrightness)%")
                }
                anchorStatusRevision = nil
            } else if let brightnessOffset, displayBrightness != lastDisplayBrightness {
                let target = max(1, min(100, displayBrightness + brightnessOffset))
                if lamp.setBrightness(target) {
                    lastDisplayBrightness = displayBrightness
                }
            }
        }

        if Date().timeIntervalSince(lastStatusRequest) >= 2 {
            let connected = lamp.checkConnection()
            if connected != wasLampConnected {
                if connected {
                    log("iScreenBar reconnected; restoring sync state")
                    if powerSyncEnabled {
                        if isAsleep {
                            helperTurnedLampOff = lamp.setPower(on: false)
                        } else if !ambientTurnedLampOff {
                            _ = lamp.setPower(on: true)
                        }
                    }
                    if brightnessFollowEnabled {
                        brightnessOffset = nil
                        lastDisplayBrightness = nil
                        anchorStatusRevision = lamp.statusRevision
                        lamp.requestStatus()
                    }
                } else {
                    log("iScreenBar disconnected")
                    brightnessOffset = nil
                    anchorStatusRevision = nil
                }
                wasLampConnected = connected
            }
            statusIndicator.update(isAsleep: isAsleep, healthy: connected && displayID != nil)
            lastStatusRequest = Date()
        }
    }
}
