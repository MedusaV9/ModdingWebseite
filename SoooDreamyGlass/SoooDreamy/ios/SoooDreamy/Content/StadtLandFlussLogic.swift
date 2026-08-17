import Foundation

// Stadt-Land-Fluss Paar-Edition 🗺️ — pure deterministic core, UI-free.
//
// Anti-spoiler via commit-reveal: both write their answers for the round's
// letter, COMMIT the hash first (`sha256(joined + salt)`), and only after
// BOTH commits are in do the clients reveal the plaintext — nobody (not even
// a network sniffer) sees the partner's answers early, and the relay
// certifies every reveal against its commit. Scoring is mutual: each partner
// rates the other's answers, classic points (10 valid / 5 duplicate /
// 20 exclusive) are derived automatically.
//
// Move protocol (relay `data` objects):
// - `{kind: "commit", round, commit}`                       — answers locked
// - `{kind: "reveal", round, reveal, salt, commitId}`       — after both commits
// - `{kind: "rate", round, verdicts: [Bool]}`               — judging the PARTNER

// MARK: - Events

enum SLFEvent {
    case commit(member: String, round: Int, at: Date)
    case reveal(member: String, round: Int, text: String, serverVerified: Bool)
    case rate(member: String, round: Int, verdicts: [Bool])
}

// MARK: - State

struct SLFRound {
    var commits: [String: Date] = [:]
    /// member → their revealed answers (aligned with the category list).
    var answers: [String: [String]] = [:]
    var revealVerified: [String: Bool] = [:]
    /// member → verdicts about the PARTNER's answers.
    var ratings: [String: [Bool]] = [:]

    var firstCommitAt: Date? { commits.values.min() }

    func phase(members: [String]) -> SLFRoundPhase {
        if members.allSatisfy({ ratings[$0] != nil }) { return .done }
        if members.allSatisfy({ answers[$0] != nil }) { return .rating }
        if members.allSatisfy({ commits[$0] != nil }) { return .revealing }
        return .collecting
    }
}

enum SLFRoundPhase {
    case collecting, revealing, rating, done
}

struct SLFState {
    var rounds: [SLFRound]
    /// First round that is not done (== rounds.count → finished).
    var currentRound: Int

    var finished: Bool { currentRound >= rounds.count }
}

// MARK: - Rules

enum StadtLandFluss {
    static let defaultRounds = 3
    /// Seconds the second player gets once the first one commits ("Stop!").
    static let stopSecs = 45
    /// Unit separator — answers never contain it, safe join for the commit.
    static let joiner = "\u{1F}"

    static func defaultCategories(lang: String) -> [String] {
        lang == "de"
            ? ["Stadt", "Land", "Fluss", "Kosename", "Essen", "Song"]
            : ["City", "Country", "River", "Pet name", "Food", "Song"]
    }

    /// Deterministic unique letters for all rounds (rare letters excluded).
    static func letters(seed: Int, rounds: Int) -> [String] {
        let pool = "ABCDEFGHIJKLMNOPRSTUVWZ".map(String.init)
        return Array(pool.seededShuffled(seed: seed).prefix(Swift.max(1, rounds)))
    }

    static func encodeAnswers(_ answers: [String]) -> String {
        answers.map { $0.replacingOccurrences(of: joiner, with: " ") }
            .joined(separator: joiner)
    }

    static func decodeAnswers(_ text: String, categoryCount: Int) -> [String] {
        var parts = text.components(separatedBy: joiner)
        while parts.count < categoryCount { parts.append("") }
        return Array(parts.prefix(categoryCount))
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Auto-check: non-empty and starts with the round's letter.
    static func startsCorrectly(_ answer: String, letter: String) -> Bool {
        guard let first = normalize(answer).first else { return false }
        return String(first) == letter.lowercased()
    }

    /// Reduces ordered events. Anti-spoiler is ENFORCED here: reveals
    /// before both commits and ratings before both reveals are skipped, as
    /// are duplicate/out-of-order events.
    static func reduce(events: [SLFEvent], rounds: Int, categoryCount: Int,
                       starter: String, partner: String) -> SLFState {
        let members = [starter, partner]
        var state = SLFState(rounds: [SLFRound](repeating: SLFRound(), count: Swift.max(1, rounds)),
                             currentRound: 0)
        for event in events {
            switch event {
            case .commit(let member, let round, let at):
                guard state.rounds.indices.contains(round),
                      members.contains(member),
                      round == activeRound(state, members: members),
                      state.rounds[round].commits[member] == nil
                else { continue }
                state.rounds[round].commits[member] = at

            case .reveal(let member, let round, let text, let verified):
                guard state.rounds.indices.contains(round),
                      members.contains(member),
                      state.rounds[round].phase(members: members) == .revealing
                        || state.rounds[round].phase(members: members) == .rating,
                      state.rounds[round].answers[member] == nil
                else { continue }
                state.rounds[round].answers[member] = decodeAnswers(text, categoryCount: categoryCount)
                state.rounds[round].revealVerified[member] = verified

            case .rate(let member, let round, let verdicts):
                guard state.rounds.indices.contains(round),
                      members.contains(member),
                      state.rounds[round].phase(members: members) == .rating
                        || state.rounds[round].phase(members: members) == .done,
                      state.rounds[round].ratings[member] == nil,
                      state.rounds[round].answers.count == members.count
                else { continue }
                var clean = verdicts
                while clean.count < categoryCount { clean.append(false) }
                state.rounds[round].ratings[member] = Array(clean.prefix(categoryCount))
            }
        }
        state.currentRound = activeRound(state, members: members)
        return state
    }

    private static func activeRound(_ state: SLFState, members: [String]) -> Int {
        for (index, round) in state.rounds.enumerated()
        where round.phase(members: members) != .done {
            return index
        }
        return state.rounds.count
    }

    // MARK: Scoring

    /// Classic points for `member` in one category of a DONE round:
    /// 0 invalid · 5 both same · 20 exclusive valid · 10 valid.
    static func points(round: SLFRound, category: Int, letter: String,
                       member: String, partner: String) -> Int {
        guard let mine = round.answers[member]?[safe: category] else { return 0 }
        let myValid = isValid(round: round, category: category, letter: letter,
                              member: member, judge: partner)
        guard myValid else { return 0 }
        let partnerValid = isValid(round: round, category: category, letter: letter,
                                   member: partner, judge: member)
        guard let theirs = round.answers[partner]?[safe: category], partnerValid else {
            return 20
        }
        return normalize(mine) == normalize(theirs) ? 5 : 10
    }

    /// Valid = auto letter check AND the partner's verdict (the judge).
    private static func isValid(round: SLFRound, category: Int, letter: String,
                                member: String, judge: String) -> Bool {
        guard let answer = round.answers[member]?[safe: category],
              startsCorrectly(answer, letter: letter),
              let verdicts = round.ratings[judge],
              verdicts.indices.contains(category)
        else { return false }
        return verdicts[category]
    }

    /// Total across all DONE rounds.
    static func total(state: SLFState, letters: [String], categoryCount: Int,
                      member: String, partner: String) -> Int {
        var sum = 0
        for (index, round) in state.rounds.enumerated()
        where round.phase(members: [member, partner]) == .done && letters.indices.contains(index) {
            for category in 0..<categoryCount {
                sum += points(round: round, category: category, letter: letters[index],
                              member: member, partner: partner)
            }
        }
        return sum
    }
}

extension Array {
    /// nil instead of a crash for out-of-range reads (reducer hygiene).
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
