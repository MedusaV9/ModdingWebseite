import Foundation

enum BackupDomain: String, Codable, CaseIterable, Hashable {
    case deviceSettings
    case appGroupSettings
    case serverProfiles
    case coupleSnapshot
}

struct BackupManifest: Codable, Equatable {
    static let currentSchema = 2

    let schema: Int
    let domains: Set<BackupDomain>

    init(schema: Int = currentSchema, domains: Set<BackupDomain>) {
        self.schema = schema
        self.domains = domains
    }

    enum ValidationError: Error, Equatable {
        case unsupportedSchema(Int)
        case empty
    }

    func validate() throws {
        guard (1...Self.currentSchema).contains(schema) else {
            throw ValidationError.unsupportedSchema(schema)
        }
        guard !domains.isEmpty else { throw ValidationError.empty }
    }

    /// Version-1 payloads predate an explicit manifest and always contained
    /// server profiles plus local/app-group settings; light data was optional.
    static func migratedLegacy(hasCoupleSnapshot: Bool) -> BackupManifest {
        var domains: Set<BackupDomain> = [.deviceSettings, .appGroupSettings, .serverProfiles]
        if hasCoupleSnapshot { domains.insert(.coupleSnapshot) }
        return BackupManifest(schema: 1, domains: domains)
    }
}

struct BackupRestoreOptions: Equatable {
    var deviceSettings = true
    var appGroupSettings = true
    var serverProfiles = true

    func selectedDomains(available: Set<BackupDomain>) -> Set<BackupDomain> {
        var selected: Set<BackupDomain> = []
        if deviceSettings, available.contains(.deviceSettings) { selected.insert(.deviceSettings) }
        if appGroupSettings, available.contains(.appGroupSettings) { selected.insert(.appGroupSettings) }
        if serverProfiles, available.contains(.serverProfiles) { selected.insert(.serverProfiles) }
        return selected
    }
}

enum RestoreTransaction {
    /// Runs a mutation against a snapshot and restores that snapshot when the
    /// mutation throws. Production restore uses non-throwing storage writes;
    /// this primitive keeps future migrations rollback-safe.
    static func apply<State>(
        state: inout State,
        mutation: (inout State) throws -> Void
    ) rethrows {
        let snapshot = state
        do {
            try mutation(&state)
        } catch {
            state = snapshot
            throw error
        }
    }
}
