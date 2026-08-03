import XCTest
@testable import SoooDreamyLogic

/// Integrity checks for every bundled content pack in `SoooDreamy/Content/Data/`.
final class ContentPackTests: XCTestCase {

    // MARK: - Helpers

    /// Asserts ids are exactly 1, 2, 3, … n (unique AND ascending from 1).
    private func assertIdsAscendingFromOne(_ ids: [Int], pack: String,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ids, Array(1...max(ids.count, 1)),
                       "\(pack): ids must be unique and ascending from 1", file: file, line: line)
    }

    private func assertNonEmpty(_ text: LText, context: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.de.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "\(context): empty German string", file: file, line: line)
        XCTAssertFalse(text.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "\(context): empty English string", file: file, line: line)
    }

    // MARK: - Ids unique & ascending from 1

    func testAllPackIdsUniqueAndAscendingFromOne() {
        assertIdsAscendingFromOne(ContentPack.dailyQuestions.map(\.id), pack: "dailyQuestions")
        assertIdsAscendingFromOne(ContentPack.quizQuestions.map(\.id), pack: "quizQuestions")
        assertIdsAscendingFromOne(ContentPack.thisOrThat.map(\.id), pack: "thisOrThat")
        assertIdsAscendingFromOne(ContentPack.wouldYouRather.map(\.id), pack: "wouldYouRather")
        assertIdsAscendingFromOne(ContentPack.truthOrDare.map(\.id), pack: "truthOrDare")
        assertIdsAscendingFromOne(ContentPack.questions36.map(\.id), pack: "questions36")
        assertIdsAscendingFromOne(ContentPack.dateIdeas.map(\.id), pack: "dateIdeas")
    }

    // MARK: - Counts

    func testDailyQuestionsCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.dailyQuestions.count, 180)
    }

    func testQuizQuestionsCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.quizQuestions.count, 110)
    }

    func testThisOrThatCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.thisOrThat.count, 110)
    }

    func testWouldYouRatherCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.wouldYouRather.count, 90)
    }

    func testTruthOrDareCountsAndSpice() {
        let truths = ContentPack.truthOrDare.filter { !$0.isDare }
        let dares = ContentPack.truthOrDare.filter { $0.isDare }
        XCTAssertGreaterThanOrEqual(truths.count, 55, "need at least 55 truths")
        XCTAssertGreaterThanOrEqual(dares.count, 55, "need at least 55 dares")
        for item in ContentPack.truthOrDare {
            XCTAssertTrue((1...3).contains(item.spice),
                          "truthOrDare id \(item.id): spice \(item.spice) out of 1…3")
        }
    }

    func testQuestions36ExactlyThirtySixWithSetMapping() {
        let items = ContentPack.questions36
        XCTAssertEqual(items.count, 36, "must be exactly the classic 36 questions")
        for q in items {
            let expectedSet = (q.id - 1) / 12 + 1 // 1–12 → 1, 13–24 → 2, 25–36 → 3
            XCTAssertEqual(q.set, expectedSet, "questions36 id \(q.id): set \(q.set), expected \(expectedSet)")
        }
    }

    func testDateIdeasCountBudgetAndTags() {
        let allowedTags: Set<String> = ["cozy", "adventure", "creative", "food", "outdoor",
                                        "romantic", "silly", "longdistance", "athome", "night"]
        let ideas = ContentPack.dateIdeas
        XCTAssertGreaterThanOrEqual(ideas.count, 110)
        for idea in ideas {
            XCTAssertTrue((0...3).contains(idea.budget),
                          "dateIdeas id \(idea.id): budget \(idea.budget) out of 0…3")
            XCTAssertTrue((1...3).contains(idea.tags.count),
                          "dateIdeas id \(idea.id): \(idea.tags.count) tags, expected 1…3")
            for tag in idea.tags {
                XCTAssertTrue(allowedTags.contains(tag),
                              "dateIdeas id \(idea.id): unknown tag \"\(tag)\"")
            }
            XCTAssertEqual(Set(idea.tags).count, idea.tags.count,
                           "dateIdeas id \(idea.id): duplicate tags")
        }
        let longDistance = ideas.filter { $0.tags.contains("longdistance") }
        XCTAssertGreaterThanOrEqual(longDistance.count, 15,
                                    "need at least 15 long-distance date ideas")
    }

    // MARK: - Text content

    func testQuizQuestionsContainPartnerPlaceholderInBothLanguages() {
        for q in ContentPack.quizQuestions {
            XCTAssertTrue(q.text.de.contains("{partner}"),
                          "quizQuestions id \(q.id): German text missing {partner}")
            XCTAssertTrue(q.text.en.contains("{partner}"),
                          "quizQuestions id \(q.id): English text missing {partner}")
        }
    }

    func testNoEmptyStringsAnywhere() {
        for q in ContentPack.dailyQuestions { assertNonEmpty(q.text, context: "dailyQuestions id \(q.id)") }
        for q in ContentPack.quizQuestions { assertNonEmpty(q.text, context: "quizQuestions id \(q.id)") }
        for p in ContentPack.thisOrThat {
            assertNonEmpty(p.a, context: "thisOrThat id \(p.id) option a")
            assertNonEmpty(p.b, context: "thisOrThat id \(p.id) option b")
        }
        for p in ContentPack.wouldYouRather {
            assertNonEmpty(p.a, context: "wouldYouRather id \(p.id) option a")
            assertNonEmpty(p.b, context: "wouldYouRather id \(p.id) option b")
        }
        for t in ContentPack.truthOrDare { assertNonEmpty(t.text, context: "truthOrDare id \(t.id)") }
        for q in ContentPack.questions36 { assertNonEmpty(q.text, context: "questions36 id \(q.id)") }
        for d in ContentPack.dateIdeas {
            assertNonEmpty(d.title, context: "dateIdeas id \(d.id) title")
            assertNonEmpty(d.details, context: "dateIdeas id \(d.id) details")
            XCTAssertFalse(d.emoji.isEmpty, "dateIdeas id \(d.id): empty emoji")
        }
    }

    // MARK: - dailyQuestion(dateKey:coupleId:)

    func testDailyQuestionIsDeterministic() {
        let samples: [(dateKey: String, coupleId: String)] = [
            ("2024-01-15", "couple-abc123"),
            ("2025-07-31", "couple-xyz789"),
            ("2026-12-24", "c0ffee00-dead-beef")
        ]
        for sample in samples {
            let first = ContentPack.dailyQuestion(dateKey: sample.dateKey, coupleId: sample.coupleId)
            let second = ContentPack.dailyQuestion(dateKey: sample.dateKey, coupleId: sample.coupleId)
            XCTAssertEqual(first.id, second.id,
                           "same date \(sample.dateKey) + couple \(sample.coupleId) must give the same question")
        }
    }

    func testDifferentCouplesGetDifferentQuestionsOnSomeDay() {
        let coupleA = "couple-aaaa-1111"
        let coupleB = "couple-bbbb-2222"
        let dates = (1...10).map { String(format: "2025-03-%02d", $0) }
        let differs = dates.contains { date in
            ContentPack.dailyQuestion(dateKey: date, coupleId: coupleA).id
                != ContentPack.dailyQuestion(dateKey: date, coupleId: coupleB).id
        }
        XCTAssertTrue(differs,
                      "two different couples should get different questions on at least one of 10 days")
    }
}
