import AppKit
import CoreText

// App-local G2 profile. Vendored and shared ShaperKit stay unchanged.
enum RelayStyle {
    static let bg = NSColor(hex: "#ffffff")
    static let ink = NSColor(hex: "#202124")
    static let muted = NSColor(hex: "#6b6e75")
    static let hair = NSColor(hex: "#e8e9ed")
    static let fill = NSColor(hex: "#f5f6f8")
    static let card = NSColor(hex: "#f2f3f5")
    static let accent = NSColor(hex: "#db303d")
    static let radius: CGFloat = 8
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
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

final class RelayButton: NSButton {
    var isActive = false { didSet { state = isActive ? .on : .off; needsDisplay = true } }
    private let caption: String
    private var hovering = false { didSet { needsDisplay = true } }
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
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func isAccessibilitySelected() -> Bool { isActive }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
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
            .foregroundColor: isEnabled ? RelayStyle.ink : RelayStyle.muted,
        ])
        text.draw(at: NSPoint(x: (bounds.width - text.size().width) / 2, y: (bounds.height - text.size().height) / 2))
        if let window, window.firstResponder === self {
            RelayStyle.ink.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5)
            ring.lineWidth = 1; ring.stroke()
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
