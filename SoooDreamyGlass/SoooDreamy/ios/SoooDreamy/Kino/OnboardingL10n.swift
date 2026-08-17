import Foundation

/// Onboarding-area strings (`cinematic.*`): the first-launch cinema —
/// chapter captions, the language gate, the quiet skip vocabulary, the
/// replay entry and the VoiceOver telling of the story. German first,
/// du/ihr-form; no exclamation marks, no emoji in copy (DESIGN.md
/// commandments 2 and 10). The chapter caption keys are pinned by
/// `CinematicScriptTests` — every chapter must resolve DE and EN.
enum OnboardingL10n {
    static let table: [String: LText] = [
        // MARK: The cinema itself
        "cinematic.tagline": LText(
            de: "für euch zwei",
            en: "for the two of you"),
        "cinematic.skip": LText(
            de: "Überspringen",
            en: "Skip"),
        "cinematic.next": LText(
            de: "Weiter",
            en: "Next"),
        // The named VoiceOver action on merged story chapters — explicit
        // about leaving the WHOLE cinema, not just the chapter.
        "cinematic.skipAll": LText(
            de: "Kino überspringen",
            en: "Skip the film"),

        // MARK: Chapter captions — the words live here, never in pixels
        // (the videos are text-free; SwiftUI overlays these lines so
        // Dynamic Type and VoiceOver keep working).
        // t2-Sprachgate (Gesamtbild-Eval S2): the gate addresses BOTH of
        // them — ihr-form „Wählt", not the du-form „Wähl" (the app speaks
        // du/ihr; a couple chooses together).
        "cinematic.chapter.lampenklick": LText(
            de: "Wählt eure Sprache · Choose your language",
            en: "Wählt eure Sprache · Choose your language"),
        "cinematic.chapter.umschlag": LText(
            de: "Für euch beide",
            en: "For the two of you"),
        "cinematic.chapter.siegelbruch": LText(
            de: "Ein Ort für zwei. Alles hier gehört nur euch.",
            en: "A place for two. Everything here belongs only to you."),
        "cinematic.chapter.tinten": LText(
            de: "Wähl deine Farbe",
            en: "Pick your color"),
        "cinematic.chapter.wachssiegel": LText(
            de: "Das ist eure Farbe. Nur ihr zwei habt sie.",
            en: "This is your color. Only the two of you have it."),
        "cinematic.chapter.polaroid": LText(
            de: "Eure erste Erinnerung fehlt noch.",
            en: "Your first memory is still missing."),
        "cinematic.chapter.ankunft": LText(
            de: "Willkommen zuhause.",
            en: "Welcome home."),

        // The Kurzfassung postmark of chapter 2 — the one word the stage
        // stamps itself (the video renders its own text-free postmark).
        "cinematic.umschlag.stamp": LText(
            de: "TAG 1",
            en: "DAY 1"),

        // MARK: Language gate (chapter 1) — both options name themselves
        // in their OWN language, readable before any choice exists.
        "cinematic.language.de": LText(
            de: "Deutsch",
            en: "Deutsch"),
        "cinematic.language.de.sub": LText(
            de: "Die App spricht Deutsch mit euch",
            en: "Die App spricht Deutsch mit euch"),
        "cinematic.language.de.a11y": LText(
            de: "Deutsch. Die App spricht Deutsch mit euch.",
            en: "Deutsch. Die App spricht Deutsch mit euch."),
        // EN-Idiomatik (Fix-Runde 3, Kino-Befund 5): „The app speaks
        // English with you" was German syntax in English clothes — the
        // card promises in natural future tense, named by the app.
        "cinematic.language.en": LText(
            de: "English",
            en: "English"),
        "cinematic.language.en.sub": LText(
            de: "SoooDreamy will speak English with you",
            en: "SoooDreamy will speak English with you"),
        "cinematic.language.en.a11y": LText(
            de: "English. SoooDreamy will speak English with you.",
            en: "English. SoooDreamy will speak English with you."),

        // MARK: Ink chapter (chapter 4) — the interactive color moment
        // EN-Idiomatik (Re-Eval Runde 2): „your love" as a person is
        // stilted English — the app's EN voice says "sweetheart"
        // (see the daily-question notification).
        "cinematic.ink.partner": LText(
            de: "Der zweite Strich wartet auf deinen Schatz",
            en: "The second stroke is waiting for your sweetheart"),
        // Re-Eval Runde 2 (A11y): the well speaks its COLOR — „Tintenfass
        // Rosa, 1 von 8" instead of eight silent circles.
        "cinematic.ink.wellA11y": LText(
            de: "Tintenfass {name}, {index} von {total}",
            en: "Ink well {name}, {index} of {total}"),

        // MARK: Chapter chrome — progress + per-chapter skip
        "cinematic.progressA11y": LText(
            de: "Kapitel {current} von {total}",
            en: "Chapter {current} of {total}"),
        "cinematic.nextA11y": LText(
            de: "Springt zum nächsten Kapitel.",
            en: "Skips to the next chapter."),

        // MARK: Replay entry (welcome flow)
        "cinematic.replay": LText(
            de: "Intro erneut ansehen",
            en: "Watch the intro again"),

        // MARK: The guide's closing page — one delivery route, not a
        // numbered form (Fix-Runde 3, Kino-Befund 3; Fix4 Befund 1 makes
        // the COMPOSITION carry it too: OnboardingFlowView draws the
        // three stops as one connected Zustellroute instead of 1/2/3
        // stamps). The lines are TIGHT — the guide-ende shot clipped
        // „warten sc…" and „QR-Code mit" — every line stays under the
        // L10n length pin; the second device rides ONE quiet subordinate
        // clause. Step 3 keeps naming ALL FIVE stations — the L10n test
        // pins the terms in both languages.
        "onboarding.page.guide.step1": LText(
            de: "Zuerst verbindet ihr euren Server — die Adresse, von der euer Postamt zustellt",
            en: "First you connect your server — the address your post office delivers from"),
        "onboarding.page.guide.step2": LText(
            de: "Dann koppelt ihr euch: eine Person eröffnet euer Fach, die andere tritt mit dem Code dazu",
            en: "Then you pair up: one of you opens your pigeonhole, the other steps in with the code"),
        "onboarding.page.guide.step3": LText(
            de: "Dann wird zugestellt — Postfach, Schreibstube, Spieltisch, Archiv und Amt warten schon",
            en: "Then the mail moves — Mailbox, Writing Desk, Game Table, Archive and Bureau are waiting"),
        "onboarding.page.guide.link": LText(
            de: "Und kommt später ein Zweitgerät dazu, genügt „Ich habe schon ein Gerät“",
            en: "And if a second device joins later, “I already have a device” is all it takes"),

        // MARK: Page-1 entry paths — three ways in, decision-ready
        "onboarding.path.scan": LText(
            de: "Einladung scannen",
            en: "Scan an invitation"),
        "onboarding.path.scanHintA11y": LText(
            de: "Öffnet die Kamera. Der QR-Code deines Schatzes bringt Server und Paar-Code in einem Schritt mit.",
            en: "Opens the camera. Your partner's QR code carries server and couple code in one step."),
        "onboarding.path.server": LText(
            de: "Server verbinden",
            en: "Connect a server"),
        // EN-Idiomatik (Re-Eval Runde 2): „See what awaits you" read like
        // a prophecy — plain curiosity is the natural register here.
        "onboarding.path.tour": LText(
            de: "Was euch erwartet",
            en: "See what's inside"),
        "onboarding.invite.needServer": LText(
            de: "Code gemerkt — verbindet jetzt noch euren Server",
            en: "Code saved — now connect your server"),
        "onboarding.invite.unrecognized": LText(
            de: "Diesen Code kennt die App nicht — ihr könnt ihn später eintippen",
            en: "The app doesn't recognize this code — you can type it later"),

        // MARK: Accessibility — the story with closed eyes
        "cinematic.a11y": LText(
            de: "Ein kurzes Kino erzählt, wie aus einem Brief euer gemeinsamer Ort wird. Es dauert ungefähr eine Minute.",
            en: "A short cinema tells how a letter becomes your shared place. It takes about a minute."),
        "cinematic.skipA11y": LText(
            de: "Doppeltippen überspringt das Kino und bringt dich direkt zur Einrichtung.",
            en: "Double-tap to skip the cinema and go straight to setup."),
    ]
}
