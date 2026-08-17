import Foundation

// Spieltisch-Kartenschrank (NEUBAU_ENTSCHEID §4.3, NEUBAU_POSTAMT §3.3):
// die deterministische, VOLLSTÄNDIGE Zuordnung jeder GameDestination zu
// genau einem Fach. Foundation-only — der Hub liest hieraus, die
// LogicTests pinnen Vollständigkeit und Eindeutigkeit auf Linux.

/// The five shelves of the games table. Three are the actual cabinet
/// drawers (ENTSCHEID: Fernpartien · Am Tisch · Feste & Fragen); the
/// notice board and the game book live outside the cabinet but still own
/// their destinations, so the mapping covers EVERY `GameDestination`.
enum KartenschrankFach: String, CaseIterable, Sendable {
    /// Tagesaushang: the daily sheet + daily quests (zone 1).
    case aushang
    /// Correspondence rounds — turn-based envelopes (drawer 1).
    case fernpartien
    /// Live rounds — both partners at the table (drawer 2).
    case amTisch
    /// Party, questions, going-out cards & the movie program (drawer 3).
    case festeFragen
    /// The game book: tournament · scoreboard · replays · tutorials (zone 4).
    case spielbuch

    /// The three drawers of the physical cabinet, in shelf order.
    static let schrank: [KartenschrankFach] = [.fernpartien, .amTisch, .festeFragen]
}

enum KartenschrankRules {
    /// Pinned drawer contents in DISPLAY order (POSTAMT §2 mapping table):
    /// the async catalog plays by post, the live catalog sits at the
    /// table, parties/questions/going-out fill drawer 3. `emojiriddle`
    /// and `truthordare` appear under their plain names in the party
    /// list, so that is their one home (the "-live" variants of the
    /// dossier table do not exist as destinations).
    static let inhalt: [KartenschrankFach: [String]] = [
        .aushang: ["wordle", "dailyquests"],
        .fernpartien: ["wordchain", "hangman", "wordleduo", "story", "bingo",
                       "battleship", "kniffel", "stadtlandfluss", "twotruths",
                       "pictionary", "dame", "reversi", "kaesekaestchen",
                       "gomoku", "mancala", "memoryduo"],
        .amTisch: ["connectfour", "photomemory", "quizduel", "rps"],
        .festeFragen: ["quiz", "thisorthat", "wouldyourather", "truthordare",
                       "questions36", "emojiriddle", "dateideas", "movieroulette"],
        .spielbuch: ["season", "record", "replay", "tutorials"],
    ]

    /// Reverse lookup, built once — deterministic because `inhalt` is a
    /// constant and the tests pin that no id appears twice.
    private static let fachVon: [String: KartenschrankFach] = {
        var map: [String: KartenschrankFach] = [:]
        for fach in KartenschrankFach.allCases {
            for ziel in inhalt[fach] ?? [] {
                map[ziel] = fach
            }
        }
        return map
    }()

    /// The one Fach a destination id belongs to (nil only for ids outside
    /// the pinned universe — the completeness test keeps that set empty).
    static func fach(fuer ziel: String) -> KartenschrankFach? {
        fachVon[ziel]
    }

    /// Ordered contents of one Fach.
    static func ziele(im fach: KartenschrankFach) -> [String] {
        inhalt[fach] ?? []
    }

    /// The complete pinned universe of destination ids.
    static var alleZiele: Set<String> {
        Set(fachVon.keys)
    }

    /// True when the given id set is covered EXACTLY ONCE — frequency-
    /// counted across the shelves, so a doubled drawer entry fails even
    /// though the deduplicated sets would still match. The ONE shared
    /// coverage rule: the DEBUG assert in the hub and the LogicTest both
    /// call this (never two diverging checks again).
    static func decktGenauEinmal(_ ziele: Set<String>) -> Bool {
        var haeufigkeit: [String: Int] = [:]
        for fach in KartenschrankFach.allCases {
            for ziel in inhalt[fach] ?? [] {
                haeufigkeit[ziel, default: 0] += 1
            }
        }
        return haeufigkeit.values.allSatisfy { $0 == 1 }
            && Set(haeufigkeit.keys) == ziele
    }

    /// A1 page number: played rounds of one Fach, counted from the
    /// existing finished-games statistic (the same `GET /api/games` list
    /// the scoreboard reads) — an honest number, never an estimate.
    static func gespieltePartien(im fach: KartenschrankFach,
                                 verlauf gespielteTypen: [String]) -> Int {
        gespielteTypen.reduce(0) { summe, typ in
            fachVon[typ] == fach ? summe + 1 : summe
        }
    }

    /// A1 page number from the server aggregate (`GET /api/games/stats`,
    /// `perKind`): the same drawer filter as the list variant, fed with
    /// WHOLE-history counts so the register stays honest past game 51
    /// (the history list pages at 50). Unknown types count nowhere.
    static func gespieltePartien(im fach: KartenschrankFach,
                                 zaehlung: [String: Int]) -> Int {
        zaehlung.reduce(0) { summe, eintrag in
            fachVon[eintrag.key] == fach ? summe + eintrag.value : summe
        }
    }

    /// A1 register line, pure formatting: „Fernpartien ····· 34". The UI
    /// draws the flexible dotted leader itself; this literal form feeds
    /// compact contexts and the formatting test.
    static func punktzeile(titel: String, zahl: Int) -> String {
        "\(titel) ····· \(zahl)"
    }
}
