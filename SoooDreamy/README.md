# 💜 SoooDreamy

**Die App für euch zwei.** Eine moderne iOS-Couple-App (SwiftUI, iOS 17+) mit eigenem, selbst gehostetem Mini-Server — eure Daten gehören nur euch.

> The app for the two of you: a modern iOS couple app with a tiny self-hosted server — your data stays yours. Fully bilingual (Deutsch/English).

## ✨ Features

- **Herzklopfen & Berührungen** — sende Herzklopfen, Küsse, Umarmungen … mit echten CoreHaptics-Mustern und synthetisierten Sounds. Empfangene Berührungen erscheinen als Vollbild-Moment.
- **3D-Herz** — ein prozedural generiertes, schlagendes SceneKit-Herz auf dem Dashboard (tippen = Herzklopfen senden 💓).
- **Chat** — Texte, 💌 Liebesbriefe (mit eigenem Composer + Vollbild-Leser) und Sprachnachrichten mit Live-Pegel, Tipp-Indikator, Tag-Gruppierung.
- **„Öffnen wenn…"-Briefe** 🔒 — versiegelte Liebesbriefe („Öffne mich, wenn du traurig bist / mich vermisst / nicht schlafen kannst …"); der Empfänger bricht das Siegel mit einer dramatischen Enthüllungs-Animation.
- **Frage des Tages** — 185 bilinguale Fragen, deterministisch pro Tag & Paar; Antworten werden erst enthüllt, wenn beide geantwortet haben. Mit 🔥-Serie (Streak) und **📖 „Unser Tagebuch"** zum Durchblättern aller bisherigen Antworten.
- **💘 Liebes-Wordle** — tägliches Paar-Wordle: beide raten dasselbe Wort (514 deutsche / 461 englische Wörter), Ergebnis-Grid direkt in den Chat teilen.
- **Spiele** — „Wer kennt wen besser?"-Quiz, This-or-That, Würdest-du-eher (alle realtime-multiplayer über den Server), Wahrheit-oder-Pflicht (Couple-Edition, 3 Schärfegrade), die 36 Fragen zum Verlieben, Date-Ideen-Generator mit Filtern (110+ Ideen, auch für Fernbeziehungen).
- **Gemeinsame Galerie** — Fotos hochladen (automatisch verkleinert, mit Grid-Thumbnails), Vollbild-Pager, in die Fotobibliothek sichern.
- **Kritzel-Canvas** — zeichnet zusammen in Echtzeit (WebSocket), Stift/Marker/Radierer + Undo.
- **Bucket List** — eure gemeinsamen Träume, mit Konfetti beim Abhaken.
- **Momente & Countdowns** — Jahrestage & besondere Termine, optional jährlich wiederholend, mit **Live Activity / Dynamic Island Countdown**. Das Dashboard feiert **Monatstage & Jahrestage** automatisch. 🎉
- **Stimmungen** — Mood + Notiz teilen, Partner-Stimmung auf Dashboard & Widget, **Stimmungsverlauf-Timeline** in den Love-Stats.
- **Love-Stats** — Tage zusammen, gesendete vs. empfangene Berührungen, Nachrichten, Spiele, Streak.
- **Widgets** — Tage zusammen, Partner-Stimmung, Countdown, Frage des Tages (Home Screen + Lock Screen).
- **App Intents / Siri** — „Schick Liebe mit SoooDreamy", Partner-Stimmung abfragen.
- **App-Sperre** 🔒 — optional per Face ID / Touch ID / Code.
- **Mehrere Server, ein Tap** — Server in den Einstellungen anlegen, testen, **wechseln** (jeder Server hat seine eigene Kopplung). Pairing per 6-stelligem Code **oder QR-Code** (Server + Code in einem Scan).

## 🏗 Architektur

```
SoooDreamy/
├── server/          Node.js ≥ 20, nur 1 Dependency (ws). REST + WebSocket, JSON-Datei-Storage.
│   ├── src/         server.js (Entry), app.js, router.js, realtime.js, store.js, util.js
│   └── test/        node:test E2E-Suite (38 Tests)
├── ios/
│   ├── project.yml  XcodeGen-Projektdefinition (App + Widget-Extension)
│   ├── SoooDreamy/  App-Target (SwiftUI, iOS 17+)
│   ├── Widgets/     WidgetKit-Extension (4 Widgets + Live Activity)
│   ├── Shared/      In beide Targets kompiliert (Widget-Snapshot, Live-Activity-Attributes)
│   └── scripts/     GenerateIcon.swift — rendert das App-Icon prozedural (keine Binärdateien im Repo)
└── docs/API.md      Vollständige API-Spezifikation (REST + WS)
```

## 🖥 Server starten

```bash
cd SoooDreamy/server
npm install
npm start            # PORT=4321 HOST=0.0.0.0 DATA_DIR=./data
```

Der Server läuft auf allem, was Node 20+ kann (Raspberry Pi, NAS, alter Laptop, Cloud-VM). Die App verbindet sich über die Adresse, die ihr in den Einstellungen eintragt (z. B. `192.168.1.20:4321`). Für Fernbeziehungen: Port-Forwarding, [Tailscale](https://tailscale.com) o. ä. Details in `server/README.md`.

```bash
npm test             # 38 E2E-Tests (node:test)
```

## 📱 App bauen

**Unsigniertes IPA aus CI:** Der GitHub-Actions-Workflow `SoooDreamy` baut bei jedem Push automatisch `SoooDreamy-unsigned.ipa` — als Workflow-Artifact **und** als Download im rollenden Release [`sooodreamy-latest`](https://github.com/MedusaV9/ModdingWebseite/releases/tag/sooodreamy-latest). Das IPA installiert ihr mit [AltStore](https://altstore.io), [SideStore](https://sidestore.io), Sideloadly o. ä. — die signieren es beim Installieren mit eurer Apple-ID.

**Lokal mit Xcode (macOS):**

```bash
brew install xcodegen
cd SoooDreamy/ios
swift scripts/GenerateIcon.swift SoooDreamy/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png
xcodegen generate
open SoooDreamy.xcodeproj
```

> ⚠️ Hinweise zum unsignierten Build: Kein Remote-Push (Realtime läuft über WebSocket, solange die App offen ist — die tägliche Erinnerung ist eine lokale Notification). App Groups (Widget-Daten) funktionieren, wenn euer Sideload-Tool die `group.app.sooodreamy.shared`-Entitlement mitsigniert (AltStore/SideStore tun das); sonst zeigen Widgets Platzhalter.

## 🔄 Feedback-Loop

Dieses Projekt wird iterativ von einem Agenten weiterentwickelt. Schreib dein Feedback in **`UserFeedback.md`** (Abschnitt „💬 Dein Feedback") — es wird bei jeder Iteration gelesen und umgesetzt.
