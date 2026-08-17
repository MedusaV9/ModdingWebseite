import XCTest
@testable import SoooDreamyLogic

/// Tests for the in-app localization engine (`L10n`) and every table wired
/// into the runtime resolver.
final class L10nTests: XCTestCase {

    /// All tables with names, mirroring `L10n.tables` (which is private).
    private let namedTables: [(name: String, table: [String: LText])] = [
        ("CoreStrings", CoreStrings.table),
        ("ChatL10n", ChatL10n.table),
        ("GamesL10n", GamesL10n.table),
        ("MemoriesL10n", MemoriesL10n.table),
        ("OnboardingL10n", OnboardingL10n.table),
        ("RitualsL10n", RitualsL10n.table),
        ("PlatformL10n", PlatformL10n.table),
        ("IntelligenceL10n", IntelligenceL10n.table),
        ("SettingsL10n", SettingsL10n.table),
        ("PostfachL10n", PostfachL10n.table)
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

    func testGuideClosingStepNamesAllFiveStations() {
        // Guide-Eval S3: the closing guide step walks the WHOLE
        // Nachtpostamt — all five stations by name, in both languages
        // (the canonical names of the tab vocabulary). The route steps
        // live in OnboardingL10n since Fix-Runde 3 (Kino-Befund 3).
        guard let step = OnboardingL10n.table["onboarding.page.guide.step3"] else {
            return XCTFail("guide step 3 vanished from OnboardingL10n")
        }
        for term in ["Postfach", "Schreibstube", "Spieltisch", "Archiv", "Amt"] {
            XCTAssertTrue(step.de.contains(term),
                          "guide step 3 (de) must name \(term)")
        }
        for term in ["Mailbox", "Writing Desk", "Game Table", "Archive", "Bureau"] {
            XCTAssertTrue(step.en.contains(term),
                          "guide step 3 (en) must name \(term)")
        }
    }

    func testGuideRouteStepsResolveAndTellOneRoute() {
        // Fix-Runde 3 (Kino-Befund 3): the three steps + the second-
        // device line resolved through the runtime stack (they moved
        // tables — a stale CoreStrings copy would shadow them), and the
        // second device stays a SUBORDINATE clause, not a QR manual.
        for key in ["onboarding.page.guide.step1", "onboarding.page.guide.step2",
                    "onboarding.page.guide.step3", "onboarding.page.guide.link"] {
            XCTAssertNotNil(OnboardingL10n.table[key],
                            "\(key) must live in OnboardingL10n")
            XCTAssertNil(CoreStrings.table[key],
                         "\(key) would be shadowed by CoreStrings (first table wins)")
        }
        guard let link = OnboardingL10n.table["onboarding.page.guide.link"] else { return }
        XCTAssertTrue(link.de.hasPrefix("Und "),
                      "the second device rides a subordinate clause (de)")
        XCTAssertTrue(link.en.hasPrefix("And "),
                      "the second device rides a subordinate clause (en)")
        XCTAssertFalse(link.de.contains("übernimmt per QR-Code"),
                       "the technical QR instruction must not return")
    }

    func testGuideRouteLinesStayShotTight() {
        // Fix4 Befund 1a: the guide-ende shot clipped „warten sc…" and
        // „QR-Code mit". The structural cure is the scrollable page +
        // intrinsically growing card (OnboardingFlowView); THIS pin keeps
        // the copy itself from creeping back toward clipping length.
        for key in ["onboarding.page.guide.step1", "onboarding.page.guide.step2",
                    "onboarding.page.guide.step3", "onboarding.page.guide.link"] {
            guard let line = OnboardingL10n.table[key] else {
                XCTFail("\(key) vanished from OnboardingL10n")
                continue
            }
            XCTAssertLessThanOrEqual(line.de.count, 96,
                                     "\(key) (de) grew past the shot-tight budget")
            XCTAssertLessThanOrEqual(line.en.count, 96,
                                     "\(key) (en) grew past the shot-tight budget")
        }
    }

    func testLanguageGateSpeaksToBothOfThem() {
        // t2-Sprachgate (Gesamtbild-Eval S2): the gate addresses the
        // COUPLE — ihr-form „Wählt eure Sprache", never du-form „Wähl".
        guard let caption = OnboardingL10n.table["cinematic.chapter.lampenklick"]
        else {
            return XCTFail("the language gate lost its caption")
        }
        for text in [caption.de, caption.en] {
            XCTAssertTrue(text.contains("Wählt eure Sprache"),
                          "the gate caption must use the ihr-form")
            XCTAssertFalse(text.contains("Wähl eure"),
                           "the du-form crept back into the gate caption")
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
        XCTAssertEqual(L10n.t("server.testOK", ["name": "Home"]), "Connected — Home ({version})")
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

    // W8 Sprachpass: names ending in an s-sound take a bare apostrophe in
    // German („Jonas' Tag“) and English ("Jonas' day"); everyone else gets
    // the regular genitive ("Mias Tag" / "Mia's day").
    func testGenitiveHelperHandlesSibilantNames() {
        let original = L10n.language
        defer { L10n.language = original }

        L10n.language = .de
        XCTAssertEqual(L10n.genitive("Mia"), "Mias")
        XCTAssertEqual(L10n.genitive("Jonas"), "Jonas'")
        XCTAssertEqual(L10n.genitive("Felix"), "Felix'")
        XCTAssertEqual(L10n.genitive("Moritz"), "Moritz'")
        XCTAssertEqual(L10n.genitive("Liz "), "Liz'")
        // The neutral fallback declines instead of taking an apostrophe.
        XCTAssertEqual(L10n.genitive("dein Schatz"), "deines Schatzes")
        XCTAssertEqual(L10n.t("daymemo.theirs", ["name": "Jonas"]), "Jonas' Tag")
        XCTAssertEqual(L10n.t("daymemo.theirs", ["name": "Mia"]), "Mias Tag")
        XCTAssertEqual(L10n.t("home.waitingPartnerAnswer", ["name": "Felix"]),
                       "Warte auf Felix' Antwort…")

        L10n.language = .en
        XCTAssertEqual(L10n.genitive("Mia"), "Mia's")
        XCTAssertEqual(L10n.genitive("Jonas"), "Jonas'")
        XCTAssertEqual(L10n.genitive("your sweetheart"), "your sweetheart's")
        XCTAssertEqual(L10n.t("daymemo.theirs", ["name": "Mia"]), "Mia's day")
    }

    // W8 Sprachpass: bracket plurals ("Umarmung(en)") were lifted onto the
    // plural engine — one hug reads like one hug.
    func testBracketPluralsUseThePluralEngine() {
        let original = L10n.language
        defer { L10n.language = original }

        L10n.language = .de
        XCTAssertEqual(L10n.t("hug.card.pending", count: 1),
                       "Eine ungeöffnete Umarmung wartet auf dich")
        XCTAssertTrue(L10n.t("hug.card.pending", count: 3).contains("3 ungeöffnete Umarmungen"))
        XCTAssertEqual(L10n.t("games.mr.end.some", count: 1), "Ein Filmabend-Match!")
        XCTAssertEqual(L10n.t("weekreview.share.perfect", count: 1), "✨ Ein perfekter Tag")
        XCTAssertEqual(L10n.t("weekreview.share.perfect", count: 4), "✨ 4 perfekte Tage")

        L10n.language = .en
        XCTAssertEqual(L10n.t("hug.card.pending", count: 1),
                       "An unopened hug is waiting for you")
        XCTAssertEqual(L10n.t("games.mr.end.some", count: 2), "2 movie-night matches!")
    }

    // The lowercase partner fallback capitalizes itself at sentence starts;
    // real names and mid-sentence uses stay untouched.
    func testPartnerFallbackCapitalizesAtSentenceStart() {
        let original = L10n.language
        defer { L10n.language = original }

        L10n.language = .de
        // "pairing.partnerJoined" starts with {name}: "{name} ist da — …"
        XCTAssertEqual(L10n.t("pairing.partnerJoined", ["name": "dein Schatz"]),
                       "Dein Schatz ist da — jetzt seid ihr zwei")
        XCTAssertEqual(L10n.t("pairing.partnerJoined", ["name": "Mia"]),
                       "Mia ist da — jetzt seid ihr zwei")
        // Mid-sentence stays lowercase: "Warte auf {nameGen} Antwort…"
        XCTAssertEqual(L10n.t("home.waitingPartnerAnswer", ["name": "dein Schatz"]),
                       "Warte auf deines Schatzes Antwort…")
    }

    /// Guard against bracket-plural regressions: "(en)"/"(es)"/"(s)" pluralism
    /// is banned — the plural engine (`.one`/`.other`) exists for this.
    func testNoBracketPluralsInAnyTable() {
        let bracketPlural = try! NSRegularExpression(pattern: #"\((e?n|es|s)\)"#)
        for (name, table) in namedTables {
            for (key, value) in table {
                for text in [value.de, value.en] {
                    let range = NSRange(text.startIndex..., in: text)
                    XCTAssertNil(bracketPlural.firstMatch(in: text, range: range),
                                 "\(name)[\"\(key)\"] uses a bracket plural: \(text)")
                }
            }
        }
    }

    /// Destructive confirmation dialogs stay emoji-free (Emoji-Leitlinie,
    /// dossier 39 #24): no confetti next to a delete button.
    func testDestructiveConfirmStringsCarryNoEmoji() {
        let emoji = try! NSRegularExpression(pattern: "[\\U0001F300-\\U0001FAFF\\u2600-\\u27BF\\u2764]")
        for (name, table) in namedTables {
            for (key, value) in table
            where key.hasSuffix("deleteConfirm") || key.hasSuffix("unpairConfirm")
                || key.hasSuffix("reset.message") {
                for text in [value.de, value.en] {
                    let range = NSRange(text.startIndex..., in: text)
                    XCTAssertNil(emoji.firstMatch(in: text, range: range),
                                 "\(name)[\"\(key)\"] mixes emoji into a destructive confirm: \(text)")
                }
            }
        }
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
