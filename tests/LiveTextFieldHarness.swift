import AppKit
import Foundation

@MainActor
private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let resultURL = URL(fileURLWithPath: "/private/tmp/layout-pilot-live-result.txt")
    private var window: NSWindow!
    private var textView: NSTextView!
    private var triggerMode = "direct"
    private var triggerAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.removeItem(at: resultURL)
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--no-trigger") {
            triggerMode = "none"
        } else if arguments.contains("--double-shift") {
            triggerMode = "double-shift"
        } else {
            triggerMode = "direct"
        }
        let seed = arguments.first(where: { !$0.hasPrefix("--") }) ?? "ghbdtn"
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 180))
        textView.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
        textView.string = seed
        let seedLength = (seed as NSString).length
        textView.setSelectedRange(
            arguments.contains("--select-all")
                ? NSRange(location: 0, length: seedLength)
                : NSRange(location: seedLength, length: 0)
        )

        let scroll = NSScrollView(frame: textView.frame)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Type Relay Live Test"
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)
        fputs("READY\n", stderr)

        Timer.scheduledTimer(
            timeInterval: 0.45,
            target: self,
            selector: #selector(reassertFocus),
            userInfo: nil,
            repeats: false
        )
        Timer.scheduledTimer(
            timeInterval: 0.75,
            target: self,
            selector: #selector(reassertFocus),
            userInfo: nil,
            repeats: false
        )
        if triggerMode != "none" {
            Timer.scheduledTimer(
                timeInterval: 1.0,
                target: self,
                selector: #selector(triggerLayoutPilot),
                userInfo: nil,
                repeats: false
            )
        }
        Timer.scheduledTimer(
            timeInterval: 7.0,
            target: self,
            selector: #selector(finish),
            userInfo: nil,
            repeats: false
        )
    }

    @objc private func reassertFocus() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    @objc private func triggerLayoutPilot() {
        reassertFocus()
        triggerAttempts += 1
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "dev.alex.layout-pilot-live-test" else {
            if triggerAttempts < 16 {
                perform(#selector(triggerLayoutPilot), with: nil, afterDelay: 0.25)
            } else {
                fputs("TRIGGER-FAILED=unable-to-focus-harness\n", stderr)
            }
            return
        }

        let direct = "layoutPilotFix()"
        let doubleShift = """
        local event = hs.eventtap.event
        local function tap()
          event.newKeyEvent({}, 56, true):post()
          event.newKeyEvent({}, 56, false):post()
        end
        tap()
        hs.timer.doAfter(0.12, tap)
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hs")
        task.arguments = ["-c", triggerMode == "double-shift" ? doubleShift : direct]
        do {
            try task.run()
            fputs("TRIGGER=\(triggerMode)\n", stderr)
        } catch {
            fputs("TRIGGER-FAILED=\(error)\n", stderr)
        }
    }

    @objc private func finish() {
        try? Data(textView.string.utf8).write(to: resultURL, options: .atomic)
        NSApp.terminate(nil)
    }
}

@main
private struct LiveTextFieldHarness {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = HarnessDelegate()
        app.delegate = delegate
        app.run()
    }
}
