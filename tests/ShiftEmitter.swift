import ApplicationServices
import Foundation

guard AXIsProcessTrusted() else {
    fputs("ShiftEmitter needs Accessibility permission from its responsible process.\n", stderr)
    exit(2)
}

func tapShift() {
    CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(45_000)
    CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: false)?.post(tap: .cghidEventTap)
}

tapShift()
usleep(120_000)
tapShift()

