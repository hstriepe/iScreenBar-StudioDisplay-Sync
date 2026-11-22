import AppKit
import CoreGraphics
import IOKit

final class DisplayController {
    private var studioCover: NSWindow?
    var isStudioCovered: Bool { studioCover != nil }

    func studioTarget() -> CGDirectDisplayID? {
        return NSScreen.screens.first {
            $0.localizedName.replacingOccurrences(of: " ", with: "").lowercased().contains("studiodisplay")
        }.flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    }

    func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return true }
        defer { IOObjectRelease(root) }
        return (IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool) ?? true
    }

    func setStudioEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            studioCover?.orderOut(nil)
            studioCover = nil
            return true
        }
        guard let id = studioTarget(), let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) else { return false }
        if studioCover != nil { return true }
        // Draws an overlay only; does not change display power, brightness, resolution, main display, or window layout.
        let cover = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        cover.backgroundColor = .black
        cover.isOpaque = true
        cover.hasShadow = false
        cover.isReleasedWhenClosed = false
        cover.level = .statusBar
        cover.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = BlackDisplayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.restore = { [weak self] in _ = self?.setStudioEnabled(true) }
        cover.contentView = view
        studioCover = cover
        cover.orderFrontRegardless()
        return true
    }
    private typealias GetDisplayList = @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let skyLightHandle: UnsafeMutableRawPointer?
    private let monitorPanelHandle: UnsafeMutableRawPointer?
    private let getDisplayList: GetDisplayList?
    private let configureEnabled: ConfigureEnabled?
    private var lastKnownBuiltinDisplayID: CGDirectDisplayID?

    init() {
        skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        monitorPanelHandle = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY)
        if let handle = skyLightHandle, let symbol = dlsym(handle, "CGSGetDisplayList") {
            getDisplayList = unsafeBitCast(symbol, to: GetDisplayList.self)
        } else { getDisplayList = nil }
        if let handle = skyLightHandle, let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") {
            configureEnabled = unsafeBitCast(symbol, to: ConfigureEnabled.self)
        } else { configureEnabled = nil }
        _ = builtinDisplay()
    }

    deinit {
        if let skyLightHandle { dlclose(skyLightHandle) }
        if let monitorPanelHandle { dlclose(monitorPanelHandle) }
    }

    var isAvailable: Bool { getDisplayList != nil && configureEnabled != nil && monitorPanelHandle != nil }

    private func displays() -> [CGDirectDisplayID] {
        guard let getDisplayList else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard getDisplayList(32, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func isGhost(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsOnline(id) == 0 && CGDisplayVendorNumber(id) == 0 &&
            CGDisplayModelNumber(id) == 0 && CGDisplaySerialNumber(id) == 0
    }

    func builtinDisplay() -> CGDirectDisplayID? {
        if let builtin = displays().first(where: { CGDisplayIsBuiltin($0) != 0 && !isGhost($0) }) {
            lastKnownBuiltinDisplayID = builtin
            return builtin
        }
        if let cached = lastKnownBuiltinDisplayID, CGDisplayIsBuiltin(cached) != 0 {
            return cached
        }
        return nil
    }

    func externalDisplays() -> [CGDirectDisplayID] {
        displays().filter {
            CGDisplayIsBuiltin($0) == 0 && !isGhost($0) && CGDisplayIsOnline($0) != 0 &&
                CGDisplayIsActive($0) != 0 && (CGDisplayVendorNumber($0) != 0 || CGDisplayModelNumber($0) != 0)
        }
    }

    func currentPreset(name: String) -> DisplayPreset? {
        guard let builtin = builtinDisplay() else { return nil }
        return DisplayPreset(name: name,
                             builtinEnabled: CGDisplayIsOnline(builtin) != 0,
                             rotation: Int(CGDisplayRotation(builtin).rounded()),
                             builtinPrimary: CGMainDisplayID() == builtin)
    }

    private func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool, temporary: Bool = false) -> Bool {
        guard let configureEnabled else {
            log("Display toggle failed: CGSConfigureDisplayEnabled unavailable")
            return false
        }
        var config: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&config)
        guard beginResult == .success, let config else {
            log("Display \(id) toggle failed: CGBeginDisplayConfiguration=\(beginResult.rawValue)")
            return false
        }
        if !enabled, CGDisplayIsInMirrorSet(id) != 0,
           CGConfigureDisplayMirrorOfDisplay(config, id, kCGNullDirectDisplay) != .success {
            CGCancelDisplayConfiguration(config); return false
        }
        let configureResult = configureEnabled(config, id, enabled)
        guard configureResult == .success else {
            CGCancelDisplayConfiguration(config)
            log("Display \(id) toggle failed: CGSConfigureDisplayEnabled=\(configureResult.rawValue), target=\(enabled)")
            return false
        }
        let completeResult = CGCompleteDisplayConfiguration(config, temporary ? .forSession : .permanently)
        if completeResult != .success {
            log("Display \(id) toggle failed: CGCompleteDisplayConfiguration=\(completeResult.rawValue), target=\(enabled)")
        }
        return completeResult == .success
    }

    func enableBuiltin(force: Bool = false) -> Bool {
        for attempt in 0..<3 {
            guard let builtin = builtinDisplay() else {
                log("Built-in enable failed: cannot resolve built-in display ID")
                return false
            }
            // Online only means the display is enumerated; a disabled panel can be Online but not Active.
            if !force, CGDisplayIsOnline(builtin) != 0, CGDisplayIsActive(builtin) != 0 { return true }
            let submitted = setEnabled(builtin, true)
            log("Built-in enable request: ID=\(builtin), submitted=\(submitted), online=\(CGDisplayIsOnline(builtin)), active=\(CGDisplayIsActive(builtin)), asleep=\(CGDisplayIsAsleep(builtin))")
            if submitted, CGDisplayIsOnline(builtin) != 0, CGDisplayIsActive(builtin) != 0 { return true }
            if attempt < 2 { Thread.sleep(forTimeInterval: 0.4) }
        }
        return false
    }

    func builtinIsAwake() -> Bool {
        guard let builtin = builtinDisplay() else { return false }
        return CGDisplayIsOnline(builtin) != 0 && CGDisplayIsActive(builtin) != 0 && CGDisplayIsAsleep(builtin) == 0
    }

    func disableBuiltin() -> Bool {
        guard !externalDisplays().isEmpty, let builtin = builtinDisplay() else { return false }
        if CGDisplayIsOnline(builtin) == 0 { return true }
        return setEnabled(builtin, false) && CGDisplayIsOnline(builtin) == 0
    }

    func restoreBuiltinDefault() -> Bool {
        guard enableBuiltin(),
              let builtin = builtinDisplay(),
              CGDisplayIsOnline(builtin) != 0 else { return false }
        let rotationRestored = Int(CGDisplayRotation(builtin).rounded()) == 0 || rotateBuiltin(to: 0)
        let primaryRestored = CGMainDisplayID() == builtin || makePrimary(builtin)
        return rotationRestored && primaryRestored
    }

    func rotateBuiltin(to degrees: Int) -> Bool {
        guard let builtin = builtinDisplay(), CGDisplayIsOnline(builtin) != 0,
              let cls: AnyClass = NSClassFromString("MPDisplay"),
              let rawObject = class_createInstance(cls, 0) else { return false }
        let object = rawObject as AnyObject
        let initSelector = NSSelectorFromString("initWithCGSDisplayID:")
        let setSelector = NSSelectorFromString("setOrientation:")
        guard let initMethod = class_getInstanceMethod(cls, initSelector),
              let setMethod = class_getInstanceMethod(cls, setSelector) else { return false }
        typealias InitFunction = @convention(c) (AnyObject, Selector, UInt32) -> Unmanaged<AnyObject>
        typealias SetFunction = @convention(c) (AnyObject, Selector, Int32) -> Void
        // class_createInstance already owns the object; init returns the same instance, so it must not be taken as retained again,
        // or it is released twice when the function returns, causing EXC_BAD_ACCESS when the rotation preset is applied.
        let initialized = unsafeBitCast(method_getImplementation(initMethod), to: InitFunction.self)(object, initSelector, builtin).takeUnretainedValue()
        unsafeBitCast(method_getImplementation(setMethod), to: SetFunction.self)(initialized, setSelector, Int32(degrees))
        return true
    }

    func makePrimary(_ target: CGDirectDisplayID) -> Bool {
        let targetBounds = CGDisplayBounds(target)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        for display in displays() where CGDisplayIsOnline(display) != 0 && !isGhost(display) {
            let bounds = CGDisplayBounds(display)
            let error = CGConfigureDisplayOrigin(config, display,
                Int32(bounds.origin.x - targetBounds.origin.x), Int32(bounds.origin.y - targetBounds.origin.y))
            if error != .success { CGCancelDisplayConfiguration(config); return false }
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func apply(_ preset: DisplayPreset) -> Bool {
        if preset.builtinEnabled {
            guard enableBuiltin(), let builtin = builtinDisplay() else { return false }
            _ = rotateBuiltin(to: preset.rotation)
            let primary = preset.builtinPrimary ? builtin : (externalDisplays().first ?? builtin)
            if CGMainDisplayID() != primary { _ = makePrimary(primary) }
            return true
        }
        guard let external = externalDisplays().first else { return false }
        if let builtin = builtinDisplay(), CGDisplayIsOnline(builtin) != 0 {
            _ = rotateBuiltin(to: preset.rotation)
            _ = makePrimary(external)
        }
        return disableBuiltin()
    }
}
