import AppKit
import ApplicationServices
import Carbon

/// Sends ⌘V to the frontmost app. Needs Accessibility permission, which macOS asks for once.
@MainActor
enum Paster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    private static var asked = false
    /// Shows the system prompt (at most once per launch) that leads to Privacy & Security › Accessibility.
    static func requestTrust() {
        guard !asked else { return }
        asked = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Activates `app`, waits for it to come forward, then presses ⌘V.
    static func paste(into app: NSRunningApplication?) {
        app?.activate(options: [])
        waitForFront(app, attempts: 20)
    }
    private static func waitForFront(_ app: NSRunningApplication?, attempts: Int) {
        let ready = app == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == app?.processIdentifier
        if ready || attempts == 0 {
            // A short pause lets the destination restore its focused text field.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pressCommandV() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { waitForFront(app, attempts: attempts - 1) }
    }
    private static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// The key code that types `character` in the current keyboard layout (so Dvorak and AZERTY work).
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
                if status == noErr, length == 1, Character(UnicodeScalar(chars[0]) ?? " ") == character { return CGKeyCode(code) }
            }
            return nil
        }
    }
}
