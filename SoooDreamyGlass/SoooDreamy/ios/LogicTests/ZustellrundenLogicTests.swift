import XCTest
@testable import SoooDreamyLogic

/// Pins the Zustellrunden verdict (NEUBAU_ENTSCHEID §4.6): round boundaries,
/// the one-mark-per-round-and-device model, and determinism. The logic is
/// pure Foundation — no clock, no locale, no global state — so every test
/// here passes identically on Linux and macOS.
final class ZustellrundenLogicTests: XCTestCase {

    // MARK: Rundengrenzen (05–11 · 11–17 · 17–05, lokale Gerätestunde)

    func testRoundBoundariesCoverEveryHourExactlyOnce() {
        for hour in 0..<24 {
            let expected: Zustellrunde
            switch hour {
            case 5..<11: expected = .morgenpost
            case 11..<17: expected = .tagespost
            default: expected = .nachtpost
            }
            XCTAssertEqual(Zustellrunde.from(hour: hour), expected,
                           "hour \(hour) landed in the wrong round")
        }
    }

    func testExactBoundaryHours() {
        // The lower bound belongs to the NEW round (half-open windows).
        XCTAssertEqual(Zustellrunde.from(hour: 4), .nachtpost)
        XCTAssertEqual(Zustellrunde.from(hour: 5), .morgenpost)
        XCTAssertEqual(Zustellrunde.from(hour: 10), .morgenpost)
        XCTAssertEqual(Zustellrunde.from(hour: 11), .tagespost)
        XCTAssertEqual(Zustellrunde.from(hour: 16), .tagespost)
        XCTAssertEqual(Zustellrunde.from(hour: 17), .nachtpost)
        XCTAssertEqual(Zustellrunde.from(hour: 23), .nachtpost)
        XCTAssertEqual(Zustellrunde.from(hour: 0), .nachtpost)
    }

    func testNachtpostReplacesTheOldEveningAndNightPhasesWithoutAGap() {
        // The old DayPhase split 17–21 (evening) and 21–05 (night); both
        // only ever drove the night-checkin suggestion — nachtpost is the
        // exact union, so no hour changed its hero behavior.
        for hour in [17, 18, 20, 21, 23, 0, 3, 4] {
            XCTAssertEqual(Zustellrunde.from(hour: hour), .nachtpost)
        }
    }

    // MARK: Marke („{dateKey}#{runde}")

    func testMarkeFormat() {
        XCTAssertEqual(ZustellrundenLogic.marke(dateKey: "2026-08-16", runde: .tagespost),
                       "2026-08-16#tagespost")
        XCTAssertEqual(ZustellrundenLogic.marke(dateKey: "2026-01-01", runde: .morgenpost),
                       "2026-01-01#morgenpost")
        XCTAssertEqual(ZustellrundenLogic.marke(dateKey: "2025-12-31", runde: .nachtpost),
                       "2025-12-31#nachtpost")
    }

    // MARK: Runden-Mengen-Modell (Fix2-A №6 — genau EINE Inszenierung
    // pro Runde, TAG und Gerät; die Marke sammelt alle gespielten Runden)

    func testFirstForegroundOfARoundStagesOnce() {
        // Fresh device (no mark yet) stages …
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .morgenpost, dateKey: "2026-08-16", zuletzt: nil))
        // … and after writing the mark, the SAME round stays quiet
        // (idempotent for every further foreground entry).
        let marke = ZustellrundenLogic.naechsteMarke(
            runde: .morgenpost, dateKey: "2026-08-16", zuletzt: nil)
        for _ in 0..<3 {
            XCTAssertFalse(ZustellrundenLogic.sollInszenieren(
                runde: .morgenpost, dateKey: "2026-08-16", zuletzt: marke))
        }
    }

    func testNextRoundOfTheSameDayStagesAgain() {
        let morgens = ZustellrundenLogic.naechsteMarke(
            runde: .morgenpost, dateKey: "2026-08-16", zuletzt: nil)
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: morgens))
        let tags = ZustellrundenLogic.naechsteMarke(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: morgens)
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: tags))
    }

    func testSameRoundOnANewDayStagesAgain() {
        // Deliberate midnight nuance (documented in ZustellrundenLogic):
        // the over-midnight Nachtpost counts as the NEW day's round — the
        // new letter (daily question flips with the dateKey) really is in
        // the tray. A new day always begins a FRESH set.
        let gestern = ZustellrundenLogic.naechsteMarke(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: nil)
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .nachtpost, dateKey: "2026-08-17", zuletzt: gestern))
        XCTAssertTrue(ZustellrundenLogic.gespielteRunden(
            dateKey: "2026-08-17", zuletzt: gestern).isEmpty)
    }

    func testClockRollbackNeverReplaysAPlayedRound() {
        // Die Runden-Zeitreise (Fix2-A №6): Uhr-Rückstellung (Zeitzonen-
        // Reise) in eine BEREITS gespielte Runde darf sie nie erneut
        // inszenieren — die Tages-Menge vergisst nichts.
        var marke: String? = ZustellrundenLogic.naechsteMarke(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: nil)
        marke = ZustellrundenLogic.naechsteMarke(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: marke)
        // Clock rolls back from Nachtpost into the already-played Tagespost:
        XCTAssertFalse(ZustellrundenLogic.sollInszenieren(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: marke))
        // The genuinely unplayed Morgenpost may still stage.
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .morgenpost, dateKey: "2026-08-16", zuletzt: marke))
    }

    // MARK: Marken-Format & Idempotenz (Fix2-A №6)

    func testNaechsteMarkeUsesCanonicalRoundOrder() {
        // Egal in welcher Reihenfolge gespielt wird — die Marke listet die
        // Runden immer in Rundenfolge (morgenpost,tagespost,nachtpost).
        let nachts = ZustellrundenLogic.naechsteMarke(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: nil)
        XCTAssertEqual(nachts, "2026-08-16#nachtpost")
        let dann = ZustellrundenLogic.naechsteMarke(
            runde: .morgenpost, dateKey: "2026-08-16", zuletzt: nachts)
        XCTAssertEqual(dann, "2026-08-16#morgenpost,nachtpost")
        let alle = ZustellrundenLogic.naechsteMarke(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: dann)
        XCTAssertEqual(alle, "2026-08-16#morgenpost,tagespost,nachtpost")
    }

    func testNaechsteMarkeIsIdempotent() {
        let einmal = ZustellrundenLogic.naechsteMarke(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: nil)
        let zweimal = ZustellrundenLogic.naechsteMarke(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: einmal)
        XCTAssertEqual(einmal, zweimal)
        XCTAssertEqual(einmal, "2026-08-16#tagespost")
    }

    func testNewDayStartsAFreshSetInTheMark() {
        let gestern = "2026-08-16#morgenpost,tagespost,nachtpost"
        let heute = ZustellrundenLogic.naechsteMarke(
            runde: .morgenpost, dateKey: "2026-08-17", zuletzt: gestern)
        XCTAssertEqual(heute, "2026-08-17#morgenpost")
    }

    // MARK: Migration der Alt-Marke (Ein-Marken-Modell → Runden-Menge)

    func testLegacySingleMarkReadsAsOneRoundSet() {
        // Die alte Ein-Marken-Form („{dateKey}#{runde}") IST bereits eine
        // gültige Ein-Runden-Menge — kein Sonderpfad, kein Datenverlust.
        let alt = ZustellrundenLogic.marke(dateKey: "2026-08-16", runde: .tagespost)
        XCTAssertEqual(ZustellrundenLogic.gespielteRunden(
            dateKey: "2026-08-16", zuletzt: alt), [.tagespost])
        XCTAssertFalse(ZustellrundenLogic.sollInszenieren(
            runde: .tagespost, dateKey: "2026-08-16", zuletzt: alt))
        XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: alt))
        // Weiterschreiben migriert die Alt-Marke in die kanonische Menge.
        XCTAssertEqual(ZustellrundenLogic.naechsteMarke(
            runde: .nachtpost, dateKey: "2026-08-16", zuletzt: alt),
            "2026-08-16#tagespost,nachtpost")
    }

    func testGarbageMarksReadAsEmptySetAndStage() {
        for kaputt in ["", "unfug", "2026-08-16#", "2026-08-16#gestern",
                       "#tagespost", "2026-08-15#tagespost"] {
            XCTAssertTrue(ZustellrundenLogic.gespielteRunden(
                dateKey: "2026-08-16", zuletzt: kaputt).isEmpty,
                "'\(kaputt)' muss als leere Menge lesen")
            XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
                runde: .tagespost, dateKey: "2026-08-16", zuletzt: kaputt))
        }
    }

    // MARK: Determinismus

    func testVerdictIsDeterministic() {
        for runde in Zustellrunde.allCases {
            let marke = ZustellrundenLogic.naechsteMarke(
                runde: runde, dateKey: "2026-08-16", zuletzt: nil)
            for _ in 0..<5 {
                XCTAssertEqual(ZustellrundenLogic.naechsteMarke(
                    runde: runde, dateKey: "2026-08-16", zuletzt: nil), marke)
                XCTAssertFalse(ZustellrundenLogic.sollInszenieren(
                    runde: runde, dateKey: "2026-08-16", zuletzt: marke))
                XCTAssertTrue(ZustellrundenLogic.sollInszenieren(
                    runde: runde, dateKey: "2026-08-16", zuletzt: nil))
            }
        }
        for hour in 0..<24 {
            XCTAssertEqual(Zustellrunde.from(hour: hour), Zustellrunde.from(hour: hour))
        }
    }

    func testTitleKeysFollowThePostfachNamespace() {
        // The stamp line and the Zustellzettel read the same L10n name.
        XCTAssertEqual(Zustellrunde.morgenpost.titleKey, "postfach.runde.morgenpost")
        XCTAssertEqual(Zustellrunde.tagespost.titleKey, "postfach.runde.tagespost")
        XCTAssertEqual(Zustellrunde.nachtpost.titleKey, "postfach.runde.nachtpost")
        for runde in Zustellrunde.allCases {
            XCTAssertNotNil(PostfachL10n.table[runde.titleKey],
                            "\(runde.titleKey) missing from PostfachL10n")
        }
    }

    func testGreetingKeysResolveInBothLanguages() {
        // The greeting line of the mailbox head (redesign wave 1): every
        // round owns a resolvable greeting in DE and EN — a broken key
        // would print its raw name into the first line of the app.
        XCTAssertEqual(Zustellrunde.morgenpost.greetingKey, "postfach.gruss.morgenpost")
        XCTAssertEqual(Zustellrunde.tagespost.greetingKey, "postfach.gruss.tagespost")
        XCTAssertEqual(Zustellrunde.nachtpost.greetingKey, "postfach.gruss.nachtpost")
        for runde in Zustellrunde.allCases {
            let text = PostfachL10n.table[runde.greetingKey]
            XCTAssertNotNil(text, "\(runde.greetingKey) missing from PostfachL10n")
            XCTAssertFalse(text?.de.isEmpty ?? true,
                           "\(runde.greetingKey) has an empty German greeting")
            XCTAssertFalse(text?.en.isEmpty ?? true,
                           "\(runde.greetingKey) has an empty English greeting")
        }
    }
}
