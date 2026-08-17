import Foundation

// Kniffel-Liebesedition 🎲 — pure deterministic core, UI-free.
//
// Dice are DERIVED, never rolled: the value of every roll is a pure function
// of (payload seed, turn index, roll index), so both phones — and a replay —
// compute identical pips without trusting either device's RNG. A move only
// says "player rolled, holding these dice"; the values follow from the seed.
// Fully async-capable: 26 alternating turns (13 each), up to 3 rolls per
// turn, standard Kniffel scoring incl. upper-section bonus.
//
// Move protocol (relay `data` objects):
// - `{kind: "roll", held: [diceIndex…]}`   — held is ignored on a turn's first roll
// - `{kind: "score", category: "<id>"}`    — banks the dice, ends the turn

// MARK: - Categories

enum KniffelCategory: String, CaseIterable, Codable {
    case ones, twos, threes, fours, fives, sixes
    case threeOfAKind = "three"
    case fourOfAKind = "four"
    case fullHouse = "full"
    case smallStraight = "small"
    case largeStraight = "large"
    case kniffel
    case chance

    var isUpper: Bool {
        switch self {
        case .ones, .twos, .threes, .fours, .fives, .sixes: return true
        default: return false
        }
    }

    /// Points the current dice would bank in this category.
    func score(dice: [Int]) -> Int {
        let counts = Dictionary(grouping: dice, by: { $0 }).mapValues(\.count)
        let sum = dice.reduce(0, +)
        switch self {
        case .ones: return (counts[1] ?? 0) * 1
        case .twos: return (counts[2] ?? 0) * 2
        case .threes: return (counts[3] ?? 0) * 3
        case .fours: return (counts[4] ?? 0) * 4
        case .fives: return (counts[5] ?? 0) * 5
        case .sixes: return (counts[6] ?? 0) * 6
        case .threeOfAKind: return counts.values.contains { $0 >= 3 } ? sum : 0
        case .fourOfAKind: return counts.values.contains { $0 >= 4 } ? sum : 0
        case .fullHouse:
            let sorted = counts.values.sorted()
            return sorted == [2, 3] || sorted == [5] ? 25 : 0
        case .smallStraight:
            return Self.hasRun(dice, length: 4) ? 30 : 0
        case .largeStraight:
            return Self.hasRun(dice, length: 5) ? 40 : 0
        case .kniffel:
            return counts.values.contains { $0 >= 5 } ? 50 : 0
        case .chance:
            return sum
        }
    }

    private static func hasRun(_ dice: [Int], length: Int) -> Bool {
        let unique = Set(dice)
        for start in 1...(7 - length) where (start..<start + length).allSatisfy(unique.contains) {
            return true
        }
        return false
    }
}

// MARK: - Events & state

enum KniffelEvent {
    case roll(member: String, held: [Int])
    case score(member: String, category: String)
}

struct KniffelState {
    /// member → banked points per category.
    var scorecards: [String: [KniffelCategory: Int]]
    /// 0-based global turn counter (creator plays even turns).
    var turnIndex: Int
    /// Rolls used in the current turn (0 = dice not rolled yet).
    var rollCount: Int
    /// Current dice pips (empty before the turn's first roll).
    var dice: [Int]

    func scorecard(of member: String) -> [KniffelCategory: Int] {
        scorecards[member] ?? [:]
    }

    var finished: Bool {
        turnIndex >= Kniffel.totalTurns
    }
}

// MARK: - Rules

enum Kniffel {
    static let diceCount = 5
    static let maxRolls = 3
    static let turnsPerPlayer = KniffelCategory.allCases.count   // 13
    static var totalTurns: Int { turnsPerPlayer * 2 }
    static let upperBonus = 35
    static let upperBonusThreshold = 63

    /// Creator plays even turns, partner odd ones.
    static func player(turn: Int, starter: String, partner: String) -> String {
        turn.isMultiple(of: 2) ? starter : partner
    }

    /// THE deterministic dice function: pips of roll `roll` in turn `turn`.
    /// SplitMix64 seeded from (seed, turn, roll) — same everywhere, forever.
    static func pips(seed: Int, turn: Int, roll: Int) -> [Int] {
        var generator = SeededGenerator(seed: seed &+ turn &* 1_000_003 &+ roll &* 10_007)
        return (0..<diceCount).map { _ in 1 + generator.int(upTo: 6) }
    }

    /// Reduces ordered events into the game state. Defensive: rolls/scores
    /// from the wrong player, 4th rolls, scoring an already-banked category
    /// or scoring before rolling are SKIPPED.
    static func reduce(events: [KniffelEvent], seed: Int,
                       starter: String, partner: String) -> KniffelState {
        var state = KniffelState(scorecards: [:], turnIndex: 0, rollCount: 0, dice: [])
        for event in events {
            guard !state.finished else { break }
            let current = player(turn: state.turnIndex, starter: starter, partner: partner)
            switch event {
            case .roll(let member, let held):
                guard member == current, state.rollCount < maxRolls else { continue }
                let fresh = pips(seed: seed, turn: state.turnIndex, roll: state.rollCount)
                if state.rollCount == 0 || state.dice.count != diceCount {
                    state.dice = fresh
                } else {
                    let keep = Set(held.filter { $0 >= 0 && $0 < diceCount })
                    state.dice = (0..<diceCount).map { keep.contains($0) ? state.dice[$0] : fresh[$0] }
                }
                state.rollCount += 1

            case .score(let member, let category):
                guard member == current,
                      state.rollCount > 0,
                      let cat = KniffelCategory(rawValue: category),
                      state.scorecards[member]?[cat] == nil
                else { continue }
                state.scorecards[member, default: [:]][cat] = cat.score(dice: state.dice)
                state.turnIndex += 1
                state.rollCount = 0
                state.dice = []
            }
        }
        return state
    }

    // MARK: Totals

    static func upperSum(_ card: [KniffelCategory: Int]) -> Int {
        card.filter { $0.key.isUpper }.values.reduce(0, +)
    }

    static func total(_ card: [KniffelCategory: Int]) -> Int {
        let upper = upperSum(card)
        let bonus = upper >= upperBonusThreshold ? upperBonus : 0
        let lower = card.filter { !$0.key.isUpper }.values.reduce(0, +)
        return upper + bonus + lower
    }

    /// nil = tie.
    static func winner(state: KniffelState, starter: String, partner: String) -> String? {
        let a = total(state.scorecard(of: starter))
        let b = total(state.scorecard(of: partner))
        if a == b { return nil }
        return a > b ? starter : partner
    }
}
