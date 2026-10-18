import AppKit
import SwiftUI
import Combine

@main
struct CliplightApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ApplicationController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Intentionally a menu-bar utility, with no persistent Dock icon.
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        controller = ApplicationController()
        controller?.start()
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Cliplight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    func applicationWillTerminate(_ notification: Notification) { controller?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let controller, !controller.panel.panel.isVisible { controller.panel.show() }
        return true
    }
}

@MainActor
final class ApplicationController: NSObject, NSMenuDelegate {
    let store = ClipboardStore()
    let shortcut = HotKeyManager()
    let monitor: ClipboardMonitor
    let panel: PanelController
    let sync: SyncService
    private let status: NSStatusItem
    private var preferences: NSWindow?
    private let preferencesState = PreferencesState()
    private var menu: NSMenu!
    private var pauseItem: NSMenuItem!
    private var showItem: NSMenuItem!

    override init() {
        monitor = ClipboardMonitor(store: store)
        panel = PanelController(store: store, monitor: monitor, shortcut: shortcut)
        sync = SyncService(store: store)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        shortcut.onPress = { [weak self] in self?.panel.toggle() }
        panel.onSettings = { [weak self] in self?.showPreferences() }
        panel.onShow = { [weak self] in self?.sync.syncNow() }
        let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Cliplight")
        image?.isTemplate = true
        status.button?.image = image
        status.button?.toolTip = "Cliplight — Clipboard History"
        status.button?.target = self; status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        menu = NSMenu()
        menu.delegate = self
        showItem = add("Open Clipboard", action: #selector(openPanel))
        menu.addItem(.separator())
        pauseItem = add("Pause Capture", action: #selector(togglePause))
        add("Settings…", action: #selector(showPreferences), key: ",")
        menu.addItem(.separator())
        add("Quit Cliplight", action: #selector(quit), key: "q")
    }
    func start() {
        shortcut.start(); monitor.start(); store.startSweeping(); sync.start()
        // Make screenshots saved before text recognition existed searchable too.
        for clip in store.items where clip.kind == .image && clip.recognizedText == nil { ImageText.recognize(clip, in: store) }
        panel.show()
    }
    func stop() { monitor.stop(); shortcut.stop(); store.flush() }
    @discardableResult private func add(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            status.menu = menu
            sender.performClick(nil)
            status.menu = nil
        } else { panel.toggle() }
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = store.isPaused ? "Resume Capture" : "Pause Capture"
        showItem.title = "Open Clipboard   \(shortcut.choice.glyphs)"
    }
    @objc private func openPanel() { panel.show() }
    @objc func showPreferences() {
        panel.hide()
        if preferences == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for tab in PreferencesView.Tab.allCases {
                let pane = NSHostingController(rootView: PreferencesView(tab: tab, store: store, shortcut: shortcut, sync: sync, state: preferencesState))
                pane.preferredContentSize = PreferencesView.size
                pane.title = tab.rawValue  // The window title follows the selected pane, as in System Settings-style apps.
                let item = NSTabViewItem(viewController: pane)
                item.label = tab.rawValue
                item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.rawValue)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            preferences = window
        }
        preferencesState.accessibilityTrusted = Paster.isTrusted
        preferences?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func togglePause() { store.isPaused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
