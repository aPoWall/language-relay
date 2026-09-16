import AppKit
import CoreText
import QuartzCore

// Local AppKit adapter for the generated N1 contract.
enum RelayStyle {
    private static let tokens = AIMMiniAppTokens.N1.semantic
    static let bg = NSColor(hex: tokens["canvas"]!)
    static let ink = NSColor(hex: tokens["text"]!)
    static let muted = NSColor(hex: tokens["text-secondary"]!)
    static let disabled = NSColor(hex: tokens["text-disabled"]!)
    static let hair = NSColor(hex: tokens["divider"]!)
    static let fill = NSColor(hex: tokens["selected"]!)
    static let card = NSColor(hex: tokens["data"]!)
    static let accent = NSColor(hex: tokens["selection"]!)
    static let focus = NSColor(hex: AIMMiniAppTokens.N1.component["focus-ring"]!)
    static let radius = CGFloat(AIMMiniAppTokens.number(tokens["radius-control"]!)!)
    static let contentRadius = CGFloat(AIMMiniAppTokens.number(tokens["radius-content"]!)!)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func stateDuration(reducedMotion: Bool) -> TimeInterval {
        AIMMiniAppTokens.seconds(tokens["motion-state"]!, reducedMotion: reducedMotion)
    }
    /// One appear transition for the AIM mini apps (AIM-APPS-RULES rule 28): the panel popover animates over
    /// `motion-panel-appear` (system NSPopover, ≈200 ms), a framed window over `motion-window-appear` (180 ms)
    /// with a `motion-window-appear-shift` (6 pt) rise. Reduce Motion turns every value into 0.
    static func panelAppearDuration(reducedMotion: Bool) -> TimeInterval {
        AIMMiniAppTokens.seconds(tokens["motion-panel-appear"]!, reducedMotion: reducedMotion)
    }
    static func windowAppearDuration(reducedMotion: Bool) -> TimeInterval {
        AIMMiniAppTokens.seconds(tokens["motion-window-appear"]!, reducedMotion: reducedMotion)
    }
    static func windowAppearShift(reducedMotion: Bool) -> CGFloat {
        reducedMotion ? 0 : CGFloat(AIMMiniAppTokens.number(tokens["motion-window-appear-shift"]!) ?? 0)
    }
    private static let registered: Void = {
        for weight in [400, 500, 600] {
            if let url = Bundle.main.url(forResource: "plex-mono-\(weight)", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        _ = registered
        let name = weight >= .semibold ? "IBMPlexMono-SmBld" : weight >= .medium ? "IBMPlexMono-Medm" : "IBMPlexMono"
        return NSFont(name: name, size: max(10, size)) ?? NSFont.monospacedSystemFont(ofSize: max(10, size), weight: weight)
    }
}

enum RelayFocus {
    static func target(in view: NSView, identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if view.identifier == identifier { return view }
        return view.subviews.lazy.compactMap { target(in: $0, identifier: identifier) }.first
    }
}

enum RelayMotion {
    static func reveal(_ view: NSView, reducedMotion: Bool = RelayStyle.reduceMotion) {
        view.layer?.removeAnimation(forKey: "relay-state")
        let duration = RelayStyle.stateDuration(reducedMotion: reducedMotion)
        guard duration > 0, view.window?.isVisible == true else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        view.layer?.add(animation, forKey: "relay-state")
    }
}

final class RelayButton: NSButton {
    var isActive = false { didSet { state = isActive ? .on : .off; needsDisplay = true } }
    var moveSelection: ((Int) -> Void)?
    private(set) var caption: String
    private var hovering = false { didSet { needsDisplay = true } }
    /// Glyph-only buttons (pin ◉/○) change their caption in place; the identifier and the VoiceOver name stay as set by the host.
    func setLabel(_ title: String) { caption = title; needsDisplay = true }
    init(_ title: String, target: AnyObject?, action: Selector?, width: CGFloat, height: CGFloat = 32, lowercase: Bool = true) {
        caption = lowercase ? title.lowercased() : title
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityLabel(caption)
        identifier = NSUserInterfaceItemIdentifier(caption)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { isEnabled }
    /// Tab reaches every button even when macOS Full Keyboard Access is off (NSButton drops out of the loop otherwise).
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func isAccessibilitySelected() -> Bool { isActive }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        // Tab / Shift-Tab walk the panel's key view loop here; NSButton's own path hands the event to the parent
        // (status bar) window, which closes a transient popover.
        if event.keyCode == 48, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) } else { window?.selectNextKeyView(nil) }
            return
        }
        guard isEnabled, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            super.keyDown(with: event); return
        }
        if let moveSelection, event.keyCode == 123 || event.keyCode == 124 {
            moveSelection(event.keyCode == 123 ? -1 : 1)
        } else if event.keyCode == 36 || event.keyCode == 49 || event.keyCode == 76 {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: RelayStyle.radius, yRadius: RelayStyle.radius)
        if hovering || isActive || isHighlighted {
            RelayStyle.fill.setFill(); shape.fill()
        }
        RelayStyle.hair.setStroke(); shape.lineWidth = 1; shape.stroke()
        if isActive {
            RelayStyle.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 8, y: 1, width: 16, height: 2), xRadius: 1, yRadius: 1).fill()
        }
        let text = NSAttributedString(string: caption, attributes: [
            .font: RelayStyle.mono(11, weight: isActive ? .medium : .regular),
            .foregroundColor: isEnabled ? RelayStyle.ink : RelayStyle.disabled,
        ])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: (bounds.height - text.size().height) / 2))
        if let window, window.firstResponder === self {
            RelayStyle.focus.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5)
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class RelaySegmentedControl: NSStackView {
    struct Item {
        let title: String
        let help: String
        let preservesCase: Bool
        init(_ title: String, help: String, preservesCase: Bool = false) {
            self.title = title; self.help = help; self.preservesCase = preservesCase
        }
    }
    var selectedIndex: Int { didSet { updateSelection() } }
    private let onSelection: ((Int) -> Void)?
    private(set) var segmentButtons: [RelayButton] = []
    init(items: [Item], selectedIndex: Int, width: CGFloat, height: CGFloat = 32, onSelection: ((Int) -> Void)? = nil) {
        self.selectedIndex = selectedIndex; self.onSelection = onSelection
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; distribution = .fillEqually; spacing = 4
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
        let buttonWidth = (width - spacing * CGFloat(max(0, items.count - 1))) / CGFloat(max(1, items.count))
        for (index, item) in items.enumerated() {
            let button = RelayButton(item.title, target: self, action: #selector(select(_:)), width: buttonWidth, height: height, lowercase: !item.preservesCase)
            button.tag = index; button.toolTip = item.help; button.setAccessibilityHelp(item.help)
            button.moveSelection = { [weak self] delta in
                guard let self else { return }
                let next = max(0, min(self.segmentButtons.count - 1, index + delta))
                let target = self.segmentButtons[next]
                self.window?.makeFirstResponder(target)
                self.select(target)
            }
            segmentButtons.append(button); addArrangedSubview(button)
        }
        updateSelection()
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func select(_ sender: RelayButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag; onSelection?(sender.tag)
    }
    private func updateSelection() {
        for (index, button) in segmentButtons.enumerated() { button.isActive = index == selectedIndex }
    }
}

func relaySectionHeader(_ text: String, width: CGFloat) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = RelayStyle.mono(10, weight: .medium)
    field.textColor = RelayStyle.muted
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(equalToConstant: width).isActive = true
    field.heightAnchor.constraint(equalToConstant: 14).isActive = true
    return field
}
