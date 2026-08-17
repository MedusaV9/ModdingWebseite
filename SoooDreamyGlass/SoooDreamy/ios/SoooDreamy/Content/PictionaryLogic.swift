import Foundation

// Montagsmaler (pictionary) — pure deterministic core, UI-free.
//
// One partner draws the secret word, the other guesses against the clock;
// roles swap every round. The guess timer is derived from SERVER move
// timestamps (`round_start.createdAt + secs`), so both phones agree on the
// deadline without trusting either device clock. "now" is always injected —
// no OS clock inside the reducer.
//
// Move protocol (relay `data` objects):
// - `{kind: "round_start", round}`                    — by the round's artist
// - `{kind: "stroke", round, color, width, points}`   — artist drawing (view-layer)
// - `{kind: "clear", round}`                          — artist wipes the canvas
// - `{kind: "guess", round, text}`                    — by the guesser

// MARK: - Events

enum PictionaryEvent {
    case roundStart(member: String, round: Int, at: Date)
    case guess(member: String, round: Int, text: String, at: Date)
}

// MARK: - State

struct PictionaryGuess {
    let member: String
    let text: String
    let correct: Bool
}

struct PictionaryRound {
    var startedAt: Date?
    var solvedBy: String?
    var guesses: [PictionaryGuess] = []
}

enum PictionaryPhase: Equatable {
    /// Waiting for the artist of `round` to start it.
    case waitingStart(round: Int)
    /// Round is live: draw & guess until `deadline`.
    case drawing(round: Int, deadline: Date)
    /// Round decided (solved or expired) — show the interstitial.
    case roundOver(round: Int, solved: Bool)
    case finished
}

struct PictionaryState {
    var rounds: [PictionaryRound]
    var phase: PictionaryPhase
    /// Guesser points: 1 per round solved before the deadline.
    var scores: [String: Int]

    func score(of member: String) -> Int { scores[member] ?? 0 }

    var solvedCount: Int { rounds.filter { $0.solvedBy != nil }.count }
}

// MARK: - Rules

enum Pictionary {
    static let defaultRounds = 6
    static let defaultSecs = 90

    /// Deterministic word deck for a session. The LANGUAGE comes from the
    /// payload (creator's pick) so mixed-language couples share one list.
    static func deck(seed: Int, rounds: Int, lang: String) -> [String] {
        Array(PictionaryWords.list(lang: lang)
            .seededShuffled(seed: seed)
            .prefix(Swift.max(1, rounds)))
    }

    /// Round r: the creator draws even rounds, the partner odd ones.
    static func artist(round: Int, starter: String, partner: String) -> String {
        round.isMultiple(of: 2) ? starter : partner
    }

    /// Case-, whitespace- and separator-insensitive answer matching
    /// ("Heißluftballon" == " heissluftballon " == "Heiß-Luft-Ballon").
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Reduces ordered events into the game state. Defensive: starts from
    /// the wrong artist, guesses by the artist, out-of-order rounds and
    /// repeated starts are SKIPPED. `now` decides whether the current
    /// round's clock has run out — inject it, never read the OS clock here.
    static func reduce(events: [PictionaryEvent], deck: [String],
                       starter: String, partner: String,
                       secs: Int, now: Date) -> PictionaryState {
        var rounds = [PictionaryRound](repeating: PictionaryRound(), count: deck.count)
        var scores: [String: Int] = [:]

        for event in events {
            switch event {
            case .roundStart(let member, let round, let at):
                guard rounds.indices.contains(round),
                      rounds[round].startedAt == nil,
                      member == artist(round: round, starter: starter, partner: partner),
                      round == 0 || isOver(rounds[round - 1], secs: secs, at: at)
                else { continue }
                rounds[round].startedAt = at

            case .guess(let member, let round, let text, let at):
                guard rounds.indices.contains(round),
                      let startedAt = rounds[round].startedAt,
                      rounds[round].solvedBy == nil,
                      member != artist(round: round, starter: starter, partner: partner),
                      at <= startedAt.addingTimeInterval(TimeInterval(secs))
                else { continue }
                let correct = normalize(text) == normalize(deck[round])
                rounds[round].guesses.append(
                    PictionaryGuess(member: member, text: text, correct: correct))
                if correct {
                    rounds[round].solvedBy = member
                    scores[member, default: 0] += 1
                }
            }
        }

        return PictionaryState(rounds: rounds,
                               phase: phase(rounds: rounds, secs: secs, now: now),
                               scores: scores)
    }

    /// A round is over once solved or once its clock ran out.
    private static func isOver(_ round: PictionaryRound, secs: Int, at: Date) -> Bool {
        guard let startedAt = round.startedAt else { return false }
        return round.solvedBy != nil || at > startedAt.addingTimeInterval(TimeInterval(secs))
    }

    private static func phase(rounds: [PictionaryRound], secs: Int, now: Date) -> PictionaryPhase {
        for (index, round) in rounds.enumerated() {
            guard let startedAt = round.startedAt else {
                return .waitingStart(round: index)
            }
            let deadline = startedAt.addingTimeInterval(TimeInterval(secs))
            if round.solvedBy == nil && now <= deadline {
                return .drawing(round: index, deadline: deadline)
            }
            // Decided round: show the interstitial until the NEXT round
            // starts — unless it was the last one.
            if index == rounds.count - 1 {
                return .finished
            }
            if rounds[index + 1].startedAt == nil {
                return .roundOver(round: index, solved: round.solvedBy != nil)
            }
        }
        return .finished
    }
}
