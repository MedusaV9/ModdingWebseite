import Foundation

struct CoreColdCacheRecord: Codable, Hashable {
    let profileID: UUID
    let coupleID: String
    var savedAt: Date
    var couple: Data
    var events: Data
    var daily: Data?
    var stats: Data?
    var level: Data?
}

/// Pure bounded state used by the file store and Linux migration tests.
struct CoreColdCacheState: Codable, Hashable {
    static let currentVersion = 1
    static let maximumProfiles = 8

    var version = currentVersion
    private(set) var records: [CoreColdCacheRecord] = []

    mutating func upsert(_ record: CoreColdCacheRecord) {
        records.removeAll { $0.profileID == record.profileID }
        records.append(record)
        records.sort { $0.savedAt > $1.savedAt }
        if records.count > Self.maximumProfiles {
            records.removeLast(records.count - Self.maximumProfiles)
        }
    }

    mutating func remove(profileID: UUID) {
        records.removeAll { $0.profileID == profileID }
    }

    func record(profileID: UUID, coupleID: String) -> CoreColdCacheRecord? {
        records.first { $0.profileID == profileID && $0.coupleID == coupleID }
    }
}

/// Atomic, non-secret cache. It contains already-renderable core API state,
/// never bearer tokens, and is scoped to both profile and couple id.
final class CoreColdCacheStore: @unchecked Sendable {
    static let shared = CoreColdCacheStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var state: CoreColdCacheState

    init(fileURL: URL = CoreColdCacheStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(CoreColdCacheState.self, from: data),
           decoded.version == CoreColdCacheState.currentVersion {
            state = decoded
        } else {
            state = CoreColdCacheState()
        }
    }

    func record(profileID: UUID, coupleID: String) -> CoreColdCacheRecord? {
        lock.coldWithLock { state.record(profileID: profileID, coupleID: coupleID) }
    }

    func save(_ record: CoreColdCacheRecord) {
        mutate { $0.upsert(record) }
    }

    func remove(profileID: UUID) {
        mutate { $0.remove(profileID: profileID) }
    }

    private func mutate(_ body: (inout CoreColdCacheState) -> Void) {
        lock.coldWithLock {
            body(&state)
            guard let data = try? JSONEncoder().encode(state) else { return }
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SoooDreamy", isDirectory: true)
            .appendingPathComponent("core-cold-cache-v1.json")
    }
}

private extension NSLock {
    func coldWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
