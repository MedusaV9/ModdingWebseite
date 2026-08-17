import Foundation

/// Apple-Intelligence area strings (`ai.*`): consent sheet, Settings
/// toggle + honest availability reasons, letter workshop, "say it
/// gently" and the daily-question spark. German first, du/ihr-form.
enum IntelligenceL10n {
    static let table: [String: LText] = [
        // MARK: Consent sheet — the three-sentence on-device promise
        "ai.consent.title": LText(de: "Apple Intelligence", en: "Apple Intelligence"),
        "ai.consent.line1": LText(
            de: "Dein iPhone kann euch beim Formulieren helfen — mit Apple Intelligence, direkt auf diesem Gerät.",
            en: "Your iPhone can help you find the words — with Apple Intelligence, right on this device."),
        "ai.consent.line2": LText(
            de: "Nichts davon geht an Apple, an Dritte oder auf euren Server: Eure Worte verlassen das Gerät nie.",
            en: "None of it goes to Apple, to third parties or to your server: your words never leave the device."),
        "ai.consent.line3": LText(
            de: "Vorschläge sind immer nur Entwürfe. Gesendet wird nichts von allein.",
            en: "Suggestions are always just drafts. Nothing is ever sent on its own."),
        "ai.consent.accept": LText(de: "Apple Intelligence nutzen", en: "Use Apple Intelligence"),
        "ai.consent.later": LText(de: "Nicht jetzt", en: "Not now"),
        "ai.onDevice.badge": LText(de: "Bleibt auf dem Gerät", en: "Stays on this device"),

        // MARK: Settings (privacy/security card)
        "ai.settings.toggle": LText(de: "Apple Intelligence nutzen", en: "Use Apple Intelligence"),
        "ai.settings.hint": LText(
            de: "Formulier-Hilfen laufen komplett auf diesem Gerät. Eure Worte verlassen es nie.",
            en: "Writing helpers run entirely on this device. Your words never leave it."),

        // MARK: Honest availability reasons (Settings only — entry points
        // hide instead of explaining)
        "ai.availability.available": LText(
            de: "Apple Intelligence ist bereit.",
            en: "Apple Intelligence is ready."),
        "ai.availability.deviceNotEligible": LText(
            de: "Dieses Gerät unterstützt Apple Intelligence nicht — die Formulier-Hilfen bleiben deshalb ausgeblendet.",
            en: "This device doesn't support Apple Intelligence, so the writing helpers stay hidden."),
        "ai.availability.notEnabled": LText(
            de: "Apple Intelligence ist in den iOS-Einstellungen ausgeschaltet. Schalte es dort ein, dann erscheinen die Formulier-Hilfen hier.",
            en: "Apple Intelligence is turned off in iOS Settings. Turn it on there and the writing helpers will appear here."),
        "ai.availability.modelNotReady": LText(
            de: "Das Sprachmodell wird noch geladen. Schau in ein paar Minuten wieder vorbei.",
            en: "The language model is still downloading. Check back in a few minutes."),
        "ai.availability.unknown": LText(
            de: "Apple Intelligence ist gerade nicht verfügbar. Prüfe die iOS-Einstellungen.",
            en: "Apple Intelligence isn't available right now. Check iOS Settings."),

        // MARK: Letter-opening workshop
        "ai.workshop.entry": LText(de: "Schreibblockade?", en: "Writer's block?"),
        "ai.workshop.entryA11y": LText(
            de: "Drei Briefanfänge vorschlagen lassen",
            en: "Get three letter openings suggested"),
        "ai.workshop.title": LText(de: "Briefanfang-Werkstatt", en: "Opening workshop"),
        "ai.workshop.pick": LText(
            de: "Wähl einen Ton — dein iPhone schlägt dir drei Anfänge vor.",
            en: "Pick a tone — your iPhone will suggest three openings."),
        "ai.tone.tender": LText(de: "Zärtlich", en: "Tender"),
        "ai.tone.playful": LText(de: "Verspielt", en: "Playful"),
        "ai.tone.deep": LText(de: "Tief", en: "Deep"),
        "ai.workshop.generate": LText(de: "Drei Anfänge vorschlagen", en: "Suggest three openings"),
        "ai.workshop.regenerate": LText(de: "Drei neue vorschlagen", en: "Suggest three new ones"),
        "ai.workshop.useOpenerA11y": LText(
            de: "Diesen Anfang in den Brief übernehmen",
            en: "Use this opening in the letter"),
        "ai.workshop.failed": LText(
            de: "Der Vorschlag hat nicht geklappt. Dein Brief ist unverändert — versuch es gleich noch einmal.",
            en: "The suggestion didn't work out. Your letter is unchanged — try again in a moment."),
        "ai.workshop.guardrail": LText(
            de: "Dazu schlägt das Modell nichts vor. Formuliere den Gedanken etwas anders und versuch es erneut.",
            en: "The model won't make a suggestion for that. Phrase the thought a little differently and try again."),
        "ai.workshop.readyA11y": LText(
            de: "Drei Anfänge sind bereit",
            en: "Three openings are ready"),

        // MARK: "Say it gently"
        "ai.soften.entry": LText(de: "Sag es sanft", en: "Say it gently"),
        "ai.soften.entryA11y": LText(
            de: "Entwurf sanfter formulieren lassen",
            en: "Get a gentler wording of the draft"),
        "ai.soften.title": LText(de: "Sanfter gesagt", en: "Said more gently"),
        "ai.soften.hint": LText(
            de: "Dein Original bleibt stehen, bis du übernimmst.",
            en: "Your original stays until you adopt this."),
        "ai.soften.use": LText(de: "Diese Fassung übernehmen", en: "Use this wording"),
        "ai.soften.keep": LText(de: "Original behalten", en: "Keep the original"),
        "ai.soften.readyA11y": LText(
            de: "Die sanftere Fassung ist bereit",
            en: "The gentler wording is ready"),

        // MARK: Daily-question spark
        "ai.spark.title": LText(de: "Gemeinsamer Funke", en: "Shared spark"),
        "ai.spark.hint": LText(
            de: "Eine kleine Anschlussfrage aus euren beiden Antworten — gebaut auf diesem Gerät.",
            en: "A little follow-up question built from both your answers — made on this device."),
        "ai.spark.generate": LText(de: "Frage entdecken", en: "Reveal the question"),
        "ai.spark.again": LText(de: "Andere Frage (einmal am Tag)", en: "Another question (once a day)"),
        // Honest per-device framing (FXC-4 #10): the spark lives in this
        // device's storage only — it never syncs, so the copy must not
        // promise it follows the couple around.
        "ai.spark.kept": LText(de: "Dieser Funke bleibt heute bei euch — auf diesem Gerät",
                               en: "This spark stays with you today — on this device"),
        "ai.spark.failed": LText(
            de: "Die Anschlussfrage ist nicht entstanden. Eure Antworten sind sicher — versuch es noch einmal.",
            en: "The follow-up question didn't come together. Your answers are safe — try again."),
    ]
}
