import AppKit
import Foundation

// MARK: - ShaperKit v1.0
// Shared design-system for Shaper-aesthetic native macOS menu-bar apps.
// Compiled together with each app's own .swift via swiftc multi-file.
// All types are internal — visible across both source files in the same build.
// CANONICAL VALUES from MEM PRISM (polished 2026-06).

// MARK: - Color helper

extension NSColor {
    /// Convenience init from a CSS hex string ("#1a1b1f" or "1a1b1f").
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255
        let b = CGFloat( rgb        & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - ThemeMode

enum ThemeMode: String {
    case dark, light
}

// MARK: - Theme

struct Theme {
    let bg:       NSColor
    let ink:      NSColor
    let muted:    NSColor
    let soft:     NSColor
    let hair:     NSColor
    let fill:     NSColor
    let red:      NSColor
    let redBright: NSColor
    let amber:    NSColor

    /// Near-black background, warm off-white ink. Canonical dark preset.
    static let dark = Theme(
        bg:        NSColor(hex: "#1a1b1f"),
        ink:       NSColor(hex: "#e8e6e2"),
        muted:     NSColor(hex: "#9a958d"),
        soft:      NSColor(hex: "#3a3a40"),
        hair:      NSColor(hex: "#26262a"),
        fill:      NSColor(hex: "#202127"),
        red:       NSColor(hex: "#c84545"),
        redBright: NSColor(hex: "#ff6b6b"),
        amber:     NSColor(hex: "#c7a648")
    )

    /// Warm paper bg, warm near-black ink — never pure #fff/#000 (Shaper SSOT).
    /// Mirrors the dark preset's warmth so light mode reads as polished, not harsh:
    /// fill lifts gently off the paper, soft gives gauge tracks/borders real
    /// visibility, muted clears 4.5:1 on the paper bg for legible captions.
    static let light = Theme(
        bg:        NSColor(hex: "#f4f2ec"),
        ink:       NSColor(hex: "#222019"),
        muted:     NSColor(hex: "#6e6a62"),
        soft:      NSColor(hex: "#cdcabf"),
        hair:      NSColor(hex: "#e0ddd4"),
        fill:      NSColor(hex: "#eae7df"),
        red:       NSColor(hex: "#b23b2c"),
        redBright: NSColor(hex: "#cf4636"),
        amber:     NSColor(hex: "#8a6f1c")
    )

    static func named(_ mode: ThemeMode) -> Theme {
        mode == .light ? .light : .dark
    }
}

// MARK: - UI namespace (global token access)

enum UI {
    static var mode:  ThemeMode = .dark
    static var theme: Theme     = .dark

    static func setMode(_ m: ThemeMode) {
        mode  = m
        theme = Theme.named(m)
    }

    static var bg:       NSColor { theme.bg }
    static var ink:      NSColor { theme.ink }
    static var muted:    NSColor { theme.muted }
    static var soft:     NSColor { theme.soft }
    static var hair:     NSColor { theme.hair }
    static var fill:     NSColor { theme.fill }
    static var red:      NSColor { theme.red }
    static var redBright: NSColor { theme.redBright }
    static var amber:    NSColor { theme.amber }

    /// Canonical corner radius for cards / panels / boxes / tiles (px).
    /// A gentle softening so container surfaces don't read as hard square
    /// blocks, while staying restrained Shaper — not bubbly. Matches
    /// ShaperButton. Dense grid cells, ticks, swatches and pill bars keep
    /// their own (square or full-pill) radius — only standalone container
    /// surfaces adopt this.
    static let radius: CGFloat = 7

    /// True when the user has enabled System Settings → Accessibility → Display →
    /// "Reduce motion". Shaper transitions substitute a plain cross-dissolve for
    /// directional slides when this is on (Apple HIG — replace movement with a
    /// fade, don't strip all feedback). Read live (not cached) so a mid-session
    /// toggle takes effect on the very next transition.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// JetBrains Mono with monospaced-system-font fallback.
    /// weight: .regular or .semibold (semibold also handles .medium).
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let names: [String]
        if weight == .semibold || weight == .medium {
            names = ["JetBrainsMono-SemiBold", "JetBrains Mono SemiBold", "JetBrains Mono"]
        } else {
            names = ["JetBrainsMono-Regular", "JetBrains Mono", "JetBrainsMonoNL-Regular"]
        }
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - ShaperButton

/// Shaper-aesthetic button: lowercase label, 1px border, rounded corners.
/// Hover = full ink inversion (bg → ink background, ink → bg text).
/// Active state = same ink-inversion as hover (inverted = selected).
final class ShaperButton: NSButton {
    var isActive = false { didSet { applyState() } }
    var representedObject: Any?
    private var labelText: String
    private var hovering = false { didSet { applyState() } }

    init(_ title: String, target: AnyObject?, action: Selector?, width: CGFloat, height: CGFloat = 28) {
        self.labelText = title.lowercased()
        super.init(frame: .zero)
        self.title = ""
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.focusRingType = .none
        self.wantsLayer = true
        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalToConstant: width).isActive = true
        self.heightAnchor.constraint(equalToConstant: height).isActive = true
        self.layer?.borderWidth = 1
        self.layer?.cornerRadius = UI.radius
        // VoiceOver name. The visible title is custom-drawn in `draw` and
        // `self.title` is left empty, so without this the canonical button
        // (every tab/action/toggle/cleanup/mode control across all three apps)
        // exposes no accessible name — screen readers announce a bare "button".
        // Mirror the lowercase display label; kept in sync in setLabel.
        self.setAccessibilityLabel(labelText)
        applyState()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLabel(_ t: String) {
        labelText = t.lowercased()
        setAccessibilityLabel(labelText)
        needsDisplay = true
    }

    /// VoiceOver selected-state. The label (0f48d01) gives the canonical button an
    /// accessible NAME, but its visually-obvious active state — the ink-inverted
    /// tab/mode button (`isActive`) that a sighted user reads at a glance — stayed
    /// invisible to a screen reader: every tab announced identically whether or not
    /// it was the current one. Expose `isActive` as AXSelected so VoiceOver appends
    /// "selected" to the active tab/mode, completing the name+state contract begun
    /// by the label. A pure read-through (no stored state, no paint change); queried
    /// at focus time like the label. Momentary action buttons keep `isActive == false`
    /// → never report selected, so the signal stays meaningful (tabs/toggles only).
    override func isAccessibilitySelected() -> Bool { isActive }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent)  { hovering = false }

    /// Tactile press feedback. The canonical clickable element gave zero visual
    /// response on click: the custom `draw` only reads isEnabled/isActive/hovering
    /// and ignores the pressed/highlighted cell state, so a hovered button (the
    /// common case — the cursor is already on it) looked identical before, during
    /// and after a click. Dip the whole layer to 0.7 opacity while the mouse is
    /// held, springing back on release — a restrained B&W "push" cue, no colour or
    /// geometry change (so no Reduce-Motion concern). `super.mouseDown` runs
    /// NSControl's tracking loop synchronously, returning on mouse-up, so the dip
    /// shows for the press duration and the action still fires / cancels via the
    /// button's own handling. Disabled buttons stay inert (no dip).
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { super.mouseDown(with: event); return }
        layer?.opacity = 0.7
        super.mouseDown(with: event)
        layer?.opacity = 1.0
    }

    /// Keyboard twin of the mouseDown press-dip. The focus-ring work made every
    /// ShaperButton a first-class keyboard target (Full Keyboard Access → Tab to
    /// focus, paint a hairline ring), but activating with Space/Return fires the
    /// action through `performClick(_:)` — NOT `mouseDown` — so the keyboard path
    /// got zero press feedback while the mouse path dipped to 0.7. AppKit calls
    /// `performClick` when the focused button is activated by the space bar, so
    /// overriding it (the activation method, not a key handler — it can't swallow
    /// the key) is the deterministic, double-fire-proof hook: `super.performClick`
    /// remains the SOLE action dispatch. Dip to 0.7, then restore after a brief
    /// fixed interval so the cue is visible even though `performClick` returns
    /// promptly (unlike `mouseDown`, which blocks for the whole press). The async
    /// restore captures `layer` directly (not self) — harmless if the view is gone.
    override func performClick(_ sender: Any?) {
        guard isEnabled, let layer = layer else { super.performClick(sender); return }
        layer.opacity = 0.7
        super.performClick(sender)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { layer.opacity = 1.0 }
    }

    override func resetCursorRects() {
        if isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    /// Keep the cursor affordance + paint in sync with enablement. `resetCursorRects`
    /// guards the pointing-hand on `isEnabled` and `draw`/`applyState` colour by it,
    /// but AppKit does NOT re-evaluate cursor rects (nor call applyState) when
    /// isEnabled flips. So a cleanup button disabled mid-run while the cursor sits on
    /// it — the common case, the user just clicked it — kept its stale pointing-hand
    /// over a now-inert control (silently defeating the c913143 guard), and an active
    /// button disabled kept its ink layer. Refresh both on every enablement change,
    /// guarded so there's zero cost on the default path (enablement rarely flips).
    override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            let changed = newValue != super.isEnabled
            super.isEnabled = newValue
            if changed {
                window?.invalidateCursorRects(for: self)
                applyState()
            }
        }
    }

    /// Keyboard-focus redraw. `focusRingType = .none` suppresses the native blue
    /// focus ring (it would violate the strict B&W aesthetic), but the VoiceOver
    /// work made these buttons first-class accessible/keyboard targets — so under
    /// Full Keyboard Access a sighted keyboard-only user tabbing through had no
    /// idea which button was focused. `draw` now paints a Shaper hairline focus
    /// indicator; these overrides trigger the repaint when focus enters/leaves.
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { needsDisplay = true }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { needsDisplay = true }
        return ok
    }

    private func applyState() {
        layer?.borderColor = (isActive ? UI.ink : UI.hair).cgColor
        if !isEnabled {
            layer?.backgroundColor = UI.fill.cgColor
        } else if isActive || hovering {
            layer?.backgroundColor = UI.ink.cgColor
        } else {
            layer?.backgroundColor = UI.fill.cgColor
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color: NSColor = !isEnabled ? UI.muted : (isActive || hovering ? UI.bg : UI.ink)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            UI.mono(11, weight: .semibold),
            .foregroundColor: color,
            .kern:            0.25 as Any,
        ]
        let text = NSAttributedString(string: labelText, attributes: attrs)
        let sz   = text.size()
        text.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                              y: (bounds.height - sz.height) / 2 - 1))
        // Keyboard-focus indicator (Full Keyboard Access). Native ring is
        // suppressed (focusRingType=.none) for the B&W aesthetic, so paint a
        // restrained 1px inset hairline in the same colour as the label — visible
        // on the resting fill (ink) and on the inverted hover/active bg (bg). Only
        // when this button is the key window's first responder, i.e. keyboard nav;
        // a normal mouse click doesn't make NSButton first responder, so mouse
        // users never see it → zero change on the default path.
        if isEnabled, let win = window, win.isKeyWindow, win.firstResponder === self {
            let inset: CGFloat = 2.5
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                    xRadius: max(UI.radius - inset, 1),
                                    yRadius: max(UI.radius - inset, 1))
            ring.lineWidth = 1
            color.setStroke()
            ring.stroke()
        }
    }
}

// MARK: - ClosureSleeve (NSMenuItem target helper)

/// Wraps a Swift closure as an @objc action target for NSMenuItem.
final class ClosureSleeve: NSObject {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
    @objc func invoke(_ sender: Any?) { closure() }
}

// MARK: - Layout helpers

/// 1px horizontal rule (NSBox separator).
func hairLine(width: CGFloat) -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.widthAnchor.constraint(equalToConstant: width).isActive = true
    return box
}

/// Flexible horizontal spacer (spring).
func flexSpacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(.defaultLow, for: .horizontal)
    v.translatesAutoresizingMaskIntoConstraints = false
    return v
}

/// Fixed-height blank spacer.
func fixedSpacer(height: CGFloat) -> NSView {
    let v = NSView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.heightAnchor.constraint(equalToConstant: height).isActive = true
    return v
}

/// Section-header label: 9pt semibold muted, full width, uppercase rendered by caller.
func sectionHeader(_ text: String, width: CGFloat) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = UI.mono(9, weight: .semibold)
    l.textColor = UI.muted
    l.lineBreakMode = .byTruncatingTail
    l.maximumNumberOfLines = 1
    l.translatesAutoresizingMaskIntoConstraints = false
    l.widthAnchor.constraint(equalToConstant: width).isActive = true
    return l
}

// MARK: - Tab transition

/// Canonical Shaper tab/panel switch animation — a subtle directional slide
/// (~6px) combined with a crossfade. Call on the content/body container's layer
/// in the same runloop turn you swap the visible panel (BEFORE mutating its
/// sublayers, so the crossfade captures old→new). `forward` sets slide direction
/// (true = new panel enters from the right). 0.18s, ease-in-out — tuned to feel
/// intentional and smooth, not flashy. Identical across all three apps.
///
/// Honors the system "Reduce Motion" setting: when on, the directional slide is
/// dropped and only the cross-dissolve plays (Apple HIG — substitute a fade for
/// movement rather than removing all transition feedback).
func shaperTabTransition(_ layer: CALayer, forward: Bool = true) {
    let timing = CAMediaTimingFunction(name: .easeInEaseOut)

    let fade = CATransition()
    fade.type = .fade
    fade.duration = 0.18
    fade.timingFunction = timing
    layer.add(fade, forKey: "shaperTabFade")

    // Reduce Motion → cross-dissolve only, no directional slide.
    if UI.reduceMotion { return }

    let slide = CABasicAnimation(keyPath: "transform.translation.x")
    slide.fromValue = forward ? 6.0 : -6.0
    slide.toValue = 0.0
    slide.duration = 0.18
    slide.timingFunction = timing
    layer.add(slide, forKey: "shaperTabSlide")
}

// MARK: - Array chunked

/// Split into consecutive slices of `size` (last may be shorter). Shared by the
/// apps' grid builders (e.g. Calendar's 7-day month rows); size ≤ 0 → [self].
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

