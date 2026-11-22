import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit.hid
import IOKit.pwr_mgt
import ObjectiveC.runtime
import UniformTypeIdentifiers

private let benqVendorID = 0x04A5
private let iScreenBarProductID = 0x2501
private let appleDisplayVendorID: UInt32 = 0x0610
// Studio Display models report different model numbers (0xAE46, 0xAE3A observed).
private let studioDisplayProductIDs: Set<UInt32> = [0xAE46, 0xAE3A]
// USB product IDs of the Studio Display HID interfaces (ambient light sensor). Firmware 17.0 changed 0x1118 to 0x1114.
private let studioDisplaySensorProductIDs = [0x1118, 0x1114]
private let pollInterval: TimeInterval = 0.25
// Wake on presence: a lamp power-on within this many seconds of the app's own power command counts as the app's.
private let presenceWakeOwnCommandWindow: TimeInterval = 3
// If the display is still asleep this long after a presence wake request, give up and apply normal sleep sync.
private let presenceWakeTimeout: TimeInterval = 10

// Internal so Automation.swift and ScriptingSupport.swift can log too.
func log(_ message: String) {
    let formatter = ISO8601DateFormatter()
    print("[\(formatter.string(from: Date()))] \(message)")
    fflush(stdout)
}

private let activeControlColor = NSColor.controlAccentColor

private func requestSystemDisplaySleep() -> Bool {
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

private func requestSystemDisplayWake() -> Bool {
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

private enum UIStyle {
    static let panelWidth: CGFloat = 344
    static let contentWidth: CGFloat = 312
    static let outerInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 8
    static let bodyFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let controlFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let iconSize: CGFloat = 15
}

private final class HighlightSliderCell: NSSliderCell {
    let activeColor: NSColor
    var isInteracting = false

    init(activeColor: NSColor) {
        self.activeColor = activeColor
        super.init()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard isInteracting else {
            super.drawBar(inside: rect, flipped: flipped)
            return
        }
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        activeColor.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
    }
}

private final class InteractiveSlider: NSSlider {
    private let activeColor: NSColor
    private let highlightCell: HighlightSliderCell

    init(value: Double, minValue: Double, maxValue: Double, activeColor: NSColor) {
        self.activeColor = activeColor
        highlightCell = HighlightSliderCell(activeColor: activeColor)
        super.init(frame: .zero)
        cell = highlightCell
        self.minValue = minValue
        self.maxValue = maxValue
        self.doubleValue = value
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        highlightCell.isInteracting = true
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            layer?.backgroundColor = activeColor.withAlphaComponent(0.14).cgColor
        }
        super.mouseDown(with: event)
        highlightCell.isInteracting = false
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

private func displayPowerIcon() -> NSImage {
    let size = NSSize(width: 21, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
        let displayConfig = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let powerConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        let display = NSImage(systemSymbolName: "display", accessibilityDescription: String(localized: "Built-in display toggle"))?
            .withSymbolConfiguration(displayConfig)
        let power = NSImage(systemSymbolName: "power", accessibilityDescription: nil)?
            .withSymbolConfiguration(powerConfig)
        display?.draw(in: rect)
        power?.draw(in: NSRect(x: 7, y: 6, width: 7, height: 7))
        return true
    }
    image.isTemplate = true
    return image
}

private final class FeatureButton: NSButton {
    private let accentColor: NSColor

    init(title: String, symbol: String, accentColor: NSColor) {
        self.accentColor = accentColor
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = UIStyle.controlFont
        alignment = .center
        setButtonType(.toggle)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.shadowRadius = 6
        focusRingType = .none
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override var state: NSControl.StateValue {
        didSet { updateAppearance() }
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let foregroundColor: NSColor = state == .on ? .white : .black
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIStyle.controlFont,
            .foregroundColor: foregroundColor
        ]
        attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)
        if state == .on {
            layer.backgroundColor = accentColor.withAlphaComponent(0.88).cgColor
            layer.borderColor = accentColor.cgColor
            layer.shadowColor = accentColor.withAlphaComponent(0.18).cgColor
            layer.shadowOpacity = 1
            contentTintColor = .white
        } else {
            layer.backgroundColor = NSColor.black.withAlphaComponent(0.045).cgColor
            layer.borderColor = NSColor.black.withAlphaComponent(0.09).cgColor
            layer.shadowColor = NSColor.clear.cgColor
            layer.shadowOpacity = 0
            contentTintColor = .black
        }
        layer.borderWidth = 0.5
    }
}

/// Two-layer keep-awake (as in NotchNotes): caffeinate holds the idle assertion,
/// pmset disablesleep covers forced sleep paths such as lid close. Both are tied to the app PID.
private final class KeepAwakeController {
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

/// Keeps the macOS switch size and knob shape; only fixes the highlight color of the on state.
private final class AccentSwitch: NSButton {
    private let accentColor: NSColor
    private let knobLayer = CALayer()

    init(accentColor: NSColor = .systemBlue) {
        self.accentColor = accentColor
        super.init(frame: .zero)
        title = ""
        setButtonType(.toggle)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        knobLayer.backgroundColor = NSColor.white.cgColor
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.18
        knobLayer.shadowRadius = 1.5
        knobLayer.shadowOffset = NSSize(width: 0, height: -0.5)
        layer?.addSublayer(knobLayer)
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 38, height: 22) }

    override var state: NSControl.StateValue {
        didSet { updateAppearance(animated: window != nil) }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance(animated: false) }
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        updateAppearance(animated: false)
    }

    private func updateAppearance(animated: Bool) {
        guard let layer else { return }
        let knobSize = max(0, bounds.height - 4)
        let knobX = state == .on ? max(2, bounds.width - knobSize - 2) : 2
        let changes = {
            layer.backgroundColor = (self.state == .on
                ? self.accentColor
                : NSColor.systemGray.withAlphaComponent(0.34)).cgColor
            layer.opacity = self.isEnabled ? 1 : 0.45
            self.knobLayer.cornerRadius = knobSize / 2
            self.knobLayer.frame = NSRect(x: knobX, y: 2, width: knobSize, height: knobSize)
        }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            changes()
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
        }
    }
}

private struct SavedMode: Codable {
    let name: String
    let brightness: Int
    let temperature: Int
    let videoMode: Bool
}

private struct DisplayPreset: Codable {
    var name: String
    var builtinEnabled: Bool
    var rotation: Int
    var builtinPrimary: Bool
}

private final class BlackDisplayView: NSView {
    var restore: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { restore?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
    }
}

private final class DisplayController {
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

// Launch at login is the same user LaunchAgent that scripts/install.sh writes (not SMAppService):
// it keeps the stdout log redirect and avoids a second login mechanism that could start a duplicate instance.
private enum LoginItem {
    // The LaunchAgent label is the bundle ID (scripts/install.sh uses the same value).
    static let label = Bundle.main.bundleIdentifier ?? "org.windholm.iScreenBarMenu"
    // Earlier labels: local.qiu.iScreenBarStudioSync (before the bundle ID change),
    // org.windholm.iScreenMenu (before the rename to iScreenBar Menu, 0.4 and earlier).
    private static let legacyLabels = ["local.qiu.iScreenBarStudioSync", "org.windholm.iScreenMenu"]

    private static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var plistURL: URL { agentURL(for: label) }
    private static var logURL: URL {
        homeDirectory.appendingPathComponent("Library/Logs/iScreenBarMenu.log")
    }

    private static func agentURL(for label: String) -> URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let fileManager = FileManager.default
        if !enabled {
            guard isEnabled else { return true }
            do {
                try fileManager.removeItem(at: plistURL)
                return true
            } catch {
                log("Failed to remove LaunchAgent: \(error.localizedDescription)")
                return false
            }
        }
        guard let executable = Bundle.main.executablePath else { return false }
        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Restart after a crash, but a normal Quit (exit 0) stays quit.
            "KeepAlive": ["SuccessfulExit": false],
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path
        ]
        do {
            try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            return true
        } catch {
            log("Failed to write LaunchAgent: \(error.localizedDescription)")
            return false
        }
    }

    // Earlier installs used another label (local.qiu.iScreenBarStudioSync also had KeepAlive=true, which relaunches
    // the app after Quit; org.windholm.iScreenMenu points at the old app's executable). Remove those files and carry
    // the login preference over to the current label.
    // A job that is already loaded is not touched; scripts/install.sh boots it out.
    static func replaceLegacyAgentIfNeeded() {
        for legacyLabel in legacyLabels where legacyLabel != label {
            let legacyURL = agentURL(for: legacyLabel)
            guard FileManager.default.fileExists(atPath: legacyURL.path) else { continue }
            do {
                try FileManager.default.removeItem(at: legacyURL)
            } catch {
                log("Failed to remove legacy LaunchAgent \(legacyLabel): \(error.localizedDescription)")
                continue
            }
            let enabled = isEnabled || setEnabled(true)
            log(enabled
                ? "Replaced legacy LaunchAgent \(legacyLabel) with \(label)"
                : "Removed legacy LaunchAgent \(legacyLabel); new one could not be written")
        }
    }
}

// Help window: localized Help.rtf (en.lproj / zh-Hans.lproj) in a read-only text view.
// It follows the system Appearance; text and background use dynamic system colors, so a light/dark switch
// while the window is open redraws without reloading.
private final class HelpWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = String(localized: "iScreenBar Menu Help")
        window.minSize = NSSize(width: 380, height: 320)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("HelpWindow")
        super.init(window: window)
        window.contentView = makeContentView()
        if !window.setFrameUsingName("HelpWindow") { window.center() }
    }

    required init?(coder: NSCoder) { nil }

    private func makeContentView() -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.loadHelpText())
        scrollView.documentView = textView
        return scrollView
    }

    private static func loadHelpText() -> NSAttributedString {
        // Help.rtfd (RTF + images, editable in TextEdit), localized per lproj.
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "rtfd"),
              let text = try? NSMutableAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtfd],
                                                        documentAttributes: nil) else {
            log("Help.rtfd not found in bundle")
            return NSAttributedString(string: String(localized: "Help isn't available."),
                                      attributes: [.foregroundColor: NSColor.labelColor,
                                                   .font: NSFont.systemFont(ofSize: 13)])
        }
        // The RTF stores fixed black text; replace it with the dynamic label color so it follows light/dark.
        let range = NSRange(location: 0, length: text.length)
        text.removeAttribute(.backgroundColor, range: range)
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        return text
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// LSUIElement apps show no menu bar, but key equivalents still come from the main menu.
// A minimal hidden menu makes ⌘W, ⌘C, ⌘A (and ⌘Q) work in the app's windows.
private func installHiddenMainMenu() {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: String(localized: "Quit iScreenBar Menu"),
                               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let fileItem = NSMenuItem()
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    fileItem.submenu = fileMenu
    mainMenu.addItem(fileItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
}

private final class StatusIndicator: NSObject, NSMenuDelegate {
    private let presenceDelayOptions = [180, 300, 600]
    private let item: NSStatusItem
    private let lamp: LampController
    private let popover = NSPopover()
    private let powerSwitch = FeatureButton(title: String(localized: "Light"), symbol: "power", accentColor: activeControlColor)
    private let brightnessSlider = InteractiveSlider(value: 50, minValue: 1, maxValue: 100, activeColor: .systemBlue)
    private let brightnessValueLabel = NSTextField(labelWithString: "50%")
    private let temperatureSlider = InteractiveSlider(value: 5000, minValue: 2700, maxValue: 6500, activeColor: .systemYellow)
    private let temperatureValueLabel = NSTextField(labelWithString: "5000K")
    private let timeTemperatureSwitch = FeatureButton(title: String(localized: "Auto Temp"), symbol: "circle.lefthalf.filled", accentColor: activeControlColor)
    private let autoLightSwitch = FeatureButton(title: String(localized: "Auto Light"), symbol: "sun.max", accentColor: activeControlColor)
    private let presenceSwitch = FeatureButton(title: String(localized: "Presence"), symbol: "figure.seated.side", accentColor: activeControlColor)
    private let presenceDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presenceSensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presenceWakeSwitch = AccentSwitch()
    private var presenceDelaySeconds = 180
    private var presenceSensitivity = 2
    private let videoModeSwitch = FeatureButton(title: String(localized: "Video Mode"), symbol: "video", accentColor: activeControlColor)
    private let modeButton = NSButton(title: String(localized: "Favorite"), target: nil, action: nil)
    private let rotationModeButton = NSButton(title: String(localized: "Portrait Dual"), target: nil, action: nil)
    private var modeCenterWindow: NSWindow?
    private var helpWindowController: HelpWindowController?
    private var panelStack: NSStackView?
    private var displaySectionViews: [NSView] = []
    private var rotationPresetViews: [NSView] = []
    private let bindAppButton = NSButton(title: String(localized: "Bind App"), target: nil, action: nil)
    private let brightnessFollowSwitch = FeatureButton(title: String(localized: "Match Screen"), symbol: "display", accentColor: activeControlColor)
    private let displayBrightnessLockSwitch = FeatureButton(title: String(localized: "Link Screens"), symbol: "rectangle.on.rectangle", accentColor: activeControlColor)
    private let powerSyncSwitch = FeatureButton(title: String(localized: "Sleep Sync"), symbol: "moon.zzz", accentColor: activeControlColor)
    private let keepAwakeSwitch = FeatureButton(title: String(localized: "Keep Awake"), symbol: "cup.and.saucer", accentColor: activeControlColor)
    private let keepAwakeController = KeepAwakeController()
    private let captureBrightButton = FeatureButton(title: String(localized: "Bright: Off"), symbol: "sun.max.fill", accentColor: .systemOrange)
    private let captureDarkButton = FeatureButton(title: String(localized: "Dim: On"), symbol: "moon.fill", accentColor: .systemBlue)
    private let ambientEnableSwitch = AccentSwitch()
    private let brightThresholdLabel = NSTextField(labelWithString: "--")
    private let darkThresholdLabel = NSTextField(labelWithString: "--")
    private let ambientStatusLabel = NSTextField(labelWithString: String(localized: "Ambient light not calibrated yet"))
    private let displayPowerSwitch: FeatureButton = {
        let button = FeatureButton(title: String(localized: "Built-in"), symbol: "display", accentColor: activeControlColor)
        button.image = displayPowerIcon()
        return button
    }()
    private let displayRotateButton = FeatureButton(title: String(localized: "Rotate \(0)°"), symbol: "arrow.clockwise", accentColor: activeControlColor)
    private let studioPowerSwitch = FeatureButton(title: "Studio Display", symbol: "display", accentColor: activeControlColor)
    private let displayAutoPresetSwitch = AccentSwitch()
    private let displayController = DisplayController()
    private(set) var isBrightnessFollowEnabled: Bool
    private(set) var isDisplayBrightnessLockEnabled: Bool
    private(set) var isPowerSyncEnabled: Bool
    private(set) var isPresenceWakeEnabled: Bool
    private(set) var isTimeTemperatureEnabled: Bool
    private(set) var ambientCloseThreshold: Int?
    private(set) var ambientOpenThreshold: Int?
    private(set) var currentDisplayAmbientProxy: Int?
    private var currentAmbientSourceName = "display"
    private var ambientThresholdSource: String?
    private var areAmbientRulesEnabled: Bool
    private var isDisplayAutoPresetEnabled: Bool
    private var isHealthy = true
    private var isAsleep: Bool
    private var autoLightChangePendingUntil: Date?
    private var pendingAutoLightState: Bool?
    private var lastScheduledTemperature: Int?
    private var lastScheduledTemperatureChangeAt = Date.distantPast
    private var lastFrontmostBundleID: String?
    private var isAmbientPresenceLockActive = false
    private var presenceWasEnabledBeforeAmbientLock = false
    private var autoLightWasEnabledBeforeAmbientLock = false
    private var isScreenSleepPresenceLockActive = false
    private var presenceWasEnabledBeforeScreenSleep = false
    private var isDisplaySessionSafe = false
    private var pendingDisplayConnectionState: Bool?
    private var pendingDisplayPolicyWorkItem: DispatchWorkItem?
    private var pendingBuiltinWakeWorkItems: [DispatchWorkItem] = []
    private var didRequestDisplaySleepForCurrentLidClosure = false

    private var isBuiltinManuallyDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: "builtinManuallyDisabled") }
        set { UserDefaults.standard.set(newValue, forKey: "builtinManuallyDisabled") }
    }

    init(isAsleep: Bool, lamp: LampController) {
        self.lamp = lamp
        self.isAsleep = isAsleep
        isBrightnessFollowEnabled = UserDefaults.standard.bool(forKey: "brightnessFollowEnabled")
        isDisplayBrightnessLockEnabled = UserDefaults.standard.bool(forKey: "displayBrightnessLockEnabled")
        isPowerSyncEnabled = UserDefaults.standard.object(forKey: "powerSyncEnabled") as? Bool ?? true
        isPresenceWakeEnabled = UserDefaults.standard.bool(forKey: "presenceWakeEnabled")
        isTimeTemperatureEnabled = UserDefaults.standard.bool(forKey: "timeTemperatureEnabled")
        ambientCloseThreshold = UserDefaults.standard.object(forKey: "ambientCloseThreshold") as? Int
        ambientOpenThreshold = UserDefaults.standard.object(forKey: "ambientOpenThreshold") as? Int
        ambientThresholdSource = UserDefaults.standard.string(forKey: "ambientThresholdSource")
        areAmbientRulesEnabled = UserDefaults.standard.object(forKey: "ambientRulesEnabled") as? Bool
            ?? (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
        UserDefaults.standard.removeObject(forKey: "ambientLinkEnabled")
        if ambientThresholdSource != "studioDisplayALS-v1" {
            ambientCloseThreshold = nil
            ambientOpenThreshold = nil
            areAmbientRulesEnabled = false
        }
        presenceWasEnabledBeforeAmbientLock = UserDefaults.standard.bool(forKey: "ambientSuspendedPresenceWasEnabled")
        autoLightWasEnabledBeforeAmbientLock = UserDefaults.standard.bool(forKey: "ambientSuspendedAutoLightWasEnabled")
        isAmbientPresenceLockActive = presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock
        presenceWasEnabledBeforeScreenSleep = UserDefaults.standard.bool(forKey: "screenSleepSuspendedPresenceWasEnabled")
        isScreenSleepPresenceLockActive = presenceWasEnabledBeforeScreenSleep
        isDisplayAutoPresetEnabled = UserDefaults.standard.bool(forKey: "displayAutoPresetEnabled")
        presenceDelaySeconds = UserDefaults.standard.object(forKey: "presenceDelaySeconds") as? Int ?? 180
        if !presenceDelayOptions.contains(presenceDelaySeconds) {
            presenceDelaySeconds = 180
        }
        presenceSensitivity = UserDefaults.standard.object(forKey: "presenceSensitivity") as? Int ?? 2
        presenceSensitivity = max(0, min(2, presenceSensitivity))
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        installHiddenMainMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        migrateDisplayPresetIfNeeded()
        LoginItem.replaceLegacyAgentIfNeeded()
        configurePanel()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate),
                                               name: NSApplication.willTerminateNotification, object: nil)
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe(_:)),
                                           name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameUnsafe(_:)),
                                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspaceNotifications.addObserver(self, selector: #selector(displaySessionBecameActive),
                                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        scheduleDisplaySessionActivation()
        update(isAsleep: isAsleep, healthy: true)
    }

    func update(isAsleep: Bool, healthy: Bool) {
        self.isAsleep = isAsleep
        isHealthy = healthy
        handleKeepAwakeLidDisplayState()
        if lamp.isAutoLightEnabled == true, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            log("Lamp auto-light is on; turned off Studio Display brightness follow")
        }
        updateIcon(healthy: healthy)
        let displayState = isAsleep ? "Studio Display asleep" : "Studio Display awake"
        let brightnessStatus = isBrightnessFollowEnabled ? "brightness follow on" : "brightness follow off"
        let powerStatus = isPowerSyncEnabled ? "sleep sync on" : "sleep sync off"
        let status = healthy ? String(localized: "sync OK") : String(localized: "sync error")
        _ = (displayState, brightnessStatus, powerStatus)
        let brightnessText = healthy ? lamp.currentBrightness.map { "\($0)%" } ?? "--%" : "--%"
        let temperatureText = healthy ? lamp.currentTemperature.map { "\($0)K" } ?? "----K" : "----K"
        item.button?.toolTip = "\(brightnessText) · \(temperatureText)"
        item.button?.setAccessibilityLabel("iScreenBar Menu \(status)")
        if displayController.isStudioCovered,
           (displayController.studioTarget() == nil || isConsoleSessionLocked()) {
            _ = displayController.setStudioEnabled(true)
        }
        if popover.isShown { refreshControls() }
    }

    // Left-click opens the control panel; right-click or Control-click opens the standard menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        lamp.requestStatus()
        let menu = buildStatusMenu()
        menu.delegate = self
        item.menu = menu
        button.performClick(nil)
    }

    // Detach the menu once it closes so the next click reaches statusItemClicked again.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === item.menu else { return }
        DispatchQueue.main.async { [weak self] in self?.item.menu = nil }
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            lamp.requestStatus()
            refreshControls()
            if let panelStack {
                popover.contentSize = NSSize(width: UIStyle.panelWidth, height: ceil(panelStack.fittingSize.height))
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func powerChanged() {
        let requested = powerSwitch.state == .on
        if !lamp.setPower(on: requested) { powerSwitch.state = requested ? .off : .on }
        updateIcon(healthy: isHealthy && lamp.isConnected)
        lamp.requestStatus()
    }

    @objc private func captureBrightThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureBrightButton.state = .off
            ambientStatusLabel.stringValue = String(localized: "Can't read the Studio Display light sensor right now")
            NSSound.beep()
            return
        }
        ambientCloseThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientCloseThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureBrightButton, valueLabel: brightThresholdLabel)
        log("Captured ambient off point: \(currentAmbientSourceName) score \(value)")
    }

    @objc private func captureDarkThreshold() {
        guard let value = currentDisplayAmbientProxy else {
            captureDarkButton.state = .off
            ambientStatusLabel.stringValue = String(localized: "Can't read the Studio Display light sensor right now")
            NSSound.beep()
            return
        }
        ambientOpenThreshold = value
        UserDefaults.standard.set(value, forKey: "ambientOpenThreshold")
        ambientThresholdSource = "studioDisplayALS-v1"
        UserDefaults.standard.set("studioDisplayALS-v1", forKey: "ambientThresholdSource")
        updateAmbientStatusLabel()
        flashCaptureSuccess(button: captureDarkButton, valueLabel: darkThresholdLabel)
        log("Captured ambient on point: \(currentAmbientSourceName) score \(value)")
    }

    private func flashCaptureSuccess(button: FeatureButton, valueLabel: NSTextField) {
        button.state = .on
        valueLabel.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak button, weak valueLabel] in
            button?.state = .off
            valueLabel?.textColor = .secondaryLabelColor
        }
    }

    @objc private func ambientEnableChanged() {
        areAmbientRulesEnabled = ambientEnableSwitch.state == .on
        UserDefaults.standard.set(areAmbientRulesEnabled, forKey: "ambientRulesEnabled")
        updateAmbientStatusLabel()
        log(areAmbientRulesEnabled ? "Enabled saved ambient light rules" : "Disabled ambient light rules; calibration kept")
    }

    func updateDisplayAmbientProxy(_ value: Int?, sourceName: String) {
        let availabilityChanged = (currentDisplayAmbientProxy == nil) != (value == nil)
        currentDisplayAmbientProxy = value
        currentAmbientSourceName = sourceName
        if availabilityChanged { updateAmbientControlAvailability() }
        if popover.isShown { updateAmbientStatusLabel() }
    }

    // Capture needs a sensor reading; the rules switch also needs at least one saved threshold.
    // Kept separate from refreshControls so the menu and an open panel follow the sensor as soon as it appears or drops out.
    private func updateAmbientControlAvailability() {
        let hasReading = currentDisplayAmbientProxy != nil
        captureBrightButton.isEnabled = hasReading
        captureDarkButton.isEnabled = hasReading
        ambientEnableSwitch.isEnabled = hasReading && (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
    }

    @discardableResult
    func suspendPresenceForAmbientLock() -> Bool {
        if isAmbientPresenceLockActive {
            maintainPresenceSuspendedForAmbientLock()
            return true
        }
        isAmbientPresenceLockActive = true
        presenceWasEnabledBeforeAmbientLock = presenceWasEnabledBeforeAmbientLock || lamp.isPresenceDetectionEnabled == true
        autoLightWasEnabledBeforeAmbientLock = autoLightWasEnabledBeforeAmbientLock || lamp.isAutoLightEnabled == true
        if autoLightWasEnabledBeforeAmbientLock {
            guard lamp.setAutoLight(enabled: false) else {
                isAmbientPresenceLockActive = false
                autoLightWasEnabledBeforeAmbientLock = false
                return false
            }
            UserDefaults.standard.set(true, forKey: "ambientSuspendedAutoLightWasEnabled")
            log("Ambient off-lock temporarily paused auto-light")
        }
        if presenceWasEnabledBeforeAmbientLock {
            guard lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                            sensitivity: presenceSensitivity) else {
                if autoLightWasEnabledBeforeAmbientLock {
                    _ = lamp.setAutoLight(enabled: true)
                    UserDefaults.standard.removeObject(forKey: "ambientSuspendedAutoLightWasEnabled")
                }
                isAmbientPresenceLockActive = false
                presenceWasEnabledBeforeAmbientLock = false
                autoLightWasEnabledBeforeAmbientLock = false
                return false
            }
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
            log("Ambient off-lock temporarily paused presence detection")
        }
        refreshControls()
        return true
    }

    func maintainPresenceSuspendedForAmbientLock() {
        guard isAmbientPresenceLockActive else { return }
        // While the lamp is off, the firmware ignores the "write manual brightness" action that exits auto-light.
        // An off-lock left by an older version only remembers the intent to restore; if the lamp turns itself on, pause again immediately.
        if lamp.isPowerOn == true, lamp.isAutoLightEnabled == true {
            autoLightWasEnabledBeforeAmbientLock = true
            if lamp.setAutoLight(enabled: false) {
                UserDefaults.standard.set(true, forKey: "ambientSuspendedAutoLightWasEnabled")
                log("Auto-light still on during ambient lock; paused temporarily")
            }
        }
        if lamp.isPresenceDetectionEnabled == true {
            presenceWasEnabledBeforeAmbientLock = true
            if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
                log("Presence detection still on during ambient lock; paused temporarily")
            }
        }
    }

    func restorePresenceAfterAmbientLock() {
        guard isAmbientPresenceLockActive || presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock else { return }
        let shouldRestorePresence = presenceWasEnabledBeforeAmbientLock
        let shouldRestoreAutoLight = autoLightWasEnabledBeforeAmbientLock
        isAmbientPresenceLockActive = false
        presenceWasEnabledBeforeAmbientLock = false
        autoLightWasEnabledBeforeAmbientLock = false
        UserDefaults.standard.removeObject(forKey: "ambientSuspendedPresenceWasEnabled")
        UserDefaults.standard.removeObject(forKey: "ambientSuspendedAutoLightWasEnabled")
        if shouldRestorePresence, isScreenSleepPresenceLockActive {
            presenceWasEnabledBeforeScreenSleep = true
            UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
        } else if shouldRestorePresence {
            if lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                log("Ambient off-lock released; presence detection restored")
            } else {
                log("Ambient off-lock released, but restoring presence detection failed")
            }
        }
        if shouldRestoreAutoLight {
            if lamp.setAutoLight(enabled: true) {
                log("Ambient off-lock released; auto-light restored")
            } else {
                log("Ambient off-lock released, but restoring auto-light failed")
            }
        }
        refreshControls()
    }

    func suspendPresenceForScreenSleep() {
        // Wake Screen: presence detection keeps running so the lamp turning itself on can wake the display (ADR 0008).
        guard !isPresenceWakeEnabled else { return }
        if isScreenSleepPresenceLockActive {
            if lamp.isPresenceDetectionEnabled == true {
                presenceWasEnabledBeforeScreenSleep = true
                if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                             sensitivity: presenceSensitivity) {
                    UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
                    log("Presence detection still on while screen is off; paused again")
                }
            }
            return
        }
        // If the ambient off-lock already paused it, the ambient lock restores it, so wake does not turn it on early.
        guard !isAmbientPresenceLockActive else { return }
        isScreenSleepPresenceLockActive = true
        presenceWasEnabledBeforeScreenSleep = lamp.isPresenceDetectionEnabled == true
        guard presenceWasEnabledBeforeScreenSleep else { return }
        if lamp.setPresenceDetection(enabled: false, delaySeconds: presenceDelaySeconds,
                                     sensitivity: presenceSensitivity) {
            UserDefaults.standard.set(true, forKey: "screenSleepSuspendedPresenceWasEnabled")
            log("Sleep sync temporarily paused presence detection")
        } else {
            isScreenSleepPresenceLockActive = false
            presenceWasEnabledBeforeScreenSleep = false
            log("Failed to pause presence detection on screen sleep")
        }
        refreshControls()
    }

    func restorePresenceAfterScreenWake() {
        guard isScreenSleepPresenceLockActive || presenceWasEnabledBeforeScreenSleep else { return }
        let shouldRestore = presenceWasEnabledBeforeScreenSleep
        isScreenSleepPresenceLockActive = false
        presenceWasEnabledBeforeScreenSleep = false
        UserDefaults.standard.removeObject(forKey: "screenSleepSuspendedPresenceWasEnabled")
        if shouldRestore, isAmbientPresenceLockActive {
            presenceWasEnabledBeforeAmbientLock = true
            UserDefaults.standard.set(true, forKey: "ambientSuspendedPresenceWasEnabled")
        }
        if shouldRestore, !isAmbientPresenceLockActive {
            if lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds,
                                         sensitivity: presenceSensitivity) {
                log("Screen awake; presence detection restored")
            } else {
                log("Screen awake, but restoring presence detection failed")
            }
        }
        refreshControls()
    }

    var hasPendingAmbientPresenceRestore: Bool {
        return presenceWasEnabledBeforeAmbientLock || autoLightWasEnabledBeforeAmbientLock
    }

    private func updateAmbientStatusLabel() {
        brightThresholdLabel.stringValue = ambientCloseThreshold.map(String.init) ?? "--"
        darkThresholdLabel.stringValue = ambientOpenThreshold.map(String.init) ?? "--"
        captureBrightButton.state = .off
        captureDarkButton.state = .off
        ambientEnableSwitch.state = areAmbientRulesEnabled ? .on : .off
        updateAmbientControlAvailability()
        let currentText = currentDisplayAmbientProxy.map { String(localized: "Ambient \($0)") } ?? String(localized: "Ambient --")
        if currentDisplayAmbientProxy != nil, ambientCloseThreshold == nil, ambientOpenThreshold == nil {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Capture a threshold to enable")
        } else if let close = ambientCloseThreshold, let open = ambientOpenThreshold, open >= close {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Thresholds overlap; may toggle repeatedly")
        } else if !areAmbientRulesEnabled, ambientCloseThreshold != nil || ambientOpenThreshold != nil {
            ambientStatusLabel.stringValue = String(localized: "\(currentText)  ·  Saved, not enabled")
        } else {
            ambientStatusLabel.stringValue = currentText
        }
    }

    var isAmbientLinkEnabled: Bool {
        return areAmbientRulesEnabled && (ambientCloseThreshold != nil || ambientOpenThreshold != nil)
    }

    @objc private func brightnessChanged() {
        let value = Int(brightnessSlider.doubleValue.rounded())
        brightnessValueLabel.stringValue = "\(value)%"
        _ = lamp.setBrightness(value)
        lamp.requestStatus()
    }

    @objc private func temperatureChanged() {
        let value = Int((temperatureSlider.doubleValue / 100).rounded()) * 100
        temperatureSlider.doubleValue = Double(value)
        temperatureValueLabel.stringValue = "\(value)K"
        _ = lamp.setTemperature(value)
        lamp.requestStatus()
    }

    @objc private func timeTemperatureChanged() {
        isTimeTemperatureEnabled = timeTemperatureSwitch.state == .on
        UserDefaults.standard.set(isTimeTemperatureEnabled, forKey: "timeTemperatureEnabled")
        lastScheduledTemperature = nil
        lastScheduledTemperatureChangeAt = .distantPast
        refreshControls()
        if isTimeTemperatureEnabled {
            applyScheduledTemperatureIfNeeded(isAsleep: isAsleep, force: true)
            log("Time-based color temperature on")
        } else {
            log("Time-based color temperature off; keeping current temperature")
        }
    }

    func applyScheduledTemperatureIfNeeded(isAsleep: Bool, force: Bool = false) {
        guard isTimeTemperatureEnabled,
              !isAsleep,
              lamp.isConnected,
              lamp.isPowerOn == true else { return }
        let target = scheduledTemperature(at: Date())
        guard force || target != lastScheduledTemperature || lamp.currentTemperature != target else { return }
        guard force || Date().timeIntervalSince(lastScheduledTemperatureChangeAt) >= 60 else { return }
        if lamp.setTemperature(target) {
            lastScheduledTemperature = target
            lastScheduledTemperatureChangeAt = Date()
            log("Time-based color temperature set to \(target)K")
        }
    }

    private func scheduledTemperature(at date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let value: Double
        switch minute {
        case 0..<(6 * 60):
            value = 3000
        case (6 * 60)..<(10 * 60):
            value = interpolate(minute: minute, from: 6 * 60, to: 10 * 60, start: 3000, end: 5500)
        case (10 * 60)..<(16 * 60):
            value = 5500
        case (16 * 60)..<(21 * 60):
            value = interpolate(minute: minute, from: 16 * 60, to: 21 * 60, start: 5500, end: 3500)
        default:
            value = interpolate(minute: minute, from: 21 * 60, to: 24 * 60, start: 3500, end: 3000)
        }
        return max(2700, min(6500, Int((value / 50).rounded()) * 50))
    }

    private func interpolate(minute: Int, from: Int, to: Int, start: Double, end: Double) -> Double {
        let progress = Double(minute - from) / Double(to - from)
        return start + (end - start) * max(0, min(1, progress))
    }

    @objc private func autoLightChanged() {
        let requested = autoLightSwitch.state == .on
        if !lamp.setAutoLight(enabled: requested) {
            autoLightSwitch.state = requested ? .off : .on
            return
        }
        autoLightChangePendingUntil = Date().addingTimeInterval(1)
        pendingAutoLightState = requested
        if requested, isBrightnessFollowEnabled {
            isBrightnessFollowEnabled = false
            brightnessFollowSwitch.state = .off
            UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
            update(isAsleep: isAsleep, healthy: isHealthy)
            log("Turned off Studio Display brightness follow; using lamp auto-light")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.lamp.requestStatus()
        }
    }

    @objc private func presenceChanged() {
        let requested = presenceSwitch.state == .on
        if !lamp.setPresenceDetection(enabled: requested, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
            presenceSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc private func presenceDelayChanged() {
        let seconds = selectedPresenceDelaySeconds()
        presenceDelaySeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "presenceDelaySeconds")
        log("Presence delay set to \(seconds) s")
        if lamp.isPresenceDetectionEnabled == true {
            let requested = presenceSwitch.state == .on
            if !lamp.setPresenceDetection(enabled: requested, delaySeconds: seconds, sensitivity: presenceSensitivity) {
                log("Presence delay not accepted by lamp; local setting kept")
            }
            lamp.requestStatus()
        }
    }

    @objc private func presenceSensitivityChanged() {
        presenceSensitivity = presenceSensitivityPopup.selectedItem?.tag ?? 2
        UserDefaults.standard.set(presenceSensitivity, forKey: "presenceSensitivity")
        log("Presence sensitivity set to \(presenceSensitivity)")
        if lamp.isPresenceDetectionEnabled == true {
            if !lamp.setPresenceDetection(enabled: true, delaySeconds: presenceDelaySeconds, sensitivity: presenceSensitivity) {
                log("Presence sensitivity not accepted by lamp; local setting kept")
            }
            lamp.requestStatus()
        }
    }

    @objc private func videoModeChanged() {
        let requested = videoModeSwitch.state == .on
        if !lamp.setVideoMode(enabled: requested) {
            videoModeSwitch.state = requested ? .off : .on
        }
        lamp.requestStatus()
    }

    @objc private func presetChanged(_ sender: NSMenuItem) {
        let index = sender.tag
        let preset: (brightness: Int, temperature: Int, video: Bool)
        if (index == 0 || index >= 3),
           let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let saved = try? JSONDecoder().decode(SavedMode.self, from: data) {
            preset = (saved.brightness, saved.temperature, saved.videoMode)
        } else {
            switch index {
            case 1: preset = (30, 4000, false)
            case 2: preset = (20, 3000, false)
            default: preset = (47, 5500, false)
            }
        }
        isBrightnessFollowEnabled = false
        brightnessFollowSwitch.state = .off
        UserDefaults.standard.set(false, forKey: "brightnessFollowEnabled")
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(preset.brightness)
        _ = lamp.setTemperature(preset.temperature)
        _ = lamp.setVideoMode(enabled: preset.video)
        refreshControls()
        modeButton.title = sender.title
        log("Applied mode preset: \(sender.title)")
        lamp.requestStatus()
    }

    @objc private func showModeMenu() {
        let menu = NSMenu()
        for (index, title) in modeNames().enumerated() {
            let item = NSMenuItem(title: title, action: #selector(presetChanged(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if title == modeButton.title { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let center = NSMenuItem(title: String(localized: "Mode Center…"), action: #selector(showModeCenter), keyEquivalent: "")
        center.target = self
        menu.addItem(center)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: modeButton.bounds.height + 4), in: modeButton)
    }

    private func modeNames() -> [String] {
        var names = [String(localized: "Favorite"), String(localized: "Night Work"), String(localized: "Wind Down")]
        if let data = UserDefaults.standard.data(forKey: "savedCustomMode"),
           let mode = try? JSONDecoder().decode(SavedMode.self, from: data),
           !names.contains(mode.name) {
            names.append(mode.name)
        }
        return names
    }

    @objc private func showModeCenter() {
        if let window = modeCenterWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 270),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Mode Center")
        let title = NSTextField(labelWithString: String(localized: "Mode Center"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: String(localized: "Quickly switch between lighting presets"))
        subtitle.font = UIStyle.bodyFont
        subtitle.textColor = .secondaryLabelColor
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 1
        rows.wantsLayer = true
        rows.layer?.cornerRadius = 10
        rows.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        for (index, name) in modeNames().enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(modeCenterPresetChanged(_:)))
            button.tag = index
            button.isBordered = false
            button.setAccessibilityTitle(name)
            button.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: name)
            label.font = UIStyle.bodyFont
            label.translatesAutoresizingMaskIntoConstraints = false
            let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            chevron.translatesAutoresizingMaskIntoConstraints = false
            let row = NSView()
            row.addSubview(button)
            row.addSubview(label)
            row.addSubview(chevron)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 44),
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
                chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 10),
                chevron.heightAnchor.constraint(equalToConstant: 14)
            ])
            rows.addArrangedSubview(row)
        }
        let add = NSButton(title: String(localized: "New Scene Mode"), target: self, action: #selector(saveCurrentMode))
        add.bezelStyle = .rounded
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        let bind = NSButton(title: String(localized: "Bind App"), target: self, action: #selector(bindCurrentModeToApp))
        bind.bezelStyle = .rounded
        bind.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bind.imagePosition = .imageLeading
        let leadingSpace = NSView()
        let trailingSpace = NSView()
        leadingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [leadingSpace, add, bind, trailingSpace])
        actions.orientation = .horizontal
        actions.spacing = 10
        actions.distribution = .fill
        actions.widthAnchor.constraint(equalToConstant: 512).isActive = true
        leadingSpace.widthAnchor.constraint(equalTo: trailingSpace.widthAnchor).isActive = true
        let stack = NSStackView(views: [title, subtitle, rows, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            rows.widthAnchor.constraint(equalToConstant: 512)
        ])
        window.contentView = content
        window.isReleasedWhenClosed = false
        if let screen = item.button?.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                          y: visible.midY - frame.height / 2))
        } else {
            window.center()
        }
        modeCenterWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func modeCenterPresetChanged(_ sender: NSButton) {
        let item = NSMenuItem(title: modeNames()[sender.tag], action: nil, keyEquivalent: "")
        item.tag = sender.tag
        presetChanged(item)
    }

    @objc private func saveCurrentMode() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else {
            log("Lamp status not available yet; cannot save mode")
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save New Mode")
        alert.informativeText = String(localized: "Saves the current brightness, color temperature, and video mode.")
        let field = NSTextField(string: String(localized: "My Mode"))
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let mode = SavedMode(name: field.stringValue.isEmpty ? String(localized: "My Mode") : field.stringValue,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        if let data = try? JSONEncoder().encode(mode) {
            UserDefaults.standard.set(data, forKey: "savedCustomMode")
            modeButton.title = mode.name
            log("Saved mode: \(mode.name)")
            modeCenterWindow?.close()
            modeCenterWindow = nil
        }
    }

    @objc private func bindCurrentModeToApp() {
        guard let brightness = lamp.currentBrightness,
              let temperature = lamp.currentTemperature else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an App to Bind")
        panel.prompt = String(localized: "Bind")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let mode = SavedMode(name: url.deletingPathExtension().lastPathComponent,
                             brightness: brightness,
                             temperature: temperature,
                             videoMode: lamp.isVideoModeEnabled == true)
        var mappings = loadAppModes()
        mappings[bundleID] = mode
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: "appModes")
            bindAppButton.title = String(localized: "Bound: \(mode.name)")
            log("Bound app mode: \(mode.name)")
        }
    }

    func applyModeForFrontmostAppIfNeeded() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              bundleID != lastFrontmostBundleID else { return }
        lastFrontmostBundleID = bundleID
        guard let mode = loadAppModes()[bundleID] else { return }
        _ = lamp.setPower(on: true)
        _ = lamp.setBrightness(mode.brightness)
        _ = lamp.setTemperature(mode.temperature)
        _ = lamp.setVideoMode(enabled: mode.videoMode)
        log("Applied app mode: \(mode.name)")
    }

    private func loadAppModes() -> [String: SavedMode] {
        guard let data = UserDefaults.standard.data(forKey: "appModes") else { return [:] }
        return (try? JSONDecoder().decode([String: SavedMode].self, from: data)) ?? [:]
    }

    @objc private func brightnessFollowChanged() {
        let requested = brightnessFollowSwitch.state == .on
        if requested, lamp.isAutoLightEnabled == true {
            guard lamp.setAutoLight(enabled: false) else {
                brightnessFollowSwitch.state = .off
                log("Failed to turn off auto-light; Studio Display brightness follow not enabled")
                return
            }
            autoLightSwitch.state = .off
            autoLightChangePendingUntil = Date().addingTimeInterval(1)
            pendingAutoLightState = false
            lamp.requestStatus()
            log("Turned off auto-light; using Studio Display brightness follow")
        }
        isBrightnessFollowEnabled = requested
        UserDefaults.standard.set(isBrightnessFollowEnabled, forKey: "brightnessFollowEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isBrightnessFollowEnabled ? "Studio Display brightness follow on" : "Studio Display brightness follow off")
    }

    @objc private func displayBrightnessLockChanged() {
        isDisplayBrightnessLockEnabled = displayBrightnessLockSwitch.state == .on
        UserDefaults.standard.set(isDisplayBrightnessLockEnabled, forKey: "displayBrightnessLockEnabled")
        log(isDisplayBrightnessLockEnabled
            ? "MacBook / Studio Display brightness lock on"
            : "MacBook / Studio Display brightness lock off")
        refreshControls()
    }

    @objc private func powerSyncChanged() {
        isPowerSyncEnabled = powerSyncSwitch.state == .on
        UserDefaults.standard.set(isPowerSyncEnabled, forKey: "powerSyncEnabled")
        update(isAsleep: isAsleep, healthy: isHealthy)
        log(isPowerSyncEnabled ? "Sleep sync on" : "Sleep sync off")
        refreshControls()
    }

    @objc private func presenceWakeChanged() {
        isPresenceWakeEnabled = presenceWakeSwitch.state == .on
        UserDefaults.standard.set(isPresenceWakeEnabled, forKey: "presenceWakeEnabled")
        // Presence paused by an earlier display sleep goes back on now; turning it off lets the poll loop pause it again.
        if isPresenceWakeEnabled { restorePresenceAfterScreenWake() }
        log(isPresenceWakeEnabled ? "Wake screen on presence on" : "Wake screen on presence off")
        refreshControls()
    }

    @objc private func keepAwakeChanged() {
        let requested = keepAwakeSwitch.state == .on
        guard keepAwakeController.setActive(requested) else {
            keepAwakeSwitch.state = .off
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Turn On Keep Awake")
            alert.informativeText = String(localized: "macOS couldn't start caffeinate. Please try again later.")
            alert.runModal()
            return
        }
        keepAwakeSwitch.state = keepAwakeController.isActive ? .on : .off
        handleKeepAwakeLidDisplayState()
        log(keepAwakeController.isActive ? "Keep-awake on" : "Restored default system sleep")
    }

    private func handleKeepAwakeLidDisplayState() {
        guard displayController.lidClosed() else {
            didRequestDisplaySleepForCurrentLidClosure = false
            return
        }
        guard keepAwakeController.isActive,
              displayController.externalDisplays().isEmpty,
              !didRequestDisplaySleepForCurrentLidClosure else { return }

        // With disablesleep, a closed lid falls back to the displaysleep timer; with no external display, request display sleep now.
        didRequestDisplaySleepForCurrentLidClosure = true
        let success = requestSystemDisplaySleep()
        log(success
            ? "Lid closed during keep-awake; requested built-in display off"
            : "Lid closed during keep-awake; display sleep request failed")
    }

    private func migrateDisplayPresetIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: "rotationPreset") == nil else { return }
        if let old = UserDefaults(suiteName: "local.qiu.builtin-display-rotation"),
           old.bool(forKey: "DisplayPresetSaved") {
            let preset = DisplayPreset(name: String(localized: "My Rotation Preset"),
                                       builtinEnabled: old.bool(forKey: "DisplayPresetBuiltinEnabled"),
                                       rotation: old.integer(forKey: "DisplayPresetRotation"),
                                       builtinPrimary: old.bool(forKey: "DisplayPresetBuiltinPrimary"))
            saveRotationPreset(preset)
            return
        }
        saveRotationPreset(DisplayPreset(name: String(localized: "Portrait Dual"), builtinEnabled: true, rotation: 90, builtinPrimary: false))
    }

    private func saveRotationPreset(_ preset: DisplayPreset) {
        if let data = try? JSONEncoder().encode(preset) {
            UserDefaults.standard.set(data, forKey: "rotationPreset")
            rotationModeButton.title = preset.name
        }
    }

    private func loadRotationPreset() -> DisplayPreset {
        if let data = UserDefaults.standard.data(forKey: "rotationPreset"),
           let preset = try? JSONDecoder().decode(DisplayPreset.self, from: data) { return preset }
        return DisplayPreset(name: String(localized: "Portrait Dual"), builtinEnabled: true, rotation: 90, builtinPrimary: false)
    }

    private func saveDisplayBaselineIfNeeded() {
        guard UserDefaults.standard.data(forKey: "displayAutoBaseline") == nil,
              let baseline = displayController.currentPreset(name: String(localized: "Before Auto-Apply")) else { return }
        if let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: "displayAutoBaseline")
        }
    }

    private func restoreDisplayBaseline(clear: Bool) {
        guard let data = UserDefaults.standard.data(forKey: "displayAutoBaseline"),
              let baseline = try? JSONDecoder().decode(DisplayPreset.self, from: data) else {
            _ = displayController.enableBuiltin(); return
        }
        _ = displayController.apply(baseline)
        if clear { UserDefaults.standard.removeObject(forKey: "displayAutoBaseline") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func displayPowerChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        let requested = displayPowerSwitch.state == .on
        let success = requested ? displayController.enableBuiltin() : displayController.disableBuiltin()
        if success {
            isBuiltinManuallyDisabled = !requested
        } else {
            displayPowerSwitch.state = requested ? .off : .on
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func studioPowerChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { refreshControls(); return }
        let enabled = studioPowerSwitch.state == .on
        guard displayController.setStudioEnabled(enabled) else {
            refreshControls()
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Switch Studio Display")
            alert.informativeText = String(localized: "No available Studio Display found.")
            alert.runModal()
            return
        }
        if !enabled { popover.performClose(nil) }
        refreshControls()
    }

    @objc private func displaySessionBecameUnsafe(_ notification: Notification) {
        _ = displayController.setStudioEnabled(true)
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        pendingDisplayPolicyWorkItem = nil
        log("Locked or display asleep; paused built-in display configuration")
        if notification.name == NSWorkspace.sessionDidResignActiveNotification {
            // Chrome/web video may hold a NoDisplaySleepAssertion that keeps the display on for minutes after locking.
            // Request display sleep only once the session is confirmed locked; display configuration after unlock is unaffected.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard isConsoleSessionLocked() else { return }
                log(requestSystemDisplaySleep()
                    ? "Mac locked; requested immediate display sleep"
                    : "Mac locked, but display sleep request failed")
            }
        }
    }

    @objc private func displaySessionBecameActive() {
        scheduleDisplaySessionActivation()
    }

    private func scheduleDisplaySessionActivation() {
        isDisplaySessionSafe = false
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isDisplaySessionSafe = true
            let pendingState = self.pendingDisplayConnectionState
            self.pendingDisplayConnectionState = nil
            if let pendingState {
                self.scheduleDisplayPolicy(forExternalConnection: pendingState)
            }
            self.refreshControls()
            log("Display session settled; built-in manual control resumed")
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func scheduleDisplayPolicy(forExternalConnection connected: Bool) {
        pendingDisplayPolicyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let externalStillConnected = studioDisplayID() != nil
            guard externalStillConnected == connected else { return }
            if !connected {
                // After an external disconnect the built-in display is the only fallback: even while the session is switching or locked,
                // bring the built-in display online first so the "unsafe" guard does not drop the disconnect event.
                self.isBuiltinManuallyDisabled = false
                let enabled = self.displayController.enableBuiltin()
                if enabled {
                    self.requestBuiltinWakeAfterExternalDisconnect()
                    if self.isDisplaySessionSafe, !isConsoleSessionLocked() {
                        _ = self.displayController.restoreBuiltinDefault()
                    }
                } else {
                    self.pendingDisplayConnectionState = false
                    self.scheduleDisplaySessionActivation()
                    log("External display disconnected; built-in restore not effective yet, retry scheduled")
                }
                self.refreshControls()
                return
            }
            guard self.isDisplaySessionSafe, !isConsoleSessionLocked() else {
                self.pendingDisplayConnectionState = true
                return
            }
            if connected {
                if self.isDisplayAutoPresetEnabled {
                    self.saveDisplayBaselineIfNeeded()
                    _ = self.displayController.apply(self.automaticRotationPreset())
                    log("Studio Display connected: auto preset on, applying saved rotation")
                } else {
                    if !self.isBuiltinManuallyDisabled {
                        _ = self.displayController.enableBuiltin()
                    }
                    self.resetBuiltinRotationWhenPresetDisabled()
                }
            }
            self.refreshControls()
        }
        pendingDisplayPolicyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func requestBuiltinWakeAfterExternalDisconnect() {
        pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
        pendingBuiltinWakeWorkItems.removeAll()

        let delays: [TimeInterval] = [0, 1.5, 4, 8, 15]
        for (index, delay) in delays.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, studioDisplayID() == nil else { return }
                self.isBuiltinManuallyDisabled = false
                let enabled = self.displayController.enableBuiltin(force: true)
                let lidOpen = !self.displayController.lidClosed()
                let wakeRequested = lidOpen && requestSystemDisplayWake()
                if self.displayController.builtinIsAwake() {
                    log("External display disconnected; system reports built-in online/active/awake (picture not verified)")
                    self.pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
                    self.pendingBuiltinWakeWorkItems.removeAll()
                } else if index == delays.count - 1 {
                    log("External display disconnected; built-in restore unconfirmed: online=\(enabled), lidClosed=\(!lidOpen), wakeRequested=\(wakeRequested)")
                }
                self.refreshControls()
            }
            pendingBuiltinWakeWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func automaticRotationPreset() -> DisplayPreset {
        var preset = loadRotationPreset()
        preset.builtinEnabled = !isBuiltinManuallyDisabled
        return preset
    }

    @objc private func displayRotationChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        guard let builtin = displayController.builtinDisplay(), CGDisplayIsOnline(builtin) != 0 else { return }
        let current = Int(CGDisplayRotation(builtin).rounded())
        rotateBuiltinWithConfirmation(to: current == 0 ? 90 : (current == 90 ? 270 : 0))
    }

    @objc private func menuRotationChanged(_ sender: NSMenuItem) {
        rotateBuiltinWithConfirmation(to: sender.tag)
    }

    private func rotateBuiltinWithConfirmation(to next: Int) {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        guard let builtin = displayController.builtinDisplay(), CGDisplayIsOnline(builtin) != 0 else { return }
        let current = Int(CGDisplayRotation(builtin).rounded())
        guard next != current else { return }
        popover.performClose(nil)
        guard displayController.rotateBuiltin(to: next) else {
            log("Built-in rotation failed; skipping confirmation")
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Keep Built-in Display Rotation?")
        alert.informativeText = String(localized: "Reverting to \(current)° in 5 seconds unless you confirm.")
        alert.addButton(withTitle: String(localized: "Keep Rotation"))
        alert.addButton(withTitle: String(localized: "Revert"))
        // Repeated Return presses must not confirm the rotation by accident; Esc always reverts.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var expired = false
        let countdown = Timer(timeInterval: 0.1, repeats: true) { _ in
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 {
                expired = true
                NSApplication.shared.abortModal()
            } else {
                alert.informativeText = String(localized: "Reverting to \(current)° in \(Int(ceil(remaining))) seconds unless you confirm.")
            }
        }
        // runModal uses its own run-loop mode; a normal scheduledTimer does not fire meanwhile.
        RunLoop.main.add(countdown, forMode: .modalPanel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        countdown.invalidate()
        alert.window.orderOut(nil)
        let confirmed = response == .alertFirstButtonReturn && !expired &&
            ProcessInfo.processInfo.systemUptime < deadline
        if !confirmed {
            let restored = displayController.rotateBuiltin(to: current)
            log(restored ? "Built-in rotation not confirmed; requested revert to \(current)°" : "Built-in rotation revert failed")
        } else {
            log("Built-in rotation confirmed at \(next)°")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func displayAutoPresetChanged() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else {
            refreshControls()
            return
        }
        isDisplayAutoPresetEnabled = displayAutoPresetSwitch.state == .on
        UserDefaults.standard.set(isDisplayAutoPresetEnabled, forKey: "displayAutoPresetEnabled")
        if isDisplayAutoPresetEnabled {
            saveDisplayBaselineIfNeeded()
            if !displayController.externalDisplays().isEmpty { _ = displayController.apply(automaticRotationPreset()) }
            log("Rotation auto preset on")
        } else {
            // Turning the preset off returns to landscape explicitly; the old baseline may already be 270°, so it must not be reapplied.
            UserDefaults.standard.removeObject(forKey: "displayAutoBaseline")
            resetBuiltinRotationWhenPresetDisabled()
            log("Rotation auto preset off; future connections stay at 0°")
        }
        refreshControls()
    }

    private func resetBuiltinRotationWhenPresetDisabled() {
        guard !isDisplayAutoPresetEnabled,
              let builtin = displayController.builtinDisplay(),
              CGDisplayIsOnline(builtin) != 0 else { return }
        if Int(CGDisplayRotation(builtin).rounded()) != 0 {
            let requested = displayController.rotateBuiltin(to: 0)
            log("Auto preset off; built-in landscape request: \(requested)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, !self.isDisplayAutoPresetEnabled,
                  let id = self.displayController.builtinDisplay() else { return }
            log("Auto preset off; built-in rotation readback: \(Int(CGDisplayRotation(id).rounded()))°")
            self.refreshControls()
        }
    }

    @objc private func showRotationModeMenu() {
        let menu = NSMenu()
        let preset = loadRotationPreset()
        let apply = NSMenuItem(title: String(localized: "Apply “\(preset.name)”"), action: #selector(applyRotationPreset), keyEquivalent: "")
        apply.target = self; menu.addItem(apply)
        let save = NSMenuItem(title: String(localized: "Save Current as Rotation Preset…"), action: #selector(saveCurrentRotationPreset), keyEquivalent: "")
        save.target = self; menu.addItem(save)
        menu.addItem(.separator())
        let automatic = NSMenuItem(title: String(localized: "Apply Automatically When Studio Display Connects"), action: #selector(toggleRotationPresetAutomation), keyEquivalent: "")
        automatic.target = self; automatic.state = isDisplayAutoPresetEnabled ? .on : .off
        menu.addItem(automatic)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: rotationModeButton.bounds.height + 4), in: rotationModeButton)
    }

    @objc private func applyRotationPreset() {
        guard isDisplaySessionSafe, !isConsoleSessionLocked() else { return }
        if !displayController.apply(loadRotationPreset()) { log("Failed to apply rotation preset") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.refreshControls() }
    }

    @objc private func saveCurrentRotationPreset() {
        guard let current = displayController.currentPreset(name: String(localized: "My Rotation Preset")) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Rotation Preset")
        alert.informativeText = String(localized: "Saves the built-in display on/off state, rotation, and main display role.")
        let field = NSTextField(string: loadRotationPreset().name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save")); alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var preset = current
        preset.name = field.stringValue.isEmpty ? String(localized: "My Rotation Preset") : field.stringValue
        saveRotationPreset(preset)
        log("Saved rotation preset: \(preset.name)")
    }

    @objc private func toggleRotationPresetAutomation() {
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .off : .on
        displayAutoPresetChanged()
    }

    func handleStudioDisplayConnection(connected: Bool) {
        pendingDisplayConnectionState = connected
        if connected {
            pendingBuiltinWakeWorkItems.forEach { $0.cancel() }
            pendingBuiltinWakeWorkItems.removeAll()
        }
        if !connected {
            // Skip the 5-second session settle period; enable the built-in display first, restore rotation and main display later.
            isBuiltinManuallyDisabled = false
            requestBuiltinWakeAfterExternalDisconnect()
            log("External display disconnected; scheduled forced built-in enable with separate retries")
        }
        guard isDisplaySessionSafe else { return }
        pendingDisplayConnectionState = nil
        scheduleDisplayPolicy(forExternalConnection: connected)
    }

    @objc private func applicationWillTerminate() {
        pendingDisplayPolicyWorkItem?.cancel()
        _ = displayController.setStudioEnabled(true)
        _ = keepAwakeController.setActive(false)
        clearPublishedLampState()
    }

    // MARK: - Status menu (left-click)

    private func buildStatusMenu() -> NSMenu {
        refreshControls()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let lampConnected = lamp.isConnected

        menu.addItem(toggleItem(String(localized: "Light"), control: powerSwitch))

        let brightnessMenu = NSMenu()
        brightnessMenu.autoenablesItems = false
        for value in [25, 50, 75, 100] {
            let entry = actionItem("\(value)%", action: #selector(menuBrightnessChanged(_:)), tag: value)
            entry.state = lamp.currentBrightness == value ? .on : .off
            entry.isEnabled = lampConnected
            brightnessMenu.addItem(entry)
        }
        menu.addItem(submenuItem(String(localized: "Brightness"), brightnessMenu))

        let temperatureMenu = NSMenu()
        temperatureMenu.autoenablesItems = false
        temperatureMenu.addItem(toggleItem(String(localized: "Auto Temp"), control: timeTemperatureSwitch))
        temperatureMenu.addItem(.separator())
        for value in [2700, 4000, 5000, 6500] {
            let entry = actionItem("\(value)K", action: #selector(menuTemperatureChanged(_:)), tag: value)
            entry.state = !isTimeTemperatureEnabled && lamp.currentTemperature == value ? .on : .off
            entry.isEnabled = temperatureSlider.isEnabled
            temperatureMenu.addItem(entry)
        }
        menu.addItem(submenuItem(String(localized: "Color Temperature"), temperatureMenu))

        let lampMenu = NSMenu()
        lampMenu.autoenablesItems = false
        for control in [autoLightSwitch, presenceSwitch, videoModeSwitch] {
            lampMenu.addItem(toggleItem(control.title, control: control))
        }
        lampMenu.addItem(.separator())
        for control in [brightnessFollowSwitch, displayBrightnessLockSwitch, powerSyncSwitch] {
            lampMenu.addItem(toggleItem(control.title, control: control))
        }
        let presenceWakeItem = toggleItem(String(localized: "Wake Screen on Presence"), control: presenceWakeSwitch)
        presenceWakeItem.indentationLevel = 1
        lampMenu.addItem(presenceWakeItem)
        menu.addItem(submenuItem(String(localized: "Lamp"), lampMenu))

        updateAmbientControlAvailability()
        menu.addItem(toggleItem(String(localized: "Ambient Rules"), control: ambientEnableSwitch))

        let displayMenu = NSMenu()
        displayMenu.autoenablesItems = false
        if showsDisplaySection {
            addDisplayControls(to: displayMenu)
        } else {
            displayMenu.addItem(toggleItem("Studio Display", control: studioPowerSwitch))
        }
        menu.addItem(submenuItem(String(localized: "Displays"), displayMenu))

        let favoritesMenu = NSMenu()
        favoritesMenu.autoenablesItems = false
        for (index, title) in modeNames().enumerated() {
            let entry = actionItem(title, action: #selector(presetChanged(_:)), tag: index)
            entry.state = title == modeButton.title ? .on : .off
            entry.isEnabled = lampConnected
            favoritesMenu.addItem(entry)
        }
        favoritesMenu.addItem(.separator())
        favoritesMenu.addItem(actionItem(String(localized: "Mode Center…"), action: #selector(showModeCenter)))
        menu.addItem(submenuItem(String(localized: "Favorites"), favoritesMenu))

        menu.addItem(toggleItem(String(localized: "Keep Awake"), control: keepAwakeSwitch))

        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Control Panel…"), action: #selector(openPanelFromMenu)))

        menu.addItem(.separator())
        let login = actionItem(String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(actionItem(String(localized: "Help…"), action: #selector(showHelp)))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit iScreenBar Menu"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func addDisplayControls(to displayMenu: NSMenu) {
        displayMenu.addItem(toggleItem(String(localized: "Built-in Display"), control: displayPowerSwitch))
        let rotateMenu = NSMenu()
        rotateMenu.autoenablesItems = false
        let currentRotation = displayController.builtinDisplay().map { Int(CGDisplayRotation($0).rounded()) }
        for degrees in [0, 90, 180, 270] {
            let entry = actionItem("\(degrees)°", action: #selector(menuRotationChanged(_:)), tag: degrees)
            entry.state = currentRotation == degrees ? .on : .off
            entry.isEnabled = displayRotateButton.isEnabled
            rotateMenu.addItem(entry)
        }
        let rotateItem = submenuItem(String(localized: "Rotate Built-in"), rotateMenu)
        rotateItem.isEnabled = displayRotateButton.isEnabled
        displayMenu.addItem(rotateItem)
        displayMenu.addItem(toggleItem("Studio Display", control: studioPowerSwitch))
        displayMenu.addItem(.separator())
        let preset = loadRotationPreset()
        let applyPreset = actionItem(String(localized: "Apply “\(preset.name)”"), action: #selector(applyRotationPreset))
        applyPreset.isEnabled = rotationModeButton.isEnabled
        displayMenu.addItem(applyPreset)
        displayMenu.addItem(toggleItem(String(localized: "Apply Automatically When Studio Display Connects"),
                                       control: displayAutoPresetSwitch))
    }

    private func actionItem(_ title: String, action: Selector, tag: Int = 0) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        return entry
    }

    private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = submenu
        return entry
    }

    // Mirrors a panel toggle; choosing it flips the control and runs the control's own handler.
    private func toggleItem(_ title: String, control: NSButton) -> NSMenuItem {
        let entry = actionItem(title, action: #selector(menuToggleChanged(_:)))
        entry.representedObject = control
        entry.state = control.state
        entry.isEnabled = control.isEnabled
        return entry
    }

    @objc private func menuToggleChanged(_ sender: NSMenuItem) {
        guard let control = sender.representedObject as? NSButton, let action = control.action else { return }
        control.state = control.state == .on ? .off : .on
        NSApp.sendAction(action, to: control.target, from: control)
    }

    @objc private func menuBrightnessChanged(_ sender: NSMenuItem) {
        brightnessSlider.doubleValue = Double(sender.tag)
        brightnessChanged()
    }

    @objc private func menuTemperatureChanged(_ sender: NSMenuItem) {
        temperatureSlider.doubleValue = Double(sender.tag)
        temperatureChanged()
    }

    @objc private func openPanelFromMenu() {
        // Wait for the menu to finish closing before anchoring the popover to the status button.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.togglePanel()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LoginItem.isEnabled
        guard LoginItem.setEnabled(enable) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't Change Launch at Login")
            alert.informativeText = String(localized: "The login item in ~/Library/LaunchAgents couldn't be updated.")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        log(enable ? "Launch at login on (LaunchAgent written)" : "Launch at login off (LaunchAgent removed)")
    }

    @objc private func showAbout() {
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func showHelp() {
        if popover.isShown { popover.performClose(nil) }
        let controller = helpWindowController ?? HelpWindowController()
        helpWindowController = controller
        controller.present()
    }

    @objc private func quitApp() {
        log("Quit requested")
        NSApp.terminate(nil)
    }

    private func configurePanel() {
        powerSwitch.target = self
        powerSwitch.action = #selector(powerChanged)
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.isContinuous = false
        temperatureSlider.target = self
        temperatureSlider.action = #selector(temperatureChanged)
        temperatureSlider.isContinuous = false
        temperatureSlider.numberOfTickMarks = 5
        temperatureSlider.tickMarkPosition = .below
        timeTemperatureSwitch.target = self
        timeTemperatureSwitch.action = #selector(timeTemperatureChanged)
        timeTemperatureSwitch.toolTip = String(localized: "Adjust color temperature automatically by time of day")
        autoLightSwitch.target = self
        autoLightSwitch.action = #selector(autoLightChanged)
        autoLightSwitch.toolTip = String(localized: "Turn the lamp's auto-light on or off with the official HID command")
        presenceSwitch.target = self
        presenceSwitch.action = #selector(presenceChanged)
        for seconds in presenceDelayOptions {
            let title = String(localized: "\(seconds / 60) min")
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = seconds
            presenceDelayPopup.menu?.addItem(item)
        }
        presenceDelayPopup.target = self
        presenceDelayPopup.action = #selector(presenceDelayChanged)
        selectPresenceDelay(presenceDelaySeconds)
        for (title, value) in [(String(localized: "Low"), 0), (String(localized: "Medium"), 1), (String(localized: "High"), 2)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = value
            presenceSensitivityPopup.menu?.addItem(item)
        }
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        presenceSensitivityPopup.target = self
        presenceSensitivityPopup.action = #selector(presenceSensitivityChanged)
        presenceWakeSwitch.target = self
        presenceWakeSwitch.action = #selector(presenceWakeChanged)
        presenceWakeSwitch.toolTip = String(localized: "Wake the display when presence detection turns the lamp back on. Needs Presence and Sleep Sync")
        videoModeSwitch.target = self
        videoModeSwitch.action = #selector(videoModeChanged)
        modeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        modeButton.imagePosition = .imageTrailing
        modeButton.alignment = .left
        modeButton.bezelStyle = .rounded
        modeButton.controlSize = .large
        modeButton.font = UIStyle.bodyFont
        modeButton.target = self
        modeButton.action = #selector(showModeMenu)
        bindAppButton.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil)
        bindAppButton.imagePosition = .imageLeading
        bindAppButton.bezelStyle = .roundRect
        bindAppButton.controlSize = .small
        bindAppButton.target = self
        bindAppButton.action = #selector(bindCurrentModeToApp)
        brightnessFollowSwitch.target = self
        brightnessFollowSwitch.action = #selector(brightnessFollowChanged)
        displayBrightnessLockSwitch.target = self
        displayBrightnessLockSwitch.action = #selector(displayBrightnessLockChanged)
        displayBrightnessLockSwitch.toolTip = String(localized: "Locks the current brightness difference between the MacBook display and Studio Display; adjusting either one moves both")
        powerSyncSwitch.target = self
        powerSyncSwitch.action = #selector(powerSyncChanged)
        keepAwakeSwitch.target = self
        keepAwakeSwitch.action = #selector(keepAwakeChanged)
        keepAwakeSwitch.toolTip = String(localized: "Prevents sleep on battery, on power, or with the lid closed; needs administrator authorization the first time")
        captureBrightButton.target = self
        captureBrightButton.action = #selector(captureBrightThreshold)
        captureBrightButton.setButtonType(.momentaryPushIn)
        captureBrightButton.toolTip = String(localized: "Click to save the current ambient value as the bright (light off) point")
        captureDarkButton.target = self
        captureDarkButton.action = #selector(captureDarkThreshold)
        captureDarkButton.setButtonType(.momentaryPushIn)
        captureDarkButton.toolTip = String(localized: "Click to save the current ambient value as the dim (light on) point")
        ambientEnableSwitch.target = self
        ambientEnableSwitch.action = #selector(ambientEnableChanged)
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
        }
        ambientStatusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        ambientStatusLabel.textColor = .secondaryLabelColor
        displayPowerSwitch.target = self
        displayPowerSwitch.action = #selector(displayPowerChanged)
        studioPowerSwitch.target = self
        studioPowerSwitch.action = #selector(studioPowerChanged)
        studioPowerSwitch.toolTip = String(localized: "Pure black overlay; doesn't disconnect the display or change window layout. Double-click the black screen or click the button again to restore")
        displayRotateButton.setButtonType(.momentaryPushIn)
        displayRotateButton.target = self
        displayRotateButton.action = #selector(displayRotationChanged)
        displayAutoPresetSwitch.target = self
        displayAutoPresetSwitch.action = #selector(displayAutoPresetChanged)
        rotationModeButton.title = loadRotationPreset().name
        rotationModeButton.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)
        rotationModeButton.imagePosition = .imageTrailing
        rotationModeButton.alignment = .left
        rotationModeButton.bezelStyle = .rounded
        rotationModeButton.controlSize = .large
        rotationModeButton.font = UIStyle.bodyFont
        rotationModeButton.target = self
        rotationModeButton.action = #selector(showRotationModeMenu)

        [brightnessSlider, temperatureSlider].forEach { $0.controlSize = .small }
        [presenceDelayPopup, presenceSensitivityPopup].forEach { $0.controlSize = .small }
        brightnessValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        brightnessValueLabel.textColor = .secondaryLabelColor
        temperatureValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        temperatureValueLabel.textColor = .secondaryLabelColor

        let brightnessRow = sliderRow(symbol: "sun.max", title: String(localized: "Brightness"), slider: brightnessSlider, valueLabel: brightnessValueLabel)
        let temperatureRow = sliderRow(symbol: "thermometer.medium", title: String(localized: "Color Temp"), slider: temperatureSlider, valueLabel: temperatureValueLabel)
        let delayField = optionField(symbol: "clock", title: String(localized: "Away Delay"), control: presenceDelayPopup)
        let sensitivityField = optionField(symbol: "gauge", title: String(localized: "Sensitivity"), control: presenceSensitivityPopup)
        let presenceOptions = NSStackView(views: [delayField, sensitivityField])
        presenceOptions.orientation = .horizontal
        presenceOptions.alignment = .top
        presenceOptions.spacing = 12
        delayField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        sensitivityField.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let featureTitle = sectionLabel(String(localized: "Quick Controls"))
        let featureGrid = NSGridView(views: [
            [powerSwitch, autoLightSwitch, presenceSwitch],
            [videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch],
            [timeTemperatureSwitch, displayBrightnessLockSwitch, keepAwakeSwitch]
        ])
        featureGrid.rowSpacing = 6
        featureGrid.columnSpacing = 6
        featureGrid.xPlacement = .fill
        for button in [powerSwitch, autoLightSwitch, presenceSwitch, videoModeSwitch, brightnessFollowSwitch, powerSyncSwitch, timeTemperatureSwitch, displayBrightnessLockSwitch, keepAwakeSwitch] {
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let featureContainer = NSStackView(views: [featureTitle, featureGrid])
        featureContainer.orientation = .vertical
        featureContainer.alignment = .leading
        featureContainer.spacing = UIStyle.sectionSpacing

        let adjustmentTitle = sectionLabel(String(localized: "Light Adjustment"))
        let adjustmentContainer = NSStackView(views: [adjustmentTitle, brightnessRow, temperatureRow])
        adjustmentContainer.orientation = .vertical
        adjustmentContainer.alignment = .leading
        adjustmentContainer.spacing = 8

        let presetTitle = sectionLabel(String(localized: "Light Presets"))
        modeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        modeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let rotationPresetTitle = sectionLabel(String(localized: "Rotation Preset"))
        rotationModeButton.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        rotationModeButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let presetContainer = NSStackView(views: [presetTitle, modeButton, rotationPresetTitle, rotationModeButton])
        presetContainer.orientation = .vertical
        presetContainer.alignment = .leading
        presetContainer.spacing = UIStyle.sectionSpacing

        let presenceTitle = sectionLabel(String(localized: "Presence Detection"))
        let presenceWakeLabel = NSTextField(labelWithString: String(localized: "Wake Screen"))
        presenceWakeLabel.font = UIStyle.bodyFont
        presenceWakeLabel.textColor = .secondaryLabelColor
        let presenceHeader = NSStackView(views: [presenceTitle, flexibleSpace(), presenceWakeLabel, presenceWakeSwitch])
        presenceHeader.orientation = .horizontal
        presenceHeader.alignment = .centerY
        presenceHeader.spacing = 6
        presenceHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        let presenceContainer = NSStackView(views: [presenceHeader, presenceOptions])
        presenceContainer.orientation = .vertical
        presenceContainer.alignment = .leading
        presenceContainer.spacing = UIStyle.sectionSpacing

        let ambientTitle = sectionLabel(String(localized: "Ambient Light Calibration"))
        let ambientEnableLabel = NSTextField(labelWithString: String(localized: "Enable"))
        ambientEnableLabel.font = UIStyle.bodyFont
        ambientEnableLabel.textColor = .secondaryLabelColor
        let ambientHeader = NSStackView(views: [ambientTitle, flexibleSpace(), ambientEnableLabel, ambientEnableSwitch])
        ambientHeader.orientation = .horizontal
        ambientHeader.alignment = .centerY
        ambientHeader.spacing = 6
        ambientHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        for button in [captureBrightButton, captureDarkButton] {
            button.widthAnchor.constraint(equalToConstant: 106).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        for label in [brightThresholdLabel, darkThresholdLabel] {
            label.widthAnchor.constraint(equalToConstant: 34).isActive = true
        }
        let brightCapture = NSStackView(views: [captureBrightButton, brightThresholdLabel])
        brightCapture.orientation = .horizontal
        brightCapture.alignment = .centerY
        brightCapture.spacing = 4
        let darkCapture = NSStackView(views: [captureDarkButton, darkThresholdLabel])
        darkCapture.orientation = .horizontal
        darkCapture.alignment = .centerY
        darkCapture.spacing = 4
        let ambientActions = NSStackView(views: [brightCapture, darkCapture])
        ambientActions.orientation = .horizontal
        ambientActions.alignment = .centerY
        ambientActions.spacing = 12
        ambientActions.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        ambientStatusLabel.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        let ambientContainer = NSStackView(views: [ambientHeader, ambientActions, ambientStatusLabel])
        ambientContainer.orientation = .vertical
        ambientContainer.alignment = .leading
        ambientContainer.spacing = 6

        let displayGrid = NSGridView(views: [[displayPowerSwitch, displayRotateButton], [studioPowerSwitch, NSView()]])
        displayGrid.rowSpacing = 6
        displayGrid.columnSpacing = 6
        displayGrid.xPlacement = .fill
        for button in [displayPowerSwitch, studioPowerSwitch, displayRotateButton] {
            button.widthAnchor.constraint(equalToConstant: 153).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }
        let displayTitle = sectionLabel(String(localized: "Displays & Rotation"))
        let displayContainer = NSStackView(views: [displayTitle, displayGrid])
        displayContainer.orientation = .vertical
        displayContainer.alignment = .leading
        displayContainer.spacing = UIStyle.sectionSpacing

        let autoPresetLabel = NSTextField(labelWithString: String(localized: "Enable Preset"))
        autoPresetLabel.font = UIStyle.bodyFont
        autoPresetLabel.textColor = .secondaryLabelColor
        let rotationPresetHeader = NSStackView(views: [rotationPresetTitle, flexibleSpace(), autoPresetLabel, displayAutoPresetSwitch])
        rotationPresetHeader.orientation = .horizontal
        rotationPresetHeader.alignment = .centerY
        rotationPresetHeader.spacing = 6
        rotationPresetHeader.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        presetContainer.setViews([presetTitle, modeButton, rotationPresetHeader, rotationModeButton], in: .top)

        let aboutButton = NSButton(title: String(localized: "About…"), target: self, action: #selector(showAbout))
        let helpButton = NSButton(title: String(localized: "Help…"), target: self, action: #selector(showHelp))
        let quitButton = NSButton(title: String(localized: "Quit"), target: self, action: #selector(quitApp))
        for button in [aboutButton, helpButton, quitButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = UIStyle.captionFont
        }
        let footer = NSStackView(views: [flexibleSpace(), aboutButton, helpButton, quitButton])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true

        let displaySeparator = separator()
        displaySectionViews = [displaySeparator, displayContainer]
        rotationPresetViews = [rotationPresetHeader, rotationModeButton]
        let stack = NSStackView(views: [featureContainer, separator(), adjustmentContainer,
                                       separator(), ambientContainer, separator(), presenceContainer, displaySeparator, displayContainer,
                                       separator(), presetContainer, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: UIStyle.outerInset, bottom: 14, right: UIStyle.outerInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [brightnessRow, temperatureRow, presenceOptions] {
            view.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        }

        // Panel height fits the content (localized labels can change row heights); recomputed on open.
        panelStack = stack
        updateDisplaySectionVisibility()
        let panelHeight = ceil(stack.fittingSize.height)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: UIStyle.panelWidth, height: panelHeight))
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: controller.view.bottomAnchor)
        ])
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: UIStyle.panelWidth, height: panelHeight)
        log("Control panel height: \(Int(panelHeight)) pt")
        popover.behavior = .transient
    }

    private lazy var sliderLabelWidth: CGFloat = {
        let titles = [String(localized: "Brightness"), String(localized: "Color Temp")]
        let widest = titles.map { ceil(rowLabel($0).fittingSize.width) }.max() ?? 32
        return min(max(32, widest), 96)
    }()

    private func sliderRow(symbol: String, title: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let label = rowLabel(title)
        // Label column fits the widest localized slider title; the slider absorbs the difference.
        label.widthAnchor.constraint(equalToConstant: sliderLabelWidth).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 216 - sliderLabelWidth).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let row = NSStackView(views: [symbolView(symbol), label, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func optionField(symbol: String, title: String, control: NSView) -> NSStackView {
        let heading = NSStackView(views: [symbolView(symbol), rowLabel(title)])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 6
        let field = NSStackView(views: [heading, control])
        field.orientation = .vertical
        field.alignment = .leading
        field.spacing = 5
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return field
    }

    private func optionsRow(symbol: String, title: String, controls: [NSView]) -> NSStackView {
        let row = NSStackView(views: [symbolView(symbol), rowLabel(title), flexibleSpace()] + controls)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func symbolView(_ name: String) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        view.symbolConfiguration = .init(pointSize: UIStyle.iconSize, weight: .regular)
        view.widthAnchor.constraint(equalToConstant: 18).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.bodyFont
        return label
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = UIStyle.captionFont
        label.textColor = .secondaryLabelColor
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func separator() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: UIStyle.contentWidth).isActive = true
        return divider
    }

    /// Display and rotation controls only act on a built-in display (or a second screen). A desktop Mac with
    /// just the Studio Display has nothing to switch or rotate, so the section is hidden there.
    private var showsDisplaySection: Bool {
        displayController.builtinDisplay() != nil || displayController.externalDisplays().count > 1
    }

    private func updateDisplaySectionVisibility() {
        let hidden = !showsDisplaySection
        for view in displaySectionViews + rotationPresetViews where view.isHidden != hidden {
            view.isHidden = hidden
        }
    }

    private func refreshControls() {
        updateDisplaySectionVisibility()
        let displayControlsAllowed = isDisplaySessionSafe && !isConsoleSessionLocked()
        let studioID = displayController.studioTarget()
        studioPowerSwitch.state = studioID != nil && !displayController.isStudioCovered ? .on : .off
        studioPowerSwitch.isEnabled = displayControlsAllowed && studioID != nil
        powerSwitch.state = lamp.isPowerOn == true ? .on : .off
        let autoLightChangePending = autoLightChangePendingUntil.map { Date() < $0 } ?? false
        if isAmbientPresenceLockActive {
            autoLightSwitch.title = autoLightWasEnabledBeforeAmbientLock ? String(localized: "Auto Light Paused") : String(localized: "Auto Light")
            autoLightSwitch.state = autoLightWasEnabledBeforeAmbientLock ? .on : .off
            autoLightSwitch.toolTip = autoLightWasEnabledBeforeAmbientLock
                ? String(localized: "Was on; paused while the ambient off-lock is active and restored automatically afterward")
                : String(localized: "Auto light can't be turned on while the ambient off-lock is active")
        } else if autoLightChangePending, let pendingAutoLightState {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightSwitch.state = pendingAutoLightState ? .on : .off
            autoLightSwitch.toolTip = pendingAutoLightState ? String(localized: "Turning auto light on…") : String(localized: "Turning auto light off…")
        } else if lamp.isAutoLightEnabled == true {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .on
            autoLightSwitch.toolTip = String(localized: "Turn off auto light")
        } else {
            autoLightSwitch.title = String(localized: "Auto Light")
            autoLightChangePendingUntil = nil
            pendingAutoLightState = nil
            autoLightSwitch.state = .off
            autoLightSwitch.toolTip = String(localized: "Turn on auto light")
        }
        if isAmbientPresenceLockActive || isScreenSleepPresenceLockActive {
            let wasEnabled = presenceWasEnabledBeforeAmbientLock || presenceWasEnabledBeforeScreenSleep
            presenceSwitch.title = wasEnabled ? String(localized: "Presence Paused") : String(localized: "Presence")
            presenceSwitch.state = wasEnabled ? .on : .off
            presenceSwitch.toolTip = wasEnabled
                ? String(localized: "Was on; paused while the light-off lock is active and restored automatically afterward")
                : String(localized: "Presence detection can't be turned on while the light-off lock is active")
        } else {
            presenceSwitch.title = String(localized: "Presence")
            presenceSwitch.state = lamp.isPresenceDetectionEnabled == true ? .on : .off
            presenceSwitch.toolTip = String(localized: "Turn the lamp's presence detection on or off")
        }
        videoModeSwitch.state = lamp.isVideoModeEnabled == true ? .on : .off
        brightnessFollowSwitch.state = isBrightnessFollowEnabled ? .on : .off
        displayBrightnessLockSwitch.state = isDisplayBrightnessLockEnabled ? .on : .off
        displayBrightnessLockSwitch.isEnabled = displayControlsAllowed && studioDisplayID() != nil && activeBuiltinDisplayID() != nil
        powerSyncSwitch.state = isPowerSyncEnabled ? .on : .off
        presenceWakeSwitch.state = isPresenceWakeEnabled ? .on : .off
        keepAwakeSwitch.state = keepAwakeController.isActive ? .on : .off
        timeTemperatureSwitch.state = isTimeTemperatureEnabled ? .on : .off
        updateAmbientStatusLabel()
        if let builtin = displayController.builtinDisplay() {
            let online = CGDisplayIsOnline(builtin) != 0
            displayPowerSwitch.state = online ? .on : .off
            displayPowerSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable
            displayRotateButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            rotationModeButton.isEnabled = displayControlsAllowed && online && displayController.isAvailable
            displayRotateButton.title = online ? String(localized: "Rotate \(Int(CGDisplayRotation(builtin).rounded()))°") : String(localized: "Rotate —")
        } else {
            displayPowerSwitch.state = .off
            displayPowerSwitch.isEnabled = false
            displayRotateButton.isEnabled = false
            rotationModeButton.isEnabled = false
            displayRotateButton.title = String(localized: "Rotate —")
        }
        displayAutoPresetSwitch.state = isDisplayAutoPresetEnabled ? .on : .off
        displayAutoPresetSwitch.isEnabled = displayControlsAllowed && displayController.isAvailable && displayController.builtinDisplay() != nil
        rotationModeButton.title = loadRotationPreset().name
        selectPresenceDelay(presenceDelaySeconds)
        presenceSensitivityPopup.selectItem(withTag: presenceSensitivity)
        if let brightness = lamp.currentBrightness {
            brightnessSlider.doubleValue = Double(brightness)
            brightnessValueLabel.stringValue = "\(brightness)%"
        }
        if let temperature = lamp.currentTemperature {
            temperatureSlider.doubleValue = Double(temperature)
            temperatureValueLabel.stringValue = "\(temperature)K"
        }
        let enabled = lamp.isConnected
        powerSwitch.isEnabled = enabled
        autoLightSwitch.isEnabled = enabled && !isAmbientPresenceLockActive
        brightnessSlider.isEnabled = enabled
        temperatureSlider.isEnabled = enabled && !isTimeTemperatureEnabled
        timeTemperatureSwitch.isEnabled = enabled
        presenceSwitch.isEnabled = enabled && !isAmbientPresenceLockActive && !isScreenSleepPresenceLockActive
        videoModeSwitch.isEnabled = enabled
        powerSyncSwitch.isEnabled = enabled
        updateAmbientControlAvailability()
        presenceDelayPopup.isEnabled = enabled
        presenceSensitivityPopup.isEnabled = enabled
        // Turning it off stays possible even without Sleep Sync, so the setting is never stuck on.
        presenceWakeSwitch.isEnabled = enabled && (isPowerSyncEnabled || isPresenceWakeEnabled)
    }

    private func updateIcon(healthy: Bool) {
        let iconColor: NSColor
        if !healthy {
            iconColor = .systemRed
        } else if lamp.isPowerOn == true {
            iconColor = .systemYellow
        } else {
            iconColor = .systemGray
        }
        // 15 pt is ~2 px larger than the default status-item symbol size.
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))
        let symbol = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: String(localized: "iScreenBar status"))?
            .withSymbolConfiguration(configuration)
        symbol?.isTemplate = false
        item.button?.attributedTitle = NSAttributedString(string: "")
        item.button?.image = symbol
    }

    private func selectPresenceDelay(_ seconds: Int) {
        if let item = presenceDelayPopup.menu?.item(withTag: seconds) {
            presenceDelayPopup.select(item)
            return
        }
        if let fallback = presenceDelayPopup.itemArray.first(where: { $0.tag == 180 }) {
            presenceDelayPopup.select(fallback)
        }
    }

    private func selectedPresenceDelaySeconds() -> Int {
        return presenceDelayPopup.selectedItem?.tag ?? presenceDelaySeconds
    }

}

// MARK: - Automation (AppleScript, App Intents, Control Center)

// Same path as the menu's toggleItem: set the panel control, then run its own action,
// so automation gets the same side effects, saving, and mutual exclusions.
extension StatusIndicator: AutomationTarget {
    private func automationControl(for feature: AutomationFeature) -> NSButton {
        switch feature {
        case .light: return powerSwitch
        case .autoTemperature: return timeTemperatureSwitch
        case .autoLight: return autoLightSwitch
        case .presence: return presenceSwitch
        case .videoMode: return videoModeSwitch
        case .matchScreen: return brightnessFollowSwitch
        case .linkScreens: return displayBrightnessLockSwitch
        case .sleepSync: return powerSyncSwitch
        case .wakeScreen: return presenceWakeSwitch
        case .keepAwake: return keepAwakeSwitch
        case .builtinDisplay: return displayPowerSwitch
        }
    }

    private func requiresLamp(_ feature: AutomationFeature) -> Bool {
        switch feature {
        case .light, .autoTemperature, .autoLight, .presence, .videoMode, .sleepSync, .wakeScreen: return true
        case .matchScreen, .linkScreens, .keepAwake, .builtinDisplay: return false
        }
    }

    var isLampConnected: Bool { lamp.isConnected }
    var lampBrightness: Int? { lamp.isConnected ? lamp.currentBrightness : nil }
    var lampTemperature: Int? { lamp.isConnected ? lamp.currentTemperature : nil }
    var isLampPowerOn: Bool { lamp.isPowerOn == true }
    var isAutoTemperatureOn: Bool { isTimeTemperatureEnabled }
    var isKeepAwakeActive: Bool { keepAwakeController.isActive }
    var favoriteNames: [String] { modeNames() }
    var rotationPresetName: String { loadRotationPreset().name }

    func isOn(_ feature: AutomationFeature) -> Bool {
        refreshControls()
        return automationControl(for: feature).state == .on
    }

    func setFeature(_ feature: AutomationFeature, on: Bool) throws {
        refreshControls()
        if requiresLamp(feature), !lamp.isConnected { throw AutomationError.lampNotConnected }
        let control = automationControl(for: feature)
        guard control.isEnabled, let action = control.action else { throw AutomationError.unavailable(feature.localizedName) }
        let target: NSControl.StateValue = on ? .on : .off
        guard control.state != target else { return }
        control.state = target
        NSApp.sendAction(action, to: control.target, from: control)
        guard control.state == target else { throw AutomationError.failed(feature.localizedName) }
        log("Automation: \(feature.rawValue) \(on ? "on" : "off")")
    }

    func setBrightness(_ value: Int) throws {
        refreshControls()
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        guard brightnessSlider.isEnabled else { throw AutomationError.unavailable(String(localized: "Brightness")) }
        brightnessSlider.doubleValue = Double(max(1, min(100, value)))
        brightnessChanged()
        log("Automation: brightness \(Int(brightnessSlider.doubleValue))%")
    }

    func setTemperature(_ kelvin: Int) throws {
        refreshControls()
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        guard !isTimeTemperatureEnabled else { throw AutomationError.autoTemperatureOn }
        guard temperatureSlider.isEnabled else { throw AutomationError.unavailable(String(localized: "Color Temperature")) }
        temperatureSlider.doubleValue = Double(max(2700, min(6500, kelvin)))
        temperatureChanged()
        log("Automation: color temperature \(Int(temperatureSlider.doubleValue))K")
    }

    func applyFavorite(named name: String) throws {
        let names = modeNames()
        // Built-in favorites also match their English names, whatever the UI language.
        let englishBuiltins = ["Favorite", "Night Work", "Wind Down"]
        let index = names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
            ?? englishBuiltins.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        guard let index else { throw AutomationError.unknownFavorite(name) }
        guard lamp.isConnected else { throw AutomationError.lampNotConnected }
        let entry = NSMenuItem(title: names[index], action: nil, keyEquivalent: "")
        entry.tag = index
        presetChanged(entry)
    }

    func applyRotationPresetFromAutomation() throws {
        refreshControls()
        guard rotationModeButton.isEnabled else { throw AutomationError.unavailable(String(localized: "Rotation preset")) }
        applyRotationPreset()
        log("Automation: applied rotation preset")
    }

    func showControlPanel() {
        NSApp.activate(ignoringOtherApps: true)
        openPanelFromMenu()
    }
}

private final class LampController {
    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private(set) var currentBrightness: Int?
    private(set) var currentTemperature: Int?
    private(set) var isPowerOn: Bool?
    private(set) var isAutoLightEnabled: Bool?
    private(set) var isPresenceDetectionEnabled: Bool?
    private(set) var isVideoModeEnabled: Bool?
    private(set) var statusRevision = 0
    private var lastTemperatureValues: (Int, Int)?
    private var lastStatusHex: String?
    private(set) var lastPowerCommandAt = Date.distantPast

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
        lastPowerCommandAt = Date()
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
        isAutoLightEnabled = enabled
        log(enabled ? "Auto-light on" : "Auto-light off")
        return true
    }

    func setPresenceDetection(enabled: Bool, delaySeconds: Int, sensitivity: Int) -> Bool {
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
                    controller.isAutoLightEnabled = (report[6] & 0x04) != 0
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

private final class DisplayBrightnessReader {
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

private final class StudioDisplayAmbientSensor {
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

private func studioDisplayID() -> CGDirectDisplayID? {
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

private func activeBuiltinDisplayID() -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
    return displays.prefix(Int(count)).first {
        CGDisplayIsBuiltin($0) != 0 && CGDisplayIsOnline($0) != 0 && CGDisplayIsActive($0) != 0
    }
}

private func isConsoleSessionLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}

// Up to 0.4 the app was "iScreen Menu" with bundle ID org.windholm.iScreenMenu. Copy its settings once into the
// current domain (keys already set here win); the old domain is left in place. Runs before anything reads defaults.
private func importPreRenameSettingsIfNeeded() {
    let oldDomain = "org.windholm.iScreenMenu"
    let doneKey = "importedPreRenameSettings"
    let defaults = UserDefaults.standard
    guard let currentDomain = Bundle.main.bundleIdentifier, currentDomain != oldDomain,
          !defaults.bool(forKey: doneKey) else { return }
    defaults.set(true, forKey: doneKey)
    guard let old = defaults.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
    let current = defaults.persistentDomain(forName: currentDomain) ?? [:]
    var copied = 0
    for (key, value) in old where current[key] == nil {
        defaults.set(value, forKey: key)
        copied += 1
    }
    log("Imported \(copied) settings from \(oldDomain)")
}
importPreRenameSettingsIfNeeded()

var displayID = studioDisplayID()
private let lamp = LampController()
private let displayBrightnessReader = DisplayBrightnessReader()
private let studioAmbientSensor = StudioDisplayAmbientSensor()

if let displayID {
    log("Monitoring Studio Display ID=\(displayID), resolution=\(CGDisplayPixelsWide(displayID))x\(CGDisplayPixelsHigh(displayID))")
} else {
    log("No external display found; waiting for Studio Display to connect")
}
var wasAsleep = displayID.map { CGDisplayIsAsleep($0) != 0 } ?? false
var wasConsoleSessionLocked = isConsoleSessionLocked()
var helperTurnedLampOff = false
var ambientTurnedLampOff = UserDefaults.standard.bool(forKey: "ambientLampLockActive")
var ambientCloseCandidateSince: Date?
var ambientOpenCandidateSince: Date?
var ambientProxySamples: [(Date, Int)] = []
var ambientProxySourceName: String?
var lastLoggedAmbientProxy: Int?
var presenceWakeRequestedAt: Date?
var lampSeenOffDuringSleep = false
var presenceUserActivityAssertion: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

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
private let statusIndicator = StatusIndicator(isAsleep: wasAsleep, lamp: lamp)
automationTarget = statusIndicator
installControlActionObserver()
statusIndicator.handleStudioDisplayConnection(connected: displayID != nil)
if !wasAsleep {
    statusIndicator.restorePresenceAfterScreenWake()
}
var wasBrightnessFollowEnabled = statusIndicator.isBrightnessFollowEnabled
var wasDisplayBrightnessLockEnabled = statusIndicator.isDisplayBrightnessLockEnabled
var wasPowerSyncEnabled = statusIndicator.isPowerSyncEnabled
var wasAmbientLinkEnabled = statusIndicator.isAmbientLinkEnabled
var wasAmbientCloseThreshold = statusIndicator.ambientCloseThreshold
var brightnessOffset: Int?
var anchorStatusRevision: Int?
var lastDisplayBrightness: Int?
var displayBrightnessOffset: Int?
var lastBuiltinDisplayBrightness: Int?
var lastStudioDisplayBrightnessForLock: Int?
var displayBrightnessWriteSuppressedUntil = Date.distantPast
var lastStatusRequest = Date.distantPast
var wasLampConnected = lamp.isConnected
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

private func pollDisplayAndLamp() {
    statusIndicator.applyModeForFrontmostAppIfNeeded()
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
    if !isAsleep {
        lampSeenOffDuringSleep = false
    } else if lamp.isPowerOn == false {
        lampSeenOffDuringSleep = true
    }
    if powerSyncEnabled, isAsleep {
        statusIndicator.suspendPresenceForScreenSleep()
        if lamp.isPowerOn == true {
            // Only an off → on change during this sleep counts; on the first asleep tick the lamp is still on from before.
            let lampTurnedItselfOn = lampSeenOffDuringSleep &&
                Date().timeIntervalSince(lamp.lastPowerCommandAt) >= presenceWakeOwnCommandWindow
            let mayWakeDisplay = statusIndicator.isPresenceWakeEnabled && lamp.isPresenceDetectionEnabled == true &&
                !ambientTurnedLampOff && lampTurnedItselfOn
            if let requestedAt = presenceWakeRequestedAt,
               Date().timeIntervalSince(requestedAt) < presenceWakeTimeout {
                // Waiting for the display to wake.
            } else if presenceWakeRequestedAt == nil, mayWakeDisplay {
                presenceWakeRequestedAt = Date()
                log(declarePresenceUserActivity()
                    ? "Presence detection turned the lamp on; waking the display"
                    : "Presence detection turned the lamp on, but the display wake request failed")
            } else {
                let turnedOff = lamp.setPower(on: false)
                helperTurnedLampOff = helperTurnedLampOff || turnedOff
                if turnedOff {
                    log(presenceWakeRequestedAt == nil
                        ? "Sleep sync overrode lamp turning itself back on"
                        : "Display stayed asleep after the presence wake request; sleep sync turned the lamp off")
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

    if brightnessFollowEnabled != wasBrightnessFollowEnabled {
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

let pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    pollDisplayAndLamp()
    MainActor.assumeIsolated { publishLampState() }
}
pollingTimer.tolerance = 0.05
pollDisplayAndLamp()
MainActor.assumeIsolated { publishLampState() }
NSApplication.shared.run()
