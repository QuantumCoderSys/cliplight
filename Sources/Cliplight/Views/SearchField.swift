import SwiftUI
import AppKit

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var token: UUID?
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Clipboard Search"
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search clipboard")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.token != focusToken {
            context.coordinator.token = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }
}

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
