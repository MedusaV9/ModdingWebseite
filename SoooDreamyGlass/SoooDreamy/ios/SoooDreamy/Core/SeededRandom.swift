import Foundation

/// Tiny deterministic PRNG (SplitMix64) so both partners' devices derive the
/// exact same shuffled question order / daily word from a shared seed.
/// Swift's own RNG (and `.shuffled()`) is NOT deterministic across devices.
struct SeededGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform-ish value in 0..<bound (bound must be > 0).
    mutating func int(upTo bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        return Int(next() % UInt64(bound))
    }
}

extension Array {
    /// Deterministic Fisher–Yates shuffle driven by `SeededGenerator` —
    /// identical order on every device for the same seed.
    func seededShuffled(seed: Int) -> [Element] {
        var generator = SeededGenerator(seed: seed)
        var items = self
        var index = items.count - 1
        while index > 0 {
            let other = generator.int(upTo: index + 1)
            if other != index {
                items.swapAt(index, other)
            }
            index -= 1
        }
        return items
    }
}
