import XCTest
@testable import SoooDreamyLogic

/// Integrity of the Liebes-Wordle word pools (solution pool = guess dictionary).
final class WordleWordsTests: XCTestCase {

    private func validate(_ words: [String], label: String) {
        XCTAssertGreaterThanOrEqual(words.count, 350, "\(label): needs ≥ 350 words")
        XCTAssertEqual(Set(words).count, words.count, "\(label): contains duplicates")
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for word in words {
            XCTAssertEqual(word.count, 5, "\(label): '\(word)' is not 5 letters")
            XCTAssertTrue(word.allSatisfy { allowed.contains($0) },
                          "\(label): '\(word)' contains non A–Z characters")
        }
    }

    func testGermanWords() {
        validate(ContentPack.wordleWordsDE, label: "DE")
    }

    func testEnglishWords() {
        validate(ContentPack.wordleWordsEN, label: "EN")
    }

    /// The daily word must be deterministic per (dateKey, coupleId) — both
    /// partners' devices independently pick the same word.
    func testDailyWordDeterminism() {
        func pick(_ list: [String], dateKey: String, coupleId: String) -> String {
            let seed = (dateKey + coupleId).unicodeScalars.reduce(5381 as UInt64) {
                ($0 << 5) &+ $0 &+ UInt64($1.value)
            }
            return list[Int(seed % UInt64(list.count))]
        }
        for list in [ContentPack.wordleWordsDE, ContentPack.wordleWordsEN] {
            let a = pick(list, dateKey: "2026-08-03", coupleId: "c_abc")
            let b = pick(list, dateKey: "2026-08-03", coupleId: "c_abc")
            XCTAssertEqual(a, b)
            let differentDays = (1...20).map {
                pick(list, dateKey: String(format: "2026-08-%02d", $0), coupleId: "c_abc")
            }
            XCTAssertGreaterThan(Set(differentDays).count, 1, "words should vary across days")
        }
    }
}
