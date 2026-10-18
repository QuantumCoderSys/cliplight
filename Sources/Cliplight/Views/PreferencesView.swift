import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class PreferencesState: ObservableObject {
    @Published var confirmClear = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var accessibilityTrusted = Paster.isTrusted
    @Published var passphrase = ""
    @Published var editingSnippet: Clip?
    @Published var creatingSnippet = false
    @Published var draftName = ""
    @Published var draftText = ""
}

/// One pane of the Settings window. The window itself is an NSTabViewController with toolbar tabs,
/// which gives the standard macOS look (icons in the toolbar, title follows the selected pane).
struct PreferencesView: View {
    enum Tab: String, CaseIterable {
        case general = "General", privacy = "Privacy", snippets = "Snippets", sync = "Sync"
        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .privacy: return "hand.raised"
            case .snippets: return "text.quote"
            case .sync: return "icloud"
            }
        }
    }
    static let size = CGSize(width: 520, height: 500)

    let tab: Tab
    @ObservedObject var store: ClipboardStore
    @ObservedObject var shortcut: HotKeyManager
    @ObservedObject var sync: SyncService
    @ObservedObject var state: PreferencesState

    var body: some View {
        Group {
            switch tab {
            case .general: general
            case .privacy: privacy
            case .snippets: snippets
            case .sync: syncTab
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.accessibilityTrusted = Paster.isTrusted
        }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                LabeledContent("Open Cliplight") {
                    HStack {
                        ShortcutRecorder(manager: shortcut)
                        Menu("Presets") {
                            ForEach(Shortcut.presets) { preset in
                                Button(preset.glyphs) { shortcut.set(preset) }
                            }
                        }
                        .fixedSize()
                    }
                }
                if let error = shortcut.error { Text(error).foregroundStyle(.orange).font(.caption) }
            } footer: {
                Text("Click the shortcut, then press a new one. ⇧⌘V is the default: ⌘V pastes, ⇧⌘V pastes from history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Paste directly into the app you were using", isOn: $store.directPaste)
                if store.directPaste {
                    if state.accessibilityTrusted {
                        Label("Accessibility access is on.", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Needs Accessibility access to press ⌘V for you.", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings…") { Paster.requestTrust(); Paster.openAccessibilitySettings() }
                                .controlSize(.small)
                        }
                    }
                }
                Toggle("Keep text formatting", isOn: $store.preserveFormatting)
            } footer: {
                Text("↩ paste · ⇧↩ plain text · ⌥↩ copy only · ⌘K actions · ⌘Y Quick Look · ⌘P pin · ⌘S snippet · ⌘-click or ⇧↑↓ select several · ⇥ filter")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open Cliplight at login", isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            state.loginError = nil
                        } catch { state.loginError = error.localizedDescription }
                    }
                if let error = state.loginError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Privacy

    private var privacy: some View {
        Form {
            Section {
                Toggle("Pause clipboard capture", isOn: $store.isPaused)
                Picker("Keep history for", selection: $store.retention) {
                    ForEach(Retention.allCases) { Text($0.title).tag($0) }
                }
                Picker("Delete codes and passwords after", selection: $store.secretLifetime) {
                    Text("30 Seconds").tag(30)
                    Text("1 Minute").tag(60)
                    Text("5 Minutes").tag(300)
                    Text("Never").tag(0)
                }
            } footer: {
                Text("Pins and snippets are always kept. One-time codes and password-like text are recognized on this Mac and deleted automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Never Save Copies From") {
                Toggle("Password managers", isOn: $store.excludePrivateApps)
                ForEach(store.ignoredApps, id: \.self) { bundleID in
                    HStack {
                        if let icon = AppIcons.icon(for: bundleID) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                        Text(appName(bundleID))
                        Spacer()
                        Button { store.ignoredApps.removeAll { $0 == bundleID } } label: { Image(systemName: "minus.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove \(appName(bundleID))")
                    }
                }
                Button("Add App…", action: chooseApp)
            }
            Section {
                LabeledContent("Saved clips", value: "\(store.items.count)")
                Button("Clear History…", role: .destructive) { state.confirmClear = true }
            } footer: {
                Text("History is encrypted on this Mac with a key kept in your Keychain. Nothing is sent anywhere unless you turn on Sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all clipboard history?", isPresented: $state.confirmClear, titleVisibility: .visible) {
            Button("Delete Unpinned Clips", role: .destructive) { store.clearUnpinned() }
            Button("Delete Everything", role: .destructive) { store.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("“Everything” includes pins and snippets. Your current clipboard is unchanged.") }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Never Save"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { store.ignore(bundleID: id) }
        }
    }

    // MARK: Snippets

    private var snippets: some View {
        let list = store.items.filter(\.isSnippet).sorted { ($0.snippetName ?? "") < ($1.snippetName ?? "") }
        return VStack(spacing: 0) {
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
                    Text("No Snippets").font(.headline)
                    Text("Save text you paste often, like an address or a signature.\nType its name in Cliplight to paste it.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(list) { clip in
                        HStack(alignment: .firstTextBaseline) {
                            Text(clip.snippetName ?? "").fontWeight(.medium).frame(width: 120, alignment: .leading).lineLimit(1)
                            Text(clip.text.replacingOccurrences(of: "\n", with: " ")).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Edit") { edit(clip) }.buttonStyle(.borderless)
                            Button { store.remove(clip.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Delete \(clip.snippetName ?? "snippet")")
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text("Tip: press ⌘S on any clip in Cliplight.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("New Snippet…") { state.draftName = ""; state.draftText = ""; state.creatingSnippet = true }
            }
            .padding(12)
        }
        .sheet(isPresented: Binding(get: { state.creatingSnippet || state.editingSnippet != nil },
                                    set: { if !$0 { state.creatingSnippet = false; state.editingSnippet = nil } })) {
            snippetEditor
        }
    }
    private func edit(_ clip: Clip) {
        state.draftName = clip.snippetName ?? ""
        state.draftText = clip.text
        state.editingSnippet = clip
    }
    private var snippetEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.editingSnippet == nil ? "New Snippet" : "Edit Snippet").font(.headline)
            TextField("Name", text: $state.draftName)
            TextEditor(text: $state.draftText)
                .font(.system(size: 13))
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            HStack {
                Spacer()
                Button("Cancel") { state.creatingSnippet = false; state.editingSnippet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let name = state.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let clip = state.editingSnippet { store.updateSnippet(clip.id, name: name, text: state.draftText) }
                    else { store.addSnippet(name: name, text: state.draftText) }
                    state.creatingSnippet = false; state.editingSnippet = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.draftName.trimmingCharacters(in: .whitespaces).isEmpty || state.draftText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: Sync

    private var syncTab: some View {
        Form {
            Section {
                if sync.enabled {
                    LabeledContent("Status", value: sync.status)
                    if let last = sync.lastSync {
                        LabeledContent("Last synced") { Text(last, style: .relative) }
                    }
                    HStack {
                        Button("Sync Now") { sync.syncNow() }
                        Spacer()
                        Button("Turn Off Sync", role: .destructive) { sync.disable() }
                    }
                    if sync.status.contains("passphrase") { passphraseField }
                } else {
                    passphraseField
                    if sync.status != "Off" { Text(sync.status).font(.caption).foregroundStyle(.orange) }
                }
            } header: {
                Text("Sync Pins and Snippets with iCloud Drive")
            } footer: {
                Text("Off by default. Only pins and snippets sync, never everyday history. Each Mac's file is encrypted with your passphrase before it reaches iCloud, so Apple can't read it. Use the same passphrase on every Mac. If you forget it, turn sync off and on with a new one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    private var passphraseField: some View {
        HStack {
            SecureField("Passphrase", text: $state.passphrase, prompt: Text("8 or more characters"))
            Button(sync.enabled ? "Update" : "Turn On") {
                sync.enable(passphrase: state.passphrase)
                state.passphrase = ""
            }
            .disabled(state.passphrase.count < 8)
        }
    }
}
