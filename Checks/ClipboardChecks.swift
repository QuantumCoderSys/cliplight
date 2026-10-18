import AppKit
import CryptoKit

@MainActor
final class ClipRulesTests {
    func testSearchMatchesAllWordsAcrossContentAndSource() {
        let clip = Clip(kind: .text, text: "Café project notes", source: "Safari")
        XCTAssertEqual(ClipRules.matching([clip], query: "cafe SAFARI").count, 1)
        XCTAssertTrue(ClipRules.matching([clip], query: "missing Safari").isEmpty)
        var snippet = Clip(kind: .text, text: "Jane Appleseed\n1 Infinite Loop", source: "Snippet")
        snippet.snippetName = "addr"
        let other = Clip(kind: .text, text: "address book export", source: "Notes")
        XCTAssertEqual(ClipRules.matching([other, snippet], query: "addr").first?.id, snippet.id)
        var image = Clip(kind: .image, text: "Image · 10 × 10", source: "Screenshot")
        image.recognizedText = "Invoice 2026-118"
        XCTAssertEqual(ClipRules.matching([image], query: "invoice").count, 1)
    }
    func testConfidentialPasswordManagerAndIgnoredAppsAreSkipped() {
        XCTAssertTrue(ClipRules.shouldSkip(types: ["org.nspasteboard.ConcealedType"], sourceID: nil))
        XCTAssertTrue(ClipRules.shouldSkip(types: ["org.nspasteboard.TransientType"], sourceID: nil))
        XCTAssertTrue(ClipRules.shouldSkip(types: [], sourceID: "com.1password.1password"))
        XCTAssertFalse(ClipRules.shouldSkip(types: [], sourceID: "com.1password.1password", skipPasswordManagers: false))
        XCTAssertTrue(ClipRules.shouldSkip(types: [], sourceID: "com.example.bank", ignored: ["com.example.bank"]))
        XCTAssertFalse(ClipRules.shouldSkip(types: ["public.utf8-plain-text"], sourceID: "com.apple.TextEdit"))
    }
    func testRetentionPinsAndLimits() {
        let now = Date()
        var old = Clip(kind: .text, text: "old", source: "Test"); old.lastUsedAt = now.addingTimeInterval(-10 * 86_400)
        var oldPinned = Clip(kind: .text, text: "old pinned", source: "Test"); oldPinned.lastUsedAt = old.lastUsedAt; oldPinned.isPinned = true
        let fresh = Clip(kind: .text, text: "fresh", source: "Test")
        let week = ClipRules.trimmed([old, oldPinned, fresh], retention: .week, now: now)
        XCTAssertEqual(week.map(\.text), ["old pinned", "fresh"])
        XCTAssertEqual(ClipRules.trimmed([old, oldPinned, fresh], retention: .forever, now: now).count, 3)
        let many = (0..<(ClipRules.maxItems + 20)).map { Clip(kind: .text, text: "clip \($0)", source: "Test") }
        XCTAssertEqual(ClipRules.trimmed(many).count, ClipRules.maxItems)
        let oversized = Clip(kind: .image, text: "image", data: Data(count: ClipRules.maxBytes + 1), source: "Test")
        XCTAssertTrue(ClipRules.trimmed([oversized]).isEmpty)
    }
    func testContentDetection() {
        XCTAssertEqual(ClipContent.detect("#FF9500"), .color(RGBColor(red: 1, green: 149.0 / 255, blue: 0)))
        XCTAssertEqual(RGBColor(parsing: "rgb(255, 149, 0)")?.hex, "#FF9500")
        XCTAssertEqual(RGBColor(parsing: "#f90")?.hex, "#FF9900")
        XCTAssertEqual(ClipContent.detect("https://apple.com/mac"), .link(URL(string: "https://apple.com/mac")!))
        XCTAssertEqual(ClipContent.detect("tim@apple.com"), .email("tim@apple.com"))
        XCTAssertEqual(ClipContent.detect("func greet() {\n    return \"hi\";\n}"), .code)
        XCTAssertEqual(ClipContent.detect("Lunch at noon?"), .plain)
        XCTAssertEqual(ClipContent.detect("123456"), .plain)
    }
    func testSecretDetection() {
        XCTAssertTrue(ClipContent.looksSecret("087472"))
        XCTAssertTrue(ClipContent.looksSecret("123-456"))
        XCTAssertTrue(ClipContent.looksSecret("Tr0ub4dor&3xyz"))
        XCTAssertTrue(ClipContent.looksSecret("demo_token_000000_NOT_A_CREDENTIAL"))
        XCTAssertFalse(ClipContent.looksSecret("Hello there, friend"))
        XCTAssertFalse(ClipContent.looksSecret("https://apple.com/a1B2"))
        XCTAssertFalse(ClipContent.looksSecret("#FF9500"))
        XCTAssertFalse(ClipContent.looksSecret("2026"))
        XCTAssertFalse(ClipContent.looksSecret("SearchPanel"))
    }
    func testTransforms() {
        XCTAssertEqual(TextTransform.cleanLink.apply("https://example.com/a?id=4&utm_source=x&fbclid=y"), "https://example.com/a?id=4")
        XCTAssertNil(TextTransform.cleanLink.apply("https://example.com/a?id=4"))
        XCTAssertEqual(TextTransform.minifyJSON.apply("{ \"a\" : [1, 2] }"), "{\"a\":[1,2]}")
        XCTAssertNil(TextTransform.formatJSON.apply("not json"))
        XCTAssertEqual(TextTransform.trimWhitespace.apply("  hi  \n  there "), "hi\nthere")
        XCTAssertEqual(TextTransform.titleCase.apply("hello world"), "Hello World")
    }
    func testShortcutGlyphs() {
        XCTAssertEqual(Shortcut.commandShiftV.glyphs, "⇧⌘V")
        XCTAssertEqual(Shortcut.optionSpace.glyphs, "⌥Space")
        let defaults = UserDefaults(suiteName: "cliplight.checks.\(UUID())")!
        defaults.set("controlShiftV", forKey: "shortcut")
        XCTAssertEqual(HotKeyManager(defaults: defaults).choice, .commandShiftV)
        defaults.set("optionSpace", forKey: "shortcut")
        XCTAssertEqual(HotKeyManager(defaults: defaults).choice, .optionSpace)
    }
}

@MainActor
final class ClipboardIntegrationTests {
    let key = SymmetricKey(size: .bits256)
    func defaults() -> UserDefaults { UserDefaults(suiteName: "cliplight.checks.\(UUID())")! }

    func testEncryptedPersistencePinsAndClear() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = defaults()
        let store = ClipboardStore(directory: folder, defaults: settings, key: key)
        let clip = Clip(kind: .text, text: "Keep this secret-free text", source: "Test")
        store.insert(clip)
        store.pin(clip.id)
        store.insert(Clip(kind: .text, text: "Keep this secret-free text", source: "Test"))
        store.insert(Clip(kind: .text, text: "Another clip", source: "Test"))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.first?.id, clip.id)
        XCTAssertTrue(store.items.first!.isPinned)
        store.flush()
        let databaseURL = folder.appendingPathComponent("history.sqlite")
        let raw = try Data(contentsOf: databaseURL)
        XCTAssertNil(raw.range(of: Data("Another clip".utf8)))
        let permissions = try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        let loaded = ClipboardStore(directory: folder, defaults: settings, key: key)
        XCTAssertEqual(loaded.items, store.items)
        let wrongKey = ClipboardStore(directory: folder, defaults: settings, key: SymmetricKey(size: .bits256))
        XCTAssertTrue(wrongKey.items.isEmpty)
        XCTAssertNotNil(wrongKey.message)
        loaded.clearUnpinned()
        XCTAssertEqual(loaded.items.count, 1)
        loaded.clearAll()
        loaded.flush()
        XCTAssertTrue(ClipboardStore(directory: folder, defaults: settings, key: key).items.isEmpty)
    }
    func testLegacyJSONIsMigratedAndRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = [Clip(kind: .text, text: "From version one", source: "Old")]
        try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("history.json"))
        let settings = defaults()
        let store = ClipboardStore(directory: folder, defaults: settings, key: key)
        XCTAssertEqual(store.items.map(\.text), ["From version one"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("history.json").path))
        store.flush()
        XCTAssertEqual(ClipboardStore(directory: folder, defaults: settings, key: key).items.map(\.text), ["From version one"])
        // An unreadable legacy file is set aside, never deleted.
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: other) }
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: other.appendingPathComponent("history.json"))
        let broken = ClipboardStore(directory: other, defaults: defaults(), key: key)
        XCTAssertNotNil(broken.message)
        let kept = try FileManager.default.contentsOfDirectory(atPath: other.path).filter { $0.hasPrefix("history-unreadable-") }
        XCTAssertEqual(kept.count, 1)
    }
    func testSecretsExpireUnlessKept() {
        let store = ClipboardStore(ephemeral: true, defaults: defaults())
        store.secretLifetime = 60
        store.insert(Clip(kind: .text, text: "481516", source: "Messages"))
        store.insert(Clip(kind: .text, text: "Normal sentence here", source: "Notes"))
        let code = store.items.first { $0.text == "481516" }!
        XCTAssertNotNil(code.expiresAt)
        XCTAssertNil(store.items.first { $0.text == "Normal sentence here" }!.expiresAt)
        store.sweep(now: Date().addingTimeInterval(61))
        XCTAssertFalse(store.items.contains { $0.text == "481516" })
        store.insert(Clip(kind: .text, text: "Tr0ub4dor&3xyz", source: "Safari"))
        let password = store.items.first { $0.text == "Tr0ub4dor&3xyz" }!
        store.pin(password.id)
        store.sweep(now: Date().addingTimeInterval(120))
        XCTAssertTrue(store.items.contains { $0.text == "Tr0ub4dor&3xyz" })
        store.secretLifetime = 0
        store.insert(Clip(kind: .text, text: "999000", source: "Messages"))
        XCTAssertNil(store.items.first { $0.text == "999000" }!.expiresAt)
    }
    func testSnippetsAndSyncMerging() {
        let store = ClipboardStore(ephemeral: true, defaults: defaults())
        var removed: [String] = []
        store.onKeptRemoved = { removed.append($0.fingerprint) }
        store.addSnippet(name: "sig", text: "— Sent from Cliplight")
        let snippet = store.items.first!
        XCTAssertTrue(snippet.isSnippet)
        XCTAssertEqual(store.items.first?.snippetName, "sig")
        var remote = Clip(kind: .text, text: "Pinned on my other Mac", source: "Notes")
        remote.isPinned = true; remote.keptAt = Date()
        store.merge(synced: remote)
        XCTAssertTrue(store.items.contains { $0.text == "Pinned on my other Mac" && $0.isPinned })
        store.merge(synced: remote)
        XCTAssertEqual(store.items.filter { $0.text == "Pinned on my other Mac" }.count, 1)
        store.forget(synced: remote.fingerprint, removedAfter: Date().addingTimeInterval(5))
        XCTAssertFalse(store.items.first { $0.text == "Pinned on my other Mac" }!.isPinned)
        store.remove(snippet.id)
        XCTAssertEqual(removed, [snippet.fingerprint])
        let salt = Data(repeating: 7, count: 16)
        let a = try! SyncService.deriveKey(passphrase: "correct horse", salt: salt)
        let b = try! SyncService.deriveKey(passphrase: "correct horse", salt: salt)
        let c = try! SyncService.deriveKey(passphrase: "wrong horse", salt: salt)
        XCTAssertTrue(a == b)
        XCTAssertFalse(a == c)
    }
    func testMonitorDeduplicatesRestoresAndJoins() throws {
        let board = NSPasteboard(name: .init("local.cliplight.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        let store = ClipboardStore(ephemeral: true, defaults: defaults())
        let monitor = ClipboardMonitor(store: store, pasteboard: board)
        board.clearContents(); board.setString("Hello clipboard", forType: .string)
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertEqual(store.items.first?.text, "Hello clipboard")
        board.clearContents(); board.setString("Second item", forType: .string)
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertEqual(store.items.count, 2)
        let first = try XCTUnwrap(store.items.first { $0.text == "Hello clipboard" })
        XCTAssertTrue(monitor.copy(first))
        XCTAssertEqual(board.string(forType: .string), "Hello clipboard")
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(monitor.copy([store.items[1], store.items[0]]))
        XCTAssertEqual(board.string(forType: .string), "\(store.items[1].text)\n\(store.items[0].text)")
        let rich = Clip(kind: .text, text: "Bold", richText: Data("{\\rtf1 Bold}".utf8), source: "Test")
        XCTAssertTrue(monitor.copy(rich, plain: true))
        XCTAssertNil(board.data(forType: .rtf))
        XCTAssertTrue(monitor.copy(text: "Transformed"))
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertFalse(store.items.contains { $0.text == "Transformed" })
        store.isPaused = true
        board.clearContents(); board.setString("Don't record", forType: .string)
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertFalse(store.items.contains { $0.text == "Don't record" })
        store.isPaused = false
        board.clearContents(); board.setString("Secret", forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        monitor.poll(sourceName: "Test App", sourceID: "local.test")
        XCTAssertFalse(store.items.contains { $0.text == "Secret" })
        store.ignore(bundleID: "com.example.bank")
        board.clearContents(); board.setString("Account balance", forType: .string)
        monitor.poll(sourceName: "Bank", sourceID: "com.example.bank")
        XCTAssertFalse(store.items.contains { $0.text == "Account balance" })
    }
    func testImageAndFileRoundTrip() throws {
        let board = NSPasteboard(name: .init("local.cliplight.tests.\(UUID())"))
        defer { board.releaseGlobally() }
        let store = ClipboardStore(ephemeral: true, defaults: defaults())
        let monitor = ClipboardMonitor(store: store, pasteboard: board)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), atX: 0, y: 0)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        board.clearContents(); board.setData(png, forType: .png)
        monitor.poll(sourceName: "Image Test", sourceID: "local.test")
        let image = try XCTUnwrap(store.items.first)
        XCTAssertEqual(image.kind, .image)
        XCTAssertTrue(monitor.copy(image))
        XCTAssertNotNil(board.data(forType: .png))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        board.clearContents(); board.writeObjects([url as NSURL])
        monitor.poll(sourceName: "File Test", sourceID: "local.test")
        let file = try XCTUnwrap(store.items.first { $0.kind == .files })
        XCTAssertEqual(file.fileURLs, [url])
        XCTAssertTrue(monitor.copy(file))
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(monitor.copy(file))
    }
    func testTextRecognitionFindsWordsInImages() throws {
        let size = NSSize(width: 520, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("Quarterly Invoice" as NSString).draw(at: NSPoint(x: 20, y: 35), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let text = try XCTUnwrap(ImageText.recognize(png))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("invoice"))
    }
    func testSelectionFiltersAndMultiSelect() {
        let store = ClipboardStore(ephemeral: true, defaults: defaults())
        store.insert(Clip(kind: .text, text: "Alpha", source: "Test"))
        store.insert(Clip(kind: .text, text: "#336699", source: "Test"))
        store.insert(Clip(kind: .text, text: "https://swift.org", source: "Test"))
        store.addSnippet(name: "greet", text: "Hello from a snippet")
        let model = PanelModel(store: store)
        XCTAssertFalse(model.results.contains { $0.isSnippet })
        XCTAssertEqual(model.selected?.text, "https://swift.org")
        model.move(1, extend: true)
        XCTAssertEqual(model.targets.map(\.text), ["https://swift.org", "#336699"])
        model.scope = .colors
        XCTAssertEqual(model.results.map(\.text), ["#336699"])
        XCTAssertTrue(model.marked.isEmpty)
        model.scope = .links
        XCTAssertEqual(model.results.map(\.text), ["https://swift.org"])
        model.scope = .all
        model.query = "gre"
        XCTAssertEqual(model.selected?.snippetName, "greet")
        model.query = "alpha"
        store.remove(model.selected!.id)
        XCTAssertNil(model.selected)
    }
}

@MainActor func XCTAssertTrue(_ value: @autoclosure () -> Bool, line: Int = #line) { precondition(value(), "Expected true (line \(line))") }
@MainActor func XCTAssertFalse(_ value: @autoclosure () -> Bool, line: Int = #line) { precondition(!value(), "Expected false (line \(line))") }
@MainActor func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, line: Int = #line) {
    let (x, y) = (a(), b())
    precondition(x == y, "Expected equal values (line \(line)): \(x) vs \(y)")
}
@MainActor func XCTAssertNil<T>(_ value: @autoclosure () -> T?, line: Int = #line) { precondition(value() == nil, "Expected nil (line \(line))") }
@MainActor func XCTAssertNotNil<T>(_ value: @autoclosure () -> T?, line: Int = #line) { precondition(value() != nil, "Expected value (line \(line))") }
@MainActor func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw CocoaError(.coderValueNotFound) }; return value }

@main
struct ClipboardChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var passed = 0
        func check(_ name: String, _ body: () throws -> Void) rethrows {
            try body(); passed += 1; print("PASS \(name)")
        }
        let rules = ClipRulesTests()
        check("Search across content, source, snippet names and image text", rules.testSearchMatchesAllWordsAcrossContentAndSource)
        check("Confidential, password-manager and ignored-app exclusion", rules.testConfidentialPasswordManagerAndIgnoredAppsAreSkipped)
        check("Retention, pins, item cap and storage budget", rules.testRetentionPinsAndLimits)
        check("Colors, links, emails and code are recognized", rules.testContentDetection)
        check("One-time codes, passwords and tokens are recognized", rules.testSecretDetection)
        check("Quick-fix text transforms", rules.testTransforms)
        check("Shortcut glyphs and migration to ⇧⌘V", rules.testShortcutGlyphs)
        let integration = ClipboardIntegrationTests()
        try check("Encrypted persistence, wrong-key safety, private permissions, clear", integration.testEncryptedPersistencePinsAndClear)
        try check("1.0 JSON history migrates; unreadable files are kept, not deleted", integration.testLegacyJSONIsMigratedAndRemoved)
        check("Secrets expire automatically unless pinned", integration.testSecretsExpireUnlessKept)
        check("Snippets, sync merge, tombstones and key derivation", integration.testSnippetsAndSyncMerging)
        try check("Capture, restore, join, plain text, pause, ignored apps", integration.testMonitorDeduplicatesRestoresAndJoins)
        try check("Image and file round-trip, missing-file recovery", integration.testImageAndFileRoundTrip)
        try check("On-device text recognition in images", integration.testTextRecognitionFindsWordsInImages)
        check("Filters, multi-select and snippet keywords", integration.testSelectionFiltersAndMultiSelect)
        print("\(passed) checks passed. The system clipboard was not modified.")
    }
}
