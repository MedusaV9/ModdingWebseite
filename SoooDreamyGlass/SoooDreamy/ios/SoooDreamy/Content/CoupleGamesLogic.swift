import Foundation

// Realtime games — pure, deterministic reducers. The server relays an
// ordered move list; BOTH clients derive identical state from
// payload + moves via these helpers. UI-free on purpose: the Linux logic
// tests pin every rule the multiplayer protocol relies on.

// MARK: - Connect Four (4 Gewinnt)

struct ConnectFourState {
    /// memberIds bottom-up per column.
    var columns: [[String]]
    var winner: String?
    /// The four winning cells (column, row bottom-up) for highlighting.
    var winningCells: [ConnectFourCell]
    var moveCount = 0

    func height(_ column: Int) -> Int { columns[column].count }

    func owner(column: Int, row: Int) -> String? {
        guard columns.indices.contains(column), columns[column].indices.contains(row) else { return nil }
        return columns[column][row]
    }

    var isDraw: Bool {
        winner == nil && columns.allSatisfy { $0.count >= ConnectFour.rows }
    }
}

struct ConnectFourCell: Hashable {
    let column: Int
    let row: Int
}

enum ConnectFour {
    static let columns = 7
    static let rows = 6

    /// Whose turn is it — the creator drops first, then strict alternation.
    static func turn(state: ConnectFourState, starter: String, partner: String) -> String {
        state.moveCount.isMultiple(of: 2) ? starter : partner
    }

    /// Reduces ordered drop moves into a board. Defensive: drops from the
    /// wrong player, into full/invalid columns, or after the win are
    /// SKIPPED (not errors) so a double-send can never fork the state.
    static func reduce(drops: [(memberId: String, column: Int)],
                       starter: String, partner: String) -> ConnectFourState {
        var state = ConnectFourState(columns: Array(repeating: [], count: columns),
                                     winner: nil, winningCells: [])
        for drop in drops {
            guard state.winner == nil else { break }
            guard drop.column >= 0, drop.column < columns else { continue }
            guard state.columns[drop.column].count < rows else { continue }
            guard drop.memberId == turn(state: state, starter: starter, partner: partner) else { continue }
            state.columns[drop.column].append(drop.memberId)
            state.moveCount += 1
            if let win = winningRun(in: state, lastColumn: drop.column,
                                    lastRow: state.columns[drop.column].count - 1) {
                state.winner = drop.memberId
                state.winningCells = win
            }
        }
        return state
    }

    /// Four-in-a-row through the last-dropped disc (only place a new win
    /// can appear). Returns the winning cells, or nil.
    private static func winningRun(in state: ConnectFourState,
                                   lastColumn: Int, lastRow: Int) -> [ConnectFourCell]? {
        guard let player = state.owner(column: lastColumn, row: lastRow) else { return nil }
        let directions = [(1, 0), (0, 1), (1, 1), (1, -1)]
        for (dx, dy) in directions {
            var run = [ConnectFourCell(column: lastColumn, row: lastRow)]
            for sign in [1, -1] {
                var c = lastColumn + dx * sign
                var r = lastRow + dy * sign
                while state.owner(column: c, row: r) == player {
                    run.append(ConnectFourCell(column: c, row: r))
                    c += dx * sign
                    r += dy * sign
                }
            }
            if run.count >= 4 { return Array(run.prefix(4)) }
        }
        return nil
    }
}

// MARK: - Photo memory

struct PhotoMemoryState {
    /// pairIndex → memberId who matched it.
    var matched: [Int: String]
    /// memberId whose turn it is.
    var turn: String
    var scores: [String: Int]

    func score(of memberId: String) -> Int { scores[memberId] ?? 0 }
}

enum PhotoMemory {
    /// Max pairs on the board (16 tiles, 4×4).
    static let maxPairs = 8

    /// Deterministic tile layout: every pair index twice, seeded shuffle —
    /// identical on both phones.
    static func tiles(pairCount: Int, seed: Int) -> [Int] {
        let pairs = Swift.max(2, Swift.min(pairCount, maxPairs))
        let deck = (0..<pairs).flatMap { [$0, $0] }
        return deck.seededShuffled(seed: seed)
    }

    /// Reduces ordered flip moves (each = one turn revealing two tiles).
    /// Match → point + SAME player again; miss → turn switches. Defensive:
    /// out-of-range/equal indexes, already-matched tiles and out-of-turn
    /// flips are skipped.
    static func reduce(flips: [(memberId: String, first: Int, second: Int)],
                       tiles: [Int], starter: String, partner: String) -> PhotoMemoryState {
        var state = PhotoMemoryState(matched: [:], turn: starter, scores: [:])
        for flip in flips {
            guard flip.memberId == state.turn else { continue }
            guard flip.first != flip.second,
                  tiles.indices.contains(flip.first),
                  tiles.indices.contains(flip.second) else { continue }
            let pairA = tiles[flip.first]
            let pairB = tiles[flip.second]
            guard state.matched[pairA] == nil, state.matched[pairB] == nil else { continue }
            if pairA == pairB {
                state.matched[pairA] = flip.memberId
                state.scores[flip.memberId, default: 0] += 1
            } else {
                state.turn = flip.memberId == starter ? partner : starter
            }
        }
        return state
    }

    static func finished(state: PhotoMemoryState, tiles: [Int]) -> Bool {
        state.matched.count >= Set(tiles).count
    }
}

// MARK: - Quiz duel (buzzer scoring)

enum QuizDuel {
    static let defaultRounds = 8

    /// Deterministic question deck for a session.
    static func deck(seed: Int, rounds: Int) -> [DuelQuestion] {
        Array(ContentPack.duelQuestions.seededShuffled(seed: seed).prefix(Swift.max(rounds, 1)))
    }

    /// Buzzer scoring from answers in SERVER ARRIVAL ORDER: per round, the
    /// fastest correct answer earns 2 points, a later correct answer 1,
    /// wrong answers 0. Only each member's FIRST answer per round counts.
    static func scores(answers: [(memberId: String, round: Int, option: Int)],
                       deck: [DuelQuestion]) -> [String: Int] {
        var scores: [String: Int] = [:]
        var answered: Set<String> = []      // "round|member"
        var correctTaken: Set<Int> = []     // rounds whose +2 is gone
        for answer in answers {
            guard deck.indices.contains(answer.round) else { continue }
            let key = "\(answer.round)|\(answer.memberId)"
            guard !answered.contains(key) else { continue }
            answered.insert(key)
            guard answer.option == deck[answer.round].correct else { continue }
            if correctTaken.contains(answer.round) {
                scores[answer.memberId, default: 0] += 1
            } else {
                correctTaken.insert(answer.round)
                scores[answer.memberId, default: 0] += 2
            }
        }
        return scores
    }

    /// Round is complete once both members answered (or locked out).
    static func bothAnswered(answers: [(memberId: String, round: Int, option: Int)],
                             round: Int, members: [String]) -> Bool {
        let inRound = Set(answers.filter { $0.round == round }.map(\.memberId))
        return members.allSatisfy { inRound.contains($0) }
    }
}

// MARK: - This or That: Couch-Modus (Welle 7 [W6-Rest])

/// Pass-and-play This-or-That on ONE phone (TruthOrDare-solo pattern):
/// no server session, no engine — one phone travels between the two.
/// Per round the first player picks SECRETLY, a hand-off screen hides the
/// pick while the phone changes hands, the second player picks, then the
/// reveal puts both choices on the table.
struct ThisOrThatCouchState: Equatable {
    enum Phase: Equatable {
        /// The round's first player is picking (nothing revealed yet).
        case firstPick
        /// First pick locked in — the phone travels; the screen keeps
        /// the secret.
        case handoff
        /// The round's second player is picking (first pick stays hidden).
        case secondPick
        /// Both picks on the table — match or different.
        case reveal
        /// All rounds played.
        case finished
    }

    let totalRounds: Int
    /// Player (0/1) who picks first in round 0. The first picker alternates
    /// every round, so waiting-not-peeking is shared fairly.
    let startingPlayer: Int

    var round = 0
    var phase: Phase = .firstPick
    var firstPick: String?
    var secondPick: String?
    var matches = 0
}

enum ThisOrThatCouch {
    static let defaultRounds = 12

    static func start(rounds: Int = defaultRounds, startingPlayer: Int) -> ThisOrThatCouchState {
        ThisOrThatCouchState(totalRounds: Swift.max(1, rounds),
                             startingPlayer: startingPlayer == 0 ? 0 : 1)
    }

    /// Player (0/1) who picks FIRST in the current round.
    static func firstPicker(_ state: ThisOrThatCouchState) -> Int {
        (state.startingPlayer + state.round) % 2
    }

    /// Player (0/1) whose pick is being asked for right now — nil outside
    /// the two picking phases.
    static func currentPicker(_ state: ThisOrThatCouchState) -> Int? {
        switch state.phase {
        case .firstPick: return firstPicker(state)
        case .secondPick: return 1 - firstPicker(state)
        case .handoff, .reveal, .finished: return nil
        }
    }

    /// This round's pick of a specific player (0/1) — nil until made.
    static func pick(of player: Int, in state: ThisOrThatCouchState) -> String? {
        player == firstPicker(state) ? state.firstPick : state.secondPick
    }

    /// Applies a pick ("a"/"b"). Defensive like every reducer here:
    /// invalid options or picks outside a picking phase are skipped, so a
    /// double-tap can never fork the state.
    static func pick(_ state: ThisOrThatCouchState, option: String) -> ThisOrThatCouchState {
        guard option == "a" || option == "b" else { return state }
        var next = state
        switch state.phase {
        case .firstPick:
            next.firstPick = option
            next.phase = .handoff
        case .secondPick:
            next.secondPick = option
            next.phase = .reveal
            if state.firstPick == option { next.matches += 1 }
        case .handoff, .reveal, .finished:
            break
        }
        return next
    }

    /// The hand-off is confirmed — the second player takes over.
    static func confirmHandoff(_ state: ThisOrThatCouchState) -> ThisOrThatCouchState {
        guard state.phase == .handoff else { return state }
        var next = state
        next.phase = .secondPick
        return next
    }

    /// Leaves the reveal: next round, or finished after the last one.
    static func advance(_ state: ThisOrThatCouchState) -> ThisOrThatCouchState {
        guard state.phase == .reveal else { return state }
        var next = state
        next.round += 1
        next.firstPick = nil
        next.secondPick = nil
        next.phase = next.round >= next.totalRounds ? .finished : .firstPick
        return next
    }

    /// True when the revealed round's picks agree.
    static func isMatch(_ state: ThisOrThatCouchState) -> Bool {
        state.phase == .reveal && state.firstPick != nil && state.firstPick == state.secondPick
    }
}
