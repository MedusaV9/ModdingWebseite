import Foundation
import Security

/// Secrets shared by the app and widget extension. Nothing confidential is
/// mirrored through UserDefaults/App Group files. When a sideload signature
/// strips keychain-sharing, the app falls back to its private Keychain; widgets
/// then degrade to cached snapshots instead of exposing a token in defaults.
enum SharedKeychain {
    private static let service = "app.sooodreamy.session.v4"
    private static var sharedAccessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "SoooDreamyKeychainAccessGroup") as? String
    }
    private static let tokenPrefix = "profile-token:"
    private static let sessionPrefix = "profile-session:"
    private static let recoveryPrefix = "recovery-key:"
    private static let deviceAccount = "device-id"

    static func token(profileID: UUID) -> String? {
        read(account: tokenPrefix + profileID.uuidString)
    }

    @discardableResult
    static func setToken(_ token: String?, profileID: UUID) -> Bool {
        write(token, account: tokenPrefix + profileID.uuidString)
    }

    static func removeToken(profileID: UUID) {
        _ = write(nil, account: tokenPrefix + profileID.uuidString)
    }

    // MARK: Session ids (multi-device)

    // The own sessionId identifies THIS device's seat among the member's
    // devices: its suffix is compared against `origin.sessionSuffix` on WS
    // frames (echo detection) and against GET /api/sessions rows ("this
    // device"). It lives next to the token — same lifetime, same store —
    // and like the token it never touches UserDefaults or exports.

    static func sessionId(profileID: UUID) -> String? {
        read(account: sessionPrefix + profileID.uuidString)
    }

    @discardableResult
    static func setSessionId(_ sessionId: String?, profileID: UUID) -> Bool {
        write(sessionId, account: sessionPrefix + profileID.uuidString)
    }

    static func removeSessionId(profileID: UUID) {
        _ = write(nil, account: sessionPrefix + profileID.uuidString)
    }

    // MARK: Recovery keys (v10)

    // The recovery key is the member's proof-of-identity for
    // POST /api/couples/rejoin — it must OUTLIVE the session. It is stored as
    // a synchronizable item so the iCloud keychain carries it across
    // reinstalls and new phones; when a sideload signature blocks
    // synchronization, the write transparently degrades to a local item
    // (still survives "leave device" — only profile deletion removes it).

    static func recoveryKey(profileID: UUID) -> String? {
        readSynchronizable(account: recoveryPrefix + profileID.uuidString)
            ?? read(account: recoveryPrefix + profileID.uuidString)
    }

    /// Where the recovery key actually lives — so the UI can be honest about
    /// it instead of promising iCloud unconditionally. `.synchronizable` means
    /// the item is iCloud-capable (it travels when the user's iCloud keychain
    /// is on); `.localOnly` is the sideload-signature fallback that stays on
    /// this device and makes the paper backup essential.
    enum RecoveryKeyStorage {
        case synchronizable
        case localOnly
        case missing
    }

    static func recoveryKeyStorage(profileID: UUID) -> RecoveryKeyStorage {
        let account = recoveryPrefix + profileID.uuidString
        if readSynchronizable(account: account) != nil { return .synchronizable }
        if read(account: account) != nil { return .localOnly }
        return .missing
    }

    @discardableResult
    static func setRecoveryKey(_ key: String?, profileID: UUID) -> Bool {
        let account = recoveryPrefix + profileID.uuidString
        if key == nil {
            let sync = deleteSynchronizable(account: account)
            let local = write(nil, account: account)
            return sync || local
        }
        if writeSynchronizable(key, account: account) {
            _ = write(nil, account: account)   // avoid a stale local shadow
            return true
        }
        return write(key, account: account)
    }

    static func removeRecoveryKey(profileID: UUID) {
        _ = setRecoveryKey(nil, profileID: profileID)
    }

    static func deviceID() -> String {
        if let existing = read(account: deviceAccount), !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        _ = write(created, account: deviceAccount)
        return created
    }

    /// Widget/background helpers read only the currently active profile's
    /// token. The account name is metadata; the bearer value remains Keychain.
    static func activeToken(profileID: UUID) -> String? {
        token(profileID: profileID)
    }

    private static func baseQuery(account: String, shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared, let accessGroup = sharedAccessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func read(account: String) -> String? {
        if let shared = read(account: account, shared: true) { return shared }
        return read(account: account, shared: false)
    }

    private static func read(account: String, shared: Bool) -> String? {
        var query = baseQuery(account: account, shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ value: String?, account: String) -> Bool {
        guard sharedAccessGroup != nil else {
            let status = write(value, account: account, shared: false)
            return status == errSecSuccess || (value == nil && status == errSecItemNotFound)
        }
        if value == nil {
            // A token may have been written to the private fallback by an
            // older/sideloaded signature. Always clear both locations so a
            // stale local credential cannot reappear after entitlement changes.
            let sharedStatus = write(nil, account: account, shared: true)
            let localStatus = write(nil, account: account, shared: false)
            let accepted: Set<OSStatus> = [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement]
            return accepted.contains(sharedStatus) && accepted.contains(localStatus)
        }
        let sharedStatus = write(value, account: account, shared: true)
        if sharedStatus == errSecSuccess {
            // Shared storage is authoritative; remove a possible old fallback.
            _ = write(nil, account: account, shared: false)
            return true
        }
        // Free/sideload signatures may strip the access-group entitlement.
        let localStatus = write(value, account: account, shared: false)
        return localStatus == errSecSuccess
    }

    private static func write(_ value: String?, account: String, shared: Bool) -> OSStatus {
        let query = baseQuery(account: account, shared: shared)
        guard let value else { return SecItemDelete(query as CFDictionary) }
        guard let data = value.data(using: .utf8) else { return errSecParam }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updated != errSecItemNotFound { return updated }
        return SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil)
    }

    // MARK: Synchronizable items (iCloud keychain — recovery keys only)

    // Bearer tokens deliberately stay ThisDeviceOnly; the recovery key is the
    // ONE secret that is supposed to follow the user to a new phone.

    private static func synchronizableQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
        ]
    }

    private static func readSynchronizable(account: String) -> String? {
        var query = synchronizableQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeSynchronizable(_ value: String?, account: String) -> Bool {
        guard let value, let data = value.data(using: .utf8) else { return false }
        let query = synchronizableQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteSynchronizable(account: String) -> Bool {
        let status = SecItemDelete(synchronizableQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
