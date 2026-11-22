import Darwin
import notify
import Foundation

// Compiled into both the app and the Control Center / widget extension.
// The extension is sandboxed and shares no container with the app (no app group, so the
// committed project stays ad-hoc signed). The app publishes a small lamp snapshot as the
// 64-bit state of a Darwin notification name; the extension reads it with notify_get_state.
// State 0 means the app isn't running (or hasn't published yet).

struct LampState: Equatable {
    static let notificationName = "org.windholm.iScreenBarMenu.state"
    /// Widget kind; the app reloads it when the state changes.
    static let widgetKind = "org.windholm.iScreenBarMenu.Controls.lampLevels"

    static let brightnessSteps = Array(stride(from: 10, through: 100, by: 10))
    static let temperatureSteps = [2700, 3100, 3500, 4000, 4400, 4800, 5200, 5700, 6100, 6500]
    static let brightnessStep = 10
    static let temperatureStep = 500

    var isAppRunning = false
    var isConnected = false
    var isPowerOn = false
    var isAutoTemperatureOn = false
    var isKeepAwakeOn = false
    var brightness: Int?
    var temperature: Int?

    init(isAppRunning: Bool = false, isConnected: Bool = false, isPowerOn: Bool = false,
         isAutoTemperatureOn: Bool = false, isKeepAwakeOn: Bool = false,
         brightness: Int? = nil, temperature: Int? = nil) {
        self.isAppRunning = isAppRunning
        self.isConnected = isConnected
        self.isPowerOn = isPowerOn
        self.isAutoTemperatureOn = isAutoTemperatureOn
        self.isKeepAwakeOn = isKeepAwakeOn
        self.brightness = brightness
        self.temperature = temperature
    }

    // Layout: bit 0 running, 1 connected, 2 power, 3 auto temp, 4 keep awake,
    // bits 8–15 brightness % (0 = unknown), bits 16–23 Kelvin / 100 (0 = unknown).
    init(rawValue: UInt64) {
        isAppRunning = rawValue & 1 != 0
        isConnected = rawValue & 2 != 0
        isPowerOn = rawValue & 4 != 0
        isAutoTemperatureOn = rawValue & 8 != 0
        isKeepAwakeOn = rawValue & 16 != 0
        let percent = Int((rawValue >> 8) & 0xFF)
        let kelvin = Int((rawValue >> 16) & 0xFF) * 100
        brightness = percent > 0 ? percent : nil
        temperature = kelvin > 0 ? kelvin : nil
    }

    var rawValue: UInt64 {
        guard isAppRunning else { return 0 }
        var value: UInt64 = 1
        if isConnected { value |= 2 }
        if isPowerOn { value |= 4 }
        if isAutoTemperatureOn { value |= 8 }
        if isKeepAwakeOn { value |= 16 }
        if let brightness { value |= UInt64(max(1, min(100, brightness))) << 8 }
        if let temperature { value |= UInt64(max(27, min(65, temperature / 100))) << 16 }
        return value
    }

    private static var token: Int32?

    private static func registeredToken() -> Int32? {
        if let token { return token }
        var newToken: Int32 = 0
        guard notify_register_check(notificationName, &newToken) == UInt32(NOTIFY_STATUS_OK) else { return nil }
        token = newToken
        return newToken
    }

    /// The snapshot the app last published (all off / not running if none).
    static func current() -> LampState {
        guard let token = registeredToken() else { return LampState() }
        var raw: UInt64 = 0
        guard notify_get_state(token, &raw) == UInt32(NOTIFY_STATUS_OK) else { return LampState() }
        return LampState(rawValue: raw)
    }

    /// App only. Returns false if the notification system refused the state.
    @discardableResult
    func publish() -> Bool {
        guard let token = Self.registeredToken(),
              notify_set_state(token, rawValue) == UInt32(NOTIFY_STATUS_OK) else { return false }
        notify_post(Self.notificationName)
        return true
    }
}
