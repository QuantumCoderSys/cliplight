import Foundation
import Combine

struct PanelAction: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var shortcut: String? = nil
    var destructive = false
    let run: () -> Void
}

@MainActor
final class PanelModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", pinned = "Pinned", snippets = "Snippets", text = "Text", links = "Links",
             code = "Code", colors = "Colors", images = "Images", files = "Files"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .pinned: return "pin.fill"
            case .snippets: return "text.quote"
            case .text: return "text.alignleft"
            case .links: return "link"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .colors: return "paintpalette"
            case .images: return "photo"
            case .files: return "doc"
            }
        }
        func includes(_ clip: Clip) -> Bool {
            switch self {
            case .all: return true
            case .pinned: return clip.isPinned
            case .snippets: return clip.isSnippet
            case .text: return clip.kind == .text
            case .links: if case .link = ClipContent.of(clip) { return true } else { return false }
            case .code: return ClipContent.of(clip) == .code
            case .colors: if case .color = ClipContent.of(clip) { return true } else { return false }
            case .images: return clip.kind == .image
            case .files: return clip.kind == .files
            }
        }
    }
    struct Section: Identifiable {
        let title: String
        let clips: [Clip]
        var id: String { title }
    }
    @Published var query = "" { didSet { selectedID = nil; marked = [] } }
    @Published var scope: Scope = .all { didSet { selectedID = nil; marked = [] } }
    @Published var selectedID: UUID?
    /// Extra clips chosen with ⌘-click or ⇧↑/↓, pasted together.
    @Published var marked: [UUID] = []
    @Published var focusToken = UUID()
    @Published var actions: [PanelAction] = []
    @Published var actionIndex = 0
    var actionsOpen: Bool { !actions.isEmpty }
    let store: ClipboardStore
    init(store: ClipboardStore) { self.store = store }

    var results: [Clip] {
        let now = Date()
        return ClipRules.matching(store.items, query: query).filter { clip in
            guard !clip.isExpired(at: now), scope.includes(clip) else { return false }
            // Snippets stay out of the everyday list until searched for or filtered to.
            return !(clip.isSnippet && scope == .all && query.isEmpty)
        }
    }
    /// Results grouped for display. Order is preserved, so flat indexes (⌘1–9) still line up.
    var sections: [Section] {
        let calendar = Calendar.current
        var groups: [(String, [Clip])] = []
        for clip in results {
            let title: String
            if clip.isSnippet { title = "Snippets" }
            else if clip.isPinned { title = "Pinned" }
            else if calendar.isDateInToday(clip.lastUsedAt) { title = "Today" }
            else if calendar.isDateInYesterday(clip.lastUsedAt) { title = "Yesterday" }
            else { title = "Earlier" }
            if groups.last?.0 == title { groups[groups.count - 1].1.append(clip) }
            else { groups.append((title, [clip])) }
        }
        return groups.map { Section(title: $0.0, clips: $0.1) }
    }
    var selected: Clip? { results.first { $0.id == selectedID } ?? results.first }
    /// The clips an action applies to: the marked ones in list order, or just the selection.
    var targets: [Clip] {
        guard !marked.isEmpty else { return selected.map { [$0] } ?? [] }
        let ids = Set(marked + [selected?.id].compactMap { $0 })
        return results.filter { ids.contains($0.id) }
    }
    func isMarked(_ id: UUID) -> Bool { marked.contains(id) }

    func move(_ delta: Int, extend: Bool = false) {
        let clips = results
        guard !clips.isEmpty else { return }
        let index = clips.firstIndex { $0.id == selected?.id } ?? 0
        if extend, let current = selected?.id, !marked.contains(current) { marked.append(current) }
        let next = clips[max(0, min(clips.count - 1, index + delta))].id
        if extend, !marked.contains(next) { marked.append(next) }
        selectedID = next
    }
    func toggleMark(_ id: UUID) {
        if marked.isEmpty, let current = selected?.id, current != id { marked = [current] }
        if let index = marked.firstIndex(of: id) { marked.remove(at: index) } else { marked.append(id) }
        selectedID = id
    }
    func cycleScope(_ delta: Int) {
        let all = Scope.allCases
        let index = all.firstIndex(of: scope) ?? 0
        scope = all[(index + delta + all.count) % all.count]
    }
    func moveAction(_ delta: Int) {
        guard !actions.isEmpty else { return }
        actionIndex = max(0, min(actions.count - 1, actionIndex + delta))
    }
    func closeActions() { actions = []; actionIndex = 0 }
    func reset() { query = ""; scope = .all; selectedID = nil; marked = []; closeActions(); focusToken = UUID() }
}
