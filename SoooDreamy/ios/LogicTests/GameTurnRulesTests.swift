import XCTest
@testable import SoooDreamyLogic

/// Contract v11/v12 „du bist dran": the server-authoritative
/// `turnMemberId` verdict wins whenever the server spoke — including an
/// EXPLICIT "nobody" — and only a truly missing field (old server) falls
/// back to the pre-v11 derivation (lobby invitation from the partner /
/// last move came from the partner).
final class GameTurnRulesTests: XCTestCase {

    // MARK: Server-authoritative verdict

    func testServerTurnMemberIdWins() {
        // Server says it's me — even when the move tail would say otherwise
        // (e.g. a multi-move turn where I keep the turn after moving).
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .some("m1"), lastMoveMemberId: "m1", myId: "m1"))
        // Server says it's the partner — even when the last move was hers.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .some("m2"), lastMoveMemberId: "m2", myId: "m1"))
        // Lobby with a server verdict: the verdict outranks createdBy.
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "lobby", createdBy: "m1",
            turnVerdict: .some("m1"), lastMoveMemberId: nil, myId: "m1"))
    }

    func testEndedGamesNeverAwaitAnyone() {
        // Explicit null is the CONTRACT for ended games …
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "ended", createdBy: "m2",
            turnVerdict: .some(nil), lastMoveMemberId: "m2", myId: "m1"))
        // … and a buggy server that still carries a holder must not
        // resurrect a "you are up" hint on a finished board.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "ended", createdBy: "m2",
            turnVerdict: .some("m1"), lastMoveMemberId: "m2", myId: "m1"))
    }

    // MARK: Old-server fallback (field missing)

    func testLobbyFallbackAwaitsTheInvitee() {
        // Partner created the lobby → the invitation awaits ME.
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "lobby", createdBy: "m2",
            turnVerdict: .none, lastMoveMemberId: nil, myId: "m1"))
        // My own lobby awaits the partner, not me.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "lobby", createdBy: "m1",
            turnVerdict: .none, lastMoveMemberId: nil, myId: "m1"))
    }

    func testActiveFallbackDerivesFromTheMoveTail() {
        // Partner moved last → my turn.
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .none, lastMoveMemberId: "m2", myId: "m1"))
        // I moved last → partner's turn.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .none, lastMoveMemberId: "m1", myId: "m1"))
        // No move yet → nobody is nagged (pre-v11 behavior preserved).
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m2",
            turnVerdict: .none, lastMoveMemberId: nil, myId: "m1"))
    }

    func testUnknownIdentityNeverClaimsATurn() {
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m2",
            turnVerdict: .some("m1"), lastMoveMemberId: "m2", myId: nil))
    }

    // MARK: Contract v12 — three-state frame verdict

    func testExtraMoveVerdictKeepsTheTurnWithTheMover() {
        // EVAL repro: Mancala store landing — the partner moved AND stays
        // on turn. The old "last player" fallback flipped the hint to me.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .some("m2"), lastMoveMemberId: "m2", myId: "m1"))
        // My own extra move: the frame verdict keeps the hint with ME.
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .some("m1"), lastMoveMemberId: "m1", myId: "m1"))
    }

    func testExplicitNullVerdictNeverFallsBack() {
        // Decisive move: the frame says NOBODY is on turn — the fallback
        // ("partner moved last → me") must stay silenced even while the
        // session still reads "active" until game_ended lands.
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .some(nil), lastMoveMemberId: "m2", myId: "m1"))
    }

    func testMissingVerdictKeepsThePreV12Fallback() {
        // Old server: no field in the frame → the derivation still runs.
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .none, lastMoveMemberId: "m2", myId: "m1"))
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: .none, lastMoveMemberId: "m1", myId: "m1"))
    }

    func testLayeredVerdictPrefersTheLiveFrame() {
        // Frame spoke (even "nobody") → it outranks the session's field.
        XCTAssertEqual(GameTurnRules.layeredVerdict(frame: .some("m2"),
                                                    session: .some("m1")),
                       String??.some("m2"))
        XCTAssertEqual(GameTurnRules.layeredVerdict(frame: .some(nil),
                                                    session: .some("m1")),
                       String??.some(nil))
        // No frame verdict → the session's own three-state field passes
        // through untouched: holder, EXPLICIT null, and missing alike.
        XCTAssertEqual(GameTurnRules.layeredVerdict(frame: .none,
                                                    session: .some("m1")),
                       String??.some("m1"))
        XCTAssertEqual(GameTurnRules.layeredVerdict(frame: .none,
                                                    session: .some(nil)),
                       String??.some(nil))
        XCTAssertEqual(GameTurnRules.layeredVerdict(frame: .none,
                                                    session: .none),
                       String??.none)
    }

    // MARK: Wire decoding — "explicit null" vs "field missing"

    /// Mirrors the custom decoders of `GameMovePayload`/`MoveResponse`
    /// (Models.swift is app-only; the shared helper lives in GameTurnRules
    /// so Linux tests cover the three-state split).
    private struct Frame: Decodable {
        let turnMemberId: String??
        enum CodingKeys: String, CodingKey { case turnMemberId }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            turnMemberId = try GameTurnRules.decodeVerdict(from: container,
                                                           key: .turnMemberId)
        }
    }

    private func decodeFrame(_ json: String) throws -> Frame {
        try JSONDecoder().decode(Frame.self, from: Data(json.utf8))
    }

    func testDecodeVerdictSplitsPresentNullAndMissing() throws {
        XCTAssertEqual(try decodeFrame(#"{"turnMemberId":"m2"}"#).turnMemberId,
                       String??.some("m2"))
        XCTAssertEqual(try decodeFrame(#"{"turnMemberId":null}"#).turnMemberId,
                       String??.some(nil))
        XCTAssertEqual(try decodeFrame(#"{}"#).turnMemberId,
                       String??.none)
    }

    // MARK: No-turn reconnect (FXD-1 Fund 1)

    func testReconnectReconcileKeepsExplicitNoTurn() throws {
        // EVAL repro: active daily-quests session, the PARTNER made the
        // last move, the server pins `turnMemberId: null` (checklists have
        // no turn). A socket-welcome reconcile drops every held frame
        // verdict — so the freshly fetched session must carry the explicit
        // null itself (`GameSession` decodes three-state like
        // `MoveResponse`), or the last-mover fallback resurrects a phantom
        // "du bist dran".
        let sessionVerdict =
            try decodeFrame(#"{"turnMemberId":null}"#).turnMemberId
        let layered = GameTurnRules.layeredVerdict(frame: .none,
                                                   session: sessionVerdict)
        XCTAssertEqual(layered, String??.some(nil),
                       "the fetched explicit null must survive the reconcile")
        XCTAssertFalse(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: layered, lastMoveMemberId: "m2", myId: "m1"),
            "explicit no-turn must silence the last-mover fallback after reconnect")
        // Contrast: a genuinely OLD server (field missing) still falls
        // back — the guard must not overshoot into pre-v11 deployments.
        let missing = try decodeFrame(#"{}"#).turnMemberId
        XCTAssertTrue(GameTurnRules.awaitingMe(
            state: "active", createdBy: "m1",
            turnVerdict: GameTurnRules.layeredVerdict(frame: .none,
                                                      session: missing),
            lastMoveMemberId: "m2", myId: "m1"))
    }
}
