import XCTest
@testable import SoooDreamyLogic

/// Tests for the in-app localization engine (`L10n`) and all string tables
/// (CoreStrings + ChatL10n + GamesL10n + MemoriesL10n).
final class L10nTests: XCTestCase {

    /// All tables with names, mirroring `L10n.tables` (which is private).
    private let namedTables: [(name: String, table: [String: LText])] = [
        ("CoreStrings", CoreStrings.table),
        ("ChatL10n", ChatL10n.table),
        ("GamesL10n", GamesL10n.table),
        ("MemoriesL10n", MemoriesL10n.table)
    ]

    func testAllTableValuesNonEmptyInBothLanguages() {
        for (name, table) in namedTables {
            for (key, value) in table {
                XCTAssertFalse(value.de.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(name)[\"\(key)\"]: empty German string")
                XCTAssertFalse(value.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "\(name)[\"\(key)\"]: empty English string")
            }
        }
    }

    func testUnknownKeyReturnsKeyItself() {
        let bogus = "definitely.not.a.real.key.42"
        XCTAssertEqual(L10n.t(bogus), bogus)
    }

    func testResolutionAndPlaceholderReplacement() {
        // Note: setting L10n.language persists to UserDefaults (a plist in the
        // temp home on Linux) and to SharedStore — this must not crash.
        let original = L10n.language
        defer { L10n.language = original }

        // "home.moodOf" contains {name} in BOTH languages:
        // de "{name} fühlt sich…" / en "{name} is feeling…"
        L10n.language = .de
        XCTAssertEqual(L10n.lang, "de")
        XCTAssertTrue(L10n.isGerman)
        XCTAssertEqual(L10n.t("home.moodOf", ["name": "Mia"]), "Mia fühlt sich…")

        L10n.language = .en
        XCTAssertEqual(L10n.lang, "en")
        XCTAssertFalse(L10n.isGerman)
        XCTAssertEqual(L10n.t("home.moodOf", ["name": "Mia"]), "Mia is feeling…")
    }

    func testPlaceholderReplacementLeavesUnrelatedPlaceholdersAlone() {
        let original = L10n.language
        defer { L10n.language = original }
        L10n.language = .en
        // "server.testOK" has {name} and {version}; only {name} is provided here.
        XCTAssertEqual(L10n.t("server.testOK", ["name": "Home"]), "Connected! Home ({version})")
    }

    func testRelativeShortFormatsInAppLanguage() {
        let original = L10n.language
        defer { L10n.language = original }
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        L10n.language = .de
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-30), now: now), "gerade eben")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-5 * 60), now: now), "vor 5 Min.")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-3 * 3600), now: now), "vor 3 Std.")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-30 * 3600), now: now), "gestern")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-4 * 86400), now: now), "vor 4 Tagen")

        L10n.language = .en
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-5 * 60), now: now), "5 min ago")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-3 * 3600), now: now), "3 h ago")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-30 * 3600), now: now), "yesterday")
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(-4 * 86400), now: now), "4 days ago")

        // Future dates (clock skew) degrade gracefully to "just now".
        XCTAssertEqual(L10n.relativeShort(now.addingTimeInterval(120), now: now), "just now")
    }

    func testNoDuplicateKeysAcrossTables() {
        // A key present in two tables would silently shadow (first table wins).
        for i in 0..<namedTables.count {
            for j in (i + 1)..<namedTables.count {
                let overlap = Set(namedTables[i].table.keys).intersection(namedTables[j].table.keys)
                XCTAssertTrue(overlap.isEmpty,
                              "keys defined in both \(namedTables[i].name) and \(namedTables[j].name): \(overlap.sorted())")
            }
        }
    }
}
