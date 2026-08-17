import XCTest
@testable import SoooDreamyLogic

/// Pins the client half of the input lease (roadmap 25): seat decisions
/// from `game.leases` + own session id, the fail-open contract, the banner
/// gate, and the wire shape of the lease view.
final class GameLeaseRulesTests: XCTestCase {

    private func lease(suffix: String?, name: String? = "Mias iPhone") -> GameLease {
        GameLease(deviceId: "mia-iphone-0001", deviceName: name,
                  sessionSuffix: suffix, acquiredAt: "2026-08-14T12:00:00.000Z")
    }

    // MARK: Seat decisions

    func testNoLeaseMeansOpenTable() {
        XCTAssertEqual(GameLeaseRules.seat(lease: nil, ownSessionId: "session_abcd1234"),
                       .open)
    }

    func testOwnSuffixTakesTheDriverSeat() {
        let seat = GameLeaseRules.seat(lease: lease(suffix: "abcd1234"),
                                       ownSessionId: "session_abcd1234")
        XCTAssertEqual(seat, .driver)
    }

    func testForeignSuffixMakesThisDeviceASpectator() {
        let seat = GameLeaseRules.seat(lease: lease(suffix: "ffff0000"),
                                       ownSessionId: "session_abcd1234")
        XCTAssertEqual(seat, .spectator(deviceName: "Mias iPhone"))
    }

    func testSuffixComparesOnlyTheLastEightCharacters() {
        // The server sends `sessionId.slice(-8)` — a long own id must
        // reduce to the same suffix before comparing.
        let seat = GameLeaseRules.seat(lease: lease(suffix: "d1234567"),
                                       ownSessionId: "session_0000d1234567")
        XCTAssertEqual(seat, .driver)
    }

    // MARK: Fail open — unknown identity must never lock the UI

    func testUnknownOwnSessionFailsOpen() {
        XCTAssertEqual(GameLeaseRules.seat(lease: lease(suffix: "ffff0000"),
                                           ownSessionId: nil), .open)
        XCTAssertEqual(GameLeaseRules.seat(lease: lease(suffix: "ffff0000"),
                                           ownSessionId: ""), .open)
    }

    func testEmptyLeaseSuffixFailsOpen() {
        XCTAssertEqual(GameLeaseRules.seat(lease: lease(suffix: ""),
                                           ownSessionId: "session_abcd1234"), .open)
        XCTAssertEqual(GameLeaseRules.seat(lease: lease(suffix: nil),
                                           ownSessionId: "session_abcd1234"), .open)
    }

    // MARK: Banner gate

    func testBannerShowsOnlyInActiveSpectatedGames() {
        let foreign = lease(suffix: "ffff0000")
        XCTAssertTrue(GameLeaseRules.showsSpectatorBanner(
            state: "active", lease: foreign, ownSessionId: "session_abcd1234"))
        // Own lease, lobby, ended, unknown state: no banner.
        XCTAssertFalse(GameLeaseRules.showsSpectatorBanner(
            state: "active", lease: lease(suffix: "abcd1234"), ownSessionId: "session_abcd1234"))
        XCTAssertFalse(GameLeaseRules.showsSpectatorBanner(
            state: "lobby", lease: foreign, ownSessionId: "session_abcd1234"))
        XCTAssertFalse(GameLeaseRules.showsSpectatorBanner(
            state: "ended", lease: foreign, ownSessionId: "session_abcd1234"))
        XCTAssertFalse(GameLeaseRules.showsSpectatorBanner(
            state: nil, lease: foreign, ownSessionId: "session_abcd1234"))
    }

    func testBannerDeviceNameFallsBackForBlankNames() {
        XCTAssertEqual(GameLeaseRules.bannerDeviceName(lease(suffix: "x", name: "Mias iPad")),
                       "Mias iPad")
        XCTAssertNil(GameLeaseRules.bannerDeviceName(lease(suffix: "x", name: "   ")))
        XCTAssertNil(GameLeaseRules.bannerDeviceName(lease(suffix: "x", name: nil)))
        XCTAssertNil(GameLeaseRules.bannerDeviceName(nil))
        // The fallback key exists in the games table (DE + EN).
        XCTAssertNotNil(GamesL10n.table[GameLeaseRules.unknownDeviceKey])
    }

    // MARK: Wire shape

    func testLeaseDecodesFromTheServerViewShape() throws {
        let json = Data("""
        {"deviceId":"mia-ipad-0001","deviceName":"Mias iPad",
         "sessionSuffix":"1a2b3c4d","acquiredAt":"2026-08-14T12:00:00.123Z"}
        """.utf8)
        let decoded = try JSONDecoder().decode(GameLease.self, from: json)
        XCTAssertEqual(decoded.deviceName, "Mias iPad")
        XCTAssertEqual(decoded.sessionSuffix, "1a2b3c4d")
        // Every field is optional — a pruned or future view must not throw.
        let sparse = try JSONDecoder().decode(GameLease.self, from: Data("{}".utf8))
        XCTAssertNil(sparse.sessionSuffix)
    }

    func testRefusalCodeMatchesTheErrorCatalog() {
        XCTAssertEqual(GameLeaseRules.refusalCode, "game_lease_held")
        // The humanizer owns a hand-written sentence for it.
        let human = APIErrorHumanizer.humanize(status: 409, code: "game_lease_held",
                                               message: nil)
        XCTAssertEqual(human.text, L10n.t("error.code.game_lease_held"))
    }
}
