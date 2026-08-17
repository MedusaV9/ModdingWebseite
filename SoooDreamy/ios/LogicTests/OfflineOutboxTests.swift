import Foundation
import XCTest
@testable import SoooDreamyLogic

final class OfflineOutboxTests: XCTestCase {
    private let scopeA = OutboxScope(profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     coupleID: "couple-a", memberID: "member-a")
    private let scopeB = OutboxScope(profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                     coupleID: "couple-b", memberID: "member-b")

    func testStateDeduplicatesAndScopesEntriesInFIFOOrder() {
        var state = OfflineOutboxState()
        let late = entry(id: "late", scope: scopeA, text: "second", at: 20)
        let early = entry(id: "early", scope: scopeA, text: "first", at: 10)
        state.enqueue(late)
        state.enqueue(early)
        state.enqueue(entry(id: "early", scope: scopeA, text: "forged replacement", at: 30))
        state.enqueue(entry(id: "other", scope: scopeB, text: "private to B", at: 5))

        XCTAssertEqual(state.entries(for: scopeA).map(\.clientMessageID), ["early", "late"])
        XCTAssertEqual(state.entries(for: scopeA).map(\.text), ["first", "second"])
        XCTAssertEqual(state.entries(for: scopeB).map(\.clientMessageID), ["other"])
    }

    func testAttemptAndAcknowledgementAreIdempotent() {
        var state = OfflineOutboxState()
        state.enqueue(entry(id: "msg-1", scope: scopeA, text: "hello", at: 10))
        state.enqueue(entry(id: "msg-1", scope: scopeB, text: "other profile", at: 11))
        state.markAttempt(clientMessageID: "msg-1", scope: scopeA,
                          at: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(state.entries(for: scopeA).first?.attemptCount, 1)
        XCTAssertEqual(state.entries(for: scopeA).first?.lastAttemptAt,
                       Date(timeIntervalSince1970: 30))
        XCTAssertEqual(state.entries(for: scopeB).first?.attemptCount, 0)

        state.remove(clientMessageID: "msg-1", scope: scopeA)
        state.remove(clientMessageID: "msg-1", scope: scopeA)
        XCTAssertTrue(state.entries(for: scopeA).isEmpty)
        XCTAssertEqual(state.entries(for: scopeB).map(\.text), ["other profile"])

        state.removeAll(for: scopeB)
        XCTAssertTrue(state.entries(for: scopeB).isEmpty)
    }

    func testStoreSurvivesReinitialization() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = OfflineOutboxStore(fileURL: file)
        _ = first.enqueue(text: "do not lose", scope: scopeA, clientMessageID: "persisted",
                          createdAt: Date(timeIntervalSince1970: 42))

        let restored = OfflineOutboxStore(fileURL: file)
        XCTAssertEqual(restored.entries(for: scopeA).map(\.clientMessageID), ["persisted"])
        XCTAssertEqual(restored.entries(for: scopeA).first?.text, "do not lose")
    }

    func testBoundedQueueKeepsNewestEntries() {
        var state = OfflineOutboxState()
        for index in 0..<(OfflineOutboxState.maximumEntries + 5) {
            state.enqueue(entry(id: "id-\(index)", scope: scopeA, text: "\(index)",
                                at: TimeInterval(index)))
        }
        let entries = state.entries(for: scopeA)
        XCTAssertEqual(entries.count, OfflineOutboxState.maximumEntries)
        XCTAssertEqual(entries.first?.clientMessageID, "id-5")
    }

    func testWidenedOperationsAreScopedDeduplicatedAndFIFO() {
        var state = OfflineOutboxState()
        state.enqueue(operation(id: "daily", scope: scopeA, kind: .dailyAnswer, at: 20))
        state.enqueue(operation(id: "reaction", scope: scopeA, kind: .reaction, at: 10))
        state.enqueue(operation(id: "reaction", scope: scopeA, kind: .reaction, at: 30))
        state.enqueue(operation(id: "quest", scope: scopeB, kind: .questCheck, at: 5))

        XCTAssertEqual(
            state.operations(for: scopeA).map(\.clientOperationID),
            ["reaction", "daily"]
        )
        XCTAssertEqual(
            state.operations(for: scopeA, kinds: [.dailyAnswer]).map(\.kind),
            [.dailyAnswer]
        )
        XCTAssertEqual(state.operations(for: scopeB).map(\.kind), [.questCheck])

        state.markOperationAttempt(id: "reaction", scope: scopeA,
                                   at: Date(timeIntervalSince1970: 40))
        XCTAssertEqual(state.operations(for: scopeA).first?.attemptCount, 1)
        state.removeOperation(id: "reaction", scope: scopeA)
        state.removeOperation(id: "reaction", scope: scopeA)
        XCTAssertEqual(state.operations(for: scopeA).map(\.clientOperationID), ["daily"])
    }

    func testWidenedOperationsSurviveReinitialization() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-operations-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = OfflineOutboxStore(fileURL: file)
        _ = first.enqueue(
            kind: .rating,
            payload: ["gameId": "game-1", "data": #"{"kind":"rate"}"#],
            scope: scopeA,
            clientOperationID: "rating-1",
            createdAt: Date(timeIntervalSince1970: 50)
        )

        let restored = OfflineOutboxStore(fileURL: file)
        XCTAssertEqual(restored.operations(for: scopeA).map(\.clientOperationID), ["rating-1"])
        XCTAssertEqual(restored.operations(for: scopeA).first?.payload["gameId"], "game-1")
    }

    // MARK: Poison pill / failed shelf

    func testRetryPolicyClassifiesPermanentAndTransientFailures() {
        // Permanent 4xx → give up immediately, regardless of attempts.
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 400), attemptCount: 0), .giveUp)
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 404), attemptCount: 1), .giveUp)
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 422), attemptCount: 0), .giveUp)

        // Auth and rate-limit are NOT poison: session refresh / waiting fixes them.
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 401), attemptCount: 3), .retryLater)
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 429), attemptCount: 3), .retryLater)

        // Server-side trouble retries until the budget is spent.
        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .http(status: 500), attemptCount: 3), .retryLater)
        XCTAssertEqual(OutboxRetryPolicy.verdict(
            failure: .http(status: 503),
            attemptCount: OutboxRetryPolicy.maximumAttempts), .giveUp)
        XCTAssertEqual(OutboxRetryPolicy.verdict(
            failure: .http(status: 401),
            attemptCount: OutboxRetryPolicy.maximumAttempts), .giveUp)

        // Being offline never consumes the budget — flight mode is not a failure.
        XCTAssertEqual(OutboxRetryPolicy.verdict(
            failure: .transport, attemptCount: 1_000), .retryLater)

        XCTAssertEqual(OutboxRetryPolicy.verdict(failure: .decoding, attemptCount: 1), .retryLater)
        XCTAssertEqual(OutboxRetryPolicy.verdict(
            failure: .decoding,
            attemptCount: OutboxRetryPolicy.maximumAttempts), .giveUp)
    }

    func testMarkFailedMovesEntryAsideAndKeepsQueueFlowing() {
        var state = OfflineOutboxState()
        state.enqueue(entry(id: "poison", scope: scopeA, text: "rejected", at: 10))
        state.enqueue(entry(id: "healthy", scope: scopeA, text: "fine", at: 20))

        state.markFailed(clientMessageID: "poison", scope: scopeA,
                         reason: "too_long", at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(state.entries(for: scopeA).map(\.clientMessageID), ["healthy"])
        XCTAssertEqual(state.failedEntries(for: scopeA).map(\.id), ["poison"])
        XCTAssertEqual(state.failedEntries(for: scopeA).first?.reason, "too_long")
        XCTAssertTrue(state.failedEntries(for: scopeB).isEmpty)

        // Unknown IDs are a no-op, and marking twice cannot duplicate.
        state.markFailed(clientMessageID: "ghost", scope: scopeA, reason: nil,
                         at: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(state.failedEntries(for: scopeA).count, 1)
    }

    func testRetryFailedRequeuesWithFreshAttemptBudget() {
        var state = OfflineOutboxState()
        var poisoned = entry(id: "again", scope: scopeA, text: "second chance", at: 10)
        poisoned.attemptCount = 7
        poisoned.lastAttemptAt = Date(timeIntervalSince1970: 90)
        state.enqueue(poisoned)
        state.markFailed(clientMessageID: "again", scope: scopeA,
                         reason: nil, at: Date(timeIntervalSince1970: 100))

        state.retryFailed(clientMessageID: "again", scope: scopeA)

        XCTAssertTrue(state.failedEntries(for: scopeA).isEmpty)
        let requeued = state.entries(for: scopeA).first
        XCTAssertEqual(requeued?.clientMessageID, "again")
        XCTAssertEqual(requeued?.attemptCount, 0)
        XCTAssertNil(requeued?.lastAttemptAt)
        XCTAssertEqual(requeued?.text, "second chance")
    }

    func testDiscardFailedAndScopeCleanupRemoveShelfEntries() {
        var state = OfflineOutboxState()
        state.enqueue(entry(id: "a", scope: scopeA, text: "a", at: 10))
        state.enqueue(entry(id: "b", scope: scopeA, text: "b", at: 20))
        state.markFailed(clientMessageID: "a", scope: scopeA, reason: nil,
                         at: Date(timeIntervalSince1970: 30))
        state.markFailed(clientMessageID: "b", scope: scopeA, reason: nil,
                         at: Date(timeIntervalSince1970: 31))

        state.discardFailed(clientMessageID: "a", scope: scopeA)
        XCTAssertEqual(state.failedEntries(for: scopeA).map(\.id), ["b"])

        state.removeAll(for: scopeA)
        XCTAssertTrue(state.failedEntries(for: scopeA).isEmpty)
    }

    func testFailedShelfIsBounded() {
        var state = OfflineOutboxState()
        let total = OfflineOutboxState.maximumFailedEntries + 5
        for index in 0..<total {
            state.enqueue(entry(id: "id-\(index)", scope: scopeA, text: "\(index)",
                                at: TimeInterval(index)))
            state.markFailed(clientMessageID: "id-\(index)", scope: scopeA, reason: nil,
                             at: Date(timeIntervalSince1970: TimeInterval(1_000 + index)))
        }
        let shelf = state.failedEntries(for: scopeA)
        XCTAssertEqual(shelf.count, OfflineOutboxState.maximumFailedEntries)
        XCTAssertEqual(shelf.first?.id, "id-5")
    }

    func testFailedShelfSurvivesReinitializationAndOldFilesStillLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-failed-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = OfflineOutboxStore(fileURL: file)
        _ = first.enqueue(text: "will fail", scope: scopeA, clientMessageID: "poison",
                          createdAt: Date(timeIntervalSince1970: 42))
        first.markFailed(clientMessageID: "poison", scope: scopeA, reason: "invalid_effect",
                         at: Date(timeIntervalSince1970: 43))

        let restored = OfflineOutboxStore(fileURL: file)
        XCTAssertEqual(restored.failedEntries(for: scopeA).map(\.id), ["poison"])
        XCTAssertEqual(restored.failedEntries(for: scopeA).first?.reason, "invalid_effect")

        // A v2 file written before the failed-shelf/sticker fields existed
        // must decode without loss.
        let legacyJSON = """
        {"version":2,
         "pending":[{"clientMessageID":"old","scope":{"profileID":"00000000-0000-0000-0000-000000000001","coupleID":"couple-a","memberID":"member-a"},"text":"vintage","createdAt":0,"attemptCount":2}],
         "operations":[]}
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try legacyJSON.data(using: .utf8)!.write(to: file)
        let migrated = OfflineOutboxStore(fileURL: file)
        XCTAssertEqual(migrated.entries(for: scopeA).map(\.clientMessageID), ["old"])
        XCTAssertNil(migrated.entries(for: scopeA).first?.sticker)
        XCTAssertTrue(migrated.failedEntries(for: scopeA).isEmpty)
    }

    func testStickerEntriesPersistTheRecipe() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-sticker-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let recipe = StickerRecipe(shape: .heart, color: "#FF5C8A", seed: 7, label: "hi")
        let store = OfflineOutboxStore(fileURL: file)
        _ = store.enqueue(text: "", sticker: recipe, scope: scopeA,
                          clientMessageID: "sticker-1",
                          createdAt: Date(timeIntervalSince1970: 7))

        let restored = OfflineOutboxStore(fileURL: file)
        XCTAssertEqual(restored.entries(for: scopeA).first?.sticker, recipe)
    }

    func testMomentFreshnessExpiresTouchAndPulseOnly() {
        let created = Date(timeIntervalSince1970: 1_000)
        let justInside = created.addingTimeInterval(OutboxFreshness.momentLifetime - 1)
        let justOutside = created.addingTimeInterval(OutboxFreshness.momentLifetime + 1)

        for kind in [OfflineOperationKind.touch, .pulse] {
            XCTAssertFalse(OutboxFreshness.isExpired(kind: kind, createdAt: created, now: justInside))
            XCTAssertTrue(OutboxFreshness.isExpired(kind: kind, createdAt: created, now: justOutside))
        }
        for kind in [OfflineOperationKind.reaction, .dailyAnswer, .questCheck, .rating] {
            XCTAssertFalse(OutboxFreshness.isExpired(
                kind: kind, createdAt: created,
                now: created.addingTimeInterval(86_400 * 30)))
        }
    }

    private func entry(id: String, scope: OutboxScope, text: String,
                       at: TimeInterval) -> PendingChatText {
        PendingChatText(clientMessageID: id, scope: scope, text: text,
                        effect: nil,
                        createdAt: Date(timeIntervalSince1970: at),
                        attemptCount: 0, lastAttemptAt: nil)
    }

    private func operation(id: String, scope: OutboxScope, kind: OfflineOperationKind,
                           at: TimeInterval) -> PendingOfflineOperation {
        PendingOfflineOperation(clientOperationID: id, scope: scope, kind: kind,
                                payload: ["value": id],
                                createdAt: Date(timeIntervalSince1970: at),
                                attemptCount: 0, lastAttemptAt: nil)
    }
}
