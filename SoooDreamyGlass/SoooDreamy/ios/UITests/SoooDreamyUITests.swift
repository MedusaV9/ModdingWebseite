import XCTest

// P1-D — real usage tests. ONE class on purpose: XCTest executes the
// methods alphabetically (test01…test05, scheme parallelization off),
// which turns cross-launch UserDefaults persistence from a hazard into
// a scripted journey. Every anchor below is a real user-facing label
// from the app's L10n tables (German pinned via -AppleLanguages).
//
// test05 talks to the REAL Node server the CI job boots on
// localhost:4321 — pairing code (and optionally member A's token for
// the in-test journal check) arrive via TEST_RUNNER_-prefixed
// environment variables; without them the test provisions member A
// itself through the documented API (docs/API.md).
final class SoooDreamyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - test01 — Erststart: Sprach-Gate → Kino → Guide

    /// First launch (CI erases the simulator beforehand): the cinema's
    /// language gate shows BOTH cards, tapping Deutsch starts the intro
    /// chapters, "Weiter" walks through them, "Überspringen" leaves the
    /// cinema — and the onboarding guide with its three entry paths is
    /// the landing spot.
    func test01_LanguageGateAndIntro() throws {
        // introSeen pinned to NO — even a leaked seen-flag cannot hide
        // the cinema. germanChosen false: the gate only exists while the
        // language key is absent (argument domain cannot fake nil, so
        // this leg additionally relies on the CI's simulator erase).
        let app = launchApp(LaunchConfig(introSeen: false, demoActive: false,
                                         germanChosen: false))

        // Both language cards, addressed via their stable accessibility
        // IDs — label-prefix anchors broke once when the EN copy was
        // idiomatized (eval round 3); the IDs are the a11y contract.
        let germanCard = app.buttons["cinematic.language.de"]
        let englishCard = app.buttons["cinematic.language.en"]
        waitFor(germanCard, timeout: 45,
                "Sprach-Gate: Deutsch-Karte fehlt — Erststart-Kino nicht erschienen")
        waitFor(englishCard, timeout: 10, "Sprach-Gate: English-Karte fehlt")
        attachScreenshot("01_sprachwahl_beide_karten", of: app)
        germanCard.tap()

        // The gate holds a 4 s dwell, then chapter 2 brings the chrome:
        // "Weiter" (per chapter) and "Überspringen" (whole cinema).
        let weiter = app.buttons["Weiter"]
        waitFor(weiter, timeout: 30,
                "Intro nicht gestartet — Kapitel-2-Chrome (Weiter) fehlt nach Sprachwahl")

        // At least one real chapter caption must be on stage (which one
        // depends on video-run timing — auto-advance keeps rolling while
        // the test waits, so the check accepts any of chapters 2–4).
        let captions = ["Für euch beide", "Ein Ort für zwei", "Wähl deine Farbe"]
        let anyCaption = captions.contains { app.text(containing: $0).waitForExistence(timeout: 6) }
        XCTAssertTrue(anyCaption, "Keine Kapitel-Caption sichtbar — Intro läuft nicht")
        attachScreenshot("01_intro_kapitel", of: app)

        // "Weiter" through a couple of chapters (the button survives the
        // chapter swap; a tap during a video run skips that clip).
        weiter.tap()
        waitFor(weiter, timeout: 15, "Weiter-Chrome nach Kapitelwechsel verschwunden")
        weiter.tap()

        // Skip the rest of the cinema entirely — by a11y id: the guide is
        // mounted UNDER the cinema (hand-off architecture), so a plain
        // "Überspringen" label matches twice (run 31907294748).
        let skipById = app.buttons["cinematic.skipAll"].firstMatch
        let skip = skipById.exists ? skipById : app.buttons["Überspringen"].firstMatch
        waitFor(skip, timeout: 15, "Überspringen-Chrome fehlt")
        skip.tap()

        // Landing: the onboarding guide's page-1 entry paths.
        waitFor(app.buttons["Erst mal ansehen"], timeout: 30,
                "Onboarding-Guide fehlt nach Kino-Skip (Erst mal ansehen)")
        waitFor(app.buttons["Einladung scannen"], timeout: 10,
                "Onboarding-Guide unvollständig (Einladung scannen fehlt)")
        waitFor(app.buttons["Server verbinden"], timeout: 10,
                "Onboarding-Guide unvollständig (Server verbinden fehlt)")
        attachScreenshot("01_onboarding_guide", of: app)
    }

    // MARK: - test02 — Demo betreten, alle fünf Tabs

    /// Enter the in-app demo ("Erst mal ansehen") from the guide, then
    /// visit all five tabs with 1–2 core assertions each plus scroll
    /// rounds — the staged demo couple (Mia & Ben) provides the props.
    func test02_DemoModeTour() throws {
        let app = launchApp(LaunchConfig(introSeen: true, demoActive: false))

        let demoEntry = app.buttons["Erst mal ansehen"]
        waitFor(demoEntry, timeout: 45, "Guide-Einstieg fehlt (Erst mal ansehen)")
        demoEntry.tap()

        // The permanent demo badge is the proof we are in the demo.
        waitFor(app.button(startingWith: "Demo-Modus aktiv"), timeout: 20,
                "Demo-Badge fehlt nach Demo-Einstieg")

        // Zuhause: question-of-the-day card + send-love grid. First give
        // the dashboard a beat to render, THEN scroll-search (lazy
        // stacks materialize content only near the viewport).
        _ = app.text(containing: "Frage des Tages").waitForExistence(timeout: 15)
        XCTAssertTrue(app.scrollToFind(app.text(containing: "Frage des Tages")),
                      "Zuhause: Frage-des-Tages-Karte fehlt")
        XCTAssertTrue(app.scrollToFind(app.text(containing: "Schick Liebe")),
                      "Zuhause: Schick-Liebe-Karte nicht erreichbar")
        attachScreenshot("02_demo_zuhause", of: app)
        app.scrollRounds()

        // Schreibstube: staged transcript + composer.
        app.switchTab(id: "tab.chat", labelPrefix: "Schreibstube")
        waitFor(app.textField(placeholderContaining: "Schreib etwas"),
                timeout: 20, "Schreibstube: Composer-Feld fehlt")
        waitFor(app.text(containing: "Versprochen."), timeout: 15,
                "Schreibstube: gestagtes Transkript fehlt (Versprochen.)")
        attachScreenshot("02_demo_chat", of: app)

        // Spieltisch: hub subtitle + scroll through the catalog.
        app.switchTab(id: "tab.play", labelPrefix: "Spieltisch")
        waitFor(app.text(containing: "Kleine Spiele"), timeout: 20,
                "Spieltisch: Hub-Untertitel fehlt")
        app.scrollRounds()
        attachScreenshot("02_demo_spielen", of: app)

        // Archiv: memories hub + scroll (the cabinet lives here; the hub
        // title is „Archiv" now — same word as the tab label, so the
        // anchor moved to the SUBTITLE, which can never match the tab
        // bar button).
        app.switchTab(id: "tab.us", labelPrefix: "Archiv")
        waitFor(app.text(containing: "Eure Erinnerungen"), timeout: 20,
                "Archiv: Hub-Untertitel fehlt (Eure Erinnerungen)")
        app.scrollRounds()
        attachScreenshot("02_demo_wir", of: app)

        // Amt: settings list (language row is a stable resident).
        app.switchTab(id: "tab.settings", labelPrefix: "Amt")
        waitFor(app.navigationBars["Amt"], timeout: 20,
                "Amt: Settings-Navigation fehlt")
        XCTAssertTrue(app.scrollToFind(app.text(containing: "Sprache")),
                      "Amt: Sprache-Zeile nicht erreichbar")
        attachScreenshot("02_demo_mehr", of: app)
    }

    // MARK: - test03 — Chat: senden + suchen (Demo)

    /// Type a message into the demo chat, send it, see the bubble —
    /// then run the transcript search (magnifier), watch the filter
    /// kick in, and cancel back to the full transcript.
    func test03_ChatSendInDemo() throws {
        // demo.active pinned YES — lands directly in the staged demo. The
        // search seam pins the drawer field visible (the minimized system
        // button is SDK chrome XCUITest cannot address, two runs proved).
        let app = launchApp(LaunchConfig(
            introSeen: true, demoActive: true,
            extraArguments: ["-SoooDreamyUITestSearchAlways"]))

        app.switchTab(id: "tab.chat", labelPrefix: "Schreibstube")
        let composer = app.textField(placeholderContaining: "Schreib etwas")
        waitFor(composer, timeout: 30, "Chat: Composer-Feld fehlt")
        composer.tap()
        composer.typeText("Bis gleich am Kanal")

        let send = app.buttons["Nachricht senden"]
        waitFor(send, timeout: 10, "Chat: Senden-Knopf fehlt bei gefülltem Feld")
        send.tap()
        waitFor(app.text(containing: "Bis gleich am Kanal"), timeout: 15,
                "Chat: gesendete Bubble fehlt")
        attachScreenshot("03_chat_bubble_gesendet", of: app)

        // Search — iOS 26 minimizes .searchable into a toolbar button.
        // The system button's label is SDK-owned (run 31903489346 found
        // neither „Suchen" nor „Search"), so hunt case-insensitively
        // across buttons AND the navigation bar, and give the toolbar a
        // scroll-up nudge first (scroll-edge chrome).
        let searchField = app.searchFields.firstMatch
        if !searchField.exists {
            app.swipeDown(velocity: .slow)
            let lupePredicate = NSPredicate(
                format: "label CONTAINS[c] 'such' OR label CONTAINS[c] 'search' OR identifier CONTAINS[c] 'search'")
            var lupe = app.buttons.matching(lupePredicate).firstMatch
            if !lupe.waitForExistence(timeout: 6) {
                lupe = app.navigationBars.buttons.matching(lupePredicate).firstMatch
            }
            if !lupe.exists {
                // Last resort: the trailing-most nav-bar button that is
                // neither help nor connection — on this screen that is
                // the system search affordance.
                lupe = app.navigationBars.firstMatch.buttons.element(
                    boundBy: max(0, app.navigationBars.firstMatch.buttons.count - 1))
            }
            waitFor(lupe, timeout: 10, "Chat: Such-Einstieg (Lupe) fehlt")
            app.tapRobust(lupe)
        }
        waitFor(searchField, timeout: 15, "Chat: Suchfeld erschien nicht")
        searchField.tap()
        searchField.typeText("Kino")

        // Filter proof: the matching staged bubble stays, others leave.
        waitFor(app.text(containing: "Kinokarten"), timeout: 15,
                "Chat-Suche: Treffer (Kinokarten) fehlt")
        XCTAssertTrue(waitForDisappearance(of: app.text(containing: "Versprochen.")),
                      "Chat-Suche: Filter greift nicht (Versprochen. weiter sichtbar)")
        attachScreenshot("03_chat_suche_gefiltert", of: app)

        // Clearing the query restores the full transcript. The pinned
        // always-drawer shows no cancel button (run 31907294748) — prefer
        // Abbrechen when the SDK offers it, otherwise delete the query.
        let abbrechen = app.buttons["Abbrechen"]
        if abbrechen.waitForExistence(timeout: 4) {
            abbrechen.tap()
        } else {
            searchField.tap()
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4)
            searchField.typeText(deletes)
        }
        waitFor(app.text(containing: "Versprochen."), timeout: 15,
                "Chat-Suche: Transkript nach Leeren nicht zurück")
    }

    // MARK: - test04 — Post-Station: Zeitpost- & Verlauf-Sheets

    /// Open the Zeitpost sheet from the send-love grid, cycle the kind
    /// chips, touch the DatePicker, close — then open and close the
    /// journal sheet. Demo mode: composing UI only, nothing is sent.
    func test04_PostStationSheets() throws {
        let app = launchApp(LaunchConfig(introSeen: true, demoActive: true))

        // Let the dashboard render before scroll-searching the grid.
        waitFor(app.text(containing: "Frage des Tages"), timeout: 30,
                "Zuhause nicht gerendert (Frage des Tages fehlt)")

        // Zeitpost tile lives in the "Schick Liebe" grid on Zuhause.
        let zeitpostTile = app.button(startingWith: "Zeitpost planen")
        XCTAssertTrue(app.scrollToFind(zeitpostTile), "Zuhause: Zeitpost-Kachel fehlt")
        zeitpostTile.tap()
        waitFor(app.navigationBars["Zeitpost"], timeout: 20, "Zeitpost-Sheet fehlt")

        // Kind chips: Berührung → Puls → Notiz (note field appears) →
        // back to Berührung (gesture chips appear, pick Kuss).
        let noteChip = app.buttons["Notiz"]
        waitFor(noteChip, timeout: 15, "Zeitpost: Kind-Chips fehlen")
        app.buttons["Puls"].tap()
        noteChip.tap()
        waitFor(app.textField(placeholderContaining: "Ein paar liebe Worte"),
                timeout: 10, "Zeitpost: Notiz-Feld fehlt nach Chip-Wechsel")
        app.buttons["Berührung"].tap()
        let kissChip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Kuss")).firstMatch
        waitFor(kissChip, timeout: 10, "Zeitpost: Berührungs-Chips fehlen (Kuss)")
        kissChip.tap()
        attachScreenshot("04_zeitpost_chips", of: app)

        // DatePicker ("Ankunft"): open the compact picker, then dismiss
        // its overlay with a tap outside.
        let datePicker = app.datePickers.firstMatch
        waitFor(datePicker, timeout: 10, "Zeitpost: Ankunft-DatePicker fehlt")
        datePicker.tap()
        attachScreenshot("04_zeitpost_datepicker", of: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        // Close via the toolbar's Fertig.
        let fertig = app.buttons["Fertig"]
        waitFor(fertig, timeout: 10, "Zeitpost: Fertig-Knopf fehlt")
        fertig.tap()
        XCTAssertTrue(waitForDisappearance(of: app.navigationBars["Zeitpost"]),
                      "Zeitpost-Sheet schloss nicht")

        // Journal sheet ("Verlauf" tile → Posteingang der Zärtlichkeiten).
        let journalTile = app.button(startingWith: "Posteingang der Zärtlichkeiten")
        XCTAssertTrue(app.scrollToFind(journalTile), "Zuhause: Verlauf-Kachel fehlt")
        journalTile.tap()
        waitFor(app.navigationBars["Posteingang der Zärtlichkeiten"], timeout: 20,
                "Verlauf-Sheet fehlt")
        attachScreenshot("04_verlauf_sheet", of: app)
        let journalFertig = app.buttons["Fertig"]
        waitFor(journalFertig, timeout: 10, "Verlauf: Fertig-Knopf fehlt")
        journalFertig.tap()
        XCTAssertTrue(waitForDisappearance(of: app.navigationBars["Posteingang der Zärtlichkeiten"]),
                      "Verlauf-Sheet schloss nicht")
    }

    // MARK: - test05 — Der Königs-Test: echter Server, echtes Pairing

    /// Against the REAL Node server on localhost: the app adds the
    /// server through onboarding UI, joins the CI-created couple as
    /// member B via code, sees the paired home (partner "Mia"), sends a
    /// kiss — and the kiss is verified in the server's journal (in-test
    /// via API when member A's token is available; the CI step curls
    /// the journal again after the run as the second, independent gate).
    func test05_ServerPairedFlow() throws {
        let environment = ProcessInfo.processInfo.environment
        let serverURLString = environment["SOOODREAMY_SERVER_URL"] ?? "http://127.0.0.1:4321"
        guard let serverURL = URL(string: serverURLString) else {
            XCTFail("Ungültige Server-URL: \(serverURLString)"); return
        }
        let client = CoupleServerClient(baseURL: serverURL)

        // Fail fast and loud when the server is not up — this test is a
        // gate, never a silent skip.
        do {
            _ = try client.health()
        } catch {
            XCTFail("Couple-Server nicht erreichbar unter \(serverURLString) — "
                    + "CI-Step 'Start couple server' prüfen (\(error))")
            return
        }

        // Member A: prefer the CI-provisioned couple (code via
        // TEST_RUNNER_SOOODREAMY_PAIR_CODE), else provision here.
        var pairCode = environment["SOOODREAMY_PAIR_CODE"]
        var miaToken = environment["SOOODREAMY_MIA_TOKEN"]
        if pairCode?.isEmpty != false {
            let auth = try client.createCouple()
            pairCode = auth.code
            miaToken = auth.token
        }
        guard let code = pairCode, !code.isEmpty else {
            XCTFail("Kein Pairing-Code verfügbar"); return
        }

        let app = launchApp(LaunchConfig(introSeen: true, demoActive: false))

        // Onboarding → server sheet → address → live connection test.
        let serverEntry = app.buttons["Server verbinden"]
        waitFor(serverEntry, timeout: 45, "Guide-Einstieg fehlt (Server verbinden)")
        serverEntry.tap()

        let addressField = app.textField(placeholderContaining: "Adresse")
        waitFor(addressField, timeout: 20, "Server-Sheet: Adressfeld fehlt")
        addressField.tap()
        addressField.typeText(serverURLString)
        // Return ends editing (no onSubmit on this field) — the keyboard
        // leaves and stops covering the buttons below.
        app.typeText("\n")

        let testButton = app.buttons["Verbindung testen"]
        XCTAssertTrue(app.scrollToFind(testButton), "Server-Sheet: Testen-Knopf fehlt")
        testButton.tap()
        waitFor(app.text(containing: "Verbunden"), timeout: 30,
                "Server-Sheet: Verbindungstest gegen den echten Server schlug fehl")
        attachScreenshot("05_server_verbunden", of: app)

        let weiter = app.buttons["Weiter"]
        XCTAssertTrue(app.scrollToFind(weiter), "Server-Sheet: Weiter fehlt")
        weiter.tap()

        // Pairing: join as member B with the code.
        waitFor(app.text(containing: "Findet zueinander"), timeout: 20,
                "Pairing-Screen fehlt nach Server-Setup")
        app.buttons["Mit Code beitreten"].firstMatch.tap()

        let nameField = app.textField(placeholderContaining: "Dein Name")
        waitFor(nameField, timeout: 15, "Pairing: Namensfeld fehlt")
        nameField.tap()
        nameField.typeText("Ben")

        let codeField = app.textField(placeholderContaining: "Code, z. B.")
        XCTAssertTrue(app.scrollToFind(codeField), "Pairing: Code-Feld fehlt")
        codeField.tap()
        codeField.typeText(code)
        // Dismiss the keyboard so the submit button is reachable.
        app.typeText("\n")
        attachScreenshot("05_join_formular", of: app)

        // Two buttons now share the label (mode switch + primary) —
        // the primary submit is the LAST one in the hierarchy.
        let joinButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Mit Code beitreten"))
        let submit = joinButtons.count > 1
            ? joinButtons.element(boundBy: joinButtons.count - 1)
            : joinButtons.firstMatch
        XCTAssertTrue(app.scrollToFind(submit), "Pairing: Beitreten-Knopf fehlt")
        submit.tap()

        // Arrival: pairing ceremony plays (~4 s), then the one-time
        // recovery-key sheet — acknowledge it.
        let keySafe = app.buttons["Ich hab ihn sicher"]
        waitFor(keySafe, timeout: 60,
                "Recovery-Key-Zeremonie fehlt — Join vermutlich fehlgeschlagen")
        attachScreenshot("05_recovery_zeremonie", of: app)
        keySafe.tap()

        // Paired home: the partner's name is on stage.
        waitFor(app.text(containing: "Mia"), timeout: 30,
                "Gepaartes Zuhause: Partnername Mia fehlt")
        attachScreenshot("05_gepaartes_zuhause", of: app)

        // Send the FIRST GREETING from the FirstMoment hero — the designed
        // fresh-couple path (run 31904755259 proved the touch grid does not
        // exist yet: DashboardPriority filters `.touches` while the
        // firstMoment hero is on stage). The greeting sends a heartbeat
        // touch over the real server.
        let greetingById = app.buttons["home.firstGreeting"].firstMatch
        let greeting = greetingById.exists
            ? greetingById
            : app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Gruß")).firstMatch
        XCTAssertTrue(app.scrollToFind(greeting, maxSwipes: 6),
                      "Zuhause: Ersten-Gruß-Knopf fehlt")
        app.tapRobust(greeting)
        waitFor(app.text(containing: "ist unterwegs"), timeout: 20,
                "Gruß-Toast fehlt — POST /api/touches vermutlich fehlgeschlagen")
        attachScreenshot("05_gruss_unterwegs", of: app)

        // In-test server-side verification (when member A's token is
        // known): the greeting must land in the journal. The CI step re-
        // checks via curl after the run — two independent proofs.
        if let miaToken {
            var journalHasGreeting = false
            for _ in 0..<10 {
                if let found = try? client.journalContainsGreeting(token: miaToken), found {
                    journalHasGreeting = true
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(1))
            }
            XCTAssertTrue(journalHasGreeting,
                          "Server-Journal enthält den Gruß nicht (GET /api/post/journal)")
        }
    }
}
