import Foundation

// Feedback hints for the W8C boards — pure helpers the game views render.
// BoardGameRules.swift stays the untouched reducer home; the NEW hints of
// the feel pass (spatial Käsekästchen edge names, the Mancala sowing
// preview plan, Memory-Duo reveal pacing) live here. Foundation-only so
// Linux `swift test` pins every hint against the reducers.

/// Spatial description of one Käsekästchen edge: which side of which named
/// box ("obere Kante von B2" instead of "Kante 17"). Edges on the outer rim
/// are described from the single box they border; inner edges use the box
/// above/left so every edge has exactly one stable name.
struct KaeseEdgeDescription: Equatable {
    enum Side: String {
        case top, bottom, left, right
    }

    let side: Side
    /// Board name of the described box — column letter + row number ("B2"),
    /// row 1 = the creator's top edge row, same as the edge-index contract.
    let square: String
}

enum BoardGameFeedback {
    // MARK: Käsekästchen (spatial edge names)

    /// Maps a raw edge index (server contract: horizontal first, then
    /// vertical) to its spatial description; nil for out-of-range indexes.
    static func kaeseEdgeDescription(size: Int, edge: Int) -> KaeseEdgeDescription? {
        guard size > 0, edge >= 0, edge < 2 * size * (size + 1) else { return nil }
        let horizontalCount = size * (size + 1)
        if edge < horizontalCount {
            let row = edge / size
            let col = edge % size
            // The very last horizontal row borders no box below — describe
            // it as the BOTTOM edge of the box above.
            if row == size {
                return KaeseEdgeDescription(side: .bottom, square: squareName(row: row - 1, col: col))
            }
            return KaeseEdgeDescription(side: .top, square: squareName(row: row, col: col))
        }
        let vertical = edge - horizontalCount
        let row = vertical / (size + 1)
        let col = vertical % (size + 1)
        if col == size {
            return KaeseEdgeDescription(side: .right, square: squareName(row: row, col: col - 1))
        }
        return KaeseEdgeDescription(side: .left, square: squareName(row: row, col: col))
    }

    private static func squareName(row: Int, col: Int) -> String {
        let letter = Character(UnicodeScalar(UInt8(65 + col % 26)))
        return "\(letter)\(row + 1)"
    }

    // MARK: Mancala (sowing preview plan)

    /// Everything the long-press preview overlays: which pits gain stones,
    /// where the last stone lands, and what a capture would sweep.
    struct MancalaSowPlan: Equatable {
        /// Stones added per own pit (index 0…5) during the sow.
        let ownGains: [Int]
        /// Stones added per opponent pit during the sow.
        let theirGains: [Int]
        /// Stones dropped into the own store during the sow.
        let storeGain: Int
        /// The last stone landed in the own store — extra turn.
        let landsInStore: Bool
        /// Own pit index the last stone lands in (nil when it is the store
        /// or an opponent pit).
        let landingOwnPit: Int?
        /// Opponent pit a capture would sweep, with the total stones won
        /// (landing stone + opposite pit); zero stones = no capture.
        let capturedOpponentPit: Int?
        let capturedStones: Int
    }

    /// Walks the same 13-cell track as `Mancala.sow` WITHOUT mutating any
    /// state — the read-only twin the preview overlay renders. nil when the
    /// pit is empty or out of range.
    static func mancalaSowPlan(ownPits: [Int], theirPits: [Int], pit: Int) -> MancalaSowPlan? {
        let pitsPerSide = 6
        guard pit >= 0, pit < pitsPerSide,
              ownPits.count == pitsPerSide, theirPits.count == pitsPerSide,
              ownPits[pit] > 0 else { return nil }
        var own = ownPits
        var theirs = theirPits
        var ownGains = [Int](repeating: 0, count: pitsPerSide)
        var theirGains = [Int](repeating: 0, count: pitsPerSide)
        var storeGain = 0
        var hand = own[pit]
        own[pit] = 0
        var position = pit
        while hand > 0 {
            position = (position + 1) % 13
            if position == pitsPerSide {
                storeGain += 1
            } else if position < pitsPerSide {
                own[position] += 1
                ownGains[position] += 1
            } else {
                theirs[position - 7] += 1
                theirGains[position - 7] += 1
            }
            hand -= 1
        }
        let landsInStore = position == pitsPerSide
        let landingOwnPit = (!landsInStore && position < pitsPerSide) ? position : nil
        var capturedPit: Int?
        var captured = 0
        if let landing = landingOwnPit, own[landing] == 1, theirs[5 - landing] > 0 {
            capturedPit = 5 - landing
            captured = 1 + theirs[5 - landing]
        }
        return MancalaSowPlan(ownGains: ownGains, theirGains: theirGains,
                              storeGain: storeGain, landsInStore: landsInStore,
                              landingOwnPit: landingOwnPit,
                              capturedOpponentPit: capturedPit,
                              capturedStones: captured)
    }

    // MARK: Memory-Duo (staged reveal pacing)

    /// How long a mismatched pair stays face-up before flipping back —
    /// long enough to actually SEE the second motif.
    static let memoryMismatchPause = 0.8
    /// Short beat on a match before the pair settles into its owner tint.
    static let memoryMatchPause = 0.35
}
