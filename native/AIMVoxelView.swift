// AIMVoxelView · N1 · v3 · live product mark for native AIM mini apps. Hand-written once, vendored byte for byte.
// Pairs with AIMVoxelModels.swift (generated: models, gestures, AIMVoxelMotion) and AIMMiniAppTokens.swift (generated). AppKit only.
// Projection as mem-prism VoxelView.swift and aim-voxel.js: screen = (ox + (x − y)·u, oy + (x + y)·0.48·u − z·u).
// Cube = three faces (top, left y+1, right x+1), painter order by x + y + z.
// Motion, the same numbers as the web renderer: appear = assemble 0.7 s in 6–8 depth steps (x + y + z, cubic-out);
// click = scatter 0.25 s → assemble 0.55 s → the character's gesture (flash ≤ 0.6 s, or mirror / cycle applied while scattered);
// hover = 2 pt lift in 0.16 s plus ±2 pt depth parallax. A 1/16 s timer runs only while a run is active and the window is visible.
// The first draw is always the assembled frame; the appear run starts after that draw. Reduce Motion → only the gesture.
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
    /// The cubes as currently shown (after gestures); read-only for hosts and tests.
    public var currentVoxels: [Voxel] { cubes }
    /// Fallback for models without a gesture: one red voxel steps between neighbours of the same y layer.
    private var signalIndex: Int?
    private var transfers = 0
    private var cycleIndex = 0
    private var cycleBase: [String: AIMVoxelColor] = [:]
    private var flashBackup: [(Int, AIMVoxelColor)] = []
    public var showsShadow = true { didSet { needsDisplay = true } }
    public var padding: CGFloat = 1 { didSet { needsDisplay = true } }
    /// Called after every click; the host may mirror the gesture (log, about window).
    public var onClick: (() -> Void)?
    /// Assemble the character once when the view first appears in a visible window (0.7 s). Off → static first frame only.
    public var assemblesOnAppear = true

    private static let tick: TimeInterval = 1.0 / 16.0
    private static let parallaxMax: CGFloat = 2          // ± pt by depth (x + y)
    private var timer: Timer?
    /// -1 idle · otherwise seconds into the current run
    private var phase: TimeInterval = -1
    private enum Run { case appear, click }
    private var run: Run = .click
    private var gestureApplied = false
    private var flashUntil: TimeInterval = -1
    private var appearPending = false
    private var hover: CGFloat = 0                        // −1…1 cursor position across the view, 0 when outside
    private var lift: CGFloat = 0                         // 0…1 hover lift progress
    private var liftTarget: CGFloat = 0
    private var tracking: NSTrackingArea?

    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static var selfTest: Bool { CommandLine.arguments.contains("--self-test") }
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
        transfers = 0; cycleIndex = 0; cycleBase = [:]; flashBackup = []
        phase = -1; flashUntil = -1; pause()
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

    // MARK: tracking · hover lift + parallax
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    public override func mouseEntered(with event: NSEvent) { liftTarget = 1; mouseMoved(with: event); resume() }
    public override func mouseMoved(with event: NSEvent) {
        guard !AIMVoxelView.reduceMotion, bounds.width > 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        hover = max(-1, min(1, (p.x / bounds.width) * 2 - 1))
        needsDisplay = true
    }
    public override func mouseExited(with event: NSEvent) { hover = 0; liftTarget = 0; needsDisplay = true; resume() }
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    // MARK: click · scatter → assemble → gesture
    public override func mouseDown(with event: NSEvent) { trigger() }
    public override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 || event.keyCode == 76 { trigger() }
        else { super.keyDown(with: event) }
    }
    /// One click: with motion and a visible window the run is scatter 0.25 s → assemble 0.55 s → gesture;
    /// otherwise (Reduce Motion, no window, self-test) the gesture alone, applied at once.
    public func trigger() {
        guard phase < 0 else { return }
        if !AIMVoxelView.reduceMotion, windowVisible, !AIMVoxelView.selfTest {
            run = .click; gestureApplied = false; flashUntil = -1; restoreFlash(); phase = 0; resume()
        } else {
            gesture()
        }
        needsDisplay = true
        onClick?()
    }
    /// The character's gesture without the scatter: mirror / cycle change the cubes and stay, flash holds for its time and returns.
    public func gesture() {
        applyStateGesture()
        startFlash()
        needsDisplay = true
    }
    private func cellIndex(_ c: (x: Int, y: Int, z: Int)) -> Int? {
        cubes.firstIndex { $0.x == c.x && $0.y == c.y && $0.z == c.z }
    }
    /// mirror and cycle (state gestures); models without a gesture fall back to the single-signal step.
    private func applyStateGesture() {
        guard let g = model.gesture else { transferSignal(); return }
        switch g {
        case .mirror(let axis):
            let values = cubes.map { axis == "x" ? $0.x : axis == "y" ? $0.y : $0.z }
            guard let lo = values.min(), let hi = values.max() else { return }
            for i in cubes.indices {
                switch axis {
                case "x": cubes[i].x = lo + hi - cubes[i].x
                case "y": cubes[i].y = lo + hi - cubes[i].y
                default: cubes[i].z = lo + hi - cubes[i].z
                }
            }
            cubes = AIMVoxelView.sorted(cubes)
        case .cycle(let cells, let color):
            guard cells.count > 1 else { return }
            if cycleBase.isEmpty {
                let fallback = cells.compactMap { cellIndex($0) }.map { cubes[$0].c }.first { $0 != color } ?? .mid
                for c in cells {
                    let base = cellIndex(c).map { cubes[$0].c } ?? fallback
                    cycleBase["\(c.x),\(c.y),\(c.z)"] = base == color ? fallback : base
                }
            }
            let next = (cycleIndex + 1) % cells.count
            let cur = cells[cycleIndex]
            if let i = cellIndex(cur) { cubes[i].c = cycleBase["\(cur.x),\(cur.y),\(cur.z)"] ?? .mid }
            if let j = cellIndex(cells[next]) { cubes[j].c = color }
            cycleIndex = next
        case .flash: break
        }
    }
    private var flashHold: TimeInterval? {
        if case .flash(_, _, let hold)? = model.gesture { return min(0.6, max(0.04, hold)) }
        return nil
    }
    /// flash: the listed cells take the colour for `hold` seconds; restored by the timer, or by a one-shot when no timer runs.
    private func startFlash() {
        guard case .flash(let cells, let color, _)? = model.gesture, let hold = flashHold else { return }
        restoreFlash()
        for c in cells { if let i = cellIndex(c) { flashBackup.append((i, cubes[i].c)); cubes[i].c = color } }
        needsDisplay = true
        if phase >= 0 { return } // the click run ends the flash on its own clock
        if AIMVoxelView.selfTest { return } // tests inspect the flashed state
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in self?.restoreFlash(); self?.needsDisplay = true }
    }
    private func restoreFlash() {
        for (i, c) in flashBackup where i < cubes.count { cubes[i].c = c }
        flashBackup = []
    }
    /// Fallback for models without a gesture: the single red signal steps to the nearest cell of the same y layer.
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

    // MARK: timer · only while a run is active and the window is visible
    @objc private func visibilityChanged(_ notification: Notification) { resume(); needsDisplay = true }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged(_:)),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
            // the assembled frame draws first; the appear run starts from inside draw(_:) after that frame
            appearPending = assemblesOnAppear && !AIMVoxelView.reduceMotion && !AIMVoxelView.selfTest
            needsDisplay = true
        } else {
            appearPending = false
        }
        window == nil ? pause() : resume()
    }
    private var windowVisible: Bool {
        window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }
    private var needsTimer: Bool { phase >= 0 || lift != liftTarget }
    private func resume() {
        pause()
        if AIMVoxelView.reduceMotion { if phase >= 0 { phase = -1; restoreFlash() }; lift = 0; liftTarget = 0; return }
        guard needsTimer, windowVisible, !AIMVoxelView.selfTest else { return }
        timer = Timer.scheduledTimer(withTimeInterval: AIMVoxelView.tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.windowVisible, !AIMVoxelView.reduceMotion else { self.pause(); if AIMVoxelView.reduceMotion { self.phase = -1; self.restoreFlash() }; return }
            self.step(AIMVoxelView.tick)
            self.needsDisplay = true
            if !self.needsTimer { self.pause() }
        }
        timer?.tolerance = AIMVoxelView.tick / 4
    }
    private func pause() { timer?.invalidate(); timer = nil }
    /// One timer tick: hover lift, then the current run's clock.
    private func step(_ dt: TimeInterval) {
        if lift != liftTarget {
            let d = CGFloat(dt / AIMVoxelMotion.hover)
            lift = liftTarget > lift ? min(liftTarget, lift + d) : max(liftTarget, lift - d)
        }
        guard phase >= 0 else { return }
        phase += dt
        switch run {
        case .appear:
            if phase >= AIMVoxelMotion.assemble { phase = -1 }
        case .click:
            let scatterEnd = AIMVoxelMotion.scatter, assembleEnd = scatterEnd + AIMVoxelMotion.reassemble
            if phase >= scatterEnd, !gestureApplied { gestureApplied = true; applyStateGesture() }
            if phase >= assembleEnd, flashUntil < 0 {
                if let hold = flashHold { startFlash(); flashUntil = assembleEnd + hold } else { phase = -1 }
            }
            if flashUntil >= 0, phase >= flashUntil { restoreFlash(); flashUntil = -1; phase = -1 }
        }
    }

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
    /// Depth band 0…1 per cube: 6–8 steps over x + y + z, as aim-voxel.js stepOf.
    private static func bands(_ cubes: [Voxel]) -> [CGFloat] {
        let depths = cubes.map { $0.x + $0.y + $0.z }
        guard let lo = depths.min(), let hi = depths.max() else { return [] }
        let range = hi - lo + 1, steps = max(AIMVoxelMotion.steps.min, min(AIMVoxelMotion.steps.max, range))
        return depths.map { CGFloat(Int(Double($0 - lo) / Double(range) * Double(steps))) / CGFloat(steps - 1) }
    }
    private static func cubicOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
    private static func cubicIn(_ t: CGFloat) -> CGFloat { t * t * t }
    /// Scatter progress 0 (assembled) … 1 (scattered) for one cube at `phase` of the current run.
    private func scatterProgress(band: CGFloat) -> CGFloat {
        guard phase >= 0 else { return 0 }
        switch run {
        case .appear:
            return 1 - AIMVoxelView.assembleProgress(phase, total: AIMVoxelMotion.assemble, band: band)
        case .click:
            let s = AIMVoxelMotion.scatter
            if phase < s {
                // scatter: piece 60 %, spread 40 %, front bands first (1 − band), ease-in
                let piece = s * 0.6, start = (1 - band) * (s - piece)
                let t = CGFloat(max(0, min(1, (phase - start) / piece)))
                return AIMVoxelView.cubicIn(t)
            }
            return 1 - AIMVoxelView.assembleProgress(phase - s, total: AIMVoxelMotion.reassemble, band: band)
        }
    }
    /// Assemble progress 0…1: piece 43 % of the run, bands spread over the remaining 57 %, cubic-out.
    private static func assembleProgress(_ t: TimeInterval, total: TimeInterval, band: CGFloat) -> CGFloat {
        let piece = total * 0.43, start = TimeInterval(band) * (total - piece)
        let k = CGFloat(max(0, min(1, (t - start) / piece)))
        return cubicOut(k)
    }

    // MARK: drawing
    public override func draw(_ dirtyRect: NSRect) {
        let bands = AIMVoxelView.bands(cubes)
        let progress = cubes.indices.map { scatterProgress(band: bands[$0]) }
        AIMVoxelView.draw(cubes, in: bounds, pad: padding, shadow: showsShadow, mono: false,
                          hover: hover, lift: lift, progress: progress)
        if appearPending {
            appearPending = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.phase < 0, self.windowVisible, !AIMVoxelView.reduceMotion else { return }
                self.run = .appear; self.phase = 0; self.resume(); self.needsDisplay = true
            }
        }
    }

    /// Shared drawing for the live view and static images. `progress` per cube: 0 assembled … 1 scattered (empty = assembled).
    private static func draw(_ cubes: [Voxel], in rect: NSRect, pad: CGFloat, shadow: Bool, mono: Bool,
                             hover: CGFloat, lift: CGFloat, progress: [CGFloat]) {
        let ub = unitBounds(cubes)
        let u = min(rect.width / (ub.width + 2 * pad), rect.height / (ub.height + 2 * pad))
        guard u > 0 else { return }
        let liftPt = CGFloat(AIMVoxelMotion.hoverLift) * cubicOut(lift)
        let origin = NSPoint(x: rect.midX - (ub.midX) * u, y: rect.midY - (ub.midY) * u - liftPt)
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
            let ground = NSPoint(x: origin.x, y: origin.y + liftPt)
            for v in columns.values {
                let x = Double(v.x) + 0.08, y = Double(v.y) + 0.08, e = 0.84
                face([point(x, y, 0, u, ground), point(x + e, y, 0, u, ground), point(x + e, y + e, 0, u, ground), point(x, y + e, 0, u, ground)], divider, nil, 1)
            }
        }
        let depths = cubes.map { $0.x + $0.y }
        let dMin = CGFloat(depths.min() ?? 0), dMax = CGFloat(depths.max() ?? 0)
        for (i, v) in cubes.enumerated() {
            let x = Double(v.x), y = Double(v.y), z = Double(v.z)
            // parallax by depth: back cubes move against the cursor, front cubes with it
            var dx: CGFloat = 0, dy: CGFloat = 0, alpha: CGFloat = 1
            if hover != 0, dMax > dMin {
                let d = (CGFloat(v.x + v.y) - dMin) / (dMax - dMin) * 2 - 1
                dx = hover * d * parallaxMax
            }
            let p = i < progress.count ? progress[i] : 0
            if p > 0 {
                let px = origin.x + CGFloat(x - y) * u, py = origin.y + CGFloat((x + y) * 0.48 - z) * u
                let tx = (px - cx) * 1.1 + rnd(i) * 6 * u, ty = (py - cy) * 0.9 - 3.5 * u + rnd(i * 7) * 4 * u
                dx += tx * p; dy += ty * p; alpha = 1 - p
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
            draw(cubes, in: rect, pad: mono ? 0 : 0.5, shadow: !mono, mono: mono, hover: 0, lift: 0, progress: [])
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
