import Foundation

// Zwei Wahrheiten, eine Lüge 🤥 — pure deterministic core, UI-free.
//
// Quick & witty: the teller writes three statements and COMMITS the lie's
// index (sha256(index + salt)) in the same move — so the lie is locked in
// before the partner guesses and provably cannot be switched afterwards.
// Three moves per round: statements+commit → guess → reveal (certified by
// the relay). Guesser right = guesser point, fooled = teller point.
//
// Move protocol (relay `data` objects):
// - `{kind: "statements", round, texts: [a,b,c], commit}`
// - `{kind: "guess", round, pick: 0|1|2}`
// - `{kind: "reveal", round, reveal: "0|1|2", salt, commitId}`

// MARK: - Events

enum TwoTruthsEvent {
    case statements(member: String, round: Int, texts: [String])
    case guess(member: String, round: Int, pick: Int)
    case reveal(member: String, round: Int, lieIndex: Int, serverVerified: Bool)
}

// MARK: - State

struct TwoTruthsRound {
    var texts: [String]?
    var guess: Int?
    var lieIndex: Int?
    var revealVerified = false

    var phase: TwoTruthsRoundPhase {
        if lieIndex != nil { return .done }
        if guess != nil { return .revealing }
        if texts != nil { return .guessing }
        return .composing
    }

    /// Guesser found the lie (only meaningful once done).
    var guessedRight: Bool? {
        guard let guess, let lieIndex else { return nil }
        return guess == lieIndex
    }
}

struct TwoTruthsState {
    var rounds: [TwoTruthsRound]
    var currentRound: Int

    var finished: Bool { currentRound >= rounds.count }
}

// MARK: - Rules

enum TwoTruths {
    static let defaultRounds = 4
    static let statementCount = 3

    /// The teller of round r (creator tells even rounds).
    static func teller(round: Int, starter: String, partner: String) -> String {
        round.isMultiple(of: 2) ? starter : partner
    }

    /// Reduces ordered events. Defensive: wrong roles, out-of-order rounds,
    /// bad indexes and repeated moves are SKIPPED. Reveals only count after
    /// a guess (the lie stays sealed until then).
    static func reduce(events: [TwoTruthsEvent], rounds: Int,
                       starter: String, partner: String) -> TwoTruthsState {
        var state = TwoTruthsState(
            rounds: [TwoTruthsRound](repeating: TwoTruthsRound(), count: Swift.max(1, rounds)),
            currentRound: 0)
        for event in events {
            switch event {
            case .statements(let member, let round, let texts):
                guard state.rounds.indices.contains(round),
                      round == active(state),
                      member == teller(round: round, starter: starter, partner: partner),
                      state.rounds[round].texts == nil,
                      texts.count == statementCount,
                      texts.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                else { continue }
                state.rounds[round].texts = texts

            case .guess(let member, let round, let pick):
                guard state.rounds.indices.contains(round),
                      state.rounds[round].phase == .guessing,
                      member != teller(round: round, starter: starter, partner: partner),
                      [starter, partner].contains(member),
                      pick >= 0, pick < statementCount
                else { continue }
                state.rounds[round].guess = pick

            case .reveal(let member, let round, let lieIndex, let verified):
                guard state.rounds.indices.contains(round),
                      state.rounds[round].phase == .revealing,
                      member == teller(round: round, starter: starter, partner: partner),
                      lieIndex >= 0, lieIndex < statementCount
                else { continue }
                state.rounds[round].lieIndex = lieIndex
                state.rounds[round].revealVerified = verified
            }
        }
        state.currentRound = active(state)
        return state
    }

    private static func active(_ state: TwoTruthsState) -> Int {
        for (index, round) in state.rounds.enumerated() where round.phase != .done {
            return index
        }
        return state.rounds.count
    }

    /// Points: each done round awards 1 — to the guesser when they caught
    /// the lie, to the teller when they fooled their partner.
    static func score(state: TwoTruthsState, member: String,
                      starter: String, partner: String) -> Int {
        var points = 0
        for (index, round) in state.rounds.enumerated() {
            guard let right = round.guessedRight else { continue }
            let roundTeller = teller(round: index, starter: starter, partner: partner)
            let winner = right
                ? (roundTeller == starter ? partner : starter)
                : roundTeller
            if winner == member { points += 1 }
        }
        return points
    }
}

enum TwoTruthsRoundPhase {
    case composing, guessing, revealing, done
}
