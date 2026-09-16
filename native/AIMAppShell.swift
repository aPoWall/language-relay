// AIMAppShell · N1 · v1 · the L2 shell of every native AIM mini app (AIM apps rules 21, 22, 31, 32, 33, 34, 38).
// Hand-written once, vendored byte for byte. Pairs with AIMMiniAppTokens.swift, AIMAppMarks.swift and
// AIMAppMarkView.swift. AppKit only.
//
// Rule 34, level L2: a product declares name, version, tabs and body; the header, the tab strip, the pin,
// the footer line and the appearance come from here. Every component returns a finished NSView, so a product
// passes data and never draws the chrome again.
//
//   AIMAppHeader   mark 40 pt · name · optional status under the name · version · settings · pin · x (rule 32)
//   AIMPinButton   the one pin control, off by default, identifier `pin-panel` (rule 31)
//   AIMTabStrip    views only, red underline on the active tab, keys 1...N (rules 32, 37)
//   AIMFooterLine  keys · esc close · version and status, 11 pt muted (rule 22)
//   AIMSurface     one show by the appear token, one read-only outside-click monitor, one close(reason:) (rules 28, 29, 33)
//
// `NSColor(aimHex:)` lives in AIMVoxelView.swift; the files ship together in every product.
import AppKit

// MARK: - Style

/// Palette, type and the sizes the shell holds. Colours and motion come from the generated tokens;
/// the sizes are the L0 candidates named in MINI-APPS-CONTRACT.md and live here until the tokens carry them.
public enum AIMAppShellStyle {
    private static func semantic(_ key: String, _ fallback: String) -> String { AIMMiniAppTokens.N1.semantic[key] ?? fallback }
    private static func component(_ key: String, _ fallback: String) -> String { AIMMiniAppTokens.N1.component[key] ?? fallback }

    public static let canvas = NSColor(aimHex: semantic("canvas", "#ffffff"))
    public static let surface = NSColor(aimHex: component("button-background", "#ffffff"))
    public static let ink = NSColor(aimHex: semantic("text", "#202124"))
    public static let muted = NSColor(aimHex: semantic("text-secondary", "#6b6e75"))
    public static let disabled = NSColor(aimHex: semantic("text-disabled", "#c9cbd1"))
    public static let divider = NSColor(aimHex: semantic("divider", "#e8e9ed"))
    public static let hover = NSColor(aimHex: semantic("hover", "#f5f6f8"))
    public static let signal = NSColor(aimHex: semantic("selection", "#db303d"))

    public static let controlRadius = CGFloat(AIMMiniAppTokens.number(semantic("radius-control", "8px")) ?? 8)
    /// Content inset and the gap between groups (rule 23).
    public static let inset: CGFloat = 16
    /// Gap inside the header row (rule 34, `header-gap`).
    public static let gap: CGFloat = 8
    /// Header and footer control heights (rule 34, `control-height-compact` / `control-height-quiet`).
    public static let controlHeight: CGFloat = 28
    public static let quietHeight: CGFloat = 22
    public static let markSize = AIMAppMarkView.headerSize
    public static let titleSize: CGFloat = 20
    public static let subtitleSize: CGFloat = 10
    public static let footerSize = CGFloat(AIMMiniAppTokens.number(semantic("size-meta", "11px")) ?? 11)

    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    public static var panelAppear: TimeInterval { AIMMiniAppTokens.seconds(semantic("motion-panel-appear", "200ms"), reducedMotion: reduceMotion) }
    public static var windowAppear: TimeInterval { AIMMiniAppTokens.seconds(semantic("motion-window-appear", "180ms"), reducedMotion: reduceMotion) }
    public static var windowAppearShift: CGFloat {
        reduceMotion ? 0 : CGFloat(AIMMiniAppTokens.number(semantic("motion-window-appear-shift", "6px")) ?? 6)
    }

    /// Products register IBM Plex Mono under their own resource names; the shell asks this hook first.
    public static var font: (CGFloat, NSFont.Weight) -> NSFont = { size, weight in
        let name = weight >= .semibold ? "IBMPlexMono-SmBld" : weight >= .medium ? "IBMPlexMono-Medm" : "IBMPlexMono"
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// One label recipe for every piece of shell text.
    public static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = AIMShellLabel(labelWithString: text)
        field.font = font(size, weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    public static func spacer() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }
}

/// A label that asks for the point it draws past its measured width. AppKit measures a label to a fraction of a
/// point and lays it out on the alignment rect, so a footer line sized to the exact intrinsic width truncates
/// its own last character; rounding the request up ends that.
public final class AIMShellLabel: NSTextField {
    public override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        if size.width > 0 { size.width = ceil(size.width) + 2 }
        return size
    }
}

// MARK: - Button

/// The one shell button: 28 pt tall, 8 pt corners, hover fill, visible focus ring (rule 16).
/// `.navigation` drops the frame and marks the active item with the red underline of the tab strip.
public class AIMShellButton: NSButton {
    public enum Kind { case framed, navigation, quiet }
    public var kind: Kind = .framed { didSet { needsDisplay = true } }
    public var isActive = false { didSet { state = isActive ? .on : .off; needsDisplay = true } }
    private var caption: String
    private var hovering = false { didSet { needsDisplay = true } }
    private let handler: (() -> Void)?

    public init(_ title: String, width: CGFloat, height: CGFloat = AIMAppShellStyle.controlHeight, action: (() -> Void)? = nil) {
        caption = title.lowercased()
        handler = action
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityLabel(caption)
        if handler != nil { target = self; self.action = #selector(fire) }
    }
    public required init?(coder: NSCoder) { fatalError("AIMShellButton is built in code") }

    @objc private func fire() { handler?() }

    public func setCaption(_ text: String) {
        caption = text.lowercased()
        setAccessibilityLabel(caption)
        needsDisplay = true
    }
    public var captionText: String { caption }

    public override func isAccessibilitySelected() -> Bool { isActive }
    public override var acceptsFirstResponder: Bool { isEnabled }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }
    public override func mouseEntered(with event: NSEvent) { hovering = true }
    public override func mouseExited(with event: NSEvent) { hovering = false }

    public override func draw(_ dirtyRect: NSRect) {
        let radius = AIMAppShellStyle.controlRadius
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if kind != .navigation || hovering || isActive {
            (hovering || isActive ? AIMAppShellStyle.hover : AIMAppShellStyle.surface).setFill()
            shape.fill()
        }
        if kind == .framed {
            AIMAppShellStyle.divider.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        if kind == .navigation && isActive {
            // NSControl reports the flip of its cell, so the bottom edge is named, never assumed.
            AIMAppShellStyle.signal.setFill()
            let y = isFlipped ? bounds.height - 2 : 0
            NSBezierPath(roundedRect: NSRect(x: 10, y: y, width: max(2, bounds.width - 20), height: 2), xRadius: 1, yRadius: 1).fill()
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let color = !isEnabled ? AIMAppShellStyle.disabled : (isActive || hovering ? AIMAppShellStyle.ink : AIMAppShellStyle.muted)
        let text = NSAttributedString(string: caption, attributes: [
            .font: AIMAppShellStyle.font(11, isActive ? .semibold : .regular),
            .paragraphStyle: paragraph,
            .foregroundColor: color,
        ])
        text.draw(in: NSRect(x: 4, y: (bounds.height - text.size().height) / 2, width: max(1, bounds.width - 8), height: text.size().height))
        if window?.firstResponder === self {
            AIMAppShellStyle.ink.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: max(2, radius - 2), yRadius: max(2, radius - 2))
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

// MARK: - Pin

/// Rule 31: one pin control with one meaning, the surface survives an outside click.
/// Off by default; a stored `true` from an older build is migrated once under `migrationKey`.
public enum AIMPinPolicy {
    public static let pinDefault = false
    public static let migrationKey = "aim.shell.pin-migrated"
    public static func glyph(_ pinned: Bool) -> String { pinned ? "\u{25C9}" : "\u{25CB}" }
    /// One tooltip, the same wording in every product; the state is announced by the accessibility description.
    public static let tooltip = "pin: the panel stays open on a click outside"
    public static func accessibilityDescription(_ pinned: Bool) -> String { pinned ? "unpin panel" : "pin panel open" }
    /// A click outside closes an open, unpinned surface (rule 29).
    public static func closesOnOutsideClick(pinned: Bool, shown: Bool) -> Bool { shown && !pinned }
    public struct PinResolution: Equatable {
        public let pinned: Bool
        public let writePinned: Bool
        public let markMigrated: Bool
    }
    /// `stored`: the saved value (nil when never saved); `migrated`: the migration flag.
    public static func resolve(stored: Bool?, migrated: Bool) -> PinResolution {
        migrated ? PinResolution(pinned: stored ?? pinDefault, writePinned: false, markMigrated: false)
                 : PinResolution(pinned: pinDefault, writePinned: true, markMigrated: true)
    }
}

public final class AIMPinButton: AIMShellButton {
    public static let identifier = NSUserInterfaceItemIdentifier("pin-panel")
    /// Called with the new value after every press; the host stores it and re-arms its outside-click monitor.
    public var onChange: ((Bool) -> Void)?
    public private(set) var pinned: Bool

    public init(pinned: Bool = AIMPinPolicy.pinDefault, onChange: ((Bool) -> Void)? = nil) {
        self.pinned = pinned
        self.onChange = onChange
        super.init(AIMPinPolicy.glyph(pinned), width: AIMAppShellStyle.controlHeight, height: AIMAppShellStyle.controlHeight, action: nil)
        identifier = AIMPinButton.identifier
        toolTip = AIMPinPolicy.tooltip
        target = self
        action = #selector(toggle)
        apply()
    }
    public required init?(coder: NSCoder) { fatalError("AIMPinButton is built in code") }

    @objc private func toggle() { setPinned(!pinned); onChange?(pinned) }

    /// Host-side change (settings menu, migration, restore): updates the glyph and the description without a callback.
    public func setPinned(_ value: Bool) {
        pinned = value
        apply()
    }
    private func apply() {
        setCaption(AIMPinPolicy.glyph(pinned))
        isActive = pinned
        // Rule 31: the name follows the state, so a driver reads what the glyph shows.
        setAccessibilityLabel(AIMPinPolicy.accessibilityDescription(pinned))
    }
}

// MARK: - Header

/// Rules 21, 32: mark 40 pt · product name · optional status line under the name · then, on the right edge and
/// always in this order, version · `settings` · `pin` · `x`. A product without one of the four leaves the slot
/// empty and keeps the order.
public final class AIMAppHeader: NSView {
    public let markView: AIMAppMarkView
    public let nameLabel: NSTextField
    public let statusLabel: NSTextField?
    public let versionLabel: NSTextField?
    public private(set) var settingsButton: AIMShellButton?
    public private(set) var pinButton: AIMPinButton?
    public private(set) var closeButton: AIMShellButton?

    /// `status` is the line under the name; `nil` leaves the name alone.
    /// `onSettings`, `pin` and `onClose` are the three optional slots: a nil slot is simply absent.
    public init(mark: AIMAppMark,
                name: String,
                status: String? = nil,
                version: String? = nil,
                width: CGFloat,
                onSettings: (() -> Void)? = nil,
                pin: AIMPinButton? = nil,
                onClose: (() -> Void)? = nil) {
        markView = AIMAppMarkView(mark: mark, size: AIMAppShellStyle.markSize)
        nameLabel = AIMAppShellStyle.label(name, size: AIMAppShellStyle.titleSize, weight: .semibold, color: AIMAppShellStyle.ink)
        statusLabel = status.map { AIMAppShellStyle.label($0, size: AIMAppShellStyle.subtitleSize, weight: .medium, color: AIMAppShellStyle.muted) }
        versionLabel = version.map { AIMAppShellStyle.label($0, size: AIMAppShellStyle.footerSize, weight: .medium, color: AIMAppShellStyle.muted) }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: AIMAppShellStyle.markSize))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(name) header")

        let lines = NSStackView(views: statusLabel.map { [nameLabel, $0] } ?? [nameLabel])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 2
        lines.translatesAutoresizingMaskIntoConstraints = false

        var row: [NSView] = [markView, lines, AIMAppShellStyle.spacer()]
        if let versionLabel {
            versionLabel.alignment = .right
            versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.append(versionLabel)
        }
        if let onSettings {
            let settings = AIMShellButton("settings", width: 72, action: onSettings)
            settings.identifier = NSUserInterfaceItemIdentifier("settings")
            settings.kind = .framed          // one look for `settings`, `pin` and `x` in the header
            settings.toolTip = "settings"
            settingsButton = settings
            row.append(settings)
        }
        if let pin { pinButton = pin; row.append(pin) }
        if let onClose {
            let close = AIMShellButton("\u{00D7}", width: AIMAppShellStyle.controlHeight, action: onClose)
            close.identifier = NSUserInterfaceItemIdentifier("close-panel")
            close.toolTip = "close \u{00B7} esc"
            close.setAccessibilityLabel("close panel")
            closeButton = close
            row.append(close)
        }

        let stack = NSStackView(views: row)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = AIMAppShellStyle.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: AIMAppShellStyle.markSize),
        ])
    }
    public required init?(coder: NSCoder) { fatalError("AIMAppHeader is built in code") }

    /// The identifiers on the right edge, in order. A testbed pass reads this to check rule 32.
    public var trailingIdentifiers: [String] {
        [settingsButton, pinButton, closeButton].compactMap { $0?.identifier?.rawValue }
    }
    public func setStatus(_ text: String) { statusLabel?.stringValue = text }
    public func setVersion(_ text: String) { versionLabel?.stringValue = text }
}

// MARK: - Tab strip

/// Rules 32, 37: views only, one red underline on the active tab, digit keys 1...N in the printed order.
public final class AIMTabStrip: NSView {
    public struct Tab {
        public let id: String
        public let title: String
        public init(id: String, title: String) { self.id = id; self.title = title }
    }
    public private(set) var tabs: [Tab]
    public private(set) var selected: String
    /// Called with the tab id after a click or a digit key.
    public var onSelect: ((String) -> Void)?
    private var buttons: [String: AIMShellButton] = [:]

    public init(tabs: [Tab], selected: String? = nil, width: CGFloat, tabWidth: CGFloat = 80, onSelect: ((String) -> Void)? = nil) {
        self.tabs = tabs
        self.selected = selected ?? tabs.first?.id ?? ""
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("views")

        var row: [NSView] = []
        for (index, tab) in tabs.enumerated() {
            let button = AIMShellButton(tab.title, width: tabWidth, height: 30)
            button.kind = .navigation
            button.identifier = NSUserInterfaceItemIdentifier(tab.id)
            button.toolTip = "key \(index + 1)"
            button.target = self
            button.action = #selector(pick(_:))
            button.isActive = tab.id == self.selected
            buttons[tab.id] = button
            row.append(button)
        }
        row.append(AIMAppShellStyle.spacer())
        let stack = NSStackView(views: row)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }
    public required init?(coder: NSCoder) { fatalError("AIMTabStrip is built in code") }

    @objc private func pick(_ sender: AIMShellButton) {
        guard let id = sender.identifier?.rawValue else { return }
        select(id)
        onSelect?(id)
    }

    /// Host-side change: moves the underline without calling back.
    public func select(_ id: String) {
        guard buttons[id] != nil else { return }
        selected = id
        for (key, button) in buttons { button.isActive = key == id }
    }

    /// The digit key of a tab, 1...N in the printed order; `nil` when the key belongs to no tab.
    public func id(forKey digit: Int) -> String? {
        guard digit >= 1, digit <= tabs.count else { return nil }
        return tabs[digit - 1].id
    }
    /// The key map for the footer line: `1 today \u{00B7} 2 week`.
    public var keyMap: String {
        tabs.enumerated().map { "\($0.offset + 1) \($0.element.title)" }.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Footer

/// Rule 22: one structure everywhere, three parts on one row, 11 pt muted. Left = the key map, centre = the
/// way out, right = version and status. A product passes text; nothing here is a control.
public final class AIMFooterLine: NSView {
    public let keysLabel: NSTextField
    public let escLabel: NSTextField
    public let statusLabel: NSTextField
    /// Extra controls (`apps \u{2197}`, `detach \u{2197}`, `float`) sit between the centre and the status.
    public private(set) var extras: [NSView]

    public init(keys: String, esc: String = "esc close", status: String, width: CGFloat, extras: [NSView] = []) {
        keysLabel = AIMAppShellStyle.label(keys, size: AIMAppShellStyle.footerSize, weight: .medium, color: AIMAppShellStyle.muted)
        escLabel = AIMAppShellStyle.label(esc, size: AIMAppShellStyle.footerSize, weight: .medium, color: AIMAppShellStyle.muted)
        statusLabel = AIMAppShellStyle.label(status, size: AIMAppShellStyle.footerSize, weight: .medium, color: AIMAppShellStyle.muted)
        self.extras = extras
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: AIMAppShellStyle.quietHeight))
        translatesAutoresizingMaskIntoConstraints = false
        escLabel.identifier = NSUserInterfaceItemIdentifier("hint-esc")
        // The right column gives way first: a long status truncates, the centre never shrinks to zero.
        escLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        keysLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        statusLabel.alignment = .right
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("hints")

        let stack = NSStackView(views: [keysLabel, escLabel, AIMAppShellStyle.spacer()] + extras + [statusLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = AIMAppShellStyle.inset
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: AIMAppShellStyle.quietHeight),
        ])
    }
    public required init?(coder: NSCoder) { fatalError("AIMFooterLine is built in code") }

    public func setKeys(_ text: String) { keysLabel.stringValue = text }
    public func setStatus(_ text: String) { statusLabel.stringValue = text }
}

/// The name the contract uses for the same component.
public typealias AIMHintLine = AIMFooterLine

// MARK: - Surface

/// Rules 28, 29, 33: one appearance read from the tokens, one read-only outside-click monitor, one close.
/// The host owns the popover or the window and hands it over; the surface owns show, monitor and close.
public final class AIMSurface {
    public enum Host {
        case popover(NSPopover)
        case window(NSWindow)
    }
    /// Where the close came from. It travels into the receipt and changes nothing else (rule 33).
    public enum CloseReason: String {
        case escape, commandW = "command-w", closeButton = "close-button", menuBarItem = "menu-bar-item"
        case hotkey, route, outsideClick = "outside-click", host
    }

    public let host: Host
    public private(set) var isShown = false
    /// Rule 29: off by default. Setting it re-arms the monitor.
    public var pinned: Bool { didSet { updateMonitor() } }
    public var onShow: (() -> Void)?
    /// Called once per close with the reason, after the surface has left.
    public var onClose: ((CloseReason) -> Void)?
    private var monitor: Any?

    public init(host: Host, pinned: Bool = AIMPinPolicy.pinDefault) {
        self.host = host
        self.pinned = pinned
    }
    deinit { removeMonitor() }

    /// The appear duration of this surface kind (rule 28); 0 under Reduce Motion.
    public var appearDuration: TimeInterval {
        switch host {
        case .popover: return AIMAppShellStyle.panelAppear
        case .window: return AIMAppShellStyle.windowAppear
        }
    }

    /// Shows the surface with the content already laid out. A popover takes the system transition, a window
    /// fades alpha 0 to 1 with a 6 pt rise. Repeating `show` on a surface already shown is a no-op.
    /// `anchor` and `edge` are the popover arguments and are ignored by a window.
    public func show(relativeTo rect: NSRect = .zero, of anchor: NSView? = nil, preferredEdge edge: NSRectEdge = .minY) {
        guard !isShown else { return }
        switch host {
        case let .popover(popover):
            guard let anchor else { return }
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
            popover.animates = appearDuration > 0
            popover.show(relativeTo: rect == .zero ? anchor.bounds : rect, of: anchor, preferredEdge: edge)
        case let .window(window):
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let duration = appearDuration
            let shift = AIMAppShellStyle.windowAppearShift
            let target = window.frame
            if duration > 0 {
                window.alphaValue = 0
                window.setFrame(target.offsetBy(dx: 0, dy: -shift), display: false)
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 1
                    window.animator().setFrame(target, display: true)
                }
            } else {
                window.alphaValue = 1
                window.orderFrontRegardless()
            }
        }
        isShown = true
        updateMonitor()
        onShow?()
    }

    /// The single way out (rule 33). Every entrance calls this, the reason only travels into the receipt.
    public func close(reason: CloseReason) {
        guard isShown else { return }
        isShown = false
        removeMonitor()
        switch host {
        case let .popover(popover): popover.performClose(nil)
        case let .window(window): window.orderOut(nil)
        }
        onClose?(reason)
    }

    /// Maps a key event to its close reason: Escape and Command-W, nothing else (rule 37).
    /// Returns `nil` when the event is not a close, so the host keeps handling it.
    public func closeReason(for event: NSEvent) -> CloseReason? {
        if event.keyCode == 53 { return .escape }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "w" { return .commandW }
        return nil
    }

    // MARK: outside click (rule 29)

    /// The monitor exists only while it can act: shown and unpinned. It reads the fact of a mouse down in
    /// another process; nothing is sent, consumed or replayed, and the cursor is never moved.
    private func updateMonitor() {
        guard AIMPinPolicy.closesOnOutsideClick(pinned: pinned, shown: isShown) else { removeMonitor(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close(reason: .outsideClick)
        }
    }
    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
