import Foundation

/// Settings feature strings (German du-form + English) — new copy that the
/// Settings rework introduces. Established keys stay in `CoreStrings`; this
/// table only ADDS keys, it never shadows one (guarded by
/// `testNoDuplicateKeysAcrossTables`).
enum SettingsL10n {
    static let table: [String: LText] = [
        // The six still Amt sections (Neubau N4, ENTSCHEID §4.5).
        "settings.section.unserAmt": LText(de: "Unser Amt", en: "Our bureau"),
        "settings.section.zustelldienst": LText(de: "Zustelldienst", en: "Delivery service"),
        "settings.section.zweigstellen": LText(de: "Zweigstellen & Bezirke",
                                               en: "Branches & districts"),
        "settings.section.werkstatt": LText(de: "Werkstatt", en: "Workshop"),
        "settings.section.sicherung": LText(de: "Sicherung & Schlüssel",
                                            en: "Safeguard & keys"),
        "settings.section.betriebsbuch": LText(de: "Betriebsbuch", en: "Operations log"),

        // Zustellrunden switch (ENTSCHEID §4.6 respect rules): honest
        // about being stage-only and device-local.
        "settings.zustellrunden": LText(de: "Zustellrunden inszenieren",
                                        en: "Stage the delivery rounds"),
        "settings.zustellrundenHint": LText(
            de: "Morgen-, Tages- und Nachtpost rahmen euer Postfach — reine Bühne, nur auf diesem Gerät.",
            en: "Morning, day and night post frame your mailbox — pure staging, on this device only."
        ),

        // Setzkasten row under the delivery service.
        "settings.dailyqHint": LText(
            de: "Eigene Tagesfragen für euren gemeinsamen Fragen-Pool",
            en: "Your own daily questions for the shared question pool"
        ),

        // Betriebsbuch: the founding film row (its own wording — the
        // `cinematic.replay` key keeps its original onboarding voice).
        "settings.kinoReplay": LText(
            de: "Die Amtsgründung noch einmal ansehen",
            en: "Watch the bureau's founding again"
        ),

        // Danger zone — serious, not shouty.
        "settings.danger.footnote": LText(
            de: "Beide Schritte fragen erst nach. Nichts geht aus Versehen verloren.",
            en: "Both steps ask first. Nothing is lost by accident."
        ),
        "settings.danger.unpairHint": LText(
            de: "Löscht eure gemeinsamen Daten auf dem Server. Endgültig.",
            en: "Deletes your shared data on the server. For good."
        ),

        // Connection doctor entry — the honest one-liner.
        "settings.doctor.checking": LText(
            de: "Verbindung wird geprüft …",
            en: "Checking the connection …"
        ),

        // Notification sheet — section headers for a clear rhythm.
        "settings.notif.events": LText(
            de: "Ereignisse",
            en: "Events"
        ),
        "settings.notif.reminders": LText(
            de: "Erinnerungen",
            en: "Reminders"
        ),

        // Remote revoke (WS close 4001) — honest, no blame, clear next step.
        "devices.revokedRemote.notice": LText(
            de: "Dieses Gerät wurde von einem anderen Gerät abgemeldet. Melde dich neu an, wenn du es wieder nutzen möchtest.",
            en: "This device was signed out from another device. Sign in again if you want to keep using it."
        ),

        // About origin story (FXC-4 #12) — replaces the generic
        // "built with love" template footer with where the app actually
        // comes from. "made by Sonic0810" stays the credit above it.
        "settings.about.story": LText(
            de: "SoooDreamy ist als Geschenk entstanden: eine App für genau eine Beziehung — unsere. Kein Konzern, kein Abo, kein Tracking, nur ein kleiner eigener Server und die Frage, wie sich Nähe über Entfernung anfühlt. Alles hier wurde an Abenden und Wochenenden gebaut, für zwei Menschen.",
            en: "SoooDreamy began as a gift: an app for exactly one relationship — ours. No company, no subscription, no tracking, just a small self-hosted server and the question of what closeness feels like across a distance. Everything here was built on evenings and weekends, for two people."
        )
    ]
}
