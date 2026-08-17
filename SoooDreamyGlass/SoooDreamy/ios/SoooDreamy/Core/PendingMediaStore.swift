import Foundation

/// One prepared-but-not-yet-accepted media upload (Linse 41/45): the JPEG
/// bytes live as a file next to the JSON index, so a failed upload or a
/// dismissed caption sheet costs patience — never the photo or its caption.
struct PendingMediaEntry: Codable, Hashable, Identifiable {
    let id: String
    let scope: OutboxScope
    var caption: String
    var album: String
    let width: Int
    let height: Int
    /// EXIF capture time of the original bytes (nil when the photo had
    /// none) — survives the stash so retries keep the real date. Optional,
    /// so pre-takenAt index files still decode.
    var takenAt: Date?
    let createdAt: Date
    /// Server error code of the last failed attempt (nil before the first
    /// try, or when it was stashed by a sheet dismiss).
    var lastErrorCode: String?
}

/// Disk-backed holding area for pending photo uploads. JPEG payloads are
/// individual files (`<id>.jpg`), metadata is one JSON index — both under
/// Application Support, both surviving process kills. Bounded so a broken
/// server can't grow the folder forever.
final class PendingMediaStore: @unchecked Sendable {
    static let shared = PendingMediaStore()
    static let maximumEntries = 20

    private let directory: URL
    private let lock = NSLock()
    private var entries: [PendingMediaEntry]

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init(directory: URL = PendingMediaStore.defaultDirectory()) {
        self.directory = directory
        if let data = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
           let decoded = try? JSONDecoder().decode([PendingMediaEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// Persists bytes + metadata atomically enough for our purpose: the JPEG
    /// file is written first, the index second — a crash in between leaves an
    /// orphaned file, never an entry without bytes.
    @discardableResult
    func add(jpeg: Data, caption: String, album: String, width: Int, height: Int,
             takenAt: Date? = nil, scope: OutboxScope, id: String = UUID().uuidString,
             createdAt: Date = Date()) -> PendingMediaEntry? {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try jpeg.write(to: jpegURL(id: id), options: .atomic)
        } catch {
            return nil
        }
        let entry = PendingMediaEntry(id: id, scope: scope, caption: caption,
                                      album: album, width: width, height: height,
                                      takenAt: takenAt, createdAt: createdAt,
                                      lastErrorCode: nil)
        entries.removeAll { $0.id == id }
        entries.append(entry)
        entries.sort { $0.createdAt < $1.createdAt }
        while entries.count > Self.maximumEntries {
            let dropped = entries.removeFirst()
            try? FileManager.default.removeItem(at: jpegURL(id: dropped.id))
        }
        persistLocked()
        return entry
    }

    func entries(for scope: OutboxScope) -> [PendingMediaEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.scope == scope }.sorted { $0.createdAt < $1.createdAt }
    }

    func jpegData(id: String) -> Data? {
        try? Data(contentsOf: jpegURL(id: id))
    }

    /// Keeps caption/album edits from the retry card.
    func update(id: String, caption: String, album: String) {
        mutate(id: id) {
            $0.caption = caption
            $0.album = album
        }
    }

    func setLastError(id: String, code: String?) {
        mutate(id: id) { $0.lastErrorCode = code }
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: jpegURL(id: id))
        persistLocked()
    }

    private func mutate(id: String, _ change: (inout PendingMediaEntry) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        persistLocked()
    }

    private func jpegURL(id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SoooDreamy", isDirectory: true)
            .appendingPathComponent("pending-media", isDirectory: true)
    }
}
