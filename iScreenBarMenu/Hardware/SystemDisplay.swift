import CoreGraphics
import Foundation

func requestSystemDisplaySleep() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["displaysleepnow"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        log("Could not request display sleep: \(error.localizedDescription)")
        return false
    }
}

func requestSystemDisplayWake() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
    process.arguments = ["-u", "-t", "2"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        return true
    } catch {
        log("Could not request display wake: \(error.localizedDescription)")
        return false
    }
}

func studioDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count)).first {
        CGDisplayIsBuiltin($0) == 0 &&
            CGDisplayIsOnline($0) != 0 &&
            CGDisplayVendorNumber($0) == appleDisplayVendorID &&
            studioDisplayProductIDs.contains(CGDisplayModelNumber($0))
    }
}

func activeBuiltinDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count)).first {
        CGDisplayIsBuiltin($0) != 0 && CGDisplayIsOnline($0) != 0 && CGDisplayIsActive($0) != 0
    }
}

func isConsoleSessionLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}
