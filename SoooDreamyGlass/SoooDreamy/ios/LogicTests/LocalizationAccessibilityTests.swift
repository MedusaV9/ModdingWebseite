import XCTest
@testable import SoooDreamyLogic

final class LocalizationAccessibilityTests: XCTestCase {
    func testFormattersHonorInAppLanguageIndependently() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: zone, year: 2026, month: 8, day: 11, hour: 17, minute: 5
        )))

        let deDate = AppFormatters.date(date, language: "de", timeZone: zone)
        let enDate = AppFormatters.date(date, language: "en", timeZone: zone)
        XCTAssertNotEqual(deDate, enDate)
        XCTAssertTrue(deDate.contains("2026"))
        XCTAssertTrue(enDate.contains("2026"))

        XCTAssertEqual(AppFormatters.integer(12_345, language: "de"), "12.345")
        XCTAssertEqual(AppFormatters.integer(12_345, language: "en"), "12,345")
        XCTAssertEqual(AppFormatters.decimal(1_234.5, language: "de"), "1.234,5")
        XCTAssertEqual(AppFormatters.decimal(1_234.5, language: "en"), "1,234.5")
        XCTAssertEqual(AppFormatters.duration(minutes: 95, language: "de"), "1 Std. 35 Min.")
        XCTAssertEqual(AppFormatters.duration(minutes: 95, language: "en"), "1 hr 35 min")
    }

    func testFormatterCacheReturnsIdenticalInstancePerKey() throws {
        // The static cache must hand out the SAME instance for the same
        // (language, style/template, time zone) key — and different
        // instances as soon as any key component differs.
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let berlin = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))

        let a = AppFormatters.dateFormatter(language: "de", dateStyle: .medium,
                                            timeStyle: .none, timeZone: utc)
        let b = AppFormatters.dateFormatter(language: "de", dateStyle: .medium,
                                            timeStyle: .none, timeZone: utc)
        XCTAssertTrue(a === b, "same key must be a cache hit (identical instance)")
        XCTAssertFalse(a === AppFormatters.dateFormatter(
            language: "en", dateStyle: .medium, timeStyle: .none, timeZone: utc))
        XCTAssertFalse(a === AppFormatters.dateFormatter(
            language: "de", dateStyle: .long, timeStyle: .none, timeZone: utc))
        XCTAssertFalse(a === AppFormatters.dateFormatter(
            language: "de", dateStyle: .medium, timeStyle: .none, timeZone: berlin))

        let t1 = AppFormatters.templateDateFormatter(language: "de",
                                                     template: "LLLL yyyy", timeZone: utc)
        let t2 = AppFormatters.templateDateFormatter(language: "de",
                                                     template: "LLLL yyyy", timeZone: utc)
        XCTAssertTrue(t1 === t2)
        XCTAssertFalse(t1 === AppFormatters.templateDateFormatter(
            language: "de", template: "d MMM", timeZone: utc))

        let n1 = AppFormatters.numberFormatter(language: "en", maximumFractionDigits: 2)
        let n2 = AppFormatters.numberFormatter(language: "en", maximumFractionDigits: 2)
        XCTAssertTrue(n1 === n2)
        XCTAssertFalse(n1 === AppFormatters.numberFormatter(language: "en",
                                                            maximumFractionDigits: 0))

        // Cached instances must still format correctly on repeat use.
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: utc, year: 2026, month: 8, day: 11, hour: 17, minute: 5
        )))
        XCTAssertEqual(AppFormatters.date(date, language: "de", timeZone: utc),
                       AppFormatters.date(date, language: "de", timeZone: utc))
        XCTAssertEqual(AppFormatters.integer(7_654, language: "de"), "7.654")
        XCTAssertEqual(AppFormatters.integer(7_654, language: "de"), "7.654")
    }

    func testPluralSelectionUsesOneAndOtherForms() {
        let original = L10n.language
        defer { L10n.language = original }

        L10n.language = .de
        XCTAssertEqual(L10n.t("count.entries", count: 1), "ein Eintrag")
        XCTAssertEqual(L10n.t("count.entries", count: 1_200), "1.200 Einträge")

        L10n.language = .en
        XCTAssertEqual(L10n.t("count.entries", count: 1), "one entry")
        XCTAssertEqual(L10n.t("count.entries", count: 1_200), "1,200 entries")
        XCTAssertEqual(L10n.t("tab.chat.unreadA11y", count: 2),
                       "Writing Desk, 2 unread messages")
    }

    func testBundledHandbookParserKeepsStableDeepLinkAnchors() {
        let markdown = """
        Intro outside sections.
        <!-- anchor:home -->
        # Home
        Dashboard help.
        <!-- anchor:chat -->
        # Chat
        Composer help.
        """
        XCTAssertEqual(
            HandbookDocument.parse(markdown),
            [
                HandbookSection(id: "home", markdown: "# Home\nDashboard help."),
                HandbookSection(id: "chat", markdown: "# Chat\nComposer help."),
            ]
        )
    }
}
