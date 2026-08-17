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

    /// "YYYY-MM-DD" keys for `count` consecutive days starting at `start`.
    private func dateKeys(from start: String, count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = start.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let startDate = calendar.date(from: components) else { return [] }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
    }

    // MARK: - Counts

    func testDailyQuestionsCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.dailyQuestions.count, 510,
                                    "expansion target: 510+ daily questions (cycle covers > 1 year)")
    }

    func testDailyQuestionDepthTagsAreCurated() {
        let pool = ContentPack.dailyQuestions
        let light = pool.filter { $0.depth == .light }.count
        let close = pool.filter { $0.depth == .close }.count
        let deep = pool.filter { $0.depth == .deep }.count
        XCTAssertEqual(light + close + deep, pool.count)
        XCTAssertGreaterThanOrEqual(light, 150, "need a broad base of light questions")
        XCTAssertGreaterThanOrEqual(close, 170, "need a broad base of close questions")
        XCTAssertGreaterThanOrEqual(deep, 70, "need enough deep questions to matter")
        XCTAssertLessThan(deep * 3, pool.count,
                          "deep questions must stay under a third of the pool so the depth guard always finds a lighter swap")
    }

    func testQuizQuestionsCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.quizQuestions.count, 155)
    }

    func testThisOrThatCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.thisOrThat.count, 200)
    }

    func testWouldYouRatherCount() {
        XCTAssertGreaterThanOrEqual(ContentPack.wouldYouRather.count, 160)
    }

    func testTruthOrDareCountsAndSpice() {
        let truths = ContentPack.truthOrDare.filter { !$0.isDare }
        let dares = ContentPack.truthOrDare.filter { $0.isDare }
        XCTAssertGreaterThanOrEqual(truths.count, 65, "need at least 65 truths")
        XCTAssertGreaterThanOrEqual(dares.count, 65, "need at least 65 dares")
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
        XCTAssertGreaterThanOrEqual(ideas.count, 280,
                                    "expansion target: 280+ ideas incl. the under-served-realities block")
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
        XCTAssertGreaterThanOrEqual(longDistance.count, 35,
                                    "need at least 35 long-distance date ideas")
        let quick = ideas.filter { $0.energy == .quick }
        XCTAssertGreaterThanOrEqual(quick.count, 45,
                                    "need at least 45 quick ideas for exhausted ≤ 20-minute evenings")
        let freeAtHome = ideas.filter { $0.tags.contains("athome") && $0.budget == 0 }
        XCTAssertGreaterThanOrEqual(freeAtHome.count, 60,
                                    "need at least 60 zero-budget at-home ideas")
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

    // MARK: - No duplicate texts within a pack (both languages)

    /// Asserts every string appears only once. `context` names the pack + field.
    private func assertUnique(_ values: [(id: Int, value: String)], context: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        var seen: [String: Int] = [:]
        for (id, value) in values {
            if let firstId = seen[value] {
                XCTFail("\(context): duplicate \"\(value)\" (ids \(firstId) and \(id))",
                        file: file, line: line)
            } else {
                seen[value] = id
            }
        }
    }

    func testNoDuplicateTextsWithinPacks() {
        assertUnique(ContentPack.dailyQuestions.map { ($0.id, $0.text.de) }, context: "dailyQuestions.de")
        assertUnique(ContentPack.dailyQuestions.map { ($0.id, $0.text.en) }, context: "dailyQuestions.en")
        assertUnique(ContentPack.quizQuestions.map { ($0.id, $0.text.de) }, context: "quizQuestions.de")
        assertUnique(ContentPack.quizQuestions.map { ($0.id, $0.text.en) }, context: "quizQuestions.en")
        assertUnique(ContentPack.truthOrDare.map { ($0.id, $0.text.de) }, context: "truthOrDare.de")
        assertUnique(ContentPack.truthOrDare.map { ($0.id, $0.text.en) }, context: "truthOrDare.en")
        // Choice packs: the (a, b) combination must be unique per language.
        assertUnique(ContentPack.thisOrThat.map { ($0.id, "\($0.a.de)|\($0.b.de)") }, context: "thisOrThat pair.de")
        assertUnique(ContentPack.thisOrThat.map { ($0.id, "\($0.a.en)|\($0.b.en)") }, context: "thisOrThat pair.en")
        assertUnique(ContentPack.wouldYouRather.map { ($0.id, "\($0.a.de)|\($0.b.de)") }, context: "wouldYouRather pair.de")
        assertUnique(ContentPack.wouldYouRather.map { ($0.id, "\($0.a.en)|\($0.b.en)") }, context: "wouldYouRather pair.en")
        // Date ideas advertise unique titles in both languages.
        assertUnique(ContentPack.dateIdeas.map { ($0.id, $0.title.de) }, context: "dateIdeas title.de")
        assertUnique(ContentPack.dateIdeas.map { ($0.id, $0.title.en) }, context: "dateIdeas title.en")
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

    // MARK: - Repeat-free cycle, growth stability, depth stratification

    func testDailyQuestionCycleIsAPermutationOfThePool() {
        for coupleId in ["cp-perm-1", "cp-perm-2", "d0d0-4242"] {
            let cycle = ContentPack.dailyQuestionCycle(coupleId: coupleId)
            XCTAssertEqual(cycle.count, ContentPack.dailyQuestions.count)
            XCTAssertEqual(Set(cycle), Set(0..<ContentPack.dailyQuestions.count),
                           "cycle must contain every pool index exactly once")
        }
    }

    func testDailyQuestionIsRepeatFreeOverAFullPoolPass() {
        let poolSize = ContentPack.dailyQuestions.count
        // A full pass crossing a year boundary and a (2028) leap day.
        let days = dateKeys(from: "2027-11-20", count: poolSize + 1)
        XCTAssertEqual(days.count, poolSize + 1)
        let ids = days.map { ContentPack.dailyQuestion(dateKey: $0, coupleId: "cp-cycle-365").id }
        XCTAssertEqual(Set(ids.prefix(poolSize)).count, poolSize,
                       "no question may repeat before the whole pool was seen (\(poolSize) days)")
        XCTAssertEqual(ids[poolSize], ids[0],
                       "after a full pass the cycle wraps to the same start position")
    }

    func testDailyQuestionCycleOrderIsStableWhenPoolGrows() {
        for coupleKey in ["dailyq|cp-a", "dailyq|cp-b", "quests|cp-c"] {
            let before = ContentCycle.order(poolSize: 290, coupleKey: coupleKey)
            let after = ContentCycle.order(poolSize: 410, coupleKey: coupleKey)
            XCTAssertEqual(after.filter { $0 < 290 }, before,
                           "growing the pool must keep every existing card in the same relative order")
        }
    }

    func testDailyQuestionCycleNeverServesThreeDeepQuestionsInARow() {
        let pool = ContentPack.dailyQuestions
        for coupleId in ["cp-strat-1", "cp-strat-2", "cp-strat-3", "afafaf-99"] {
            let cycle = ContentPack.dailyQuestionCycle(coupleId: coupleId, pool: pool)
            let count = cycle.count
            // + 2 checks the wrap-around windows too.
            for start in 0..<count {
                let window = (0..<3).map { pool[cycle[(start + $0) % count]].depth }
                XCTAssertFalse(window.allSatisfy { $0 == .deep },
                               "couple \(coupleId): three deep questions on days \(start)…\(start + 2)")
            }
        }
    }

    // MARK: - Recents buffer: no replays around pool-growth releases

    /// Synthetic pool so the growth scenario is exact (real pool sizes drift).
    private func syntheticPool(count: Int) -> [DailyQuestion] {
        (1...count).map { DailyQuestion(id: $0, text: LText(de: "Frage \($0)", en: "Question \($0)")) }
    }

    func testDailyQuestionSkipsIdsServedWithinTheRecentsWindow() {
        let pool = syntheticPool(count: 430)
        let dateKey = "2026-09-01"
        let coupleId = "cp-recents-skip"
        let day = ContentCycle.dayNumber(of: dateKey)!
        let natural = ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                pool: pool, recent: [])
        // Served yesterday → today must resolve to a different question.
        let skipped = ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                pool: pool,
                                                recent: [(day: day - 1, id: natural.id)])
        XCTAssertNotEqual(skipped.id, natural.id,
                          "a question served yesterday must not be replayed today")
        // Served outside the window (or later) → the natural pick stands, so
        // ordinary days keep both partners' derivations identical.
        let outside = ContentPack.dailyQuestion(
            dateKey: dateKey, coupleId: coupleId, pool: pool,
            recent: [(day: day - DailyQuestionRecents.window - 1, id: natural.id),
                     (day: day + 3, id: natural.id)])
        XCTAssertEqual(outside.id, natural.id,
                       "only serves within the window before the day may block the natural pick")
    }

    func testPoolGrowthFrom410To430NeverReplaysWithinThirtyDays() {
        let smallPool = syntheticPool(count: 410)
        let grownPool = syntheticPool(count: 430)
        // 30 days on the old pool, release, 30 days on the grown pool — the
        // recents list is maintained exactly like the UserDefaults store.
        let days = dateKeys(from: "2026-08-01", count: 60)
        for coupleId in ["cp-grow-1", "cp-grow-2", "cp-grow-3", "cp-grow-4"] {
            var recent: [(day: Int, id: Int)] = []
            var served: [(day: Int, id: Int)] = []
            for (index, dateKey) in days.enumerated() {
                let pool = index < 30 ? smallPool : grownPool
                let day = ContentCycle.dayNumber(of: dateKey)!
                let question = ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                         pool: pool, recent: recent)
                served.append((day, question.id))
                recent.append((day, question.id))
                if recent.count > DailyQuestionRecents.window {
                    recent.removeFirst(recent.count - DailyQuestionRecents.window)
                }
            }
            for (index, current) in served.enumerated() {
                for previous in served[..<index]
                where current.day - previous.day <= DailyQuestionRecents.window {
                    XCTAssertNotEqual(current.id, previous.id,
                                      "couple \(coupleId): question \(current.id) replayed on day "
                                      + "\(current.day) only \(current.day - previous.day) days after its last serve")
                }
            }
        }
    }

    // MARK: - Pair-authoritative pin (FXD-1 Fund 3)

    func testPinnedEntryQuestionWinsOverAsymmetricDeviceRecents() {
        // EVAL repro (two devices): the recents buffer is device-local, so
        // around a pool-growth release the couple's devices can derive
        // DIFFERENT questions for the same day — the growth shifts today's
        // cycle position, and only the long-lived device remembers that
        // the new natural pick was just seen (the fresh partner install
        // has an empty buffer). Constructed exactly: the long-lived device
        // saw today's natural pick three days ago, so its derivation skips
        // while the fresh device serves it.
        let pool = syntheticPool(count: 430)
        let coupleId = "cp-pin-asym"
        let dateKey = "2026-09-01"
        let day = ContentCycle.dayNumber(of: dateKey)!

        let freshDevice = ContentPack.dailyQuestion(
            dateKey: dateKey, coupleId: coupleId, pool: pool, recent: [])
        let longLivedDevice = ContentPack.dailyQuestion(
            dateKey: dateKey, coupleId: coupleId, pool: pool,
            recent: [(day: day - 3, id: freshDevice.id)])
        XCTAssertNotEqual(freshDevice.id, longLivedDevice.id,
                          "repro precondition: asymmetric recents diverge the derivations")

        // The server pinned the day with the FIRST answer (say the
        // long-lived device answered first) → the pin resolves to exactly
        // that question, on BOTH devices, regardless of local recents.
        let pinnedId = longLivedDevice.id
        XCTAssertEqual(ContentPack.pinnedDailyQuestion(pinnedId, pool: pool)?.id,
                       pinnedId,
                       "an entry with questionId must resolve the pinned question everywhere")
    }

    func testPinnedQuestionResolvesOnlyIdsTheBundledPoolKnows() {
        let pool = syntheticPool(count: 410)
        // No entry yet → no pin: the derivation stays the proposal.
        XCTAssertNil(ContentPack.pinnedDailyQuestion(nil, pool: pool))
        // A pinned pool question resolves to exactly that question.
        XCTAssertEqual(ContentPack.pinnedDailyQuestion(322, pool: pool)?.id, 322)
        // An id from a NEWER pool (partner updated first) cannot resolve —
        // the caller falls back to the derivation instead of a blank card.
        XCTAssertNil(ContentPack.pinnedDailyQuestion(9_999, pool: pool))
    }

    func testUnknownPinWithServerTextRendersTheStoredQuestion() {
        // Schlussrunde 5 (mixed-version lockout): the server refuses every
        // answer that diverges from the pin — a client that doesn't KNOW
        // the pinned id must therefore render the server-stored text
        // instead of deriving a question it can never submit.
        let pool = syntheticPool(count: 410)
        let serverText = LText(de: "Was war heute schön?", en: "What was lovely today?")
        let resolved = ContentPack.pinnedDailyQuestion(9_999, pinnedText: serverText,
                                                       pool: pool)
        XCTAssertEqual(resolved?.id, 9_999,
                       "the answer must be filed under the PINNED id")
        XCTAssertEqual(resolved?.text, serverText)
    }

    func testUnknownPinWithoutServerTextKeepsTheDerivationFallback() {
        // Entries pinned by old clients carry no text — the previous
        // behavior (fall back to the local derivation) stays.
        let pool = syntheticPool(count: 410)
        XCTAssertNil(ContentPack.pinnedDailyQuestion(9_999, pinnedText: nil, pool: pool))
    }

    func testKnownPinPrefersThePoolTextOverTheServerText() {
        // The bundled pool carries depth tags and copy fixes — when this
        // build knows the pinned id, its own text wins over the (possibly
        // older) server-stored snapshot.
        let pool = syntheticPool(count: 410)
        let staleServerText = LText(de: "Alte Formulierung", en: "Old wording")
        let resolved = ContentPack.pinnedDailyQuestion(322, pinnedText: staleServerText,
                                                       pool: pool)
        XCTAssertEqual(resolved?.id, 322)
        XCTAssertEqual(resolved?.text, pool[321].text,
                       "the pool text wins; the server text is only the fallback")
    }

    func testDailyQuestionConvenienceHonorsThePinOverTheLocalDerivation() {
        // The card-facing resolver: an entry pin overrides the device's
        // own derivation; without a resolvable pin the derivation stays.
        let coupleId = "cp-pin-convenience"
        let dateKey = "2026-09-01"
        let derived = ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId)
        let pinned = ContentPack.dailyQuestions.first { $0.id != derived.id }!
        XCTAssertEqual(ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                 pinnedId: pinned.id).id,
                       pinned.id,
                       "the server-pinned question must win over the local derivation")
        // Unknown pin (the entry was written by a newer build with a
        // bigger pool) → fall back to the derivation, never a blank card.
        let unknownId = (ContentPack.dailyQuestions.map(\.id).max() ?? 0) + 1
        XCTAssertEqual(ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                 pinnedId: unknownId).id,
                       derived.id)
        // No entry → the derivation is still only the local proposal.
        XCTAssertEqual(ContentPack.dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                                 pinnedId: nil).id,
                       derived.id)
    }

    // MARK: - Energy tags

    func testDateIdeaEnergyTagsMatchTheQuickDefinition() {
        let byId = Dictionary(uniqueKeysWithValues: ContentPack.dateIdeas.map { ($0.id, $0) })
        // Regression (FXC-3): all-day or meal-length ideas must not claim to
        // fit into ≤ 20 exhausted minutes.
        XCTAssertEqual(byId[137]?.energy, .normal,
                       "split-shift dinner date is a meal-length call, not a quick idea")
        XCTAssertEqual(byId[216]?.energy, .normal,
                       "a photo every waking hour plus a film night is an all-day relay")
    }

    func testDayNumberMatchesCalendarAcrossBounds() {
        // Consecutive keys (incl. month, year and 2028-02-29 leap bounds) must
        // yield consecutive day numbers — this is what steps the cycle daily.
        let days = dateKeys(from: "2027-12-28", count: 70)
        let numbers = days.compactMap { ContentCycle.dayNumber(of: $0) }
        XCTAssertEqual(numbers.count, days.count)
        for i in 1..<numbers.count {
            XCTAssertEqual(numbers[i], numbers[i - 1] + 1,
                           "\(days[i - 1]) → \(days[i]) must advance the day number by exactly 1")
        }
        XCTAssertEqual(ContentCycle.dayNumber(of: "1970-01-01"), 0)
        XCTAssertNil(ContentCycle.dayNumber(of: "kaputt"))
        XCTAssertNil(ContentCycle.dayNumber(of: "2026-13-01"))
    }
}
