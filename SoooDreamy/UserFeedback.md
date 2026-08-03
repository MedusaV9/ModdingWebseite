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

### Iteration 2 — CI grün, Review & Fixes 💅
- `[2026-08-03 19:28 UTC]` **GitHub Actions komplett grün im ersten Anlauf**: Server-Tests ✓ (38/38), iOS-Build ✓ `** BUILD SUCCEEDED **` — Artifact `SoooDreamy-unsigned-ipa` (3,0 MB) mit App-Binary (7,4 MB), Widget-Extension, App-Intents-Metadaten. IPA heruntergeladen & Inhalt verifiziert.
- `[2026-08-03 19:30 UTC]` **Manueller E2E-Smoke** gegen laufenden Server: Mia erstellt Paar (Code `JPAY4U`) → Ben tritt bei → Ben empfängt via WebSocket live: `welcome`, `touch` (Herzklopfen 💓), `message`, `daily_answer` (Reveal-Logik: Antwort erst sichtbar, als beide geantwortet hatten ✓, Streak 1), `game_started`, `game_move`. **Alles grün.**
- `[2026-08-03 19:35 UTC]` App-Icon visuell geprüft (prozedurale Renderlogik nachgestellt) — dreamy Nachthimmel, Herz-Paar, Sterne ✨.
- `[2026-08-03 19:45 UTC]` **Review-Fixes**: `SocketClient` cancelt jetzt alte Sockets vor dem Neuverbinden und überspringt redundante Connects (kein Socket-Leak mehr beim App-Foreground); Dashboard zeigt beim Kaltstart ohne Netz jetzt einen Lade-/Retry-Zustand statt einer leeren Warte-Karte.

### Iteration 3 — Server-Wechsel-Härtung & Self-Hosting 🐳
- `[2026-08-03 19:38 UTC]` **Edge-Case gefixt**: Beim Wechsel des aktiven Servers setzen Chat (Nachrichtenliste, Typing) und Spiele-Engine (Session, Navigation) ihren Zustand jetzt sauber zurück — jeder Server ist ein komplett eigener Paar-Kontext.
- `[2026-08-03 19:38 UTC]` **Dockerfile** für den Server (node:22-alpine, Volume für `data/`) + README-Anleitung — Self-Hosting mit einem Befehl.
- `[2026-08-03 19:40 UTC]` **CI wieder komplett grün** (Run 30846653658): Server-Tests 38/38 ✓, iOS `** BUILD SUCCEEDED **` ✓, Artifact `SoooDreamy-unsigned-ipa` (3,06 MB) ✓.

### Iteration 4 — Die große Feature-Welle (5 parallele Subagents) 🌊
- `[2026-08-03 20:15 UTC]` **Server v1.1** (52/52 Tests): Foto-**Thumbnails** (`POST /api/photos/:id/thumb`), **Canvas-Undo** (`DELETE /api/canvas/strokes/:id`, nur eigene), **Stimmungs-Verlauf** (`GET /api/moods`, letzte 60 pro Person), **Tagebuch-Liste** (`GET /api/daily?limit=`), **versiegelte Briefe** (`openWhen`-Feld) — alles abwärtskompatibel zu v1.0-Daten (eigener Kompat-Test), `docs/API.md` aktualisiert.
- `[2026-08-03 20:15 UTC]` **💌🔒 „Öffnen wenn…“-Briefe**: Siegel-Auswahl beim Schreiben (traurig 😢, vermisst mich 🥺, feiern 🥳, mieser Tag 🌧, schlaflos 🌙, Jahrestag 💍, eigenes), Empfänger sieht einen versiegelten Umschlag und öffnet ihn mit dramatischer Enthüllungs-Animation; dazu Brief-Vollbild-Leser & Kopieren-Kontextmenüs im Chat.
- `[2026-08-03 20:15 UTC]` **💘 Liebes-Wordle**: tägliches Paar-Wordle — beide raten dasselbe Wort (deterministisch pro Tag & Paar), 514 deutsche + 461 englische Wörter (validiert), QWERTZ/QWERTY-Tastatur, korrektes Zwei-Pass-Scoring bei doppelten Buchstaben, Tages-Persistenz, Ergebnis-Grid (🟩🟨⬛) direkt in den Chat teilen, Hub-Karte mit Täglich-Badge & Erledigt-Häkchen.
- `[2026-08-03 20:15 UTC]` **Galerie-Thumbnails** (Grid lädt jetzt ~320px-Thumbs, alte Fotos fallen aufs Original zurück), **Canvas-Undo-Button** (optimistisch + Partner-Undos live), **Stimmungsverlauf-Timeline** in den Love-Stats, **📖 „Unser Tagebuch“** — alle bisherigen Tagesfragen mit beiden Antworten zum Durchblättern.
- `[2026-08-03 20:15 UTC]` **🔒 App-Sperre** (Face ID/Touch ID/Code, sperrt beim Verlassen der App) + **🎉 Monatstag-Feier**: Dashboard feiert automatisch „X Monate/Jahre zusammen — genau heute!“ mit Herzchen-Regen.
- `[2026-08-03 20:20 UTC]` **Neue Test-Ebene**: SwiftPM-Package `SoooDreamyLogic` — **40 Logik-Tests laufen auf Linux** (`swift test`): Content-Integrität (alle 7 Packs + Wordle-Wörter), Datums-Mathe, deterministischer Seeded-Shuffle, L10n-Tabellen (keine leeren/doppelten Keys) und ein statischer Quellcode-Scan, der prüft, dass jeder verwendete `L10n.t("…")`-Key existiert.
- `[2026-08-03 20:21 UTC]` **E2E-Smoke v1.1 grün**: versiegelter Brief (openWhen ✓), Thumb-Upload (Partner → 403 ✓, Abruf 200 ✓), Stroke-Undo (fremd → 403, eigen → 200 ✓), Mood-Verlauf ✓, Tagebuch-Reveal ✓, alle 7 WS-Events live empfangen ✓.
- `[2026-08-03 20:25 UTC]` **CI ausgebaut**: neuer Job „Logic tests (Swift on Linux)“ + rollendes GitHub-Prerelease `sooodreamy-latest` mit dem frischen IPA als Download (best-effort).

### Iteration 5 — Welle 5: Duell, Reaktionen, Gutscheine 🥊
- `[2026-08-03 20:50 UTC]` **Server v1.2** (63/63 Tests): Nachrichten-**Reaktionen** (Toggle, `message_updated`), **Wordle-Duell-Endpoints** mit Anti-Spoiler (Partner-Ergebnis erst sichtbar, wenn man selbst fertig ist — auch in den WS-Payloads pro Person zugeschnitten), **Foto-Favoriten**, **Love-Coupons** (erstellen → Partner löst ein, komplette Rechte-Matrix) — plus erweiterter v1.0-Kompatibilitätstest.
- `[2026-08-03 20:50 UTC]` **Chat-Reaktionen** ❤️😂😮🥺🔥👍: Doppeltipp = schnelles Herz, „Reagieren…“-Menü, Chips unter den Bubbles (eigene pink markiert), live via WebSocket.
- `[2026-08-03 20:50 UTC]` **Wordle-Duell** 🥊: Auto-Submit nach dem Lösen, Duell-Karte mit beiden Emoji-Grids nebeneinander, Sieger-Logik (Sieg schlägt Niederlage → weniger Versuche → Unentschieden 💞), Spoiler-freier Teaser solange man selbst noch rätselt, 🏆-Badge im Hub.
- `[2026-08-03 20:50 UTC]` **Foto-Favoriten** (Herz im Vollbild, Filter „Favoriten ❤️“, Live-Sync), **Canvas-Replay** 🎬 (Strich-für-Strich-Wiedergabe eurer Kunstwerke), **Love-Coupons** 🎟 (Gutschein-Karten mit gestricheltem Rand, 10 Ideen-Presets, Einlöse-Zeremonie mit Konfetti, globale Toasts).
- `[2026-08-03 20:50 UTC]` **Dashboard-Erinnerung** 💭 (zufälliges altes Foto oder alte Tagesfrage, > 7 Tage her), Pairing-Konfetti, **einstellbare Erinnerungszeit** für die Tagesfrage.

### Iteration 6 — Welle 6: Foto-Widget & Emoji-Rätsel 🧩
- `[2026-08-03 21:05 UTC]` **Foto-Widget** „Euer Foto“ (Small/Medium): zeigt euer neuestes Favoriten-Foto (sonst neuestes) als Vollbild-Widget mit Caption — lädt selbstständig vom eigenen Server; dazu **Tage-zusammen als Inline-Widget** (oberhalb der Uhr auf dem Lock Screen).
- `[2026-08-03 21:05 UTC]` **🧩 Emoji-Rätsel**: Party-Spiel mit **140 validierten Rätseln** in 6 Kategorien (Filme mit deutschen/englischen Titeln, Songs, Orte, Essen, Paar-Dinge, Aktivitäten) — Karten-Flip-Reveal, Punktevergabe pro Partner, Sieger-Zeremonie, Revanche.
- `[2026-08-03 21:10 UTC]` Logic-Test-Suite auf **46 Tests** erweitert (Emoji-Rätsel-Integrität: Kategorien, keine ASCII-Zeichen in Emoji-Strings, keine doppelten Antworten).

### Iteration 7 — Qualitätswelle: Deep-Review & 15 Fixes 🔍
- `[2026-08-03 21:20 UTC]` Ein unabhängiger Review-Agent hat alle Wellen-5/6-Features tiefgeprüft (Chat-Reaktionen, Duell-Statemachine, Replay, Coupons, Widgets, Server-Endpoints): **15 Findings (5× Medium, 10× Low, 0 kritisch)** — alle behoben:
  - **Wordle**: Ergebnisse jetzt **pro Sprache** gespeichert (Server v1.2.1, lazy Migration alter Daten), gestern-fertig-aber-offline-Boards werden nachgereicht, kein Endlos-Spinner mehr bei fehlgeschlagenem Submit (Retry-Button), Race-Guard gegen veraltete Antworten, absurde Datums-Submits abgelehnt (±1 Tag).
  - **Chat**: Fehler-Pfad der Reaktionen synchronisiert jetzt mit Server-Wahrheit statt blind zurückzutoggeln; Echo-Duplikat beim Senden eliminiert; Reconnect lädt Lücken seitenweise nach (max. 4 Seiten) und frischt Reaktionen auf.
  - **Galerie/Canvas**: Favoriten-Fehlerpfad überschreibt keine Partner-Herzen mehr; Favoriten-Filter gilt jetzt auch im Vollbild-Pager; Replay-Tasks werden beim Verlassen gecancelt.
  - **Coupons**: Kap-Räumung broadcastet jetzt `coupon_deleted` (keine Geister-Gutscheine).
  - **Dashboard**: Erinnerungs-Karte resettet beim Server-/Paar-Wechsel.
  - **Foto-Widget**: speicherschonendes Dekodieren via `CGImageSourceCreateThumbnailAtIndex` (kein Memory-Kill durch große Fotos).
- `[2026-08-03 21:25 UTC]` Stand: **Server 66/66 Tests · 46/46 Logic-Tests (Linux) · Parse aller 70 Swift-Dateien sauber.**

## 🔄 Als Nächstes
- Auf dein Feedback warten — schreib es oben in „💬 Dein Feedback“! Ich lese es bei jeder Iteration. 💜
- Ideen für kommende Wellen: Duell-Bilanz über Zeit (W:N:U-Statistik), gemeinsame Playlist-Wünsche, Countdown-Sharing als Nachricht, Coupons mit Ablaufdatum, Stimmungs-Trends, Fotoalben.
