import SwiftUI
import AppKit

/// Click, then press a key combination to set the global shortcut. Escape cancels.
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var manager: HotKeyManager

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.manager = manager
        button.refresh()
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.manager = manager
        button.refresh()
    }

    final class RecorderButton: NSButton {
        weak var manager: HotKeyManager?
        private var recording = false { didSet { refresh() } }

        init() {
            super.init(frame: .zero)
            bezelStyle = .push
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(begin)
            setAccessibilityLabel("Global shortcut")
        }
        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: max(150, super.intrinsicContentSize.width), height: super.intrinsicContentSize.height) }
        override var acceptsFirstResponder: Bool { true }

        @MainActor func refresh() {
            title = recording ? "Press shortcut…" : (manager?.choice.glyphs ?? "")
        }
        @objc @MainActor private func begin() {
            manager?.suspend()
            recording = true
            window?.makeFirstResponder(self)
        }
        @MainActor private func end() {
            recording = false
            manager?.resume()
        }
        override func resignFirstResponder() -> Bool {
            if recording { MainActor.assumeIsolated { end() } }
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            MainActor.assumeIsolated {
                if event.keyCode == 53 { end(); return }
                guard let shortcut = Shortcut(event: event) else { NSSound.beep(); return }
                recording = false
                manager?.set(shortcut)
                manager?.resume()
            }
        }
    }
}
