import AppKit
import ApplicationServices
import Carbon
import Foundation

private enum AppIdentity {
    static let name = "Language Relay"
    static let bundleID = "dev.alex.layout-pilot"
    /// Fallback pair used when no `sourceLayoutID` / `targetLayoutID` are stored,
    /// or when the stored pair cannot be resolved. Keeps existing installs
    /// unchanged (they never wrote those keys, so they always hit this pair).
    static let defaultSourceID = "com.apple.keylayout.US"
    static let defaultTargetID = "com.apple.keylayout.RussianWin"
    static let hammerspoonBridgeMarker = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/language-relay/hammerspoon-bridge")
        .path
}

private struct KeyStroke: Hashable {
    let keyCode: UInt16
    let shifted: Bool
}

private struct LayoutMap {
    let id: String
    let name: String
    let strokeToCharacter: [KeyStroke: Character]
    let characterToStroke: [Character: KeyStroke]
}

private struct Conversion {
    let text: String
    let sourceID: String
    let targetID: String
}

private enum CapitalizationMode: String {
    case preserve
    case sentence
    case uppercase
    case lowercase

    func apply(to text: String) -> String {
        switch self {
        case .preserve:
            return text
        case .sentence:
            var result = text.lowercased()
            guard let letterIndex = result.firstIndex(where: \.isLetter) else { return result }
            let nextIndex = result.index(after: letterIndex)
            result.replaceSubrange(letterIndex..<nextIndex, with: String(result[letterIndex]).uppercased())
            return result
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        }
    }
}

private enum FeedbackSound: String, CaseIterable {
    case pulse
    case relay
    case scan
    case flux
    case prism
    case tick
    case fold
    case nova
}

private enum FeedbackLevel: String {
    case silent
    case quiet
    case balanced
    case full

    var volume: Float {
        switch self {
        case .silent: return 0
        case .quiet: return 0.25
        case .balanced: return 0.55
        case .full: return 0.82
        }
    }
}

private enum InputSources {
    static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(pointer, to: CFString.self) as String
    }

    /// Any installed source, enabled or not (mirrors the historical lookup used
    /// to build the default pair, so absent-settings installs see no behavior
    /// change and no new dependency on the source being in the active list).
    static func source(withID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() else { return nil }
        return (list as NSArray).firstObject as! TISInputSource?
    }

    /// Only a source the user currently has enabled (in their active input
    /// menu) resolves here — used to validate a *stored* configured pair,
    /// where "not enabled" must be treated as a distinct failure from
    /// "not installed" per the settings-validation contract.
    static func enabledSource(withID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return nil }
        return (list as NSArray).firstObject as! TISInputSource?
    }

    static func isEnabled(id: String) -> Bool {
        enabledSource(withID: id) != nil
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    @discardableResult
    static func select(_ id: String) -> Bool {
        guard let source = source(withID: id) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    @discardableResult
    static func toggle(source sourceID: String, target targetID: String) -> Bool {
        let next = currentID() == targetID ? sourceID : targetID
        return select(next)
    }

    /// Currently enabled keyboard layouts eligible for the pair picker:
    /// excludes palette entries (`kTISCategoryPaletteInputSource`) and IME
    /// input modes (e.g. `com.apple.CharacterPaletteIM`, Pinyin, Kotoeri) by
    /// requiring the same Unicode key layout data the conversion engine
    /// itself needs — those categories never carry it. Never enables,
    /// disables, or reorders anything; read-only enumeration.
    static func enabledKeyboardLayouts() -> [(id: String, name: String)] {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
            guard TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { return nil }
            let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
            return (id, name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Structural build only (installed + has key layout data). Used for the
    /// default pair and for exercising the engine against an arbitrary
    /// deterministic pair without requiring it to be in the user's active
    /// input menu on this machine.
    static func layoutMap(id: String) -> LayoutMap? {
        guard let source = source(withID: id),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        let data = unsafeBitCast(dataPointer, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let keyboardLayout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var strokeToCharacter: [KeyStroke: Character] = [:]
        var characterToStroke: [Character: KeyStroke] = [:]

        for keyCode in UInt16(0)...UInt16(127) {
            for shifted in [false, true] {
                guard let character = translate(
                    keyboardLayout: keyboardLayout,
                    keyCode: keyCode,
                    shifted: shifted
                ) else { continue }

                let stroke = KeyStroke(keyCode: keyCode, shifted: shifted)
                strokeToCharacter[stroke] = character
                if characterToStroke[character] == nil {
                    characterToStroke[character] = stroke
                }
            }
        }

        guard !strokeToCharacter.isEmpty else { return nil }
        return LayoutMap(
            id: id,
            name: name,
            strokeToCharacter: strokeToCharacter,
            characterToStroke: characterToStroke
        )
    }

    /// Validation build for a *stored* pair identifier: missing, not
    /// enabled, and no-Unicode-data are each distinct failures collapsed
    /// into one `nil` here; the caller (`LayoutPairResolver`) re-derives
    /// which one it was for the doctor blocker message.
    static func enabledLayoutMap(id: String) -> LayoutMap? {
        guard isEnabled(id: id) else { return nil }
        return layoutMap(id: id)
    }

    private static func translate(
        keyboardLayout: UnsafePointer<UCKeyboardLayout>,
        keyCode: UInt16,
        shifted: Bool
    ) -> Character? {
        var deadKeyState: UInt32 = 0
        var actualLength = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let modifierState = shifted ? UInt32(shiftKey >> 8) : 0
        let status = buffer.withUnsafeMutableBufferPointer { pointer in
            UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                pointer.count,
                &actualLength,
                pointer.baseAddress
            )
        }

        guard status == noErr, actualLength > 0 else { return nil }
        let value = String(utf16CodeUnits: buffer, count: Int(actualLength))
        guard value.count == 1, let character = value.first, !character.isWhitespace else { return nil }
        return character
    }
}

/// Resolves the configured layout pair from `UserDefaults`, validating a
/// stored pair and falling back to `AppIdentity`'s default pair (with a
/// `blocker` explanation) instead of ever failing outright — only the
/// default pair itself being unresolvable is left as a hard failure, which
/// mirrors today's exit-on-missing-defaults behavior.
private enum LayoutPairResolver {
    struct Resolution {
        let source: LayoutMap
        let target: LayoutMap
        let sourceID: String
        let targetID: String
        let blocker: String?
    }

    static func resolve(defaults: UserDefaults) -> Resolution? {
        let storedSource = defaults.string(forKey: "sourceLayoutID")
        let storedTarget = defaults.string(forKey: "targetLayoutID")

        // Nothing stored at all: existing installs keep today's pair, silently.
        guard storedSource != nil || storedTarget != nil else {
            return defaultResolution()
        }

        let sourceID = storedSource ?? AppIdentity.defaultSourceID
        let targetID = storedTarget ?? AppIdentity.defaultTargetID

        if let source = InputSources.enabledLayoutMap(id: sourceID),
           let target = InputSources.enabledLayoutMap(id: targetID) {
            return Resolution(source: source, target: target, sourceID: sourceID, targetID: targetID, blocker: nil)
        }

        guard let fallback = defaultResolution() else { return nil }
        return Resolution(
            source: fallback.source,
            target: fallback.target,
            sourceID: fallback.sourceID,
            targetID: fallback.targetID,
            blocker: blockerMessage(sourceID: sourceID, targetID: targetID)
        )
    }

    private static func defaultResolution() -> Resolution? {
        guard let source = InputSources.layoutMap(id: AppIdentity.defaultSourceID),
              let target = InputSources.layoutMap(id: AppIdentity.defaultTargetID)
        else { return nil }
        return Resolution(
            source: source,
            target: target,
            sourceID: AppIdentity.defaultSourceID,
            targetID: AppIdentity.defaultTargetID,
            blocker: nil
        )
    }

    private static func blockerMessage(sourceID: String, targetID: String) -> String {
        var reasons: [String] = []
        if let reason = failureReason(id: sourceID) { reasons.append("source \(sourceID) \(reason)") }
        if let reason = failureReason(id: targetID) { reasons.append("target \(targetID) \(reason)") }
        let detail = reasons.isEmpty ? "the configured layout pair is unavailable" : reasons.joined(separator: "; ")
        return "\(detail). Using \(AppIdentity.defaultSourceID) ⇄ \(AppIdentity.defaultTargetID) instead. " +
            "Re-pick the pair in the Language Relay panel, or enable it in " +
            "System Settings → Keyboard → Input Sources."
    }

    private static func failureReason(id: String) -> String? {
        guard InputSources.source(withID: id) != nil else { return "is not installed" }
        guard InputSources.isEnabled(id: id) else { return "is not enabled" }
        guard InputSources.layoutMap(id: id) != nil else { return "has no usable keyboard layout data" }
        return nil
    }
}

private final class LayoutConversionCore {
    let source: LayoutMap
    let target: LayoutMap
    /// Non-nil only when a stored pair failed validation and the default
    /// pair was substituted; surfaced verbatim by `--doctor-json`.
    let blocker: String?

    /// Production entry point: resolves the pair from `UserDefaults`,
    /// validating a stored pair against "installed", "enabled", and "has
    /// Unicode key layout data" and falling back to the default pair
    /// (with `blocker` set) rather than failing.
    init?(defaults: UserDefaults) {
        guard let resolution = LayoutPairResolver.resolve(defaults: defaults) else { return nil }
        self.source = resolution.source
        self.target = resolution.target
        self.blocker = resolution.blocker
    }

    /// Structural entry point used by tests to exercise the conversion
    /// engine against an arbitrary deterministic pair (e.g. Apple's
    /// standard `Russian` layout) without requiring it to be enabled in the
    /// active input menu on the machine running the test.
    init?(sourceID: String, targetID: String) {
        guard let source = InputSources.layoutMap(id: sourceID),
              let target = InputSources.layoutMap(id: targetID)
        else { return nil }
        self.source = source
        self.target = target
        self.blocker = nil
    }

    func convertAll(
        _ text: String,
        capitalization: CapitalizationMode = .preserve
    ) -> Conversion? {
        guard let detectedSource = detectSource(for: text) else { return nil }
        let destination = detectedSource.id == source.id ? target : source
        guard let converted = convert(text, from: detectedSource, to: destination) else { return nil }
        return Conversion(
            text: capitalization.apply(to: converted.text),
            sourceID: converted.sourceID,
            targetID: converted.targetID
        )
    }

    func convertTrailingPhrase(
        _ text: String,
        capitalization: CapitalizationMode = .preserve
    ) -> Conversion? {
        let tokens = tokenize(text)
        guard let lastWordIndex = tokens.lastIndex(where: { $0.isWord }),
              let phraseSource = detectSource(for: tokens[lastWordIndex].text)
        else { return nil }

        var startIndex = lastWordIndex
        var index = lastWordIndex
        while index >= 0 {
            let token = tokens[index]
            if token.isWord {
                guard detectSource(for: token.text)?.id == phraseSource.id else { break }
                startIndex = index
            }
            if index == 0 { break }
            index -= 1
        }

        let keep = tokens[..<startIndex].map(\.text).joined()
        let phrase = tokens[startIndex...].map(\.text).joined()
        let destination = phraseSource.id == source.id ? target : source
        guard let converted = convert(phrase, from: phraseSource, to: destination) else { return nil }
        return Conversion(
            text: keep + capitalization.apply(to: converted.text),
            sourceID: phraseSource.id,
            targetID: destination.id
        )
    }

    private func convert(_ text: String, from origin: LayoutMap, to destination: LayoutMap) -> Conversion? {
        var result = ""
        var mappedLetters = 0

        for character in text {
            if let stroke = origin.characterToStroke[character],
               let targetCharacter = destination.strokeToCharacter[stroke] {
                result.append(targetCharacter)
                if character.isLetter { mappedLetters += 1 }
            } else {
                result.append(character)
            }
        }

        guard mappedLetters > 0, result != text else { return nil }
        return Conversion(text: result, sourceID: origin.id, targetID: destination.id)
    }

    private func detectSource(for text: String) -> LayoutMap? {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }
        let sourceScore = letters.reduce(0) { $0 + (source.characterToStroke[$1] == nil ? 0 : 1) }
        let targetScore = letters.reduce(0) { $0 + (target.characterToStroke[$1] == nil ? 0 : 1) }
        guard sourceScore != targetScore else { return nil }
        return sourceScore > targetScore ? source : target
    }

    private struct Token {
        let text: String
        let isWord: Bool
    }

    private func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var bufferIsWord: Bool?

        for character in text {
            let isWord = character.isLetter || character.isNumber
            if let currentKind = bufferIsWord, currentKind != isWord {
                tokens.append(Token(text: buffer, isWord: currentKind))
                buffer = ""
            }
            bufferIsWord = isWord
            buffer.append(character)
        }

        if let currentKind = bufferIsWord, !buffer.isEmpty {
            tokens.append(Token(text: buffer, isWord: currentKind))
        }
        return tokens
    }
}

private enum FixMode: String {
    case phrase
    case lastWord
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture() -> PasteboardSnapshot {
        let values = NSPasteboard.general.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        return PasteboardSnapshot(items: values)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let pasteboardItems = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !pasteboardItems.isEmpty { pasteboard.writeObjects(pasteboardItems) }
    }
}

@MainActor
private final class TextFixer {
    /// `var` so the app delegate can swap in a rebuilt core after the user
    /// picks a new layout pair, without tearing down the whole fixer.
    var core: LayoutConversionCore

    init(core: LayoutConversionCore) {
        self.core = core
    }

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func fix(
        mode: FixMode,
        capitalization: CapitalizationMode,
        completion: @escaping (Bool) -> Void
    ) {
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission()
            completion(false)
            return
        }

        let snapshot = PasteboardSnapshot.capture()
        if let selected = selectedTextFromAccessibility(),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let conversion = core.convertAll(selected, capitalization: capitalization) {
            paste(conversion, snapshot: snapshot, completion: completion)
            return
        }
        selectAndFix(
            mode: mode,
            capitalization: capitalization,
            snapshot: snapshot,
            completion: completion
        )
    }

    private func selectedTextFromAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else { return nil }

        let focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success else { return nil }
        return selectedValue as? String
    }

    private func selectAndFix(
        mode: FixMode,
        capitalization: CapitalizationMode,
        snapshot: PasteboardSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        switch mode {
        case .phrase:
            keyStroke(code: 0x7B, flags: [.maskCommand, .maskShift])
        case .lastWord:
            keyStroke(code: 0x7B, flags: [.maskAlternate, .maskShift])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { completion(false); return }
            NSPasteboard.general.clearContents()
            self.keyStroke(code: 0x08, flags: .maskCommand)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self else { completion(false); return }
                guard let selected = NSPasteboard.general.string(forType: .string),
                      !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.cancelSelection(snapshot: snapshot, completion: completion)
                    return
                }

                let conversion = mode == .phrase
                    ? self.core.convertTrailingPhrase(selected, capitalization: capitalization)
                    : self.core.convertAll(selected, capitalization: capitalization)
                guard let conversion else {
                    self.cancelSelection(snapshot: snapshot, completion: completion)
                    return
                }
                self.paste(conversion, snapshot: snapshot, completion: completion)
            }
        }
    }

    private func paste(
        _ conversion: Conversion,
        snapshot: PasteboardSnapshot,
        completion: @escaping (Bool) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(conversion.text, forType: .string)
        keyStroke(code: 0x09, flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            _ = InputSources.select(conversion.targetID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            snapshot.restore()
            completion(true)
        }
    }

    private func cancelSelection(snapshot: PasteboardSnapshot, completion: @escaping (Bool) -> Void) {
        keyStroke(code: 0x7C)
        snapshot.restore()
        completion(false)
    }

    private func keyStroke(code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

private final class DoubleShiftMonitor {
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastCleanTap: TimeInterval = 0
    private var cleanShiftIsDown = false
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func start() {
        stop()
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.cleanShiftIsDown = false
            self?.lastCleanTap = 0
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.cleanShiftIsDown = false
            self?.lastCleanTap = 0
            return event
        }
    }

    func stop() {
        for monitor in [globalFlagsMonitor, localFlagsMonitor, globalKeyMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        cleanShiftIsDown = false
        lastCleanTap = 0
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftDown = flags.contains(.shift)
        let onlyShift = shiftDown && !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)

        if onlyShift && !cleanShiftIsDown {
            cleanShiftIsDown = true
            return
        }
        guard !shiftDown, cleanShiftIsDown else {
            if !onlyShift { cleanShiftIsDown = false; lastCleanTap = 0 }
            return
        }

        cleanShiftIsDown = false
        let now = ProcessInfo.processInfo.systemUptime
        if lastCleanTap > 0, now - lastCleanTap <= 0.38 {
            lastCleanTap = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: action)
        } else {
            lastCleanTap = now
        }
    }
}

private enum LayoutPilotPanelMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 604
    static let contentWidth: CGFloat = 388
}

private final class LayoutPilotRootView: NSView {
    var closeAction: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            closeAction?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class ScopeChoiceButton: NSButton {
    enum Kind { case phrase, word }

    var isActive = false { didSet { applyState() } }
    private let kind: Kind
    private let primary: String
    private let detail: String
    private var hovering = false { didSet { applyState() } }

    init(
        kind: Kind,
        primary: String,
        detail: String,
        target: AnyObject?,
        action: Selector,
        width: CGFloat
    ) {
        self.kind = kind
        self.primary = primary
        self.detail = detail
        super.init(frame: .zero)
        title = ""
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 48).isActive = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 0
        setAccessibilityLabel("\(primary), \(detail)")
        applyState()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func applyState() {
        layer?.borderColor = (isActive ? UI.ink : UI.hair).cgColor
        layer?.backgroundColor = (isActive ? UI.ink : hovering ? UI.hair : UI.fill).cgColor
        setAccessibilitySelected(isActive)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = isActive ? UI.bg : UI.ink
        drawGlyph(color: color)
        NSAttributedString(
            string: primary,
            attributes: [
                .font: UI.mono(11.5, weight: .semibold),
                .foregroundColor: color,
                .kern: 0.2,
            ]
        ).draw(at: NSPoint(x: 61, y: 8))
        NSAttributedString(
            string: detail,
            attributes: [
                .font: UI.mono(8.2, weight: .semibold),
                .foregroundColor: isActive ? UI.bg.withAlphaComponent(0.72) : UI.muted,
                .kern: 0.2,
            ]
        ).draw(at: NSPoint(x: 61, y: 29))
    }

    private func drawGlyph(color: NSColor) {
        color.setStroke()
        color.setFill()
        let tokens = [NSRect(x: 14, y: 16, width: 9, height: 8),
                      NSRect(x: 27, y: 16, width: 8, height: 8),
                      NSRect(x: 39, y: 16, width: 11, height: 8)]
        for token in tokens {
            let path = NSBezierPath(rect: token)
            path.lineWidth = 1.1
            path.stroke()
        }
        let startX: CGFloat = kind == .phrase ? 14 : 39
        let brace = NSBezierPath()
        brace.move(to: NSPoint(x: startX, y: 29))
        brace.line(to: NSPoint(x: startX, y: 33))
        brace.line(to: NSPoint(x: 50, y: 33))
        brace.line(to: NSPoint(x: 50, y: 29))
        brace.lineWidth = 1.2
        brace.stroke()
    }
}

private final class CaseChoiceButton: NSButton {
    var isActive = false { didSet { applyState() } }
    private let sample: String
    private let labelText: String
    private var hovering = false { didSet { applyState() } }

    init(sample: String, label: String, help: String, target: AnyObject?, action: Selector, width: CGFloat) {
        self.sample = sample
        self.labelText = label
        super.init(frame: .zero)
        title = ""
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 54).isActive = true
        layer?.borderWidth = 1
        layer?.cornerRadius = 0
        setAccessibilityLabel("\(label), \(help)")
        applyState()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func applyState() {
        layer?.borderColor = (isActive ? UI.ink : UI.hair).cgColor
        layer?.backgroundColor = (isActive ? UI.ink : hovering ? UI.hair : UI.fill).cgColor
        setAccessibilitySelected(isActive)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = isActive ? UI.bg : UI.ink
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSAttributedString(
            string: sample,
            attributes: [
                .font: UI.mono(17, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: 0.4,
            ]
        ).draw(in: NSRect(x: 0, y: 5, width: bounds.width, height: 23))
        NSAttributedString(
            string: labelText,
            attributes: [
                .font: UI.mono(8.2, weight: .semibold),
                .foregroundColor: isActive ? UI.bg.withAlphaComponent(0.72) : UI.muted,
                .paragraphStyle: paragraph,
                .kern: 0.25,
            ]
        ).draw(in: NSRect(x: 0, y: 34, width: bounds.width, height: 14))
    }
}

private enum LayoutPilotStatusGlyph {
    static func make(russianActive: Bool) -> NSImage {
        let size = NSSize(width: 54, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            drawCell(NSRect(x: 1, y: 1, width: 18, height: 16), text: "a", active: !russianActive)
            drawCell(NSRect(x: 35, y: 1, width: 18, height: 16), text: "ру", active: russianActive)

            let relay = NSBezierPath()
            relay.move(to: NSPoint(x: 21, y: 9))
            relay.line(to: NSPoint(x: 33, y: 9))
            relay.move(to: NSPoint(x: 21, y: 9))
            relay.line(to: NSPoint(x: 24.5, y: 12.5))
            relay.move(to: NSPoint(x: 21, y: 9))
            relay.line(to: NSPoint(x: 24.5, y: 5.5))
            relay.move(to: NSPoint(x: 33, y: 9))
            relay.line(to: NSPoint(x: 29.5, y: 12.5))
            relay.move(to: NSPoint(x: 33, y: 9))
            relay.line(to: NSPoint(x: 29.5, y: 5.5))
            relay.lineWidth = 1
            relay.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Language Relay input source"
        return image
    }

    private static func drawCell(_ rect: NSRect, text: String, active: Bool) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        if active {
            path.fill()
        } else {
            path.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: text == "a" ? 9.5 : 7.4, weight: .semibold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
            .kern: 0.1,
        ]
        let textValue = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(x: rect.minX, y: rect.minY + 2.2, width: rect.width, height: rect.height - 2)
        if active {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            textValue.draw(in: textRect)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            textValue.draw(in: textRect)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    /// `var`: rebuilt in place when the user picks a new layout pair from
    /// the panel, so the running app never needs a restart to pick it up.
    private var core: LayoutConversionCore
    private let fixer: TextFixer
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var monitor: DoubleShiftMonitor!
    private var refreshTimer: Timer?
    private var popover: NSPopover?
    private var lastPopoverCloseAt = Date.distantPast
    private var previewSound: NSSound?
    private var lastObservedInputID: String?
    private var layoutMenuSleeves: [ClosureSleeve] = []

    private var mode: FixMode {
        get { FixMode(rawValue: defaults.string(forKey: "fixMode") ?? "phrase") ?? .phrase }
        set { defaults.set(newValue.rawValue, forKey: "fixMode") }
    }

    private var soundEnabled: Bool {
        get { soundLevel != .silent }
        set { soundLevel = newValue ? .balanced : .silent }
    }

    private var soundName: String {
        get {
            let value = defaults.string(forKey: "soundName") ?? FeedbackSound.pulse.rawValue
            return FeedbackSound(rawValue: value)?.rawValue ?? FeedbackSound.pulse.rawValue
        }
        set { defaults.set(newValue, forKey: "soundName") }
    }

    private var soundLevel: FeedbackLevel {
        get {
            FeedbackLevel(rawValue: defaults.string(forKey: "soundLevel") ?? "balanced")
                ?? .balanced
        }
        set { defaults.set(newValue.rawValue, forKey: "soundLevel") }
    }

    private var capitalization: CapitalizationMode {
        get {
            CapitalizationMode(rawValue: defaults.string(forKey: "capitalizationMode") ?? "preserve")
                ?? .preserve
        }
        set { defaults.set(newValue.rawValue, forKey: "capitalizationMode") }
    }

    private var shiftEnabled: Bool {
        get { defaults.object(forKey: "shiftEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shiftEnabled") }
    }

    private var optionEnabled: Bool {
        get { defaults.object(forKey: "optionEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "optionEnabled") }
    }

    init(core: LayoutConversionCore) {
        self.core = core
        self.fixer = TextFixer(core: core)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.enforceSingleInstance()
        }
        NSApp.setActivationPolicy(.accessory)
        UI.setMode(.light)
        setupStatusItem()

        monitor = DoubleShiftMonitor { [weak self] in self?.performFix() }
        if !usesHammerspoonBridge { monitor.start() }
        updateStatusButton()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusButton() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if !usesHammerspoonBridge, !fixer.hasAccessibilityPermission {
            fixer.requestAccessibilityPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        refreshTimer?.invalidate()
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseAt = Date()
    }

    private func enforceSingleInstance() {
        let mine = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .filter {
                $0.processIdentifier != mine.processIdentifier
                    && !$0.isTerminated
                    && $0.bundleURL == mine.bundleURL
            }
        let myKey = (mine.launchDate ?? .distantPast, mine.processIdentifier)
        for other in others {
            let otherKey = (other.launchDate ?? .distantPast, other.processIdentifier)
            if otherKey < myKey { exit(0) }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 54)
        statusItem.autosaveName = "dev.alex.layout-pilot.status-item.v3"
        statusItem.menu = nil
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityLabel("Language Relay")
        button.setAccessibilityHelp("Left click opens controls. Right click opens quick actions.")
    }

    private func updateStatusButton() {
        let currentID = InputSources.currentID()
        let targetActive = currentID == core.target.id
        statusItem.button?.image = LayoutPilotStatusGlyph.make(russianActive: targetActive)
        statusItem.button?.toolTip = "Language Relay · ⇧⇧ or clean ⌥ repairs the last wrong-layout text"
        if let previous = lastObservedInputID,
           previous != currentID,
           popover?.isShown == true {
            rebuildPopoverContent()
        }
        lastObservedInputID = currentID
    }

    private var usesHammerspoonBridge: Bool {
        FileManager.default.fileExists(atPath: AppIdentity.hammerspoonBridgeMarker)
    }

    private var carambaRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "tech.caramba.switcher"
        ).isEmpty
    }

    @objc private func statusItemAction(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showNativeMenu()
            return
        }
        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }
        guard Date().timeIntervalSince(lastPopoverCloseAt) > 0.35 else { return }
        showPopover()
    }

    private func showPopover() {
        buildPopover()
        guard let popover, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let root = popover.contentViewController?.view {
            root.window?.makeFirstResponder(root)
        }
    }

    private func buildPopover() {
        let controller = NSViewController()
        controller.view = makePanelContent()
        controller.preferredContentSize = NSSize(
            width: LayoutPilotPanelMetrics.width,
            height: LayoutPilotPanelMetrics.height
        )

        let next = NSPopover()
        next.behavior = .transient
        next.animates = !UI.reduceMotion
        next.appearance = NSAppearance(named: .aqua)
        next.contentSize = controller.preferredContentSize
        next.contentViewController = controller
        next.delegate = self
        popover = next
    }

    private func rebuildPopoverContent() {
        guard popover?.isShown == true else { return }
        popover?.contentViewController?.view = makePanelContent()
    }

    private func makePanelContent() -> NSView {
        let content = LayoutPilotRootView(frame: NSRect(
            x: 0,
            y: 0,
            width: LayoutPilotPanelMetrics.width,
            height: LayoutPilotPanelMetrics.height
        ))
        content.closeAction = { [weak self] in self?.popover?.performClose(nil) }
        content.wantsLayer = true
        content.layer?.backgroundColor = UI.bg.cgColor
        content.layer?.borderColor = UI.hair.cgColor
        content.layer?.borderWidth = 1

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 4
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -10),
        ])

        root.addArrangedSubview(label("language relay", size: 20, weight: .semibold, color: UI.ink, height: 27))
        root.addArrangedSubview(label("apowall instrument 02 · local layout bridge · v2.3.1", size: 9.2, weight: .semibold, color: UI.muted, height: 13))
        root.addArrangedSubview(hairLine(width: LayoutPilotPanelMetrics.contentWidth))

        root.addArrangedSubview(sectionHeader("01 · input · active layout", width: LayoutPilotPanelMetrics.contentWidth))
        let layoutRow = NSStackView()
        layoutRow.orientation = .horizontal
        layoutRow.alignment = .centerY
        layoutRow.spacing = 6
        let current = InputSources.currentID()
        let sourceLabel = core.source.name.lowercased()
        let targetLabel = core.target.name.lowercased()
        let currentLabel = current == core.target.id
            ? "\(sourceLabel) ⇄ [\(targetLabel)] · active"
            : "[\(sourceLabel)] ⇄ \(targetLabel) · active"
        let state = stateReadout(currentLabel, width: 340, height: 42)
        let toggle = squareButton("⇄", action: #selector(toggleLayout), width: 42, height: 42)
        toggle.toolTip = "switch input source"
        layoutRow.addArrangedSubview(state)
        layoutRow.addArrangedSubview(toggle)
        root.addArrangedSubview(layoutRow)

        root.addArrangedSubview(sectionHeader("02 · layout pair · pick from enabled sources", width: LayoutPilotPanelMetrics.contentWidth))
        let pairRow = NSStackView()
        pairRow.orientation = .horizontal
        pairRow.spacing = 6
        let sourcePick = squareButton("src · \(sourceLabel)", action: #selector(chooseSourceLayout(_:)), width: 191, height: 34)
        sourcePick.toolTip = "pick the source keyboard layout from currently enabled input sources"
        let targetPick = squareButton("dst · \(targetLabel)", action: #selector(chooseTargetLayout(_:)), width: 191, height: 34)
        targetPick.toolTip = "pick the target keyboard layout from currently enabled input sources"
        pairRow.addArrangedSubview(sourcePick)
        pairRow.addArrangedSubview(targetPick)
        root.addArrangedSubview(pairRow)

        // Fixed-height slot regardless of blocker presence, so the panel's
        // layout does not shift based on runtime settings validity.
        let blockerText = core.blocker ?? "layout pair resolved from settings"
        let blockerLabel = label(
            blockerText,
            size: 7.6,
            weight: .semibold,
            color: core.blocker == nil ? UI.muted : UI.red,
            height: 26
        )
        blockerLabel.toolTip = blockerText
        blockerLabel.maximumNumberOfLines = 2
        root.addArrangedSubview(blockerLabel)

        root.addArrangedSubview(sectionHeader("03 · correction scope", width: LayoutPilotPanelMetrics.contentWidth))
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.spacing = 6
        let phrase = ScopeChoiceButton(
            kind: .phrase,
            primary: "last phrase",
            detail: "language-run tail",
            target: self,
            action: #selector(setPhraseMode),
            width: 191
        )
        phrase.isActive = mode == .phrase
        let word = ScopeChoiceButton(
            kind: .word,
            primary: "last word",
            detail: "one token",
            target: self,
            action: #selector(setLastWordMode),
            width: 191
        )
        word.isActive = mode == .lastWord
        modeRow.addArrangedSubview(phrase)
        modeRow.addArrangedSubview(word)
        root.addArrangedSubview(modeRow)

        root.addArrangedSubview(sectionHeader("04 · letter case · aA keep · Aa sentence · AA upper · aa lower", width: LayoutPilotPanelMetrics.contentWidth))
        let capitalizationRow = NSStackView()
        capitalizationRow.orientation = .horizontal
        capitalizationRow.spacing = 6
        let preserve = CaseChoiceButton(
            sample: "aA", label: "preserve", help: "keep original capitalization",
            target: self, action: #selector(setCapitalizationPreserve), width: 92.5
        )
        preserve.isActive = capitalization == .preserve
        let sentence = CaseChoiceButton(
            sample: "Aa", label: "sentence", help: "first letter uppercase",
            target: self, action: #selector(setCapitalizationSentence), width: 92.5
        )
        sentence.isActive = capitalization == .sentence
        let uppercase = CaseChoiceButton(
            sample: "AA", label: "uppercase", help: "every letter uppercase",
            target: self, action: #selector(setCapitalizationUppercase), width: 92.5
        )
        uppercase.isActive = capitalization == .uppercase
        let lowercase = CaseChoiceButton(
            sample: "aa", label: "lowercase", help: "every letter lowercase",
            target: self, action: #selector(setCapitalizationLowercase), width: 92.5
        )
        lowercase.isActive = capitalization == .lowercase
        capitalizationRow.addArrangedSubview(preserve)
        capitalizationRow.addArrangedSubview(sentence)
        capitalizationRow.addArrangedSubview(uppercase)
        capitalizationRow.addArrangedSubview(lowercase)
        root.addArrangedSubview(capitalizationRow)

        root.addArrangedSubview(sectionHeader("05 · triggers · standalone modifier taps only", width: LayoutPilotPanelMetrics.contentWidth))
        let triggerRow = NSStackView()
        triggerRow.orientation = .horizontal
        triggerRow.spacing = 6
        let shift = squareButton("⇧ ⇧ · double shift", action: #selector(toggleShift), width: 191, height: 34)
        shift.isActive = shiftEnabled
        let option = squareButton("⌥ · clean option", action: #selector(toggleOption), width: 191, height: 34)
        option.isActive = optionEnabled
        triggerRow.addArrangedSubview(shift)
        triggerRow.addArrangedSubview(option)
        root.addArrangedSubview(triggerRow)

        root.addArrangedSubview(sectionHeader("06 · feedback · micro-sfx", width: LayoutPilotPanelMetrics.contentWidth))
        let soundRow = NSStackView()
        soundRow.orientation = .horizontal
        soundRow.spacing = 6
        let pulse = squareButton("01 pulse", action: #selector(setSoundPulse), width: 92.5, height: 30)
        pulse.isActive = soundEnabled && soundName == "pulse"
        let relay = squareButton("02 relay", action: #selector(setSoundRelay), width: 92.5, height: 30)
        relay.isActive = soundEnabled && soundName == "relay"
        let scan = squareButton("03 scan", action: #selector(setSoundScan), width: 92.5, height: 30)
        scan.isActive = soundEnabled && soundName == "scan"
        let flux = squareButton("04 flux", action: #selector(setSoundFlux), width: 92.5, height: 30)
        flux.isActive = soundEnabled && soundName == "flux"
        soundRow.addArrangedSubview(pulse)
        soundRow.addArrangedSubview(relay)
        soundRow.addArrangedSubview(scan)
        soundRow.addArrangedSubview(flux)
        root.addArrangedSubview(soundRow)

        let soundRowTwo = NSStackView()
        soundRowTwo.orientation = .horizontal
        soundRowTwo.spacing = 6
        let prism = squareButton("05 prism", action: #selector(setSoundPrism), width: 92.5, height: 30)
        prism.isActive = soundEnabled && soundName == "prism"
        let tick = squareButton("06 tick", action: #selector(setSoundTick), width: 92.5, height: 30)
        tick.isActive = soundEnabled && soundName == "tick"
        let fold = squareButton("07 fold", action: #selector(setSoundFold), width: 92.5, height: 30)
        fold.isActive = soundEnabled && soundName == "fold"
        let nova = squareButton("08 nova", action: #selector(setSoundNova), width: 92.5, height: 30)
        nova.isActive = soundEnabled && soundName == "nova"
        soundRowTwo.addArrangedSubview(prism)
        soundRowTwo.addArrangedSubview(tick)
        soundRowTwo.addArrangedSubview(fold)
        soundRowTwo.addArrangedSubview(nova)
        root.addArrangedSubview(soundRowTwo)

        let levelRow = NSStackView()
        levelRow.orientation = .horizontal
        levelRow.spacing = 6
        let silent = squareButton("mute · 00", action: #selector(setLevelSilent), width: 92.5, height: 26)
        silent.isActive = soundLevel == .silent
        let quiet = squareButton("low · 25", action: #selector(setLevelQuiet), width: 92.5, height: 26)
        quiet.isActive = soundLevel == .quiet
        let balanced = squareButton("mid · 55", action: #selector(setLevelBalanced), width: 92.5, height: 26)
        balanced.isActive = soundLevel == .balanced
        let full = squareButton("high · 82", action: #selector(setLevelFull), width: 92.5, height: 26)
        full.isActive = soundLevel == .full
        levelRow.addArrangedSubview(silent)
        levelRow.addArrangedSubview(quiet)
        levelRow.addArrangedSubview(balanced)
        levelRow.addArrangedSubview(full)
        root.addArrangedSubview(levelRow)

        let diagnostic = NSView()
        diagnostic.translatesAutoresizingMaskIntoConstraints = false
        diagnostic.wantsLayer = true
        diagnostic.layer?.backgroundColor = UI.fill.cgColor
        diagnostic.layer?.borderColor = UI.hair.cgColor
        diagnostic.layer?.borderWidth = 1
        diagnostic.widthAnchor.constraint(equalToConstant: LayoutPilotPanelMetrics.contentWidth).isActive = true
        diagnostic.heightAnchor.constraint(equalToConstant: 31).isActive = true
        let diagnosticStack = NSStackView()
        diagnosticStack.orientation = .horizontal
        diagnosticStack.alignment = .centerY
        diagnosticStack.spacing = 8
        diagnosticStack.translatesAutoresizingMaskIntoConstraints = false
        diagnostic.addSubview(diagnosticStack)
        NSLayoutConstraint.activate([
            diagnosticStack.leadingAnchor.constraint(equalTo: diagnostic.leadingAnchor, constant: 10),
            diagnosticStack.trailingAnchor.constraint(equalTo: diagnostic.trailingAnchor, constant: -10),
            diagnosticStack.centerYAnchor.constraint(equalTo: diagnostic.centerYAnchor),
        ])
        let bridge = carambaRunning
            ? "compat · caramba"
            : (usesHammerspoonBridge ? "bridge · online" : "bridge · native")
        diagnosticStack.addArrangedSubview(label(bridge, size: 8.2, weight: .semibold, color: UI.ink, width: 108, height: 13))
        let detail = carambaRunning ? "shift / option owned by caramba" : "last · \(bridgeStatus())"
        diagnosticStack.addArrangedSubview(label(detail, size: 8.0, weight: .semibold, color: UI.muted, width: 242, height: 13))
        root.addArrangedSubview(diagnostic)

        root.addArrangedSubview(label(
            "caps · switch layout   ⇧⇧ / clean ⌥ · repair   esc · close",
            size: 8.0,
            weight: .semibold,
            color: UI.muted,
            height: 13
        ))
        return content
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        width: CGFloat = LayoutPilotPanelMetrics.contentWidth,
        height: CGFloat,
        centered: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text.lowercased())
        field.font = UI.mono(size, weight: weight)
        field.textColor = color
        field.alignment = centered ? .center : .left
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.heightAnchor.constraint(equalToConstant: height).isActive = true
        return field
    }

    private func squareButton(_ title: String, action: Selector, width: CGFloat, height: CGFloat) -> ShaperButton {
        let button = ShaperButton(title, target: self, action: action, width: width, height: height)
        button.layer?.cornerRadius = 0
        return button
    }

    private func stateReadout(_ title: String, width: CGFloat, height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = UI.ink.cgColor
        view.layer?.borderColor = UI.ink.cgColor
        view.layer?.borderWidth = 1
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let text = label(title, size: 11, weight: .semibold, color: UI.bg, width: width - 20, height: 18, centered: true)
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func bridgeStatus() -> String {
        guard usesHammerspoonBridge, FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/hs") else {
            return "native ready"
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hs")
        process.arguments = ["-c", "return tostring(hs.settings.get('layout_pilot_last_status') or 'ready')"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : "ready"
        } catch {
            return "bridge unavailable"
        }
    }

    func runBackgroundUISelfTest() -> Bool {
        UI.setMode(.light)
        let panel = makePanelContent()
        panel.layoutSubtreeIfNeeded()
        let glyph = LayoutPilotStatusGlyph.make(russianActive: false)
        return panel.frame.size == NSSize(
            width: LayoutPilotPanelMetrics.width,
            height: LayoutPilotPanelMetrics.height
        )
            && panel.window == nil
            && !panel.subviews.isEmpty
            && glyph.size == NSSize(width: 54, height: 18)
            && glyph.isTemplate
    }

    func renderBackgroundUIPreview(to url: URL) -> Bool {
        UI.setMode(.light)
        let panel = makePanelContent()
        panel.layoutSubtreeIfNeeded()
        guard let bitmap = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else { return false }
        panel.cacheDisplay(in: panel.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url, options: .atomic)
            return panel.window == nil
        } catch {
            return false
        }
    }

    private func showNativeMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "open language relay", action: #selector(openPanelFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let toggle = NSMenuItem(title: "switch layout", action: #selector(toggleLayout), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "quit language relay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.statusItem.menu = nil }
    }

    private func performFix() {
        guard !carambaRunning else { return }
        if usesHammerspoonBridge {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hs")
            task.arguments = ["-c", "layoutPilotFix()"]
            try? task.run()
            return
        }
        fixer.fix(mode: mode, capitalization: capitalization) { [weak self] success in
            guard let self else { return }
            if success { self.playSelectedSound() }
            self.updateStatusButton()
        }
    }

    private func reloadBridgeSettings() {
        guard usesHammerspoonBridge else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hs")
        task.arguments = ["-c", "return tostring(layoutPilotReloadSettings())"]
        try? task.run()
    }

    @objc private func openPanelFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.showPopover() }
    }

    @objc private func toggleLayout() {
        _ = InputSources.toggle(source: core.source.id, target: core.target.id)
        updateStatusButton()
        rebuildPopoverContent()
    }

    @objc private func chooseSourceLayout(_ sender: NSButton) {
        presentLayoutMenu(current: core.source.id, for: sender) { [weak self] id in
            self?.setLayoutPair(sourceID: id, targetID: nil)
        }
    }

    @objc private func chooseTargetLayout(_ sender: NSButton) {
        presentLayoutMenu(current: core.target.id, for: sender) { [weak self] id in
            self?.setLayoutPair(sourceID: nil, targetID: id)
        }
    }

    private func presentLayoutMenu(current: String, for sender: NSButton, onSelect: @escaping (String) -> Void) {
        layoutMenuSleeves.removeAll()
        let menu = NSMenu()
        let layouts = InputSources.enabledKeyboardLayouts()
        if layouts.isEmpty {
            let empty = NSMenuItem(title: "no enabled keyboard layouts found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for layout in layouts {
            let item = NSMenuItem(title: layout.name, action: #selector(ClosureSleeve.invoke(_:)), keyEquivalent: "")
            let sleeve = ClosureSleeve { onSelect(layout.id) }
            layoutMenuSleeves.append(sleeve)
            item.target = sleeve
            item.state = layout.id == current ? .on : .off
            menu.addItem(item)
        }
        _ = menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    /// Writes the picked identifier(s) as strings under `dev.alex.layout-pilot`
    /// and rebuilds the running core in place. If the new pick collides with
    /// the other half of the pair, swaps them instead of collapsing to a
    /// degenerate single-layout "pair".
    private func setLayoutPair(sourceID: String?, targetID: String?) {
        var nextSource = sourceID ?? core.source.id
        var nextTarget = targetID ?? core.target.id
        if nextSource == nextTarget {
            if let sourceID { nextTarget = core.source.id; nextSource = sourceID }
            else if let targetID { nextSource = core.target.id; nextTarget = targetID }
        }
        defaults.set(nextSource, forKey: "sourceLayoutID")
        defaults.set(nextTarget, forKey: "targetLayoutID")
        reloadLayoutPair()
    }

    private func reloadLayoutPair() {
        guard let rebuilt = LayoutConversionCore(defaults: defaults) else { return }
        core = rebuilt
        fixer.core = rebuilt
        reloadBridgeSettings()
        updateStatusButton()
        rebuildPopoverContent()
    }

    @objc private func setPhraseMode() { mode = .phrase; reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setLastWordMode() { mode = .lastWord; reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setCapitalizationPreserve() { setCapitalization(.preserve) }
    @objc private func setCapitalizationSentence() { setCapitalization(.sentence) }
    @objc private func setCapitalizationUppercase() { setCapitalization(.uppercase) }
    @objc private func setCapitalizationLowercase() { setCapitalization(.lowercase) }
    @objc private func toggleShift() { shiftEnabled.toggle(); reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func toggleOption() { optionEnabled.toggle(); reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setSoundPulse() { selectSound(.pulse) }
    @objc private func setSoundRelay() { selectSound(.relay) }
    @objc private func setSoundScan() { selectSound(.scan) }
    @objc private func setSoundFlux() { selectSound(.flux) }
    @objc private func setSoundPrism() { selectSound(.prism) }
    @objc private func setSoundTick() { selectSound(.tick) }
    @objc private func setSoundFold() { selectSound(.fold) }
    @objc private func setSoundNova() { selectSound(.nova) }
    @objc private func setLevelSilent() { selectLevel(.silent) }
    @objc private func setLevelQuiet() { selectLevel(.quiet) }
    @objc private func setLevelBalanced() { selectLevel(.balanced) }
    @objc private func setLevelFull() { selectLevel(.full) }
    private func setCapitalization(_ value: CapitalizationMode) {
        capitalization = value
        reloadBridgeSettings()
        rebuildPopoverContent()
    }

    private func selectSound(_ sound: FeedbackSound) {
        soundName = sound.rawValue
        soundEnabled = true
        reloadBridgeSettings()
        playSelectedSound()
        rebuildPopoverContent()
    }

    private func selectLevel(_ level: FeedbackLevel) {
        soundLevel = level
        reloadBridgeSettings()
        playSelectedSound()
        rebuildPopoverContent()
    }

    private func playSelectedSound() {
        guard soundEnabled,
              let url = Bundle.main.resourceURL?
                .appendingPathComponent("Sounds", isDirectory: true)
                .appendingPathComponent("\(soundName).aiff"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        previewSound?.stop()
        previewSound = sound
        sound.volume = soundLevel.volume
        sound.play()
    }

    @objc private func openAccessibility() {
        fixer.requestAccessibilityPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private enum SelfTest {
    static func run(core: LayoutConversionCore) -> Int32 {
        var failures: [String] = []

        func expect(_ input: String, _ expected: String) {
            let actual = core.convertAll(input)?.text
            if actual != expected { failures.append("\(input) -> \(actual ?? "nil"), expected \(expected)") }
        }

        expect("ghbdtn", "привет")
        expect("руддщ", "hello")
        expect("Ghbdtn", "Привет")
        expect("Vbh!", "Мир!")
        expect("ghbdtn&", "привет?")
        expect("fewfw", "ауцац")
        expect("ауцаау", "fewffe")

        let sentence = core.convertAll("ghbdtn", capitalization: .sentence)?.text
        if sentence != "Привет" { failures.append("sentence capitalization -> \(sentence ?? "nil")") }
        let sentenceFromUppercase = core.convertAll("GHBDTN", capitalization: .sentence)?.text
        if sentenceFromUppercase != "Привет" {
            failures.append("sentence uppercase input -> \(sentenceFromUppercase ?? "nil")")
        }
        let uppercase = core.convertAll("ghbdtn", capitalization: .uppercase)?.text
        if uppercase != "ПРИВЕТ" { failures.append("uppercase capitalization -> \(uppercase ?? "nil")") }
        let lowercase = core.convertAll("GHBDTN", capitalization: .lowercase)?.text
        if lowercase != "привет" { failures.append("lowercase capitalization -> \(lowercase ?? "nil")") }

        let phrase = core.convertTrailingPhrase("Привет ghbdtn rfr ltkf")?.text
        if phrase != "Привет привет как дела" {
            failures.append("phrase -> \(phrase ?? "nil")")
        }

        let roundTripSeed = "Hello, World!"
        if let russian = core.convertAll(roundTripSeed)?.text,
           let roundTrip = core.convertAll(russian)?.text {
            if roundTrip != roundTripSeed { failures.append("round trip -> \(roundTrip)") }
        } else {
            failures.append("round trip unavailable")
        }

        // Configurable pair, check 1: the engine generalizes to a deterministic
        // pair sourced the same way settings would supply it (plain identifier
        // strings), including Apple's standard `Russian` layout rather than
        // only the PC-remapped `RussianWin` this app shipped with. Built via
        // the structural (installed-only) path, since `com.apple.keylayout.Russian`
        // ships with every macOS install but is not necessarily in anyone's
        // active input menu — this must not require enabling it on the
        // machine running `make test`.
        if let applePair = LayoutConversionCore(sourceID: "com.apple.keylayout.US", targetID: "com.apple.keylayout.Russian") {
            let seed = "privet mir"
            if let converted = applePair.convertAll(seed)?.text,
               converted != seed,
               let roundTrip = applePair.convertAll(converted)?.text,
               roundTrip == seed {
                // conversion and round trip both hold for the Apple standard Russian pair
            } else {
                failures.append("apple standard russian pair: conversion/round-trip failed")
            }
        } else {
            failures.append("apple standard russian pair unavailable (com.apple.keylayout.Russian has no Unicode key layout data on this system)")
        }

        // Configurable pair, check 2: an unresolvable *stored* identifier
        // must fall back to the default pair with a blocker explanation
        // rather than making the whole app exit. Uses an isolated defaults
        // suite (cleaned up below) so this never touches real app settings.
        let selfTestSuite = "dev.alex.layout-pilot.self-test"
        if let fallbackDefaults = UserDefaults(suiteName: selfTestSuite) {
            fallbackDefaults.removePersistentDomain(forName: selfTestSuite)
            fallbackDefaults.set("com.apple.keylayout.LanguageRelaySelfTestBogus", forKey: "sourceLayoutID")
            if let resolved = LayoutConversionCore(defaults: fallbackDefaults) {
                if resolved.blocker == nil {
                    failures.append("settings fallback: expected a blocker for an unresolvable stored identifier")
                }
                if resolved.source.id != AppIdentity.defaultSourceID || resolved.target.id != AppIdentity.defaultTargetID {
                    failures.append("settings fallback: expected the default pair, got \(resolved.source.id) / \(resolved.target.id)")
                }
            } else {
                failures.append("settings fallback: resolver exited instead of falling back to the default pair")
            }
            fallbackDefaults.removePersistentDomain(forName: selfTestSuite)
        } else {
            failures.append("settings fallback: could not create an isolated defaults suite for the test")
        }

        // Configurable pair, check 3: absent settings (the common case for
        // every existing install) must keep today's pair with no blocker.
        let absentSuite = "dev.alex.layout-pilot.self-test-absent"
        if let absentDefaults = UserDefaults(suiteName: absentSuite) {
            absentDefaults.removePersistentDomain(forName: absentSuite)
            if let resolved = LayoutConversionCore(defaults: absentDefaults) {
                if resolved.blocker != nil {
                    failures.append("absent settings: unexpected blocker \(resolved.blocker ?? "")")
                }
                if resolved.source.id != AppIdentity.defaultSourceID || resolved.target.id != AppIdentity.defaultTargetID {
                    failures.append("absent settings: expected the default pair, got \(resolved.source.id) / \(resolved.target.id)")
                }
            } else {
                failures.append("absent settings: resolver returned nil")
            }
            absentDefaults.removePersistentDomain(forName: absentSuite)
        } else {
            failures.append("absent settings: could not create an isolated defaults suite for the test")
        }

        guard failures.isEmpty else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            return 1
        }
        print("PASS: 16 layout conversion tests; \(core.source.name) ↔ \(core.target.name)")
        return 0
    }
}

@main
private struct LayoutPilotMain {
    @MainActor
    static func main() {
        let defaults = UserDefaults.standard
        guard let core = LayoutConversionCore(defaults: defaults) else {
            fputs(
                "Language Relay: no usable keyboard layout pair. " +
                "Enable \(AppIdentity.defaultSourceID) and \(AppIdentity.defaultTargetID), " +
                "or configure a pair in the Language Relay panel.\n",
                stderr
            )
            exit(2)
        }

        let arguments = CommandLine.arguments
        let capitalization: CapitalizationMode = {
            guard let index = arguments.firstIndex(of: "--capitalization"),
                  arguments.indices.contains(index + 1)
            else { return .preserve }
            return CapitalizationMode(rawValue: arguments[index + 1]) ?? .preserve
        }()
        if arguments.contains("--self-test") {
            exit(SelfTest.run(core: core))
        }
        if arguments.contains("--ui-self-test") {
            let delegate = AppDelegate(core: core)
            guard delegate.runBackgroundUISelfTest() else {
                fputs("FAIL: background UI self-test\n", stderr)
                exit(6)
            }
            print("PASS: background UI self-test; panel=420x604; glyph=54x18; window=none")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--render-ui"), arguments.indices.contains(index + 1) {
            let delegate = AppDelegate(core: core)
            let output = URL(fileURLWithPath: arguments[index + 1])
            exit(delegate.renderBackgroundUIPreview(to: output) ? 0 : 7)
        }
        if let index = arguments.firstIndex(of: "--convert"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertAll(arguments[index + 1], capitalization: capitalization) else { exit(3) }
            print(conversion.text)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--convert-json"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertAll(arguments[index + 1], capitalization: capitalization) else { exit(3) }
            writeJSON(conversion, core: core)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--convert-phrase-json"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertTrailingPhrase(
                arguments[index + 1],
                capitalization: capitalization
            ) else { exit(3) }
            writeJSON(conversion, core: core)
            exit(0)
        }
        if arguments.contains("--status") {
            print("input=\(InputSources.currentID() ?? "unknown")")
            print("accessibility=\(AXIsProcessTrusted())")
            exit(0)
        }
        if arguments.contains("--status-json") || arguments.contains("--doctor-json") {
            let current = InputSources.currentID() ?? "unknown"
            let caramba = !NSRunningApplication.runningApplications(
                withBundleIdentifier: "tech.caramba.switcher"
            ).isEmpty
            var payload: [String: Any] = [
                "schemaVersion": 1,
                "app": AppIdentity.name,
                "version": "2.3.1",
                "inputSourceID": current,
                "accessibilityTrusted": AXIsProcessTrusted(),
                "carambaRunning": caramba,
                "ready": current == core.source.id || current == core.target.id,
                "sourceLayoutID": core.source.id,
                "targetLayoutID": core.target.id,
                "inputSourcesEnabled": [core.source.id, core.target.id],
            ]
            if let blocker = core.blocker {
                payload["blocker"] = blocker
            }
            writeJSONObject(payload)
            exit(0)
        }
        if arguments.contains("--capabilities-json") {
            writeJSONObject([
                "schemaVersion": 1,
                "app": AppIdentity.name,
                "version": "2.3.1",
                "pair": [core.source.id, core.target.id],
                "pairConfigurable": true,
                "scopes": ["word", "phrase"],
                "capitalization": ["preserve", "sentence", "uppercase", "lowercase"],
                "commands": ["convert", "convert-phrase", "switch", "status", "doctor", "setup"],
                "localOnly": true,
                "textLogging": false,
            ])
            exit(0)
        }
        if arguments.contains("--switch") {
            exit(InputSources.toggle(source: core.source.id, target: core.target.id) ? 0 : 4)
        }
        if arguments.contains("--enable-pair") {
            let sourceEnabled = enableInputSource(core.source.id)
            let targetEnabled = enableInputSource(core.target.id)
            exit(sourceEnabled && targetEnabled ? 0 : 4)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(core: core)
        app.delegate = delegate
        app.run()
    }

    /// Backing `language-relay setup`: enables the configured pair as active
    /// macOS input sources (`TISEnableInputSource`), driven by whatever pair
    /// `core` resolved to — never a hard-coded U.S./Russian – PC pair.
    /// Enabling is a one-time explicit setup action the user runs, not
    /// something the app does implicitly on launch.
    private static func enableInputSource(_ id: String) -> Bool {
        guard let source = InputSources.source(withID: id) else { return false }
        if InputSources.isEnabled(id: id) { return true }
        return TISEnableInputSource(source) == noErr
    }

    /// Includes `sourceName`/`targetName` (the layouts' localized names)
    /// alongside the identifiers, so the Hammerspoon bridge can resolve
    /// `hs.keycodes.setLayout`'s target from the payload it already
    /// receives instead of a hard-coded identifier→name mapping.
    private static func writeJSON(_ conversion: Conversion, core: LayoutConversionCore) {
        let targetName = conversion.targetID == core.target.id ? core.target.name : core.source.name
        let sourceName = conversion.sourceID == core.target.id ? core.target.name : core.source.name
        let payload: [String: Any] = [
            "text": conversion.text,
            "sourceID": conversion.sourceID,
            "targetID": conversion.targetID,
            "sourceName": sourceName,
            "targetName": targetName,
        ]
        writeJSONObject(payload)
    }

    private static func writeJSONObject(_ payload: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { exit(5) }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
