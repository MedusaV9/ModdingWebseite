import Foundation

// „Heute Abend für euch" — pure curation rules for the Play hub. The hub
// used to be one long flat wall of tiles; these rules pick ONE hero
// recommendation from a local heuristic (time of day, last played, never
// played, season participation) and derive the "recently played" row from
// the couple's finished sessions. No server round-trip, no tracking — just
// the data the hub already loads. Foundation-only so Linux `swift test`
// pins the heuristic.

/// Per-game play history the hub derives from its ended sessions.
struct PlayHistoryEntry: Hashable {
    let lastPlayed: Date?
    let playCount: Int

    init(lastPlayed: Date?, playCount: Int) {
        self.lastPlayed = lastPlayed
        self.playCount = playCount
    }
}

/// The hero pick: which game, and the one honest reason line (L10n key)
/// explaining why it surfaced — a recommendation without a reason is noise.
struct PlayRecommendation: Equatable {
    let gameId: String
    let reasonKey: String
}

/// One decided head-to-head result the hub already loads — input for the
/// "keep the series going" momentum nudge (FXC-3, S3).
struct SeriesResult {
    let gameId: String
    let mine: Int
    let theirs: Int
    let endedAt: Date

    init(gameId: String, mine: Int, theirs: Int, endedAt: Date) {
        self.gameId = gameId
        self.mine = mine
        self.theirs = theirs
        self.endedAt = endedAt
    }
}

/// A best-of style rivalry that is still open — the hub's "Weiterspielen"
/// prompt names the game and both tallies.
struct SeriesMomentum: Equatable {
    let gameId: String
    let myWins: Int
    let theirWins: Int
}

enum PlayHubCuration {
    /// The ONE "played game" rule (re-eval 2, Spieltisch Befund 8;
    /// Fix-Runde 3, Befund 5) — mirrors the server's `isPlayedGame` in
    /// `game-rules.js` VERBATIM: a session was PLAYED when it ended with
    /// recorded moves or a real result. Administrative ends are noise —
    /// cancelled/declined lobbies, zero-move rules-migration
    /// invalidations and empty `{}` results — and must never feed the
    /// hero heuristic, "recently played", the series nudge or any
    /// register number. LogicTest-pinned so client and server can never
    /// drift apart silently.
    static func isPlayedGame(state: String, moveCount: Int, result: JSONValue?) -> Bool {
        guard state == "ended" else { return false }
        if moveCount > 0 { return true }
        guard let object = result?.objectValue else { return false }
        if object["cancelled"]?.boolValue == true { return false }
        if object["declined"]?.boolValue == true { return false }
        // A zero-move session the rules migration invalidated never saw
        // play; an empty result object carries no outcome either.
        if object["invalidated"]?.boolValue == true { return false }
        if object.isEmpty { return false }
        return true
    }

    /// Grounds the list-derived play history on the WHOLE-history
    /// aggregate (Fix-Runde 3, Befund 8a): the hub's curation page stops
    /// at 50 sessions, so a game whose rounds all fell off that page
    /// would resurface as "Noch nie gespielt" although `perKind` proves
    /// otherwise. The aggregate carries counts but no dates — `playCount`
    /// takes the larger of the two truths, `lastPlayed` stays the list's
    /// (nil = long ago, exactly the honest reading for a game only the
    /// aggregate remembers).
    static func groundedHistory(_ history: [String: PlayHistoryEntry],
                                aggregate: [String: Int]?) -> [String: PlayHistoryEntry] {
        guard let aggregate else { return history }
        var grounded = history
        for (gameId, count) in aggregate where count > 0 {
            let entry = grounded[gameId]
            grounded[gameId] = PlayHistoryEntry(
                lastPlayed: entry?.lastPlayed,
                playCount: max(entry?.playCount ?? 0, count))
        }
        return grounded
    }

    /// The „Spiele-Bilanz" register number (Fix4 Befund 4): the row's
    /// destination (GamesRecordView) shows only rounds with a VERDICT —
    /// head-to-head scores or a match rate — while `stats.total` counts
    /// every played round including scoreless ones. Binding `total` made
    /// the register read „1" over an empty „Noch keine Spiele" scoreboard;
    /// the Bilanz truth is decided matches plus draws. LogicTest-pinned.
    static func bilanzPartien(decided: Int, draws: Int) -> Int {
        decided + draws
    }

    /// Quick in-between games — favored during the day.
    static let quickGames: Set<String> = [
        "thisorthat", "wouldyourather", "quizduel", "emojiriddle",
        "wordchain", "movieroulette", "rps",
    ]

    /// Cozy conversation games — favored in the evening.
    static let eveningGames: Set<String> = [
        "questions36", "truthordare", "twotruths", "quiz", "pictionary", "story",
    ]

    /// Head-to-head matches that count toward the monthly season.
    static let seasonGames: Set<String> = [
        "connectfour", "battleship", "kniffel", "quizduel",
        "dame", "reversi", "kaesekaestchen", "gomoku", "mancala", "memoryduo",
    ]

    /// Evening starts at 18:00 — the „Heute Abend für euch" framing.
    static func isEvening(hour: Int) -> Bool { hour >= 18 || hour < 4 }

    /// Deterministic per-day jitter so ties rotate day to day instead of
    /// always crowning the alphabetically first candidate. FNV-1a over
    /// gameId + dateKey — stable across launches and devices.
    static func dayJitter(gameId: String, dateKey: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(gameId)#\(dateKey)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % 7)
    }

    /// Picks the hero. Score components (largest positive one names the
    /// reason): never played +30, favorite resting a week +22, daypart fit
    /// +14/+12, season boost +8; played in the last 3 days −25 (variety).
    static func recommendation(candidates: [String],
                               history: [String: PlayHistoryEntry],
                               hour: Int, now: Date, dateKey: String,
                               playedThisSeason: Bool) -> PlayRecommendation? {
        guard !candidates.isEmpty else { return nil }
        let day: TimeInterval = 24 * 3600
        var best: (score: Int, jitter: Int, id: String, reason: String)?
        for id in candidates {
            let entry = history[id]
            var components: [(score: Int, reason: String)] = []
            if entry == nil || entry?.playCount == 0 {
                components.append((30, "games.hub.hero.reason.discover"))
            }
            if let entry, entry.playCount >= 3,
               let last = entry.lastPlayed, now.timeIntervalSince(last) > 7 * day {
                components.append((22, "games.hub.hero.reason.favorite"))
            }
            if isEvening(hour: hour) {
                if eveningGames.contains(id) { components.append((14, "games.hub.hero.reason.evening")) }
            } else if quickGames.contains(id) {
                components.append((12, "games.hub.hero.reason.quick"))
            }
            if playedThisSeason, seasonGames.contains(id) {
                components.append((8, "games.hub.hero.reason.season"))
            }
            var score = components.reduce(0) { $0 + $1.score }
            if let last = entry?.lastPlayed, now.timeIntervalSince(last) < 3 * day {
                score -= 25
            }
            guard let reason = components.max(by: { $0.score < $1.score })?.reason else { continue }
            let jitter = dayJitter(gameId: id, dateKey: dateKey)
            if best == nil || (score, jitter) > (best!.score, best!.jitter) {
                best = (score, jitter, id, reason)
            }
        }
        guard let best, best.score > 0 else { return nil }
        return PlayRecommendation(gameId: best.id, reasonKey: best.reason)
    }

    /// The "recently played" rail: newest finished session per game, unique
    /// by game, newest first, capped.
    static func recentlyPlayed(records: [(gameId: String, endedAt: Date)],
                               limit: Int = 6) -> [String] {
        var seen: Set<String> = []
        return records.sorted { $0.endedAt > $1.endedAt }
            .compactMap { seen.insert($0.gameId).inserted ? $0.gameId : nil }
            .prefix(limit).map { $0 }
    }

    /// The "Weiterspielen" nudge: aggregates decided head-to-head results
    /// (callers pass the current season month) per game and surfaces the
    /// series that is still OPEN — at least two decided games, nobody more
    /// than one win ahead. Among several open series the most recently
    /// played one carries the momentum. Existing Records data only.
    static func runningSeries(results: [SeriesResult]) -> SeriesMomentum? {
        var byGame: [String: (mine: Int, theirs: Int, last: Date)] = [:]
        for result in results where result.mine != result.theirs {
            var entry = byGame[result.gameId] ?? (0, 0, .distantPast)
            if result.mine > result.theirs {
                entry.mine += 1
            } else {
                entry.theirs += 1
            }
            entry.last = max(entry.last, result.endedAt)
            byGame[result.gameId] = entry
        }
        let open = byGame.filter { _, entry in
            entry.mine + entry.theirs >= 2 && abs(entry.mine - entry.theirs) <= 1
        }
        guard let best = open.max(by: { a, b in
            a.value.last != b.value.last ? a.value.last < b.value.last : a.key > b.key
        }) else { return nil }
        return SeriesMomentum(gameId: best.key,
                              myWins: best.value.mine,
                              theirWins: best.value.theirs)
    }
}
