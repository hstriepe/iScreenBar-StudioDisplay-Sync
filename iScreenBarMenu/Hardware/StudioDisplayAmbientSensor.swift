import Foundation
import IOKit.hid

final class StudioDisplayAmbientSensor {
    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private var illuminanceElement: IOHIDElement?
    private var lastReconnectAttempt = Date.distantPast

    init() {
        manager = Self.makeManager()
        guard openManager() else {
            log("Could not open Studio Display ambient light sensor")
            return
        }
        if !attachSensor() {
            let ids = studioDisplaySensorProductIDs.map { String(format: "0x%04X", $0) }.joined(separator: ", ")
            log("Studio Display ambient light sensor not found (VID 0x05AC, PID \(ids))")
        }
    }

    deinit {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func rawIlluminance() -> Int? {
        if device == nil || illuminanceElement == nil,
           !attachSensor(),
           !reconnectIfNeeded() {
            return nil
        }
        if let value = readCurrentValue() { return value }

        // The Studio Display recreates its HID service after lock, sleep, or display rearrangement.
        // The old IOHIDDevice may still exist but GetValue keeps failing, so the manager must be rebuilt.
        device = nil
        illuminanceElement = nil
        guard reconnectIfNeeded() else { return nil }
        return readCurrentValue()
    }

    private static func makeManager() -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = studioDisplaySensorProductIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: 0x05AC,
                kIOHIDProductIDKey as String: productID,
                kIOHIDPrimaryUsagePageKey as String: 0x20,
                kIOHIDPrimaryUsageKey as String: 0x41
            ]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        return manager
    }

    private func openManager() -> Bool {
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
    }

    private func readCurrentValue() -> Int? {
        guard let device, let illuminanceElement else { return nil }
        var rawValue: Unmanaged<IOHIDValue> = .fromOpaque(UnsafeRawPointer(bitPattern: 1)!)
        guard IOHIDDeviceGetValue(device, illuminanceElement, &rawValue) == kIOReturnSuccess else {
            return nil
        }
        let raw = IOHIDValueGetIntegerValue(rawValue.takeUnretainedValue())
        // The Studio Display reports in roughly thousandths of a lux; convert to a readable relative ambient score.
        return max(0, raw / 1_000)
    }

    private func reconnectIfNeeded() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastReconnectAttempt) >= 2 else { return false }
        lastReconnectAttempt = now
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = Self.makeManager()
        guard openManager(), attachSensor() else { return false }
        log("Studio Display ambient light sensor reconnected")
        return true
    }

    private func attachSensor() -> Bool {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else { return false }
        let elements = (IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        guard let element = elements.first(where: {
            IOHIDElementGetUsagePage($0) == 0x20 && IOHIDElementGetUsage($0) == 0x04D1
        }) else { return false }
        self.device = device
        illuminanceElement = element
        return true
    }
}
