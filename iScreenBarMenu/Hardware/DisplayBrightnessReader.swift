import CoreGraphics
import Darwin
import Foundation

final class DisplayBrightnessReader {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let handle: UnsafeMutableRawPointer?
    private let getter: GetBrightness?
    private let setter: SetBrightness?

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getter = unsafeBitCast(symbol, to: GetBrightness.self)
        } else {
            getter = nil
        }
        if let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            setter = unsafeBitCast(symbol, to: SetBrightness.self)
        } else {
            setter = nil
        }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func percent(for displayID: CGDirectDisplayID) -> Int? {
        guard let getter else { return nil }
        var value: Float = 0
        guard getter(displayID, &value) == 0 else { return nil }
        return Int((max(0, min(1, value)) * 100).rounded())
    }

    func setPercent(_ percent: Int, for displayID: CGDirectDisplayID) -> Bool {
        guard let setter else { return false }
        let value = Float(max(0, min(100, percent))) / 100
        return setter(displayID, value) == 0
    }
}
