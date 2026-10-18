import AppKit
import Combine
import CryptoKit

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [Clip] = []
    @Published var isPaused = false
    @Published var message: String?
    @Published var preserveFormatting = true {
        didSet { defaults.set(preserveFormatting, forKey: "preserveFormatting") }
    }
    @Published var excludePrivateApps = true {
        didSet { defaults.set(excludePrivateApps, forKey: "excludePrivateApps") }
    }
    @Published var directPaste = true {
        didSet { defaults.set(directPaste, forKey: "directPaste") }
    }
    @Published var retention: Retention = .month {
        didSet { defaults.set(retention.rawValue, forKey: "retention"); replace(ClipRules.trimmed(items, retention: retention)) }
    }
    /// Seconds before one-time codes and password-like clips are deleted. 0 keeps them.
    @Published var secretLifetime = 60 {
        didSet { defaults.set(secretLifetime, forKey: "secretLifetime") }
    }
    /// Bundle identifiers whose copies are never recorded.
    @Published var ignoredApps: [String] = [] {
        didSet { defaults.set(ignoredApps, forKey: "ignoredApps") }
    }

    /// Called after pins or snippets change, so sync can publish them.
    var onKeptChange: (() -> Void)?
    /// Called when a pinned clip or snippet stops being kept (unpinned or deleted).
    var onKeptRemoved: ((Clip) -> Void)?

    private let defaults: UserDefaults
    private var database: HistoryDatabase?
    private let io = DispatchQueue(label: "local.cliplight.history", qos: .utility)
    private var sweeper: Timer?

    init(directory: URL? = nil, ephemeral: Bool = false, defaults: UserDefaults = .standard, key: SymmetricKey? = nil) {
        self.defaults = defaults
        preserveFormatting = defaults.object(forKey: "preserveFormatting") as? Bool ?? true
        excludePrivateApps = defaults.object(forKey: "excludePrivateApps") as? Bool ?? true
        directPaste = defaults.object(forKey: "directPaste") as? Bool ?? true
        retention = Retention(rawValue: defaults.object(forKey: "retention") as? Int ?? Retention.month.rawValue) ?? .month
        secretLifetime = defaults.object(forKey: "secretLifetime") as? Int ?? 60
        ignoredApps = defaults.stringArray(forKey: "ignoredApps") ?? []
        if ephemeral { return }
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cliplight", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            #if DEBUG
            let file = "history-dev.sqlite"
            #else
            let file = "history.sqlite"
            #endif
            let database = try HistoryDatabase(url: folder.appendingPathComponent(file), key: key ?? Keychain.historyKey(folder: folder))
            self.database = database
            var loaded = try database.loadAll()
            loaded += try migrateLegacyJSON(in: folder, into: database)
            items = ClipRules.trimmed(loaded, retention: retention)
            let dropped = Set(loaded.map(\.id)).subtracting(items.map(\.id))
            try database.delete(Array(dropped))
            if database.unreadableRows > 0 {
                message = "\(database.unreadableRows) saved clips couldn't be decrypted and were skipped."
            }
        } catch { message = "History could not be loaded. New clips will still appear. \(error.localizedDescription)" }
    }

    /// Moves history from the 1.0 JSON file into the encrypted database, then removes the plain file.
    private func migrateLegacyJSON(in folder: URL, into database: HistoryDatabase) throws -> [Clip] {
        let legacy = folder.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return [] }
        let bytes = try Data(contentsOf: legacy)
        let clips: [Clip]
        do { clips = try JSONDecoder().decode([Clip].self, from: bytes) } catch {
            // Never delete history we couldn't read. Set it aside so a later version (or the user) can recover it.
            let aside = folder.appendingPathComponent("history-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: legacy, to: aside)
            message = "Older history couldn't be read. It was kept at \(aside.path)."
            return []
        }
        try database.upsert(clips)
        try? Data(count: bytes.count).write(to: legacy)
        try? FileManager.default.removeItem(at: legacy)
        return clips
    }

    // MARK: - Changes

    func insert(_ incoming: Clip) {
        var clip = incoming
        if let old = items.first(where: { $0.fingerprint == clip.fingerprint }) {
            clip.id = old.id; clip.createdAt = old.createdAt
            clip.isPinned = old.isPinned; clip.snippetName = old.snippetName
            clip.expiresAt = old.expiresAt; clip.keptAt = old.keptAt
        }
        if clip.kind == .text, !clip.isKept, secretLifetime > 0, ClipContent.looksSecret(clip.text) {
            clip.expiresAt = Date().addingTimeInterval(TimeInterval(secretLifetime))
        }
        replace(ClipRules.trimmed(items.filter { $0.id != clip.id } + [clip], retention: retention), changed: [clip])
    }
    /// Adds or updates a kept clip that arrived from another Mac.
    func merge(synced clip: Clip) {
        if let index = items.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            var local = items[index]
            guard local.isPinned != clip.isPinned || local.snippetName != clip.snippetName else { return }
            local.isPinned = local.isPinned || clip.isPinned
            local.snippetName = local.snippetName ?? clip.snippetName
            local.keptAt = max(local.keptAt ?? .distantPast, clip.keptSince)
            local.expiresAt = nil
            update(local, notify: false)
        } else {
            var copy = clip
            copy.expiresAt = nil
            replace(ClipRules.trimmed(items + [copy], retention: retention), changed: [copy])
        }
    }
    func pin(_ id: UUID) {
        guard var clip = items.first(where: { $0.id == id }) else { return }
        clip.isPinned.toggle()
        clip.expiresAt = nil
        if clip.isPinned { clip.keptAt = Date() }
        if !clip.isPinned && !clip.isSnippet { onKeptRemoved?(clip) }
        update(clip)
    }
    func unpin(_ id: UUID) {
        guard let clip = items.first(where: { $0.id == id }), clip.isPinned else { return }
        pin(id)
    }
    func saveSnippet(_ id: UUID, name: String) {
        guard var clip = items.first(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clip.isSnippet && trimmed.isEmpty && !clip.isPinned { onKeptRemoved?(clip) }
        clip.snippetName = trimmed.isEmpty ? nil : trimmed
        clip.expiresAt = nil
        if clip.isSnippet { clip.keptAt = Date() }
        update(clip)
    }
    func addSnippet(name: String, text: String) {
        var clip = Clip(kind: .text, text: text, source: "Snippet")
        clip.snippetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.keptAt = Date()
        if let old = items.first(where: { $0.fingerprint == clip.fingerprint }) {
            clip.id = old.id; clip.isPinned = old.isPinned
        }
        replace(ClipRules.trimmed(items.filter { $0.id != clip.id } + [clip], retention: retention), changed: [clip])
    }
    func updateSnippet(_ id: UUID, name: String, text: String) {
        guard var clip = items.first(where: { $0.id == id }) else { return }
        if clip.text != text { onKeptRemoved?(clip) }
        clip.snippetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.text = text; clip.richText = nil
        clip.keptAt = Date()
        update(clip)
    }
    func remove(_ id: UUID) {
        guard let clip = items.first(where: { $0.id == id }) else { return }
        if clip.isKept { onKeptRemoved?(clip) }
        replace(items.filter { $0.id != id })
    }
    /// Removes kept state for a clip another Mac stopped keeping.
    func forget(synced fingerprint: String, removedAfter: Date) {
        guard let clip = items.first(where: { $0.fingerprint == fingerprint && $0.isKept }), clip.keptSince < removedAfter else { return }
        if clip.isSnippet { replace(items.filter { $0.id != clip.id }) }
        else { var unpinned = clip; unpinned.isPinned = false; update(unpinned, notify: false) }
    }
    func clearUnpinned() { replace(items.filter(\.isKept)) }
    func clearAll() {
        items.filter(\.isKept).forEach { onKeptRemoved?($0) }
        items = []
        io.async { [database] in try? database?.deleteAll() }
        onKeptChange?()
    }
    func touch(_ id: UUID) {
        guard var clip = items.first(where: { $0.id == id }) else { return }
        clip.lastUsedAt = Date()
        update(clip, notify: false)
    }
    func attach(recognizedText: String, to id: UUID) {
        guard var clip = items.first(where: { $0.id == id }) else { return }
        clip.recognizedText = recognizedText
        update(clip, notify: false)
    }
    func ignore(bundleID: String) {
        guard !ignoredApps.contains(bundleID) else { return }
        ignoredApps.append(bundleID)
    }

    /// Deletes expired secrets. Runs every couple of seconds while the app is open.
    func startSweeping() {
        sweeper = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
        sweeper?.tolerance = 0.5
    }
    func sweep(now: Date = Date()) {
        guard items.contains(where: { $0.isExpired(at: now) }) else { return }
        replace(items.filter { !$0.isExpired(at: now) })
    }

    private func update(_ clip: Clip, notify: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == clip.id }) else { return }
        let wasKept = items[index].isKept
        var next = items
        next[index] = clip
        replace(ClipRules.ordered(next), changed: [clip], notify: notify && (wasKept || clip.isKept))
    }

    private func replace(_ next: [Clip], changed: [Clip] = [], notify: Bool = true) {
        let removed = Set(items.map(\.id)).subtracting(next.map(\.id))
        let keptChanged = notify && (items.contains { removed.contains($0.id) && $0.isKept } || changed.contains(where: \.isKept))
        items = next
        let survivors = changed.filter { clip in next.contains { $0.id == clip.id } }
        if let database {
            io.async { [weak self] in
                do {
                    try database.delete(Array(removed))
                    try database.upsert(survivors)
                } catch {
                    let detail = error.localizedDescription
                    DispatchQueue.main.async { self?.message = "Couldn't save history: \(detail)" }
                }
            }
        }
        if keptChanged { onKeptChange?() }
    }
    func flush() { io.sync {} }
}
