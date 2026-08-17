import Foundation

// Schiffe versenken (battleship) — pure deterministic core, UI-free.
//
// Hidden information via commit-reveal (Core/CommitReveal.swift + relay):
// each player places a fleet locally, commits `sha256(layout + salt)`, and
// only REPORTS hit/miss per incoming salvo during the battle. After the win
// both reveal `layout + salt`; the relay certifies the hash (`verified`) and
// `Battleship.honest` replays every report against the revealed board, so a
// cheater is exposed post-hoc instead of trusted mid-game.
//
// Move protocol (relay `data` objects, reduced in arrival order):
// - `{kind: "commit", commit: <hex>}`            — fleet locked in
// - `{kind: "salvo", cells: [Int]}`              — attacker fires ≤2 cells
// - `{kind: "report", index, hits, sunk}`        — DEFENDER answers salvo #index
// - `{kind: "reveal", reveal, salt, commitId}`   — board opened, relay verifies

// MARK: - Events (typed view of the relay moves)

enum BattleshipEvent {
    case commit(member: String)
    case salvo(member: String, cells: [Int])
    case report(member: String, index: Int, hits: [Int], sunk: [Int])
    case reveal(member: String, layout: String, salt: String, serverVerified: Bool)
}

// MARK: - State

struct BattleshipSalvo {
    let member: String
    let cells: [Int]
}

struct BattleshipReport {
    let hits: [Int]
    /// Sizes of ships this salvo sank (e.g. [3] — "the 3er is down!").
    let sunk: [Int]
}

struct BattleshipReveal {
    let layout: String
    let salt: String
    /// The relay's commit-reveal certification of this reveal move.
    let serverVerified: Bool
}

enum BattleshipPhase {
    case setup
    case battle
    case finished
}

struct BattleshipState {
    var committed: Set<String> = []
    var salvos: [BattleshipSalvo] = []
    /// Salvo index → the defender's answer (first report wins).
    var reports: [Int: BattleshipReport] = [:]
    /// Revealer → their opened board (first reveal wins).
    var reveals: [String: BattleshipReveal] = [:]
    var winner: String?

    var phase: BattleshipPhase {
        if winner != nil { return .finished }
        return committed.count >= 2 ? .battle : .setup
    }

    /// All cells a member has fired at so far.
    func shotCells(by member: String) -> Set<Int> {
        Set(salvos.filter { $0.member == member }.flatMap(\.cells))
    }

    /// Cell → hit? for one attacker; nil value = report still pending.
    func shotResults(by member: String) -> [Int: Bool?] {
        var results: [Int: Bool?] = [:]
        for (index, salvo) in salvos.enumerated() where salvo.member == member {
            let report = reports[index]
            for cell in salvo.cells {
                results.updateValue(report.map { $0.hits.contains(cell) }, forKey: cell)
            }
        }
        return results
    }

    /// Confirmed hits an attacker landed on the partner's fleet.
    func hitCount(by member: String) -> Int {
        shotResults(by: member).values.filter { $0 == true }.count
    }

    /// Sizes of the partner ships this attacker has sunk, in sink order.
    func sunkSizes(by member: String) -> [Int] {
        salvos.enumerated()
            .filter { $0.element.member == member }
            .compactMap { reports[$0.offset] }
            .flatMap(\.sunk)
    }

    /// True while the newest salvo BY the partner still lacks my report.
    func pendingReportIndex(defender: String) -> Int? {
        for (index, salvo) in salvos.enumerated()
        where salvo.member != defender && reports[index] == nil {
            return index
        }
        return nil
    }
}

// MARK: - Rules

enum Battleship {
    /// 8×8 keeps a phone-sized grid tappable; cells are 0..<64, row-major.
    static let size = 8
    /// Fleet sizes — 12 ship cells total.
    static let fleet = [4, 3, 3, 2]
    /// Shots per turn ("Salve").
    static let salvoSize = 2

    static var cellCount: Int { size * size }
    static var fleetCellCount: Int { fleet.reduce(0, +) }

    /// Creator fires the first salvo, then strict alternation.
    static func turn(state: BattleshipState, starter: String, partner: String) -> String {
        state.salvos.count.isMultiple(of: 2) ? starter : partner
    }

    /// Reduces the ordered event list into a state. Defensive: events from
    /// the wrong player / phase, repeated cells, over-long salvos and
    /// duplicate reports are SKIPPED so a double-send can never fork state.
    static func reduce(events: [BattleshipEvent], starter: String, partner: String) -> BattleshipState {
        var state = BattleshipState()
        let members: Set<String> = [starter, partner]
        for event in events {
            switch event {
            case .commit(let member):
                guard members.contains(member) else { continue }
                state.committed.insert(member)

            case .salvo(let member, let cells):
                guard state.phase == .battle,
                      member == turn(state: state, starter: starter, partner: partner)
                else { continue }
                let already = state.shotCells(by: member)
                var unique: [Int] = []
                for cell in cells
                where cell >= 0 && cell < cellCount && !already.contains(cell) && !unique.contains(cell) {
                    unique.append(cell)
                }
                guard !unique.isEmpty else { continue }
                state.salvos.append(BattleshipSalvo(member: member,
                                                    cells: Array(unique.prefix(salvoSize))))

            case .report(let member, let index, let hits, let sunk):
                guard state.salvos.indices.contains(index),
                      state.reports[index] == nil,
                      state.salvos[index].member != member,   // only the defender answers
                      members.contains(member)
                else { continue }
                let salvoCells = Set(state.salvos[index].cells)
                let cleanHits = hits.filter { salvoCells.contains($0) }
                let cleanSunk = sunk.filter { $0 > 0 && $0 <= (fleet.max() ?? 0) }
                state.reports[index] = BattleshipReport(hits: cleanHits, sunk: cleanSunk)
                let attacker = state.salvos[index].member
                if state.winner == nil, state.hitCount(by: attacker) >= fleetCellCount {
                    state.winner = attacker
                }

            case .reveal(let member, let layout, let salt, let serverVerified):
                guard members.contains(member), state.reveals[member] == nil else { continue }
                state.reveals[member] = BattleshipReveal(layout: layout, salt: salt,
                                                         serverVerified: serverVerified)
            }
        }
        return state
    }

    // MARK: Layout encoding

    /// Canonical string form of a fleet: ships sorted by their lowest cell,
    /// cells ascending, `"0,1,2,3|17,25,33|…"` — the commit-reveal secret.
    static func encodeLayout(_ ships: [[Int]]) -> String {
        ships.map { $0.sorted() }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
            .map { $0.map(String.init).joined(separator: ",") }
            .joined(separator: "|")
    }

    static func decodeLayout(_ text: String) -> [[Int]]? {
        var ships: [[Int]] = []
        for part in text.split(separator: "|") {
            let cells = part.split(separator: ",").compactMap { Int($0) }
            guard !cells.isEmpty, cells.count == part.split(separator: ",").count else { return nil }
            ships.append(cells)
        }
        return ships.isEmpty ? nil : ships
    }

    /// Legality of a (revealed) fleet: exact fleet sizes, every ship a
    /// straight horizontal/vertical line inside the board, no overlaps.
    static func isValidLayout(_ ships: [[Int]]) -> Bool {
        guard ships.map(\.count).sorted() == fleet.sorted() else { return false }
        var seen: Set<Int> = []
        for ship in ships {
            let cells = ship.sorted()
            guard cells.allSatisfy({ $0 >= 0 && $0 < cellCount }) else { return false }
            guard Set(cells).count == cells.count else { return false }
            let rows = Set(cells.map { $0 / size })
            let columns = Set(cells.map { $0 % size })
            let horizontal = rows.count == 1
                && cells.last! - cells.first! == cells.count - 1
            let vertical = columns.count == 1
                && cells.last! - cells.first! == (cells.count - 1) * size
            guard horizontal || vertical else { return false }
            guard seen.isDisjoint(with: cells) else { return false }
            seen.formUnion(cells)
        }
        return true
    }

    /// Deterministic random fleet for a seed — same seed, same board (used
    /// for the shuffle button and pinned by the logic tests). Ships prefer
    /// not to touch; if a roll cannot fit (rare on 8×8) the next roll runs
    /// with the advanced RNG state, so the function always terminates.
    static func randomLayout(seed: Int) -> [[Int]] {
        var rng = SeededGenerator(seed: seed)
        for attempt in 0..<64 {
            if let ships = tryPlaceFleet(&rng, avoidTouching: attempt < 48) {
                return ships
            }
        }
        // Unreachable in practice; a diagonal fallback keeps the API total.
        var fallback: [[Int]] = []
        var row = 0
        for length in fleet {
            fallback.append((0..<length).map { row * size + $0 })
            row += 2
        }
        return fallback
    }

    private static func tryPlaceFleet(_ rng: inout SeededGenerator,
                                      avoidTouching: Bool) -> [[Int]]? {
        var occupied: Set<Int> = []
        var blocked: Set<Int> = []
        var ships: [[Int]] = []
        for length in fleet {
            var placed = false
            for _ in 0..<128 {
                let vertical = rng.int(upTo: 2) == 1
                let maxCol = vertical ? size : size - length + 1
                let maxRow = vertical ? size - length + 1 : size
                let col = rng.int(upTo: maxCol)
                let row = rng.int(upTo: maxRow)
                let cells = (0..<length).map { step in
                    vertical ? (row + step) * size + col : row * size + col + step
                }
                let clash = avoidTouching ? blocked : occupied
                guard cells.allSatisfy({ !clash.contains($0) }) else { continue }
                ships.append(cells)
                occupied.formUnion(cells)
                for cell in cells {
                    blocked.formUnion(neighborhood(of: cell))
                }
                placed = true
                break
            }
            if !placed { return nil }
        }
        return ships
    }

    /// The cell plus its 8 neighbours (board-clipped).
    private static func neighborhood(of cell: Int) -> [Int] {
        let row = cell / size
        let col = cell % size
        var cells: [Int] = []
        for dr in -1...1 {
            for dc in -1...1 {
                let r = row + dr
                let c = col + dc
                if r >= 0, r < size, c >= 0, c < size {
                    cells.append(r * size + c)
                }
            }
        }
        return cells
    }

    // MARK: Defender bookkeeping

    /// The truthful answer to a salvo against `layout`, given the cells the
    /// attacker already hit before: which shots hit, which ships that sank.
    static func report(cells: [Int], layout: [[Int]], alreadyHit: Set<Int>) -> (hits: [Int], sunk: [Int]) {
        let shipCells = Set(layout.flatMap { $0 })
        let hits = cells.filter { shipCells.contains($0) }
        var sunk: [Int] = []
        let total = alreadyHit.union(hits)
        for ship in layout
        where ship.allSatisfy({ total.contains($0) }) && !ship.allSatisfy({ alreadyHit.contains($0) }) {
            sunk.append(ship.count)
        }
        return (hits, sunk.sorted())
    }

    /// Post-reveal fair-play audit: replays every salvo against the
    /// defender's revealed layout and compares with the reports they sent.
    /// True = every report was truthful.
    static func honest(state: BattleshipState, defender: String, layout: [[Int]]) -> Bool {
        var alreadyHit: Set<Int> = []
        for (index, salvo) in state.salvos.enumerated() where salvo.member != defender {
            guard let sent = state.reports[index] else { continue }
            let expected = report(cells: salvo.cells, layout: layout, alreadyHit: alreadyHit)
            guard Set(sent.hits) == Set(expected.hits),
                  sent.sunk.sorted() == expected.sunk
            else { return false }
            alreadyHit.formUnion(expected.hits)
        }
        return true
    }

    // MARK: Share card

    /// Emoji grid of MY shots on the partner's waters (💥 hit, 🌊 miss,
    /// ⬛ untouched) — the chat-shareable result, Wordle-style.
    static func shareGrid(results: [Int: Bool?]) -> String {
        (0..<size).map { row in
            (0..<size).map { col in
                switch results[row * size + col] {
                case .some(.some(true)): return "💥"
                case .some(.some(false)): return "🌊"
                default: return "⬛"
                }
            }.joined()
        }.joined(separator: "\n")
    }
}
