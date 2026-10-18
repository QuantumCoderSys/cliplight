import AppKit
import Carbon
import Combine
import OSLog

/// A global keyboard shortcut: a key plus Carbon modifier flags.
struct Shortcut: Codable, Equatable, Identifiable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    var id: String { "\(modifiers)-\(keyCode)" }
    var glyphs: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        return out + key
    }

    static let commandShiftV = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), key: "V")
    static let optionSpace = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")
    static let controlShiftV = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey), key: "V")
    static let controlOptionV = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), key: "V")
    static let presets = [commandShiftV, optionSpace, controlShiftV, controlOptionV]

    /// Builds a shortcut from a key press, or nil if it has no ⌘, ⌃ or ⌥ (function keys excepted).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        let code = Int(event.keyCode)
        let name = Self.specialKeys[code] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        let isFunctionKey = Self.functionKeys.contains(code)
        guard !name.isEmpty, isFunctionKey || carbon & UInt32(cmdKey | controlKey | optionKey) != 0 else { return nil }
        self.init(keyCode: UInt32(code), modifiers: carbon, key: name)
    }
    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.key = key
    }

    private static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19"
    ]
}

@MainActor
final class HotKeyManager: ObservableObject {
    @Published private(set) var choice: Shortcut
    @Published private(set) var error: String?
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "globalShortcut"), let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            choice = saved
        } else {
            // Earlier versions saved one of four named presets. ⌃⇧V users move to the new ⇧⌘V default.
            switch defaults.string(forKey: "shortcut") {
            case "optionSpace": choice = .optionSpace
            case "controlOptionV": choice = .controlOptionV
            default: choice = .commandShiftV
            }
        }
    }
    func start() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                Logger(subsystem: "local.cliplight.app", category: "Shortcut").info("Global clipboard shortcut pressed")
                manager.onPress?()
            }
            return noErr
        }, 1, &type, context, &handler)
        guard status == noErr else { error = "The global shortcut listener couldn't start. Use the menu-bar icon."; return }
        register(choice, save: true)
    }
    func set(_ next: Shortcut) {
        if reference != nil && choice == next { return }
        register(next, save: true)
    }
    /// Releases the shortcut while a new one is being recorded, so pressing it doesn't open the panel.
    func suspend() {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
    }
    func resume() {
        if reference == nil { register(choice, save: false) }
    }
    private func register(_ next: Shortcut, save: Bool) {
        var newReference: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        let status = RegisterEventHotKey(next.keyCode, next.modifiers, id, GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else {
            if reference == nil, next != choice { register(choice, save: false) }
            error = "\(next.glyphs) is used by another app. Choose another shortcut or use the menu-bar icon."
            return
        }
        if let reference { UnregisterEventHotKey(reference) }
        reference = newReference
        choice = next; error = nil
        if save, let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: "globalShortcut") }
    }
    func stop() {
        suspend()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
