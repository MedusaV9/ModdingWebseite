import Foundation

// W8C board & duel games — pure, deterministic client reducers. The server
// stores an ordered move list and stays authoritative (a decisive move ends
// the session server-side); BOTH clients derive the identical board from
// payload + moves via these helpers. Every reducer is defensive exactly like
// the server's state builders: moves from the wrong member, out-of-range
// indexes, or rule-breaking data are SKIPPED (not errors), so a double-send
// or a stale frame can never fork the state. Board indexes are always
// `row * size + col` with row 0 = the CREATOR's back row; the creator moves
// first. UI-free on purpose — the Linux logic tests pin every rule.

// MARK: - Dame (checkers, 8×8 dark squares)

struct DamePiece: Equatable {
    let owner: String
    var king: Bool
}

struct DameState {
    /// 64 squares, only the dark ones are ever occupied.
    var board: [DamePiece?]
    var turn: String
    /// Capture-free plies in a row (the draw clock).
    var quietPlies: Int
    var moveCount: Int
    let starter: String
    let partner: String

    func count(of member: String) -> Int {
        board.reduce(0) { $0 + ($1?.owner == member ? 1 : 0) }
    }

    /// Men of the starter walk toward row 7, the partner's toward row 0.
    func forward(of member: String) -> Int {
        member == starter ? 1 : -1
    }
}

enum Dame {
    static let size = 8
    static let squares = 64
    /// International-simplified: men and kings both capture in ALL four
    /// diagonals; only quiet steps are forward-locked for men.
    static let diagonals: [(Int, Int)] = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    static func row(_ index: Int) -> Int { index / size }
    static func col(_ index: Int) -> Int { index % size }

    /// Dame lives on the dark squares only: `(row+col) % 2 == 1`.
    static func isPlayable(_ index: Int) -> Bool {
        index >= 0 && index < squares && (row(index) + col(index)) % 2 == 1
    }

    static func initialBoard(starter: String, partner: String) -> [DamePiece?] {
        var board = [DamePiece?](repeating: nil, count: squares)
        for index in 0..<squares where isPlayable(index) {
            if row(index) <= 2 {
                board[index] = DamePiece(owner: starter, king: false)
            } else if row(index) >= 5 {
                board[index] = DamePiece(owner: partner, king: false)
            }
        }
        return board
    }

    /// Single jumps available from one square. Captured squares stay
    /// blocked-but-unjumpable during a chain (official rule: pieces are
    /// lifted at the END of the move).
    static func jumps(board: [DamePiece?], from index: Int, owner: String,
                      captured: Set<Int> = []) -> [(to: Int, mid: Int)] {
        var result: [(to: Int, mid: Int)] = []
        let r = row(index)
        let c = col(index)
        for (dr, dc) in diagonals {
            let toRow = r + 2 * dr
            let toCol = c + 2 * dc
            guard toRow >= 0, toRow < size, toCol >= 0, toCol < size else { continue }
            let mid = (r + dr) * size + (c + dc)
            let to = toRow * size + toCol
            guard let victim = board[mid], victim.owner != owner, !captured.contains(mid) else { continue }
            guard board[to] == nil else { continue }
            result.append((to: to, mid: mid))
        }
        return result
    }

    /// Quiet diagonal steps from one square (men forward-only, kings all four).
    static func steps(board: [DamePiece?], from index: Int, king: Bool, forward: Int) -> [Int] {
        var result: [Int] = []
        let r = row(index)
        let c = col(index)
        for (dr, dc) in diagonals {
            if !king && dr != forward { continue }
            let toRow = r + dr
            let toCol = c + dc
            guard toRow >= 0, toRow < size, toCol >= 0, toCol < size else { continue }
            let to = toRow * size + toCol
            if board[to] == nil { result.append(to) }
        }
        return result
    }

    static func sideHasCapture(board: [DamePiece?], owner: String) -> Bool {
        board.indices.contains { index in
            guard let piece = board[index], piece.owner == owner else { return false }
            return !jumps(board: board, from: index, owner: owner).isEmpty
        }
    }

    static func sideHasMove(board: [DamePiece?], owner: String, forward: Int) -> Bool {
        board.indices.contains { index in
            guard let piece = board[index], piece.owner == owner else { return false }
            return !steps(board: board, from: index, king: piece.king, forward: forward).isEmpty
                || !jumps(board: board, from: index, owner: owner).isEmpty
        }
    }

    /// Legality of one move path against a board — the client mirror of the
    /// server's trace: a quiet step while any capture exists, or a jump
    /// chain that stops while it could continue, is ILLEGAL (the server
    /// answers `409 capture_required`).
    static func trace(board: [DamePiece?], path: [Int], owner: String,
                      forward: Int) -> (to: Int, captures: [Int])? {
        guard path.count >= 2, path.count <= 13 else { return nil }
        guard path.allSatisfy(isPlayable) else { return nil }
        guard Set(path.dropFirst()).count == path.count - 1 else { return nil }
        let from = path[0]
        guard let piece = board[from], piece.owner == owner else { return nil }
        var sim = board
        sim[from] = nil
        if path.count == 2 {
            let dr = row(path[1]) - row(from)
            let dc = col(path[1]) - col(from)
            if abs(dr) == 1 && abs(dc) == 1 {
                guard sim[path[1]] == nil, piece.king || dr == forward else { return nil }
                guard !sideHasCapture(board: board, owner: owner) else { return nil }
                return (to: path[1], captures: [])
            }
        }
        var captured: Set<Int> = []
        var orderedCaptures: [Int] = []
        var at = from
        for step in 1..<path.count {
            let to = path[step]
            let dr = row(to) - row(at)
            let dc = col(to) - col(at)
            guard abs(dr) == 2, abs(dc) == 2 else { return nil }
            let mid = (row(at) + dr / 2) * size + (col(at) + dc / 2)
            guard let victim = sim[mid], victim.owner != owner, !captured.contains(mid) else { return nil }
            guard sim[to] == nil else { return nil }
            captured.insert(mid)
            orderedCaptures.append(mid)
            at = to
        }
        guard jumps(board: sim, from: at, owner: owner, captured: captured).isEmpty else { return nil }
        return (to: at, captures: orderedCaptures)
    }

    /// Applies ONE legal move path for the side to move — nil when the path
    /// is illegal in `state`. A man promotes only when the move ENDS on the
    /// far row (a chain passing through it stays a man).
    static func applying(path: [Int], to state: DameState) -> DameState? {
        let forward = state.forward(of: state.turn)
        guard let traced = trace(board: state.board, path: path,
                                 owner: state.turn, forward: forward),
              let piece = state.board[path[0]] else { return nil }
        var next = state
        next.board[path[0]] = nil
        for mid in traced.captures { next.board[mid] = nil }
        let backRow = forward == 1 ? size - 1 : 0
        next.board[traced.to] = DamePiece(owner: state.turn,
                                          king: piece.king || row(traced.to) == backRow)
        next.quietPlies = traced.captures.isEmpty ? state.quietPlies + 1 : 0
        next.moveCount = state.moveCount + 1
        next.turn = state.turn == state.starter ? state.partner : state.starter
        return next
    }

    /// Reduces the ordered `{kind:"move", path}` list into a board. The
    /// creator's men start on rows 0–2 and walk toward row 7.
    static func reduce(moves: [(memberId: String, path: [Int])],
                       starter: String, partner: String) -> DameState {
        var state = DameState(board: initialBoard(starter: starter, partner: partner),
                              turn: starter, quietPlies: 0, moveCount: 0,
                              starter: starter, partner: partner)
        for move in moves {
            guard move.memberId == state.turn,
                  let next = applying(path: move.path, to: state) else { continue }
            state = next
        }
        return state
    }

    /// Every legal move path for the side to move: complete capture chains
    /// when any capture exists (Schlagzwang + continuation duty), quiet
    /// steps otherwise — the source of the tap-path preview.
    static func legalPaths(state: DameState) -> [[Int]] {
        var captures: [[Int]] = []
        var steps: [[Int]] = []
        let forward = state.forward(of: state.turn)
        for index in state.board.indices {
            guard let piece = state.board[index], piece.owner == state.turn else { continue }
            var sim = state.board
            sim[index] = nil
            func walk(at: Int, captured: Set<Int>, path: [Int]) {
                let continuations = jumps(board: sim, from: at, owner: state.turn, captured: captured)
                if continuations.isEmpty {
                    if path.count > 1 { captures.append(path) }
                    return
                }
                for jump in continuations {
                    walk(at: jump.to, captured: captured.union([jump.mid]), path: path + [jump.to])
                }
            }
            walk(at: index, captured: [], path: [index])
            for to in Self.steps(board: state.board, from: index, king: piece.king, forward: forward) {
                steps.append([index, to])
            }
        }
        return captures.isEmpty ? steps : captures
    }

    /// Server end conditions: a side without pieces or without a legal move
    /// loses; `drawPlies` capture-free plies force the draw.
    static func status(state: DameState, drawPlies: Int) -> (complete: Bool, winner: String?, draw: Bool) {
        for member in [state.starter, state.partner] where state.count(of: member) == 0 {
            return (true, member == state.starter ? state.partner : state.starter, false)
        }
        if state.quietPlies >= drawPlies { return (true, nil, true) }
        if !sideHasMove(board: state.board, owner: state.turn, forward: state.forward(of: state.turn)) {
            return (true, state.turn == state.starter ? state.partner : state.starter, false)
        }
        return (false, nil, false)
    }
}

// MARK: - Reversi (Othello, 8×8)

/// A parsed Reversi move — placements carry the index, passes stand alone.
enum ReversiMove: Equatable {
    case place(Int)
    case pass
}

struct ReversiState {
    var board: [String?]
    var turn: String
    var passes: Int
    var placed: Int
    let starter: String
    let partner: String

    var complete: Bool { placed == Reversi.squares || passes >= 2 }

    func count(of member: String) -> Int {
        board.reduce(0) { $0 + ($1 == member ? 1 : 0) }
    }

    var winner: String? {
        guard complete else { return nil }
        let a = count(of: starter)
        let b = count(of: partner)
        if a == b { return nil }
        return a > b ? starter : partner
    }
}

enum Reversi {
    static let size = 8
    static let squares = 64
    static let directions: [(Int, Int)] = [
        (0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]

    /// Enemy discs a placement on `index` would flip (empty = illegal).
    static func flips(board: [String?], index: Int, owner: String) -> [Int] {
        guard index >= 0, index < squares, board[index] == nil else { return [] }
        let row = index / size
        let col = index % size
        var result: [Int] = []
        for (dr, dc) in directions {
            var line: [Int] = []
            var r = row + dr
            var c = col + dc
            while r >= 0, r < size, c >= 0, c < size {
                let at = r * size + c
                guard let disc = board[at] else { break }
                if disc == owner {
                    result.append(contentsOf: line)
                    break
                }
                line.append(at)
                r += dr
                c += dc
            }
        }
        return result
    }

    static func legalMoves(board: [String?], owner: String) -> [Int] {
        (0..<squares).filter { board[$0] == nil && !flips(board: board, index: $0, owner: owner).isEmpty }
    }

    /// Initial discs: the creator owns 28/35, the partner 27/36 — then the
    /// ordered place/pass list replays. A pass while a placement exists is
    /// skipped (the server refuses it with `pass_not_allowed`).
    static func reduce(moves: [(memberId: String, move: ReversiMove)],
                       starter: String, partner: String) -> ReversiState {
        var board = [String?](repeating: nil, count: squares)
        board[27] = partner
        board[36] = partner
        board[28] = starter
        board[35] = starter
        var state = ReversiState(board: board, turn: starter, passes: 0, placed: 4,
                                 starter: starter, partner: partner)
        for entry in moves {
            guard entry.memberId == state.turn else { continue }
            switch entry.move {
            case .pass:
                guard legalMoves(board: state.board, owner: state.turn).isEmpty else { continue }
                state.passes += 1
                state.turn = state.turn == starter ? partner : starter
            case .place(let index):
                let flipped = flips(board: state.board, index: index, owner: state.turn)
                guard !flipped.isEmpty else { continue }
                state.board[index] = state.turn
                for flip in flipped { state.board[flip] = state.turn }
                state.placed += 1
                state.passes = 0
                state.turn = state.turn == starter ? partner : starter
            }
        }
        return state
    }
}

// MARK: - Käsekästchen (Dots & Boxes)

struct KaeseState {
    let size: Int
    var drawn: Set<Int>
    var owners: [String?]
    var scores: [String: Int]
    var turn: String
    let starter: String
    let partner: String

    var complete: Bool { drawn.count == Kaesekaestchen.edgeCount(size: size) }

    var winner: String? {
        guard complete else { return nil }
        let a = scores[starter] ?? 0
        let b = scores[partner] ?? 0
        if a == b { return nil }
        return a > b ? starter : partner
    }
}

enum Kaesekaestchen {
    /// `2 * size * (size+1)` edges: horizontal first, then vertical.
    static func edgeCount(size: Int) -> Int { 2 * size * (size + 1) }

    /// Horizontal edge above box-row `row` (row 0…size), left column `col`.
    static func horizontalEdge(size: Int, row: Int, col: Int) -> Int {
        row * size + col
    }

    /// Vertical edge left of box-column `col` (col 0…size), box-row `row`.
    static func verticalEdge(size: Int, row: Int, col: Int) -> Int {
        size * (size + 1) + row * (size + 1) + col
    }

    /// The four edges of box `row*size+col`: top, bottom, left, right.
    static func boxEdges(size: Int, box: Int) -> [Int] {
        let row = box / size
        let col = box % size
        return [
            horizontalEdge(size: size, row: row, col: col),
            horizontalEdge(size: size, row: row + 1, col: col),
            verticalEdge(size: size, row: row, col: col),
            verticalEdge(size: size, row: row, col: col + 1),
        ]
    }

    /// Unowned boxes that `edge` completes against the drawn set.
    static func closedBoxes(size: Int, drawn: Set<Int>, owners: [String?], edge: Int) -> [Int] {
        (0..<(size * size)).filter { box in
            guard owners[box] == nil else { return false }
            let edges = boxEdges(size: size, box: box)
            return edges.contains(edge) && edges.allSatisfy(drawn.contains)
        }
    }

    /// Closing ≥ 1 box scores each and keeps the turn (chainable).
    static func reduce(moves: [(memberId: String, edge: Int)], size: Int,
                       starter: String, partner: String) -> KaeseState {
        let edgeTotal = edgeCount(size: size)
        var state = KaeseState(size: size, drawn: [], owners: [String?](repeating: nil, count: size * size),
                               scores: [starter: 0, partner: 0], turn: starter,
                               starter: starter, partner: partner)
        for move in moves {
            guard move.memberId == state.turn else { continue }
            guard move.edge >= 0, move.edge < edgeTotal, !state.drawn.contains(move.edge) else { continue }
            state.drawn.insert(move.edge)
            let closed = closedBoxes(size: size, drawn: state.drawn, owners: state.owners, edge: move.edge)
            for box in closed { state.owners[box] = state.turn }
            state.scores[state.turn, default: 0] += closed.count
            if closed.isEmpty {
                state.turn = state.turn == starter ? partner : starter
            }
        }
        return state
    }
}

// MARK: - Gomoku (five in a row, 15×15)

struct GomokuState {
    var board: [String?]
    var turn: String
    var winner: String?
    var placed: Int
    /// The exact five winning cells (highlight uses the SAME exact-5 rule
    /// as the server — an overline never lights up).
    var winningRun: [Int]
    let starter: String
    let partner: String

    var draw: Bool { winner == nil && placed == Gomoku.squares }
}

enum Gomoku {
    static let size = 15
    static let squares = 225
    static let directions: [(Int, Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

    /// EXACTLY five contiguous stones through `index` — six or more in the
    /// same direction is an overline and does NOT win. Returns the run.
    static func exactFiveRun(board: [String?], index: Int, owner: String) -> [Int]? {
        let row = index / size
        let col = index % size
        for (dr, dc) in directions {
            var run = [index]
            for sign in [1, -1] {
                var r = row + dr * sign
                var c = col + dc * sign
                while r >= 0, r < size, c >= 0, c < size, board[r * size + c] == owner {
                    run.append(r * size + c)
                    r += dr * sign
                    c += dc * sign
                }
            }
            if run.count == 5 { return run.sorted() }
        }
        return nil
    }

    static func reduce(placements: [(memberId: String, index: Int)],
                       starter: String, partner: String) -> GomokuState {
        var state = GomokuState(board: [String?](repeating: nil, count: squares),
                                turn: starter, winner: nil, placed: 0, winningRun: [],
                                starter: starter, partner: partner)
        for placement in placements {
            guard placement.memberId == state.turn, state.winner == nil else { continue }
            guard placement.index >= 0, placement.index < squares,
                  state.board[placement.index] == nil else { continue }
            state.board[placement.index] = state.turn
            state.placed += 1
            if let run = exactFiveRun(board: state.board, index: placement.index, owner: state.turn) {
                state.winner = state.turn
                state.winningRun = run
            }
            state.turn = state.turn == starter ? partner : starter
        }
        return state
    }
}

// MARK: - Mancala (Kalaha, 6 pits + store per member)

struct MancalaSowOutcome: Equatable {
    let extraTurn: Bool
    let captured: Int
    let swept: Bool
}

struct MancalaState {
    var pits: [String: [Int]]
    var stores: [String: Int]
    var turn: String
    var complete: Bool
    let starter: String
    let partner: String

    var winner: String? {
        guard complete else { return nil }
        let a = stores[starter] ?? 0
        let b = stores[partner] ?? 0
        if a == b { return nil }
        return a > b ? starter : partner
    }
}

enum Mancala {
    static let pitsPerSide = 6

    /// One sow over the 13-cell track: own pits ascending → own store →
    /// opponent pits ascending (the opponent store is skipped). Mutates
    /// pits/stores in place and reports the derived outcome.
    static func sow(pits: inout [String: [Int]], stores: inout [String: Int],
                    me: String, them: String, pit: Int) -> MancalaSowOutcome {
        var hand = pits[me]?[pit] ?? 0
        pits[me]?[pit] = 0
        var position = pit
        while hand > 0 {
            position = (position + 1) % 13
            if position == pitsPerSide {
                stores[me, default: 0] += 1
            } else if position < pitsPerSide {
                pits[me]?[position] += 1
            } else {
                pits[them]?[position - 7] += 1
            }
            hand -= 1
        }
        let extraTurn = position == pitsPerSide
        var captured = 0
        if !extraTurn, position < pitsPerSide,
           pits[me]?[position] == 1, let opposite = pits[them]?[5 - position], opposite > 0 {
            captured = 1 + opposite
            stores[me, default: 0] += captured
            pits[me]?[position] = 0
            pits[them]?[5 - position] = 0
        }
        var swept = false
        let myEmpty = pits[me]?.allSatisfy { $0 == 0 } ?? true
        let theirEmpty = pits[them]?.allSatisfy { $0 == 0 } ?? true
        if myEmpty || theirEmpty {
            for side in [me, them] {
                stores[side, default: 0] += pits[side]?.reduce(0, +) ?? 0
                pits[side] = [Int](repeating: 0, count: pitsPerSide)
            }
            swept = true
        }
        return MancalaSowOutcome(extraTurn: extraTurn, captured: captured, swept: swept)
    }

    /// Board state from the ordered sow list. `extraTurn` keeps the mover.
    static func reduce(sows: [(memberId: String, pit: Int)], stones: Int,
                       starter: String, partner: String) -> MancalaState {
        var state = MancalaState(
            pits: [starter: [Int](repeating: stones, count: pitsPerSide),
                   partner: [Int](repeating: stones, count: pitsPerSide)],
            stores: [starter: 0, partner: 0],
            turn: starter, complete: false, starter: starter, partner: partner
        )
        for move in sows {
            guard move.memberId == state.turn, !state.complete else { continue }
            guard move.pit >= 0, move.pit < pitsPerSide,
                  (state.pits[state.turn]?[move.pit] ?? 0) > 0 else { continue }
            let them = state.turn == starter ? partner : starter
            let outcome = sow(pits: &state.pits, stores: &state.stores,
                              me: state.turn, them: them, pit: move.pit)
            state.complete = outcome.swept
            if !outcome.extraTurn {
                state.turn = them
            }
        }
        return state
    }

    /// Aussaat-Vorschau: the board AFTER sowing `pit` for `member`, or nil
    /// when the pit is empty / it is not the member's turn.
    static func preview(state: MancalaState, member: String,
                        pit: Int) -> (state: MancalaState, outcome: MancalaSowOutcome)? {
        guard member == state.turn, !state.complete,
              pit >= 0, pit < pitsPerSide,
              (state.pits[member]?[pit] ?? 0) > 0 else { return nil }
        var next = state
        let them = member == state.starter ? state.partner : state.starter
        let outcome = sow(pits: &next.pits, stores: &next.stores,
                          me: member, them: them, pit: pit)
        next.complete = outcome.swept
        if !outcome.extraTurn { next.turn = them }
        return (next, outcome)
    }
}

// MARK: - Memory-Duo (6×6 pair memory, hidden deck)

struct MemoryDuoState {
    /// Faces learned through accepted flips — once flipped, a card stays
    /// known to BOTH members (the shared pair memory is the game).
    var faces: [Int?]
    /// Card → member who matched it (nil = still open).
    var matched: [String?]
    var scores: [String: Int]
    var turn: String
    /// The single face-up unmatched card of the running turn.
    var open: Int?
    let starter: String
    let partner: String

    var complete: Bool { matched.allSatisfy { $0 != nil } }

    var winner: String? {
        guard complete else { return nil }
        let a = scores[starter] ?? 0
        let b = scores[partner] ?? 0
        if a == b { return nil }
        return a > b ? starter : partner
    }
}

enum MemoryDuo {
    /// The deck is server-only (seed stripped from every view); faces
    /// arrive exclusively inside accepted `{kind:"flip"}` moves. A match
    /// scores and keeps the turn; a miss passes it. Both flipped faces are
    /// remembered forever — that IS the couple's shared memory aid.
    static func reduce(flips: [(memberId: String, index: Int, face: Int)], cards: Int,
                       starter: String, partner: String) -> MemoryDuoState {
        var state = MemoryDuoState(faces: [Int?](repeating: nil, count: cards),
                                   matched: [String?](repeating: nil, count: cards),
                                   scores: [starter: 0, partner: 0],
                                   turn: starter, open: nil,
                                   starter: starter, partner: partner)
        for flip in flips {
            guard flip.memberId == state.turn else { continue }
            guard flip.index >= 0, flip.index < cards else { continue }
            guard state.matched[flip.index] == nil, flip.index != state.open else { continue }
            state.faces[flip.index] = flip.face
            guard let open = state.open else {
                state.open = flip.index
                continue
            }
            if state.faces[open] == flip.face {
                state.matched[open] = state.turn
                state.matched[flip.index] = state.turn
                state.scores[state.turn, default: 0] += 1
            } else {
                state.turn = state.turn == starter ? partner : starter
            }
            state.open = nil
        }
        return state
    }
}
