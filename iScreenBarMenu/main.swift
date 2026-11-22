import AppKit
import CoreGraphics
import Foundation

// Entry point. The app's types live in App/, Hardware/, Models/, UI/, StatusIndicator/, Sync/ and Automation/.
importPreRenameSettingsIfNeeded()

private let initialDisplayID = studioDisplayID()
private let lamp = LampController()
private let displayBrightnessReader = DisplayBrightnessReader()
private let studioAmbientSensor = StudioDisplayAmbientSensor()

if let initialDisplayID {
    log("Monitoring Studio Display ID=\(initialDisplayID), resolution=\(CGDisplayPixelsWide(initialDisplayID))x\(CGDisplayPixelsHigh(initialDisplayID))")
} else {
    log("No external display found; waiting for Studio Display to connect")
}
private let initiallyAsleep = initialDisplayID.map { CGDisplayIsAsleep($0) != 0 } ?? false
private let initiallyConsoleSessionLocked = isConsoleSessionLocked()
private let initialAmbientLampLock = UserDefaults.standard.bool(forKey: "ambientLampLockActive")

private let statusIndicator = StatusIndicator(isAsleep: initiallyAsleep, lamp: lamp)
automationTarget = statusIndicator
installControlActionObserver()
statusIndicator.handleStudioDisplayConnection(connected: initialDisplayID != nil)
if !initiallyAsleep {
    statusIndicator.restorePresenceAfterScreenWake()
}

private let displayLampSync = DisplayLampSync(lamp: lamp, statusIndicator: statusIndicator, displayID: initialDisplayID,
                                      isAsleep: initiallyAsleep, wasConsoleSessionLocked: initiallyConsoleSessionLocked,
                                      ambientTurnedLampOff: initialAmbientLampLock,
                                      displayBrightnessReader: displayBrightnessReader,
                                      studioAmbientSensor: studioAmbientSensor)
displayLampSync.start()
NSApplication.shared.run()
