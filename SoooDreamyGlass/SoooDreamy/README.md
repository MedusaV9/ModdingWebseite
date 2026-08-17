# 💜 SoooDreamy

**Die App für euch zwei.** Eine moderne iOS-Couple-App (SwiftUI, iOS 26) mit eigenem, selbst gehostetem Mini-Server samt Admin-Webpanel — eure Daten gehören nur euch.

> The app for the two of you: a modern iOS couple app with a tiny self-hosted server — your data stays yours. Fully bilingual (Deutsch/English).

**made by Sonic0810**

## ✨ Features

- **Herzklopfen & Berührungen** — sende Herzklopfen, Küsse, Umarmungen … mit echten CoreHaptics-Mustern und synthetisierten Sounds. Empfangene Berührungen erscheinen als Vollbild-Moment.
- **3D-Herz** — ein prozedural generiertes, schlagendes SceneKit-Herz auf dem Dashboard (tippen = Herzklopfen senden 💓).
- **Chat** — Texte, 💌 Liebesbriefe (mit eigenem Composer + Vollbild-Leser) und Sprachnachrichten mit Live-Pegel, Tipp-Indikator, Tag-Gruppierung, **Emoji-Reaktionen** (Doppeltipp ❤️).
- **„Öffnen wenn…"-Briefe** 🔒 — versiegelte Liebesbriefe („Öffne mich, wenn du traurig bist / mich vermisst / nicht schlafen kannst …"); der Empfänger bricht das Siegel mit einer dramatischen Enthüllungs-Animation.
- **Frage des Tages** — 229 bilinguale Fragen, deterministisch pro Tag & Paar; Antworten werden erst enthüllt, wenn beide geantwortet haben. Mit 🔥-Serie (Streak) und **📖 „Unser Tagebuch"** zum Durchblättern aller bisherigen Antworten.
- **💘 Liebes-Wordle** — tägliches Paar-Wordle: beide raten dasselbe Wort (535 deutsche / 487 englische Wörter), Ergebnis-Grid direkt in den Chat teilen.
- **Spiele** — „Wer kennt wen besser?"-Quiz, This-or-That, Würdest-du-eher (alle realtime-multiplayer über den Server), Wahrheit-oder-Pflicht (Couple-Edition, 3 Schärfegrade), die 36 Fragen zum Verlieben, Date-Ideen-Generator mit Filtern (140+ Ideen, auch für Fernbeziehungen).
- **🆕 2.0-Spiele (live zu zweit)** — **4 Gewinnt** (klassisches Brett, Gewinner-Reihe leuchtet), **Foto-Memory** (Paare finden mit euren eigenen Galerie-Fotos — Treffer = Punkt + nochmal dran), **Liebes-Quiz-Duell** (gleiche Frage auf beiden Handys, schnellste richtige Antwort kassiert doppelt). Alle drei laufen deterministisch über das Server-Move-Relay: beide Handys leiten den identischen Spielstand aus derselben Zugliste ab.
- **Gemeinsame Galerie** — Fotos hochladen (automatisch verkleinert, mit Grid-Thumbnails), Vollbild-Pager, in die Fotobibliothek sichern.
- **🆕 Videos** 🎬 — Videos aufnehmen/hochladen (Client-Transcoding auf sinnvolle Größe, Thumbnails), Server streamt mit Range-Requests, Vollbild-Player mit Sichern in die Fotobibliothek.
- **🆕 Sechs neue Couple-Features (2.0)** — **Morgen-/Gutenacht-Check-in** ☀️🌙 mit gemeinsamer 🔥-Serie, **Umarmungs-Warteschlange** 🫂 (queuen während der Schatz schläft, öffnen wie ein Geschenk), **gemeinsame Listen** 📝 (Einkauf/Filme, live abhaken), **Foto des Tages** 📷 (jeder kürt täglich ein Galerie-Foto), **„Gerade am Hören"** 🎧 (Musik-Status, verfällt nach 60 min), **„Unser Jahr"** ✨ (Jahresrückblick in Zahlen, teilbar in den Chat).
- **🆕 Tresor (Spicy Vault)** 🌶️🔒 — Ende-zu-Ende-verschlüsselter Bereich für private Paar-Inhalte (eigene PIN + Face ID, Panik-Verstecken); Details unten.
- **🆕 Haptik-Studio** 🎛️ — eigene Vibrationsmuster aufnehmen, in der gemeinsamen Bibliothek verwalten und dem Partner senden; Details unten.
- **🆕 Rituale & Beziehung (3.0)** 💞 — **„Wie war dein Tag?"-Audio-Check-in** 🎙️ (Enthüllung erst wenn BEIDE aufgenommen haben, mit 🔥-Streak), **Zeitkapsel-Briefe** 💌 (versiegelt bis zum Wunschdatum, dramatische Öffnung), **Bedürfnis-Knopf** 🫶 („Ich brauche gerade… Raum/Zuspruch/Ablenkung/Nähe/Zuhören"), **gemeinsame Ziele & Sparziele** 🎯 (Meilenstein-Konfetti beidseitig), **„Unsere Woche"** 🗓️ (Verfügbarkeits-Board + wiederkehrende Slots), **Energie-Ampel** 🚦 und das **„Unser Monat"-Magazin** 📖 (blätterbare Monats-Ausgabe eurer Momente).
- **🆕 Spiele-Offensive (3.0)** 🎮 — **Schiffe versenken** 🚢 (kryptografischer Fair-Play-Beweis via Commit-Reveal), **Montagsmaler** 🎨, **Kniffel-Liebesedition** 🎲, **Film-Roulette** 🍿 (Swipe-Matching), **Stadt-Land-Fluss** 🗺️, **Zwei Wahrheiten, eine Lüge** 🤥, **Paar-Tagesquests** ⚔️ (3 Mini-Missionen täglich) — plus **parallele Sessions**, **Turnier-Modus mit Saison-Trophäen** 🥇 und **Replay & Zuschauer-Modus** 🎬 für jede beendete Partie.
- **🆕 Level, Delight & Plattform (3.0)** ✨ — **Beziehungs-Level** 💜 (XP für alles, was ihr zusammen macht — rückwirkend fair aus eurer Historie, 10 Titel von „Frisch verliebt" bis „Legendäres Duo", Level-Up-Zeremonie beidseitig), **20 Abzeichen als Glas-Medaillen** 🏅 (4 geheime), **App-Icon-Geschenke** 🎁 (10 prozedurale Icon-Varianten, Auspack-Zeremonie), **Haptik-Duett + Live-Herzschlag** 🫀 (synchron auf beiden iPhones), **Date-Night-Live-Activity** 🌃, **Saison-Themes** 🍂, **Polaroid-Foto-Widgets** 📸, **iOS-18-Controls** 🎛️ (Kontrollzentrum/Action Button) und die **„Erste Woche"-Quest** für frische Paare — alles gefeiert von der neuen **Delight-Engine** 🎉.
- **🔐 Coherence & Security (4.0)** — alle Spielzüge und Ergebnisse werden serverseitig validiert/abgeleitet; HTTP ist für das private Standard-Setup bewusst möglich und `REQUIRE_HTTPS=1` härtet öffentliche Setups; Geräte-Sessions sind ablaufbar, rotierbar und widerrufbar; Bearer liegen im Keychain statt in URLs. Dazu kommen verschlüsselte Exporte, persistente Chat-Outbox/Cold-Cache, gehärtete Widgets und ein ehrlich extern gegateter APNs-Pfad. Details: [`docs/CHANGELOG.md`](docs/CHANGELOG.md).
- **🆕 Rituale, Erinnerungen & Nähe (7.0–9.0)** — **„Eure Woche in Zahlen"** 📊 (Wochen-Rückblick als Liquid-Glass-Magazin, beidseitig identisch vom Server berechnet), **eigene Tagesfragen** ✍️ (eure Fragen wandern in die tägliche Rotation), **„An diesem Tag"-Karten** 🗓️ + **„Unsere Geschichte"-Timeline** 📖 + **Memory-Widget**, sowie **Fokus-/Schlaf-Modi** 🌙 mit Partner-Status-Glow in der Live Activity und dem **„Ich denk an dich"-Puls** 💗, den der Schatz als echtes Haptik-Muster fühlt.
- **🆕 Das Sicherheitsnetz (10.0)** 🕸️ — beim Koppeln bekommt jede Person einen **Wiederherstellungs-Schlüssel** (iCloud-Schlüsselbund + einmalige Zeremonie); **„Wieder verbinden"** holt den eigenen Platz nach Handywechsel/Neuinstallation zurück, kürzlich abgelaufene Sitzungen heilen sich innerhalb einer 24-h-Nachfrist, und für den ausgesperrten Partner gibt es den **Ersatz-Code**. Dazu: neu gebautes Liquid-Glass-Onboarding, aufgeräumte Einstellungen („Sicherheit & Wiederherstellung") und das zehnte Icon **„Aurora"** 🌌. Alle Wieder-Verbinden-Wege als Runbook: [`../docs/RECOVERY.md`](../docs/RECOVERY.md).
- **🆕 Die Kommandobrücke (10.1)** 🖥️ — der Server bringt ein **Admin-Webpanel** unter `/admin` mit (gleicher Prozess, Passwort bei jedem Start frisch im Konsolen-Banner): Paare-Übersicht, Codes zurücksetzen, Geräte ausloggen, Backups, Log-/Audit-Tail — und der **einmalige Login-QR** je Platz: Handy scannt den `sooodreamy://rejoin`-Deep-Link und verbindet sich ohne weitere Eingabe wieder. Außerdem zielt die App jetzt direkt auf **iOS 26** (echtes `glassEffect` überall, siehe [`../docs/IOS-26.md`](../docs/IOS-26.md)). Details: [`../docs/ADMIN-PANEL.md`](../docs/ADMIN-PANEL.md).
- **🆕 Aus einem Guss (11.0)** ✨ — die große **Polish-Offensive**: ein Liquid-Glass-Designsystem für jede Ecke der App, die **Enthüllung als Zeremonie**, ein Dashboard mit Fokus, eine echte **Foto-Lightbox**, die Live-Activity-Brücke zum Sperrbildschirm, mehr Siri, sanfte **Sounds mit Credits** — und der **Sprachpass**: jeder Satz neu gelesen, ein Wort pro Ding (Tresor, Leinwand, Träumeliste), leere Bildschirme laden ein statt Sackgasse zu sein. Die Einstellungen bekamen eine Landkarte (Benachrichtigungs-Blatt, Scope-Anzeigen, Gefahrenzone, **Verbindungs-Doktor**, „Unsere Reise“-Timeline). Die ganze Geschichte: [`../PATCHNOTES.md`](../PATCHNOTES.md).
- **Kritzel-Leinwand** — zeichnet zusammen in Echtzeit (WebSocket), Stift/Marker/Radierer + Undo.
- **Träumeliste** — eure gemeinsamen Träume, mit Konfetti beim Abhaken.
- **Momente & Countdowns** — Jahrestage & besondere Termine, optional jährlich wiederholend, mit **Live Activity / Dynamic Island Countdown**. Das Dashboard feiert **Monatstage & Jahrestage** automatisch. 🎉
- **Stimmungen** — Mood + Notiz teilen, Partner-Stimmung auf Dashboard & Widget, **Stimmungsverlauf-Timeline** in den Love-Stats.
- **Love-Stats** — Tage zusammen, gesendete vs. empfangene Berührungen, Nachrichten, Spiele, Streak.
- **Widgets 2.0** — 8 Widgets (Tage zusammen, Stimmung, Countdown, Tagesfrage, Streak, Foto, Canvas, Liebe senden) in **allen Größen** inkl. Lock Screen/StandBy, mit tickenden Countdowns, **interaktiven AppIntent-Buttons** („Herzklopfen senden" direkt vom Home Screen) und Themes/Layouts pro Widget — konfigurierbar im **🎨 Widget-Studio** (Einstellungen) mit Live-Vorschau.
- **App Intents / Siri** — „Schick Liebe mit SoooDreamy", Partner-Stimmung abfragen.
- **App-Sperre** 🔒 — optional per Face ID / Touch ID / Code.
- **Mehrere Server, ein Tap** — Server in den Einstellungen anlegen, testen, **wechseln** (jeder Server hat seine eigene Kopplung). Pairing per 6-stelligem Code **oder QR-Code** (Server + Code in einem Scan).

## 🏗 Architektur

Ein Server-Prozess, zwei iPhones, ein Browser — mehr ist es nicht:

```
 iPhone A (SoooDreamy)                          iPhone B (SoooDreamy)
        │  REST + WebSocket (privates HTTP/WS,         │
        │  HTTPS/WSS als harter Opt-in)                │
        ╰──────────────►  Node-Server  ◄───────────────╯
                          (1 Prozess)
                          ├── /api/…    REST + WS: Paar, Chat, Spiele, Medien
                          │             (JSON-Segmente + Medienordner auf Platte)
                          └── /admin    Admin-Webpanel für die Betreiberin
                                        (Browser; Passwort im Start-Banner,
                                         Login-QR → sooodreamy://rejoin)
```

```
SoooDreamy/
├── server/          Node.js ≥ 20, ws + qrcode. REST + WebSocket, JSON-Segment-Storage mit WAL.
│   ├── src/         REST/WS + v4 Security, Game Rules/Migrations und optionaler APNs-Provider
│   │   └── admin/   Admin-Webpanel (/admin): Backend + statisches Frontend
│   └── test/        node:test E2E-/Security-/Adversarial-Suite (360+ Tests)
├── ios/
│   ├── project.yml  XcodeGen-Projektdefinition (App + Widget-Extension, iOS 26)
│   ├── SoooDreamy/  App-Target (SwiftUI)
│   ├── Widgets/     WidgetKit-Extension (8 Widgets + 3 Live Activities + Controls)
│   ├── Shared/      In beide Targets kompiliert (Widget-Snapshot, Widget-Einstellungen, Live-Activity-Attributes)
│   ├── LogicTests/  SwiftPM-Pure-Logic-Tests (inkl. Outbox, Cold Cache und FIFO)
│   └── scripts/     GenerateIcon.swift — rendert alle 10 App-Icon-Varianten prozedural (keine Binärdateien im Repo)
└── docs/            API.md (REST + WS-Spezifikation), CHANGELOG.md, CREDITS.md
```

Guides auf Repo-Ebene: [`../docs/HANDBUCH.de.md`](../docs/HANDBUCH.de.md) / [`../docs/MANUAL.en.md`](../docs/MANUAL.en.md) (Handbuch), [`../docs/ADMIN-PANEL.md`](../docs/ADMIN-PANEL.md), [`../docs/RECOVERY.md`](../docs/RECOVERY.md), [`../docs/SIDELOAD-ESIGN.md`](../docs/SIDELOAD-ESIGN.md), [`../docs/SOOODREAMY-LITE.md`](../docs/SOOODREAMY-LITE.md).

## 🖥 Server starten

```bash
cd SoooDreamy/server
npm install
npm start            # PORT=4321 HOST=0.0.0.0 DATA_DIR=./data
```

Der Server läuft auf allem, was Node 20+ kann (Raspberry Pi, NAS, alter Laptop, Cloud-VM). Beim Start druckt die Konsole den aktiven Transportmodus, einen gerahmten Banner mit der **Admin-Panel-URL** (`/admin`) und einem frischen Passwort — plus einen **QR-Code direkt im Terminal**. Der QR öffnet eine freundliche Startseite mit kopierbarer Serveradresse. Standard-HTTP ist für das kleine private Setup bewusst aktiv, aber unverschlüsselt; für Fernbeziehungen bevorzugt Tailscale oder HTTPS. Details in `server/README.md`; Admin-Panel: [`../docs/ADMIN-PANEL.md`](../docs/ADMIN-PANEL.md).

```bash
npm test             # E2E-/Security-/Adversarial-Suite (node:test, 330+ Tests)
```

## 📱 App bauen

**Unsigniertes IPA aus CI:** Der GitHub-Actions-Workflow `SoooDreamy` baut bei jedem Push automatisch `SoooDreamy-unsigned-<version>.ipa` **und** `SoooDreamy-Lite-unsigned-<version>.ipa` (ohne Widgets, nur eine Bundle-ID — siehe [`../docs/SOOODREAMY-LITE.md`](../docs/SOOODREAMY-LITE.md)) — als Workflow-Artifacts und als Download im rollenden Release [`sooodreamy-latest`](https://github.com/MedusaV9/BiggerRepo/releases/tag/sooodreamy-latest).

Zum Installieren gibt es zwei Wege:

- **Mit Rechner:** [AltStore](https://altstore.io), [SideStore](https://sidestore.io) oder Sideloadly signieren das IPA beim Installieren mit eurer (kostenlosen) Apple-ID — inklusive Widget-Extension und App Group. Schritt für Schritt: [`../docs/HANDBUCH.de.md`](../docs/HANDBUCH.de.md) / [`../docs/MANUAL.en.md`](../docs/MANUAL.en.md), Kapitel 2.
- **Ohne Rechner:** ESign bzw. der Nachfolger KSign (oder [Feather](https://github.com/khcrysalis/Feather) mit bezahltem Developer-Account) signieren direkt auf dem iPhone. Achtung Widgets: beide Bundle-IDs mitsignieren, App Groups brauchen ein passendes Zertifikat — ausführlicher Guide inkl. Vergleichstabelle und Troubleshooting: [`../docs/SIDELOAD-ESIGN.md`](../docs/SIDELOAD-ESIGN.md).

**Lokal mit Xcode (macOS):**

```bash
brew install xcodegen
cd SoooDreamy/ios
swift scripts/GenerateIcon.swift SoooDreamy/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png
xcodegen generate
open SoooDreamy.xcodeproj
```

> ⚠️ Hinweise zum unsignierten Build: Remote-Push ist im Client und Server verdrahtet, funktioniert aber nur, wenn das iOS-Provisioning-Profil die Push-Capability (`aps-environment`) trägt **und** der Server gültige APNs-Zugangsdaten hat. Typische Gratis-/Unsigned-Sideloads erfüllen das nicht; dann bleiben WebSocket-Hinweise bei laufender App und lokale Erinnerungen. App Groups (Widget-Daten) funktionieren, wenn euer Sideload-Tool die `group.app.sooodreamy.shared`-Entitlement mitsigniert; sonst zeigen Widgets Platzhalter.

> 🔒 **Drei ehrliche Transportmodi:** Ohne Flag erlaubt der Server HTTP/WS für das vertraute private Setup (kein Transportschutz). `ALLOW_HTTP_PRIVATE_LAN=1` beschränkt Klartext auf private/Tailscale-Quellen. Öffentlich erreichbare Server gehören hinter HTTPS/WSS (Caddy/nginx) mit `TRUST_PROXY=1 REQUIRE_HTTPS=1`.

### 🔄 Background-Refresh (ehrliche Einordnung)

Die App registriert einen `BGAppRefreshTask` (`app.sooodreamy.refresh`), der im Hintergrund Partner-Status, Momente und den Frage-des-Tages-Stand vom Server holt und alle Widgets aktualisiert. **Aber:** iOS entscheidet selbst, wann (und ob) solche Tasks laufen — abhängig von Nutzungsmuster, Akku, Ladezustand und Low-Power-Mode. Realistisch sind ein paar Läufe pro Tag, garantiert ist keiner; `earliestBeginDate` ist nur eine Untergrenze. Deshalb verlässt sich SoooDreamy nicht darauf: Das Foto-Widget lädt selbst nach, Tages-Zähler tragen vordatierte Timeline-Einträge, tickende Countdown-Timer laufen ohne Updates weiter, und beim App-Öffnen wird immer alles frisch geladen. Auf Sideload-Builds funktioniert Background-Refresh grundsätzlich, sobald das Signing-Tool die Standard-Entitlements setzt — im iOS-Einstellungsmenü muss „Hintergrundaktualisierung“ für SoooDreamy erlaubt sein.

### 🔔 Push bei beendeter App (externes Gate)

Der v4-Server besitzt registrierungs-, widerrufs- und zustellbare APNs-Pfade; der iOS-Client registriert sein Token pro authentifiziertem Gerät. Push-Payloads enthalten keine Chattexte oder andere freie private Inhalte. Vollständige Zustellung bei beendeter App ist trotzdem **kein rein im Repository abschließbares Feature**: Erforderlich sind ein bezahltes Apple-Developer-/App-Store-Provisioning mit Push-Capability sowie ein APNs-`.p8`-Schlüssel, Team-ID und Key-ID auf dem Server. Ohne diese Voraussetzungen meldet der Server `deliveryAvailable: false` und behauptet keine Zustellung. Details stehen in `server/README.md`.

### ⚡ Live Activities (Countdown & Couple Pulse)

Live Activities werden ohne Push-Zugang (unsigned/Sideload) nur aktualisiert, solange die App läuft — tickende Timer (`Text(timerInterval:)`) und Fortschrittsbalken animieren aber systemseitig weiter, auch wenn die App geschlossen ist. Inhalte, die nicht mehr aktualisiert werden können, markiert iOS über das gesetzte `staleDate` als veraltet. Stil und angezeigte Elemente konfiguriert ihr in der App unter Einstellungen → Live Activity.

### ☁️ iCloud-Backup (ehrliche Einordnung)

Unter Einstellungen → iCloud & Backup sichert die App **Server-Metadaten ohne Sitzungstokens** und App-Einstellungen in die private CloudKit-Datenbank des eigenen Apple-Accounts. Nach einem Restore muss ein neues Gerät deshalb ehrlich neu gekoppelt werden. Zusätzlich gibt es einen portablen `.sooodreamy`-Export (Schnappschuss von Momenten/Träumeliste/Songs/Gutscheinen), der immer per AES-GCM verschlüsselt ist; der Schlüssel wird mit PBKDF2-SHA256 (210k Iterationen, zufälliges Salt) aus einer mindestens 12 Zeichen langen Passphrase abgeleitet. Die Passphrase wird nicht gespeichert — vergessen bedeutet nicht wiederherstellbar. CloudKit und der iCloud-Drive-Container brauchen Entitlements, die die Signierung überleben; der verschlüsselte Datei-Export über das Teilen-Menü funktioniert ohne diese Entitlements.

### 🌶️ Tresor (Ende-zu-Ende verschlüsselt)

Der Tresor (Wir-Tab → Tresor 🔒) ist ein separat gesicherter Bereich für private Paar-Inhalte (Fotos, Videos, Notizen) mit **eigener PIN** — unabhängig von der App-Sperre. Kryptografie: Der Schlüssel wird per **PBKDF2-SHA256** (210k Iterationen, zufälliges Salt) aus eurer gemeinsamen Tresor-PIN abgeleitet und **verlässt nie eure Geräte**; jeder Eintrag wird on-device per **AES-GCM** (CryptoKit) versiegelt. Der Server speichert ausschließlich Ciphertext-Blobs plus die öffentlichen KDF-Parameter — echte Ende-zu-Ende-Verschlüsselung. Face-ID-Entsperrung läuft über eine biometrisch geschützte Schlüsselkopie im lokalen Keychain (ThisDeviceOnly, synct nie). Tresor-Inhalte tauchen **niemals** in Widgets, im App-Group-Snapshot, in Benachrichtigungen oder im iCloud-/Datei-Backup auf. Schütteln sperrt den Tresor sofort (Panik-Verstecken, abschaltbar). Ehrlich: PIN vergessen = Inhalte weg (Reset löscht alles) — das ist der Preis von E2E ohne Hintertür.

### 🎛️ Haptik-Studio (eigene Vibrationen)

Im Home-Tab (unter „Liebe senden") liegt das Haptik-Studio: Auf dem Aufnahme-Pad tippst/hältst du deinen Rhythmus — **kurzer Tap = Klopfen** (je länger der Kontakt, desto kräftiger), **langes Halten = sanftes Beben**. Das Muster lässt sich sofort fühlen, spontan an den Partner senden oder benannt (mit Emoji) in eurer **gemeinsamen Bibliothek** speichern. Technisch wird jede Aufnahme als kompakte Event-Timeline gespeichert und auf dem Gerät ins **AHAP-Format** (Apple Haptic and Audio Pattern) übersetzt, das CoreHaptics direkt abspielt. Mitgelieferte Presets: Herzschlag 💓, Schmetterlinge 🦋, Regen 🌧️, SOS-Kuss 😘, Meeresrauschen 🌊, Funkeln ✨. Beim Empfang übernimmt ein Vollbild-Moment mit Puls-Ringen das Display und das iPhone spielt das Muster ab; die **Verlaufs-Liste** im Studio bewahrt die letzten 100 gesendeten/empfangenen Vibes auf, damit auch ein offline gewesener Partner nichts verpasst. Ehrlich: Haptik braucht eine Taptic Engine — im Simulator und auf den meisten iPads ist nichts zu spüren (die App zeigt dann einen Hinweis).

### 🔊 Sound-Engine 2.0

Alle App-Sounds sind weiterhin **Original-Synthese ohne gebündelte Audio-Dateien** — in 2.0 aber deutlich hochwertiger: Stereo-Voices mit Cent-Verstimmung, echte Attack/Decay-Hüllkurven, inharmonische Glas-Glocken-Spektren, animiert gefiltertes Rauschen und Echo-Fahnen mit Soft-Knee-Sättigung. Sieben neue Sounds (u. a. Brief-Siegel, Vault-Unlock, Gewinn-Fanfare, mitfühlender Lose-Seufzer, Vibe-Pad). Standard-Lautstärken sind bewusst sanft und in den Einstellungen **pro Kategorie regelbar** (Momente/Chat/Spiele/Interface, Preview beim Loslassen des Reglers). Details & Begründung, warum keine CC0-Downloads gebündelt sind: `docs/CREDITS.md`.

## 🔄 Feedback-Loop

Dieses Projekt wird iterativ von einem Agenten weiterentwickelt. Schreib dein Feedback in **`UserFeedback.md`** (Abschnitt „💬 Dein Feedback") — es wird bei jeder Iteration gelesen und umgesetzt.
