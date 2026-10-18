// An isolated presentation app for README screenshots. No clipboard polling, Keychain, sync, or real history.
import AppKit
import SwiftUI

@MainActor
final class ShowcaseState: ObservableObject {
    @Published var scene = 1
    let store: ClipboardStore
    let model: PanelModel
    let shortcut: HotKeyManager
    let controller: PanelController
    let codeID: UUID
    let colorID: UUID
    let proseID: UUID
    let snippetID: UUID

    init() {
        let defaults = UserDefaults(suiteName: "local.cliplight.showcase") ?? .standard
        store = ClipboardStore(ephemeral: true, defaults: defaults)
        store.secretLifetime = 0
        shortcut = HotKeyManager(defaults: defaults)
        let board = NSPasteboard(name: .init("local.cliplight.showcase"))
        controller = PanelController(store: store, monitor: ClipboardMonitor(store: store, pasteboard: board), shortcut: shortcut)
        model = controller.model
        func item(_ text: String, source: String, app: String?, minutes: Double, pinned: Bool = false) -> Clip {
            var clip = Clip(kind: .text, text: text, source: source, sourceBundleID: app)
            clip.lastUsedAt = Date().addingTimeInterval(-minutes * 60)
            clip.createdAt = clip.lastUsedAt
            clip.isPinned = pinned
            return clip
        }
        let address = item("1 Infinite Loop, Cupertino, CA", source: "Mail", app: "com.apple.mail", minutes: 40, pinned: true)
        let color = item("#7C6CF2", source: "Design", app: nil, minutes: 7)
        let code = item("""
        func keepWhatMatters() {
            let history = clipboard.search("idea")
            return history.pinned
        }
        """, source: "Editor", app: nil, minutes: 15)
        let prose = item("Good ideas deserve a second copy.\nKeep the useful things within reach.", source: "Notes", app: "com.apple.Notes", minutes: 24)
        let link = item("https://www.swift.org/documentation/", source: "Safari", app: "com.apple.Safari", minutes: 50)
        let command = item("swift build -c release", source: "Terminal", app: "com.apple.Terminal", minutes: 1_440)
        let note = item("Review the final details. Then ship something lovely.", source: "Notes", app: "com.apple.Notes", minutes: 1_500)
        for clip in [address, color, code, prose, link, command, note] { store.insert(clip) }
        store.addSnippet(name: "A friendly sign-off", text: "Thanks for taking a look.\nHave a lovely day!")
        codeID = code.id; colorID = color.id; proseID = prose.id
        snippetID = store.items.first { $0.isSnippet }?.id ?? UUID()
        select(1)
    }
    var dark: Bool { scene == 2 }
    var headline: String {
        switch scene {
        case 2: return "Right at home.\nEven after dark."
        case 3: return "A small menu.\nA lot less busywork."
        case 4: return "The words you reuse.\nAlways within reach."
        default: return "Your clipboard.\nBack in a keystroke."
        }
    }
    var caption: String {
        switch scene {
        case 2: return "Native macOS materials. A familiar place for everything you copy."
        case 3: return "Change case, clean links, and format JSON with ⌘K."
        case 4: return "Save a snippet with ⌘S. Find it by name whenever you need it."
        default: return "Search, preview, and paste — without breaking your flow."
        }
    }
    func select(_ scene: Int) {
        self.scene = scene
        model.reset()
        model.selectedID = scene == 1 ? colorID : scene == 3 ? proseID : codeID
        if scene == 4 { model.scope = .snippets; model.selectedID = snippetID }
        if scene == 3 { controller.toggleActions() }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

struct ShowcaseStage: View {
    @ObservedObject var state: ShowcaseState
    var body: some View {
        ZStack {
            LinearGradient(colors: state.dark ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.19, green: 0.13, blue: 0.29)] : [Color(red: 0.86, green: 0.91, blue: 1.0), Color(red: 0.94, green: 0.86, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "clipboard").font(.system(size: 17, weight: .semibold))
                    Text("Cliplight").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Text("⇧⌘V").font(.system(size: 16, weight: .medium, design: .rounded))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.bottom, 20)
                Text(state.headline).font(.system(size: 38, weight: .semibold)).tracking(-1.4).lineSpacing(-1)
                Spacer(minLength: 0)
                ContentView(store: state.store, model: state.model, shortcut: state.shortcut, controller: state.controller)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(state.dark ? 0.35 : 0.16), radius: 25, y: 14)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack {
                    Text(state.caption).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("macOS 14+").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 48).padding(.vertical, 32)
        }
        .frame(width: 840, height: 730)
        .environment(\.colorScheme, state.dark ? .dark : .light)
    }
}

final class ShowcaseWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ShowcaseDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var state: ShowcaseState!
    var keyboard: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        state = ShowcaseState()
        window = ShowcaseWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 730), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Cliplight Showcase"
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: ShowcaseStage(state: state))
        window.center()
        let menu = NSMenu()
        let item = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "Quit Showcase", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = app; menu.addItem(item); NSApp.mainMenu = menu
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if let key = event.charactersIgnoringModifiers, let number = Int(key), (1...4).contains(number) {
                self?.state.select(number); return nil
            }
            return event
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@main
struct ShowcaseApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ShowcaseDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
