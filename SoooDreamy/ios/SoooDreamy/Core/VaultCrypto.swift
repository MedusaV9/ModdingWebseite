import CommonCrypto
import CryptoKit
import Foundation
import Security

// Spicy Vault crypto — architecture:
//
//   vault key  = PBKDF2-SHA256(PIN, per-couple random salt, 210k iterations)
//   item blob  = AES-GCM(key) over [u32-be metaLen][meta JSON][content bytes]
//   verifier   = AES-GCM(key) over a fixed known plaintext (PIN check)
//
// The salt + verifier + KDF params are stored openly on the couple server;
// the PIN (and therefore the key) never leaves the devices — true end-to-end.
// Both partners derive the SAME key from the SAME shared PIN, so everything
// either of them seals can be opened by the other.
//
// Face-ID convenience: after a successful PIN unlock the derived key is kept
// in the local Keychain behind `.userPresence` (ThisDeviceOnly, never synced),
// so the next unlock is a biometric prompt instead of typing.

/// Metadata sealed INSIDE each blob (never visible to the server).
struct VaultMeta: Codable {
    var kind: String                 // "photo" | "video" | "note"
    var caption: String?
    /// Small poster JPEG for grid previews (videos + photos alike).
    var poster: Data?
    var duration: Double?
    var width: Int?
    var height: Int?
}

enum VaultCryptoError: Error {
    case keyDerivationFailed
    case malformedBlob
    case wrongKey
}

enum VaultCrypto {
    static let kdfName = "pbkdf2-sha256"
    static let defaultIterations = 210_000
    private static let verifierPlaintext = Data("sooodreamy-vault-v1".utf8)

    // MARK: Key derivation

    static func randomSalt(count: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// PBKDF2-SHA256 → 256-bit AES key. ~0.1–0.3 s on-device at 210k
    /// iterations — call off the main thread.
    static func deriveKey(pin: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pinData = Data(pin.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = pinData.withUnsafeBytes { pinBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinBytes.bindMemory(to: Int8.self).baseAddress, pinData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived, derived.count)
            }
        }
        guard status == kCCSuccess else { throw VaultCryptoError.keyDerivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: PIN verifier

    static func makeVerifier(key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(verifierPlaintext, using: key).combined else {
            throw VaultCryptoError.keyDerivationFailed
        }
        return combined
    }

    static func checkVerifier(_ verifier: Data, key: SymmetricKey) -> Bool {
        guard let box = try? AES.GCM.SealedBox(combined: verifier),
              let opened = try? AES.GCM.open(box, using: key) else { return false }
        return opened == verifierPlaintext
    }

    // MARK: Item packaging

    /// Seals meta + content into one opaque blob:
    /// AES-GCM over `[u32-be metaLen][meta JSON][content]`.
    static func sealPackage(meta: VaultMeta, content: Data, key: SymmetricKey) throws -> Data {
        let metaData = try JSONEncoder().encode(meta)
        var plain = Data(capacity: 4 + metaData.count + content.count)
        var lenBE = UInt32(metaData.count).bigEndian
        withUnsafeBytes(of: &lenBE) { plain.append(contentsOf: $0) }
        plain.append(metaData)
        plain.append(content)
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw VaultCryptoError.malformedBlob
        }
        return combined
    }

    static func openPackage(_ blob: Data, key: SymmetricKey) throws -> (meta: VaultMeta, content: Data) {
        guard let box = try? AES.GCM.SealedBox(combined: blob) else {
            throw VaultCryptoError.malformedBlob
        }
        guard let plain = try? AES.GCM.open(box, using: key) else {
            throw VaultCryptoError.wrongKey
        }
        guard plain.count >= 4 else { throw VaultCryptoError.malformedBlob }
        let metaLen = plain.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard plain.count >= 4 + metaLen else { throw VaultCryptoError.malformedBlob }
        let metaData = plain.subdata(in: 4..<(4 + metaLen))
        let content = plain.subdata(in: (4 + metaLen)..<plain.count)
        let meta = try JSONDecoder().decode(VaultMeta.self, from: metaData)
        return (meta, content)
    }
}

// MARK: - Keychain (biometric convenience unlock)

/// Stores the derived vault key locally, gated behind Face ID / Touch ID /
/// passcode (`.userPresence`). ThisDeviceOnly → never syncs to iCloud.
enum VaultKeychain {
    private static let service = "app.sooodreamy.vault"
    private static let account = "vault-key"

    static func store(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        clear()
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: access,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Prompts Face ID / passcode; nil when nothing stored or the user
    /// cancelled. Blocking — call from a background task.
    static func load(reason: String) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: reason,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    /// True when a key is stored (checked WITHOUT triggering biometrics).
    static var hasStoredKey: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
