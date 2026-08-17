import Foundation

/// Core UI strings (onboarding, tabs, home, settings, servers, errors).
/// Feature-specific strings live in ChatL10n / GamesL10n / MemoriesL10n.
///
/// Stimm-Charta der deutschen Sprachfassung (W8-Sprachpass, gilt für alle Tabellen):
///  1. Du/Ihr-Regel: „du“ für alles, was EINE Person an ihrem Gerät tut
///     (Sperre, Verbindung, Geräte-Einstellungen) — „ihr“ für alles Gemeinsame
///     (Inhalte, Erlebnisse, euer Server).
///  2. Wortliste: „nochmal“ ist die Markenstimme; „erneut“ nur technisch-nüchtern
///     (Migration, Sicherheit). „Zuhause“ groß als Nomen (tab.home), „zuhause“
///     klein als Adverb (server.setupSubtitle) — beides korrekt, nicht angleichen.
///     Feste Vokabeln: Serie (nie Streak), Tresor (nie Vault), Kritzel-Leinwand,
///     Träumeliste, Gutscheine, Umarmungen auf Vorrat, Morgengruß & Gutenachtgruß,
///     Zeitinseln, Home-Bildschirm, Einstellungen (Apple-Wording).
///     Regionale Entscheidungen: „Kniffel“/„Montagsmaler“ bleiben bewusst
///     (DE-Marken, in AT/CH bekannt); „Fotoautomat“ statt „Passbildautomat“.
///  3. Keine Versalien zur Betonung — Nachdruck liegt im Satzbau (Voranstellung,
///     Gedankenstrich) oder in einem zweiten kurzen Satz („Für immer.“).
///  4. Emoji-Leitlinie: höchstens eins pro String, hinter dem Satzzeichen; nie in
///     Fehlertiteln, nie bei destruktiven Confirms (L10nTests decken das); führende
///     Emoji nur bei eingehenden Ereignissen („☀️ {name} …“). Bewusste Ausnahme:
///     games.tod.spice* nutzt 🌶️ als Schärfe-Skala.
///  5. „Sooo…“-Dehnung ist die Marken-Signatur — nur in Feier-Momenten, nie in
///     Fehlern, bewusst selten (level.title.4, home.bothAnswered, soulmates).
///  6. What's-New beschreibt, was ihr davon habt — nie, wie es gebaut ist.
///  7. Fehlertexte folgen dem Dreiklang „Was passiert ist · Was sicher ist ·
///     Der Ausweg“ — der Ausweg als Button, nicht als Imperativ im Fließtext.
///  8. Namen im Genitiv über {nameGen} (L10n.genitive) — nie „{name}s“ kleben.
enum CoreStrings {
    static let table: [String: LText] = [
        // Common
        "common.ok": LText(de: "OK", en: "OK"),
        "common.cancel": LText(de: "Abbrechen", en: "Cancel"),
        "common.save": LText(de: "Speichern", en: "Save"),
        "common.delete": LText(de: "Löschen", en: "Delete"),
        "common.edit": LText(de: "Bearbeiten", en: "Edit"),
        "common.done": LText(de: "Fertig", en: "Done"),
        "common.retry": LText(de: "Nochmal versuchen", en: "Retry"),
        "common.clearSearch": LText(de: "Suche löschen", en: "Clear search"),
        "common.close": LText(de: "Schließen", en: "Close"),
        "common.add": LText(de: "Hinzufügen", en: "Add"),
        "common.error": LText(de: "Ups, das hat nicht geklappt", en: "Oops, that didn't work"),
        "common.loading": LText(de: "Lädt…", en: "Loading…"),
        "state.offline.title": LText(de: "Gerade offline", en: "Currently offline"),
        "state.offline.body": LText(
            de: "Diese Ansicht braucht den Paar-Server. Bereits geladene Inhalte bleiben sichtbar.",
            en: "This screen needs the couple server. Content already loaded remains visible."
        ),
        "state.failed.title": LText(de: "Das hat nicht geklappt", en: "That did not work"),
        "state.failed.body": LText(
            de: "Eure Daten sind nicht weg. Prüf kurz deine Verbindung und versuch es nochmal.",
            en: "Your data is not gone. Check your connection and try again."
        ),
        "common.back": LText(de: "Zurück", en: "Back"),
        "common.share": LText(de: "Teilen", en: "Share"),
        "common.copy": LText(de: "Kopieren", en: "Copy"),
        "common.copied": LText(de: "Kopiert", en: "Copied"),
        "common.today": LText(de: "Heute", en: "Today"),
        "common.days": LText(de: "Tage", en: "days"),
        "common.day": LText(de: "Tag", en: "day"),
        "handbook.title": LText(de: "SoooDreamy Handbuch", en: "SoooDreamy Manual"),
        "handbook.open": LText(de: "Hilfe für diesen Tab öffnen", en: "Open help for this tab"),
        "handbook.missing.title": LText(de: "Handbuch nicht verfügbar", en: "Manual unavailable"),
        "handbook.missing.body": LText(
            de: "Die gebündelte Hilfedatei fehlt. Du findest das vollständige Handbuch im Repository.",
            en: "The bundled help file is missing. You'll find the full manual in the repository."
        ),

        // Compact relative times (see L10n.relativeShort)
        "time.justNow": LText(de: "gerade eben", en: "just now"),
        "time.minutesAgo": LText(de: "vor {n} Min.", en: "{n} min ago"),
        "time.hoursAgo": LText(de: "vor {n} Std.", en: "{n} h ago"),
        "time.yesterday": LText(de: "gestern", en: "yesterday"),
        "time.daysAgo": LText(de: "vor {n} Tagen", en: "{n} days ago"),
        "common.you": LText(de: "Du", en: "You"),
        "common.partner": LText(de: "Schatz", en: "Sweetheart"),
        "common.send": LText(de: "Senden", en: "Send"),

        // Tabs — Neubau N4, the final station names of ENTSCHEID §2 (keys
        // stay literal, only the VALUES rename; station 1 shows
        // `postfach.tab.home` in RootView, `tab.home` remains for legacy
        // callers). The unread/awaiting VoiceOver labels speak the same
        // station names as the bar.
        "tab.home": LText(de: "Zuhause", en: "Home"),
        "tab.chat": LText(de: "Schreibstube", en: "Writing Desk"),
        "tab.play": LText(de: "Spieltisch", en: "Game Table"),
        "tab.us": LText(de: "Archiv", en: "Archive"),
        "tab.more": LText(de: "Amt", en: "Bureau"),
        "tab.chat.unreadA11y": LText(de: "Schreibstube, {n} ungelesen", en: "Writing Desk, {n} unread"),
        "tab.chat.unreadA11y.one": LText(de: "Schreibstube, eine ungelesene Nachricht", en: "Writing Desk, one unread message"),
        "tab.chat.unreadA11y.other": LText(de: "Schreibstube, {count} ungelesene Nachrichten", en: "Writing Desk, {count} unread messages"),
        "tab.play.awaitingA11y": LText(de: "Spieltisch, {n} wartet", en: "Game Table, {n} waiting"),
        "tab.play.awaitingA11y.one": LText(de: "Spieltisch, ein Spiel wartet auf dich", en: "Game Table, one game waiting for you"),
        "tab.play.awaitingA11y.other": LText(de: "Spieltisch, {count} Spiele warten auf dich", en: "Game Table, {count} games waiting for you"),

        // FullRelease N1-A: the "Heute-Zettel" bottom accessory of the
        // native tab bar (streak text reuses "home.streak").
        "accessory.dailyOpen": LText(de: "Frage des Tages wartet", en: "Daily question is waiting"),
        "accessory.dailyDone": LText(de: "Frage des Tages beantwortet", en: "Daily question answered"),
        "accessory.a11yHint": LText(de: "Öffnet das Postfach", en: "Opens the Mailbox"),
        "count.entries": LText(de: "{count} Einträge", en: "{count} entries"),
        "count.entries.one": LText(de: "ein Eintrag", en: "one entry"),
        "count.entries.other": LText(de: "{count} Einträge", en: "{count} entries"),

        // Onboarding
        "onboarding.title": LText(de: "SoooDreamy", en: "SoooDreamy"),
        "onboarding.tagline": LText(de: "Die App für euch zwei. Euer Server, eure Daten, eure Welt.",
                                    en: "The app for the two of you. Your server, your data, your world."),
        "onboarding.feature1": LText(de: "Herzklopfen senden — mit echter Haptik", en: "Send heartbeats — with real haptics"),
        "onboarding.feature2": LText(de: "Chat, Fotos, Sprachnachrichten & Kritzel-Leinwand", en: "Chat, photos, voice notes & doodle canvas"),
        "onboarding.feature3": LText(de: "Spiele, Fragen des Tages & Date-Ideen", en: "Games, daily questions & date ideas"),
        "onboarding.feature4": LText(de: "Widgets & Live-Countdowns für eure Momente", en: "Widgets & live countdowns for your moments"),
        "onboarding.start": LText(de: "Los geht's", en: "Let's go"),
        "onboarding.language": LText(de: "Sprache", en: "Language"),
        // v10 paged onboarding (pages defined in OnboardingScript)
        "onboarding.next": LText(de: "Weiter", en: "Next"),
        "onboarding.skip": LText(de: "Überspringen", en: "Skip"),
        "onboarding.pageA11y": LText(de: "Seite {current} von {total}", en: "Page {current} of {total}"),
        "onboarding.page.together.title": LText(de: "Alles für euch zwei", en: "Everything for the two of you"),
        "onboarding.page.together.body": LText(de: "Kein Feed, keine Fremden — nur ihr beide und eure kleinen Momente.",
                                               en: "No feed, no strangers — just the two of you and your little moments."),
        "onboarding.page.server.title": LText(de: "Euer Server, eure Daten", en: "Your server, your data"),
        "onboarding.page.server.body": LText(de: "SoooDreamy läuft auf eurem eigenen kleinen Server — niemand sonst liest mit.",
                                             en: "SoooDreamy runs on your own little server — nobody else can read along."),
        "onboarding.page.server.point1": LText(de: "Ende-zu-eurem-Server: Daten bleiben bei euch", en: "End-to-your-server: data stays with you"),
        "onboarding.page.server.point2": LText(de: "Läuft zuhause, auf einem Raspberry Pi oder in der Cloud", en: "Runs at home, on a Raspberry Pi or in the cloud"),
        "onboarding.page.server.point3": LText(de: "Kein Konto bei uns, kein Tracking, keine Werbung", en: "No account with us, no tracking, no ads"),
        // Honest-promises pass (onboarding eval): "we help you back" instead
        // of absolutes — sideload signing can degrade iCloud sync, so the
        // copy promises the SAFETY NET, not a guarantee.
        "onboarding.page.safety.title": LText(de: "Wir helfen euch zurück", en: "We help you back in"),
        "onboarding.page.safety.body": LText(de: "Beim Koppeln bekommst du einen Wiederherstellungs-Schlüssel — dein Weg zurück, wenn dem Handy etwas passiert.",
                                             en: "Pairing gives you a recovery key — your way back in if something happens to your phone."),
        "onboarding.page.safety.point1": LText(de: "Der Schlüssel liegt in deinem Schlüsselbund — mit iCloud-Sync, wo dein Gerät ihn erlaubt", en: "The key lives in your keychain — iCloud-synced where your device allows it"),
        "onboarding.page.safety.point2": LText(de: "Neues Handy? „Wieder verbinden“ mit Schlüssel oder Zettel", en: "New phone? “Reconnect” with your key or your paper note"),
        "onboarding.page.safety.point3": LText(de: "Und zur Not kann dein Schatz dich zurückholen", en: "And if all else fails, your partner can bring you back"),
        // Welle 7 [29]: the closing guide page — title/body live here;
        // the three route steps + the second-device line moved to
        // OnboardingL10n (Fix-Runde 3, Kino-Befund 3: they speak the
        // Postamt grammar now, and the onboarding table owns them).
        "onboarding.page.guide.title": LText(de: "So legt ihr los", en: "How to get started"),
        "onboarding.page.guide.body": LText(de: "Drei Schritte, dann seid ihr drin — alles Weitere entsteht zu zweit.",
                                            en: "Three steps and you're in — everything else unfolds together."),
        // Welle 7 [29]: demo mode — enter without a server, leave cleanly.
        "onboarding.demo.enter": LText(de: "Erst mal ansehen", en: "Just look around first"),
        "onboarding.demo.enterHintA11y": LText(de: "Öffnet die App mit einem Beispiel-Paar, ganz ohne Server",
                                               en: "Opens the app with a sample couple, no server needed"),
        "demo.badge.exit": LText(de: "Eigenen Server verbinden", en: "Connect your own server"),
        "demo.exit.title": LText(de: "Demo beenden?", en: "Leave the demo?"),
        "demo.exit.body": LText(de: "Alles hier drin ist Beispiel-Inhalt und verschwindet spurlos. Mit eurem eigenen Server beginnt ihr frisch zu zweit.",
                                en: "Everything in here is sample content and vanishes without a trace. With your own server you start fresh as a couple."),
        "demo.exit.connect": LText(de: "Eigenen Server verbinden", en: "Connect my own server"),
        "demo.exit.keepLooking": LText(de: "Weiter ansehen", en: "Keep looking around"),
        "demo.badge.a11y": LText(de: "Demo-Modus aktiv", en: "Demo mode active"),
        "demo.badge.a11yHint": LText(de: "Antippen, um den eigenen Server zu verbinden",
                                     en: "Tap to connect your own server"),
        "language.system": LText(de: "System", en: "System"),
        "language.de": LText(de: "Deutsch", en: "German"),
        "language.en": LText(de: "Englisch", en: "English"),

        // Server setup
        "server.setupTitle": LText(de: "Euer Server", en: "Your server"),
        "server.setupSubtitle": LText(de: "SoooDreamy läuft auf eurem eigenen kleinen Server — zuhause, auf einem Raspberry Pi oder in der Cloud. Tragt hier seine Adresse ein.",
                                      en: "SoooDreamy runs on your own little server — at home, on a Raspberry Pi or in the cloud. Enter its address here."),
        "server.name": LText(de: "Name (z. B. „Zuhause“)", en: "Name (e.g. “Home”)"),
        "server.url": LText(de: "Adresse, z. B. 192.168.1.20:4321", en: "Address, e.g. 192.168.1.20:4321"),
        "server.test": LText(de: "Verbindung testen", en: "Test connection"),
        "server.testOK": LText(de: "Verbunden — {name} ({version})", en: "Connected — {name} ({version})"),
        "server.testFail": LText(de: "Keine Verbindung: {error}", en: "No connection: {error}"),
        "server.testFailATS": LText(de: "Verbindung fehlgeschlagen: Prüfe die Adresse und stelle sicher, dass der Server läuft.",
                                    en: "Connection failed: Check the address and ensure the server is running."),
        "server.invalidURL": LText(de: "Das sieht nicht wie eine gültige Adresse aus", en: "That doesn't look like a valid address"),
        "server.buildBadge": LText(de: "App-Build {version} · HTTP freigeschaltet", en: "App build {version} · HTTP enabled"),
        "server.add": LText(de: "Server hinzufügen", en: "Add server"),
        "server.manage": LText(de: "Server verwalten", en: "Manage servers"),
        "server.active": LText(de: "Aktiv", en: "Active"),
        "server.switch": LText(de: "Zu diesem Server wechseln", en: "Switch to this server"),
        "server.switched": LText(de: "Server gewechselt: {name}", en: "Switched server: {name}"),
        "server.delete": LText(de: "Server entfernen", en: "Remove server"),
        "server.deleteConfirm": LText(de: "„{name}“ wirklich entfernen? Die Kopplung auf diesem Server geht auf diesem Gerät verloren.",
                                      en: "Really remove “{name}”? Your pairing on that server will be lost on this device."),
        "server.paired": LText(de: "Gekoppelt", en: "Paired"),
        "server.notPaired": LText(de: "Noch nicht gekoppelt", en: "Not paired yet"),
        "server.hint": LText(de: "Öffentlich oder privat: http:// und https:// werden unterstützt (z. B. http://192.168.1.20:4321). Euer Server braucht kein https — schlichtes http:// reicht völlig.",
                             en: "Public or private: http:// and https:// are supported (e.g. http://192.168.1.20:4321). Your server doesn't need https — plain http:// is perfectly fine."),
        "server.continue": LText(de: "Weiter", en: "Continue"),
        "server.pickTitle": LText(de: "Mit welchem Server?", en: "Which server?"),

        // Pairing
        "pairing.title": LText(de: "Findet zueinander", en: "Find each other"),
        "pairing.subtitle": LText(de: "Du erstellst euer Paar — dein Schatz tritt mit dem Code bei.",
                                  en: "You create your couple — your sweetheart joins with the code."),
        "pairing.create": LText(de: "Paar erstellen", en: "Create couple"),
        "pairing.join": LText(de: "Mit Code beitreten", en: "Join with code"),
        "pairing.codePlaceholder": LText(de: "Code, z. B. H4XK9P", en: "Code, e.g. H4XK9P"),
        "pairing.yourCode": LText(de: "Euer Code", en: "Your code"),
        "pairing.shareCode": LText(de: "Schick den Code deinem Schatz", en: "Send the code to your sweetheart"),
        "pairing.waiting": LText(de: "Warte auf deinen Schatz…", en: "Waiting for your sweetheart…"),
        "pairing.scanQR": LText(de: "QR-Code scannen", en: "Scan QR code"),
        "pairing.showQR": LText(de: "QR-Code zeigen", en: "Show QR code"),
        "pairing.partnerJoined": LText(de: "{name} ist da — jetzt seid ihr zwei",
                                       en: "{name} is here — now it's the two of you"),
        "pairing.unknownCode": LText(de: "Diesen Code kennt der Server nicht", en: "The server doesn't know this code"),
        "pairing.coupleFull": LText(de: "Dieses Paar ist schon komplett", en: "This couple is already complete"),
        // v10 rejoin (third pairing path — re-attach your own slot)
        "pairing.rejoin": LText(de: "Wieder verbinden", en: "Reconnect"),
        "pairing.rejoin.title": LText(de: "Willkommen zurück", en: "Welcome back"),
        // Sharpened (onboarding eval): rejoin = the OLD device is no longer
        // usable; the link path below is for an ADDITIONAL device.
        "pairing.rejoin.subtitle": LText(de: "Altes Gerät weg oder App neu installiert? Hol dir euren gemeinsamen Platz zurück — eure Inhalte liegen sicher auf eurem Server.",
                                         en: "Old device gone or fresh install? Get your shared place back — your content is safe on your server."),
        "pairing.rejoin.keyPlaceholder": LText(de: "Wiederherstellungs-Schlüssel (rec_…)", en: "Recovery key (rec_…)"),
        "pairing.rejoin.keyFound": LText(de: "Schlüssel im Schlüsselbund gefunden — einfach auf „Wieder verbinden“ tippen.",
                                         en: "Key found in your keychain — just tap “Reconnect”."),
        "pairing.rejoin.replaceToggle": LText(de: "Ich habe einen Ersatz-Code von meinem Schatz", en: "I have a replace code from my love"),
        "pairing.rejoin.replacePlaceholder": LText(de: "Ersatz-Code", en: "Replace code"),
        // The radically simple reconnect screen (max two choices)
        "pairing.rejoin.reassure": LText(
            de: "Keine Sorge: Eure Fotos, eure Serie und alle Erinnerungen sind sicher auf eurem Server. Wir verbinden dich nur wieder mit eurem Zuhause.",
            en: "Don't worry: your photos, your streak and every memory are safe on your server. We're just reconnecting you with your home."),
        "pairing.rejoin.scan": LText(de: "QR-Code scannen", en: "Scan a QR code"),
        "pairing.rejoin.scan.sub": LText(
            de: "Ein Scan und ihr seid wieder verbunden — vom Handy deines Lieblingsmenschen oder aus dem Admin-Panel.",
            en: "One scan and you're back together — from your partner's phone or the admin panel."),
        "pairing.rejoin.type": LText(de: "Code eintippen", en: "Type it in"),
        "pairing.rejoin.type.sub": LText(
            de: "Paar-Code plus Schlüssel oder Ersatz-Code — ganz in deinem Tempo.",
            en: "Couple code plus key or replace code — at your own pace."),
        "pairing.rejoin.scanInstead": LText(de: "Oder lieber einen QR-Code scannen?", en: "Rather scan a QR code instead?"),
        "pairing.rejoin.backToOptions": LText(de: "Zurück zur Auswahl", en: "Back to the choices"),
        // Welle 7 [30]: pairing/link ceremony (color-merge arrival moment)
        "pairing.ceremony.pairedTitle": LText(de: "Ihr seid verbunden", en: "You're connected"),
        "pairing.ceremony.linkedTitle": LText(de: "Alles ist hier", en: "Everything's here"),
        "pairing.ceremony.a11y": LText(de: "{a} und {b} sind jetzt verbunden",
                                       en: "{a} and {b} are now connected"),
        "pairing.ceremony.skipA11y": LText(de: "Antippen zum Überspringen", en: "Tap to skip"),
        // sooodreamy://rejoin deep links (QR-scan login)
        "rejoin.link.connecting": LText(de: "Einen Moment — wir verbinden dich wieder …", en: "One moment — reconnecting you…"),
        "rejoin.link.success": LText(de: "Da seid ihr wieder — alles ist noch da.",
                                     en: "There you are again — everything is still here."),
        "rejoin.link.invalid": LText(de: "Dieser Link oder Code ist leider nicht gültig.", en: "That link or code isn't valid, sadly."),
        "rejoin.link.prefilled": LText(de: "Fast geschafft — wir haben schon alles ausgefüllt, was im Code steckte.",
                                       en: "Almost there — we prefilled everything the code contained."),
        "pairing.rejoin.help": LText(de: "Der Wiederherstellungs-Schlüssel liegt in deinem Schlüsselbund (oder auf deinem Zettel). Ohne Schlüssel kann dein Schatz in den Einstellungen einen Ersatz-Code für dich erzeugen.",
                                     en: "Your recovery key lives in your keychain (or on your piece of paper). Without it, your partner can create a replace code for you in Settings."),
        "pairing.rejoin.badKey": LText(de: "Dieser Schlüssel passt zu keinem von euch beiden", en: "This key doesn't match either of you"),
        "pairing.rejoin.badReplace": LText(de: "Ersatz-Code unbekannt, abgelaufen oder schon benutzt", en: "Replace code unknown, expired or already used"),
        "pairing.rejoin.revoked": LText(de: "Diese Sitzung wurde ersetzt — bitte deinen Schatz um einen Ersatz-Code", en: "This session was replaced — ask your partner for a replace code"),
        "pairing.coupleFullRejoin": LText(de: "Ihr seid schon zu zweit — nimm „Wieder verbinden“, um deinen Platz zurückzuholen",
                                          en: "You're already two — use “Reconnect” to get your spot back"),
        "pairing.yourName": LText(de: "Dein Name", en: "Your name"),
        "pairing.avatar": LText(de: "Dein Emoji", en: "Your emoji"),
        "pairing.color": LText(de: "Deine Farbe", en: "Your color"),
        "pairing.profileTitle": LText(de: "Das bist du", en: "This is you"),
        "pairing.qrHint": LText(de: "Dein Schatz kann den Code auch scannen — Server & Code in einem.",
                                en: "Your sweetheart can also scan the code — server & code in one."),
        "pairing.shareInvite": LText(
            de: "Ich hab uns ein Postfach auf SoooDreamy eröffnet — komm dazu.\nServer: {server}\nCode: {code}",
            en: "I opened us a mailbox on SoooDreamy — come join me.\nServer: {server}\nCode: {code}"
        ),
        // P2-9: VoiceOver on the very first impression — code entry, QR, share.
        "pairing.codeFieldA11y": LText(de: "Paar-Code", en: "Couple code"),
        "pairing.codeFieldHintA11y": LText(de: "Sechs Zeichen — Buchstaben und Ziffern",
                                           en: "Six characters — letters and digits"),
        "pairing.yourCodeA11y": LText(de: "Euer Paar-Code: {code}", en: "Your couple code: {code}"),
        "pairing.qrShowHintA11y": LText(de: "Zeigt einen QR-Code, den dein Schatz scannen kann",
                                        en: "Shows a QR code your sweetheart can scan"),
        "pairing.qrImageA11y": LText(de: "QR-Code zum Beitreten — Server und Code in einem",
                                     en: "QR code to join — server and code in one"),
        "pairing.shareHintA11y": LText(de: "Teilt Server und Code mit deinem Schatz",
                                       en: "Shares server and code with your sweetheart"),
        "pairing.serverA11y": LText(de: "Server: {name}", en: "Server: {name}"),
        "pairing.serverHintA11y": LText(de: "Zum Wechseln tippen", en: "Tap to switch"),
        "pairing.avatarPickA11y": LText(de: "Emoji {emoji}", en: "Emoji {emoji}"),
        "pairing.colorPickA11y": LText(de: "Farbe {name}", en: "Color {name}"),

        // Welle 3: Multi-Device — the fourth pairing path ("I already have
        // a device") + the device manager in Settings.
        "pairing.link": LText(de: "Ich habe schon ein Gerät", en: "I already have a device"),
        "pairing.link.sub": LText(de: "Weiteres Gerät dazuholen — dein bisheriges bleibt angemeldet. Mit einem Code von dort.",
                                  en: "Add another device — your current one stays signed in. With a code from there."),
        "pairing.link.title": LText(de: "Noch ein Gerät für dich", en: "Another device for you"),
        "pairing.link.subtitle": LText(de: "Dieses Gerät kommt einfach zu deinem Platz dazu — dein bisheriges bleibt angemeldet. Erzeuge dort einen Code und gib ihn hier ein.",
                                       en: "This device simply joins your spot — your current one stays signed in. Create a code there and enter it here."),
        "pairing.link.reassure": LText(
            de: "Alles bleibt, wie es ist: gleiches Paar, gleicher Platz, alle Erinnerungen. Dein Schatz muss nichts tun.",
            en: "Everything stays as it is: same couple, same spot, every memory. Your partner doesn't need to do a thing."),
        "pairing.link.action": LText(de: "Gerät koppeln", en: "Link this device"),
        "pairing.link.codePlaceholder": LText(de: "Geräte-Code, z. B. H4XK9PWZ", en: "Device code, e.g. H4XK9PWZ"),
        "pairing.link.codeA11y": LText(de: "Geräte-Code — acht Zeichen", en: "Device code — eight characters"),
        "pairing.link.help": LText(de: "Den Code findest du auf deinem verbundenen Gerät unter Einstellungen → Geräte → „Gerät hinzufügen“. Er gilt 10 Minuten und funktioniert genau einmal.",
                                   en: "You'll find the code on your connected device under Settings → Devices → “Add a device”. It's valid for 10 minutes and works exactly once."),

        // Device manager (Settings → Devices)
        "devices.title": LText(de: "Geräte", en: "Devices"),
        "devices.settingsHint": LText(de: "iPhone & iPad gleichzeitig — koppeln und verwalten",
                                      en: "iPhone & iPad at once — link and manage"),
        "devices.section.list": LText(de: "Deine Geräte", en: "Your devices"),
        "devices.count": LText(de: "{count} von {max} Plätzen belegt", en: "{count} of {max} seats taken"),
        "devices.thisDevice": LText(de: "Dieses Gerät", en: "This device"),
        "devices.fallbackName": LText(de: "Unbenanntes Gerät", en: "Unnamed device"),
        "devices.lastUsed": LText(de: "Zuletzt aktiv {time}", en: "Last active {time}"),
        "devices.linkedAt": LText(de: "Verbunden {time}", en: "Linked {time}"),
        "devices.revoke": LText(de: "Abmelden", en: "Sign out"),
        "devices.revoking": LText(de: "Wird abgemeldet …", en: "Signing out…"),
        "devices.revokeConfirm": LText(de: "Dieses Gerät abmelden?", en: "Sign out this device?"),
        "devices.revokedTag": LText(de: "Abgemeldet", en: "Signed out"),
        "devices.revokedToast": LText(de: "{name} wurde abgemeldet.", en: "{name} was signed out."),
        "devices.empty.title": LText(de: "Noch keine Geräte", en: "No devices yet"),
        "devices.empty.message": LText(de: "Sobald du ein Gerät koppelst, erscheint es hier.",
                                       en: "As soon as you link a device, it shows up here."),
        "devices.offline.title": LText(de: "Gerade keine Verbindung", en: "No connection right now"),
        "devices.offline.message": LText(de: "Deine Geräteliste kommt zurück, sobald euer Server wieder erreichbar ist.",
                                         en: "Your device list returns as soon as your server is reachable again."),
        "devices.failed.title": LText(de: "Liste konnte nicht laden", en: "Couldn't load the list"),
        "devices.failed.message": LText(de: "Das hat gerade nicht geklappt — versuch es gleich noch einmal.",
                                        en: "That didn't work just now — try again in a moment."),

        // Add-device hand-off (one-time code + QR + countdown)
        "devices.add": LText(de: "Gerät hinzufügen", en: "Add a device"),
        "devices.add.hint": LText(de: "Hol dein iPad oder Zweithandy dazu: Erzeuge einen Einmal-Code und scanne ihn auf dem neuen Gerät — fertig.",
                                  en: "Bring your iPad or second phone on board: create a one-time code and scan it on the new device — done."),
        "devices.add.action": LText(de: "Einmal-Code erzeugen", en: "Create one-time code"),
        "devices.add.minting": LText(de: "Wird erzeugt …", en: "Creating…"),
        "devices.add.again": LText(de: "Neuen Code erzeugen", en: "Create a new code"),
        "devices.add.expired": LText(de: "Der Code ist abgelaufen — macht nichts, ein neuer ist einen Tipp entfernt.",
                                     en: "The code expired — no worries, a fresh one is a tap away."),
        "devices.add.expires": LText(de: "Gültig noch {time}", en: "Valid for {time}"),
        "devices.add.tapToCopy": LText(de: "Tippen zum Kopieren", en: "Tap to copy"),
        "devices.add.scanHint": LText(de: "Auf dem neuen Gerät: SoooDreamy öffnen → „Ich habe schon ein Gerät“ → Code scannen oder eintippen.",
                                      en: "On the new device: open SoooDreamy → “I already have a device” → scan or type the code."),
        "devices.add.qrA11y": LText(de: "QR-Code zum Koppeln — Server und Geräte-Code in einem",
                                    en: "QR code for linking — server and device code in one"),
        "devices.add.codeA11y": LText(de: "Geräte-Code: {code}", en: "Device code: {code}"),

        // sooodreamy://link deep links + link-code redemption
        "devices.linkedToast": LText(de: "Neues Gerät verbunden: {name}", en: "New device linked: {name}"),
        "devices.link.connecting": LText(de: "Einen Moment — wir koppeln dieses Gerät …",
                                         en: "One moment — linking this device…"),
        "devices.link.success": LText(de: "Geschafft — dieses Gerät gehört jetzt zu dir.",
                                      en: "Done — this device is yours now."),
        "devices.link.invalid": LText(de: "Dieser Geräte-Link ist leider nicht gültig.",
                                      en: "That device link isn't valid, sadly."),
        "devices.link.prefilled": LText(de: "Fast geschafft — der Code ist schon eingetragen.",
                                        en: "Almost there — the code is already filled in."),
        "devices.link.alreadyPaired": LText(de: "Dieses Gerät ist hier schon verbunden — alles gut.",
                                            en: "This device is already connected here — all good."),
        "devices.link.badCode": LText(de: "Diesen Geräte-Code kennt der Server nicht.",
                                      en: "The server doesn't know this device code."),
        "devices.link.expired": LText(de: "Der Geräte-Code ist abgelaufen — erzeuge auf deinem verbundenen Gerät einfach einen neuen.",
                                      en: "The device code expired — just create a fresh one on your connected device."),
        "devices.link.consumed": LText(de: "Dieser Code wurde schon benutzt — jeder Code funktioniert genau einmal.",
                                       en: "That code was already used — each code works exactly once."),
        "devices.link.unknownCouple": LText(de: "Zu diesem Code gibt es kein Paar mehr.",
                                            en: "There's no couple behind that code anymore."),
        "devices.link.tooManySessions": LText(de: "Alle Geräte-Plätze sind belegt — melde in der Geräteverwaltung erst ein altes Gerät ab.",
                                              en: "All device seats are taken — sign out an old device in device management first."),
        "devices.link.rateLimited": LText(de: "Kurz durchatmen — zu viele Versuche. Probier es gleich noch einmal.",
                                          en: "Take a breath — too many attempts. Try again in a moment."),

        // VoiceOver names for the fixed member palette (silent colored
        // circles are unusable for a blind partner).
        "color.rose": LText(de: "Rosa", en: "Rose"),
        "color.purple": LText(de: "Lila", en: "Purple"),
        "color.indigo": LText(de: "Indigo", en: "Indigo"),
        "color.sky": LText(de: "Himmelblau", en: "Sky blue"),
        "color.mint": LText(de: "Mint", en: "Mint"),
        "color.gold": LText(de: "Gold", en: "Gold"),
        "color.orange": LText(de: "Orange", en: "Orange"),
        "color.coral": LText(de: "Koralle", en: "Coral"),

        // Home / dashboard — the header line is one whole sentence template
        // (commandment 9), not a number glued to a fragment.
        "home.daysTogether.full": LText(de: "{n} Tage zusammen", en: "{n} days together"),
        // Poststempel-Prägung auf dem Briefbogen-Hero (Papier & Licht):
        // gesetzt in Typo.anschrift (Kapitälchen), liest sich als „TAG {n}“
        // — die Zahl ist daysTogether, dieselbe Biografie-Zahl wie im Kopf.
        "home.stamp.day": LText(de: "Tag {n}", en: "Day {n}"),
        "home.sinceHint": LText(de: "Jahrestag in den Einstellungen setzen", en: "Set your anniversary in settings"),
        "home.online": LText(de: "online", en: "online"),
        "home.offline": LText(de: "offline", en: "offline"),
        "home.lastSeen": LText(de: "zuletzt {time}", en: "last seen {time}"),
        "home.yourMood": LText(de: "Deine Stimmung", en: "Your mood"),
        "home.moodOf": LText(de: "{name} fühlt sich…", en: "{name} is feeling…"),
        "home.noMood": LText(de: "Noch keine Stimmung geteilt", en: "No mood shared yet"),
        "home.setMood": LText(de: "Stimmung teilen", en: "Share mood"),
        "home.moodNote": LText(de: "Kleine Notiz dazu? (optional)", en: "A little note? (optional)"),
        "home.sendLove": LText(de: "Schick Liebe", en: "Send love"),
        "home.dailyQuestion": LText(de: "Frage des Tages", en: "Question of the day"),
        "home.answerNow": LText(de: "Jetzt antworten", en: "Answer now"),
        "home.waitingPartnerAnswer": LText(de: "Warte auf {nameGen} Antwort…", en: "Waiting for {nameGen} answer…"),
        "home.bothAnswered": LText(de: "Sooo gut — ihr habt beide geantwortet", en: "Sooo good — you both answered"),
        "home.shareAnswers": LText(de: "Antworten in den Chat", en: "Send answers to chat"),
        "home.dailyShareHeader": LText(de: "❓ Frage des Tages:", en: "❓ Question of the day:"),
        "home.streak": LText(de: "{n} Tage in Serie", en: "{n}-day streak"),
        "home.nextEvent": LText(de: "Als Nächstes", en: "Up next"),
        "home.inDays": LText(de: "in {n} Tagen", en: "in {n} days"),
        "home.tomorrow": LText(de: "morgen", en: "tomorrow"),
        "home.todayBang": LText(de: "Heute ist es so weit", en: "Today is the day"),
        "home.touchSent": LText(de: "{emoji} ist unterwegs", en: "{emoji} is on its way"),
        "home.heartTapHint": LText(de: "Tipp aufs Herz, um Herzklopfen zu senden", en: "Tap the heart to send a heartbeat"),

        // Touches
        "touch.heartbeat": LText(de: "Herzklopfen", en: "Heartbeat"),
        "touch.kiss": LText(de: "Kuss", en: "Kiss"),
        "touch.hug": LText(de: "Umarmung", en: "Hug"),
        "touch.missyou": LText(de: "Vermiss dich", en: "Miss you"),
        "touch.tickle": LText(de: "Kitzeln", en: "Tickle"),
        "touch.thinking": LText(de: "Denk an dich", en: "Thinking of you"),
        "touch.received.heartbeat": LText(de: "{name} schickt dir Herzklopfen", en: "{name} sends you a heartbeat"),
        "touch.received.kiss": LText(de: "{name} küsst dich", en: "{name} kisses you"),
        "touch.received.hug": LText(de: "{name} umarmt dich ganz fest", en: "{name} hugs you tight"),
        "touch.received.missyou": LText(de: "{name} vermisst dich", en: "{name} misses you"),
        "touch.received.tickle": LText(de: "{name} kitzelt dich", en: "{name} tickles you"),
        "touch.received.thinking": LText(de: "{name} denkt gerade an dich", en: "{name} is thinking of you"),
        // Post & Sendungen (FullRelease P6-B): two new touch kinds
        "touch.stolz": LText(de: "Stolz auf dich", en: "Proud of you"),
        "touch.haltedurch": LText(de: "Halt durch", en: "Hang in there"),
        "touch.received.stolz": LText(de: "{name} ist stolz auf dich", en: "{name} is proud of you"),
        "touch.received.haltedurch": LText(de: "{name} sagt: Halt durch", en: "{name} says: hang in there"),
        // Echo replies: one tap sends a received touch back
        "touch.echo.action": LText(de: "Zurückschicken", en: "Send back"),
        "touch.echo.sent": LText(de: "Dein Echo ist unterwegs", en: "Your echo is on its way"),
        "touch.echo.received": LText(de: "{name} schickt deine Berührung zurück", en: "{name} sends your touch back"),
        // Post-Station: the two counters in the send-love grid
        "post.station.zeitpost": LText(de: "Zeitpost", en: "Timed post"),
        "post.station.zeitpostA11y": LText(de: "Zeitpost planen — eine Sendung für später",
                                           en: "Schedule a timed post — a delivery for later"),
        "post.station.journal": LText(de: "Verlauf", en: "Journal"),
        "post.station.journalA11y": LText(de: "Posteingang der Zärtlichkeiten öffnen",
                                          en: "Open the journal of affection"),
        // Zeitpost composer & open deliveries
        "post.zeitpost.title": LText(de: "Zeitpost", en: "Timed post"),
        "post.zeitpost.body": LText(
            de: "Schick {name} eine kleine Sendung in die Zukunft — 5 Minuten bis 7 Tage voraus.",
            en: "Send {name} a little delivery into the future — 5 minutes to 7 days ahead."),
        "post.zeitpost.kind.touch": LText(de: "Berührung", en: "Touch"),
        "post.zeitpost.kind.pulse": LText(de: "Puls", en: "Pulse"),
        "post.zeitpost.kind.note": LText(de: "Notiz", en: "Note"),
        "post.zeitpost.notePlaceholder": LText(de: "Ein paar liebe Worte …",
                                               en: "A few loving words …"),
        "post.zeitpost.noteCount": LText(de: "{n} / {max}", en: "{n} / {max}"),
        "post.zeitpost.deliverAt": LText(de: "Ankunft", en: "Arrives"),
        "post.zeitpost.send": LText(de: "Aufgeben", en: "Post it"),
        "post.zeitpost.sentToast": LText(de: "Zeitpost aufgegeben — sie bleibt geheim, bis sie ankommt",
                                         en: "Timed post on its way — it stays secret until it arrives"),
        "post.zeitpost.queuedToast": LText(
            de: "Gerade kein Netz — deine Zeitpost wird aufgegeben, sobald du wieder online bist.",
            en: "No connection right now — your timed post will be posted once you're back online."),
        "post.zeitpost.secretHint": LText(de: "{name} sieht nichts davon, bis die Sendung ankommt.",
                                          en: "{name} won't see a thing until it arrives."),
        "post.zeitpost.limitHint": LText(
            de: "Alle fünf Plätze sind belegt — lass erst eine Sendung ankommen oder nimm eine zurück.",
            en: "All five slots are taken — let one arrive or take one back first."),
        "post.zeitpost.open.title": LText(de: "Unterwegs ({n} von {max})",
                                          en: "On their way ({n} of {max})"),
        "post.zeitpost.arrives": LText(de: "Kommt an: {date}", en: "Arrives: {date}"),
        "post.zeitpost.cancel": LText(de: "Zurücknehmen", en: "Take back"),
        "post.zeitpost.canceledToast": LText(de: "Zeitpost zurückgenommen", en: "Timed post taken back"),
        // Journal of affection
        "post.journal.title": LText(de: "Posteingang der Zärtlichkeiten", en: "Journal of affection"),
        "post.journal.hint": LText(de: "Die letzten 30 Tage eurer kleinen Sendungen.",
                                   en: "The last 30 days of your little deliveries."),
        "post.journal.empty": LText(
            de: "Noch keine Sendungen — die erste Berührung eröffnet euer Journal.",
            en: "No deliveries yet — the first touch opens your journal."),
        "post.journal.me": LText(de: "Du", en: "You"),
        "post.journal.echoBadge": LText(de: "Echo", en: "Echo"),
        "post.journal.zeitpostBadge": LText(de: "Zeitpost", en: "Timed post"),
        "post.journal.unknown": LText(de: "Eine kleine Sendung", en: "A little delivery"),
        // Delivered Zeitpost note (foreground alert body — text stays in-app)
        "post.note.notifBody": LText(de: "Eine kleine Notiz von {name} ist angekommen.",
                                     en: "A little note from {name} has arrived."),
        // Floating 💭 quick action on the dashboard
        "home.thinkingFabA11y": LText(de: "„Denk an dich“ senden", en: "Send a “thinking of you”"),

        // Dashboard priority & release discovery (4.2)
        "dashboard.group.auto": LText(de: "Automatisch nach Wichtigkeit", en: "Automatic by priority"),
        "dashboard.group.rituals": LText(de: "Rituale & Nähe", en: "Rituals & closeness"),
        "dashboard.group.games": LText(de: "Spiele", en: "Games"),
        // Term dedup (FXC-4 #7): "Momente" belongs exclusively to the
        // planned dates in the Wir tab (memories.events.*). This dashboard
        // group shows MEMORY flashbacks (on-this-day + memory of the day)
        // — so it says what it is: Rückblicke/Flashbacks.
        "dashboard.group.moments": LText(de: "Rückblicke", en: "Flashbacks"),
        "dashboard.group.moments.empty": LText(
            de: "Noch kein Rückblick — sobald eure Tage ein Gestern haben, erscheint er hier.",
            en: "No flashback yet — once your days have a yesterday, it will appear here."
        ),
        "dashboard.a11y.pending": LText(de: "{n} offene Einträge", en: "{n} pending items"),
        "dashboard.a11y.pending.one": LText(de: "ein offener Eintrag", en: "one pending item"),
        "dashboard.a11y.pending.other": LText(de: "{count} offene Einträge", en: "{count} pending items"),
        "dashboard.a11y.none": LText(de: "Keine offenen Einträge", en: "No pending items"),
        "dashboard.edit.title": LText(de: "Dashboard anpassen", en: "Customize dashboard"),
        "dashboard.edit.pin": LText(de: "Gruppe oben anheften", en: "Pin a group first"),
        "dashboard.edit.visibility": LText(de: "Sichtbare Gruppen", en: "Visible groups"),
        "dashboard.edit.hint": LText(
            de: "Dringendes bleibt oben sichtbar. Deine Wahl gilt nur auf diesem Gerät.",
            en: "Urgent items stay visible at the top. Your choice applies only to this device."
        ),
        "whatsnew.title": LText(de: "Neu in Version {version}", en: "New in version {version}"),
        "whatsnew.4_2.dashboard.title": LText(de: "Ein ruhigeres Zuhause", en: "A calmer Home"),
        "whatsnew.4_2.dashboard.body": LText(
            de: "Wichtiges steht oben; Rituale, Spiele und Rückblicke lassen sich einklappen, ausblenden und anheften.",
            en: "Important items stay on top; rituals, games, and flashbacks can be collapsed, hidden, and pinned."
        ),
        "whatsnew.4_2.discovery.title": LText(de: "Nichts Neues mehr verpassen", en: "Never miss what is new"),
        "whatsnew.4_2.discovery.body": LText(
            de: "Diese Übersicht erscheint pro Version einmal und führt direkt zu den neuen Bereichen.",
            en: "This overview appears once per version and links directly to each new area."
        ),
        "whatsnew.4_3.replay.title": LText(de: "Jede Partie als Geschichte", en: "Every match tells its story"),
        "whatsnew.4_3.replay.body": LText(
            de: "Jede Partie lässt sich als kleine Geschichte nachspielen — jedes Spiel erzählt seine Züge auf seine eigene Art.",
            en: "Every match replays like a little story — each game tells its moves in its own way."
        ),
        "whatsnew.4_3.season.title": LText(de: "Vollständige Saison", en: "Complete seasons"),
        "whatsnew.4_3.season.body": LText(
            de: "Turniere zählen die gesamte aufbewahrte Spielhistorie und Wordle auf Deutsch und Englisch.",
            en: "Tournaments count the full retained game history and Wordle in German and English."
        ),
        "whatsnew.4_4.states.title": LText(de: "Jeder Zustand hat einen Weg", en: "Every state has a way forward"),
        "whatsnew.4_4.states.body": LText(
            de: "Replay und Turnier unterscheiden Laden, leer, offline und Fehler — mit ehrlichem Wiederholen.",
            en: "Replay and Tournament distinguish loading, empty, offline, and failure—with an honest retry."
        ),
        "whatsnew.4_4.lock.title": LText(de: "Sperre mit Rückweg", en: "Lock with recovery"),
        "whatsnew.4_4.lock.body": LText(
            de: "Abgebrochene Authentifizierung bleibt ruhig; echte Gerätefehler zeigen Hilfe und den Weg in die Einstellungen.",
            en: "Cancelled authentication stays quiet; real device errors show help and the way into Settings."
        ),
        "whatsnew.4_5.type.title": LText(de: "Großer Text, gleiche Nähe", en: "Larger text, same closeness"),
        "whatsnew.4_5.type.body": LText(
            de: "Größere Schrift? Alles rückt zurecht: Zuhause, Status und Feiern machen Platz, statt zu quetschen.",
            en: "Larger text? Everything falls into place: Home, status, and celebrations make room instead of squeezing."
        ),
        "whatsnew.4_5.motion.title": LText(de: "Ruhige Feiern", en: "Calm celebrations"),
        "whatsnew.4_5.motion.body": LText(
            de: "„Bewegung reduzieren“ zeigt einen statischen Schimmer statt Timeline-Partikeln.",
            en: "Reduce Motion shows a static glow instead of timeline particles."
        ),
        "whatsnew.4_6.backup.title": LText(de: "Backup nach euren Regeln", en: "Backup on your terms"),
        "whatsnew.4_6.backup.body": LText(
            de: "Wählt Serverprofile, Geräte-, App-Group-Einstellungen und den Nur-Lesen-Paar-Schnappschuss getrennt.",
            en: "Choose server profiles, device and App Group settings, and the read-only couple snapshot separately."
        ),
        "whatsnew.4_6.restore.title": LText(de: "Sicherer wiederherstellen", en: "Safer restore"),
        "whatsnew.4_6.restore.body": LText(
            de: "Beim Wiederherstellen prüft die App jede Datei, bevor sie etwas anfasst — und eure gemeinsamen Inhalte bleiben sicher auf eurem Server.",
            en: "Restoring checks every file before touching anything — and your shared content stays safe on your server."
        ),
        "whatsnew.4_7.widgets.title": LText(de: "Widgets, die ehrlich altern", en: "Widgets that age honestly"),
        "whatsnew.4_7.widgets.body": LText(
            de: "Alle acht Widgets markieren Daten, die älter als ihr natürlicher Takt sind, statt Aktualität vorzutäuschen.",
            en: "All eight widgets mark data older than their natural cadence instead of pretending it is current."
        ),
        "whatsnew.4_7.controls.title": LText(de: "Vier Controls für iOS 18", en: "Four controls for iOS 18"),
        "whatsnew.4_7.controls.body": LText(
            de: "„Denk an dich“ und „Date-Night starten“ ergänzen Herzklopfen und Bedürfnis-Knopf.",
            en: "Thinking of You and Start Date Night join Heartbeat and the Need button."
        ),
        "whatsnew.4_8.repair.title": LText(de: "Ruhiger aussprechen", en: "Talk it through calmly"),
        "whatsnew.4_8.repair.body": LText(
            de: "Gefühl, Spiegeln und eine kleine Vereinbarung folgen geschützten, ungestörten Zügen.",
            en: "Feeling, mirroring, and a small agreement follow protected, uninterrupted turns."
        ),
        "whatsnew.4_8.consideration.title": LText(de: "Rücksicht bleibt freiwillig", en: "Consideration stays optional"),
        "whatsnew.4_8.consideration.body": LText(
            de: "Hinweise sind Tresor-verschlüsselt, jederzeit pausierbar und bewusst ohne XP; 3 gute Dinge enthüllen erst gemeinsam.",
            en: "Hints are Vault-encrypted, pausable anytime, and deliberately XP-free; 3 Good Things reveal only together."
        ),
        "whatsnew.4_9.manual.title": LText(de: "Hilfe genau dort, wo ihr seid", en: "Help right where you are"),
        "whatsnew.4_9.manual.body": LText(
            de: "Das ? über jedem Tab öffnet das gebündelte Handbuch direkt beim passenden Kapitel.",
            en: "The ? above every tab opens the bundled manual at the matching chapter."
        ),
        "whatsnew.4_9.locale.title": LText(de: "Deutsch und Englisch im Detail", en: "German and English in detail"),
        "whatsnew.4_9.locale.body": LText(
            de: "Datum, Zahl, Dauer und Mehrzahl folgen jetzt der gewählten App-Sprache statt still der Gerätesprache.",
            en: "Dates, numbers, durations, and plurals now follow the selected app language instead of silently using the device language."
        ),
        "whatsnew.5_0.calendar.title": LText(de: "Türchen für besondere Tage", en: "Doors for special days"),
        "whatsnew.5_0.calendar.body": LText(
            de: "Bereitet Advent, Geburtstag, Jahrestag oder einen eigenen Countdown mit sicher gesperrten Überraschungen vor.",
            en: "Prepare Advent, a birthday, an anniversary, or a custom countdown with securely locked surprises."
        ),
        "whatsnew.5_0.season.title": LText(de: "Jahreszeiten, die zu euch passen", en: "Seasons that fit you"),
        "whatsnew.5_0.season.body": LText(
            de: "Nord- und Südhalbkugel stimmen jetzt; Fest-Rahmen und Widget-Looks bleiben ehrliche Vorschläge.",
            en: "Northern and southern hemispheres now match; event frames and widget looks remain honest suggestions."
        ),
        "whatsnew.5_1.games.title": LText(de: "Drei neue Spiele", en: "Three new games"),
        "whatsnew.5_1.games.body": LText(
            de: "Wortkette-Blitz, faires Galgenraten und automatisch geprüftes Paar-Bingo warten im neu sortierten Spielen-Hub.",
            en: "Word Chain Blitz, fair Hangman, and auto-checked Couple Bingo await in the reorganized Play hub."
        ),
        "whatsnew.5_1.tutorials.title": LText(de: "Erst üben, dann spielen", en: "Practice before playing"),
        "whatsnew.5_1.tutorials.body": LText(
            de: "Alle 19 Spiele besitzen ein kurzes, fortsetzbares 3-Schritt-Intro und einen lokalen Übungsimpuls.",
            en: "All 19 games include a short, resumable three-step intro and a local practice prompt."
        ),
        "whatsnew.5_2.offline.title": LText(de: "Funkloch? Nichts geht verloren", en: "Signal gap? Nothing gets lost"),
        "whatsnew.5_2.offline.body": LText(
            de: "Reaktionen, Tagesantworten und Spielzüge warten Funklöcher einfach ab und kommen genau einmal an — nichts verschwindet, nichts kommt doppelt.",
            en: "Reactions, daily answers, and game moves simply wait out signal gaps and arrive exactly once — nothing vanishes, nothing doubles."
        ),
        "whatsnew.5_2.speed.title": LText(de: "Leichter starten, ruhiger verbinden", en: "Lighter starts, calmer reconnects"),
        "whatsnew.5_2.speed.body": LText(
            de: "Die App startet schneller und verbindet sich nach Funklöchern sanfter — ganz ohne dein Zutun.",
            en: "The app starts faster and reconnects more gently after signal gaps — with no action needed from you."
        ),
        "whatsnew.5_3.palette.title": LText(de: "Euer gemeinsamer Look", en: "Your shared look"),
        "whatsnew.5_3.palette.body": LText(
            de: "Kombiniert eure Farben, wählt ein Monogramm und tragt Kosenamen in vollständige Satzvorlagen ein.",
            en: "Combine your colors, choose a monogram, and use pet names through complete sentence templates."
        ),
        "whatsnew.5_3.chat.title": LText(de: "Nachrichten mit einem Funkeln", en: "Messages with a little sparkle"),
        "whatsnew.5_3.chat.body": LText(
            de: "Sechs sparsame Sendeeffekte und eine ehrliche prozedurale Sticker-Werkstatt warten im Chat.",
            en: "Six sparing send effects and an honest procedural Sticker Workshop are waiting in Chat."
        ),
        "whatsnew.6_0.migration.title": LText(de: "Euer Server zieht mit", en: "Take your server data with you"),
        "whatsnew.6_0.migration.body": LText(
            de: "Der geführte Assistent exportiert eure logischen Paar-Daten verschlüsselt und importiert sie sicher in ein frisches Paar.",
            en: "The guided assistant exports your logical couple data in an encrypted file and safely imports it into a fresh couple."
        ),
        "whatsnew.6_0.complete.title": LText(de: "SoooDreamy 6 ist komplett", en: "SoooDreamy 6 is complete"),
        "whatsnew.6_0.complete.body": LText(
            de: "Alle 15 Releases, zweisprachige Hilfe, Zustandsprüfungen und versionierte Builds sind gemeinsam angekommen.",
            en: "All 15 releases, bilingual help, state audits, and versioned builds have arrived together."
        ),
        "whatsnew.7_0.weekreview.title": LText(de: "Eure Woche in Zahlen", en: "Your week in numbers"),
        "whatsnew.7_0.weekreview.body": LText(
            de: "Jede Woche ein kleiner Rückblick: Zahlen, Zitat der Woche, Foto der Woche — und euer Highlight-Ritual, das sich erst zeigt, wenn ihr beide geteilt habt.",
            en: "A little review every week: numbers, quote of the week, photo of the week — and your highlight ritual that reveals only once you both shared."
        ),
        "whatsnew.7_0.dailyq.title": LText(de: "Eure eigenen Tagesfragen", en: "Your own daily questions"),
        "whatsnew.7_0.dailyq.body": LText(
            de: "Legt heimlich Fragen in euren gemeinsamen Topf — ungefähr jeden dritten Tag wird eine davon gestellt. Wer sie geschrieben hat, bleibt bis zur Auflösung geheim.",
            en: "Secretly drop questions into your shared pool — roughly every third day one of them is asked. Who wrote it stays secret until the reveal."
        ),
        "whatsnew.8_0.onthisday.title": LText(de: "An diesem Tag", en: "On this day"),
        "whatsnew.8_0.onthisday.body": LText(
            de: "Heute vor genau X Monaten oder Jahren: Fotos und gemeinsam beantwortete Tagesfragen tauchen als Erinnerung auf dem Dashboard auf — auf beiden Handys dieselben.",
            en: "Exactly X months or years ago today: photos and dailies you both answered resurface as memories on the dashboard — the same ones on both phones."
        ),
        "whatsnew.8_0.story.title": LText(de: "Unsere Geschichte", en: "Our story"),
        "whatsnew.8_0.story.body": LText(
            de: "Eure Meilensteine als Zeitreise: erster Text, erstes Foto, erste Tagesfrage zu zweit, Abzeichen und Jubiläen — Monat für Monat im Erinnerungen-Tab.",
            en: "Your milestones as a time journey: first text, first photo, first daily together, badges and milestones — month by month in the memories tab."
        ),
        "whatsnew.8_0.widget.title": LText(de: "Erinnerungs-Widget", en: "Memory widget"),
        "whatsnew.8_0.widget.body": LText(
            de: "Das neue „An diesem Tag“-Widget bringt eure Erinnerung von heute auf den Home-Bildschirm — inklusive Foto. Stil wie immer im Widget-Studio.",
            en: "The new “On this day” widget puts today's memory on your home screen — photo included. Style it in the Widget Studio as always."
        ),

        // Settings
        "settings.title": LText(de: "Amt", en: "Bureau"),
        "settings.appSection": LText(de: "App", en: "App"),
        "settings.profile": LText(de: "Dein Profil", en: "Your profile"),
        "migration.title": LText(de: "Server-Umzug", en: "Server migration"),
        "migration.settingsHint": LText(
            de: "Paar-Daten verschlüsselt auf einen neuen Server mitnehmen",
            en: "Move encrypted couple data to a new server"
        ),
        "migration.introTitle": LText(de: "Geführter Umzug in drei Schritten", en: "Guided move in three steps"),
        "migration.introBody": LText(
            de: "Exportiere auf dem alten Server, erstelle auf dem neuen Server ein frisches Paar und importiere dort die verschlüsselte Datei.",
            en: "Export on the old server, create a fresh couple on the new server, then import the encrypted file there."
        ),
        "migration.mediaLimit": LText(
            de: "Fotos, Videos, Sprach- und Tresor-Dateien bleiben im Datenordner des alten Servers und müssen vom Admin separat kopiert werden.",
            en: "Photo, video, voice, and Vault files remain in the old server data directory and need a separate admin copy."
        ),
        "migration.stepExport": LText(de: "1 · Alten Server exportieren", en: "1 · Export old server"),
        "migration.exportHint": LText(
            de: "Die Datei nutzt AES-GCM und eine Passphrase mit mindestens 12 Zeichen. SoooDreamy speichert die Passphrase nie.",
            en: "The file uses AES-GCM and a passphrase of at least 12 characters. SoooDreamy never stores the passphrase."
        ),
        "migration.passphrase": LText(de: "Passphrase (mindestens 12 Zeichen)", en: "Passphrase (at least 12 characters)"),
        "migration.passphraseAgain": LText(de: "Passphrase wiederholen", en: "Repeat passphrase"),
        "migration.shareFile": LText(de: "Umzugsdatei teilen", en: "Share migration file"),
        "migration.createFile": LText(de: "Verschlüsselte Datei erstellen", en: "Create encrypted file"),
        "migration.stepDestination": LText(de: "2 · Neuen Server vorbereiten", en: "2 · Prepare new server"),
        "migration.destinationBody": LText(
            de: "Füge den neuen Server hinzu, erstelle dort mit deinem Profil ein frisches Paar und öffne diesen Assistenten erneut. Import überschreibt niemals ein Paar mit vorhandenen Aktivitäten.",
            en: "Add the new server, create a fresh couple there with your profile, then reopen this assistant. Import never overwrites a couple that already has activity."
        ),
        "migration.sessionsReset": LText(
            de: "Tokens und Gerätesitzungen ziehen absichtlich nicht um. Dein Schatz koppelt sich danach mit dem neuen Code erneut.",
            en: "Tokens and device sessions deliberately do not migrate. Your sweetheart re-pairs afterward with the new code."
        ),
        "migration.stepImport": LText(de: "3 · Auf neuem Server importieren", en: "3 · Import on new server"),
        "migration.chooseFile": LText(de: "Umzugsdatei auswählen", en: "Choose migration file"),
        "migration.unlockReview": LText(de: "Entschlüsseln und prüfen", en: "Unlock and review"),
        "migration.review": LText(
            de: "Quelle: Server {version}\nPrüfsumme: {digest}…",
            en: "Source: server {version}\nDigest: {digest}…"
        ),
        "migration.importNow": LText(de: "Jetzt importieren", en: "Import now"),
        "migration.fileReadFailed": LText(de: "Die Umzugsdatei konnte nicht gelesen werden.", en: "The migration file could not be read."),
        "migration.confirmTitle": LText(de: "Frisches Paar ersetzen?", en: "Replace the fresh couple?"),
        "migration.confirmBody": LText(
            de: "Der Import übernimmt die logischen Paar-Daten. Deine aktuelle Sitzung bleibt gültig; alle anderen Geräte müssen neu koppeln.",
            en: "Import applies the logical couple data. Your current session remains valid; every other device must re-pair."
        ),
        "migration.completeTitle": LText(de: "Umzug importiert", en: "Migration imported"),
        "migration.completeBody": LText(
            de: "Teile diesen neuen Kopplungscode mit deinem Schatz. Alte Server-Tokens funktionieren hier nicht.",
            en: "Share this new pairing code with your sweetheart. Old-server tokens do not work here."
        ),
        "migration.digest": LText(de: "Logische Prüfsumme: {digest}…", en: "Logical digest: {digest}…"),
        "migration.exportFailed": LText(de: "Der Server-Export ist fehlgeschlagen.", en: "The server export failed."),
        "migration.unlockFailed": LText(
            de: "Datei oder Passphrase ist ungültig. Es wurde nichts importiert.",
            en: "The file or passphrase is invalid. Nothing was imported."
        ),
        "settings.couple": LText(de: "Euer Paar", en: "Your couple"),
        "settings.coupleName": LText(de: "Name eures Paars", en: "Couple name"),
        "settings.anniversary": LText(de: "Jahrestag", en: "Anniversary"),
        "settings.anniversaryHint": LText(de: "Seit wann seid ihr zusammen?", en: "Since when are you together?"),
        "settings.language": LText(de: "Sprache", en: "Language"),
        "settings.sounds": LText(de: "Sounds", en: "Sounds"),
        "settings.soundCredits.title": LText(de: "Klänge & Credits", en: "Sounds & credits"),
        "settings.soundCredits.hint": LText(
            de: "Quellen, Lizenzen und Dank — antippen spielt den Klang",
            en: "Sources, licenses and thanks — tap to hear a sound"
        ),
        "settings.soundCredits.intro": LText(
            de: "Einige Klänge basieren auf frei lizenzierten Aufnahmen, fein zugeschnitten auf die SoooDreamy-Klangwelt. Eine Zeile antippen spielt den Klang ab.",
            en: "Some sounds are based on freely licensed recordings, tailored to the SoooDreamy sound world. Tap a row to hear the sound."
        ),
        "settings.soundCredits.thanks": LText(de: "Mit Dank an", en: "With thanks to"),
        "settings.soundCredits.publicDomain": LText(de: "CC0 & Public Domain", en: "CC0 & public domain"),
        "settings.soundCredits.synthFooter": LText(
            de: "Alle übrigen Klänge sind Original-Synthese von SoooDreamy.",
            en: "All other sounds are original SoooDreamy synthesis."
        ),
        "settings.soundCredits.openSource": LText(de: "Quelle öffnen", en: "Open source page"),
        "settings.soundCredits.playHint": LText(de: "Spielt den Klang ab", en: "Plays the sound"),
        "settings.soundvol.title": LText(de: "Lautstärke pro Kategorie", en: "Volume per category"),
        // Term dedup (FXC-4 #7): this slider governs the ceremony/ambience
        // sounds (heartbeat, sparkle, cinematic bed) — "Momente" is the
        // planned-dates feature in the Wir tab, so the category says what
        // it actually controls.
        "settings.soundvol.moments": LText(de: "Zeremonien", en: "Ceremonies"),
        "settings.soundvol.chat": LText(de: "Chat", en: "Chat"),
        "settings.soundvol.games": LText(de: "Spiele", en: "Games"),
        "settings.soundvol.ui": LText(de: "Interface", en: "Interface"),
        "settings.haptics": LText(de: "Haptik", en: "Haptics"),
        "settings.reminder": LText(de: "Tägliche Erinnerung", en: "Daily reminder"),
        "settings.reminderHint": LText(de: "Erinnert euch abends an die Frage des Tages", en: "Evening nudge for the question of the day"),
        "settings.reminderTime": LText(de: "Uhrzeit", en: "Time"),
        "settings.streakGuard": LText(de: "Serien-Schutz", en: "Streak guard"),
        "settings.streakGuardHint": LText(de: "Zweite Erinnerung um 21:30 Uhr, wenn eure Antwort-Serie in Gefahr ist",
                                          en: "Second reminder at 9:30 pm when your answer streak is at risk"),
        "settings.unpair": LText(de: "Paar auflösen", en: "Dissolve couple"),
        "settings.unpairConfirm": LText(de: "Wirklich? Das löscht eure Daten auf dem Server — Chats, Fotos, alles. Für immer.",
                                        en: "Really? This deletes your data on the server — chats, photos, everything. Forever."),
        // W8 Settings-IA: scope badges, danger zone, export-before-delete
        "settings.scope.couple": LText(de: "gilt für euch beide", en: "applies to both of you"),
        "settings.scope.device": LText(de: "nur du", en: "just you"),
        "settings.dangerZone": LText(de: "Gefahrenzone", en: "Danger zone"),
        "settings.exportFirst": LText(de: "Zuerst Erinnerungen sichern", en: "Back up memories first"),
        "settings.leaveDevice": LText(de: "Auf diesem Gerät abmelden", en: "Sign out on this device"),
        "settings.leaveDeviceHint": LText(de: "Eure Daten bleiben sicher auf dem Server. Mit „Wieder verbinden“ und deinem Wiederherstellungs-Schlüssel kommst du jederzeit zurück.",
                                          en: "Your data stays safe on the server. “Reconnect” and your recovery key bring you back anytime."),
        "settings.about": LText(de: "Über SoooDreamy", en: "About SoooDreamy"),
        "settings.version": LText(de: "Version", en: "Version"),
        "settings.build": LText(de: "Build", en: "Build"),
        "settings.serverUnavailable": LText(de: "nicht erreichbar", en: "unavailable"),
        // ENTSCHIEDEN (Amt-Eval S3, about-de.png): the credit is LOCALIZED,
        // not an English signature — the German office speaks German down
        // to its last line ("gemacht von"); the maker's NAME stays the
        // untranslated signature.
        "settings.credit": LText(de: "gemacht von Sonic0810", en: "made by Sonic0810"),
        "settings.madeWith": LText(de: "Mit Liebe gebaut — für euch zwei.", en: "Built with love — for the two of you."),
        "settings.connection": LText(de: "Verbindung", en: "Connection"),
        "settings.serverVersionLabel": LText(de: "Server-Version", en: "Server version"),
        "settings.serverVersion": LText(de: "Server-Version {version}", en: "Server version {version}"),
        "settings.pairingShow": LText(de: "Paar-Code & QR zeigen", en: "Show couple code & QR"),
        "settings.pairingHint": LText(de: "Zum Koppeln eines neuen Geräts — oder falls dein Schatz den Code nochmal braucht.",
                                      en: "For pairing a new device — or in case your sweetheart needs the code again."),
        "personalization.title": LText(de: "Eure Farben", en: "Your colors"),
        "personalization.settings.hint": LText(
            de: "Farbschema, Monogramm und Wachssiegel",
            en: "Palette, monogram and wax seal"
        ),
        "personalization.preview": LText(de: "Euer gemeinsamer Look", en: "Your shared look"),
        "personalization.preview.body": LText(
            de: "Die Farben erscheinen in Hintergründen, Chatblasen und Widgets.",
            en: "These colors appear in backgrounds, chat bubbles and widgets."
        ),
        "personalization.presets": LText(de: "Voreinstellungen", en: "Presets"),
        "personalization.preset.a11y": LText(de: "Farbschema auswählen", en: "Choose color palette"),
        "personalization.custom": LText(de: "Eigene Farben", en: "Custom colors"),
        "personalization.primary": LText(de: "Deine Farbe als #RRGGBB", en: "Your color as #RRGGBB"),
        "personalization.secondary": LText(de: "Farbe deines Schatzes als #RRGGBB",
                                            en: "Your sweetheart's color as #RRGGBB"),
        "personalization.custom.hint": LText(
            de: "Ungültige Werte fallen sicher auf das SoooDreamy-Rosé zurück.",
            en: "Invalid values safely fall back to SoooDreamy blush."
        ),
        "personalization.monogram": LText(de: "Monogramm & Wachssiegel", en: "Monogram & wax seal"),
        "personalization.monogram.seal": LText(de: "Siegel", en: "Seal"),
        "personalization.monogram.ribbon": LText(de: "Band", en: "Ribbon"),
        "personalization.monogram.minimal": LText(de: "Minimal", en: "Minimal"),
        "personalization.monogram.a11y": LText(de: "Euer Paar-Monogramm", en: "Your couple monogram"),
        "personalization.contrast": LText(
            de: "Kontrast automatisch geschützt: {ratio}:1",
            en: "Contrast automatically protected: {ratio}:1"
        ),
        "personalization.petName": LText(de: "Dein Kosename (optional)", en: "Your pet name (optional)"),
        "personalization.petName.hint": LText(
            de: "Dein Schatz sieht diesen Namen in persönlichen Sätzen. Vorlagen setzen Namen ein, statt Wörter zusammenzukleben.",
            en: "Your sweetheart sees this name in personal copy. Templates insert names instead of joining sentence fragments."
        ),
        "settings.widgets": LText(de: "Widgets", en: "Widgets"),
        "settings.widgetsHint": LText(de: "Lange auf den Home-Bildschirm drücken → „Widget hinzufügen“ → SoooDreamy",
                                      en: "Long-press your home screen → “Add widget” → SoooDreamy"),
        "settings.widgetBackground": LText(de: "Widget-Hintergrund", en: "Widget background"),
        "settings.widgetPhotoChrome": LText(de: "Foto als Widget-Hintergrund", en: "Photo as widget backdrop"),
        "settings.widgetPhotoChromeHint": LText(de: "Foto- & Leinwand-Widgets zeigen euer Lieblingsfoto abgedunkelt im Hintergrund",
                                                en: "Photo & canvas widgets show your favorite photo, dimmed, as their backdrop"),
        "settings.widgetBg.night": LText(de: "Nacht", en: "Night"),
        "settings.widgetBg.sunset": LText(de: "Abendrot", en: "Sunset"),
        "settings.widgetBg.ocean": LText(de: "Ozean", en: "Ocean"),
        "settings.widgetBg.blush": LText(de: "Rosé", en: "Blush"),
        "settings.widgetBg.mono": LText(de: "Mono", en: "Mono"),
        "settings.widgetBg.photo": LText(de: "Foto", en: "Photo"),

        // Widget Studio (2.0)
        "settings.widgetStudio": LText(de: "Widget-Studio", en: "Widget Studio"),
        "settings.widgetStudioHint": LText(de: "Themes, Layouts & Datenquellen für alle Widgets — mit Live-Vorschau.",
                                           en: "Themes, layouts & data sources for every widget — with live previews."),
        "la.title": LText(de: "Live Activity", en: "Live Activity"),
        "la.settingsHint": LText(de: "Sperrbildschirm & Dynamic Island anpassen: Theme, Ticker, Inhalte",
                                 en: "Customize lock screen & Dynamic Island: theme, ticker, content"),
        "la.preview": LText(de: "Vorschau", en: "Preview"),
        "la.theme": LText(de: "Farbschema", en: "Color scheme"),
        "la.elements": LText(de: "Angezeigte Elemente", en: "Visible elements"),
        "la.liveTimer": LText(de: "Tickender Countdown", en: "Ticking countdown"),
        "la.progress": LText(de: "Fortschrittsbalken (letzte 48 h)", en: "Progress bar (final 48 h)"),
        "la.presence": LText(de: "Online-Status", en: "Online status"),
        "la.mood": LText(de: "Stimmung & Notiz", en: "Mood & note"),
        "la.touch": LText(de: "Letzte Berührung", en: "Last touch"),
        "la.streak": LText(de: "Antwort-Serie", en: "Answer streak"),
        "la.days": LText(de: "Tage zusammen", en: "Days together"),
        "la.startPulse": LText(de: "Couple Pulse starten", en: "Start Couple Pulse"),
        "la.stopPulse": LText(de: "Couple Pulse beenden", en: "Stop Couple Pulse"),
        "la.countdownHintTitle": LText(de: "Countdown zu einem Moment", en: "Countdown to a moment"),
        "la.countdownHint": LText(de: "Starte Countdown-Live-Activities bei euren Momenten: Erinnerungen → Momente → „Live“.",
                                  en: "Start countdown Live Activities from your moments: Memories → Moments → “Live”."),
        "la.limitHint": LText(de: "iOS aktualisiert Live Activities ohne Push nur, solange die App läuft — tickende Timer & Fortschrittsbalken laufen aber immer weiter.",
                              en: "Without push, iOS only updates Live Activities while the app runs — ticking timers & progress bars keep animating regardless."),
        // Haptics composer
        "haptic.studio.title": LText(de: "Haptik-Studio", en: "Haptics Studio"),
        "home.hapticStudio": LText(de: "Haptik-Studio", en: "Haptics Studio"),
        "home.hapticStudio.hint": LText(de: "Eigene Vibration aufnehmen & senden",
                                        en: "Record & send a custom vibe"),
        "haptic.compose.title": LText(de: "Dein Muster", en: "Your pattern"),
        "haptic.pad.idle": LText(de: "Tippe & halte deinen Rhythmus — kurz = Klopfen, lang = sanftes Beben",
                                 en: "Tap & hold your rhythm — short = knock, long = gentle rumble"),
        "haptic.pad.active": LText(de: "Weiter tippen … Pausen gehören zum Rhythmus",
                                   en: "Keep tapping … pauses are part of the rhythm"),
        // VoiceOver access to the recording pad (A11y eval): the drag
        // gesture alone is invisible to switch/VoiceOver users — named
        // actions start and end an impulse over the same recording path.
        "haptic.pad.a11y": LText(de: "Aufnahmefläche", en: "Recording pad"),
        "haptic.pad.a11y.recording": LText(de: "Impuls läuft", en: "Pulse in progress"),
        "haptic.pad.a11y.hint": LText(
            de: "Zum Aufnehmen halten. Mit den Aktionen „Impuls starten“ und „Impuls beenden“ bestimmst du die Länge jedes Impulses.",
            en: "Hold to record. Use the “start pulse” and “end pulse” actions to shape each pulse's length."),
        "haptic.pad.a11y.start": LText(de: "Impuls starten", en: "Start pulse"),
        "haptic.pad.a11y.stop": LText(de: "Impuls beenden", en: "End pulse"),
        "haptic.events.count": LText(de: "{n} Impulse", en: "{n} pulses"),
        "haptic.feel": LText(de: "Fühlen", en: "Feel it"),
        "haptic.clear": LText(de: "Von vorn", en: "Start over"),
        "haptic.send": LText(de: "Senden", en: "Send"),
        "haptic.save.title": LText(de: "Muster speichern", en: "Save pattern"),
        "haptic.save.nameField": LText(de: "Name (z. B. Gute-Nacht-Puls)", en: "Name (e.g. goodnight pulse)"),
        "haptic.sent.toast": LText(de: "Vibration an {name} geschickt", en: "Vibe sent to {name}"),
        "haptic.saved.toast": LText(de: "In eurer Bibliothek gespeichert", en: "Saved to your library"),
        "haptic.presets.title": LText(de: "Presets", en: "Presets"),
        "haptic.library.title": LText(de: "Eure Bibliothek", en: "Your library"),
        "haptic.library.empty": LText(de: "Noch keine eigenen Muster — nimm oben euer erstes auf.",
                                      en: "No saved patterns yet — record your first one above."),
        "haptic.history.title": LText(de: "Zuletzt gesendet & empfangen", en: "Recently sent & received"),
        "haptic.history.empty": LText(de: "Noch nichts verschickt — ein Preset ist ein guter Anfang.",
                                      en: "Nothing sent yet — a preset is a good place to start."),
        "haptic.adhoc": LText(de: "Spontan-Vibe", en: "Spontaneous vibe"),
        "haptic.fromYou": LText(de: "von dir", en: "from you"),
        "haptic.fromPartner": LText(de: "von {name}", en: "from {name}"),
        "haptic.rename": LText(de: "Umbenennen", en: "Rename"),
        "haptic.deleteConfirm": LText(de: "Muster löschen?", en: "Delete pattern?"),
        "haptic.sentCount": LText(de: "{n}× gesendet", en: "sent {n}×"),
        "haptic.received.title": LText(de: "Vibration", en: "Vibe"),
        "haptic.received.body": LText(de: "{name} lässt dein Handy für dich vibrieren",
                                      en: "{name} is making your phone buzz for you"),
        "haptic.received.overlay": LText(de: "Eine Vibration von {name}", en: "A vibe from {name}"),
        "haptic.replay": LText(de: "Nochmal fühlen", en: "Feel again"),
        "haptic.deviceHint": LText(de: "Haptik braucht eine Taptic Engine — im Simulator und auf den meisten iPads ist nichts zu spüren.",
                                   en: "Haptics need a Taptic Engine — nothing to feel in the simulator or on most iPads."),
        "haptic.preset.heartbeat": LText(de: "Herzschlag", en: "Heartbeat"),
        "haptic.preset.butterflies": LText(de: "Schmetterlinge", en: "Butterflies"),
        "haptic.preset.rain": LText(de: "Regen", en: "Rain"),
        "haptic.preset.soskiss": LText(de: "SOS-Kuss", en: "SOS kiss"),
        "haptic.preset.ocean": LText(de: "Meeresrauschen", en: "Ocean waves"),
        "haptic.preset.sparkle": LText(de: "Funkeln", en: "Sparkle"),

        // iCloud & backup
        "icloud.title": LText(de: "iCloud & Backup", en: "iCloud & Backup"),
        "icloud.settingsHint": LText(de: "Server-Metadaten & Einstellungen sichern — ohne Sitzungstokens",
                                     en: "Back up server metadata & settings — without session tokens"),
        "icloud.status": LText(de: "iCloud-Status", en: "iCloud status"),
        "icloud.statusCloudKit": LText(de: "CloudKit (privat)", en: "CloudKit (private)"),
        "icloud.statusDrive": LText(de: "iCloud Drive", en: "iCloud Drive"),
        "icloud.available": LText(de: "verfügbar", en: "available"),
        "icloud.unavailable": LText(de: "nicht verfügbar", en: "unavailable"),
        "icloud.noAccount": LText(de: "kein iCloud-Account", en: "no iCloud account"),
        "icloud.restricted": LText(de: "eingeschränkt", en: "restricted"),
        "icloud.backup": LText(de: "iCloud-Backup", en: "iCloud backup"),
        "icloud.whatsIn": LText(de: "Sichert eure Server-Verbindungen (inkl. Kopplung) und deine App-Einstellungen — in deine private iCloud-Datenbank, die nur du lesen kannst. Eure gemeinsamen Inhalte liegen sicher auf eurem Server und kommen nach dem Wiederherstellen automatisch zurück.",
                                en: "Backs up your server connections (incl. pairing) and app settings — to your own private iCloud database that only you can read. Your shared content lives safely on your server and comes back automatically after restoring."),
        "icloud.lastBackup": LText(de: "Letztes Backup", en: "Last backup"),
        "icloud.never": LText(de: "noch nie", en: "never"),
        "icloud.backupNow": LText(de: "Jetzt in iCloud sichern", en: "Back up to iCloud now"),
        "icloud.backupDone": LText(de: "In iCloud gesichert", en: "Backed up to iCloud"),
        "icloud.backupFailed": LText(de: "Backup hat nicht geklappt", en: "Backup didn't work"),
        "icloud.restore": LText(de: "Wiederherstellen", en: "Restore"),
        "icloud.restoreConfirmTitle": LText(de: "Backup wiederherstellen?", en: "Restore backup?"),
        "icloud.restoreConfirmMessage": LText(de: "Ersetzt deine gespeicherten Server und App-Einstellungen durch das Backup. Eure Inhalte auf dem Server bleiben unberührt.",
                                              en: "Replaces your saved servers and app settings with the backup. Your content on the server stays untouched."),
        "icloud.restoreDone": LText(de: "{n} Server wiederhergestellt", en: "Restored {n} servers"),
        "icloud.restoreFailed": LText(de: "Wiederherstellen hat nicht geklappt", en: "Restore didn't work"),
        "icloud.noBackup": LText(de: "Kein Backup in iCloud gefunden", en: "No backup found in iCloud"),
        "icloud.export": LText(de: "Datei-Export", en: "File export"),
        "icloud.exportHint": LText(de: "Erstellt eine AES-GCM-verschlüsselte .sooodreamy-Datei mit Server-Metadaten, Einstellungen und einem Schnappschuss von Momenten, Träumeliste, Songs & Gutscheinen. Sitzungstokens werden nie exportiert.",
                                   en: "Creates an AES-GCM encrypted .sooodreamy file with server metadata, settings and a snapshot of moments, bucket list, songs & coupons. Session tokens are never exported."),
        "icloud.scope.servers": LText(de: "Serverprofile (ohne Tokens)", en: "Server profiles (without tokens)"),
        "icloud.scope.device": LText(de: "Sprache, Sound & Haptik", en: "Language, sound & haptics"),
        "icloud.scope.appgroup": LText(de: "Widgets & Live Activities", en: "Widgets & Live Activities"),
        "icloud.scope.couple": LText(de: "Paar-Schnappschuss (nur lesen)", en: "Couple snapshot (read-only)"),
        "icloud.restoreOptions": LText(de: "Wiederherstellungsoptionen", en: "Restore options"),
        "icloud.scope.coupleReadOnly": LText(
            de: "Paarinhalte werden nie lokal zurückgeschrieben: Das Original liegt immer auf eurem Server.",
            en: "Couple content is never written back locally: the original always lives on your server."
        ),
        "icloud.exportCreate": LText(de: "Verschlüsseltes Backup erstellen", en: "Create encrypted backup"),
        "icloud.exportShare": LText(de: "Backup-Datei teilen/sichern", en: "Share/save backup file"),
        "icloud.exportToDrive": LText(de: "Direkt in iCloud Drive ablegen", en: "Save straight to iCloud Drive"),
        "icloud.exportDone": LText(de: "In iCloud Drive abgelegt", en: "Saved to iCloud Drive"),
        "icloud.exportFailed": LText(de: "Export hat nicht geklappt", en: "Export didn't work"),
        "icloud.importFile": LText(de: "Aus Backup-Datei wiederherstellen", en: "Restore from backup file"),
        "icloud.importFailed": LText(de: "Die Datei ist kein SoooDreamy-Backup", en: "That file isn't a SoooDreamy backup"),
        "icloud.password": LText(de: "Passphrase (mindestens 12 Zeichen)", en: "Passphrase (at least 12 characters)"),
        "icloud.passwordConfirm": LText(de: "Passphrase wiederholen", en: "Repeat passphrase"),
        "icloud.passwordTooShort": LText(de: "Mindestens 12 Zeichen. Die Passphrase wird nirgendwo gespeichert.",
                                         en: "Use at least 12 characters. The passphrase is not stored anywhere."),
        "icloud.passwordMismatch": LText(de: "Die Passphrasen stimmen nicht überein.",
                                         en: "The passphrases do not match."),
        "icloud.passwordWarning": LText(de: "Wichtig: Ohne diese Passphrase ist das Backup endgültig nicht wiederherstellbar.",
                                        en: "Important: Without this passphrase, the backup cannot be recovered."),
        "icloud.importPasswordTitle": LText(de: "Backup entschlüsseln", en: "Decrypt backup"),
        "icloud.importPasswordHint": LText(de: "Gib die Passphrase ein, mit der diese Datei erstellt wurde.",
                                           en: "Enter the passphrase used to create this file."),
        "icloud.importPasswordFailed": LText(de: "Falsche Passphrase oder beschädigte Backup-Datei.",
                                             en: "Wrong passphrase or damaged backup file."),
        "icloud.decrypt": LText(de: "Entschlüsseln", en: "Decrypt"),
        "icloud.hintTitle": LText(de: "Ehrliche Sideload-Info", en: "Honest sideload note"),
        "icloud.sideloadHint": LText(de: "CloudKit und iCloud Drive brauchen iCloud-Entitlements, die das Signieren überleben. App-Store-/Entwickler-Signierung: alles funktioniert. Sideload-Signierer (freie Apple-ID, AltStore & Co.) entfernen sie oft — dann zeigen die Status-Punkte oben Rot und es bleibt der Datei-Export, der immer funktioniert.",
                                    en: "CloudKit and iCloud Drive need iCloud entitlements that survive signing. App-Store/developer signing: everything works. Sideload signers (free Apple ID, AltStore & co.) often strip them — then the status dots above show red and the always-working file export remains."),

        "studio.title": LText(de: "Widget-Studio", en: "Widget Studio"),
        "studio.settingsHint": LText(de: "Widgets live vorschauen & anpassen: Themes, Layouts, Momente, Fotos",
                                     en: "Preview & customize widgets live: themes, layouts, moments, photos"),
        "studio.diag.ok": LText(de: "Widgets erhalten Daten", en: "Widgets are receiving data"),
        "studio.diag.updated": LText(de: "Zuletzt aktualisiert: {time}", en: "Last updated: {time}"),
        "studio.diag.noData": LText(de: "Noch keine Widget-Daten — kurz die App nutzen, dann füllen sich die Widgets.",
                                    en: "No widget data yet — use the app for a moment and the widgets fill up."),
        "studio.diag.noGroup": LText(de: "App-Group nicht verfügbar", en: "App group unavailable"),
        "studio.diag.noGroupHint": LText(de: "Dein Sideload-Tool hat group.app.sooodreamy.shared nicht mitsigniert — Widgets können dann keine Daten der App lesen. AltStore/SideStore signieren die App-Group automatisch mit.",
                                         en: "Your sideload tool didn't sign group.app.sooodreamy.shared — widgets can't read the app's data without it. AltStore/SideStore sign the app group automatically."),
        "studio.globalTheme": LText(de: "Studio-Theme", en: "Studio theme"),
        "studio.globalThemeHint": LText(de: "Gilt für alle Widgets — einzelne Widgets können unten (oder per „Widget bearbeiten“ am Home-Bildschirm) abweichen.",
                                        en: "Applies to all widgets — individual widgets can override below (or via “Edit widget” on the home screen)."),
        "studio.theme": LText(de: "Theme", en: "Theme"),
        "studio.themeDefault": LText(de: "Studio", en: "Studio"),
        "studio.presets": LText(de: "Schnellstile", en: "Quick styles"),
        "studio.layout": LText(de: "Layout", en: "Layout"),
        "studio.layout.auto": LText(de: "Auto", en: "Auto"),
        "studio.layout.classic": LText(de: "Klassisch", en: "Classic"),
        "studio.layout.hero": LText(de: "Groß", en: "Hero"),
        "studio.layout.minimal": LText(de: "Minimal", en: "Minimal"),
        "studio.animated": LText(de: "Live-Ticker (tickende Zeiten)", en: "Live ticker (ticking times)"),
        "studio.countdownEvent": LText(de: "Angezeigter Moment", en: "Pinned moment"),
        "studio.countdownNext": LText(de: "Automatisch: nächster Moment", en: "Automatic: next moment"),
        "studio.photoSource": LText(de: "Fotoquelle", en: "Photo source"),
        "studio.photoSource.favorite": LText(de: "Favorit", en: "Favorite"),
        "studio.photoSource.newest": LText(de: "Neuestes", en: "Newest"),
        "studio.widget.days": LText(de: "Tage zusammen", en: "Days together"),
        "studio.widget.countdown": LText(de: "Countdown", en: "Countdown"),
        "studio.widget.mood": LText(de: "Stimmung", en: "Mood"),
        "studio.widget.daily": LText(de: "Frage des Tages", en: "Daily question"),
        "studio.widget.streak": LText(de: "Antwort-Serie", en: "Answer streak"),
        "studio.widget.photo": LText(de: "Euer Foto", en: "Your photo"),
        "studio.widget.sendLove": LText(de: "Liebe senden (interaktiv)", en: "Send love (interactive)"),
        "studio.widget.memory": LText(de: "An diesem Tag", en: "On this day"),
        "studio.perWidgetHint": LText(de: "Tipp: Jedes Widget lässt sich auch direkt am Home-Bildschirm anpassen — lange drücken → „Widget bearbeiten“ (Theme, Layout, Moment, Fotoquelle).",
                                      en: "Tip: every widget can also be tweaked right on the home screen — long-press → “Edit widget” (theme, layout, moment, photo source)."),

        // Couple Pulse Live Activity
        "settings.pulse": LText(de: "Live Activity: Couple Pulse", en: "Live Activity: Couple Pulse"),
        "settings.pulseHint": LText(de: "Stimmung, Online-Status, letzte Berührung & Serie deines Schatzes auf dem Sperrbildschirm & in der Dynamic Island — aktualisiert, solange die App läuft (kein Push).",
                                    en: "Your sweetheart's mood, online status, last touch & streak on the lock screen & Dynamic Island — updated while the app is running (no push)."),
        "settings.pulseStarted": LText(de: "Couple Pulse läuft", en: "Couple Pulse is live"),

        // Automations gallery (W7-Rest) — the 5 recipes from docs/SHORTCUTS.md
        "automations.title": LText(de: "Automationen", en: "Automations"),
        "automations.settingsHint": LText(de: "Wecker, Ankunft, NFC, Ladegerät & Fokus — fünf Rezepte, die Pushes ersetzen",
                                          en: "Alarm, arrival, NFC, charger & focus — five recipes that replace pushes"),
        "automations.intro": LText(de: "Der Sideload-Build bekommt keine Push-Nachrichten. Mit diesen Kurzbefehle-Automationen meldet sich SoooDreamy trotzdem von selbst — alles läuft lokal auf deinem iPhone, ohne Cloud und ohne Standort-Tracking in der App.",
                                   en: "The sideloaded build gets no push notifications. With these Shortcuts automations, SoooDreamy still speaks up on its own — everything runs locally on your iPhone, no cloud, no location tracking in the app."),
        "automations.openShortcuts": LText(de: "Kurzbefehle-App öffnen", en: "Open the Shortcuts app"),
        "automations.siriHint": LText(de: "Der Siri-Satz funktioniert auch ohne Automation — direkt aussprechen.",
                                      en: "The Siri phrase also works without an automation — just say it."),
        "automations.r1.title": LText(de: "Wecker aus → Guten Morgen", en: "Alarm off → Good morning"),
        "automations.r1.steps": LText(de: "Neue Automation → „Wecker“ → „Wird gestoppt“ → App: SoooDreamy → „Guten Morgen“",
                                      en: "New automation → “Alarm” → “Is Stopped” → App: SoooDreamy → “Good morning”"),
        "automations.r1.hint": LText(de: "Wecker stoppen schickt deinen Morgengruß — und Siri erzählt dir, ob dein Schatz schon wach ist.",
                                     en: "Stopping your alarm completes the morning check-in — and Siri tells you whether your partner is already awake."),
        "automations.r2.title": LText(de: "Ankunft zuhause → Bin-daheim-Puls", en: "Arriving home → I'm-home pulse"),
        "automations.r2.steps": LText(de: "Neue Automation → „Ankommen“ → dein Zuhause → App: SoooDreamy → „Puls senden“",
                                      en: "New automation → “Arrive” → your home → App: SoooDreamy → “Send pulse”"),
        "automations.r2.hint": LText(de: "Das klassische Pendler-Ritual. Der Orts-Auslöser läuft lokal auf dem iPhone — die App sieht deinen Standort nie.",
                                     en: "The classic commuter ritual. The location trigger runs locally on your phone — the app itself never sees your location."),
        "automations.r3.title": LText(de: "NFC-Tag am Nachttisch → Gute Nacht", en: "NFC tag on the nightstand → Good night"),
        "automations.r3.steps": LText(de: "Neue Automation → „NFC“ → beliebigen Sticker scannen → App: SoooDreamy → „Gute Nacht“",
                                      en: "New automation → “NFC” → scan any sticker → App: SoooDreamy → “Good night”"),
        "automations.r3.hint": LText(de: "Ein echter Gute-Nacht-Knopf am Nachttisch. Am schönsten als Paar — ein Tag pro Bettseite.",
                                     en: "A physical good-night button on the nightstand. Nicest as a pair — one tag per bedside."),
        "automations.r4.title": LText(de: "Ladegerät nach 21 Uhr → Gute Nacht", en: "Charger after 9 pm → Good night"),
        "automations.r4.steps": LText(de: "Neue Automation → „Ladegerät“ → „Wird angeschlossen“ → Kurzbefehl mit „Wenn“-Baustein (ab 21:00) → „Gute Nacht“",
                                      en: "New automation → “Charger” → “Is Connected” → shortcut with an “If” block (9 pm or later) → “Good night”"),
        "automations.r4.hint": LText(de: "Für alle ohne Wecker oder NFC-Tag: Nachts einstecken ist der Gute-Nacht-Moment. Der Zeitfilter lebt im Kurzbefehl — Automationen können selbst nicht nach Uhrzeit filtern.",
                                     en: "For everyone without an alarm or NFC tag: plugging in at night is the good-night moment. The time filter lives inside the shortcut — automations can't filter by hour themselves."),
        "automations.r5.title": LText(de: "Schlafen-Fokus → Schlafmodus", en: "Sleep Focus → sleep mode"),
        "automations.r5.steps": LText(de: "Einstellungen → Fokus → Schlafen → Filter hinzufügen → SoooDreamy → Presence „Schlafen“",
                                      en: "Settings → Focus → Sleep → Add filter → SoooDreamy → presence “Sleep”"),
        "automations.r5.hint": LText(de: "Die Null-Konfiguration: iOS setzt eure Paar-Presence bei jedem Fokuswechsel selbst — kein Kurzbefehl, kein Vergessen. Funktioniert auch für den Arbeits-Fokus.",
                                     en: "The zero-config option: iOS itself sets your couple presence with every focus change — no shortcut, no forgetting. Works for the Work focus too."),

        // Notifications (couple alerts — local, WebSocket-driven)
        "notif.section": LText(de: "Benachrichtigungen", en: "Notifications"),
        "notif.master": LText(de: "Paar-Benachrichtigungen", en: "Couple alerts"),
        "notif.masterHint": LText(
            de: "Lokal immer bei laufender App. Bei beendeter App nur mit bezahlter/App-Store-Signierung und konfigurierten APNs-Zugangsdaten auf dem Server.",
            en: "Always local while the app runs. When terminated, delivery additionally requires paid/App Store signing and APNs credentials on the server."
        ),
        // W8 Settings-IA: the notification details live in their own sheet,
        // the main card only shows the master switch plus a summary line.
        "notif.customize": LText(de: "Benachrichtigungen anpassen", en: "Customize notifications"),
        "notif.customizeHint": LText(de: "Ereignisse, Klang, Erinnerung und Serien-Schutz",
                                     en: "Events, sound, reminder, and streak guard"),
        "notif.summary": LText(de: "{on} von {total} Ereignissen an", en: "{on} of {total} events on"),
        "notif.sound": LText(de: "Benachrichtigungston", en: "Notification sound"),
        "notif.sound.soft": LText(de: "Sanft", en: "Soft"),
        "notif.sound.chime": LText(de: "Glöckchen", en: "Chime"),
        "notif.sound.heartbeat": LText(de: "Herzschlag", en: "Heartbeat"),
        "notif.sound.kiss": LText(de: "Kuss", en: "Kiss"),
        "notif.sound.sparkle": LText(de: "Funkeln", en: "Sparkle"),
        "notif.sound.whoosh": LText(de: "Wusch", en: "Whoosh"),
        "notif.sound.tada": LText(de: "Tada", en: "Tada"),
        "notif.sound.default": LText(de: "System", en: "System"),
        "notif.type.touch": LText(de: "Berührungen", en: "Touches"),
        "notif.type.message": LText(de: "Nachrichten", en: "Messages"),
        "notif.type.photo": LText(de: "Neue Fotos", en: "New photos"),
        "notif.type.dailyReveal": LText(de: "Frage des Tages gelüftet", en: "Daily question revealed"),
        "notif.type.partnerOnline": LText(de: "Schatz kommt online", en: "Sweetheart comes online"),
        "notif.type.coupon": LText(de: "Gutscheine", en: "Coupons"),
        "notif.message.title": LText(de: "Neue Nachricht von {name}", en: "New message from {name}"),
        "notif.message.letter": LText(de: "Ein Brief für dich", en: "A letter for you"),
        "notif.message.voice": LText(de: "Eine Sprachnachricht für dich", en: "A voice note for you"),
        "notif.message.photo": LText(de: "Ein Foto für dich", en: "A photo for you"),
        "notif.message.sticker": LText(de: "Ein selbstgemachter Sticker für dich",
                                        en: "A handmade sticker for you"),
        "notif.photo.title": LText(de: "Neues Foto von {name}", en: "New photo from {name}"),
        "notif.photo.body": LText(de: "{name} hat ein neues Foto geteilt", en: "{name} shared a new photo"),
        "notif.daily.body": LText(de: "Eure Antworten auf die Frage des Tages sind jetzt sichtbar",
                                  en: "Your answers to the daily question are revealed"),
        "notif.online.title": LText(de: "{name} ist jetzt online", en: "{name} is online now"),
        "notif.online.body": LText(de: "Jetzt wäre ein Herzklopfen perfekt …", en: "Now would be perfect for a heartbeat…"),
        "notif.coupon.title": LText(de: "Ein Gutschein von {name}", en: "A coupon from {name}"),
        "notif.coupon.body": LText(de: "{name} schenkt dir: „{title}“", en: "{name} gives you: “{title}”"),
        "notif.sleepSummary.title": LText(de: "Guten Morgen ☀️", en: "Good morning ☀️"),
        "notif.sleepSummary.body": LText(
            de: "Über Nacht von {name}: {items}",
            en: "Overnight from {name}: {items}"),
        "notif.sleepSummary.part.message.one": LText(de: "1 Nachricht", en: "1 message"),
        "notif.sleepSummary.part.message.other": LText(de: "{n} Nachrichten", en: "{n} messages"),
        "notif.sleepSummary.part.touch.one": LText(de: "1 Berührung", en: "1 touch"),
        "notif.sleepSummary.part.touch.other": LText(de: "{n} Berührungen", en: "{n} touches"),
        "notif.sleepSummary.part.photo.one": LText(de: "1 Foto", en: "1 photo"),
        "notif.sleepSummary.part.photo.other": LText(de: "{n} Fotos", en: "{n} photos"),
        "notif.sleepSummary.part.coupon.one": LText(de: "1 Gutschein", en: "1 coupon"),
        "notif.sleepSummary.part.coupon.other": LText(de: "{n} Gutscheine", en: "{n} coupons"),
        "notif.sleepSummary.part.dailyReveal.one": LText(
            de: "eure gelüftete Tagesfrage", en: "your revealed daily answer"),
        "notif.sleepSummary.part.dailyReveal.other": LText(
            de: "{n} gelüftete Tagesfragen", en: "{n} revealed daily answers"),
        "notif.streak.title": LText(de: "Eure Serie wartet auf dich", en: "Your streak is waiting for you"),
        "notif.streak.body": LText(de: "{n} Tage in Folge — heute fehlt nur noch deine Antwort. Zwei Minuten reichen.",
                                   en: "{n} days in a row — only your answer is missing today. Two minutes is plenty."),

        // Verbindungs-Doktor (W8/12#7): step-by-step connection checkup
        "doctor.title": LText(de: "Verbindungs-Doktor", en: "Connection doctor"),
        "doctor.settingsHint": LText(de: "Prüft Schritt für Schritt, wo es hakt",
                                     en: "Checks step by step where things get stuck"),
        "doctor.intro": LText(de: "Der Doktor klopft euren Server einmal komplett ab. Nichts wird verändert — er schaut nur nach.",
                              en: "The doctor gives your server a full checkup. Nothing is changed — it only looks."),
        "doctor.run": LText(de: "Untersuchung starten", en: "Start the checkup"),
        "doctor.rerun": LText(de: "Nochmal untersuchen", en: "Check again"),
        "doctor.copy": LText(de: "Ergebnis kopieren", en: "Copy results"),
        "doctor.copied": LText(de: "Ergebnis kopiert — schick es einfach in euren Chat.",
                               en: "Results copied — just drop them in your chat."),
        "doctor.pending": LText(de: "Wird geprüft …", en: "Checking…"),
        "doctor.skipped": LText(de: "Übersprungen — erst muss der Server antworten.",
                                en: "Skipped — the server needs to answer first."),
        "doctor.check.reach": LText(de: "Server erreichbar", en: "Server reachable"),
        "doctor.check.version": LText(de: "Server-Version", en: "Server version"),
        "doctor.check.session": LText(de: "Deine Sitzung", en: "Your session"),
        "doctor.check.socket": LText(de: "Live-Verbindung", en: "Live connection"),
        "doctor.reach.ok": LText(de: "Antwortet in {ms} ms", en: "Responds in {ms} ms"),
        "doctor.reach.slow": LText(de: "Antwortet, aber langsam ({ms} ms) — vielleicht schwaches WLAN oder weiter Weg.",
                                   en: "Responds, but slowly ({ms} ms) — maybe weak Wi-Fi or a long way around."),
        "doctor.reach.fail": LText(de: "Keine Antwort. Prüfe die Adresse und dein WLAN — oder macht der Server gerade Pause?",
                                   en: "No answer. Check the address and your Wi-Fi — or is the server taking a nap?"),
        "doctor.version.ok": LText(de: "Version {version}", en: "Version {version}"),
        "doctor.session.ok": LText(de: "Angemeldet und gültig", en: "Signed in and valid"),
        "doctor.session.fail": LText(de: "Der Server kennt diese Sitzung nicht mehr. Der Ausweg: einmal „Wieder verbinden“ — eure Inhalte sind sicher.",
                                     en: "The server no longer knows this session. The way out: “Reconnect” once — your content is safe."),
        "doctor.socket.ok": LText(de: "Verbunden — ihr seht euch live", en: "Connected — you see each other live"),
        "doctor.socket.connecting": LText(de: "Verbindet gerade …", en: "Connecting…"),
        "doctor.socket.fail": LText(de: "Getrennt. Die App verbindet automatisch neu, sobald der Server antwortet.",
                                    en: "Disconnected. The app reconnects automatically as soon as the server answers."),
        "doctor.noServer": LText(de: "Kein Server eingerichtet — lege zuerst unter „Server verwalten“ einen an.",
                                 en: "No server set up yet — add one under “Manage servers” first."),

        // Unsere Reise (W8/12#6): the app's story as a narrated timeline
        "journey.title": LText(de: "Unsere Reise", en: "Our journey"),
        "journey.settingsHint": LText(de: "Die Geschichte der App, Version für Version",
                                      en: "The app's story, version by version"),
        "journey.current": LText(de: "Aktuelle Version", en: "Current version"),
        "journey.4_2": LText(de: "Klarheit", en: "Clarity"),
        "journey.4_3": LText(de: "Replay & Turnier", en: "Replay & tournament"),
        "journey.4_4": LText(de: "Kein Zustand ohne Antwort", en: "No state left behind"),
        "journey.4_5": LText(de: "Große Schrift, sanfte Bewegung", en: "Big type, gentle motion"),
        "journey.4_6": LText(de: "Backup & Wiederherstellung", en: "Backup & restore"),
        "journey.4_7": LText(de: "Widgets ziehen ein", en: "Widgets move in"),
        "journey.4_8": LText(de: "Aussprache & Rücksicht", en: "Repair & consideration"),
        "journey.4_9": LText(de: "Sprache & Zugänglichkeit", en: "Language & accessibility"),
        "journey.5_0": LText(de: "Saisonkalender & Feste", en: "Season calendar & celebrations"),
        "journey.5_1": LText(de: "Spieleabend, zweite Welle", en: "Game night, second wave"),
        "journey.5_2": LText(de: "Stark auch ohne Netz", en: "Strong even offline"),
        "journey.5_3": LText(de: "Eure Farben", en: "Your colors"),
        "journey.6_0": LText(de: "Zusammen, überall", en: "Together, anywhere"),
        "journey.7_0": LText(de: "Rituale", en: "Rituals"),
        "journey.8_0": LText(de: "Erinnerungen", en: "Memories"),
        "journey.9_0": LText(de: "Nähe trotz Distanz", en: "Close despite distance"),
        "journey.10_0": LText(de: "Der große Runde", en: "The big round one"),
        "journey.10_1": LText(de: "Die Kommandobrücke", en: "The bridge"),
        "journey.11_0": LText(de: "Aus einem Guss", en: "All of a piece"),
        "journey.11_1": LText(de: "Belastbar", en: "Built to last"),
        "journey.12_0": LText(de: "Mehr Platz für euch", en: "Room for the two of you"),
        "journey.13_0": LText(de: "Bis ins letzte Detail", en: "Down to the last detail"),
        "journey.14_0": LText(de: "Papier & Licht", en: "Paper & Light"),
        "journey.15_0": LText(de: "Lampenlicht", en: "Lamplight"),
        "journey.16_0": LText(de: "Das Nachtpostamt", en: "The Night Post Office"),

        // App lock
        "lock.title": LText(de: "SoooDreamy ist gesperrt", en: "SoooDreamy is locked"),
        "lock.subtitle": LText(de: "Eure Momente gehören nur euch zwei.", en: "Your moments belong to the two of you only."),
        "lock.unlock": LText(de: "Entsperren", en: "Unlock"),
        "lock.reason": LText(de: "Eure gemeinsamen Momente entsperren", en: "Unlock your shared moments"),
        "lock.error.failed": LText(
            de: "Nicht erkannt. Versuch's nochmal mit Face ID, Touch ID oder deinem Code.",
            en: "Not recognized. Try again with Face ID, Touch ID, or your passcode."
        ),
        "lock.error.unavailable": LText(
            de: "Die Geräte-Authentifizierung ist nicht verfügbar. Prüfe Code und Biometrie in den Einstellungen.",
            en: "Device authentication is unavailable. Check passcode and biometrics in Settings."
        ),
        "lock.openSettings": LText(de: "Einstellungen öffnen", en: "Open Settings"),
        "settings.appLock": LText(de: "App-Sperre", en: "App lock"),
        "settings.appLockHint": LText(de: "Beim Öffnen mit Face ID / Touch ID oder Code entsperren",
                                      en: "Unlock with Face ID / Touch ID or passcode when opening"),

        // Monthiversary — the banner's particles carry the celebration;
        // the copy stays a plain warm sentence (one gesture, not three).
        "home.monthiversary": LText(de: "{n} Monate zusammen — genau heute",
                                    en: "{n} months together — today"),
        "home.monthiversaryOne": LText(de: "1 Monat zusammen — genau heute",
                                       en: "1 month together — today"),
        "home.anniversaryYears": LText(de: "{n} Jahre zusammen — alles Liebe zum Jahrestag",
                                       en: "{n} years together — happy anniversary"),
        "home.anniversaryOneYear": LText(de: "1 Jahr zusammen — alles Liebe zum Jahrestag",
                                         en: "1 year together — happy anniversary"),

        // Gallery → chat (photo messages; lives here — not in MemoriesL10n —
        // because the chat feature owns the flow end to end)
        "gallery.sendToChat": LText(de: "In den Chat senden", en: "Send to chat"),
        "gallery.sentToChat": LText(de: "Foto in den Chat geschickt", en: "Photo sent to chat"),

        // Coupons (global toasts + polish; the coupons screen itself lives in MemoriesL10n)
        "coupon.receivedToast": LText(de: "Ein Gutschein wartet auf dich", en: "A coupon is waiting for you"),
        "coupon.redeemedToast": LText(de: "„{title}“ ist eingelöst", en: "“{title}” redeemed"),
        "coupon.giftAgain": LText(de: "Nochmal schenken", en: "Gift again"),
        "settings.couponReminder": LText(de: "Gutschein-Ablauf-Erinnerung", en: "Coupon expiry reminder"),
        "settings.couponReminderHint": LText(de: "Erinnert dich, bevor ein Gutschein für dich abläuft (bis 48 Stunden vorher)",
                                             en: "Nudges you before a coupon gifted to you expires (up to 48 hours ahead)"),
        "notif.couponExpiry.title": LText(de: "Gutschein läuft bald ab", en: "Coupon expiring soon"),
        "notif.couponExpiry.body": LText(de: "„{title}“ läuft bald ab — ein guter Moment, ihn einzulösen.",
                                         en: "“{title}” is about to expire — a good moment to redeem it."),

        // Flashback card
        "home.flashback": LText(de: "Erinnerung", en: "Memory"),
        "home.flashbackDaysAgo": LText(de: "vor {n} Tagen", en: "{n} days ago"),
        "home.flashbackQuestion": LText(de: "Eure Frage von damals", en: "Your question back then"),
        "home.flashbackShare": LText(de: "In den Chat senden", en: "Send to chat"),
        "home.flashbackShareHeader": LText(de: "Erinnerung von vor {n} Tagen:",
                                           en: "A memory from {n} days ago:"),
        "home.flashbackShared": LText(de: "Erinnerung im Chat geteilt",
                                      en: "Memory shared to chat"),

        // Streak calendar (sheet behind the dashboard streak pill)
        "home.streakCalendar.title": LText(de: "Serien-Kalender", en: "Streak calendar"),
        "home.streakCalendar.open": LText(de: "Serien-Kalender öffnen", en: "Open streak calendar"),
        "home.streakCalendar.prevMonth": LText(de: "Voriger Monat", en: "Previous month"),
        "home.streakCalendar.nextMonth": LText(de: "Nächster Monat", en: "Next month"),
        "home.streakCalendar.legendBoth": LText(de: "Beide geantwortet", en: "Both answered"),
        "home.streakCalendar.legendMine": LText(de: "Nur du", en: "Only you"),
        "home.streakCalendar.monthCount": LText(de: "{n}× beide geantwortet in diesem Monat",
                                                en: "{n}× both answered this month"),
        "home.streakCalendar.empty": LText(de: "Noch keine gemeinsamen Antworten — eure erste Frage des Tages wartet schon.",
                                           en: "No shared answers yet — your first daily question is already waiting."),

        // "While you were away" card (missed inbox)
        "home.missedTitle": LText(de: "Während du weg warst", en: "While you were away"),
        "home.missedBody": LText(de: "Tippen, um alles nachzuholen", en: "Tap to catch up"),
        "home.missed.messages": LText(de: "Nachrichten", en: "Messages"),
        "home.missed.touches": LText(de: "Berührungen", en: "Touches"),
        "home.missed.photos": LText(de: "Fotos", en: "Photos"),
        "home.missed.coupons": LText(de: "Gutscheine", en: "Coupons"),
        "home.missed.songs": LText(de: "Songs", en: "Songs"),
        "home.missed.canvas": LText(de: "Leinwand-Kritzeleien", en: "Canvas doodles"),
        "home.missed.games": LText(de: "Spiele: du bist dran", en: "Games: you're up"),
        "home.missed.daily": LText(de: "Frage des Tages beantwortet", en: "Daily question answered"),

        // Check-in
        "checkin.title": LText(de: "Morgengruß & Gutenachtgruß", en: "Morning / goodnight check-in"),
        "checkin.morning": LText(de: "Guten Morgen", en: "Good morning"),
        "checkin.morning.done": LText(de: "Guten Morgen gesagt", en: "Said good morning"),
        "checkin.night": LText(de: "Gute Nacht", en: "Good night"),
        "checkin.night.done": LText(de: "Gute Nacht gesagt", en: "Said good night"),
        "checkin.partner.none": LText(de: "{name} hat sich heute noch nicht gemeldet",
                                      en: "{name} hasn't checked in today yet"),
        "checkin.partner.morning": LText(de: "{name} ist wach", en: "{name} is awake"),
        "checkin.partner.night": LText(de: "{name} schläft schon", en: "{name} is already asleep"),
        "checkin.toast.morning": LText(de: "{name} wünscht dir einen guten Morgen",
                                       en: "{name} wishes you a good morning"),
        "checkin.toast.night": LText(de: "{name} sagt gute Nacht",
                                     en: "{name} says good night"),

        // Hug queue
        "hug.card.title": LText(de: "Umarmungen auf Vorrat", en: "Hug queue"),
        "hug.card.teaser": LText(de: "Schick eine Umarmung auf Vorrat",
                                 en: "Queue a hug for later"),
        "hug.card.pending": LText(de: "{n} ungeöffnete Umarmungen warten auf dich",
                                  en: "{n} unopened hugs are waiting for you"),
        "hug.card.pending.one": LText(de: "Eine ungeöffnete Umarmung wartet auf dich",
                                      en: "An unopened hug is waiting for you"),
        "hug.card.pending.other": LText(de: "{count} ungeöffnete Umarmungen warten auf dich",
                                        en: "{count} unopened hugs are waiting for you"),
        "hug.compose.body": LText(de: "Auch wenn {name} gerade schläft: Leg eine Umarmung bereit — sie wartet wie ein Geschenk.",
                                  en: "Even while {name} is asleep: queue a hug — it waits like a little present."),
        "hug.compose.placeholder": LText(de: "Kleine Notiz dazu (optional)…",
                                         en: "A little note (optional)…"),
        "hug.compose.send": LText(de: "Umarmung bereitlegen",
                                  en: "Queue the hug"),
        "hug.compose.sentToast": LText(de: "Umarmung wartet auf {name}",
                                       en: "Hug is waiting for {name}"),
        "hug.pending.title": LText(de: "Für dich ({n})", en: "For you ({n})"),
        "hug.pending.from": LText(de: "Eine Umarmung von {name}", en: "A hug from {name}"),
        "hug.pending.open": LText(de: "Öffnen", en: "Open"),
        "hug.queued.title": LText(de: "Wartet auf {name}", en: "Waiting for {name}"),
        "hug.queued.plain": LText(de: "Eine feste Umarmung", en: "A big warm hug"),
        "hug.queued.hint": LText(de: "{name} bekommt sie beim nächsten App-Besuch.",
                                 en: "{name} will get it on their next visit."),
        "hug.history.title": LText(de: "Geöffnete Umarmungen", en: "Opened hugs"),
        "hug.receivedToast": LText(de: "Eine Umarmung von {name} wartet auf dich",
                                   en: "A hug from {name} is waiting for you"),
        "hug.openedToast": LText(de: "{name} hat deine Umarmung geöffnet",
                                 en: "{name} opened your hug"),
        "notif.hug.title": LText(de: "Eine Umarmung von {name}", en: "A hug from {name}"),
        "notif.hug.body": LText(de: "{name} hat dir eine Umarmung bereitgelegt.",
                                en: "{name} queued a hug for you."),

        // Now playing
        "nowplaying.title": LText(de: "Läuft gerade", en: "Now playing"),
        "nowplaying.songField": LText(de: "Song…", en: "Song…"),
        "nowplaying.artistField": LText(de: "Von wem? (optional)…", en: "Artist (optional)…"),
        "nowplaying.set": LText(de: "Status setzen", en: "Set status"),
        "nowplaying.clear": LText(de: "Status löschen", en: "Clear status"),
        "nowplaying.hint": LText(de: "Verschwindet automatisch nach 60 Minuten.",
                                 en: "Disappears automatically after 60 minutes."),
        "nowplaying.toast": LText(de: "{name} hört gerade: {title}",
                                  en: "{name} is listening to: {title}"),

        // What's new — 9.0.0
        "whatsnew.9_0.pulses.title": LText(de: "Denk-an-dich-Puls", en: "Thinking-of-you pulse"),
        "whatsnew.9_0.pulses.body": LText(
            de: "Das 💭 schickt jetzt ein fühlbares Muster: Herzschlag, Umarmung, Gute Nacht. Kommt an, auch wenn die App zu war — und du spürst, wenn es gefühlt wurde.",
            en: "The 💭 now sends a feelable pattern: heartbeat, hug, good night. It arrives even if the app was closed — and you'll know when it was felt."),
        "whatsnew.9_0.presence.title": LText(de: "Fokus & Schlafen", en: "Focus & sleep"),
        "whatsnew.9_0.presence.body": LText(
            de: "Sag sanft Bescheid, wenn du gerade nicht antworten kannst — dein Schatz sieht's als ruhigen Hinweis statt Funkstille.",
            en: "Gently signal when you can't reply right now — your sweetheart sees a calm hint instead of radio silence."),
        "whatsnew.9_0.glow.title": LText(de: "Status-Glow", en: "Status glow"),
        "whatsnew.9_0.glow.body": LText(
            de: "Der Sperrbildschirm-Puls leuchtet jetzt im Modus deines Schatzes — 🎯 blau, 😴 violett.",
            en: "The lock-screen pulse now glows with your sweetheart's mode — 🎯 blue, 😴 violet."),

        // Presence modes & pulses („Nähe trotz Distanz")
        "presence.mode.focus": LText(de: "Fokus", en: "Focus"),
        "presence.mode.sleep": LText(de: "Schlafen", en: "Sleep"),
        "presence.mode.focus.subtitle": LText(de: "Kurz konzentriert — keine Eile mit Antworten",
                                              en: "Heads-down for a bit — no rush replying"),
        "presence.mode.sleep.subtitle": LText(de: "Gute Nacht — Signale kommen leise an",
                                              en: "Good night — signals arrive quietly"),
        "presence.partnerHint.focus": LText(de: "{name} ist gerade im Fokus — Antworten dürfen warten.",
                                            en: "{name} is in focus right now — replies can wait."),
        "presence.partnerHint.sleep": LText(de: "{name} schläft — schick ruhig was, es weckt nicht.",
                                            en: "{name} is asleep — send away, it won't wake them."),
        "presence.sheet.title": LText(de: "Mein Modus", en: "My mode"),
        "presence.sheet.subtitle": LText(de: "Sag deinem Schatz sanft Bescheid, dass du gerade nicht antworten kannst — ganz ohne Worte.",
                                         en: "Gently let your sweetheart know you can't reply right now — no words needed."),
        "presence.noteField": LText(de: "Kleine Notiz (optional)…", en: "A little note (optional)…"),
        "presence.durationTitle": LText(de: "Wie lange?", en: "For how long?"),
        "presence.duration.open": LText(de: "Bis ich es ausschalte", en: "Until I turn it off"),
        "presence.duration.minutes": LText(de: "{minutes} min", en: "{minutes} min"),
        "presence.duration.hours": LText(de: "{hours} Std.", en: "{hours} h"),
        "presence.remaining.minutes": LText(de: "noch {minutes} min", en: "{minutes} min left"),
        "presence.remaining.hours": LText(de: "noch ca. {hours} Std.", en: "~{hours} h left"),
        "presence.set": LText(de: "Modus setzen", en: "Set mode"),
        "presence.clear": LText(de: "Modus beenden", en: "End mode"),
        "presence.chip": LText(de: "Modus", en: "Mode"),
        "presence.hint": LText(de: "Dein Schatz sieht den Modus als sanften Hinweis auf dem Dashboard und im Sperrbildschirm-Puls. Pulse und Nachrichten kommen weiter an — nur ohne Erwartung einer Antwort.",
                               en: "Your sweetheart sees the mode as a gentle hint on the dashboard and in the lock-screen pulse. Pulses and messages still arrive — just without expecting a reply."),
        "pulse.kind.thinking": LText(de: "Denk an dich", en: "Thinking of you"),
        "pulse.kind.goodnight": LText(de: "Gute Nacht", en: "Good night"),
        "pulse.kind.heartbeat": LText(de: "Herzschlag", en: "Heartbeat"),
        "pulse.kind.hug": LText(de: "Umarmung", en: "Hug"),
        "pulse.received.thinking": LText(de: "{name} denkt gerade an dich", en: "{name} is thinking of you right now"),
        "pulse.received.goodnight": LText(de: "{name} schickt dir eine Gute Nacht", en: "{name} sends you a good night"),
        "pulse.received.heartbeat": LText(de: "{name} schickt dir einen Herzschlag", en: "{name} sends you a heartbeat"),
        "pulse.received.hug": LText(de: "{name} umarmt dich aus der Ferne", en: "{name} hugs you from afar"),
        "pulse.sentToast": LText(de: "{emoji} Puls geschickt — genau so fühlt er sich an",
                                 en: "{emoji} Pulse sent — that's exactly how it feels"),
        "pulse.feltToast": LText(de: "{name} hat deinen Puls gefühlt", en: "{name} felt your pulse"),
        "pulse.moreWhileAway": LText(de: "+{n} weitere, während du weg warst", en: "+{n} more while you were away"),
        "pulse.moreWhileAway.one": LText(de: "+1 weiterer Puls, während du weg warst",
                                         en: "+1 more pulse while you were away"),
        "pulse.moreWhileAway.other": LText(de: "+{count} weitere Pulse, während du weg warst",
                                           en: "+{count} more pulses while you were away"),

        // v10 „Der große Runde" — recovery-key UX + settings security card
        "settings.security": LText(de: "Sicherheit & Wiederherstellung", en: "Security & recovery"),
        "recovery.title": LText(de: "Sicherheitsnetz", en: "Safety net"),
        "recovery.settingsHint": LText(de: "Wiederherstellungs-Schlüssel, Wieder-verbinden & Ersatz-Code", en: "Recovery key, reconnect & replace code"),
        "recovery.sheet.subtitle": LText(de: "Dein Weg zurück zu euch: Schlüssel im Schlüsselbund, Zettel als Backup — und zur Not hilft dir dein Lieblingsmensch.",
                                         en: "Your way back to each other: key in your keychain, paper note as backup — and if all else fails, your favorite person can help."),
        "recovery.ceremony.title": LText(de: "Dein Schlüssel zurück zu euch", en: "Your key back to each other"),
        "recovery.ceremony.subtitle": LText(de: "Falls dein Handy mal verloren geht: Mit diesem Schlüssel holen wir dich zurück zu euch beiden.",
                                            en: "If your phone ever gets lost: with this key we help you find your way back to the two of you."),
        // point1 has two honest variants — the view picks one from the REAL
        // keychain storage (SharedKeychain.recoveryKeyStorage) instead of
        // promising iCloud unconditionally.
        "recovery.ceremony.point1": LText(de: "Er liegt in deinem Schlüsselbund — iCloud nimmt ihn mit, wenn dein Schlüsselbund-Sync an ist",
                                          en: "It lives in your keychain — iCloud carries it along when keychain sync is on"),
        "recovery.ceremony.point1.local": LText(de: "Er liegt nur auf diesem Gerät — der Zettel ist dein echtes Sicherheitsnetz",
                                                en: "It lives on this device only — the paper note is your real safety net"),
        "recovery.ceremony.point2": LText(de: "Schreib ihn zusätzlich auf — Papier stirbt nie", en: "Write it down as well — paper never dies"),
        "recovery.ceremony.point3": LText(de: "Der Server kennt nur seinen Fingerabdruck, nie den Schlüssel selbst", en: "The server only knows its fingerprint, never the key itself"),
        "recovery.ceremony.done": LText(de: "Ich hab ihn sicher", en: "I've got it safe"),
        "recovery.copy": LText(de: "Schlüssel kopieren", en: "Copy key"),
        "recovery.copied": LText(de: "Kopiert", en: "Copied"),
        "recovery.key.section": LText(de: "Dein Wiederherstellungs-Schlüssel", en: "Your recovery key"),
        "recovery.status.stored": LText(de: "Schlüssel hinterlegt", en: "Key stored"),
        "recovery.status.missing": LText(de: "Noch kein Schlüssel auf diesem Gerät", en: "No key on this device yet"),
        "recovery.status.since": LText(de: "Auf dem Server hinterlegt seit {date}", en: "On the server since {date}"),
        // Real storage location (probed, not promised).
        "recovery.storage.synced": LText(de: "Im Schlüsselbund — wandert mit iCloud mit, wenn dein Schlüsselbund-Sync an ist",
                                         en: "In your keychain — travels with iCloud when keychain sync is on"),
        "recovery.storage.local": LText(de: "Nur auf diesem Gerät gespeichert — schreib ihn unbedingt auf",
                                        en: "Stored on this device only — be sure to write it down"),
        "recovery.reveal": LText(de: "Schlüssel zeigen", en: "Show key"),
        "recovery.hide": LText(de: "Schlüssel verbergen", en: "Hide key"),
        "recovery.issue": LText(de: "Schlüssel erzeugen", en: "Create key"),
        "recovery.rotate": LText(de: "Neuen Schlüssel erzeugen", en: "Create new key"),
        "recovery.rotate.confirmTitle": LText(de: "Neuen Schlüssel erzeugen?", en: "Create a new key?"),
        "recovery.rotate.confirmBody": LText(de: "Der alte Schlüssel wird sofort ungültig — auch auf deinem Zettel. Der neue landet automatisch im Schlüsselbund.",
                                             en: "The old key becomes invalid immediately — including the one on paper. The new one goes into your keychain automatically."),
        "recovery.issue.confirmBody": LText(de: "Der Schlüssel wird einmalig angezeigt und sicher im Schlüsselbund abgelegt.",
                                            en: "The key is shown once and stored safely in your keychain."),
        "recovery.rotated": LText(de: "Neuer Schlüssel aktiv — der alte gilt nicht mehr", en: "New key active — the old one no longer works"),
        "recovery.issued": LText(de: "Schlüssel erzeugt und im Schlüsselbund gesichert", en: "Key created and stored in your keychain"),
        "recovery.key.hint": LText(de: "Der Schlüssel ist dein Beweis, dass wirklich du es bist — er bringt dich nach Handyverlust oder Neuinstallation zurück in euer Paar. Der Server speichert nur einen Fingerabdruck.",
                                   en: "The key is your proof that it's really you — it brings you back into your couple after a lost phone or reinstall. The server stores only a fingerprint."),
        "recovery.replace.section": LText(de: "Schatz ausgesperrt?", en: "Love locked out?"),
        "recovery.replace.explain": LText(de: "Wenn {name} Handy und Schlüssel verloren hat, kannst du hier einen einmaligen Ersatz-Code erzeugen. Damit verbindet sich {name} neu — eure ganze Geschichte bleibt.",
                                          en: "If {name} lost both phone AND key, you can create a one-time replace code here. {name} reconnects with it — your whole history stays."),
        "recovery.replace.generate": LText(de: "Ersatz-Code erzeugen", en: "Create replace code"),
        "recovery.replace.expires": LText(de: "Gültig noch {time} · einmal verwendbar", en: "Valid for {time} · single use"),
        "recovery.replace.expired": LText(de: "Abgelaufen — erzeuge bei Bedarf einen neuen", en: "Expired — create a new one if needed"),
        "recovery.replace.cancel": LText(de: "Code zurückziehen", en: "Withdraw code"),
        "recovery.replace.cancelled": LText(de: "Ersatz-Code zurückgezogen", en: "Replace code withdrawn"),
        // "Partner hilft" — the replace code as a one-scan QR
        "recovery.replace.qrHint": LText(
            de: "Am einfachsten: Dein Schatz scannt diesen QR-Code — Server, Paar-Code und Ersatz-Code stecken schon drin. Ein Scan, wieder verbunden.",
            en: "Easiest way: your partner scans this QR code — server, couple code and replace code are already inside. One scan, reconnected."),
        "recovery.replace.qrA11y": LText(
            de: "QR-Code zum Wiederverbinden für deinen Schatz",
            en: "Reconnect QR code for your partner"),
        "recovery.replace.hint": LText(de: "Sicherheit: Der Code ersetzt die Geräte deines Schatzes — alle alten Sitzungen und der alte Schlüssel werden dabei ungültig.",
                                       en: "Security: the code replaces your partner's devices — all old sessions and the old key become invalid in the process."),
        "recovery.how.section": LText(de: "So kommt ihr immer zurück", en: "How you always get back in"),
        "recovery.how.point1": LText(de: "Normalfall: Die App heilt eine abgelaufene Sitzung von selbst — du merkst nichts.",
                                     en: "Normally: the app heals an expired session by itself — you won't notice a thing."),
        "recovery.how.point2": LText(de: "Neues Handy: „Wieder verbinden“ mit Paar-Code + Schlüssel — aus dem Schlüsselbund oder von deinem Zettel.",
                                     en: "New phone: “Reconnect” with your couple code + key — from your keychain or your paper note."),
        "recovery.how.point3": LText(de: "Alles weg: Dein Schatz erzeugt hier einen Ersatz-Code — 15 Minuten gültig, einmal verwendbar.",
                                     en: "Everything gone: your partner creates a replace code here — valid 15 minutes, single use."),
        "recovery.sessionHealed": LText(de: "Verbindung still erneuert — weiter geht's", en: "Session quietly healed — carry on"),
        "whatsnew.10_0.safetynet.title": LText(de: "Das Sicherheitsnetz", en: "The safety net"),
        "whatsnew.10_0.safetynet.body": LText(
            de: "Dein Wiederherstellungs-Schlüssel liegt jetzt im iCloud-Schlüsselbund. Neues Handy? „Wieder verbinden“ — alles ist noch da. Und zur Not holt dich dein Schatz mit einem Ersatz-Code zurück.",
            en: "Your recovery key now lives in the iCloud keychain. New phone? “Reconnect” — everything is still there. And if all else fails, your partner brings you back with a replace code."),
        "whatsnew.10_0.healing.title": LText(de: "Sitzungen heilen sich selbst", en: "Sessions heal themselves"),
        "whatsnew.10_0.healing.body": LText(
            de: "Abgelaufene Anmeldung? Die App verbindet sich im Hintergrund neu, statt dich auszuloggen. Kein „bitte neu koppeln“ mehr.",
            en: "Session expired? The app reconnects in the background instead of logging you out. No more “please pair again”."),
        "whatsnew.10_0.settings.title": LText(de: "Aufgeräumte Einstellungen & neues Onboarding", en: "Tidied settings & new onboarding"),
        "whatsnew.10_0.settings.body": LText(
            de: "Sicherheit hat jetzt ein eigenes Zuhause, das Onboarding erklärt in vier Seiten, wie alles zusammenhängt — und das zehnte Icon „Aurora“ macht die Familie komplett.",
            en: "Security has its own home now, onboarding explains everything in four pages — and the tenth icon “Aurora” completes the family."),
        "whatsnew.11_0.polish.title": LText(de: "Alles aus einem Guss", en: "All of a piece"),
        "whatsnew.11_0.polish.body": LText(
            de: "Wir sind einmal durch jede Ecke der App gegangen: ein Design aus flüssigem Glas, sanftere Bewegungen, die Enthüllung eurer Antworten als kleine Zeremonie, Fotos in einer echten Lightbox — und ein Dashboard, das den Blick auf euch beide richtet.",
            en: "We walked through every corner of the app: one liquid-glass design, gentler motion, your answers revealed as a little ceremony, photos in a real lightbox — and a dashboard that keeps the focus on the two of you."),
        "whatsnew.11_0.voice.title": LText(de: "Die App klingt jetzt nach euch", en: "The app sounds like you now"),
        "whatsnew.11_0.voice.body": LText(
            de: "Jeder Satz wurde neu gelesen: wärmeres Deutsch, ein Wort pro Ding (Tresor, Leinwand, Träumeliste), echte Klänge mit Quellenangabe — und leere Bildschirme laden ein, statt Sackgassen zu sein.",
            en: "Every sentence got a fresh read: warmer language, one word per thing (vault, canvas, dream list), real sounds with credits — and empty screens now invite instead of dead-ending."),
        "whatsnew.11_0.doctor.title": LText(de: "Verbindungs-Doktor & Unsere Reise", en: "Connection doctor & Our journey"),
        "whatsnew.11_0.doctor.body": LText(
            de: "Wenn der Server mal schweigt, prüft der Doktor in vier Schritten, woran es liegt — und nennt den Ausweg. Und unter „Unsere Reise“ erzählt die App ihre eigene Geschichte, Version für Version.",
            en: "If the server ever goes quiet, the doctor checks four steps and names the way out. And under “Our journey” the app tells its own story, version by version."),
        "whatsnew.12_0.ipad.title": LText(de: "Jetzt auch auf dem iPad", en: "Now on iPad too"),
        "whatsnew.12_0.ipad.body": LText(
            de: "Dashboard als Raster, Erinnerungen im Split, Briefe in Lese-Spalten — dazu Apple Pencil, Tastatur-Kürzel und Bild-Drop. Split View und Stage Manager inklusive.",
            en: "The dashboard as a grid, memories in a split view, letters in reading columns — plus Apple Pencil, keyboard shortcuts and image drop. Split View and Stage Manager included."),
        "whatsnew.12_0.devices.title": LText(de: "Alle deine Geräte, ein Zuhause", en: "All your devices, one home"),
        "whatsnew.12_0.devices.body": LText(
            de: "Verbinde iPhone und iPad gleichzeitig: Einmal-Code erzeugen, auf dem neuen Gerät scannen, fertig. Der Geräte-Manager in den Einstellungen behält den Überblick.",
            en: "Connect iPhone and iPad at the same time: create a one-time code, scan it on the new device, done. The device manager in Settings keeps track."),
        "whatsnew.12_0.words.title": LText(de: "Worte, die ankommen", en: "Words that arrive"),
        "whatsnew.12_0.words.body": LText(
            de: "Briefanfänge in drei Tönen, „Sag es sanft“ für Entwürfe, Übersetzungen unterm Original und Transkripte für Sprachnachrichten — alles nur auf deinem Gerät, alles freiwillig.",
            en: "Letter openings in three tones, “Say it gently” for drafts, translations below the original and transcripts for voice notes — all on your device only, all opt-in."),
        "whatsnew.12_0.tables.title": LText(de: "Spieltische & Zuschauer", en: "Game tables & spectators"),
        "whatsnew.12_0.tables.body": LText(
            de: "Auf dem iPad werden eure Spiele zu echten Tischen, deine anderen Geräte schauen fair zu — und This-or-That läuft jetzt auch zu zweit an einem Handy.",
            en: "On iPad your games become real tables, your other devices spectate fairly — and This-or-That now also plays on one shared phone."),
        "whatsnew.13_0.face.title": LText(de: "Ein neues Gesicht — eure Farben", en: "A new face — your colors"),
        "whatsnew.13_0.face.body": LText(
            de: "Der Neuanstrich färbt die App in eure beiden Farben, ersetzt Deko-Emojis durch eine ruhige Symbolsprache — und der erste Start ist jetzt ein kleines Kino aus Licht und Haptik.",
            en: "The rework tints the app in your two colors and swaps decorative emoji for a calm symbol language — and the first launch is now a little cinema of light and haptics."),
        "whatsnew.13_0.games.title": LText(de: "Neun neue Spiele", en: "Nine new games"),
        "whatsnew.13_0.games.body": LText(
            de: "Dame, Reversi, Käsekästchen, Gomoku, Mancala, Memory-Duo, Wordle-Duo, Schere-Stein-Papier und die Geschichten-Staffel — fair, server-geprüft, selbsterklärend.",
            en: "Checkers, Reversi, Dots and Boxes, Gomoku, Mancala, Memory Duo, Wordle Duo, Rock-Paper-Scissors, and the Story Relay — fair, server-verified, self-explaining."),
        "whatsnew.13_0.soul.title": LText(de: "Mehr Seele im Inhalt", en: "More soul in the content"),
        "whatsnew.13_0.soul.body": LText(
            de: "Über 240 neue zweisprachige Inhalte. Jede körperliche Karte ist eine echte Einladung mit klarem Ja — und Passen ist immer okay, ganz ohne Strafe.",
            en: "Over 240 new bilingual items. Every physical card is a real invitation with a clear yes — and passing is always okay, with no penalty at all."),
        "whatsnew.13_0.eyes.title": LText(de: "Für beide Augen gemacht", en: "Made for both pairs of eyes"),
        "whatsnew.13_0.eyes.body": LText(
            de: "Jedes Wort auf euren Verläufen erreicht jetzt den vollen Lese-Kontrast, VoiceOver spricht die neuen Spiele — und die Tagesfrage ist auf allen Geräten dieselbe, garantiert.",
            en: "Every word on your gradients now clears the full reading contrast, VoiceOver speaks the new games — and the daily question is the same on every device, guaranteed."),
        "whatsnew.14_0.room.title": LText(de: "Willkommen im Zimmer", en: "Welcome to the room"),
        "whatsnew.14_0.room.body": LText(
            de: "Die App spielt jetzt in einem warmen Zimmer bei Nacht: Lampenlicht, Papier, eure zwei Tinten. Der Chat ist echte Korrespondenz — beide Seiten schreiben auf Papier.",
            en: "The app now lives in a warm room at night: lamplight, paper, your two inks. The chat is true correspondence — both sides write on paper."),
        "whatsnew.14_0.bar.title": LText(de: "Die echte Leiste", en: "The real bar"),
        "whatsnew.14_0.bar.body": LText(
            de: "Unten schwebt jetzt die native Glas-Leiste des Systems — mit dem Heute-Zettel darüber: Präsenz deines Schatzes und der Tages-Hinweis, immer im Blick.",
            en: "The system's native glass bar now floats below — with the today slip above it: your partner's presence and the day's nudge, always in sight."),
        "whatsnew.14_0.post.title": LText(de: "Die Poststation", en: "The post station"),
        "whatsnew.14_0.post.body": LText(
            de: "Gib Zeitpost auf — eine Notiz, die in drei Tagen ankommt, als versiegelter Umschlag. Erst der Tipp deines Schatzes bricht das Wachs. Und Berührungen kannst du jetzt zurückschicken.",
            en: "Mail timed post — a note that arrives in three days as a sealed envelope. Only your partner's tap breaks the wax. And touches can now be echoed back."),
        "whatsnew.14_0.cinema.title": LText(de: "Ein Kino zum Anfang", en: "A cinema to begin with"),
        "whatsnew.14_0.cinema.body": LText(
            de: "Der erste Start ist jetzt eine Minute Kino: echte Filme, eure Tintenwahl, das Wachssiegel — und ein Finale, das sich in die echte App verwandelt. Jederzeit in den Einstellungen erneut ansehen.",
            en: "The first launch is now a minute of cinema: real films, your ink pick, the wax seal — and a finale that morphs into the real app. Rewatch anytime from Settings."),
        "whatsnew.15_0.night.title": LText(de: "Späte Nacht", en: "Late night"),
        "whatsnew.15_0.night.body": LText(
            de: "Die App lebt jetzt im Abend: dunkler Raum, dunkle Karten — und nur das Wichtige leuchtet als Papier im Lampenlicht. Eure Briefe, Polaroids und Spielbretter tragen das Licht.",
            en: "The app now lives in the evening: dark room, dark cards — and only what matters glows as paper in the lamplight. Your letters, polaroids, and game boards carry the light."),
        "whatsnew.15_0.gate.title": LText(de: "Die Lampe fragt zuerst", en: "The lamp asks first"),
        "whatsnew.15_0.gate.body": LText(
            de: "Das Intro ist von Grund auf repariert — und die Sprachfrage erscheint jetzt garantiert beim ersten Start: Deutsch oder English, eure Wahl, bevor irgendetwas anderes passiert.",
            en: "The intro is fixed from the ground up — and the language question now reliably appears on first launch: Deutsch or English, your pick, before anything else happens."),
        "whatsnew.15_0.smooth.title": LText(de: "Kino ohne Ruckler", en: "Cinema without glitches"),
        "whatsnew.15_0.smooth.body": LText(
            de: "Sieben Abspielfehler sind beseitigt: keine Doppelbilder beim Kapitelwechsel, keine dunkle Naht zwischen den Filmen, kein Schwarzbild beim Start.",
            en: "Seven playback bugs are gone: no double images on chapter changes, no dark seam between films, no black frame at the start."),
        "whatsnew.15_0.tested.title": LText(de: "Bei jedem Build benutzt", en: "Used on every build"),
        "whatsnew.15_0.tested.body": LText(
            de: "Automatische Tester bedienen die echte App: koppeln, schreiben, senden — und eine Arena lässt zwölf Paare gleichzeitig auf einem echten Server leben, Abstürze inklusive.",
            en: "Automated testers operate the real app: pairing, writing, sending — and an arena lets twelve couples live on a real server at once, crashes included."),
        "whatsnew.16_0.postamt.title": LText(de: "Euer Nachtpostamt", en: "Your night post office"),
        "whatsnew.16_0.postamt.body": LText(
            de: "Fünf Stationen statt fünf Tabs: Postfach mit Zustellrunden, Schreibstube mit Siegelpresse, Spieltisch mit Kartenschrank, Archiv mit sechs Fächern, Amt. Alles trägt dieselbe Papier-und-Licht-Welt.",
            en: "Five stations instead of five tabs: Mailbox with delivery rounds, Writing Desk with the seal press, Game Table with the card cabinet, Archive with six drawers, Bureau. All in one paper-and-light world."),
        "whatsnew.16_0.geraet.title": LText(de: "Auf echten iPhones bewiesen", en: "Proven on real iPhones"),
        "whatsnew.16_0.geraet.body": LText(
            de: "Der Fehler, der das Intro auf Geräten leer machte, ist an der Wurzel beseitigt — und die App ist gepanzert: Kein Kapitel kann je wieder leer oder eingefroren stehen.",
            en: "The bug that left the intro empty on devices is fixed at the root — and the app is armored: no chapter can ever stand empty or frozen again."),
        "whatsnew.16_0.zahlen.title": LText(de: "Ehrliche Lebenszahlen", en: "Honest lifetime numbers"),
        "whatsnew.16_0.zahlen.body": LText(
            de: "Der Spieltisch führt jetzt lebenslang Buch: Abbrüche zählen nie, alte Bestände tragen ein ehrliches Mindestens-Zeichen, und die Bilanz zählt exakt, was sie zeigt.",
            en: "The Game Table now keeps a lifetime book: aborts never count, legacy stores wear an honest at-least mark, and the record counts exactly what it shows."),
        "whatsnew.16_0.gesicht.title": LText(de: "Ein neues Gesicht", en: "A new face"),
        "whatsnew.16_0.gesicht.body": LText(
            de: "Neues mehrschichtiges App-Icon aus Nachtzimmer, goldener Tinte, Polaroid und Siegellack — und das Intro erzählt bis zur letzten Seite dieselbe Materialwelt.",
            en: "A new layered app icon of night room, golden ink, polaroid and sealing wax — and the intro tells the same material world down to its last page."),

        // Connection banner — the pill shows ONE word and never wraps; the
        // "retries on its own" half-sentence lives in the VoiceOver label.
        "conn.connecting": LText(de: "Verbinde…", en: "Connecting…"),
        "conn.offline": LText(de: "Offline", en: "Offline"),
        "conn.offline.a11y": LText(de: "Offline — die Verbindung versucht es von selbst wieder",
                                   en: "Offline — the connection retries on its own"),
        "conn.connected": LText(de: "Verbunden", en: "Connected"),

        // Errors
        "error.invalidURL": LText(de: "Ungültige Server-Adresse", en: "Invalid server address"),
        "error.decoding": LText(de: "Antwort vom Server nicht verstanden", en: "Couldn't understand the server's reply"),
        "error.network": LText(de: "Netzwerkfehler — ist der Server erreichbar?", en: "Network error — is the server reachable?"),
        // Shown only AFTER the silent v10 session healing has genuinely
        // failed (see AppState.handleAPIError) — so it points to the rejoin
        // flow instead of scaring with "pair again".
        "error.unauthorized": LText(de: "Deine Sitzung ließ sich nicht still erneuern. Eure Inhalte sind sicher — verbinde dich über „Wieder verbinden“ einmal neu.",
                                    en: "Your session couldn't renew itself. Everything is safe — reconnect once via “Reconnect”."),

        // Offline outbox
        "outbox.momentQueued": LText(
            de: "Gerade keine Verbindung — wird nachgeliefert, sobald du wieder online bist.",
            en: "No connection right now — it will be delivered once you're back online."),

        // Server error catalog → human sentences with a way out
        "error.code.too_long": LText(
            de: "Der Text ist zu lang für den Server — kürze ihn ein bisschen.",
            en: "That text is too long for the server — trim it a little."),
        "error.code.too_large": LText(
            de: "Die Datei ist zu groß — wähl eine kleinere Version.",
            en: "That file is too big — pick a smaller version."),
        "error.code.too_many_videos": LText(
            de: "Euer Video-Regal ist voll — lösch erst ein älteres Video.",
            en: "Your video shelf is full — delete an older video first."),
        "error.code.couple_full": LText(
            de: "Dieses Paar ist schon zu zweit. Wenn du dazugehörst: „Wieder verbinden“ statt „Beitreten“.",
            en: "This couple is already complete. If that's you: use “Reconnect” instead of “Join”."),
        "error.code.unknown_code": LText(
            de: "Diesen Code kennt der Server nicht — prüf ihn auf Tippfehler.",
            en: "The server doesn't know this code — check it for typos."),
        "error.code.bad_recovery_key": LText(
            de: "Der Wiederherstellungs-Schlüssel passt nicht zu diesem Code.",
            en: "That recovery key doesn't match this code."),
        "error.code.session_revoked": LText(
            de: "Diese Sitzung wurde abgemeldet — verbinde dich einmal neu.",
            en: "This session was signed out — reconnect once."),
        "error.code.unknown_session": LText(
            de: "Diese Sitzung kennt der Server nicht mehr — verbinde dich einmal neu.",
            en: "The server no longer knows this session — reconnect once."),
        "error.code.expired": LText(
            de: "Zu spät — das ist inzwischen abgelaufen.",
            en: "Too late — that has expired in the meantime."),
        "error.code.already_redeemed": LText(
            de: "Schon eingelöst — schaut in eure Erinnerungen.",
            en: "Already redeemed — check your memories."),
        "error.code.wrong_turn": LText(
            de: "Gerade ist dein Schatz dran — gleich wieder du.",
            en: "It's your sweetheart's turn — you're up again in a moment."),
        "error.code.game_ended": LText(
            de: "Diese Runde ist schon vorbei — starte einfach eine neue.",
            en: "That round is already over — just start a new one."),
        "error.code.game_lease_held": LText(
            de: "Ein anderes deiner Geräte spielt diese Partie — tippe im Banner auf „Hier weiterspielen“.",
            en: "Another of your devices is playing this match — tap “Play here” in the banner."),
        "error.code.game_not_active": LText(
            de: "Das Spiel läuft gerade nicht — öffne es einmal neu.",
            en: "That game isn't running right now — reopen it once."),
        "error.code.no_partner": LText(
            de: "Dafür braucht es euch beide — dein Schatz ist noch nicht dabei.",
            en: "That takes both of you — your sweetheart hasn't joined yet."),
        "error.code.not_yours": LText(
            de: "Das gehört deinem Schatz — nur er oder sie kann das ändern.",
            en: "That belongs to your sweetheart — only they can change it."),
        "error.code.not_for_you": LText(
            de: "Das ist für deinen Schatz bestimmt, nicht für dich",
            en: "That one is meant for your sweetheart, not for you"),
        "error.code.cooldown_active": LText(
            de: "Noch einen Moment — das ging gerade eben schon raus.",
            en: "One moment — that just went out a second ago."),
        "error.code.too_soon": LText(
            de: "Kurz durchatmen — in {s} s geht's weiter.",
            en: "Take a breath — ready again in {s}s."),
        "error.code.effect_cooldown": LText(
            de: "Effekte machen kurz Pause — in {s} s geht's weiter.",
            en: "Effects are taking a short break — ready again in {s}s."),
        "error.code.server_capacity": LText(
            de: "Der Server hat gerade alle Hände voll — versuch es gleich nochmal.",
            en: "The server has its hands full right now — try again shortly."),
        // Post & Sendungen (FullRelease P6-B)
        "error.code.post_limit": LText(
            de: "Fünf Sendungen warten schon — lass erst eine ankommen oder nimm eine zurück.",
            en: "Five deliveries are already waiting — let one arrive or take one back first."),
        "error.code.echo_expired": LText(
            de: "Das Echo-Fenster ist zu — nach zehn Minuten schickst du besser etwas Eigenes.",
            en: "The echo window has closed — after ten minutes, send something of your own instead."),
        "error.code.echo_taken": LText(
            de: "Diese Berührung kam schon einmal zurück — einmal ist genau richtig.",
            en: "That touch already bounced back once — once is just right."),
        "error.code.bad_deliver_at": LText(
            de: "Diese Zeitpost konnte nicht mehr aufgegeben werden — ihr Zeitpunkt ist inzwischen vorbei. Wähl einen neuen Moment.",
            en: "That timed delivery could no longer be posted — its moment has passed. Pick a new one."),
        "error.code.couple_data_quarantined": LText(
            de: "Der Server schützt eure Daten gerade vor einem Speicherfehler. Nichts ist verloren — bitte meldet euch bei der Person, die euren Server betreibt.",
            en: "The server is protecting your data from a storage fault. Nothing is lost — please contact whoever runs your server."),
        "error.status.400": LText(
            de: "Der Server konnte die Anfrage nicht verstehen ({code}). Passiert das öfter, aktualisiere die App.",
            en: "The server couldn't understand that request ({code}). If it keeps happening, update the app."),
        "error.status.403": LText(
            de: "Dafür fehlt gerade die Berechtigung ({code}).",
            en: "You don't have permission for that right now ({code})."),
        "error.status.404": LText(
            de: "Nicht mehr gefunden — vielleicht wurde es gerade gelöscht.",
            en: "Not found anymore — it may have just been deleted."),
        "error.status.409": LText(
            de: "Das hat sich gerade überschnitten ({code}) — lad einmal neu.",
            en: "That crossed paths with something else ({code}) — refresh once."),
        "error.status.413": LText(
            de: "Das ist zu groß für den Server — wähl eine kleinere Version.",
            en: "That's too big for the server — pick a smaller version."),
        "error.status.429": LText(
            de: "Kurz durchatmen — zu viele Anfragen. In {s} s geht's weiter.",
            en: "Take a breath — too many requests. Ready again in {s}s."),
        "error.status.500": LText(
            de: "Der Server hat gerade Schluckauf — eure Daten sind sicher, versuch es gleich nochmal.",
            en: "The server has the hiccups — your data is safe, try again shortly."),
        "error.status.other": LText(
            de: "Unerwartete Server-Antwort ({code}) — versuch es gleich nochmal.",
            en: "Unexpected server reply ({code}) — try again shortly."),
        "error.transport.offline": LText(
            de: "Du bist gerade offline — sobald Netz da ist, klappt's wieder.",
            en: "You're offline right now — it'll work again as soon as you have signal."),
        "error.transport.timeout": LText(
            de: "Der Server braucht gerade zu lange — versuch es gleich nochmal.",
            en: "The server is taking too long — try again shortly."),
        "error.transport.unreachable": LText(
            de: "Euer Server ist gerade nicht erreichbar — läuft er, und stimmt die Adresse?",
            en: "Your server can't be reached right now — is it running, and is the address right?"),

        // Misc
        "misc.partnerDefault": LText(de: "dein Schatz", en: "your partner"),
        // Genitive twin for templates using {nameGen} when no name is set —
        // "dein Schatz'" would be wrong German, so the fallback declines.
        "misc.partnerDefaultGen": LText(de: "deines Schatzes", en: "your partner's"),
        "misc.dissolvedTitle": LText(de: "Euer Paar wurde aufgelöst", en: "Your couple was dissolved"),
        "misc.partnerJoinedToast": LText(de: "{name} ist beigetreten — jetzt seid ihr verbunden",
                                         en: "{name} joined — you're connected now")
    ]
}
