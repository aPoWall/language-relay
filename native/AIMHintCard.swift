// AIMHintCard · N1 · v1 · shared hint card for native AIM mini apps (AIM apps rule 30). Hand-written once, vendored byte for byte.
// Pairs with AIMMiniAppTokens.swift (generated), AIMVoxelModels.swift (generated) and AIMVoxelView.swift (hand-written). AppKit only.
// Contract, lifted from the MEM PRISM pressure hint: title · one line of fact · up to three buttons · thin N1 border
// · live character 40 pt on the left · appear = alpha 0 → 1 with a 6 pt rise over `motion-window-appear` (180 ms)
// · the character assembles 700 ms after the first frame · auto-hide after `autoHide` seconds or after any action.
// Reduce Motion: the card is shown at once and the character stays static; the gesture still works on click.
// The card never activates the app and never moves the cursor: hosts put it into a non-activating panel
// (`AIMHintCard.makePanel`) and order it front with `orderFrontRegardless()`.
import AppKit

public final class AIMHintCard: NSView {
    // MARK: contract
    public struct Action {
        public let label: String
        public let handler: () -> Void
        public init(_ label: String, _ handler: @escaping () -> Void) { self.label = label; self.handler = handler }
    }
    /// At most three buttons; extra actions are ignored and reported in the console once.
    public static let maxActions = 3
    /// Live character on the left, one size for every product.
    public static let markSize: CGFloat = 40
    public static let defaultWidth: CGFloat = 320
    public static let inset: CGFloat = 16
    public static let gap: CGFloat = 12
    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: palette and type · resolved from the generated tokens, hex mapped by the file-local helper in AIMVoxelView.swift
    private static func semantic(_ key: String, _ fallback: String) -> String { AIMMiniAppTokens.N1.semantic[key] ?? fallback }
    private static func component(_ key: String, _ fallback: String) -> String { AIMMiniAppTokens.N1.component[key] ?? fallback }
    public static let surface = NSColor(aimHex: component("hint-background", "#ffffff"))
    public static let ink = NSColor(aimHex: component("hint-text", "#202124"))
    public static let muted = NSColor(aimHex: semantic("text-secondary", "#6b6e75"))
    public static let border = NSColor(aimHex: component("hint-border", "#e8e9ed"))
    public static let hover = NSColor(aimHex: semantic("hover", "#f5f6f8"))
    public static let radius = CGFloat(AIMMiniAppTokens.number(component("hint-radius", "16px")) ?? 16)
    public static let controlRadius = CGFloat(AIMMiniAppTokens.number(semantic("radius-control", "8px")) ?? 8)
    /// Products register IBM Plex Mono under their own resource names; the card asks this hook first.
    /// Default: the Plex Mono faces if a host registered them, otherwise the system monospaced font.
    public static var font: (CGFloat, NSFont.Weight) -> NSFont = { size, weight in
        let name = weight >= .semibold ? "IBMPlexMono-SmBld" : weight >= .medium ? "IBMPlexMono-Medm" : "IBMPlexMono"
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    /// Appear timing from the shared tokens: `motion-window-appear` (180 ms) and `motion-window-appear-shift` (6 pt).
    public static var appearDuration: TimeInterval { AIMMiniAppTokens.seconds(semantic("motion-window-appear", "180ms"), reducedMotion: reduceMotion) }
    public static var appearShift: CGFloat { reduceMotion ? 0 : CGFloat(AIMMiniAppTokens.number(semantic("motion-window-appear-shift", "6px")) ?? 6) }

    // MARK: state
    public let markView: AIMVoxelView
    public private(set) var title: String
    public private(set) var fact: String
    public private(set) var actions: [Action]
    /// Seconds until the card reports `expired`; 0 keeps it until an action or `dismiss(reason:)`.
    public let autoHide: TimeInterval
    /// Called once with the reason: `expired`, `escape`, `action:<label>` or the reason passed to `dismiss(reason:)`.
    public var onDismiss: ((String) -> Void)?
    public private(set) var dismissed = false
    public private(set) var dismissReason: String?
    private var hideWork: DispatchWorkItem?
    private let titleLabel: NSTextField
    private let factLabel: NSTextField
    private var buttons: [Button] = []
    private let buttonRow = NSStackView()
    private let cardWidth: CGFloat

    public init(title: String, fact: String, actions: [Action], mark: AIMVoxelModel,
                onDismiss: ((String) -> Void)? = nil, autoHide: TimeInterval = 12, width: CGFloat = AIMHintCard.defaultWidth) {
        self.title = title
        self.fact = fact
        self.actions = Array(actions.prefix(AIMHintCard.maxActions))
        self.onDismiss = onDismiss
        self.autoHide = autoHide
        self.cardWidth = width
        markView = AIMVoxelView(model: mark, frame: NSRect(x: 0, y: 0, width: AIMHintCard.markSize, height: AIMHintCard.markSize))
        titleLabel = NSTextField(wrappingLabelWithString: title)
        factLabel = NSTextField(wrappingLabelWithString: fact)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 96))
        if actions.count > AIMHintCard.maxActions { NSLog("AIMHintCard: %d actions given, showing the first %d", actions.count, AIMHintCard.maxActions) }
        wantsLayer = true
        layer?.backgroundColor = AIMHintCard.surface.cgColor
        layer?.cornerRadius = AIMHintCard.radius
        layer?.borderWidth = 1
        layer?.borderColor = AIMHintCard.border.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
        build()
    }
    public required init?(coder: NSCoder) { fatalError("AIMHintCard is built in code") }
    deinit { hideWork?.cancel() }

    private func build() {
        let textWidth = cardWidth - 2 * AIMHintCard.inset - AIMHintCard.markSize - AIMHintCard.gap
        markView.translatesAutoresizingMaskIntoConstraints = false
        markView.widthAnchor.constraint(equalToConstant: AIMHintCard.markSize).isActive = true
        markView.heightAnchor.constraint(equalToConstant: AIMHintCard.markSize).isActive = true
        markView.showsShadow = false
        markView.padding = 0.4
        markView.toolTip = title
        for (label, size, weight, color, lines) in [(titleLabel, CGFloat(11), NSFont.Weight.semibold, AIMHintCard.ink, 2), (factLabel, 11, .regular, AIMHintCard.muted, 2)] {
            label.font = AIMHintCard.font(size, weight)
            label.textColor = color
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = lines
            label.preferredMaxLayoutWidth = textWidth
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        for (i, action) in actions.enumerated() {
            let b = Button(action.label, target: self, action: #selector(actionPressed(_:)))
            b.tag = i
            buttons.append(b)
            buttonRow.addArrangedSubview(b)
        }
        let column = NSStackView(views: actions.isEmpty ? [titleLabel, factLabel] : [titleLabel, factLabel, buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.setCustomSpacing(4, after: titleLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [markView, column])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = AIMHintCard.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AIMHintCard.inset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AIMHintCard.inset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: AIMHintCard.inset),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AIMHintCard.inset),
            widthAnchor.constraint(equalToConstant: cardWidth)
        ])
    }

    // MARK: text updates · the same card can refresh its line without a re-show
    public func update(title: String? = nil, fact: String? = nil) {
        if let title { self.title = title; titleLabel.stringValue = title; setAccessibilityLabel(title); markView.toolTip = title }
        if let fact { self.fact = fact; factLabel.stringValue = fact }
        needsLayout = true
    }

    // MARK: appear · alpha 0 → 1 with a 6 pt rise over motion-window-appear; the mark assembles after its first draw
    public func appear() {
        let duration = AIMHintCard.appearDuration, shift = AIMHintCard.appearShift
        markView.assemblesOnAppear = !AIMHintCard.reduceMotion && markView.assemblesOnAppear
        startAutoHide()
        guard duration > 0, let layer else { alphaValue = 1; return }
        alphaValue = 0
        layer.removeAnimation(forKey: "aim-appear")
        let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -shift
        rise.toValue = 0
        rise.duration = duration
        rise.timingFunction = ease
        layer.add(rise, forKey: "aim-appear")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = ease
            self.animator().alphaValue = 1
        }
    }

    // MARK: hide
    public func startAutoHide() {
        hideWork?.cancel(); hideWork = nil
        guard autoHide > 0, !dismissed else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismiss(reason: "expired") }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
    }
    public func cancelAutoHide() { hideWork?.cancel(); hideWork = nil }
    /// Reports the reason once; later calls are ignored. The host closes its panel in `onDismiss`.
    public func dismiss(reason: String) {
        guard !dismissed else { return }
        dismissed = true
        dismissReason = reason
        cancelAutoHide()
        onDismiss?(reason)
    }
    @objc private func actionPressed(_ sender: Button) {
        guard sender.tag < actions.count else { return }
        let action = actions[sender.tag]
        cancelAutoHide()
        action.handler()
        dismiss(reason: "action:" + action.label)
    }
    public override var acceptsFirstResponder: Bool { true }
    public override func cancelOperation(_ sender: Any?) { dismiss(reason: "escape") }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss(reason: "escape"); return }
        super.keyDown(with: event)
    }

    // MARK: panel helper · non-activating, no cursor or focus change; the host picks the origin
    public static func makePanel(for card: AIMHintCard) -> NSPanel {
        card.layoutSubtreeIfNeeded()
        let size = card.fittingSize
        card.frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(contentRect: card.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = card
        return panel
    }
    /// Orders the panel front at `origin` without activating anything and runs the appear transition.
    public func present(in panel: NSPanel, at origin: NSPoint) {
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        appear()
    }

    // MARK: button · the N1 control: 28 pt, 8 pt radius, divider stroke, hover wash, 2 pt focus ring
    public final class Button: NSButton {
        private var caption: String
        private var hovering = false { didSet { needsDisplay = true } }
        init(_ title: String, target: AnyObject?, action: Selector?) {
            caption = title.lowercased()
            super.init(frame: .zero)
            self.title = ""; self.target = target; self.action = action
            isBordered = false; focusRingType = .none
            translatesAutoresizingMaskIntoConstraints = false
            let text = NSAttributedString(string: caption, attributes: [.font: AIMHintCard.font(11, .medium)])
            widthAnchor.constraint(equalToConstant: max(56, ceil(text.size().width) + 20)).isActive = true
            heightAnchor.constraint(equalToConstant: 28).isActive = true
            setAccessibilityLabel(caption)
        }
        required init?(coder: NSCoder) { fatalError() }
        public override var acceptsFirstResponder: Bool { isEnabled }
        public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
        public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
        }
        public override func mouseEntered(with event: NSEvent) { hovering = true }
        public override func mouseExited(with event: NSEvent) { hovering = false }
        public override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
        public override func draw(_ dirtyRect: NSRect) {
            let r = AIMHintCard.controlRadius
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: r, yRadius: r)
            (hovering ? AIMHintCard.hover : AIMHintCard.surface).setFill(); shape.fill()
            AIMHintCard.border.setStroke(); shape.lineWidth = 1; shape.stroke()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            let color = !isEnabled ? AIMHintCard.muted : (hovering ? AIMHintCard.ink : AIMHintCard.muted)
            let text = NSAttributedString(string: caption, attributes: [.font: AIMHintCard.font(11, .medium), .paragraphStyle: paragraph, .foregroundColor: color])
            text.draw(in: NSRect(x: 4, y: (bounds.height - text.size().height) / 2, width: max(1, bounds.width - 8), height: text.size().height))
            if window?.firstResponder === self {
                AIMHintCard.ink.setStroke()
                let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: max(2, r - 2), yRadius: max(2, r - 2))
                focus.lineWidth = 2; focus.stroke()
            }
        }
    }
}
