import AppKit
import SwiftUI
import Quartz
import OSLog

final class SearchPanel: NSPanel {
    weak var previewSource: PreviewSource?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Quick Look asks the key window's responder chain who supplies its items.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = previewSource
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
}

final class PreviewSource: NSObject, QLPreviewPanelDataSource {
    var urls: [URL] = []
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { urls[index] as NSURL }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: SearchPanel
    let model: PanelModel
    let store: ClipboardStore
    let monitor: ClipboardMonitor
    private let logger = Logger(subsystem: "local.cliplight.app", category: "Panel")
    private let previewSource = PreviewSource()
    private let previewFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Cliplight-QuickLook", isDirectory: true)
    private var keyboard: Any?
    private var previousApp: NSRunningApplication?
    var onSettings: (() -> Void)?
    var onShow: (() -> Void)?

    init(store: ClipboardStore, monitor: ClipboardMonitor, shortcut: HotKeyManager) {
        self.store = store; self.monitor = monitor
        model = PanelModel(store: store)
        panel = SearchPanel(contentRect: NSRect(origin: .zero, size: ContentView.size), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.previewSource = previewSource
        panel.title = "Cliplight — Clipboard Search"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ContentView(store: store, model: model, shortcut: shortcut, controller: self))
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    // MARK: - Showing

    func toggle() { panel.isVisible ? hide() : show() }
    func show() {
        logger.info("Opening clipboard panel")
        monitor.poll()
        onShow?()
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        model.reset()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let area = screen.visibleFrame
            let x = area.midX - panel.frame.width / 2
            let y = area.minY + area.height * 0.62 - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: max(area.minX, x), y: max(area.minY, min(y, area.maxY - panel.frame.height))))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        model.focusToken = UUID()
    }
    func hide() {
        logger.info("Closing clipboard panel")
        closeQuickLook()
        model.closeActions()
        panel.orderOut(nil)
    }
    func dismissToPreviousApp() { hide(); previousApp?.activate(options: []) }

    // MARK: - Pasting

    var pastes: Bool { store.directPaste }

    /// Puts clips on the clipboard, closes the panel, and pastes into the previous app when allowed.
    func deliver(_ clips: [Clip], plain: Bool = false, copyOnly: Bool = false) {
        guard monitor.copy(clips, plain: plain) else { return }
        finish(paste: !copyOnly)
    }
    func deliver(text: String) {
        guard monitor.copy(text: text) else { return }
        finish(paste: true)
    }
    private func finish(paste: Bool) {
        hide()
        let target = previousApp
        if paste && store.directPaste {
            if Paster.isTrusted { Paster.paste(into: target); return }
            // Copy still worked; ask once for permission so the next paste can be direct.
            Paster.requestTrust()
        }
        target?.activate(options: [])
    }

    // MARK: - Clip commands

    func pinSelection() {
        let clips = model.targets
        let pin = clips.contains { !$0.isPinned }
        for clip in clips where clip.isPinned != pin { store.pin(clip.id) }
    }
    func deleteSelection() {
        let clips = model.targets
        let index = model.results.firstIndex { $0.id == clips.first?.id } ?? 0
        clips.forEach { store.remove($0.id) }
        model.marked = []
        let remaining = model.results
        model.selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        refreshQuickLook()
    }
    func promptSnippet(for clip: Clip) {
        guard clip.kind == .text else { store.message = "Only text can be saved as a snippet."; return }
        let alert = NSAlert()
        alert.messageText = clip.isSnippet ? "Rename Snippet" : "Save as Snippet"
        alert.informativeText = "Type the name in Cliplight to find this text instantly. Snippets are kept until you delete them."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Name, e.g. sig or address"
        field.stringValue = clip.snippetName ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if clip.isSnippet { alert.addButton(withTitle: "Remove Snippet") }
        alert.window.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        alert.window.initialFirstResponder = field
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { store.saveSnippet(clip.id, name: name) }
        case .alertThirdButtonReturn: store.saveSnippet(clip.id, name: "")
        default: break
        }
        panel.makeKeyAndOrderFront(nil)
        model.focusToken = UUID()
    }
    func ignoreSource(of clip: Clip) {
        guard let bundleID = clip.sourceBundleID else { return }
        store.ignore(bundleID: bundleID)
        store.message = "Copies from \(clip.source) won't be saved. Change this in Settings › Privacy."
    }

    // MARK: - Actions (⌘K)

    func toggleActions() {
        if model.actionsOpen { model.closeActions(); return }
        model.actions = actions(for: model.targets)
        model.actionIndex = 0
    }
    func runAction(at index: Int) {
        guard model.actions.indices.contains(index) else { return }
        let action = model.actions[index]
        model.closeActions()
        action.run()
    }

    func actions(for clips: [Clip]) -> [PanelAction] {
        guard let clip = clips.first else { return [] }
        let verb = pastes ? "Paste" : "Copy"
        if clips.count > 1 {
            return [
                PanelAction(title: "\(verb) \(clips.count) Clips", symbol: "doc.on.clipboard", shortcut: "↩") { [unowned self] in deliver(clips) },
                PanelAction(title: "Copy \(clips.count) Clips", symbol: "doc.on.doc", shortcut: "⌥↩") { [unowned self] in deliver(clips, copyOnly: true) },
                PanelAction(title: clips.contains { !$0.isPinned } ? "Pin \(clips.count) Clips" : "Unpin \(clips.count) Clips", symbol: "pin", shortcut: "⌘P") { [unowned self] in pinSelection() },
                PanelAction(title: "Delete \(clips.count) Clips", symbol: "trash", shortcut: "⌘⌫", destructive: true) { [unowned self] in deleteSelection() }
            ]
        }
        var list: [PanelAction] = [
            PanelAction(title: verb, symbol: "doc.on.clipboard", shortcut: "↩") { [unowned self] in deliver([clip]) }
        ]
        if pastes {
            list.append(PanelAction(title: "Copy Only", symbol: "doc.on.doc", shortcut: "⌥↩") { [unowned self] in deliver([clip], copyOnly: true) })
        }
        if clip.kind == .text {
            list.append(PanelAction(title: "\(verb) as Plain Text", symbol: "textformat", shortcut: "⇧↩") { [unowned self] in deliver([clip], plain: true) })
        }
        switch ClipContent.of(clip) {
        case .link(let url):
            list.append(PanelAction(title: "Open Link", symbol: "safari") { [unowned self] in hide(); NSWorkspace.shared.open(url) })
        case .email(let address):
            if let url = URL(string: "mailto:\(address)") {
                list.append(PanelAction(title: "New Email", symbol: "envelope") { [unowned self] in hide(); NSWorkspace.shared.open(url) })
            }
        case .address(let address):
            var parts = URLComponents(string: "maps://")!
            parts.queryItems = [URLQueryItem(name: "q", value: address)]
            if let url = parts.url {
                list.append(PanelAction(title: "Open in Maps", symbol: "map") { [unowned self] in hide(); NSWorkspace.shared.open(url) })
            }
        case .color(let color):
            for (label, value) in [("HEX", color.hex), ("RGB", color.rgb), ("HSL", color.hsl)] where value != clip.text.trimmingCharacters(in: .whitespaces) {
                list.append(PanelAction(title: "\(verb) as \(label)  \(value)", symbol: "paintpalette") { [unowned self] in deliver(text: value) })
            }
        case .code, .plain: break
        }
        if clip.kind == .text {
            let content = ClipContent.of(clip)
            for transform in TextTransform.allCases {
                // Changing case only makes sense for prose, not links, colors, emails or code.
                if [.uppercase, .lowercase, .titleCase].contains(transform) && content != .plain { continue }
                guard let output = transform.apply(clip.text) else { continue }
                list.append(PanelAction(title: transform.title.replacingOccurrences(of: "Paste", with: verb), symbol: transform.symbol) { [unowned self] in deliver(text: output) })
            }
        }
        if clip.kind == .image, let text = clip.recognizedText, !text.isEmpty {
            list.append(PanelAction(title: "\(verb) Text in Image", symbol: "text.viewfinder") { [unowned self] in deliver(text: text) })
        }
        if clip.kind == .files, !clip.fileURLs.isEmpty {
            list.append(PanelAction(title: "Show in Finder", symbol: "folder") { [unowned self] in hide(); NSWorkspace.shared.activateFileViewerSelecting(clip.fileURLs) })
        }
        list.append(PanelAction(title: "Quick Look", symbol: "eye", shortcut: "⌘Y") { [unowned self] in toggleQuickLook() })
        list.append(PanelAction(title: clip.isPinned ? "Unpin" : "Pin", symbol: clip.isPinned ? "pin.slash" : "pin", shortcut: "⌘P") { [unowned self] in store.pin(clip.id) })
        if clip.kind == .text {
            list.append(PanelAction(title: clip.isSnippet ? "Rename Snippet…" : "Save as Snippet…", symbol: "text.quote", shortcut: "⌘S") { [unowned self] in promptSnippet(for: clip) })
        }
        if clip.sourceBundleID != nil, clip.sourceBundleID != Bundle.main.bundleIdentifier, !clip.isSnippet {
            list.append(PanelAction(title: "Never Save Copies from \(clip.source)", symbol: "hand.raised") { [unowned self] in ignoreSource(of: clip) })
        }
        list.append(PanelAction(title: "Delete", symbol: "trash", shortcut: "⌘⌫", destructive: true) { [unowned self] in deleteSelection() })
        return list
    }

    // MARK: - Quick Look

    var quickLookVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }
    func toggleQuickLook() {
        if quickLookVisible { closeQuickLook(); return }
        guard prepareQuickLook() else { return }
        QLPreviewPanel.shared().orderFront(nil)
        QLPreviewPanel.shared().reloadData()
    }
    func refreshQuickLook() {
        guard quickLookVisible else { return }
        if prepareQuickLook() { QLPreviewPanel.shared().reloadData() } else { closeQuickLook() }
    }
    private func closeQuickLook() {
        if quickLookVisible { QLPreviewPanel.shared().orderOut(nil) }
        try? FileManager.default.removeItem(at: previewFolder)
    }
    /// Quick Look shows files, so text and images are written to a private temporary folder first.
    private func prepareQuickLook() -> Bool {
        guard let clip = model.selected else { return false }
        try? FileManager.default.removeItem(at: previewFolder)
        switch clip.kind {
        case .files:
            previewSource.urls = clip.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        case .image, .text:
            do {
                try FileManager.default.createDirectory(at: previewFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let safe = String(clip.title.prefix(40)).components(separatedBy: CharacterSet(charactersIn: "/:\\\n")).joined(separator: " ")
                let url = previewFolder.appendingPathComponent((safe.isEmpty ? "Clip" : safe) + (clip.kind == .image ? ".png" : ".txt"))
                try (clip.kind == .image ? clip.data ?? Data() : Data(clip.text.utf8)).write(to: url, options: .atomic)
                previewSource.urls = [url]
            } catch { return false }
        }
        return !previewSource.urls.isEmpty
    }

    // MARK: - Window & keyboard

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow, !NSApp.isActive else { return }
            self.hide()
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if model.actionsOpen {
            switch event.keyCode {
            case 125: model.moveAction(1); return true
            case 126: model.moveAction(-1); return true
            case 36, 76: runAction(at: model.actionIndex); return true
            case 53: model.closeActions(); return true
            default:
                if flags.contains(.command) && key == "k" { model.closeActions(); return true }
                model.closeActions()
            }
        }

        if flags.contains(.command) {
            if let number = Int(key), (1...9).contains(number), model.results.count >= number {
                deliver([model.results[number - 1]], plain: flags.contains(.shift)); return true
            }
            switch key {
            case "k": toggleActions(); return true
            case "p": pinSelection(); return true
            case "s": if let clip = model.selected { promptSnippet(for: clip) }; return true
            case "y": toggleQuickLook(); return true
            case ",": onSettings?(); return true
            default: break
            }
            if event.keyCode == 51 { deleteSelection(); return true }
            return false
        }
        if flags.contains(.control) { return false }

        switch event.keyCode {
        case 125: model.move(1, extend: flags.contains(.shift)); refreshQuickLook(); return true
        case 126: model.move(-1, extend: flags.contains(.shift)); refreshQuickLook(); return true
        case 36, 76:
            let clips = model.targets
            guard !clips.isEmpty else { return true }
            deliver(clips, plain: flags.contains(.shift), copyOnly: flags.contains(.option))
            return true
        case 48: model.cycleScope(flags.contains(.shift) ? -1 : 1); return true
        case 49 where model.query.isEmpty && !flags.contains(.option):
            toggleQuickLook(); return true
        case 53:
            // Like Spotlight: Escape steps back (Quick Look, selection, search), then closes.
            if quickLookVisible { closeQuickLook() }
            else if !model.marked.isEmpty { model.marked = [] }
            else if !model.query.isEmpty || model.scope != .all { model.reset() }
            else { dismissToPreviousApp() }
            return true
        default: return false
        }
    }
}
