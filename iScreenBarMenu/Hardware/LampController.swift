import Foundation
import IOKit.hid

final class LampController {
    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private(set) var currentBrightness: Int?
    private(set) var currentTemperature: Int?
    private(set) var isPowerOn: Bool?
    /// Power state from the lamp's last status report only (not from the app's own commands); nil until a report
    /// arrives and again after a reconnect. Lamp On / Lamp Off actions use it (ADR 0011).
    private(set) var reportedPowerOn: Bool?
    private(set) var isAutoLightEnabled: Bool?
    private(set) var isPresenceDetectionEnabled: Bool?
    private(set) var isVideoModeEnabled: Bool?
    private(set) var statusRevision = 0
    private var lastTemperatureValues: (Int, Int)?
    private var lastStatusHex: String?
    /// Last power, auto-light, or presence-detection command from the app. Any of them can make the lamp switch
    /// itself on or off, so Wake Screen ignores lamp changes shortly after one (ADR 0008).
    private(set) var lastStateCommandAt = Date.distantPast
    /// Auto-light state set by the app's own command, kept for a short while so a status report sent before the lamp
    /// applied the command can't flip it back (a brightness write exits auto-light in the firmware).
    private var commandedAutoLight: (enabled: Bool, until: Date)?
    private static let autoLightCommandSettleTime: TimeInterval = 1.5

    var isConnected: Bool { device != nil }

    init() {
        manager = Self.makeManager()
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            log("Could not open iScreenBar USB HID device")
            return
        }
        guard attachFirstDevice() else {
            log("iScreenBar USB HID device not found; waiting for reconnect")
            return
        }
        _ = requestStatus()
    }

    deinit {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    func setPower(on: Bool) -> Bool {
        lastStateCommandAt = Date()
        if sendPowerReport(on: on) {
            isPowerOn = on
            log("Lamp \(on ? "on" : "off")")
            return true
        }

        log("USB HID connection lost; reconnecting")
        guard reconnect(), sendPowerReport(on: on) else {
            log("USB HID command still failing after reconnect")
            return false
        }

        isPowerOn = on
        log("Reconnected; lamp \(on ? "on" : "off")")
        return true
    }

    func setBrightness(_ brightness: Int) -> Bool {
        let value = UInt8(clamping: max(1, min(100, brightness)))
        guard sendCommand(0x04, payload: [value, value]) else { return false }
        currentBrightness = Int(value)
        if isAutoLightEnabled != false || commandedAutoLight != nil {
            noteAutoLightCommand(enabled: false)
        }
        log("Lamp brightness set to \(brightness)%")
        return true
    }

    func setTemperature(_ temperature: Int) -> Bool {
        let value = max(2700, min(6500, temperature))
        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        // The iScreenBar has separate color temperatures for the main and back light; both need the full 16-bit Kelvin value.
        guard sendCommand(0x03, payload: [high, low, high, low]) else { return false }
        currentTemperature = value
        log("Lamp color temperature set to \(value)K (main and back light)")
        return true
    }

    func setAutoLight(enabled: Bool) -> Bool {
        if isAutoLightEnabled == enabled {
            return true
        }
        lastStateCommandAt = Date()
        if enabled {
            // The official app enters auto-light with 01 F0 01 04 F5.
            guard sendCommand(0x01, payload: []) else { return false }
        } else {
            // The firmware does not exit auto-light with the same command; the official logic exits by writing a manual brightness.
            guard let brightness = currentBrightness else {
                log("Current brightness unknown; cannot turn off auto-light")
                return false
            }
            guard setBrightness(brightness) else { return false }
        }
        noteAutoLightCommand(enabled: enabled)
        log(enabled ? "Auto-light on" : "Auto-light off")
        return true
    }

    func setPresenceDetection(enabled: Bool, delaySeconds: Int, sensitivity: Int) -> Bool {
        lastStateCommandAt = Date()
        let basePayload = [UInt8(enabled ? 1 : 0)]
        let delayMinutes = UInt8(clamping: delaySeconds / 60)
        let sensitivityValue = UInt8(clamping: max(0, min(2, sensitivity)))
        if !sendCommand(0x06, payload: basePayload + [delayMinutes, sensitivityValue]) {
            if !sendCommand(0x06, payload: basePayload) {
                return false
            }
            log("Sending presence delay failed; fell back to on/off command only")
        }
        isPresenceDetectionEnabled = enabled
        presenceDetectionDelaySeconds = delaySeconds
        log(enabled ? "Presence detection on" : "Presence detection off")
        return true
    }

    private(set) var presenceDetectionDelaySeconds: Int?

    private func noteAutoLightCommand(enabled: Bool) {
        isAutoLightEnabled = enabled
        commandedAutoLight = (enabled, Date().addingTimeInterval(Self.autoLightCommandSettleTime))
    }

    /// Status-report auto-light bit, unless it contradicts a command the app sent moments ago.
    private func acceptReportedAutoLight(_ reported: Bool) {
        if let commanded = commandedAutoLight, Date() < commanded.until {
            if reported != commanded.enabled {
                log("Ignoring stale auto-light \(reported ? "on" : "off") in status report (commanded \(commanded.enabled ? "on" : "off"))")
            }
            return
        }
        commandedAutoLight = nil
        isAutoLightEnabled = reported
    }

    func setVideoMode(enabled: Bool) -> Bool {
        guard sendCommand(0x09, payload: [enabled ? 1 : 0]) else { return false }
        isVideoModeEnabled = enabled
        log(enabled ? "Video mode on" : "Video mode off")
        return true
    }

    @discardableResult
    func requestStatus() -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x20
        report[3] = 0x04
        report[4] = 0x14
        return send(report)
    }

    func checkConnection() -> Bool {
        if requestStatus() { return true }
        guard reconnect(), requestStatus() else { return false }
        log("USB HID reconnected")
        return true
    }

    private func sendPowerReport(on: Bool) -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = 0x07
        report[3] = 0x05
        report[4] = on ? 0xFD : 0xFC
        report[5] = on ? 0x01 : 0x00
        return send(report)
    }

    private func sendCommand(_ command: UInt8, payload: [UInt8]) -> Bool {
        var report = [UInt8](repeating: 0, count: 33)
        report[0] = 0x01
        report[1] = 0xF0
        report[2] = command
        report[3] = UInt8(payload.count + 4)
        report[4] = UInt8(truncatingIfNeeded: Int(report[1]) + Int(command) + Int(report[3]) + payload.reduce(0) { $0 + Int($1) })
        for (index, value) in payload.enumerated() {
            report[5 + index] = value
        }
        return send(report)
    }

    private func send(_ report: [UInt8]) -> Bool {
        guard let device else { return false }
        let result = report.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 1,
                                 bytes.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
        if result != kIOReturnSuccess {
            log(String(format: "USB HID command failed: 0x%08X", result))
        }
        return result == kIOReturnSuccess
    }

    private func configureInputCallback(for device: IOHIDDevice) {
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, 64,
            { context, _, _, _, _, report, reportLength in
                guard let context, reportLength >= 5 else { return }
                let controller = Unmanaged<LampController>.fromOpaque(context).takeUnretainedValue()
                if report[0] == 0x02, report[1] == 0xE1, report[2] == 0x20,
                   report[3] == 0x0D, reportLength >= 15 {
                    let statusHex = (0..<reportLength).map { String(format: "%02X", report[$0]) }.joined(separator: " ")
                    if controller.lastStatusHex != statusHex {
                        controller.lastStatusHex = statusHex
                        log("Raw status report: \(statusHex)")
                    }
                    controller.isPowerOn = (report[6] & 0x01) != 0
                    controller.reportedPowerOn = controller.isPowerOn
                    controller.acceptReportedAutoLight((report[6] & 0x04) != 0)
                    controller.isPresenceDetectionEnabled = (report[6] & 0x20) != 0
                    controller.isVideoModeEnabled = (report[6] & 0x80) != 0
                    let mainTemperature = (Int(report[8]) << 8) | Int(report[9])
                    let backTemperature = (Int(report[11]) << 8) | Int(report[12])
                    if controller.lastTemperatureValues?.0 != mainTemperature ||
                        controller.lastTemperatureValues?.1 != backTemperature {
                        controller.lastTemperatureValues = (mainTemperature, backTemperature)
                        log("Color temperature readback: main=\(mainTemperature)K, back=\(backTemperature)K")
                    }
                    controller.currentTemperature = mainTemperature
                    controller.currentBrightness = Int(report[10])
                    controller.statusRevision += 1
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func reconnect() -> Bool {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        device = nil
        reportedPowerOn = nil
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = Self.makeManager()
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        return attachFirstDevice()
    }

    private static func makeManager() -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: benqVendorID,
            kIOHIDProductIDKey as String: iScreenBarProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        return manager
    }

    private func attachFirstDevice() -> Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let first = devices.first else { return false }
        device = first
        configureInputCallback(for: first)
        return true
    }
}
