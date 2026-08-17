import XCTest
@testable import SoooDreamyLogic

/// Tests for the deterministic SplitMix64 PRNG and the seeded shuffle
/// in `SoooDreamy/Core/SeededRandom.swift`.
final class SeededRandomTests: XCTestCase {

    // MARK: - SeededGenerator

    func testSameSeedProducesIdenticalSequence() {
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 12345)
        let seqA = (0..<20).map { _ in a.next() }
        let seqB = (0..<20).map { _ in b.next() }
        XCTAssertEqual(seqA, seqB, "same seed must yield the exact same 20-value sequence")
    }

    func testDifferentSeedsProduceDifferentSequences() {
        var a = SeededGenerator(seed: 12345)
        var b = SeededGenerator(seed: 54321)
        let seqA = (0..<20).map { _ in a.next() }
        let seqB = (0..<20).map { _ in b.next() }
        XCTAssertNotEqual(seqA, seqB, "different seeds should diverge")
    }

    func testIntUpToStaysInBounds() {
        for bound in [1, 2, 7] {
            var generator = SeededGenerator(seed: 987)
            for iteration in 0..<1000 {
                let value = generator.int(upTo: bound)
                XCTAssertTrue((0..<bound).contains(value),
                              "int(upTo: \(bound)) produced \(value) at iteration \(iteration)")
            }
        }
    }

    // MARK: - seededShuffled

    func testSeededShuffledIsDeterministic() {
        let items = Array(1...50)
        XCTAssertEqual(items.seededShuffled(seed: 7), items.seededShuffled(seed: 7),
                       "two shuffles with the same seed must be identical")
    }

    func testSeededShuffledIsAPermutation() {
        let items = Array(1...50)
        let shuffled = items.seededShuffled(seed: 99)
        XCTAssertEqual(shuffled.sorted(), items.sorted(),
                       "shuffle must be a permutation of the input")
    }

    func testSeededShuffledGoldenCheck() {
        let base = Array(1...10)
        let seed42First = base.seededShuffled(seed: 42)
        let seed42Second = base.seededShuffled(seed: 42)
        XCTAssertEqual(seed42First, seed42Second, "seed 42 must be stable across calls")
        XCTAssertEqual(seed42First.sorted(), base, "seed 42 shuffle must be a permutation")
        XCTAssertNotEqual(seed42First, base.seededShuffled(seed: 43),
                          "seed 42 and seed 43 should produce different orders")
    }
}
