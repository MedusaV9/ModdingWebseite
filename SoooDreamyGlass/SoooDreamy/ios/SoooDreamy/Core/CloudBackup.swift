import CloudKit
import CryptoKit
import Foundation
import Security
import UIKit

// iCloud backup.
//
// Design: the couple SERVER is the source of truth for all shared data —
// what a fresh install really needs back is the CONNECTION metadata (never
// Keychain tokens) and personal app settings. The portable file additionally
// contains a light couple-data snapshot and is always passphrase-encrypted.
// Media (photos/videos/voice) stays on the couple server by design.
//
// Sideload reality (honest): CloudKit and the iCloud Drive container need
// iCloud entitlements that survive signing. App-Store/paid-dev signing keeps
// them; most sideload signers (free Apple ID, AltStore & Co.) strip or
// remap them — then `ubiquityIdentityToken` is nil and CloudKit calls fail
// with `.missingEntitlement`/`.notAuthenticated`. The UI detects this at
// runtime and degrades to the always-working file export (share sheet).

// MARK: - Payload

/// Everything a backup contains. Codable → one JSON blob for both CloudKit
/// and the file export.
struct AppBackupPayload: Codable {
    var version: Int
    /// Added in 4.6. Older payloads decode nil and migrate to the v1 contract.
    var manifest: BackupManifest?
    var createdAt: Date
    var deviceName: String
    var appVersion: String

    /// Saved server metadata. v4's `ServerProfile.encode` never exports the
    /// Keychain token; restored profiles require pairing on the new device.
    var servers: [ServerProfile]
    var activeServerId: UUID?

    // Personal settings
    var language: String?
    var soundsEnabled: Bool
    var hapticsEnabled: Bool
    /// Widget-studio + Live-Activity configs as raw JSON (schema-stable
    /// because both types are Codable with defaults for missing keys).
    var widgetStudioJSON: Data?
    var liveActivityJSON: Data?

    /// Optional light couple data for the encrypted export (not restored —
    /// the server owns it).
    var lightData: LightData?

    struct LightData: Codable {
        var coupleName: String?
        var anniversary: String?
        var events: [EventItem]
        var bucket: [BucketItem]
        var songs: [Song]
        var coupons: [Coupon]
    }
}

// MARK: - Build & restore

@MainActor
enum BackupService {
    static let payloadVersion = 2

    /// Assembles the current payload. `includeLightData` additionally pulls
    /// moments/bucket/songs/coupons from the server (for the file export).
    static func makePayload(
        appState: AppState,
        includeLightData: Bool,
        includeServerProfiles: Bool = true,
        includeDeviceSettings: Bool = true,
        includeAppGroupSettings: Bool = true
    ) async -> AppBackupPayload {
        var domains: Set<BackupDomain> = []
        if includeServerProfiles { domains.insert(.serverProfiles) }
        if includeDeviceSettings { domains.insert(.deviceSettings) }
        if includeAppGroupSettings { domains.insert(.appGroupSettings) }
        if includeLightData { domains.insert(.coupleSnapshot) }
        var payload = AppBackupPayload(
            version: payloadVersion,
            manifest: BackupManifest(domains: domains),
            createdAt: Date(),
            deviceName: UIDevice.current.name,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            servers: includeServerProfiles ? appState.servers.profiles : [],
            activeServerId: includeServerProfiles ? appState.servers.activeProfileID : nil,
            language: includeDeviceSettings
                ? UserDefaults.standard.string(forKey: "sooodreamy.appLanguage")
                : nil,
            soundsEnabled: SoundEngine.enabled,
            hapticsEnabled: Haptics.enabled,
            widgetStudioJSON: includeAppGroupSettings
                ? try? JSONEncoder().encode(SharedStore.readStudioConfig())
                : nil,
            liveActivityJSON: includeAppGroupSettings
                ? try? JSONEncoder().encode(SharedStore.readLiveActivityConfig())
                : nil,
            lightData: nil)

        if includeLightData, let api = appState.api {
            payload.lightData = AppBackupPayload.LightData(
                coupleName: appState.couple?.name,
                anniversary: appState.couple?.anniversary,
                events: (try? await api.events()) ?? [],
                bucket: (try? await api.bucket()) ?? [],
                songs: (try? await api.songs()) ?? [],
                coupons: (try? await api.coupons()) ?? [])
        }
        return payload
    }

    /// Restores servers + settings from a payload. Returns the number of
    /// server profiles restored. Shared couple data is NOT touched — it
    /// lives on the server and reloads after reconnect.
    @discardableResult
    static func restore(
        _ payload: AppBackupPayload,
        appState: AppState,
        options: BackupRestoreOptions = BackupRestoreOptions()
    ) -> Int {
        let manifest = payload.manifest
            ?? BackupManifest.migratedLegacy(hasCoupleSnapshot: payload.lightData != nil)
        guard (try? manifest.validate()) != nil else { return 0 }
        let selected = options.selectedDomains(available: manifest.domains)

        if selected.contains(.serverProfiles) {
            appState.servers.replaceAll(profiles: payload.servers, activeId: payload.activeServerId)
        }
        if selected.contains(.deviceSettings) {
            if let raw = payload.language, let lang = AppLanguage(rawValue: raw) {
                L10n.language = lang
            }
            SoundEngine.enabled = payload.soundsEnabled
            Haptics.enabled = payload.hapticsEnabled
        }
        if selected.contains(.appGroupSettings) {
            if let data = payload.widgetStudioJSON,
               let config = try? JSONDecoder().decode(WidgetStudioConfig.self, from: data) {
                SharedStore.writeStudioConfig(config)
            }
            if let data = payload.liveActivityJSON,
               let config = try? JSONDecoder().decode(LiveActivityConfig.self, from: data) {
                SharedStore.writeLiveActivityConfig(config)
            }
        }
        return selected.contains(.serverProfiles) ? payload.servers.count : 0
    }

    // Pure JSON plumbing — safe from any isolation context.
    nonisolated static func encodeJSON(_ payload: AppBackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    nonisolated static func decodeJSON(_ data: Data) throws -> AppBackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppBackupPayload.self, from: data)
    }

    private struct EncryptedExport: Codable {
        let format: String
        let kdf: String
        let iterations: Int
        let salt: Data
        let ciphertext: Data
    }

    enum ExportError: Error {
        case weakPassphrase
        case invalidEnvelope
    }

    /// Password-protected portable export. The password is never persisted;
    /// losing it makes the export unrecoverable by design.
    nonisolated static func encodeEncrypted(_ payload: AppBackupPayload,
                                            passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw ExportError.weakPassphrase }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw ExportError.invalidEnvelope }
        let iterations = 210_000
        let key = deriveExportKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(encodeJSON(payload), using: key)
        guard let combined = sealed.combined else { throw ExportError.invalidEnvelope }
        return try JSONEncoder().encode(
            EncryptedExport(format: "sooodreamy-export-v4", kdf: "pbkdf2-hmac-sha256",
                            iterations: iterations,
                            salt: salt, ciphertext: combined))
    }

    nonisolated static func decodeEncrypted(_ data: Data,
                                            passphrase: String) throws -> AppBackupPayload {
        guard passphrase.count >= 12 else { throw ExportError.weakPassphrase }
        let envelope = try JSONDecoder().decode(EncryptedExport.self, from: data)
        guard envelope.format == "sooodreamy-export-v4",
              envelope.kdf == "pbkdf2-hmac-sha256",
              envelope.salt.count == 16,
              (100_000...500_000).contains(envelope.iterations) else {
            throw ExportError.invalidEnvelope
        }
        let key = deriveExportKey(passphrase: passphrase, salt: envelope.salt,
                                  iterations: envelope.iterations)
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        return try decodeJSON(AES.GCM.open(box, using: key))
    }

    private nonisolated static func deriveExportKey(passphrase: String, salt: Data,
                                                     iterations: Int) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(passphrase.precomposedStringWithCanonicalMapping.utf8))
        var block = UInt32(1).bigEndian
        let blockData = Data(bytes: &block, count: MemoryLayout<UInt32>.size)
        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + blockData, using: passwordKey))
        var derived = [UInt8](u)
        for _ in 1..<iterations {
            u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
            for index in derived.indices {
                derived[index] ^= u[index]
            }
        }
        return SymmetricKey(data: Data(derived))
    }
}

// MARK: - CloudKit (private database)

/// One well-known record in the user's PRIVATE CloudKit database holds the
/// latest backup blob. Private DB = only this Apple ID can read it.
enum CloudKitBackup {
    static let containerId = "iCloud.app.sooodreamy.ios"
    static let recordType = "SoooDreamyBackup"
    static let recordName = "current-backup"
    private static let lastBackupKey = "sooodreamy.icloud.lastBackupAt"

    /// Last successful CloudKit backup from THIS device (local bookkeeping).
    static var lastBackupAt: Date? {
        get { UserDefaults.standard.object(forKey: lastBackupKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBackupKey) }
    }

    /// nil = CloudKit unusable (no entitlement after sideload signing, or
    /// the status check itself failed) — callers hide/disable the feature.
    static func accountStatus() async -> CKAccountStatus? {
        // Explicit identifier: CKContainer.default() traps when signing
        // stripped the container entitlement; the identifier variant fails
        // soft with an error instead.
        let container = CKContainer(identifier: containerId)
        return try? await container.accountStatus()
    }

    static func save(_ payload: AppBackupPayload) async throws {
        let database = CKContainer(identifier: containerId).privateCloudDatabase
        let recordID = CKRecord.ID(recordName: recordName)
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["payload"] = try BackupService.encodeJSON(payload) as NSData
        record["createdAt"] = payload.createdAt as NSDate
        record["deviceName"] = payload.deviceName as NSString
        record["appVersion"] = payload.appVersion as NSString
        _ = try await database.save(record)
        lastBackupAt = Date()
    }

    /// nil = no backup stored yet.
    static func fetch() async throws -> AppBackupPayload? {
        let database = CKContainer(identifier: containerId).privateCloudDatabase
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await database.record(for: recordID)
            guard let data = record["payload"] as? Data else { return nil }
            return try BackupService.decodeJSON(data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
}

// MARK: - iCloud Drive (document export)

enum UbiquityDrive {
    /// The app's iCloud Drive Documents folder — nil when iCloud Drive is
    /// unavailable (no account, or signing stripped the entitlement).
    /// `url(forUbiquityContainerIdentifier:)` may block, hence detached.
    static func documentsFolder() async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let container = FileManager.default.url(
                forUbiquityContainerIdentifier: CloudKitBackup.containerId) else { return nil }
            let docs = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }.value
    }

    /// Cheap signal that iCloud (Drive) is signed in AND the entitlement
    /// survived signing — nil in every sideload-degraded case.
    static var identityAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Writes the export into iCloud Drive; returns the file URL.
    static func writeExport(_ data: Data) async throws -> URL {
        guard let docs = await documentsFolder() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("SoooDreamy-Backup-\(stamp).sooodreamy")
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: url, options: .atomic)
        }.value
        return url
    }
}
