import XCTest
@testable import SoooDreamyLogic

/// Integrity checks for the emoji-riddle pack in
/// `SoooDreamy/Content/Data/EmojiRiddlesData.swift`.
final class EmojiRiddlesTests: XCTestCase {

    private let allowedCategories: Set<String> = ["movie", "song", "place", "food", "couple", "activity"]

    func testCountAtLeast195() {
        XCTAssertGreaterThanOrEqual(ContentPack.emojiRiddles.count, 195)
    }

    func testIdsUniqueAndAscendingFromOne() {
        let ids = ContentPack.emojiRiddles.map(\.id)
        XCTAssertEqual(ids, Array(1...max(ids.count, 1)),
                       "emojiRiddles: ids must be unique and ascending from 1")
    }

    func testCategoriesValidAndEachHasAtLeastTenRiddles() {
        var counts: [String: Int] = [:]
        for riddle in ContentPack.emojiRiddles {
            XCTAssertTrue(allowedCategories.contains(riddle.category),
                          "emojiRiddles id \(riddle.id): unknown category \"\(riddle.category)\"")
            counts[riddle.category, default: 0] += 1
        }
        for category in allowedCategories {
            XCTAssertGreaterThanOrEqual(counts[category] ?? 0, 10,
                                        "category \"\(category)\" needs at least 10 riddles, has \(counts[category] ?? 0)")
        }
    }

    func testEmojisNonEmptyAndFreeOfAsciiLettersDigitsSpaces() {
        for riddle in ContentPack.emojiRiddles {
            XCTAssertFalse(riddle.emojis.isEmpty, "emojiRiddles id \(riddle.id): empty emoji string")
            for scalar in riddle.emojis.unicodeScalars {
                let v = scalar.value
                let isAsciiLetter = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
                let isAsciiDigit = (0x30...0x39).contains(v)
                let isSpace = v == 0x20
                XCTAssertFalse(isAsciiLetter || isAsciiDigit || isSpace,
                               "emojiRiddles id \(riddle.id): emoji string \"\(riddle.emojis)\" contains " +
                               "ASCII letter/digit/space (U+\(String(v, radix: 16, uppercase: true)))")
            }
        }
    }

    func testAnswersNonEmptyInBothLanguages() {
        for riddle in ContentPack.emojiRiddles {
            XCTAssertFalse(riddle.answer.de.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "emojiRiddles id \(riddle.id): empty German answer")
            XCTAssertFalse(riddle.answer.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "emojiRiddles id \(riddle.id): empty English answer")
        }
    }

    func testNoDuplicateAnswersWithinACategory() {
        var seenDE: [String: Int] = [:] // "category|answer" → first id
        var seenEN: [String: Int] = [:]
        for riddle in ContentPack.emojiRiddles {
            let deKey = "\(riddle.category)|\(riddle.answer.de)"
            let enKey = "\(riddle.category)|\(riddle.answer.en)"
            if let firstId = seenDE[deKey] {
                XCTFail("duplicate (category, answer.de) pair \"\(deKey)\": ids \(firstId) and \(riddle.id)")
            } else {
                seenDE[deKey] = riddle.id
            }
            if let firstId = seenEN[enKey] {
                XCTFail("duplicate (category, answer.en) pair \"\(enKey)\": ids \(firstId) and \(riddle.id)")
            } else {
                seenEN[enKey] = riddle.id
            }
        }
    }
}
