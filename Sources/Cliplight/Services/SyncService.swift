import Foundation
import Combine
import CryptoKit
import CommonCrypto
import OSLog

/// Syncs pinned clips and snippets between Macs through iCloud Drive.
///
/// Each Mac writes one file to `iCloud Drive/Cliplight Sync/`, sealed with AES-GCM using a key derived from a
/// passphrase the user enters on every Mac. Apple only ever stores ciphertext. Everyday history is never synced.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Off"
    @Published private(set) var lastSync: Date?

    private let store: ClipboardStore
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "local.cliplight.app", category: "Sync")
    private var timer: Timer?
    private var pendingExport: DispatchWorkItem?
    private var key: SymmetricKey?

    /// Fingerprints this Mac stopped keeping, with when, so other Macs follow.
    private var tombstones: [String: Date] {
        get { (defaults.dictionary(forKey: "syncTombstones") as? [String: Date]) ?? [:] }
        set { defaults.set(newValue.filter { $0.value > Date().addingTimeInterval(-90 * 86_400) }, forKey: "syncTombstones") }
    }
    private var deviceID: String {
        if let id = defaults.string(forKey: "syncDeviceID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "syncDeviceID")
        return id
    }

    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    var folder: URL { Self.iCloudDrive.appendingPathComponent("Cliplight Sync", isDirectory: true) }
    var isICloudDriveAvailable: Bool { FileManager.default.fileExists(atPath: Self.iCloudDrive.path) }

    init(store: ClipboardStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        enabled = defaults.bool(forKey: "syncEnabled")
        store.onKeptChange = { [weak self] in self?.scheduleExport() }
        store.onKeptRemoved = { [weak self] clip in self?.tombstones[clip.fingerprint] = Date() }
    }

    func start() {
        guard enabled else { status = "Off"; return }
        guard let passphrase = Keychain.read("sync-passphrase").flatMap({ String(data: $0, encoding: .utf8) }) else {
            status = "Enter your sync passphrase."
            return
        }
        activate(passphrase: passphrase)
    }

    /// Turns sync on with a passphrase. Every Mac must use the same one.
    func enable(passphrase: String) {
        guard passphrase.count >= 8 else { status = "Use a passphrase of at least 8 characters."; return }
        guard isICloudDriveAvailable else { status = "Turn on iCloud Drive in System Settings first."; return }
        Keychain.write(Data(passphrase.utf8), account: "sync-passphrase")
        enabled = true
        defaults.set(true, forKey: "syncEnabled")
        activate(passphrase: passphrase)
    }
    func disable() {
        enabled = false
        defaults.set(false, forKey: "syncEnabled")
        timer?.invalidate(); timer = nil
        key = nil
        Keychain.delete("sync-passphrase")
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(deviceID).cliplightsync"))
        status = "Off"
    }

    private func activate(passphrase: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            key = try Self.deriveKey(passphrase: passphrase, salt: salt())
            status = "On"
            syncNow()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.syncNow() }
            }
            timer?.tolerance = 10
        } catch {
            status = "Couldn't start sync: \(error.localizedDescription)"
        }
    }

    /// A random salt shared by all Macs through the sync folder.
    private func salt() throws -> Data {
        let url = folder.appendingPathComponent("salt")
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        if let data = try? Data(contentsOf: url), data.count == 16 { return data }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, 16, &bytes) == errSecSuccess else { throw CocoaError(.featureUnsupported) }
        let data = Data(bytes)
        try data.write(to: url, options: .withoutOverwriting)
        return data
    }

    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let password = Array(passphrase.utf8).map { Int8(bitPattern: $0) }
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 310_000, &derived, derived.count)
        }
        guard status == kCCSuccess else { throw CocoaError(.featureUnsupported) }
        return SymmetricKey(data: derived)
    }

    struct Payload: Codable {
        var device: String
        var updatedAt: Date
        var clips: [Clip]
        var tombstones: [String: Date]
    }

    func scheduleExport() {
        guard enabled, key != nil else { return }
        pendingExport?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in self?.export() } }
        pendingExport = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func syncNow() {
        guard enabled, key != nil else { return }
        importOthers()
        export()
    }

    private func export() {
        guard let key else { return }
        let kept = store.items.filter(\.isKept).map { clip -> Clip in
            var copy = clip
            copy.expiresAt = nil
            return copy
        }
        let payload = Payload(device: deviceID, updatedAt: Date(), clips: kept, tombstones: tombstones)
        do {
            let sealed = try AES.GCM.seal(try JSONEncoder().encode(payload), using: key)
            guard let combined = sealed.combined else { return }
            try combined.write(to: folder.appendingPathComponent("\(deviceID).cliplightsync"), options: .atomic)
            lastSync = Date()
        } catch {
            status = "Couldn't write to iCloud Drive: \(error.localizedDescription)"
        }
    }

    private func importOthers() {
        guard let key else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var unreadable = 0
        var mergedTombstones = tombstones
        for file in files {
            let name = file.lastPathComponent
            // iCloud keeps files that aren't downloaded yet as hidden ".name.icloud" placeholders.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = file.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(7)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: real)
                continue
            }
            guard file.pathExtension == "cliplightsync", file.deletingPathExtension().lastPathComponent != deviceID,
                  let data = try? Data(contentsOf: file) else { continue }
            guard let box = try? AES.GCM.SealedBox(combined: data), let plain = try? AES.GCM.open(box, using: key),
                  let payload = try? JSONDecoder().decode(Payload.self, from: plain) else { unreadable += 1; continue }
            for (fingerprint, date) in payload.tombstones where (mergedTombstones[fingerprint] ?? .distantPast) < date {
                mergedTombstones[fingerprint] = date
                store.forget(synced: fingerprint, removedAfter: date)
            }
            for clip in payload.clips {
                if let removed = mergedTombstones[clip.fingerprint], removed >= clip.keptSince { continue }
                store.merge(synced: clip)
            }
        }
        tombstones = mergedTombstones
        status = unreadable > 0 ? "\(unreadable) Mac\(unreadable == 1 ? " uses" : "s use") a different passphrase." : "On"
        lastSync = Date()
        logger.info("Sync import finished")
    }
}
