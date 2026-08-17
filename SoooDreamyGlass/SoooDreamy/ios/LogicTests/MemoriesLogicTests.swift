import XCTest
@testable import SoooDreamyLogic

/// v8.0 „Erinnerungen": the month math MUST match server/src/memories.js —
/// the fixtures here mirror server/test/memories.test.js exactly.
final class MemoriesLogicTests: XCTestCase {

    func testMonthsBackSameDayMatchesServerFixtures() {
        XCTAssertEqual(MemoriesLogic.monthsBackSameDay(past: "2026-07-13", now: "2026-08-13"), 1)
        XCTAssertEqual(MemoriesLogic.monthsBackSameDay(past: "2025-08-13", now: "2026-08-13"), 12)
        XCTAssertNil(MemoriesLogic.monthsBackSameDay(past: "2024-02-29", now: "2026-08-13"))
        XCTAssertEqual(MemoriesLogic.monthsBackSameDay(past: "2024-02-29", now: "2028-02-29"), 48)
        XCTAssertNil(MemoriesLogic.monthsBackSameDay(past: "2026-08-13", now: "2026-08-13"))
        XCTAssertNil(MemoriesLogic.monthsBackSameDay(past: "2026-09-13", now: "2026-08-13"))
        // Jan 31 → there IS no Feb 31: honest gap instead of fuzzy matching.
        XCTAssertNil(MemoriesLogic.monthsBackSameDay(past: "2026-01-31", now: "2026-02-28"))
        XCTAssertEqual(MemoriesLogic.monthsBackSameDay(past: "2026-01-31", now: "2026-03-31"), 2)
        XCTAssertNil(MemoriesLogic.monthsBackSameDay(past: "garbage", now: "2026-08-13"))
    }

    func testDistanceCollapsesWholeYears() {
        XCTAssertEqual(MemoriesLogic.distance(fromMonths: 1),
                       MemoriesLogic.Distance(unit: "months", n: 1))
        XCTAssertEqual(MemoriesLogic.distance(fromMonths: 11),
                       MemoriesLogic.Distance(unit: "months", n: 11))
        XCTAssertEqual(MemoriesLogic.distance(fromMonths: 12),
                       MemoriesLogic.Distance(unit: "years", n: 1))
        XCTAssertEqual(MemoriesLogic.distance(fromMonths: 30),
                       MemoriesLogic.Distance(unit: "months", n: 30))
        XCTAssertEqual(MemoriesLogic.distance(fromMonths: 24),
                       MemoriesLogic.Distance(unit: "years", n: 2))
    }

    func testAgoLabelKeysCoverSingularAndPlural() {
        XCTAssertEqual(MemoriesLogic.agoLabelKey(unit: "months", n: 1), "memories.ago.month")
        XCTAssertEqual(MemoriesLogic.agoLabelKey(unit: "months", n: 3), "memories.ago.months")
        XCTAssertEqual(MemoriesLogic.agoLabelKey(unit: "years", n: 1), "memories.ago.year")
        XCTAssertEqual(MemoriesLogic.agoLabelKey(unit: "years", n: 5), "memories.ago.years")
        for key in ["memories.ago.month", "memories.ago.months",
                    "memories.ago.year", "memories.ago.years"] {
            XCTAssertNotNil(MemoriesL10n.table[key], "\(key) missing from MemoriesL10n")
        }
    }

    func testMonthiversaryLabelKeysCoverSingularAndPlural() {
        XCTAssertEqual(MemoriesLogic.monthiversaryLabelKey(unit: "months", n: 1),
                       "onthisday.monthiversary.month")
        XCTAssertEqual(MemoriesLogic.monthiversaryLabelKey(unit: "months", n: 7),
                       "onthisday.monthiversary.months")
        XCTAssertEqual(MemoriesLogic.monthiversaryLabelKey(unit: "years", n: 1),
                       "onthisday.monthiversary.year")
        XCTAssertEqual(MemoriesLogic.monthiversaryLabelKey(unit: "years", n: 2),
                       "onthisday.monthiversary.years")
        for key in ["onthisday.monthiversary.month", "onthisday.monthiversary.months",
                    "onthisday.monthiversary.year", "onthisday.monthiversary.years",
                    "onthisday.dismiss", "onthisday.pill"] {
            XCTAssertNotNil(MemoriesL10n.table[key], "\(key) missing from MemoriesL10n")
        }
    }

    func testEveryStoryKindHasLocalizedTitleInBothLanguages() {
        for (kind, spec) in MemoriesLogic.storyKinds {
            guard let text = MemoriesL10n.table[spec.titleKey] else {
                XCTFail("story kind \(kind): \(spec.titleKey) missing from MemoriesL10n")
                continue
            }
            XCTAssertFalse(text.de.isEmpty, kind)
            XCTAssertFalse(text.en.isEmpty, kind)
            XCTAssertFalse(spec.emoji.isEmpty, kind)
        }
        // Unknown future kinds degrade to the generic memory row.
        let unknown = MemoriesLogic.presentation(forKind: "hologram_dance")
        XCTAssertEqual(unknown.titleKey, "story.kind.unknown")
        XCTAssertNotNil(MemoriesL10n.table["story.kind.unknown"])
    }

    func testChaptersAreNewestFirstAndDeduplicated() {
        let keys = ["2025-12-30", "2026-01-05", "2026-01-20", "2026-03-01"]
        XCTAssertEqual(MemoriesLogic.chapters(entryDateKeys: keys),
                       ["2026-03", "2026-01", "2025-12"])
        XCTAssertEqual(MemoriesLogic.monthKey(of: "2026-08-13"), "2026-08")
        XCTAssertEqual(MemoriesLogic.chapters(entryDateKeys: []), [])
    }

    // MARK: - gallery month sections

    private func utcDate(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testGalleryMonthGroupsKeepOrderAndSplitOnMonths() {
        let utc = TimeZone(identifier: "UTC")!
        let groups = MemoriesLogic.galleryMonthGroups(photos: [
            ("d", utcDate("2026-08-13T10:00:00Z")),
            ("c", utcDate("2026-08-01T09:00:00Z")),
            ("b", utcDate("2026-07-31T22:00:00Z")),
            ("a", utcDate("2025-12-24T18:00:00Z"))
        ], timeZone: utc)
        XCTAssertEqual(groups, [
            MemoriesLogic.GalleryMonthGroup(monthKey: "2026-08", photoIds: ["d", "c"]),
            MemoriesLogic.GalleryMonthGroup(monthKey: "2026-07", photoIds: ["b"]),
            MemoriesLogic.GalleryMonthGroup(monthKey: "2025-12", photoIds: ["a"])
        ])
        XCTAssertEqual(MemoriesLogic.galleryMonthGroups(photos: [], timeZone: utc), [])
    }

    /// A photo taken 23:30 on Jul 31 in Berlin is an AUGUST photo for the
    /// couple even though UTC still says July — grouping must follow the
    /// wall clock, not the server clock.
    func testGalleryMonthGroupsUseWallClockTimeZone() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let groups = MemoriesLogic.galleryMonthGroups(photos: [
            ("late", utcDate("2026-07-31T22:30:00Z"))
        ], timeZone: berlin)
        XCTAssertEqual(groups.map(\.monthKey), ["2026-08"])
    }
}
