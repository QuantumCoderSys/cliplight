import AppKit

@MainActor
final class ClipboardMonitor {
    let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    private var timer: Timer?
    private var lastChange = Date.distantPast
    private var asleep = false
    private var observers: [NSObjectProtocol] = []

    init(store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.store = store; self.pasteboard = pasteboard
        self.changeCount = pasteboard.changeCount
    }

    /// macOS has no clipboard-change notification, so Cliplight polls. It checks quickly right after
    /// activity, backs off when idle, and stops entirely while the screen sleeps or is locked.
    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.sessionDidResignActiveNotification, true),
                                 (NSWorkspace.screensDidWakeNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.asleep = sleeping
                    if !sleeping { self.poll(); self.schedule() }
                }
            })
        }
        schedule()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }
    /// The current polling interval: 0.25 s just after a copy, easing to 1 s after a minute of quiet.
    var interval: TimeInterval {
        let idle = Date().timeIntervalSince(lastChange)
        if idle < 10 { return 0.25 }
        if idle < 60 { return 0.5 }
        return 1.0
    }
    private func schedule() {
        timer?.invalidate()
        guard !asleep else { return }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.poll(); self?.schedule() }
        }
        next.tolerance = interval * 0.25
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func poll(sourceName: String? = nil, sourceID: String? = nil) {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        lastChange = Date()
        guard !store.isPaused else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let appID = sourceID ?? front?.bundleIdentifier
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !ClipRules.shouldSkip(types: types, sourceID: appID, ignored: Set(store.ignoredApps), skipPasswordManagers: store.excludePrivateApps) else { return }
        let source = sourceName ?? front?.localizedName ?? "Clipboard"
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            store.insert(Clip(kind: .files, text: urls.map(\.absoluteString).joined(separator: "\n"), source: source, sourceBundleID: appID))
        } else if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= 1_024 * 1_024 else { store.message = "A text clip over 1 MB was skipped."; return }
            let rtf = pasteboard.data(forType: .rtf).flatMap { $0.count <= 1_024 * 1_024 ? $0 : nil }
            store.insert(Clip(kind: .text, text: text, richText: rtf, source: source, sourceBundleID: appID))
        } else {
            let bytes = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            guard let bytes, bytes.count <= 20 * 1_024 * 1_024,
                  let image = NSImage(data: bytes),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]), png.count <= 5 * 1_024 * 1_024 else { return }
            let clip = Clip(kind: .image, text: "Image · \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)", data: png, source: source, sourceBundleID: appID)
            store.insert(clip)
            ImageText.recognize(clip, in: store)
        }
    }

    /// Puts a clip on the clipboard. `plain` drops formatting.
    @discardableResult
    func copy(_ clip: Clip, plain: Bool = false) -> Bool {
        copy([clip], plain: plain)
    }

    /// Puts one or more clips on the clipboard. Several text clips are joined with new lines;
    /// several files are copied together; a mix is written as separate pasteboard items.
    @discardableResult
    func copy(_ clips: [Clip], plain: Bool = false) -> Bool {
        guard !clips.isEmpty else { return false }
        if clips.contains(where: { $0.kind == .files && $0.fileURLs.contains { !FileManager.default.fileExists(atPath: $0.path) } }) {
            store.message = "One of these files has moved or no longer exists."
            return false
        }
        pasteboard.clearContents()
        var success = false
        if clips.count > 1 && clips.allSatisfy({ $0.kind == .text }) {
            success = pasteboard.setString(clips.map(\.text).joined(separator: "\n"), forType: .string)
        } else if clips.allSatisfy({ $0.kind == .files }) {
            success = pasteboard.writeObjects(clips.flatMap(\.fileURLs).map { $0 as NSURL })
        } else {
            success = pasteboard.writeObjects(clips.compactMap { item(for: $0, plain: plain) })
        }
        changeCount = pasteboard.changeCount
        if success { clips.forEach { store.touch($0.id) } }
        else { store.message = "This item couldn't be copied. Try another clip." }
        return success
    }

    /// Puts transformed text on the clipboard without adding it to history.
    @discardableResult
    func copy(text: String) -> Bool {
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount
        return success
    }

    private func item(for clip: Clip, plain: Bool) -> NSPasteboardWriting? {
        switch clip.kind {
        case .text:
            let item = NSPasteboardItem()
            item.setString(clip.text, forType: .string)
            if !plain, store.preserveFormatting, let rtf = clip.richText { item.setData(rtf, forType: .rtf) }
            return item
        case .image:
            guard let data = clip.data else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            return item
        case .files:
            return clip.fileURLs.first.map { $0 as NSURL }
        }
    }
}
