import XCTest
@testable import SoooDreamyLogic

/// Re-Eval Runde 2, Fund 3: the server's rev-guard 409s carry
/// `current`/`generation` at the TOP LEVEL of the body while
/// `game_lease_held` wraps its payload in `details` — the decoding must
/// accept BOTH forms, otherwise the direct conflict adoption never runs.
final class APIErrorWireTests: XCTestCase {

    private func decode(_ json: String) throws -> APIErrorBody {
        try JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8))
    }

    // MARK: Top-level form (the live server's conflict/stale_generation)

    func testTopLevelCurrentOfConflictLandsInDetails() throws {
        let body = try decode("""
        {"error": "conflict",
         "message": "The resource is at rev 3 — merge with \\"current\\" and retry",
         "current": {"id": "ev_1", "title": "Jahrestag", "rev": 3}}
        """)
        XCTAssertEqual(body.error, "conflict")
        let current = try XCTUnwrap(body.details?.current)
        XCTAssertEqual(current["id"]?.stringValue, "ev_1")
        XCTAssertEqual(current["rev"]?.intValue, 3)
        XCTAssertNil(body.details?.generation)
    }

    func testTopLevelGenerationOfStaleGenerationLandsInDetails() throws {
        let body = try decode("""
        {"error": "stale_generation",
         "message": "The board was cleared while this stroke was in flight",
         "generation": 4}
        """)
        XCTAssertEqual(body.error, "stale_generation")
        XCTAssertEqual(body.details?.generation, 4)
        XCTAssertNil(body.details?.current)
    }

    // MARK: Conflict adoption — `current` re-decodes into the resource

    private struct MiniList: Codable, Equatable {
        let id: String
        let title: String
        let rev: Int
    }

    func testConflictAdoptionRedecodesTopLevelCurrentIntoTheResource() throws {
        let body = try decode("""
        {"error": "conflict", "message": "merge and retry",
         "current": {"id": "l_7", "title": "Einkauf", "rev": 9}}
        """)
        let raw = try XCTUnwrap(body.details?.current)
        let data = try JSONEncoder().encode(raw)
        let adopted = try JSONDecoder().decode(MiniList.self, from: data)
        XCTAssertEqual(adopted, MiniList(id: "l_7", title: "Einkauf", rev: 9))
    }

    // MARK: Details-wrapped form (contract v11 unchanged)

    func testDetailsWrappedLeaseStillDecodes() throws {
        let body = try decode("""
        {"error": "game_lease_held", "message": "Another device is playing",
         "details": {"gameId": "g_1",
                     "lease": {"deviceId": "d_1", "deviceName": "Bens iPad",
                               "sessionSuffix": "abcd1234", "acquiredAt": "2026-08-15T00:00:00Z"}}}
        """)
        XCTAssertEqual(body.details?.gameId, "g_1")
        XCTAssertEqual(body.details?.lease?.deviceName, "Bens iPad")
    }

    func testNestedFieldsWinOverTopLevelDuplicates() throws {
        let body = try decode("""
        {"error": "conflict", "generation": 1,
         "details": {"generation": 7, "current": {"id": "ev_9"}},
         "current": {"id": "ev_ignored"}}
        """)
        XCTAssertEqual(body.details?.generation, 7)
        XCTAssertEqual(body.details?.current?["id"]?.stringValue, "ev_9")
    }

    func testTopLevelFillsGapsNextToPartialDetails() throws {
        let body = try decode("""
        {"error": "conflict",
         "details": {"gameId": "g_2"},
         "current": {"id": "ev_5", "rev": 2}}
        """)
        XCTAssertEqual(body.details?.gameId, "g_2")
        XCTAssertEqual(body.details?.current?["id"]?.stringValue, "ev_5")
    }

    // MARK: daily_question_mismatch (Schlussrunde 5)

    func testDailyQuestionMismatchDetailsDecodeIdAndText() throws {
        let body = try decode("""
        {"error": "daily_question_mismatch",
         "message": "Today's question is already pinned — answer the pinned question",
         "details": {"questionId": 410,
                     "questionText": {"de": "Was war heute schön?",
                                      "en": "What was lovely today?"}}}
        """)
        XCTAssertEqual(body.error, "daily_question_mismatch")
        XCTAssertEqual(body.details?.questionId, 410)
        XCTAssertEqual(body.details?.questionText,
                       LText(de: "Was war heute schön?", en: "What was lovely today?"))
    }

    func testDailyQuestionMismatchWithNullTextStillCarriesTheId() throws {
        // Pins written by old clients store no text — the id alone must
        // survive so the adoption can at least refetch the entry.
        let body = try decode("""
        {"error": "daily_question_mismatch",
         "details": {"questionId": 410, "questionText": null}}
        """)
        XCTAssertEqual(body.details?.questionId, 410)
        XCTAssertNil(body.details?.questionText)
    }

    func testTopLevelQuestionFieldsFillInLikeCurrentAndGeneration() throws {
        // Same dual-shape tolerance as conflict/stale_generation: should a
        // server ever emit the fields NEXT to `error`, they still land.
        let body = try decode("""
        {"error": "daily_question_mismatch", "questionId": 42,
         "questionText": {"de": "Frage", "en": "Question"}}
        """)
        XCTAssertEqual(body.details?.questionId, 42)
        XCTAssertEqual(body.details?.questionText?.en, "Question")
    }

    // MARK: Robustness

    func testPlainErrorBodyKeepsNilDetails() throws {
        let body = try decode(#"{"error": "not_found", "message": "No such thing"}"#)
        XCTAssertEqual(body.error, "not_found")
        XCTAssertNil(body.details)
    }

    func testMalformedDetailsNeverCostErrorAndMessage() throws {
        let body = try decode("""
        {"error": "conflict", "message": "still readable",
         "details": "not-an-object", "generation": 2}
        """)
        XCTAssertEqual(body.error, "conflict")
        XCTAssertEqual(body.message, "still readable")
        // The malformed details object is dropped; the top-level field
        // still fills in.
        XCTAssertEqual(body.details?.generation, 2)
    }

    func testMalformedTopLevelFieldsAreDroppedQuietly() throws {
        let body = try decode(#"{"error": "conflict", "generation": "vier"}"#)
        XCTAssertEqual(body.error, "conflict")
        XCTAssertNil(body.details?.generation)
    }
}
