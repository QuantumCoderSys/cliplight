import SwiftUI

struct ContentView: View {
    static let size = CGSize(width: 700, height: 440)
    static let cornerRadius: CGFloat = 24

    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: PanelModel
    @ObservedObject var shortcut: HotKeyManager
    let controller: PanelController

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.5)
            if let error = store.message ?? shortcut.error { banner(error) }
            if model.results.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    resultsList.frame(width: 290)
                    Divider().opacity(0.5)
                    if let clip = model.selected {
                        ClipPreview(clip: clip, markedCount: model.targets.count, verb: controller.pastes ? "Paste" : "Copy",
                                    paste: { controller.deliver(model.targets) },
                                    actions: { controller.toggleActions() },
                                    quickLook: { controller.toggleQuickLook() })
                            .id(clip.id)
                            .overlay(alignment: .bottomTrailing) {
                                if model.actionsOpen { ActionMenu(model: model, run: controller.runAction(at:)).padding(12) }
                            }
                    }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .modifier(PanelSurface(cornerRadius: Self.cornerRadius))
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
            SearchField(text: $model.query, focusToken: model.focusToken)
                .frame(height: 30)
            if store.isPaused {
                pill("Paused", symbol: "pause.fill") { store.isPaused = false }
                    .help("Capture is paused. Click to resume.")
            }
            if model.scope != .all {
                pill(model.scope.rawValue, symbol: model.scope.symbol) { model.scope = .all }
                    .help("Showing \(model.scope.rawValue.lowercased()) only. Click to clear, or press ⇥ to change.")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func banner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text(text).lineLimit(2)
            Spacer()
            Button { store.message = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.sections) { section in
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 3)
                        ForEach(section.clips) { clip in
                            ClipRow(clip: clip, selected: model.selected?.id == clip.id, marked: model.isMarked(clip.id),
                                    choose: { model.marked = []; model.selectedID = clip.id; controller.refreshQuickLook() },
                                    toggleMark: { model.toggleMark(clip.id) },
                                    paste: { controller.deliver([clip]) },
                                    pin: { store.pin(clip.id) },
                                    remove: { model.selectedID = clip.id; controller.deleteSelection() })
                            .id(clip.id)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "clipboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(emptyTitle).font(.system(size: 15, weight: .semibold))
            Text(emptyDescription).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(2)
        }
        .padding(30)
    }
    private var emptyTitle: String {
        if !model.query.isEmpty { return "No Results" }
        switch model.scope {
        case .all: return "Nothing Copied Yet"
        case .pinned: return "No Pinned Clips"
        case .snippets: return "No Snippets"
        default: return "No \(model.scope.rawValue)"
        }
    }
    private var emptyDescription: String {
        if !model.query.isEmpty { return "Try a different word, app name, or text from an image." }
        switch model.scope {
        case .all: return "Copy anything, then press \(shortcut.choice.glyphs) to find it here."
        case .pinned: return "Press ⌘P on a clip to keep it here."
        case .snippets: return "Press ⌘S on a clip to save it as a snippet,\nthen type its name to paste it."
        default: return "Press ⇥ to switch filters."
        }
    }
}

/// The ⌘K menu: every action for the selection, with its shortcut.
private struct ActionMenu: View {
    @ObservedObject var model: PanelModel
    let run: (Int) -> Void
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                        let selected = index == model.actionIndex
                        HStack(spacing: 9) {
                            Image(systemName: action.symbol).frame(width: 16)
                                .foregroundStyle(selected ? Color.white : action.destructive ? Color.red : Color.secondary)
                            Text(action.title).lineLimit(1)
                                .foregroundStyle(selected ? Color.white : action.destructive ? Color.red : Color.primary)
                            Spacer(minLength: 12)
                            if let shortcut = action.shortcut {
                                Text(shortcut).font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                            }
                        }
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 8).frame(height: 26)
                        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { run(index) }
                        .onHover { if $0 { model.actionIndex = index } }
                        .id(action.id)
                    }
                }
                .padding(5)
            }
            .scrollIndicators(.never)
            .onChange(of: model.actionIndex) { _, index in
                if model.actions.indices.contains(index) { proxy.scrollTo(model.actions[index].id) }
            }
        }
        .frame(width: 290)
        .frame(maxHeight: min(CGFloat(model.actions.count) * 27 + 10, 300))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

/// Liquid Glass on macOS 26+, frosted material before that.
private struct PanelSurface: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            // Glass sits behind the content: wrapping content in glass would tint text and strip its colors.
            content
                .background { Color.clear.glassEffect(.regular, in: shape) }
                .clipShape(shape)
        } else {
            content
                .background(FrostedBackground())
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}
