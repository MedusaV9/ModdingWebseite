import CryptoKit
import Foundation
import Security

struct CoupleMigrationBundle: Codable, Equatable {
    struct MediaNotice: Codable, Equatable {
        let included: Bool
        let reason: String
    }

    let format: String
    let schemaVersion: Int
    let exportedAt: String
    let sourceVersion: String
    let sourceCoupleId: String
    let digest: String
    let couple: JSONValue
    let media: MediaNotice
}

struct MigrationTransferFile: Codable, Equatable {
    let bundle: CoupleMigrationBundle
    let sourceMemberId: String
}

struct MigrationExportResponse: Decodable {
    let bundle: CoupleMigrationBundle
    let me: String
}

struct MigrationImportResponse: Decodable {
    let coupleId: String
    let memberId: String
    let code: String
    let requiresPartnerRepair: Bool
    let digest: String
}

extension API {
    func exportMigration() async throws -> MigrationExportResponse {
        try await request("GET", "/api/migration/export", as: MigrationExportResponse.self)
    }

    func importMigration(_ transfer: MigrationTransferFile) async throws -> MigrationImportResponse {
        struct Body: Encodable {
            let confirm = "IMPORT"
            let sourceMemberId: String
            let bundle: CoupleMigrationBundle
        }
        let data = try API.encoder.encode(
            Body(sourceMemberId: transfer.sourceMemberId, bundle: transfer.bundle)
        )
        return try await request(
            "POST",
            "/api/migration/import",
            rawBody: data,
            contentType: "application/json",
            as: MigrationImportResponse.self
        )
    }
}

enum MigrationFileService {
    private struct Envelope: Codable {
        let format: String
        let kdf: String
        let iterations: Int
        let salt: Data
        let ciphertext: Data
    }

    enum TransferError: Error {
        case weakPassphrase
        case invalidEnvelope
    }

    static func encode(_ transfer: MigrationTransferFile, passphrase: String) throws -> Data {
        guard passphrase.count >= 12 else { throw TransferError.weakPassphrase }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw TransferError.invalidEnvelope }
        let iterations = 210_000
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let plaintext = try JSONEncoder().encode(transfer)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw TransferError.invalidEnvelope }
        return try JSONEncoder().encode(
            Envelope(
                format: "sooodreamy-migration-v1",
                kdf: "pbkdf2-hmac-sha256",
                iterations: iterations,
                salt: salt,
                ciphertext: combined
            )
        )
    }

    static func decode(_ data: Data, passphrase: String) throws -> MigrationTransferFile {
        guard passphrase.count >= 12 else { throw TransferError.weakPassphrase }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.format == "sooodreamy-migration-v1",
              envelope.kdf == "pbkdf2-hmac-sha256",
              envelope.salt.count == 16,
              (100_000...500_000).contains(envelope.iterations) else {
            throw TransferError.invalidEnvelope
        }
        let key = deriveKey(
            passphrase: passphrase,
            salt: envelope.salt,
            iterations: envelope.iterations
        )
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        return try JSONDecoder().decode(
            MigrationTransferFile.self,
            from: AES.GCM.open(box, using: key)
        )
    }

    private static func deriveKey(passphrase: String, salt: Data,
                                  iterations: Int) -> SymmetricKey {
        let password = SymmetricKey(
            data: Data(passphrase.precomposedStringWithCanonicalMapping.utf8)
        )
        var block = UInt32(1).bigEndian
        let blockData = Data(bytes: &block, count: MemoryLayout<UInt32>.size)
        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + blockData, using: password))
        var derived = [UInt8](u)
        for _ in 1..<iterations {
            u = Data(HMAC<SHA256>.authenticationCode(for: u, using: password))
            for index in derived.indices { derived[index] ^= u[index] }
        }
        return SymmetricKey(data: Data(derived))
    }
}
