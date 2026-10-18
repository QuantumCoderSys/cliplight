import Foundation
import Security
import CryptoKit

/// Minimal generic-password Keychain access, kept on this Mac only.
enum Keychain {
    static let service = "Cliplight"

    static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrLabel as String] = "Cliplight (\(account))"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// The key that encrypts history on disk. Created on first launch.
    ///
    /// Debug builds are signed ad hoc, so every rebuild looks like a new app to the Keychain and macOS would
    /// ask for permission on each launch. They keep a separate development key in a user-only file instead.
    static func historyKey(folder: URL) throws -> SymmetricKey {
        #if DEBUG
        let url = folder.appendingPathComponent("dev-history.key")
        if let data = try? Data(contentsOf: url), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try key.withUnsafeBytes { Data($0) }.write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return key
        #else
        if let data = read("history-key"), data.count == 32 { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        guard write(key.withUnsafeBytes { Data($0) }, account: "history-key") else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Couldn't use the history key in the Keychain."])
        }
        return key
        #endif
    }
}
