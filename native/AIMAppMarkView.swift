// AIMAppMarkView · N1 · v1 · the one painter of the product mark (AIM apps rule 39). Hand-written once, vendored byte for byte.
// Pairs with AIMAppMarks.swift (generated from aim-app-marks.svg) and AIMMiniAppTokens.swift (generated). AppKit only.
// Rule 39: the menu bar icon and the mark in the product header are the same drawing from the same source.
// `image(_:size:mono:)` is both of them: `mono: true` gives an 18 pt template image (square and glyph only,
// a template carries no colour, so the red signal is left out); `mono: false` keeps the red signal and is what
// `AIMAppMarkView` draws at 40 pt in the header. The voxel character stays an illustration inside the surface.
// Geometry comes from the svg untouched: 2 pt stroke, butt caps, miter join with the svg limit of 4.
// `NSColor(aimHex:)` lives in AIMVoxelView.swift; the two files ship together in every product.
import AppKit

public final class AIMAppMarkView: NSView {
    // MARK: sizes (rules 9, 26, 39)
    /// Header mark, one size for every product.
    public static let headerSize: CGFloat = 40
    /// Menu bar template image.
    public static let menuBarSize: CGFloat = 18

    // MARK: palette · resolved from the generated tokens
    private static func component(_ key: String, _ fallback: String) -> String { AIMMiniAppTokens.N1.component[key] ?? fallback }
    public static let ink = NSColor(aimHex: component("logo-ink", "#202124"))
    public static let signal = NSColor(aimHex: component("logo-signal", "#db303d"))

    // MARK: state
    public private(set) var mark: AIMAppMark
    /// Optional consequence of a click (rule 38): set it and the mark becomes a control, keyboard reachable
    /// with Enter and Space and drawn with a focus ring. Left `nil` the mark is a picture and takes no focus.
    public var onClick: (() -> Void)? { didSet { needsDisplay = true } }
    private let size: CGFloat

    public init(mark: AIMAppMark, size: CGFloat = AIMAppMarkView.headerSize) {
        self.mark = mark
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(mark.label)
    }
    public required init?(coder: NSCoder) { fatalError("AIMAppMarkView is built in code") }

    public func setMark(_ mark: AIMAppMark) {
        self.mark = mark
        setAccessibilityLabel(mark.label)
        needsDisplay = true
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }
    public override var acceptsFirstResponder: Bool { onClick != nil }
    public override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    public override func resetCursorRects() { if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) } }

    public override func mouseDown(with event: NSEvent) {
        guard let onClick else { super.mouseDown(with: event); return }
        onClick()
    }
    public override func keyDown(with event: NSEvent) {
        guard let onClick, event.charactersIgnoringModifiers == " " || event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event); return
        }
        onClick()
    }

    public override func draw(_ dirtyRect: NSRect) {
        AIMAppMarkView.draw(mark, in: bounds, mono: false)
        if onClick != nil, window?.firstResponder === self {
            AIMAppMarkView.ink.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    // MARK: painter

    /// The mark as an image. `mono` gives a template image for the menu bar: square and glyph only, the tint
    /// is the bar's. `mono: false` keeps the red signal and is the header drawing.
    public static func image(_ mark: AIMAppMark, size: CGFloat, mono: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(mark, in: rect, mono: mono)
            return true
        }
        img.isTemplate = mono
        img.accessibilityDescription = mark.label
        return img
    }

    /// Draws into a flipped context: square and glyph stroked, then the signal filled unless `mono`.
    public static func draw(_ mark: AIMAppMark, in rect: NSRect, mono: Bool) {
        let scale = min(rect.width, rect.height) / AIMAppMark.canvas
        let origin = NSPoint(x: rect.minX + (rect.width - AIMAppMark.canvas * scale) / 2,
                             y: rect.minY + (rect.height - AIMAppMark.canvas * scale) / 2)
        let stroke = AIMAppMark.strokeWidth * scale
        (mono ? NSColor.black : ink).setStroke()
        for commands in [mark.square, mark.glyph] {
            let path = bezier(commands, scale: scale, origin: origin)
            path.lineWidth = stroke
            path.lineCapStyle = .butt
            path.lineJoinStyle = .miter
            path.miterLimit = 4            // the svg default; without it the family chevron grows a spike
            path.stroke()
        }
        guard !mono else { return }
        signal.setFill()
        bezier(mark.signal, scale: scale, origin: origin).fill()
    }

    /// Path commands to a bezier path in view space.
    public static func bezier(_ commands: [AIMAppMarkCommand], scale: CGFloat, origin: NSPoint = .zero) -> NSBezierPath {
        let path = NSBezierPath()
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        for command in commands {
            switch command {
            case let .move(x, y): path.move(to: point(x, y))
            case let .line(x, y): path.line(to: point(x, y))
            case let .curve(c1x, c1y, c2x, c2y, x, y):
                path.curve(to: point(x, y), controlPoint1: point(c1x, c1y), controlPoint2: point(c2x, c2y))
            case .close: path.close()
            }
        }
        return path
    }
}
