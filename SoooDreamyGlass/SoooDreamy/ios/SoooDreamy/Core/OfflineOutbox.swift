import Foundation

/// Identifies one authenticated chat context. Entries never cross server,
/// couple, or member boundaries when the user switches profiles.
struct OutboxScope: Codable, Hashable {
    let profileID: UUID
    let coupleID: String
    let memberID: String
}

/// Durable chat send. `clientMessageID` is also sent to the server,
/// where it is the idempotency key for lost-response retries. A non-nil
/// `sticker` makes this a sticker message (text stays empty) — one queue,
/// one replay mechanic for every chat message kind.
struct PendingChatText: Codable, Hashable, Identifiable {
    var id: String { clientMessageID }

    let clientMessageID: String
    let scope: OutboxScope
    let text: String
    let effect: String?
    var sticker: StickerRecipe?
    let createdAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?

    init(clientMessageID: String, scope: OutboxScope, text: String,
         effect: String?, sticker: StickerRecipe? = nil,
         createdAt: Date, attemptCount: Int, lastAttemptAt: Date?) {
        self.clientMessageID = clientMessageID
        self.scope = scope
        self.text = text
        self.effect = effect
        self.sticker = sticker
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
    }

    // Custom decoding keeps v2 JSON (no `sticker` key) loading cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientMessageID = try c.decode(String.self, forKey: .clientMessageID)
        scope = try c.decode(OutboxScope.self, forKey: .scope)
        text = try c.decode(String.self, forKey: .text)
        effect = try c.decodeIfPresent(String.self, forKey: .effect)
        sticker = try c.decodeIfPresent(StickerRecipe.self, forKey: .sticker)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        attemptCount = try c.decode(Int.self, forKey: .attemptCount)
        lastAttemptAt = try c.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    }
}

/// A pending entry the outbox gave up on (permanent server rejection or
/// attempt budget exhausted). Kept around so the human can retry or discard
/// explicitly — a failure may cost patience, never content.
struct FailedOutboxEntry: Codable, Hashable, Identifiable {
    var id: String { entry.clientMessageID }

    let entry: PendingChatText
    let failedAt: Date
    /// Server error code when the rejection carried one (e.g. "too_long").
    let reason: String?
}

enum OfflineOperationKind: String, Codable, CaseIterable {
    case reaction
    case dailyAnswer
    case questCheck
    case rating
    case touch
    case pulse
    // Post & Sendungen (FullRelease P6-B)
    case postSchedule
    case touchEcho
}

// MARK: - Retry policy

/// How one failed outbox transmission should be classified.
enum OutboxFailureKind: Equatable {
    /// No server verdict at all (offline, timeout, DNS, TLS).
    case transport
    /// The server answered with a non-2xx status.
    case http(status: Int)
    /// The server answered 2xx but the response didn't parse — with an
    /// idempotency key the write itself very likely committed.
    case decoding
}

/// Pure poison-pill classifier: decides whether a failed entry stays in the
/// FIFO (and blocks it, by design) or is moved aside so the rest of the
/// queue can flow. Covered by Linux Swift tests.
enum OutboxRetryPolicy {
    /// Attempt budget for failures the classifier cannot prove permanent
    /// (5xx, 401, 429, decoding). Transport errors never consume the budget —
    /// a week in flight mode must not cost a single message.
    static let maximumAttempts = 12

    enum Verdict: Equatable {
        /// Keep the entry queued; stop this flush pass (preserve FIFO).
        case retryLater
        /// Permanent: move the entry to the failed shelf and CONTINUE
        /// flushing the remaining queue.
        case giveUp
    }

    static func verdict(failure: OutboxFailureKind, attemptCount: Int) -> Verdict {
        switch failure {
        case .transport:
            return .retryLater
        case .http(let status):
            if (400..<500).contains(status) && status != 401 && status != 429 {
                return .giveUp
            }
            return attemptCount >= maximumAttempts ? .giveUp : .retryLater
        case .decoding:
            return attemptCount >= maximumAttempts ? .giveUp : .retryLater
        }
    }
}

/// Emotional moments expire: a replayed "thinking of you" pulse from
/// yesterday would be strange rather than sweet. Pure and testable.
enum OutboxFreshness {
    /// Touches and pulses are only replayed within this window.
    static let momentLifetime: TimeInterval = 15 * 60
    /// Echo replies are bounded harder: the server closes the window
    /// 10 minutes after the ORIGINAL touch, while this check measures from
    /// the operation's createdAt (which is at or after the original) — so a
    /// later replay would most likely, though not guaranteed, collect a
    /// 409 echo_expired. Dropping it here just skips that pointless trip.
    static let echoLifetime: TimeInterval = 10 * 60

    static func isExpired(kind: OfflineOperationKind, createdAt: Date,
                          now: Date = Date()) -> Bool {
        switch kind {
        case .touch, .pulse:
            return now.timeIntervalSince(createdAt) > momentLifetime
        case .touchEcho:
            return now.timeIntervalSince(createdAt) > echoLifetime
        case .reaction, .dailyAnswer, .questCheck, .rating, .postSchedule:
            // A scheduled post outlives any moment window on purpose: the
            // server judges its deliverAt on replay — an expired one answers
            // 400 bad_deliver_at, which the retry policy turns into giveUp.
            return false
        }
    }
}

/// Durable write for small non-chat actions. The payload contains only the
/// endpoint identifiers and values needed to replay the operation; the stable
/// idempotency key prevents a lost response from applying it twice.
struct PendingOfflineOperation: Codable, Hashable, Identifiable {
    var id: String { clientOperationID }

    let clientOperationID: String
    let scope: OutboxScope
    let kind: OfflineOperationKind
    let payload: [String: String]
    let createdAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
}

/// Pure, migration-friendly state machine covered by Linux Swift tests.
struct OfflineOutboxState: Codable, Hashable {
    static let currentVersion = 2
    static let maximumEntries = 200
    static let maximumFailedEntries = 50

    var version = currentVersion
    private(set) var pending: [PendingChatText] = []
    private(set) var operations: [PendingOfflineOperation] = []
    /// "Konnte nicht gesendet werden" shelf — permanently rejected entries
    /// wait here for an explicit human retry/discard instead of blocking
    /// the FIFO forever.
    private(set) var failed: [FailedOutboxEntry] = []

    init(version: Int = currentVersion, pending: [PendingChatText] = [],
         operations: [PendingOfflineOperation] = [],
         failed: [FailedOutboxEntry] = []) {
        self.version = version
        self.pending = pending
        self.operations = operations
        self.failed = failed
    }

    // Custom decoding: `failed` was added within version 2, so older v2
    // files (no such key) must keep loading without a version bump.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        pending = try c.decodeIfPresent([PendingChatText].self, forKey: .pending) ?? []
        operations = try c.decodeIfPresent([PendingOfflineOperation].self, forKey: .operations) ?? []
        failed = try c.decodeIfPresent([FailedOutboxEntry].self, forKey: .failed) ?? []
    }

    mutating func enqueue(_ entry: PendingChatText) {
        guard !pending.contains(where: {
            $0.clientMessageID == entry.clientMessageID && $0.scope == entry.scope
        }) else { return }
        pending.append(entry)
        pending.sort { $0.createdAt < $1.createdAt }
        if pending.count > Self.maximumEntries {
            pending.removeFirst(pending.count - Self.maximumEntries)
        }
    }

    mutating func markAttempt(clientMessageID: String, scope: OutboxScope, at: Date) {
        guard let index = pending.firstIndex(where: {
            $0.clientMessageID == clientMessageID && $0.scope == scope
        }) else { return }
        pending[index].attemptCount += 1
        pending[index].lastAttemptAt = at
    }

    mutating func remove(clientMessageID: String, scope: OutboxScope) {
        pending.removeAll { $0.clientMessageID == clientMessageID && $0.scope == scope }
    }

    mutating func removeAll(for scope: OutboxScope) {
        pending.removeAll { $0.scope == scope }
        failed.removeAll { $0.entry.scope == scope }
    }

    func entries(for scope: OutboxScope) -> [PendingChatText] {
        pending.filter { $0.scope == scope }.sorted { $0.createdAt < $1.createdAt }
    }

    mutating func enqueue(_ operation: PendingOfflineOperation) {
        guard !operations.contains(where: {
            $0.clientOperationID == operation.clientOperationID && $0.scope == operation.scope
        }) else { return }
        operations.append(operation)
        operations.sort { $0.createdAt < $1.createdAt }
        if operations.count > Self.maximumEntries {
            operations.removeFirst(operations.count - Self.maximumEntries)
        }
    }

    mutating func markOperationAttempt(id: String, scope: OutboxScope, at: Date) {
        guard let index = operations.firstIndex(where: {
            $0.clientOperationID == id && $0.scope == scope
        }) else { return }
        operations[index].attemptCount += 1
        operations[index].lastAttemptAt = at
    }

    mutating func removeOperation(id: String, scope: OutboxScope) {
        operations.removeAll { $0.clientOperationID == id && $0.scope == scope }
    }

    func operations(for scope: OutboxScope,
                    kinds: Set<OfflineOperationKind>? = nil) -> [PendingOfflineOperation] {
        operations.filter {
            $0.scope == scope && (kinds == nil || kinds?.contains($0.kind) == true)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Failed shelf transitions

    /// Poison-pill move: pending → failed. The FIFO keeps flowing afterwards.
    mutating func markFailed(clientMessageID: String, scope: OutboxScope,
                             reason: String?, at date: Date) {
        guard let index = pending.firstIndex(where: {
            $0.clientMessageID == clientMessageID && $0.scope == scope
        }) else { return }
        let entry = pending.remove(at: index)
        failed.removeAll { $0.entry.clientMessageID == entry.clientMessageID
            && $0.entry.scope == scope }
        failed.append(FailedOutboxEntry(entry: entry, failedAt: date, reason: reason))
        if failed.count > Self.maximumFailedEntries {
            failed.removeFirst(failed.count - Self.maximumFailedEntries)
        }
    }

    /// Human-requested second chance: failed → pending with a fresh attempt
    /// budget (the old counts belong to the failure that was already judged).
    mutating func retryFailed(clientMessageID: String, scope: OutboxScope) {
        guard let index = failed.firstIndex(where: {
            $0.entry.clientMessageID == clientMessageID && $0.entry.scope == scope
        }) else { return }
        var entry = failed.remove(at: index).entry
        entry.attemptCount = 0
        entry.lastAttemptAt = nil
        enqueue(entry)
    }

    mutating func discardFailed(clientMessageID: String, scope: OutboxScope) {
        failed.removeAll { $0.entry.clientMessageID == clientMessageID
            && $0.entry.scope == scope }
    }

    func failedEntries(for scope: OutboxScope) -> [FailedOutboxEntry] {
        failed.filter { $0.entry.scope == scope }.sorted { $0.failedAt < $1.failedAt }
    }
}

/// Atomic JSON persistence for the outbox. The default lives in Application
/// Support; tests inject a temporary URL. Every mutation reaches disk before
/// returning, so an app kill after enqueue cannot discard the draft.
final class OfflineOutboxStore: @unchecked Sendable {
    static let shared = OfflineOutboxStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var state: OfflineOutboxState

    init(fileURL: URL = OfflineOutboxStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(OfflineOutboxState.self, from: data),
           decoded.version == OfflineOutboxState.currentVersion {
            state = decoded
        } else if let data = try? Data(contentsOf: fileURL),
                  let legacy = try? JSONDecoder().decode(LegacyOfflineOutboxState.self, from: data),
                  legacy.version == 1 {
            state = OfflineOutboxState(version: OfflineOutboxState.currentVersion,
                                       pending: legacy.pending, operations: [])
            persistLocked()
        } else {
            state = OfflineOutboxState()
        }
    }

    @discardableResult
    func enqueue(text: String, effect: String? = nil, sticker: StickerRecipe? = nil,
                 scope: OutboxScope,
                 clientMessageID: String = UUID().uuidString,
                 createdAt: Date = Date()) -> PendingChatText {
        let entry = PendingChatText(clientMessageID: clientMessageID, scope: scope, text: text,
                                    effect: effect, sticker: sticker,
                                    createdAt: createdAt, attemptCount: 0, lastAttemptAt: nil)
        withMutation { $0.enqueue(entry) }
        return entry
    }

    func entries(for scope: OutboxScope) -> [PendingChatText] {
        lock.sdWithLock { state.entries(for: scope) }
    }

    func markAttempt(clientMessageID: String, scope: OutboxScope, at: Date = Date()) {
        withMutation {
            $0.markAttempt(clientMessageID: clientMessageID, scope: scope, at: at)
        }
    }

    func remove(clientMessageID: String, scope: OutboxScope) {
        withMutation { $0.remove(clientMessageID: clientMessageID, scope: scope) }
    }

    func removeAll(for scope: OutboxScope) {
        withMutation {
            $0.removeAll(for: scope)
            for operation in $0.operations(for: scope) {
                $0.removeOperation(id: operation.clientOperationID, scope: scope)
            }
        }
    }

    @discardableResult
    func enqueue(kind: OfflineOperationKind, payload: [String: String], scope: OutboxScope,
                 clientOperationID: String = UUID().uuidString,
                 createdAt: Date = Date()) -> PendingOfflineOperation {
        let operation = PendingOfflineOperation(
            clientOperationID: clientOperationID,
            scope: scope,
            kind: kind,
            payload: payload,
            createdAt: createdAt,
            attemptCount: 0,
            lastAttemptAt: nil
        )
        withMutation { $0.enqueue(operation) }
        return operation
    }

    func operations(for scope: OutboxScope,
                    kinds: Set<OfflineOperationKind>? = nil) -> [PendingOfflineOperation] {
        lock.sdWithLock { state.operations(for: scope, kinds: kinds) }
    }

    func markOperationAttempt(id: String, scope: OutboxScope, at: Date = Date()) {
        withMutation { $0.markOperationAttempt(id: id, scope: scope, at: at) }
    }

    func removeOperation(id: String, scope: OutboxScope) {
        withMutation { $0.removeOperation(id: id, scope: scope) }
    }

    func markFailed(clientMessageID: String, scope: OutboxScope,
                    reason: String?, at date: Date = Date()) {
        withMutation {
            $0.markFailed(clientMessageID: clientMessageID, scope: scope,
                          reason: reason, at: date)
        }
    }

    func retryFailed(clientMessageID: String, scope: OutboxScope) {
        withMutation { $0.retryFailed(clientMessageID: clientMessageID, scope: scope) }
    }

    func discardFailed(clientMessageID: String, scope: OutboxScope) {
        withMutation { $0.discardFailed(clientMessageID: clientMessageID, scope: scope) }
    }

    func failedEntries(for scope: OutboxScope) -> [FailedOutboxEntry] {
        lock.sdWithLock { state.failedEntries(for: scope) }
    }

    private func withMutation(_ mutate: (inout OfflineOutboxState) -> Void) {
        lock.sdWithLock {
            mutate(&state)
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SoooDreamy", isDirectory: true)
            .appendingPathComponent("offline-outbox-v1.json")
    }
}

private struct LegacyOfflineOutboxState: Codable {
    let version: Int
    let pending: [PendingChatText]
}

private extension NSLock {
    func sdWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
