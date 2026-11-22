import AppKit

let activeControlColor = NSColor.controlAccentColor

enum UIStyle {
    static let panelWidth: CGFloat = 344
    static let contentWidth: CGFloat = 312
    static let outerInset: CGFloat = 16
    static let sectionSpacing: CGFloat = 8
    static let bodyFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let controlFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let captionFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let iconSize: CGFloat = 15
}

final class HighlightSliderCell: NSSliderCell {
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

final class InteractiveSlider: NSSlider {
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

func displayPowerIcon() -> NSImage {
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

final class FeatureButton: NSButton {
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

/// Keeps the macOS switch size and knob shape; only fixes the highlight color of the on state.
final class AccentSwitch: NSButton {
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
