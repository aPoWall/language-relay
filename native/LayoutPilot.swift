import AppKit
import ApplicationServices
import Carbon
import Foundation

private enum AppIdentity {
    static let name = "Layout Pilot"
    static let bundleID = "dev.alex.layout-pilot"
    static let usID = "com.apple.keylayout.US"
    static let russianPCID = "com.apple.keylayout.RussianWin"
    static let hammerspoonBridgeMarker = "~/.config/layout-pilot/hammerspoon-bridge"
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
        }
    }
}

private enum InputSources {
    static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(pointer, to: CFString.self) as String
    }

    static func source(withID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return nil }
        return (list as NSArray).firstObject as! TISInputSource?
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
    static func toggle() -> Bool {
        let target = currentID() == AppIdentity.usID ? AppIdentity.russianPCID : AppIdentity.usID
        return select(target)
    }

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

private final class LayoutConversionCore {
    let us: LayoutMap
    let russianPC: LayoutMap

    init?() {
        guard let us = InputSources.layoutMap(id: AppIdentity.usID),
              let russianPC = InputSources.layoutMap(id: AppIdentity.russianPCID)
        else { return nil }
        self.us = us
        self.russianPC = russianPC
    }

    func convertAll(
        _ text: String,
        capitalization: CapitalizationMode = .preserve
    ) -> Conversion? {
        guard let source = detectSource(for: text) else { return nil }
        let target = source.id == us.id ? russianPC : us
        guard let converted = convert(text, from: source, to: target) else { return nil }
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
        let target = phraseSource.id == us.id ? russianPC : us
        guard let converted = convert(phrase, from: phraseSource, to: target) else { return nil }
        return Conversion(
            text: keep + capitalization.apply(to: converted.text),
            sourceID: phraseSource.id,
            targetID: target.id
        )
    }

    private func convert(_ text: String, from source: LayoutMap, to target: LayoutMap) -> Conversion? {
        var result = ""
        var mappedLetters = 0

        for character in text {
            if let stroke = source.characterToStroke[character],
               let targetCharacter = target.strokeToCharacter[stroke] {
                result.append(targetCharacter)
                if character.isLetter { mappedLetters += 1 }
            } else {
                result.append(character)
            }
        }

        guard mappedLetters > 0, result != text else { return nil }
        return Conversion(text: result, sourceID: source.id, targetID: target.id)
    }

    private func detectSource(for text: String) -> LayoutMap? {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return nil }
        let usScore = letters.reduce(0) { $0 + (us.characterToStroke[$1] == nil ? 0 : 1) }
        let russianScore = letters.reduce(0) { $0 + (russianPC.characterToStroke[$1] == nil ? 0 : 1) }
        guard usScore != russianScore else { return nil }
        return usScore > russianScore ? us : russianPC
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
    private let core: LayoutConversionCore

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
    static let width: CGFloat = 480
    static let height: CGFloat = 500
    static let contentWidth: CGFloat = 432
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

private enum LayoutPilotStatusGlyph {
    static func make(russianActive: Bool) -> NSImage {
        let size = NSSize(width: 64, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            drawCell(NSRect(x: 1, y: 1, width: 18, height: 16), text: "A", active: !russianActive)
            drawCell(NSRect(x: 43, y: 1, width: 20, height: 16), text: "РУ", active: russianActive)

            let upper = NSBezierPath()
            upper.move(to: NSPoint(x: 21, y: 11.5))
            upper.line(to: NSPoint(x: 39, y: 11.5))
            upper.line(to: NSPoint(x: 35, y: 15))
            upper.move(to: NSPoint(x: 39, y: 11.5))
            upper.line(to: NSPoint(x: 35, y: 8))
            upper.lineWidth = 1
            upper.stroke()

            let lower = NSBezierPath()
            lower.move(to: NSPoint(x: 41, y: 6.5))
            lower.line(to: NSPoint(x: 23, y: 6.5))
            lower.line(to: NSPoint(x: 27, y: 10))
            lower.move(to: NSPoint(x: 23, y: 6.5))
            lower.line(to: NSPoint(x: 27, y: 3))
            lower.lineWidth = 1
            lower.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Layout Pilot input source"
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
            .font: NSFont.monospacedSystemFont(ofSize: text == "A" ? 9.5 : 7.4, weight: .semibold),
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
    private let core: LayoutConversionCore
    private let fixer: TextFixer
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var monitor: DoubleShiftMonitor!
    private var refreshTimer: Timer?
    private var popover: NSPopover?
    private var lastPopoverCloseAt = Date.distantPast

    private var mode: FixMode {
        get { FixMode(rawValue: defaults.string(forKey: "fixMode") ?? "phrase") ?? .phrase }
        set { defaults.set(newValue.rawValue, forKey: "fixMode") }
    }

    private var soundEnabled: Bool {
        get { defaults.object(forKey: "soundEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    private var soundName: String {
        get {
            let value = defaults.string(forKey: "soundName") ?? "Pop"
            return ["Pop", "Glass", "Ping", "Purr"].contains(value) ? value : "Pop"
        }
        set { defaults.set(newValue, forKey: "soundName") }
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
        statusItem = NSStatusBar.system.statusItem(withLength: 64)
        statusItem.autosaveName = "dev.alex.layout-pilot.status-item.v2"
        statusItem.menu = nil
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.setAccessibilityLabel("Layout Pilot")
        button.setAccessibilityHelp("Left click opens controls. Right click opens quick actions.")
    }

    private func updateStatusButton() {
        let russian = InputSources.currentID() == AppIdentity.russianPCID
        statusItem.button?.image = LayoutPilotStatusGlyph.make(russianActive: russian)
        statusItem.button?.toolTip = "Layout Pilot · ⇧⇧ or clean ⌥ fixes wrong-layout text"
    }

    private var usesHammerspoonBridge: Bool {
        FileManager.default.fileExists(atPath: AppIdentity.hammerspoonBridgeMarker)
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
        root.spacing = 7
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
        ])

        root.addArrangedSubview(label("layout pilot", size: 22, weight: .semibold, color: UI.ink, height: 29))
        root.addArrangedSubview(label("u.s. ⇄ russian – pc · local · no text log", size: 9.5, weight: .semibold, color: UI.muted, height: 16))
        root.addArrangedSubview(hairLine(width: LayoutPilotPanelMetrics.contentWidth))

        let layoutRow = NSStackView()
        layoutRow.orientation = .horizontal
        layoutRow.alignment = .centerY
        layoutRow.spacing = 6
        let current = InputSources.currentID()
        let us = squareButton("A · U.S.", action: #selector(selectUS), width: 190, height: 62)
        us.isActive = current == AppIdentity.usID
        let rail = label("⇄", size: 17, weight: .semibold, color: UI.ink, width: 40, height: 62, centered: true)
        let ru = squareButton("РУ · PC", action: #selector(selectRussian), width: 190, height: 62)
        ru.isActive = current == AppIdentity.russianPCID
        layoutRow.addArrangedSubview(us)
        layoutRow.addArrangedSubview(rail)
        layoutRow.addArrangedSubview(ru)
        root.addArrangedSubview(layoutRow)

        root.addArrangedSubview(sectionHeader("correction scope", width: LayoutPilotPanelMetrics.contentWidth))
        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.spacing = 6
        let phrase = squareButton("last phrase", action: #selector(setPhraseMode), width: 213, height: 31)
        phrase.isActive = mode == .phrase
        let word = squareButton("last word", action: #selector(setLastWordMode), width: 213, height: 31)
        word.isActive = mode == .lastWord
        modeRow.addArrangedSubview(phrase)
        modeRow.addArrangedSubview(word)
        root.addArrangedSubview(modeRow)

        root.addArrangedSubview(sectionHeader("capitalization", width: LayoutPilotPanelMetrics.contentWidth))
        let capitalizationRow = NSStackView()
        capitalizationRow.orientation = .horizontal
        capitalizationRow.spacing = 6
        let preserve = squareButton("preserve", action: #selector(setCapitalizationPreserve), width: 140, height: 31)
        preserve.isActive = capitalization == .preserve
        let sentence = squareButton("sentence", action: #selector(setCapitalizationSentence), width: 140, height: 31)
        sentence.isActive = capitalization == .sentence
        let uppercase = squareButton("uppercase", action: #selector(setCapitalizationUppercase), width: 140, height: 31)
        uppercase.isActive = capitalization == .uppercase
        capitalizationRow.addArrangedSubview(preserve)
        capitalizationRow.addArrangedSubview(sentence)
        capitalizationRow.addArrangedSubview(uppercase)
        root.addArrangedSubview(capitalizationRow)

        root.addArrangedSubview(sectionHeader("triggers · clean modifier taps only", width: LayoutPilotPanelMetrics.contentWidth))
        let triggerRow = NSStackView()
        triggerRow.orientation = .horizontal
        triggerRow.spacing = 6
        let shift = squareButton("⇧ ⇧ · double shift", action: #selector(toggleShift), width: 213, height: 37)
        shift.isActive = shiftEnabled
        let option = squareButton("⌥ · option tap", action: #selector(toggleOption), width: 213, height: 37)
        option.isActive = optionEnabled
        triggerRow.addArrangedSubview(shift)
        triggerRow.addArrangedSubview(option)
        root.addArrangedSubview(triggerRow)

        root.addArrangedSubview(sectionHeader("feedback", width: LayoutPilotPanelMetrics.contentWidth))
        let soundRow = NSStackView()
        soundRow.orientation = .horizontal
        soundRow.spacing = 6
        let pop = squareButton("pop", action: #selector(setSoundPop), width: 81.6, height: 31)
        pop.isActive = soundEnabled && soundName == "Pop"
        let glass = squareButton("glass", action: #selector(setSoundGlass), width: 81.6, height: 31)
        glass.isActive = soundEnabled && soundName == "Glass"
        let ping = squareButton("ping", action: #selector(setSoundPing), width: 81.6, height: 31)
        ping.isActive = soundEnabled && soundName == "Ping"
        let purr = squareButton("purr", action: #selector(setSoundPurr), width: 81.6, height: 31)
        purr.isActive = soundEnabled && soundName == "Purr"
        let silent = squareButton("silent", action: #selector(disableSound), width: 81.6, height: 31)
        silent.isActive = !soundEnabled
        soundRow.addArrangedSubview(pop)
        soundRow.addArrangedSubview(glass)
        soundRow.addArrangedSubview(ping)
        soundRow.addArrangedSubview(purr)
        soundRow.addArrangedSubview(silent)
        root.addArrangedSubview(soundRow)

        let diagnostic = NSView()
        diagnostic.translatesAutoresizingMaskIntoConstraints = false
        diagnostic.wantsLayer = true
        diagnostic.layer?.backgroundColor = UI.fill.cgColor
        diagnostic.layer?.borderColor = UI.hair.cgColor
        diagnostic.layer?.borderWidth = 1
        diagnostic.widthAnchor.constraint(equalToConstant: LayoutPilotPanelMetrics.contentWidth).isActive = true
        diagnostic.heightAnchor.constraint(equalToConstant: 43).isActive = true
        let diagnosticStack = NSStackView()
        diagnosticStack.orientation = .vertical
        diagnosticStack.alignment = .leading
        diagnosticStack.spacing = 2
        diagnosticStack.translatesAutoresizingMaskIntoConstraints = false
        diagnostic.addSubview(diagnosticStack)
        NSLayoutConstraint.activate([
            diagnosticStack.leadingAnchor.constraint(equalTo: diagnostic.leadingAnchor, constant: 10),
            diagnosticStack.trailingAnchor.constraint(equalTo: diagnostic.trailingAnchor, constant: -10),
            diagnosticStack.centerYAnchor.constraint(equalTo: diagnostic.centerYAnchor),
        ])
        let bridge = usesHammerspoonBridge ? "bridge · hammerspoon online" : "bridge · native fallback"
        diagnosticStack.addArrangedSubview(label(bridge, size: 8.8, weight: .semibold, color: UI.ink, height: 13))
        diagnosticStack.addArrangedSubview(label("last fix · \(bridgeStatus())", size: 8.2, weight: .semibold, color: UI.muted, height: 13))
        root.addArrangedSubview(diagnostic)

        root.addArrangedSubview(label(
            "caps tap switch · ⇧⇧ / ⌥ fix · esc close",
            size: 8.2,
            weight: .semibold,
            color: UI.muted,
            height: 14
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
        let panel = makePanelContent()
        panel.layoutSubtreeIfNeeded()
        let glyph = LayoutPilotStatusGlyph.make(russianActive: false)
        return panel.frame.size == NSSize(
            width: LayoutPilotPanelMetrics.width,
            height: LayoutPilotPanelMetrics.height
        )
            && panel.window == nil
            && !panel.subviews.isEmpty
            && glyph.size == NSSize(width: 64, height: 18)
            && glyph.isTemplate
    }

    private func showNativeMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "open layout pilot", action: #selector(openPanelFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let toggle = NSMenuItem(title: "switch layout", action: #selector(toggleLayout), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "quit layout pilot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.statusItem.menu = nil }
    }

    private func performFix() {
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
        _ = InputSources.toggle()
        updateStatusButton()
        rebuildPopoverContent()
    }

    @objc private func selectUS() {
        _ = InputSources.select(AppIdentity.usID)
        updateStatusButton()
        rebuildPopoverContent()
    }

    @objc private func selectRussian() {
        _ = InputSources.select(AppIdentity.russianPCID)
        updateStatusButton()
        rebuildPopoverContent()
    }

    @objc private func setPhraseMode() { mode = .phrase; reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setLastWordMode() { mode = .lastWord; reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setCapitalizationPreserve() { setCapitalization(.preserve) }
    @objc private func setCapitalizationSentence() { setCapitalization(.sentence) }
    @objc private func setCapitalizationUppercase() { setCapitalization(.uppercase) }
    @objc private func toggleShift() { shiftEnabled.toggle(); reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func toggleOption() { optionEnabled.toggle(); reloadBridgeSettings(); rebuildPopoverContent() }
    @objc private func setSoundPop() { selectSound("Pop") }
    @objc private func setSoundGlass() { selectSound("Glass") }
    @objc private func setSoundPing() { selectSound("Ping") }
    @objc private func setSoundPurr() { selectSound("Purr") }
    @objc private func disableSound() { soundEnabled = false; reloadBridgeSettings(); rebuildPopoverContent() }

    private func setCapitalization(_ value: CapitalizationMode) {
        capitalization = value
        reloadBridgeSettings()
        rebuildPopoverContent()
    }

    private func selectSound(_ name: String) {
        soundName = name
        soundEnabled = true
        reloadBridgeSettings()
        playSelectedSound()
        rebuildPopoverContent()
    }

    private func playSelectedSound() {
        guard soundEnabled, let sound = NSSound(named: soundName) else { return }
        sound.volume = 0.82
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

        guard failures.isEmpty else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            return 1
        }
        print("PASS: 12 layout conversion tests; \(core.us.name) ↔ \(core.russianPC.name)")
        return 0
    }
}

@main
private struct LayoutPilotMain {
    @MainActor
    static func main() {
        guard let core = LayoutConversionCore() else {
            fputs("Layout Pilot: U.S. and Russian – PC input sources are required.\n", stderr)
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
            print("PASS: background UI self-test; panel=480x500; glyph=64x18; window=none")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--convert"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertAll(arguments[index + 1], capitalization: capitalization) else { exit(3) }
            print(conversion.text)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--convert-json"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertAll(arguments[index + 1], capitalization: capitalization) else { exit(3) }
            writeJSON(conversion)
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--convert-phrase-json"), arguments.indices.contains(index + 1) {
            guard let conversion = core.convertTrailingPhrase(
                arguments[index + 1],
                capitalization: capitalization
            ) else { exit(3) }
            writeJSON(conversion)
            exit(0)
        }
        if arguments.contains("--status") {
            print("input=\(InputSources.currentID() ?? "unknown")")
            print("accessibility=\(AXIsProcessTrusted())")
            exit(0)
        }
        if arguments.contains("--switch") {
            exit(InputSources.toggle() ? 0 : 4)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(core: core)
        app.delegate = delegate
        app.run()
    }

    private static func writeJSON(_ conversion: Conversion) {
        let payload = ["text": conversion.text, "sourceID": conversion.sourceID, "targetID": conversion.targetID]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { exit(5) }
        FileHandle.standardOutput.write(data)
    }
}
