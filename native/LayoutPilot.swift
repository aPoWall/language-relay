import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation

private enum AppIdentity {
    static let name = "Language Relay"
    static let version = "2.3.2"
    static let bundleID = "dev.alex.layout-pilot"
    static let launchAgentLabel = "dev.alex.layout-pilot"
    static let usID = "com.apple.keylayout.US"
    static let russianPCID = "com.apple.keylayout.RussianWin"
    static let hammerspoonBundleID = "org.hammerspoon.Hammerspoon"
    static let bridgeLoadLine = "dofile(os.getenv(\"HOME\") .. \"/.config/language-relay/hammerspoon.lua\")"
    static let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    static let bridgePath = homeDirectory
        .appendingPathComponent(".config/language-relay/hammerspoon.lua")
        .path
    static let hammerspoonInitPath = homeDirectory
        .appendingPathComponent(".hammerspoon/init.lua")
        .path
    static let hammerspoonBridgeMarker = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/language-relay/hammerspoon-bridge")
        .path
}

private struct BoundedProcessResult {
    let output: String
    let status: Int32
    let timedOut: Bool
}

private enum BoundedProcess {
    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 0.35
    ) -> BoundedProcessResult? {
        let process = Process()
        let output = Pipe()
        let finished = DispatchSemaphore(value: 0)
        let outputRead = DispatchSemaphore(value: 0)
        let outputBox = OutputBox()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        DispatchQueue.global(qos: .utility).async {
            outputBox.data = output.fileHandleForReading.readDataToEndOfFile()
            outputRead.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.10) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.10)
            }
            _ = outputRead.wait(timeout: .now() + 0.20)
            return BoundedProcessResult(
                output: String(data: outputBox.data, encoding: .utf8) ?? "",
                status: process.terminationStatus,
                timedOut: true
            )
        }

        _ = outputRead.wait(timeout: .now() + 0.20)
        return BoundedProcessResult(
            output: String(data: outputBox.data, encoding: .utf8) ?? "",
            status: process.terminationStatus,
            timedOut: false
        )
    }
}

private struct HammerspoonHealth {
    let ipcAvailable: Bool
    let executableFound: Bool
    let accessibilityTrusted: Bool?
    let inputTapEnabled: Bool
    let bridgeVersion: String?
    let lastStatus: String?
    let timedOut: Bool

    var bridgeActive: Bool {
        ipcAvailable && inputTapEnabled && bridgeVersion == AppIdentity.version
    }
}

private enum HammerspoonIPC {
    private static let candidateExecutables = ["/opt/homebrew/bin/hs", "/usr/local/bin/hs"]

    static var executable: String? {
        candidateExecutables.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool {
        executable != nil
    }

    static func run(_ command: String, timeout: TimeInterval = 0.35) -> BoundedProcessResult? {
        guard let executable else { return nil }
        return BoundedProcess.run(executable, arguments: ["-c", command], timeout: timeout)
    }

    static func evaluate(_ command: String, timeout: TimeInterval = 0.35) -> String? {
        guard let result = run(command, timeout: timeout),
              !result.timedOut,
              result.status == 0
        else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func health(timeout: TimeInterval = 0.35) -> HammerspoonHealth {
        guard executable != nil else {
            return HammerspoonHealth(
                ipcAvailable: false,
                executableFound: false,
                accessibilityTrusted: nil,
                inputTapEnabled: false,
                bridgeVersion: nil,
                lastStatus: nil,
                timedOut: false
            )
        }
        let command = """
        local accessibility = tostring(hs.accessibilityState())
        local inputTap = tostring(layoutPilotInputTap and layoutPilotInputTap:isEnabled() or false)
        local bridgeVersion = tostring(hs.settings.get('layout_pilot_bridge_ver') or '')
        local lastStatus = tostring(hs.settings.get('layout_pilot_last_status') or 'ready')
        return table.concat({accessibility, inputTap, bridgeVersion, lastStatus}, '|')
        """
        guard let result = run(command, timeout: timeout) else {
            return HammerspoonHealth(
                ipcAvailable: false,
                executableFound: true,
                accessibilityTrusted: nil,
                inputTapEnabled: false,
                bridgeVersion: nil,
                lastStatus: nil,
                timedOut: false
            )
        }
        guard !result.timedOut, result.status == 0 else {
            return HammerspoonHealth(
                ipcAvailable: false,
                executableFound: true,
                accessibilityTrusted: nil,
                inputTapEnabled: false,
                bridgeVersion: nil,
                lastStatus: nil,
                timedOut: result.timedOut
            )
        }
        let parts = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count >= 4 else {
            return HammerspoonHealth(
                ipcAvailable: false,
                executableFound: true,
                accessibilityTrusted: nil,
                inputTapEnabled: false,
                bridgeVersion: nil,
                lastStatus: nil,
                timedOut: false
            )
        }
        let accessibility: Bool? = {
            switch parts[0] {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }()
        let bridgeVersion = parts[2].isEmpty ? nil : parts[2]
        let lastStatus = parts[3].isEmpty ? nil : parts[3]
        return HammerspoonHealth(
            ipcAvailable: true,
            executableFound: true,
            accessibilityTrusted: accessibility,
            inputTapEnabled: parts[1] == "true",
            bridgeVersion: bridgeVersion,
            lastStatus: lastStatus,
            timedOut: false
        )
    }
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

    static func source(withID id: String, includeAllInstalled: Bool = false) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue() else {
            return nil
        }
        return (list as NSArray).firstObject as! TISInputSource?
    }

    static func isEnabled(_ id: String) -> Bool {
        source(withID: id) != nil
    }

    @discardableResult
    static func enable(_ id: String) -> Bool {
        if isEnabled(id) { return true }
        guard let source = source(withID: id, includeAllInstalled: true) else { return false }
        return TISEnableInputSource(source) == noErr
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
        guard let source = source(withID: id, includeAllInstalled: true),
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

private enum BridgeConfiguration {
    static func containsLoadLine(_ contents: String) -> Bool {
        contents.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == AppIdentity.bridgeLoadLine
        }
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: AppIdentity.bridgePath)
    }

    static var isLoaded: Bool {
        guard let contents = try? String(contentsOfFile: AppIdentity.hammerspoonInitPath, encoding: .utf8) else {
            return false
        }
        return containsLoadLine(contents)
    }

    @discardableResult
    static func addLoadLineIfNeeded() -> Bool {
        if isLoaded { return true }

        let fileManager = FileManager.default
        let initURL = URL(fileURLWithPath: AppIdentity.hammerspoonInitPath)
        let directory = initURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: initURL.path) {
                guard fileManager.createFile(atPath: initURL.path, contents: nil) else { return false }
            }

            let existing = (try? String(contentsOf: initURL, encoding: .utf8)) ?? ""
            let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
            let handle = try FileHandle(forWritingTo: initURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\(separator)\(AppIdentity.bridgeLoadLine)\n".utf8))
            return true
        } catch {
            return false
        }
    }
}

private struct DoctorBlocker {
    let code: String
    let message: String
    let fix: String

    var jsonObject: [String: String] {
        ["code": code, "message": message, "fix": fix]
    }
}

private struct InstallationHealth {
    let hammerspoonInstalled: Bool
    let bridgeInstalled: Bool
    let bridgeLoaded: Bool
    let bridgeConfigured: Bool
    let usInputSourceEnabled: Bool
    let russianPCInputSourceEnabled: Bool
    let accessibilityTrusted: Bool
    let hammerspoonAccessibilityTrusted: Bool?
    let agentLoaded: Bool
    let appRunning: Bool
    let carambaRunning: Bool
    let currentInputSourceID: String
    let bridgeHealth: HammerspoonHealth

    static func collect(bridgeHealth providedBridgeHealth: HammerspoonHealth? = nil) -> InstallationHealth {
        let bridgeHealth = providedBridgeHealth ?? HammerspoonIPC.health()
        return InstallationHealth(
            hammerspoonInstalled: NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: AppIdentity.hammerspoonBundleID
            ) != nil || bridgeHealth.executableFound,
            bridgeInstalled: BridgeConfiguration.isInstalled,
            bridgeLoaded: BridgeConfiguration.isLoaded,
            bridgeConfigured: FileManager.default.fileExists(atPath: AppIdentity.hammerspoonBridgeMarker),
            usInputSourceEnabled: InputSources.isEnabled(AppIdentity.usID),
            russianPCInputSourceEnabled: InputSources.isEnabled(AppIdentity.russianPCID),
            accessibilityTrusted: AXIsProcessTrusted(),
            hammerspoonAccessibilityTrusted: bridgeHealth.accessibilityTrusted,
            agentLoaded: launchAgentIsLoaded(),
            appRunning: backgroundAppIsRunning(),
            carambaRunning: !NSRunningApplication.runningApplications(
                withBundleIdentifier: "tech.caramba.switcher"
            ).isEmpty,
            currentInputSourceID: InputSources.currentID() ?? "unknown",
            bridgeHealth: bridgeHealth
        )
    }

    var bridgeActive: Bool {
        bridgeHealth.bridgeActive
    }

    var accessibilityOwner: String {
        bridgeInstalled || bridgeLoaded || bridgeConfigured ? "Hammerspoon" : AppIdentity.name
    }

    var effectiveAccessibilityTrusted: Bool {
        accessibilityOwner == "Hammerspoon" ? hammerspoonAccessibilityTrusted == true : accessibilityTrusted
    }

    var bridgeVerificationBlockerCode: String {
        if bridgeHealth.timedOut { return "hammerspoon-ipc-timeout" }
        if !bridgeHealth.executableFound || !bridgeHealth.ipcAvailable { return "hammerspoon-ipc-unavailable" }
        if bridgeHealth.bridgeVersion != AppIdentity.version { return "bridge-version-mismatch" }
        return "bridge-not-active"
    }

    var blockers: [DoctorBlocker] {
        var result: [DoctorBlocker] = []
        if !hammerspoonInstalled {
            result.append(DoctorBlocker(
                code: "hammerspoon-not-installed",
                message: "Hammerspoon is not installed.",
                fix: "Install it with: brew install --cask hammerspoon"
            ))
        }
        if !bridgeInstalled {
            result.append(DoctorBlocker(
                code: "bridge-not-installed",
                message: "The Language Relay Hammerspoon bridge is missing.",
                fix: "Run: language-relay install"
            ))
        }
        if !bridgeLoaded {
            result.append(DoctorBlocker(
                code: "bridge-not-loaded",
                message: "Hammerspoon is not loading the Language Relay bridge.",
                fix: "Run: language-relay setup, then reload Hammerspoon."
            ))
        }
        if bridgeInstalled && bridgeLoaded {
            if bridgeHealth.timedOut {
                result.append(DoctorBlocker(
                    code: "hammerspoon-ipc-timeout",
                    message: "Hammerspoon did not answer before the safety timeout.",
                    fix: "Reload Hammerspoon, then run: language-relay setup"
                ))
            } else if !bridgeHealth.ipcAvailable {
                result.append(DoctorBlocker(
                    code: "hammerspoon-ipc-unavailable",
                    message: "Hammerspoon bridge execution could not be verified through hs.ipc.",
                    fix: "Start or reload Hammerspoon. If needed, run hs.ipc.cliInstall() in the Hammerspoon console, then run: language-relay setup"
                ))
            } else {
                if bridgeHealth.bridgeVersion != AppIdentity.version {
                    result.append(DoctorBlocker(
                        code: "bridge-version-mismatch",
                        message: "Hammerspoon is running a stale Language Relay bridge.",
                        fix: "Run: language-relay setup, then reload Hammerspoon."
                    ))
                }
                if !bridgeHealth.inputTapEnabled {
                    result.append(DoctorBlocker(
                        code: "bridge-not-active",
                        message: "The Hammerspoon bridge loaded, but its gesture tap is not active.",
                        fix: "Enable Hammerspoon in System Settings > Privacy & Security > Accessibility, then reload Hammerspoon."
                    ))
                }
            }
        }
        if !usInputSourceEnabled {
            result.append(DoctorBlocker(
                code: "input-source-us-not-enabled",
                message: "The U.S. input source is not enabled.",
                fix: "Run: language-relay setup"
            ))
        }
        if !russianPCInputSourceEnabled {
            result.append(DoctorBlocker(
                code: "input-source-russian-pc-not-enabled",
                message: "The Russian – PC input source is not enabled.",
                fix: "Run: language-relay setup"
            ))
        }
        // While the bridge owns the gestures, Hammerspoon is the process that needs
        // Accessibility. Language Relay never asks for it in that mode, so it never
        // appears in the Accessibility list and demanding it there sends people looking
        // for a row that cannot exist.
        if accessibilityOwner == "Hammerspoon" {
            if bridgeHealth.ipcAvailable, hammerspoonAccessibilityTrusted == false {
                result.append(DoctorBlocker(
                    code: "accessibility-not-granted-hammerspoon",
                    message: "Hammerspoon does not have Accessibility permission, so the gesture tap cannot start.",
                    fix: "Enable Hammerspoon in System Settings > Privacy & Security > Accessibility. Language Relay is not listed there while the bridge owns the gestures."
                ))
            } else if bridgeHealth.ipcAvailable, hammerspoonAccessibilityTrusted == nil {
                result.append(DoctorBlocker(
                    code: "accessibility-unverified-hammerspoon",
                    message: "Hammerspoon Accessibility permission could not be verified.",
                    fix: "Reload Hammerspoon, then run: language-relay setup"
                ))
            }
        } else if !accessibilityTrusted {
            result.append(DoctorBlocker(
                code: "accessibility-not-granted",
                message: "Accessibility permission is not granted to Language Relay.",
                fix: "Run: language-relay setup, then grant Accessibility to Language Relay."
            ))
        }
        if !agentLoaded {
            result.append(DoctorBlocker(
                code: "launch-agent-not-loaded",
                message: "The Language Relay LaunchAgent is not loaded.",
                fix: "Run: language-relay install"
            ))
        }
        if !appRunning {
            result.append(DoctorBlocker(
                code: "app-not-running",
                message: "The Language Relay background app is not running.",
                fix: "Run: launchctl kickstart -k gui/\(getuid())/\(AppIdentity.launchAgentLabel)"
            ))
        }
        return result
    }

    var doctorPayload: [String: Any] {
        [
            "schemaVersion": 2,
            "app": AppIdentity.name,
            "version": AppIdentity.version,
            "inputSourceID": currentInputSourceID,
            "accessibilityTrusted": effectiveAccessibilityTrusted,
            "carambaRunning": carambaRunning,
            "ready": blockers.isEmpty,
            "hammerspoonInstalled": hammerspoonInstalled,
            "hammerspoonAccessibilityTrusted": hammerspoonAccessibilityTrusted.map { $0 as Any } ?? NSNull(),
            "bridgeInstalled": bridgeInstalled,
            "bridgeActive": bridgeActive,
            "bridgeLoaded": bridgeLoaded,
            "inputSourcesEnabled": [
                "us": usInputSourceEnabled,
                "russianPC": russianPCInputSourceEnabled,
            ],
            "inputSources": [
                "usAvailable": usInputSourceEnabled,
                "russianPCAvailable": russianPCInputSourceEnabled,
                "currentSupported": currentInputSourceID == AppIdentity.usID
                    || currentInputSourceID == AppIdentity.russianPCID,
            ],
            "accessibility": [
                "owner": accessibilityOwner,
                "trusted": accessibilityOwner == "Hammerspoon"
                    ? hammerspoonAccessibilityTrusted.map { $0 as Any } ?? NSNull()
                    : accessibilityTrusted,
            ],
            "bridge": [
                "configured": bridgeConfigured,
                "installed": bridgeInstalled,
                "loaded": bridgeLoaded,
                "active": bridgeActive,
                "ipcAvailable": bridgeHealth.ipcAvailable,
                "ipcTimedOut": bridgeHealth.timedOut,
                "inputTapEnabled": bridgeHealth.inputTapEnabled,
                "version": bridgeHealth.bridgeVersion.map { $0 as Any } ?? NSNull(),
                "lastStatus": bridgeHealth.lastStatus.map { $0 as Any } ?? NSNull(),
            ],
            "runtime": [
                "launchAgentLoaded": agentLoaded,
                "appRunning": appRunning,
                "installedBinaryPresent": FileManager.default.isExecutableFile(
                    atPath: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications/Language Relay.app/Contents/MacOS/LanguageRelay")
                        .path
                ),
            ],
            "agentLoaded": agentLoaded,
            "appRunning": appRunning,
            "blockers": blockers.map(\.jsonObject),
        ]
    }

    private static func launchAgentIsLoaded() -> Bool {
        guard let result = BoundedProcess.run(
            "/bin/launchctl",
            arguments: ["print", "gui/\(getuid())/\(AppIdentity.launchAgentLabel)"],
            timeout: 0.35
        ) else { return false }
        return !result.timedOut && result.status == 0
    }

    static func backgroundAppIsRunning() -> Bool {
        let mine = NSRunningApplication.current.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .contains { $0.processIdentifier != mine && !$0.isTerminated }
    }
}

private enum Setup {
    static func run() -> Int32 {
        _ = InputSources.enable(AppIdentity.usID)
        _ = InputSources.enable(AppIdentity.russianPCID)
        _ = BridgeConfiguration.addLoadLineIfNeeded()

        var bridgeHealth: HammerspoonHealth?
        if BridgeConfiguration.isLoaded, HammerspoonIPC.isAvailable {
            _ = HammerspoonIPC.evaluate("hs.reload(); return 'reload-requested'", timeout: 0.25)
            bridgeHealth = waitForBridgeActivation()
        }

        var health = InstallationHealth.collect(bridgeHealth: bridgeHealth)
        if health.accessibilityOwner == "Hammerspoon" {
            // Prompting here would register this process, not Hammerspoon, so only
            // open the pane and let the checklist name the row to enable.
            if health.hammerspoonAccessibilityTrusted != true { openAccessibilitySettings() }
        } else if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            openAccessibilitySettings()
        }

        if health.agentLoaded && !health.appRunning {
            for _ in 0..<20 where !InstallationHealth.backgroundAppIsRunning() {
                Thread.sleep(forTimeInterval: 0.05)
            }
            health = InstallationHealth.collect()
        }
        printChecklist(health)
        return health.blockers.isEmpty ? 0 : 1
    }

    private static func waitForBridgeActivation() -> HammerspoonHealth {
        var health = HammerspoonIPC.health(timeout: 0.20)
        for _ in 0..<4 where !health.bridgeActive {
            Thread.sleep(forTimeInterval: 0.04)
            health = HammerspoonIPC.health(timeout: 0.20)
        }
        return health
    }

    private static func printChecklist(_ health: InstallationHealth) {
        let blockers = Dictionary(uniqueKeysWithValues: health.blockers.map { ($0.code, $0) })
        var checks: [(Bool, String, String)] = [
            (health.hammerspoonInstalled, "Hammerspoon is installed", "hammerspoon-not-installed"),
            (health.bridgeInstalled, "Language Relay bridge is installed", "bridge-not-installed"),
            (health.bridgeLoaded, "Hammerspoon loads the Language Relay bridge", "bridge-not-loaded"),
            (health.usInputSourceEnabled, "U.S. input source is enabled", "input-source-us-not-enabled"),
            (health.russianPCInputSourceEnabled, "Russian – PC input source is enabled", "input-source-russian-pc-not-enabled"),
        ]
        if health.bridgeInstalled && health.bridgeLoaded {
            checks.append((
                health.bridgeActive,
                "Hammerspoon bridge execution is verified",
                health.bridgeVerificationBlockerCode
            ))
        }
        if health.accessibilityOwner == "Hammerspoon" {
            checks.append((
                health.hammerspoonAccessibilityTrusted == true,
                "Hammerspoon has Accessibility permission",
                health.hammerspoonAccessibilityTrusted == nil
                    ? "accessibility-unverified-hammerspoon"
                    : "accessibility-not-granted-hammerspoon"
            ))
        } else {
            checks.append((health.accessibilityTrusted, "Accessibility permission is granted", "accessibility-not-granted"))
        }
        checks.append((health.agentLoaded, "Language Relay LaunchAgent is loaded", "launch-agent-not-loaded"))
        checks.append((health.appRunning, "Language Relay background app is running", "app-not-running"))

        for (complete, description, code) in checks {
            if complete {
                print("✓ \(description)")
            } else if let blocker = blockers[code] {
                print("✗ \(blocker.message)")
                print("  fix: \(blocker.fix)")
            } else {
                print("? \(description) could not be verified")
                print("  fix: Start Hammerspoon, then run: language-relay setup")
            }
        }
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
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
    static let width: CGFloat = 420
    static let height: CGFloat = 408
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
    private let core: LayoutConversionCore
    private let fixer: TextFixer
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var monitor: DoubleShiftMonitor!
    private var refreshTimer: Timer?
    private var popover: NSPopover?
    private var lastPopoverCloseAt = Date.distantPast
    private var previewSound: NSSound?
    private var lastObservedInputID: String?
    private var setupExpanded = false

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
        let russian = currentID == AppIdentity.russianPCID
        statusItem.button?.image = LayoutPilotStatusGlyph.make(russianActive: russian)
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
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -8),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        header.widthAnchor.constraint(equalToConstant: LayoutPilotPanelMetrics.contentWidth).isActive = true
        header.heightAnchor.constraint(equalToConstant: 43).isActive = true
        let identity = NSStackView()
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 0
        identity.addArrangedSubview(label("language relay", size: 17, weight: .semibold, color: UI.ink, width: 252, height: 23))
        identity.addArrangedSubview(label("instrument 02 · local bridge · v\(AppIdentity.version)", size: 8.3, weight: .semibold, color: UI.muted, width: 252, height: 12))
        header.addArrangedSubview(identity)
        header.addArrangedSubview(flexSpacer())
        header.addArrangedSubview(stateReadout(panelHealthLabel, width: 118, height: 28, textSize: 8.4))
        root.addArrangedSubview(header)
        root.addArrangedSubview(hairLine(width: LayoutPilotPanelMetrics.contentWidth))

        root.addArrangedSubview(sectionHeader("active layout", width: LayoutPilotPanelMetrics.contentWidth))
        let layoutRow = NSStackView()
        layoutRow.orientation = .horizontal
        layoutRow.alignment = .centerY
        layoutRow.spacing = 6
        let current = InputSources.currentID()
        let currentLabel = current == AppIdentity.russianPCID
            ? "a ⇄ [ру] · russian – pc"
            : "[a] ⇄ ру · u.s."
        let state = stateReadout(currentLabel, width: 340, height: 36, textSize: 10.4)
        let toggle = squareButton("⇄", action: #selector(toggleLayout), width: 42, height: 36)
        toggle.toolTip = "switch input source"
        toggle.setAccessibilityHelp("Switch between U.S. and Russian – PC")
        layoutRow.addArrangedSubview(state)
        layoutRow.addArrangedSubview(toggle)
        root.addArrangedSubview(layoutRow)

        root.addArrangedSubview(sectionHeader("correction scope", width: LayoutPilotPanelMetrics.contentWidth))
        root.addArrangedSubview(ShaperSegmentedControl(
            items: [
                .init("last phrase", help: "Repair the trailing language run"),
                .init("last word", help: "Repair one token"),
            ],
            selectedIndex: mode == .phrase ? 0 : 1,
            width: LayoutPilotPanelMetrics.contentWidth
        ) { [weak self] index in
            index == 0 ? self?.setPhraseMode() : self?.setLastWordMode()
        })

        root.addArrangedSubview(sectionHeader("letter case", width: LayoutPilotPanelMetrics.contentWidth))
        let caseIndex: Int = switch capitalization {
        case .preserve: 0
        case .sentence: 1
        case .uppercase: 2
        case .lowercase: 3
        }
        root.addArrangedSubview(ShaperSegmentedControl(
            items: [
                .init("aA preserve", help: "Keep original capitalization", preservesCase: true),
                .init("Aa sentence", help: "Uppercase the first letter", preservesCase: true),
                .init("AA upper", help: "Uppercase every letter", preservesCase: true),
                .init("aa lower", help: "Lowercase every letter", preservesCase: true),
            ],
            selectedIndex: caseIndex,
            width: LayoutPilotPanelMetrics.contentWidth
        ) { [weak self] index in
            let values: [CapitalizationMode] = [.preserve, .sentence, .uppercase, .lowercase]
            self?.setCapitalization(values[index])
        })

        root.addArrangedSubview(sectionHeader("triggers · standalone modifier taps", width: LayoutPilotPanelMetrics.contentWidth))
        let triggerRow = NSStackView()
        triggerRow.orientation = .horizontal
        triggerRow.spacing = 6
        let shift = squareButton("⇧⇧ · double shift", action: #selector(toggleShift), width: 191, height: 30)
        shift.isActive = shiftEnabled
        shift.setAccessibilityHelp("Enable or disable Double Shift repair")
        let option = squareButton("⌥ · clean option", action: #selector(toggleOption), width: 191, height: 30)
        option.isActive = optionEnabled
        option.setAccessibilityHelp("Enable or disable clean Option repair")
        triggerRow.addArrangedSubview(shift)
        triggerRow.addArrangedSubview(option)
        root.addArrangedSubview(triggerRow)

        root.addArrangedSubview(sectionHeader("feedback · cue + level", width: LayoutPilotPanelMetrics.contentWidth))
        let feedbackRow = NSStackView()
        feedbackRow.orientation = .horizontal
        feedbackRow.spacing = 6
        let cueLabel = soundEnabled ? "cue · \(soundName) · ▾" : "cue · muted · ▾"
        let cue = squareButton(cueLabel, action: #selector(showSoundMenu(_:)), width: 191, height: 32)
        cue.isActive = soundEnabled
        cue.setAccessibilityHelp("Choose one of eight feedback cues")
        feedbackRow.addArrangedSubview(cue)
        let levelIndex: Int = switch soundLevel {
        case .silent: 0
        case .quiet: 1
        case .balanced: 2
        case .full: 3
        }
        feedbackRow.addArrangedSubview(ShaperSegmentedControl(
            items: [
                .init("00", help: "Mute feedback"),
                .init("25", help: "Low feedback level"),
                .init("55", help: "Medium feedback level"),
                .init("82", help: "High feedback level"),
            ],
            selectedIndex: levelIndex,
            width: 191
        ) { [weak self] index in
            let values: [FeedbackLevel] = [.silent, .quiet, .balanced, .full]
            self?.selectLevel(values[index])
        })
        root.addArrangedSubview(feedbackRow)

        root.addArrangedSubview(setupDisclosure())

        root.addArrangedSubview(label(
            "caps · switch   ⇧⇧ / clean ⌥ · repair   esc · close",
            size: 8.0,
            weight: .semibold,
            color: UI.muted,
            height: 13
        ))
        return content
    }

    private var panelHealthLabel: String {
        if carambaRunning { return "paused · owner" }
        if !fixer.hasAccessibilityPermission { return "setup · required" }
        return usesHammerspoonBridge ? "bridge · ready" : "native · ready"
    }

    private func setupDisclosure() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.widthAnchor.constraint(equalToConstant: LayoutPilotPanelMetrics.contentWidth).isActive = true
        host.heightAnchor.constraint(equalToConstant: 48).isActive = true

        if !setupExpanded {
            let suffix = panelHealthLabel.contains("required") || carambaRunning ? "action · show" : "ready · show"
            let button = squareButton("setup + blockers · \(suffix)", action: #selector(toggleSetupDisclosure), width: LayoutPilotPanelMetrics.contentWidth, height: 32)
            button.setAccessibilityHelp("Show setup and blocker details")
            host.addSubview(button)
            button.topAnchor.constraint(equalTo: host.topAnchor).isActive = true
            return host
        }

        host.wantsLayer = true
        host.layer?.backgroundColor = UI.fill.cgColor
        host.layer?.borderColor = UI.hair.cgColor
        host.layer?.borderWidth = 1
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])

        let message: String
        if carambaRunning {
            message = "blocked · caramba owns repair gestures"
        } else if !fixer.hasAccessibilityPermission {
            message = "blocked · accessibility permission required"
        } else {
            let bridge = usesHammerspoonBridge ? "hammerspoon bridge" : "native bridge"
            message = "ready · \(bridge) · last \(bridgeStatus())"
        }
        stack.addArrangedSubview(label(message, size: 8.1, weight: .semibold, color: UI.ink, width: 270, height: 14))
        stack.addArrangedSubview(flexSpacer())
        if !fixer.hasAccessibilityPermission && !carambaRunning {
            stack.addArrangedSubview(squareButton("open", action: #selector(openAccessibility), width: 54, height: 28))
        }
        let hide = squareButton("hide", action: #selector(toggleSetupDisclosure), width: 54, height: 28)
        hide.setAccessibilityHelp("Hide setup and blocker details")
        stack.addArrangedSubview(hide)
        return host
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

    private func stateReadout(_ title: String, width: CGFloat, height: CGFloat, textSize: CGFloat = 11) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = UI.ink.cgColor
        view.layer?.borderColor = UI.ink.cgColor
        view.layer?.borderWidth = 1
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        let text = label(title, size: textSize, weight: .semibold, color: UI.bg, width: width - 20, height: 18, centered: true)
        text.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(text)
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func bridgeStatus() -> String {
        guard usesHammerspoonBridge else {
            return "native ready"
        }
        let health = HammerspoonIPC.health(timeout: 0.20)
        if health.timedOut { return "bridge timeout" }
        guard health.ipcAvailable else { return "bridge unavailable" }
        return health.lastStatus ?? "ready"
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
            _ = HammerspoonIPC.run("return tostring(layoutPilotFix())")
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
        _ = HammerspoonIPC.run("return tostring(layoutPilotReloadSettings())")
    }

    @objc private func openPanelFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.showPopover() }
    }

    @objc private func toggleLayout() {
        _ = InputSources.toggle()
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
    @objc private func toggleSetupDisclosure() {
        setupExpanded.toggle()
        rebuildPopoverContent()
    }
    @objc private func showSoundMenu(_ sender: ShaperButton) {
        let choices: [(FeedbackSound, Selector)] = [
            (.pulse, #selector(setSoundPulse)),
            (.relay, #selector(setSoundRelay)),
            (.scan, #selector(setSoundScan)),
            (.flux, #selector(setSoundFlux)),
            (.prism, #selector(setSoundPrism)),
            (.tick, #selector(setSoundTick)),
            (.fold, #selector(setSoundFold)),
            (.nova, #selector(setSoundNova)),
        ]
        let menu = NSMenu(title: "feedback cue")
        for (index, choice) in choices.enumerated() {
            let item = NSMenuItem(
                title: String(format: "%02d · %@", index + 1, choice.0.rawValue),
                action: choice.1,
                keyEquivalent: ""
            )
            item.target = self
            item.state = soundEnabled && soundName == choice.0.rawValue ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }
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

        if !BridgeConfiguration.containsLoadLine("-- personal configuration\n\(AppIdentity.bridgeLoadLine)\n") {
            failures.append("bridge load line was not recognized")
        }
        if BridgeConfiguration.containsLoadLine("-- \(AppIdentity.bridgeLoadLine)\n") {
            failures.append("commented bridge load line was accepted")
        }

        // Health collection shells out; a child that outgrows the pipe buffer must
        // not be able to stall doctor or setup.
        let healthStart = Date()
        _ = InstallationHealth.collect()
        let healthSeconds = Date().timeIntervalSince(healthStart)
        if healthSeconds > 5 {
            failures.append("health collection took \(String(format: "%.1f", healthSeconds))s")
        }

        guard failures.isEmpty else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            return 1
        }
        print("PASS: 16 local conversion and setup tests; \(core.us.name) ↔ \(core.russianPC.name)")
        return 0
    }
}

@main
private struct LayoutPilotMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--doctor-json") {
            writeJSONObject(InstallationHealth.collect().doctorPayload)
            exit(0)
        }
        if arguments.contains("--setup") {
            exit(Setup.run())
        }
        if arguments.contains("--status") {
            print("input=\(InputSources.currentID() ?? "unknown")")
            print("accessibility=\(AXIsProcessTrusted())")
            exit(0)
        }
        if arguments.contains("--status-json") {
            let current = InputSources.currentID() ?? "unknown"
            let caramba = !NSRunningApplication.runningApplications(
                withBundleIdentifier: "tech.caramba.switcher"
            ).isEmpty
            writeJSONObject([
                "schemaVersion": 1,
                "app": AppIdentity.name,
                "version": AppIdentity.version,
                "inputSourceID": current,
                "accessibilityTrusted": AXIsProcessTrusted(),
                "carambaRunning": caramba,
                "ready": current == AppIdentity.usID || current == AppIdentity.russianPCID,
            ])
            exit(0)
        }
        if arguments.contains("--capabilities-json") {
            writeJSONObject([
                "schemaVersion": 1,
                "app": AppIdentity.name,
                "version": AppIdentity.version,
                "pair": [AppIdentity.usID, AppIdentity.russianPCID],
                "scopes": ["word", "phrase"],
                "capitalization": ["preserve", "sentence", "uppercase", "lowercase"],
                "commands": ["convert", "convert-phrase", "switch", "status", "doctor", "setup"],
                "localOnly": true,
                "textLogging": false,
            ])
            exit(0)
        }
        guard let core = LayoutConversionCore() else {
            fputs("Language Relay: U.S. and Russian – PC input sources are required.\n", stderr)
            exit(2)
        }

        let capitalization: CapitalizationMode = {
            guard let index = arguments.firstIndex(of: "--capitalization"),
                  arguments.indices.contains(index + 1)
            else { return .preserve }
            return CapitalizationMode(rawValue: arguments[index + 1]) ?? .preserve
        }()
        if arguments.contains("--self-test") {
            exit(SelfTest.run(core: core))
        }
        if arguments.contains("--bounded-process-self-test") {
            let started = Date()
            let result = BoundedProcess.run("/bin/sleep", arguments: ["1"], timeout: 0.02)
            let elapsed = Date().timeIntervalSince(started)
            guard result?.timedOut == true, elapsed < 0.30 else {
                fputs("FAIL: bounded process timeout\n", stderr)
                exit(8)
            }
            print(String(format: "PASS: bounded process timeout; elapsed=%.3fs", elapsed))
            exit(0)
        }
        if arguments.contains("--ui-self-test") {
            let delegate = AppDelegate(core: core)
            guard delegate.runBackgroundUISelfTest() else {
                fputs("FAIL: background UI self-test\n", stderr)
                exit(6)
            }
            print("PASS: background UI self-test; panel=420x408; glyph=54x18; window=none")
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
        writeJSONObject(payload)
    }

    private static func writeJSONObject(_ payload: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { exit(5) }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
