import AppKit

// Help window: localized Help.rtf (en.lproj / zh-Hans.lproj) in a read-only text view.
// It follows the system Appearance; text and background use dynamic system colors, so a light/dark switch
// while the window is open redraws without reloading.
final class HelpWindowController: NSWindowController {
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
