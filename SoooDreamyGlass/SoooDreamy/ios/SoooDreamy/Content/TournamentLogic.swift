import Foundation

// Turnier-Modus & Saison-Trophäen 🏆 — pure deterministic core, UI-free.
//
// Monthly seasons across ALL games: every finished competitive match pays
// points into the month's season account (3 for a win, 1 each for a tie).
// There is NO new realtime protocol — both clients aggregate the same
// server history (`GET /api/games`, year-review pattern) and derive
// identical tables and trophies on the fly. Season key = "YYYY-MM".
//
// Trophies of a closed season: gold for the winner (or a shared trophy on
// a season tie) plus CO-OP trophies the couple earns together — gentle
// competition with a "we" feeling instead of a permanent ranking.

/// One finished match, mapped from a server session by the view layer.
struct SeasonMatch: Hashable {
    let type: String
    /// "YYYY-MM" of the session (derived from its createdAt dateKey).
    let monthKey: String
    let mine: Int
    let theirs: Int
}

/// Season account of one month.
struct SeasonTable: Hashable {
    let monthKey: String
    var myPoints = 0
    var theirPoints = 0
    var myWins = 0
    var theirWins = 0
    var ties = 0
    var games = 0
    var types: Set<String> = []

    var leader: SeasonLeader {
        if myPoints > theirPoints { return .me }
        if theirPoints > myPoints { return .partner }
        return .tie
    }
}

enum SeasonLeader {
    case me, partner, tie
}

/// A trophy on the shelf — derived, never stored.
struct SeasonTrophy: Hashable, Identifiable {
    let monthKey: String
    let kind: SeasonTrophyKind

    var id: String { monthKey + "|" + kind.rawValue }
}

enum SeasonTrophyKind: String {
    case goldMe        // I won the season
    case goldPartner   // my partner won the season
    case shared        // season tie — both on the podium
    case marathon      // co-op: lots of matches together in one month
    case explorers     // co-op: many different game types tried

    /// Co-op trophies belong to BOTH partners.
    var isCoop: Bool { self == .marathon || self == .explorers }
}

enum Tournament {
    static let winPoints = 3
    static let tiePoints = 1
    static let marathonGames = 15
    static let explorerTypes = 6

    /// "YYYY-MM-DD" (or any dateKey-prefixed string) → season key "YYYY-MM".
    static func monthKey(of dateKey: String) -> String {
        String(dateKey.prefix(7))
    }

    /// Season table of one month.
    static func table(matches: [SeasonMatch], month: String) -> SeasonTable {
        var table = SeasonTable(monthKey: month)
        for match in matches where match.monthKey == month {
            table.games += 1
            table.types.insert(match.type)
            if match.mine > match.theirs {
                table.myPoints += winPoints
                table.myWins += 1
            } else if match.theirs > match.mine {
                table.theirPoints += winPoints
                table.theirWins += 1
            } else {
                table.myPoints += tiePoints
                table.theirPoints += tiePoints
                table.ties += 1
            }
        }
        return table
    }

    /// All season tables, newest month first.
    static func tables(matches: [SeasonMatch]) -> [SeasonTable] {
        let months = Set(matches.map(\.monthKey))
        return months.sorted(by: >).map { table(matches: matches, month: $0) }
    }

    /// Trophies of one CLOSED season (pass past months only — the running
    /// month has no trophies yet). Deterministic, both devices agree.
    static func trophies(for table: SeasonTable) -> [SeasonTrophy] {
        guard table.games > 0 else { return [] }
        var result: [SeasonTrophy] = []
        switch table.leader {
        case .me:
            result.append(SeasonTrophy(monthKey: table.monthKey, kind: .goldMe))
        case .partner:
            result.append(SeasonTrophy(monthKey: table.monthKey, kind: .goldPartner))
        case .tie:
            result.append(SeasonTrophy(monthKey: table.monthKey, kind: .shared))
        }
        if table.games >= marathonGames {
            result.append(SeasonTrophy(monthKey: table.monthKey, kind: .marathon))
        }
        if table.types.count >= explorerTypes {
            result.append(SeasonTrophy(monthKey: table.monthKey, kind: .explorers))
        }
        return result
    }
}
