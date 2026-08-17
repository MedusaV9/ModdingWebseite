import Foundation

/// Postfach-Vokabular (Neubau N2+): Zustellrunden, Briefschlitz,
/// Stempelzeile und alles, was die Postfach-Station NEU spricht.
/// Eigene Tabelle, damit parallele Bau-Wellen nie dieselbe
/// Strings-Datei anfassen (CoreStrings bleibt das Bestands-Archiv).
///
/// Postdeutsch-Budget (ENTSCHEID §4, hart): pro Screen genau EINE
/// Post-Vokabel — auf dem Postfach trägt sie die Stempelzeile
/// („MORGENPOST · TAG 137"), auf dem Zustellzettel der Rundenname.
/// Alles andere hier spricht Klartext.
enum PostfachL10n {
    static let table: [String: LText] = [
        // Station 1 im Tab-Balken (a11y-ID `tab.home` bleibt wörtlich;
        // nur der sichtbare Name wechselt — ENTSCHEID §2.1).
        "postfach.tab.home": LText(
            de: "Postfach",
            en: "Mailbox"),

        // Die drei Zustellrunden (Dossier §4) — Stempelzeile und
        // Zustellzettel lesen denselben Namen.
        "postfach.runde.morgenpost": LText(
            de: "Morgenpost",
            en: "Morning post"),
        "postfach.runde.tagespost": LText(
            de: "Tagespost",
            en: "Midday post"),
        "postfach.runde.nachtpost": LText(
            de: "Nachtpost",
            en: "Night post"),

        // Begrüßungszeile des Postfach-Kopfes (Redesign Welle 1,
        // REDESIGN.md §2.1): die Zustellrunde sagt zuerst Hallo, dann
        // kommen die Zahlen. Klartext, keine Post-Vokabel — das
        // Postdeutsch-Budget trägt weiterhin allein die Stempelzeile.
        "postfach.gruss.morgenpost": LText(
            de: "Guten Morgen",
            en: "Good morning"),
        "postfach.gruss.tagespost": LText(
            de: "Schönen Tag euch",
            en: "Good afternoon"),
        "postfach.gruss.nachtpost": LText(
            de: "Guten Abend",
            en: "Good evening"),

        // Briefschlitz-Ansage (VoiceOver, ganzer Satz — ENTSCHEID §4.6):
        // „Tagespost ist da: Frage des Tages."
        "postfach.briefschlitz.a11y": LText(
            de: "{runde} ist da: {titel}.",
            en: "{runde} is here: {titel}."),

        // Ablagekorb (§4.1 Zone 3): der Falt-Titel unterm Kartenbudget.
        // „Ablage" ist Büro-Klartext, keine Post-Vokabel — das Budget des
        // Screens trägt weiter allein die Stempelzeile.
        "postfach.ablage.titel": LText(
            de: "Ablage",
            en: "Tray"),

        // Zustellzettel (Accessory): rechts Runde + Status.
        // EN idiomatisch statt woertlich (Re-Eval: "Seal is waiting"
        // klang uebersetzt) — die Handlung, nicht das Objekt. Fix3 №6:
        // auch "Question waiting" klang uebersetzt — der Zettel spricht
        // die Einladung ("Waiting for you"), nicht den Aktenstand.
        "postfach.zettel.siegel": LText(
            de: "Siegel wartet",
            en: "Ready to reveal"),
        "postfach.zettel.offen": LText(
            de: "Frage offen",
            en: "Waiting for you"),
        "postfach.zettel.beantwortet": LText(
            de: "Beantwortet",
            en: "Answered"),
        // Ungepaart wartet keine Tagesfrage, sondern nur „Sendung Nr. 1"
        // (Fix3 №2) — der Zettel darf keine Frage versprechen, die es
        // noch nicht gibt; die Runde bleibt links davor stehen.
        "postfach.zettel.sendung1": LText(
            de: "Sendung Nr. 1 wartet",
            en: "Delivery no. 1 waiting"),

        // Dienstlicht im Kopf: Energie beider als Lampenschein-Punkt,
        // Antippen öffnet den heutigen Energie-Flow.
        "postfach.dienstlicht.a11y": LText(
            de: "Dienstlicht — Energie ansehen und setzen",
            en: "Duty light — view and set energy"),
        // Ehrlicher Leerzustand (Re-Eval №11): die unbeleuchtete Birne
        // sagt in Worten, dass heute noch kein Signal kam.
        "postfach.dienstlicht.leer": LText(
            de: "Noch kein Energie-Signal heute",
            en: "No energy signal yet today"),

        // Adoption A2 „Polaroid entwickeln" (ENTSCHEID §1.2).
        "postfach.polaroid.hinweis": LText(
            de: "Halten, bis das Bild erscheint",
            en: "Hold until the picture appears"),
        // Reduce Motion entwickelt per Tap — der Hinweis darf nicht vom
        // Halten lügen (Re-Eval №8).
        "postfach.polaroid.hinweis.tippen": LText(
            de: "Antippen zum Entwickeln",
            en: "Tap to develop"),
        "postfach.polaroid.a11y": LText(
            de: "Foto entwickeln",
            en: "Develop the photo"),
        "postfach.polaroid.entwickelt": LText(
            de: "Heute vor {wann}: {titel}",
            en: "{wann} ago today: {titel}"),
        // Zeitabstand des lokalen Flashbacks für die entwickelt-Ansage
        // („Heute vor {n} Tagen: …" — Re-Eval №7).
        "postfach.polaroid.wannTage": LText(
            de: "{n} Tagen",
            en: "{n} days"),

        // „Sendung Nr. 1" — die Pairing-Bühne als erste Zustellung
        // (Re-Eval №4, ENTSCHEID-Metapher statt „Nest"-Vokabular). Die
        // Post-Vokabel des Screens trägt der Stempelkopf des Bogens.
        "postfach.sendung1.stempel": LText(
            de: "Sendung Nr. 1",
            en: "Delivery no. 1"),
        // Die Empfängerzeile bleibt offen — der Name ist das, was fehlt.
        "postfach.sendung1.empfaenger": LText(
            de: "Für …",
            en: "For …"),
        "postfach.sendung1.aktion": LText(
            de: "Einladung senden",
            en: "Send invitation"),
        "postfach.sendung1.einladung": LText(
            de: "Sendung Nr. 1 liegt für uns bei SoooDreamy bereit — komm dazu.\nServer: {server}\nCode: {code}",
            en: "Delivery no. 1 is waiting for us on SoooDreamy — join me.\nServer: {server}\nCode: {code}"),

        // Senden-Knopf des Tagesfrage-Komponisten (Fix2-A №8): VoiceOver
        // sagt die Handlung, nie den SF-Symbolnamen („paperplane").
        "postfach.antwort.sendenA11y": LText(
            de: "Antwort senden",
            en: "Send answer"),

        // Telegramm-Leiste (Fix3 №4): eigene KURZE Chip-Titel — die
        // Vollformen („Umarmung", „Vermiss dich", „Stolz auf dich")
        // ellipsierten schon bei Regulärgröße in den engen 4-Spalten-
        // Chips („Umarm…", „Stolz a…"). Gemessen an „Kitzeln" (passt)
        // vs. „Umarmung" (bricht): einzelne Wörter bleiben unter dessen
        // Breite, längere Formen sind ZWEI kurze Wörter, die der
        // lineLimit(2)-Fallback sauber umbricht statt zu ellipsieren.
        // VoiceOver spricht weiter die vollen touch.*-Titel.
        "postfach.leiste.hug": LText(
            de: "Drück dich",
            en: "Hug"),
        "postfach.leiste.missyou": LText(
            de: "Fehlst mir",
            en: "Miss you"),
        "postfach.leiste.stolz": LText(
            de: "Stolz",
            en: "Proud"),
        "postfach.leiste.haltedurch": LText(
            de: "Halt durch",
            en: "Stay strong")
    ]
}
