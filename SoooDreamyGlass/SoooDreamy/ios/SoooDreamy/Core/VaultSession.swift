import CryptoKit
import Foundation
import Observation
import UIKit

/// A decrypted vault item, cached IN MEMORY ONLY while the vault is open.
/// Nothing decrypted ever touches disk, the widget snapshot or any backup.
struct DecryptedVaultItem {
    let meta: VaultMeta
    let content: Data

    var image: UIImage? {
        meta.kind == "photo"
            ? BoundedImageDecoder.image(data: content, maxPixelSize: 2_048)
            : nil
    }

    var posterImage: UIImage? {
        meta.poster.flatMap { BoundedImageDecoder.image(data: $0, maxPixelSize: 600) }
    }

    var noteText: String? {
        meta.kind == "note" ? String(data: content, encoding: .utf8) : nil
    }
}

/// Vault state machine: setup → locked → unlocked. Holds the derived key in
/// memory only while unlocked; locking wipes the key and every decrypted
/// byte. Face-ID re-unlock uses the biometric-gated Keychain copy.
@MainActor
@Observable
final class VaultSession {
    enum Phase {
        case loading          // fetching config
        case needsSetup       // no config on the server yet
        case locked
        case unlocked
    }

    private(set) var phase: Phase = .loading
    private(set) var config: VaultConfig?
    private(set) var items: [VaultItem] = []
    var errorMessage: String?

    @ObservationIgnored private var key: SymmetricKey?
    /// Decrypted blobs by item id — memory only, wiped on lock.
    @ObservationIgnored private var cache: [String: DecryptedVaultItem] = [:]
    /// Bumped whenever the cache gains an entry so views re-render.
    private(set) var cacheVersion = 0

    var biometricsAvailable: Bool { VaultKeychain.hasStoredKey }

    // MARK: Config

    func loadConfig(api: API?) async {
        guard let api else { return }
        phase = .loading
        do {
            config = try await api.vaultConfig()
            phase = config == nil ? .needsSetup : .locked
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
            phase = .needsSetup
        }
    }

    /// First-time setup: random salt, derive key from the chosen PIN, store
    /// the verifier on the server, unlock right away.
    func setup(pin: String, api: API?) async -> Bool {
        guard let api else { return false }
        do {
            let salt = VaultCrypto.randomSalt()
            let iterations = VaultCrypto.defaultIterations
            let derived = try await Self.derive(pin: pin, salt: salt, iterations: iterations)
            let verifier = try VaultCrypto.makeVerifier(key: derived)
            config = try await api.setVaultConfig(kdf: VaultCrypto.kdfName,
                                                  iterations: iterations,
                                                  salt: salt.base64EncodedString(),
                                                  verifier: verifier.base64EncodedString())
            key = derived
            VaultKeychain.store(derived)
            phase = .unlocked
            await refreshItems(api: api)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
            return false
        }
    }

    // MARK: Unlock / lock

    /// PIN unlock: derive + check against the server-stored verifier.
    func unlock(pin: String, api: API?) async -> Bool {
        guard let config, let salt = Data(base64Encoded: config.salt),
              let verifier = Data(base64Encoded: config.verifier) else { return false }
        guard let derived = try? await Self.derive(pin: pin, salt: salt,
                                                   iterations: config.iterations),
              VaultCrypto.checkVerifier(verifier, key: derived) else { return false }
        key = derived
        VaultKeychain.store(derived)
        phase = .unlocked
        if let api { await refreshItems(api: api) }
        return true
    }

    /// Face-ID / passcode unlock via the Keychain-stored key.
    func unlockWithBiometrics(api: API?) async -> Bool {
        let reason = L10n.t("vault.bioReason")
        let loaded = await Task.detached(priority: .userInitiated) {
            VaultKeychain.load(reason: reason)
        }.value
        guard let loaded else { return false }
        // The stored key might be stale after a vault reset — verify it.
        if let config, let verifier = Data(base64Encoded: config.verifier),
           !VaultCrypto.checkVerifier(verifier, key: loaded) {
            VaultKeychain.clear()
            return false
        }
        key = loaded
        phase = .unlocked
        if let api { await refreshItems(api: api) }
        return true
    }

    /// Locks the vault and wipes every decrypted byte from memory.
    func lock() {
        key = nil
        cache.removeAll()
        cacheVersion += 1
        if phase == .unlocked { phase = .locked }
    }

    // MARK: Items

    func refreshItems(api: API) async {
        if let list = try? await api.vaultItems() {
            items = list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func cached(_ itemId: String) -> DecryptedVaultItem? {
        cache[itemId]
    }

    /// Downloads + decrypts an item (cached afterwards). nil while locked.
    func decrypt(_ item: VaultItem, api: API?) async -> DecryptedVaultItem? {
        guard let key, let api else { return nil }
        if let hit = cache[item.id] { return hit }
        guard let blob = try? await api.vaultItemData(id: item.id) else { return nil }
        guard let opened = await Task.detached(priority: .userInitiated, operation: {
            try? VaultCrypto.openPackage(blob, key: key)
        }).value else { return nil }
        let decrypted = DecryptedVaultItem(meta: opened.meta, content: opened.content)
        cache[item.id] = decrypted
        cacheVersion += 1
        return decrypted
    }

    /// Seals + uploads content. Encryption runs off-main.
    func upload(meta: VaultMeta, content: Data, api: API?) async throws -> VaultItem {
        guard let key, let api else { throw VaultCryptoError.wrongKey }
        let blob = try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.sealPackage(meta: meta, content: content, key: key)
        }.value
        let item = try await api.uploadVaultItem(blob: blob, kind: meta.kind)
        cache[item.id] = DecryptedVaultItem(meta: meta, content: content)
        cacheVersion += 1
        apply(item)
        return item
    }

    func delete(_ item: VaultItem, api: API?) async throws {
        guard let api else { return }
        try await api.deleteVaultItem(id: item.id)
        items.removeAll { $0.id == item.id }
        cache[item.id] = nil
    }

    /// Wipes the whole vault (server + local key) — forgotten-PIN escape.
    func reset(api: API?) async throws {
        guard let api else { return }
        try await api.resetVault()
        lock()
        VaultKeychain.clear()
        config = nil
        items = []
        phase = .needsSetup
    }

    // MARK: Realtime

    func handle(_ event: ServerEvent) {
        switch event.type {
        case .vaultConfigSet:
            struct Payload: Codable { let config: VaultConfig }
            if let payload = event.decode(Payload.self) {
                config = payload.config
                if phase == .needsSetup { phase = .locked }
            }
        case .vaultItemAdded:
            if let item = event.decode(VaultItemResponse.self)?.item {
                apply(item)
            }
        case .vaultItemDeleted:
            if let id = event.decode(IdPayload.self)?.id {
                items.removeAll { $0.id == id }
                cache[id] = nil
            }
        case .vaultReset:
            lock()
            VaultKeychain.clear()
            config = nil
            items = []
            phase = .needsSetup
        default:
            break
        }
    }

    private func apply(_ item: VaultItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        items.sort { $0.createdAt > $1.createdAt }
    }

    // MARK: Helpers

    private static func derive(pin: String, salt: Data, iterations: Int) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            try VaultCrypto.deriveKey(pin: pin, salt: salt, iterations: iterations)
        }.value
    }
}
