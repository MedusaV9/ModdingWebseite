# 💌 SoooDreamy — Build-Log & Dein Feedback

> **So funktioniert's:** Schreibe dein Feedback einfach unten in den Abschnitt
> **„💬 Dein Feedback"** (direkt auf GitHub editieren und committen).
> Ich lese diese Datei bei jeder Iteration. Solange kein neues Feedback da ist,
> poliere, verbessere und debugge ich weiter im Loop.
>
> **`STOPP`** (hier oder im Chat) beendet den Loop.

---

## 💬 Dein Feedback (hier schreiben!)

_(noch leer — schreib mir hier, was du dir wünschst, was dich stört, was fehlt)_

---

## 🤖 Antworten des Agents auf dein Feedback

_(hier beantworte ich dein Feedback, wenn ich es umgesetzt habe)_

---

## ✅ Build-Log (was ich erledigt habe)

### Iteration 1 — Die komplette App steht 🚀
- `[2026-08-03 18:00 UTC]` Projekt in `MedusaV9/ModdingWebseite` auf Branch `cursor/sooodreamy-couple-app-82d4` fortgeführt (Skeleton von `Githurub/cursor/sooodreamy-couple-app-f127` importiert).
- `[2026-08-03 18:10 UTC]` **Node.js-Server** komplett (nur `ws` als Dependency): Pairing per 6-stelligem Code, REST + WebSocket-Realtime (Presence, Touches, Chat, Typing), Fotos & Sprachnachrichten (Range-Streaming), gemeinsames Canvas, Events, Bucket List, Frage-des-Tages mit Streak-Logik & Reveal erst wenn beide geantwortet haben, generische Spiele-Sessions (Relay), Love-Stats, JSON-Persistenz mit atomaren Writes. **38 E2E-Tests grün** (`npm test`).
- `[2026-08-03 18:10 UTC]` **Content-Packs** (bilingual DE/EN, 721 Items): 185 Tagesfragen, 115 Quizfragen, 115 This-or-That, 95 Würdest-du-eher, 120 Wahrheit-oder-Pflicht (3 Schärfegrade), die 36 Fragen zum Verlieben, 115 Date-Ideen (18 für Fernbeziehungen). Mit echtem Swift-Compiler typegecheckt.
- `[2026-08-03 18:40 UTC]` **iOS-Core**: XcodeGen-Projekt (App + Widget-Extension), Models/API-Client/WebSocket-Client mit Auto-Reconnect, **Multi-Server-Verwaltung** (Server anlegen/testen/**wechseln** — jede Server-Verbindung hat ihre eigene Kopplung), In-App-Lokalisierung DE/EN (umschaltbar), CoreHaptics-Muster pro Berührungsart, **synthetisierte Sounds** (AVAudioEngine, keine Audio-Assets), Design-System (dreamy dark, Glass-Cards, Sternenhimmel).
- `[2026-08-03 18:40 UTC]` **Onboarding & Pairing**: Welcome → Server einrichten (mit Live-Verbindungstest) → Paar erstellen/beitreten (Profil: Name, Emoji, Farbe) — inkl. **QR-Pairing** (Server + Code in einem Scan) und Warte-Karte mit Code/QR/Teilen.
- `[2026-08-03 18:40 UTC]` **Dashboard**: Partner-Karte (online/last-seen/Stimmung), eigene Stimmung teilen, **3D-Herz (SceneKit, prozedural, schlägt im Takt)** — tippen sendet Herzklopfen, 6 Berührungsarten mit Haptik+Sound, Frage des Tages mit Antwort-Reveal & Streak, nächster Countdown.
- `[2026-08-03 19:20 UTC]` **Chat**: Tag-Gruppierung, Bubbles, Tipp-Indikator, 💌 Liebesbrief-Composer, **Sprachnachrichten** (AVAudioRecorder, Live-Pegel, AVPlayer-Streaming), Ungelesen-Badge.
- `[2026-08-03 19:20 UTC]` **Spiele**: Quiz „Wer kennt wen besser?" (Runden, Punkte, Urteil), This-or-That & Würdest-du-eher (simultane Picks, Match-Reveal) — alle **realtime-multiplayer** über deterministische Move-Reducer; Wahrheit-oder-Pflicht (lokal, 3 Schärfegrade, Karten-Flip), 36 Fragen (3 Sets, Augenkontakt-Timer), **Date-Ideen-Generator** (Filter, Slot-Animation, direkt auf die Bucket List).
- `[2026-08-03 19:20 UTC]` **Wir-Tab**: Galerie (Upload mit Auto-Resize, Pager, Speichern), **Echtzeit-Kritzel-Canvas**, Bucket List (Konfetti!), Momente/Countdowns (jährlich wiederholbar) mit **Live Activity / Dynamic Island**, Love-Stats.
- `[2026-08-03 19:20 UTC]` **Widgets** (Tage zusammen, Partner-Stimmung, Countdown, Tagesfrage — Home & Lock Screen) + **App Intents/Siri** („Schick Liebe mit SoooDreamy").
- `[2026-08-03 19:30 UTC]` **GitHub Actions**: Workflow `SoooDreamy` — Server-Tests (Ubuntu) + **unsigniertes IPA** (macOS, XcodeGen + xcodebuild, Icon wird prozedural gerendert) als Build-Artifact `SoooDreamy-unsigned-ipa`.

## 🔄 Als Nächstes
- CI-Lauf beobachten, iOS-Build grünschalten (Compile-Fixes), IPA-Artifact verifizieren.
- Polish-Loop: Animations-Feinschliff, Edge-Cases (Partner offline, Server-Wechsel mitten im Spiel), Empty-States, Accessibility.
- Auf dein Feedback warten — schreib es oben rein! 💬
