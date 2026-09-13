// AIMVoxelView · N1 · live product mark for native AIM mini apps. Hand-written once, vendored byte for byte.
// Pairs with AIMVoxelModels.swift (generated) and AIMMiniAppTokens.swift (generated). AppKit only, no renderer.
// Projection as mem-prism VoxelView.swift and aim-voxel.js: screen = (ox + (x − y)·u, oy + (x + y)·0.48·u − z·u).
// Cube = three faces (top, left y+1, right x+1), painter order by x + y + z. Motion is finite: one click → scatter
// then assemble, 1.6 s total, 16 ticks per second, only while the window is visible and not occluded.
// Reduce Motion (NSWorkspace.accessibilityDisplayShouldReduceMotion) keeps the final frame; a click then only moves the signal.
import AppKit

public final class AIMVoxelView: NSView {
    // MARK: palette · resolved from AIMMiniAppTokens primitives, hex mapped in this local helper
    private static func token(_ key: String, _ fallback: String) -> NSColor {
        NSColor(aimHex: AIMMiniAppTokens.primitives[key] ?? fallback)
    }
    public static let ink = token("ink", "#202124")
    public static let mid = token("gray600", "#6b6e75")
    public static let white = token("white", "#ffffff")
    public static let divider = token("gray200", "#e8e9ed")
    public static let compact = token("gray100", "#f2f3f5")
    public static let red = token("red", "#db303d")
    /// faces: top · left · right · edge stroke, same values as aim-voxel.js PALETTE
    private static func faces(_ c: AIMVoxelColor) -> (NSColor, NSColor, NSColor, NSColor) {
        switch c {
        case .light: return (white, divider, compact, mid)
        case .mid: return (divider, mid, mid, white)
        case .ink: return (mid, ink, mid, white)
        case .red: return (red, red, red, white)
        }
    }

    // MARK: model and state
    public struct Voxel { public var x: Int; public var y: Int; public var z: Int; public var c: AIMVoxelColor }
    public private(set) var model: AIMVoxelModel
    private var cubes: [Voxel] = []
    /// signal transfer on click for models with one red voxel (calendar: another day). Nil = many signals, no transfer.
    private var signalIndex: Int?
    private var transfers = 0
    public var showsShadow = true { didSet { needsDisplay = true } }
    public var padding: CGFloat = 1 { didSet { needsDisplay = true } }
    /// Called after every click; the host may mirror the gesture (log, about window).
    public var onClick: (() -> Void)?

    private static let sequence: TimeInterval = 1.6      // scatter + assemble, ≤ 2 s
    private static let tick: TimeInterval = 1.0 / 16.0
    private static let parallaxMax: CGFloat = 3          // ± pt by depth (x + y)
    private var timer: Timer?
    private var phase: TimeInterval = -1                  // -1 idle · 0…sequence running
    private var hover: CGFloat = 0                        // −1…1 cursor position across the view, 0 when outside
    private var tracking: NSTrackingArea?

    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: 56, height: 56) }

    public init(model: AIMVoxelModel, frame: NSRect = NSRect(x: 0, y: 0, width: 56, height: 56)) {
        self.model = model
        super.init(frame: frame)
        setModel(model)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(model.label)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(visibilityChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    public required init?(coder: NSCoder) { fatalError("AIMVoxelView is built in code") }
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    public func setModel(_ model: AIMVoxelModel) {
        self.model = model
        cubes = AIMVoxelView.sorted(model.voxels.map { Voxel(x: $0.x, y: $0.y, z: $0.z, c: $0.c) })
        let reds = cubes.indices.filter { cubes[$0].c == .red }
        signalIndex = reds.count == 1 ? reds[0] : nil
        transfers = 0
        setAccessibilityLabel(model.label)
        needsDisplay = true
    }

    /// Dedupe by cell, then painter order: x + y + z, then x + y, then z (same as aim-voxel.js).
    private static func sorted(_ list: [Voxel]) -> [Voxel] {
        var seen = Set<String>(), out: [Voxel] = []
        for v in list where seen.insert("\(v.x),\(v.y),\(v.z)").inserted { out.append(v) }
        return out.sorted { a, b in
            let sa = a.x + a.y + a.z, sb = b.x + b.y + b.z
            if sa != sb { return sa < sb }
            if a.x + a.y != b.x + b.y { return a.x + a.y < b.x + b.y }
            return a.z < b.z
        }
    }

    // MARK: tracking · hover parallax
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    public override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    public override func mouseMoved(with event: NSEvent) {
        guard !AIMVoxelView.reduceMotion, bounds.width > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        hover = max(-1, min(1, (p.x / bounds.width) * 2 - 1))
        needsDisplay = true
    }
    public override func mouseExited(with event: NSEvent) { hover = 0; needsDisplay = true }
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    // MARK: click · scatter → assemble, plus signal transfer
    public override func mouseDown(with event: NSEvent) { trigger() }
    public override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 || event.keyCode == 76 { trigger() }
        else { super.keyDown(with: event) }
    }
    public func trigger() {
        transferSignal()
        if !AIMVoxelView.reduceMotion, phase < 0 { phase = 0; resume() }
        needsDisplay = true
        onClick?()
    }
    /// Moves the single red signal to the nearest cell of the same y layer (same sheet); ties alternate, so repeated
    /// clicks walk between neighbours. Calendar: another day. Relay: the arrow tip. Aside: the cursor row.
    private func transferSignal() {
        guard let i = signalIndex else { return }
        let s = cubes[i]
        var best: [(Int, Int)] = []   // (index, distance)
        for (j, v) in cubes.enumerated() where j != i && v.y == s.y && v.c != .light {
            best.append((j, abs(v.x - s.x) + abs(v.z - s.z)))
        }
        guard let minD = best.map({ $0.1 }).min() else { return }
        let candidates = best.filter { $0.1 == minD }.sorted { cubes[$0.0].x != cubes[$1.0].x ? cubes[$0.0].x < cubes[$1.0].x : cubes[$0.0].z < cubes[$1.0].z }
        let pick = candidates[transfers % candidates.count].0
        transfers += 1
        let previous = cubes[pick].c
        cubes[pick].c = .red
        cubes[i].c = previous == .red ? .ink : previous
        signalIndex = pick
    }

    // MARK: timer · only while visible
    @objc private func visibilityChanged(_ notification: Notification) { resume(); needsDisplay = true }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        window == nil ? pause() : resume()
    }
    private var windowVisible: Bool {
        window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }
    private func resume() {
        pause()
        guard phase >= 0, !AIMVoxelView.reduceMotion, windowVisible, !CommandLine.arguments.contains("--self-test") else {
            if AIMVoxelView.reduceMotion { phase = -1 }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: AIMVoxelView.tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.windowVisible, !AIMVoxelView.reduceMotion else { self.pause(); if AIMVoxelView.reduceMotion { self.phase = -1 }; return }
            self.phase += AIMVoxelView.tick
            if self.phase >= AIMVoxelView.sequence { self.phase = -1; self.pause() }
            self.needsDisplay = true
        }
        timer?.tolerance = AIMVoxelView.tick / 4
    }
    private func pause() { timer?.invalidate(); timer = nil }

    // MARK: geometry
    private static func point(_ x: Double, _ y: Double, _ z: Double, _ u: CGFloat, _ o: NSPoint) -> NSPoint {
        NSPoint(x: o.x + CGFloat(x - y) * u, y: o.y + CGFloat((x + y) * 0.48 - z) * u)
    }
    /// Projected bounds in units (u = 1, origin 0) including shadow tiles at z = 0.
    private static func unitBounds(_ cubes: [Voxel]) -> NSRect {
        guard !cubes.isEmpty else { return NSRect(x: -1, y: -1, width: 2, height: 2) }
        var x0 = CGFloat.greatestFiniteMagnitude, y0 = x0, x1 = -x0, y1 = -x0
        let o = NSPoint.zero
        for v in cubes {
            let x = Double(v.x), y = Double(v.y), z = Double(v.z)
            for p in [point(x, y, z + 1, 1, o), point(x + 1, y, z + 1, 1, o), point(x + 1, y + 1, z + 1, 1, o), point(x, y + 1, z + 1, 1, o),
                      point(x + 1, y + 1, z, 1, o), point(x, y + 1, z, 1, o), point(x + 1, y, z, 1, o),
                      point(x, y, 0, 1, o), point(x + 1, y + 1, 0, 1, o), point(x + 1, y, 0, 1, o), point(x, y + 1, 0, 1, o)] {
                x0 = min(x0, p.x); x1 = max(x1, p.x); y0 = min(y0, p.y); y1 = max(y1, p.y)
            }
        }
        return NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    /// Deterministic pseudo-random offset per cube, the same sequence as aim-voxel.js rnd(i).
    private static func rnd(_ i: Int) -> CGFloat {
        let t = (i + 1) * 9301 + 49297
        return CGFloat(t % 233280) / 233280 - 0.5
    }

    // MARK: drawing
    public override func draw(_ dirtyRect: NSRect) {
        AIMVoxelView.draw(cubes, in: bounds, pad: padding, shadow: showsShadow, mono: false,
                          hover: hover, phase: phase, sequence: AIMVoxelView.sequence)
    }

    /// Shared drawing for the live view and static images. `phase` < 0 draws the assembled frame.
    private static func draw(_ cubes: [Voxel], in rect: NSRect, pad: CGFloat, shadow: Bool, mono: Bool,
                             hover: CGFloat, phase: TimeInterval, sequence: TimeInterval) {
        let ub = unitBounds(cubes)
        let u = min(rect.width / (ub.width + 2 * pad), rect.height / (ub.height + 2 * pad))
        guard u > 0 else { return }
        let origin = NSPoint(x: rect.midX - (ub.midX) * u, y: rect.midY - (ub.midY) * u)
        let cx = rect.midX, cy = rect.midY
        func face(_ pts: [NSPoint], _ fill: NSColor, _ stroke: NSColor?, _ alpha: CGFloat) {
            let p = NSBezierPath(); p.move(to: pts[0])
            pts.dropFirst().forEach { p.line(to: $0) }; p.close()
            fill.withAlphaComponent(fill.alphaComponent * alpha).setFill(); p.fill()
            if let stroke, u >= 4 {
                p.lineWidth = u * 0.06; p.lineJoinStyle = .round
                stroke.withAlphaComponent(0.35 * alpha).setStroke(); p.stroke()
            }
        }
        if shadow, !mono {
            var columns: [String: Voxel] = [:]
            for v in cubes { columns["\(v.x),\(v.y)"] = v }
            divider.setFill()
            for v in columns.values {
                let x = Double(v.x) + 0.08, y = Double(v.y) + 0.08, e = 0.84
                face([point(x, y, 0, u, origin), point(x + e, y, 0, u, origin), point(x + e, y + e, 0, u, origin), point(x, y + e, 0, u, origin)], divider, nil, 1)
            }
        }
        let depths = cubes.map { $0.x + $0.y }
        let dMin = CGFloat(depths.min() ?? 0), dMax = CGFloat(depths.max() ?? 0)
        let n = max(1, cubes.count)
        let half = sequence / 2
        for (i, v) in cubes.enumerated() {
            let x = Double(v.x), y = Double(v.y), z = Double(v.z)
            // parallax by depth: back cubes move against the cursor, front cubes with it
            var dx: CGFloat = 0, dy: CGFloat = 0, alpha: CGFloat = 1
            if hover != 0, dMax > dMin {
                let d = (CGFloat(v.x + v.y) - dMin) / (dMax - dMin) * 2 - 1
                dx = hover * d * parallaxMax
            }
            if phase >= 0 {
                // progress p: 0 assembled … 1 scattered; scatter half eases in, assemble half eases out
                var p: CGFloat = 0
                if phase < half {
                    let start = Double(n - 1 - i) / Double(n) * half * 0.55, dur = half * 0.45
                    let t = CGFloat(max(0, min(1, (phase - start) / dur)))
                    p = t * t
                } else {
                    let start = half + Double(i) / Double(n) * half * 0.55, dur = half * 0.45
                    let t = CGFloat(max(0, min(1, (phase - start) / dur)))
                    p = 1 - (1 - pow(1 - t, 3))
                }
                if p > 0 {
                    let px = origin.x + CGFloat(x - y) * u, py = origin.y + CGFloat((x + y) * 0.48 - z) * u
                    let tx = (px - cx) * 1.1 + rnd(i) * 6 * u, ty = (py - cy) * 0.9 - 3.5 * u + rnd(i * 7) * 4 * u
                    dx += tx * p; dy += ty * p; alpha = 1 - p
                }
            }
            let o = NSPoint(x: origin.x + dx, y: origin.y + dy)
            let c = faces(v.c)
            let top = [point(x, y, z + 1, u, o), point(x + 1, y, z + 1, u, o), point(x + 1, y + 1, z + 1, u, o), point(x, y + 1, z + 1, u, o)]
            let left = [point(x, y + 1, z + 1, u, o), point(x + 1, y + 1, z + 1, u, o), point(x + 1, y + 1, z, u, o), point(x, y + 1, z, u, o)]
            let right = [point(x + 1, y, z + 1, u, o), point(x + 1, y + 1, z + 1, u, o), point(x + 1, y + 1, z, u, o), point(x + 1, y, z, u, o)]
            if mono {
                // template rendering: one ink, faces by alpha so the form still reads in three planes; light plates stay faint
                let k: CGFloat = v.c == .mid ? 0.7 : v.c == .light ? 0.16 : 1
                face(top, NSColor.black, nil, 0.45 * k); face(left, NSColor.black, nil, 1 * k); face(right, NSColor.black, nil, 0.7 * k)
            } else {
                face(top, c.0, c.3, alpha); face(left, c.1, c.3, alpha); face(right, c.2, c.3, alpha)
            }
        }
    }

    /// Static character for menu bar (`size` 18, `mono` true → template image) and About windows.
    public static func image(model: AIMVoxelModel, size: CGFloat, mono: Bool) -> NSImage {
        let cubes = sorted(model.voxels.map { Voxel(x: $0.x, y: $0.y, z: $0.z, c: $0.c) })
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(cubes, in: rect, pad: mono ? 0 : 0.5, shadow: !mono, mono: mono, hover: 0, phase: -1, sequence: sequence)
            return true
        }
        img.isTemplate = mono
        img.accessibilityDescription = model.label
        return img
    }
}

extension NSColor {
    /// `#rrggbb` or `#rrggbbaa` in sRGB; anything else resolves to ink.
    convenience init(aimHex: String) {
        var s = aimHex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            self.init(srgbRed: 0x20 / 255, green: 0x21 / 255, blue: 0x24 / 255, alpha: 1); return
        }
        let a: CGFloat = s.count == 8 ? CGFloat(v & 0xff) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255, blue: CGFloat(rgb & 0xff) / 255, alpha: a)
    }
}
