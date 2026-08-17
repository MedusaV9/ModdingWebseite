import Foundation

// MARK: - Spieltisch statistics (GET /api/games/stats)

// The register numbers of the hub (Spielbuch rows + Fach page numbers)
// come from THIS whole-history aggregate — the paged 50-item
// `GET /api/games` list stopped being an honest census at game 51 and
// now only curates the hero, "recently played" and the replay entries.
// Feature-area API extension per the sanctioned pattern (RitualsAPI):
// `API.request` is internal exactly so stations can add their endpoints
// without touching Core/API.swift.

/// Wire shape of `GET /api/games/stats`: counts over PLAYED games only.
/// `perKind` keys are raw server game types; `decided`/`draws` split the
/// score-carrying results, `replayable` counts ended games with moves
/// (the ReplayView entry filter). `lowerBound` (Fix-Runde 3, Befund 6) is
/// true when the aggregate was seeded from an already-capped list — the
/// evicted history is unprovable, so total/perKind are honest FLOORS and
/// the register renders "{n}+"; nil on pre-lowerBound servers.
struct GamesStatsResponse: Codable, Equatable {
    let total: Int
    let perKind: [String: Int]
    let lowerBound: Bool?
    let decided: Int
    let draws: Int
    let replayable: Int

    /// The honest-floor verdict, defaulting old servers to "exact".
    var istUntergrenze: Bool { lowerBound == true }
}

extension API {
    /// Whole-history game statistics. Pre-stats servers 404 — callers keep
    /// their list-derived numbers as the progressive-enhancement fallback.
    func gamesStats() async throws -> GamesStatsResponse {
        try await request("GET", "/api/games/stats", as: GamesStatsResponse.self)
    }
}
