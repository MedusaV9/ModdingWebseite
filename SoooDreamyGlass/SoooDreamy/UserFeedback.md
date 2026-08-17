# 💌 SoooDreamy — Build-Log & Dein Feedback

> **So funktioniert's:** Schreibe dein Feedback einfach unten in den Abschnitt
> **„💬 Dein Feedback"** (direkt auf GitHub editieren und committen).
> Ich lese diese Datei bei jeder Iteration. Solange kein neues Feedback da ist,
> poliere, verbessere und debugge ich weiter im Loop.
>
> **Der Loop läuft unendlich weiter** (auf Wunsch: `STOPP` beendet ihn nicht mehr).

---

## 💬 Dein Feedback (hier schreiben!)

_(noch leer — schreib mir hier, was du dir wünschst, was dich stört, was fehlt)_

## 🤖 Antworten des Agents auf dein Feedback (Chat, 03.08.)

> **Dein Report:** „The resource could not be loaded because the App Transport Security policy requires the use of a secure connection" bei `http://138.201.60.230:4321` — auch „mit neuester Version".
>
> **Diagnose:** Dein **Server** ist korrekt und erreichbar (`/api/health` → SoooDreamy 1.4.0). Der Fehler kommt vom **iPhone-Client**. Im Screenshot endet der Tipp noch mit „`npm start` genügt." — genau dieser Text ist in IPA **1.1.0+** länger („Normales http:// funktioniert…"). Damit ist klar: auf dem Gerät läuft noch ein **altes IPA** (vor dem ATS-Fix). Das Release `sooodreamy-latest` hatte den Fix schon; Download-Count war 0.
>
> **Bitte so installieren (wichtig: alte App zuerst löschen):**
> 1. SoooDreamy auf dem iPhone **löschen** (sonst bleibt oft die alte Binary).
> 2. Frisches IPA laden: https://github.com/MedusaV9/ModdingWebseite/releases/tag/sooodreamy-latest → `SoooDreamy-unsigned.ipa`
> 3. Mit AltStore / SideStore / Sideloadly neu sideloaden.
> 4. Unter „Server hinzufügen" muss stehen: **„App-Build 1.2.0 … · HTTP freigeschaltet"** und der Tipp beginnt mit **„★ Build 1.2.0"**. Erst dann „Verbindung testen".
>
> Adresse weiter: `http://138.201.60.230:4321` (oder `http://ark.atomi23.de:4321` — Port **4321** nicht weglassen; ohne Port zeigt nginx die AMP-Seite).

---

## 🤖 Antworten des Agents auf dein Feedback

_(hier beantworte ich dein Feedback, wenn ich es umgesetzt habe)_

---

## ✅ Build-Log (was ich erledigt habe)

### Iteration 4.0 — Coherence & Security (ehrlicher P0/P1-Schnitt) 🔐
- `[2026-08-10 06:00 UTC]` **Version 4.0.0** für Server, App und Widgets. Die Welle ist bewusst Härtung statt „Welle 5–15 fertig": keine zusätzlichen Releases werden behauptet.
- **Spiele sind kein dumb relay mehr**: alle 16 registrierten Typen normalisieren Create-Payloads und prüfen Actor/Turn/Phase/Runde/Range/Duplikate; Endergebnisse entstehen ausschließlich aus akzeptierten Server-Moves. Falsche Commit-Reveals werden abgewiesen. Offene Altpartien werden vollständig replayt oder sicher als nicht fortsetzbar invalidiert — unbekannte Historien werden nie übersprungen.
- **Transport & Sessions**: HTTPS/WSS außerhalb explizitem Private-LAN, keine globalen ATS-Ausnahmen, keine Query-Tokens, gehashte Server-Bearer, iOS-Keychain/App-Group, Ablauf/Rotation/Widerruf pro Gerät, Rate-Limits/Quoten und begrenzte/redigierte Logs.
- **Daten bleiben erhalten**: persistente idempotente Chat-Outbox, paar-/servergebundener Cold Cache, Widget-Snapshot für Energie/Ziel/Level, Needs im Digest, FIFO-Feiern und zeitgenau aktualisierte Kapseln.
- **Export & Bedienbarkeit**: AES-GCM-verschlüsselte `.sooodreamy`-Backups ohne Sitzungstokens, klare Passphrase-Warnungen, 44-pt-Ziele, bessere Kontraste und zusätzliche VoiceOver-Labels.
- **Killed-app Push ehrlich gegated**: Geräte-Registrierung, Revoke, lokalisierte datensparsame Payloads und APNs-Provider sind implementiert/getestet. Ohne Push-fähiges Apple-Provisioning plus serverseitige `.p8`-Credentials bleibt `deliveryAvailable:false`; es wird keine Zustellung behauptet.
- **✅ Verifikation**: Node-Suite **225/225 grün**, inklusive Security-/Adversarial-/Migrations- und vollständigen Multiplayer-Protokolltests. Swift-Pure-Logic-Tests wurden ergänzt, konnten in dieser Linux-VM ohne Swift-Toolchain aber nicht ausgeführt werden. Kein Simulator/Hardware vorhanden — deshalb keine iOS-UI-Abnahme behauptet.

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

### Iteration 8 — Welle 8: Duell-Bilanz & Sharing 📊
- `[2026-08-03 21:40 UTC]` **Server v1.3** (68/68 Tests): neuer Verlaufs-Endpoint `GET /api/wordle?limit=&lang=` — alle Duell-Tage als Liste, Anti-Spoiler pro Tag, sprachgefiltert.
- `[2026-08-03 21:40 UTC]` **📊 Duell-Bilanz-Screen**: Gesamtstand mit Avataren („{du} X · U · Y {Schatz}“, 👑 für die Führung), 🔥-Spiel-Serie, Tagesliste mit Ausgang-Icons (🏆/💪/💞/👀) und aufklappbaren Emoji-Grid-Vergleichen. Erreichbar aus dem Wordle.
- `[2026-08-03 21:40 UTC]` **Countdown teilen**: Events lassen sich per Kontextmenü als hübsche Nachricht in den Chat senden („🗓️ 💍 Jahrestag — Noch 12 Tage“). **Top-Stimmungen**: die 3 häufigsten Moods der letzten 30 Tage als Chips über dem Stimmungsverlauf.

### Iteration 9 — Dein HTTP-Fix 🔓 (User-Feedback aus dem Chat!)
- `[2026-08-03 22:18 UTC]` **ATS-Fix**: App Transport Security war tatsächlich noch NICHT gelockert (anders als dir gesagt wurde) — jetzt erlauben App **und** Widget-Extension Klartext-HTTP (`NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking` + Local-Network-Beschreibung). `http://138.201.60.230:4321` & Co. funktionieren ab IPA **v1.1.0** — im IPA nachgeprüft (beide Info.plists enthalten den Schlüssel ✓). WebSockets (`ws://`) inklusive. Server-Hinweis in der App + README um HTTPS-Empfehlung (Reverse-Proxy) für öffentliche Server ergänzt.
- `[2026-08-03 22:18 UTC]` Loop-Regel geändert: **`STOPP` beendet den Loop nicht mehr** — es geht unendlich weiter, wie gewünscht.

### Iteration 10 — Welle 9: Soundtrack & Hard-Mode 🎵💪
- `[2026-08-03 22:30 UTC]` **Server v1.4** (74/74 Tests): „Unser Soundtrack“ — Songs mit Titel/Artist/Notiz/Link, Herz-Toggle beider Partner, Bearbeiten/Löschen nur durch den Ersteller, 300er-Kap mit Eviction-Broadcast.
- `[2026-08-03 22:30 UTC]` **🎵 „Unser Soundtrack“** im Wir-Tab: Song-Karten mit Herzen (💞 wenn beide), „Anhören ↗“-Link (Spotify/YouTube/…), 🎲 Zufalls-Song mit Scroll+Puls-Animation, Add/Edit-Sheets, Live-Sync.
- `[2026-08-03 22:30 UTC]` **💪 Wordle Hard-Mode**: klassische NYT-Regeln (Grün bleibt stehen, Gelb muss vorkommen), Umschalten nur vor dem ersten Versuch, spezifische Hinweis-Toasts, „4/6*“-Stern im Share-Text, Hard-Pill auf der Endkarte.

### Iteration 11 — ATS-Follow-up: altes IPA erkannt 📱
- `[2026-08-03 22:50 UTC]` Server-Health von hier aus grün: `http://138.201.60.230:4321/api/health` und `http://ark.atomi23.de:4321/api/health` → SoooDreamy **1.4.0**. Release-IPA **1.1.0** enthält ATS + neuen Tip-Text (im Binary verifiziert). Screenshot-Tip endet noch beim alten Text → Client war veraltet.
- `[2026-08-03 22:50 UTC]` **IPA 1.2.0 (build 12)**: committed Info.plists, Extra-Exception-Domains (`ark.atomi23.de`), sichtbares „App-Build … · HTTP freigeschaltet“, Tip beginnt mit „★ Build 1.2.0“, ATS-Fehler zeigt klare Neuinstall-Anleitung.

### Iteration 12 — Responsive UI-Skalierung (iPhone 16 vs Pro Max) 📐
- `[2026-08-03 23:05 UTC]` **LayoutMetrics**: Design-Breite 430pt (Pro Max). Kleinere Geräte skalieren Fonts/Frames/Paddings/Spacings proportional (zusätzlicher Faktor unter 410pt). Pro Max bleibt 1.0.
- `[2026-08-03 23:05 UTC]` `Font.scaled`, `glassCard`/Buttons, Dashboard/Onboarding/Games/Memories/Chat umgestellt. RootView: `.fitsPhoneLayout()`. IPA **1.2.1**.

### Iteration 13 — Notifications, Widgets & Live Activities (4× Fable-Max) 🔔🧩🏝️
- `[2026-08-03 23:45 UTC]` **Server v1.5** (77/77): `GET /api/widget-snapshot` (Bearer oder `?token=`), `GET /api/canvas?limit=N`.
- `[2026-08-03 23:45 UTC]` **Lokale Couple-Alerts** mit wählbaren Sounds (7 WAVs: soft/chime/heartbeat/kiss/sparkle/whoosh/tada): Touch, Chat, Foto, Daily-Reveal, Partner-online, Coupon — Einstellungen + Sound-Picker.
- `[2026-08-03 23:45 UTC]` **Foto-Widget gefixt**: Cache im App-Group, Fallback bei Netzfehler; Sizes Small/Medium/Large + Lock-Screen rectangular.
- `[2026-08-03 23:45 UTC]` **🎨 Canvas-Widget** neu (zeichnet eure Strokes); mehr Sizes auf Days/Mood/Countdown/Daily; **Custom-Hintergründe** (night/sunset/ocean/blush/mono/photo) in Einstellungen.
- `[2026-08-03 23:45 UTC]` **Live Activity „Couple Pulse“**: Lock Screen + Dynamic Island mit Mood/Online/letzter Touch/Streak — Updates lokal über WebSocket. Countdown-Activity zeigt jetzt auch Pulse-Strip. IPA **1.3.0**.
- Hinweis: echte Push-Notifications (App geschlossen) brauchen Apple-Signing/APNs — bei Sideload nur lokal solange die App/WS läuft (+ tägliche Erinnerung).

### Iteration 14 — Riesenwelle (Server 1.6 + iOS 1.4.0) 🌊
- `[2026-08-04 00:20 UTC]` **Server v1.6** (86/86): Coupon-`expiresAt`, `GET /api/inbox?since=`, Photo-`album` + PATCH, Message-Delete, Read-Receipts, `GET /api/games`, `emojiriddle` Type.
- `[2026-08-04 00:20 UTC]` Coupons mit Ablauf, Foto-Alben, Canvas-Pinsel (Glow/Dotted/Calligraphy), Soundtrack-Provider-Chips, Chat löschen + ✓✓, „Während du weg warst“-Karte, Spiele-Bilanz. IPA **1.4.0**.

### Iteration 15 — Noch mehr Loop 🔁
- `[2026-08-04 00:40 UTC]` **Emoji-Rätsel Live-Multiplayer** (zwei Handys, Move-Relay), Solo bleibt.
- `[2026-08-04 00:40 UTC]` **Streak-Guard**-Reminder (21:30 wenn Frage offen & Streak > 0), Settings-Toggle.
- `[2026-08-04 00:40 UTC]` +26 Content-Items (Daily/Dates/Rätsel), Chat „Jump to latest“ FAB, Partner last-seen relativ, 🔥-Pulse ab Streak 3. IPA **1.4.1** · Logic **50** Tests.

### Iteration 16 — Welle 16: Teilen, Filter & Wochen-Chart 💬📊
- `[2026-08-04 01:00 UTC]` **In-den-Chat-Teilen überall**: Wahrheit-oder-Pflicht-Karten („💋 Pflicht für Mia: …“), 36-Fragen-Karten („💫 36 Fragen — Frage 7: …“) und Bucket-List-Einträge (erfüllte Träume als 🎉-Feier-Nachricht, offene als 🌌-Teaser, per Kontextmenü).
- `[2026-08-04 01:00 UTC]` **Merkt sich eure Wahl**: Wahrheit-oder-Pflicht startet mit der zuletzt gewählten Schärfestufe, 36 Fragen mit dem zuletzt gewählten Set.
- `[2026-08-04 01:00 UTC]` **Bucket List**: Filter-Chips Alle / Offen 🌌 / Geschafft ✨ mit eigenen Leer-Hinweisen.
- `[2026-08-04 01:00 UTC]` **Momente**: Ein-Tipp-Helfer „Monatstag hinzufügen“ (wenn Jahrestag gesetzt) — schlägt den nächsten Monatstag mit Datum vor, dedupliziert, verschwindet sobald er in der Liste steht.
- `[2026-08-04 01:00 UTC]` **Love-Stats**: neues „Diese Woche“-Balkendiagramm (letzte 7 Tage, gestapelt Du/Schatz in euren Farben, Wochentags-Beschriftung) + größerer Leer-Zustand.
- `[2026-08-04 01:00 UTC]` **Einstellungen**: „Paar-Code & QR zeigen“ — Code, Kopieren/Teilen & Pairing-QR (Server+Code) jederzeit wieder abrufbar, z. B. für ein neues Gerät.
- `[2026-08-04 01:00 UTC]` **Server-Tipp geschärft**: Beispiel jetzt `http://ark.atomi23.de:4321` mit explizitem „Port :4321 nicht weglassen!“.
- `[2026-08-04 01:00 UTC]` **+15 Content-Items** (5 Quiz, 5 This-or-That, 5 Würdest-du-eher, DE/EN). IPA **1.4.2** (Build 17) · Logic **50/50** Tests grün.

### Iteration 17 — Welle 17: Suche, Raster & noch mehr Teilen 🔍🖼️
- `[2026-08-04 01:15 UTC]` **Chat-Suche**: Lupe im Chat-Header öffnet ein Suchfeld — filtert die geladenen Nachrichten live (Text & Brief-Titel, Groß/Klein egal), mit eigenem „Nichts gefunden“-Hinweis (ältere Nachrichten weiterhin per Pull-to-Refresh nachladbar).
- `[2026-08-04 01:15 UTC]` **Galerie-Raster umschaltbar**: Toolbar-Button wechselt zwischen 2 Spalten (große Kacheln) und 3 Spalten — die Wahl bleibt gespeichert.
- `[2026-08-04 01:15 UTC]` **Canvas-Farbverlauf**: die letzten 6 tatsächlich benutzten Farben als Schnellzugriff-Reihe unter der Palette (überlebt App-Neustarts).
- `[2026-08-04 01:15 UTC]` **Wordle-Duell teilen**: fertige Duelle („🥊 Wordle-Duell 04.08. · Du 3/6 · Mia 4/6 + Urteil“) direkt in den Chat schicken.
- `[2026-08-04 01:15 UTC]` **Frage des Tages teilen**: nach dem Reveal beide Antworten als Chat-Nachricht festhalten („❓ Frage … / Du: … / Mia: …“).
- `[2026-08-04 01:15 UTC]` **+10 Wahrheit-oder-Pflicht-Karten** (5 Wahrheiten + 5 Pflichten, alle Schärfegrade, DE/EN) — jetzt 130 Karten.
- `[2026-08-04 01:15 UTC]` **Haptik-Feinschliff**: Bucket-List-Teilen bestätigt den Tipp jetzt sofort spürbar (wie alle anderen Teilen-Buttons).
- `[2026-08-04 01:15 UTC]` IPA **1.4.3** (Build 18) · Logic **50/50** Tests grün.

### Iteration 18 — Foto-Chat, ToD-Live, Journal, Streak-Kalender 📸🃏
- `[2026-08-04 01:55 UTC]` **Server v1.7** (89/89): Chat-Nachrichten vom Typ `photo` mit `photoId`.
- `[2026-08-04 01:55 UTC]` Fotos aus der Galerie in den Chat senden + Foto-Bubbles mit Vollbild.
- `[2026-08-04 01:55 UTC]` **Wahrheit-oder-Pflicht Live** zu zweit (Move-Relay); Solo bleibt.
- `[2026-08-04 01:55 UTC]` Journal: Suche, Monatsgruppen, Eintrag teilen.
- `[2026-08-04 01:55 UTC]` **Streak-Kalender** (Tap auf 🔥) — Tage an denen beide geantwortet haben.
- `[2026-08-04 01:55 UTC]` Voice-Player: Scrub, 1×/1.5×/2×, Restzeit. +36 Content-Items. IPA **1.5.0**.

### Iteration 19 — Edit, Alben 2.0, Canvas-Export, Streak-Widget ✏️🖼️
- `[2026-08-04 02:10 UTC]` **Server v1.8** (93/93): `PATCH /api/messages/:id` (bearbeiten + `editedAt`).
- `[2026-08-04 02:10 UTC]` Chat: Nachrichten bearbeiten + „(bearbeitet)“-Label.
- `[2026-08-04 02:10 UTC]` Galerie: Alben umbenennen, Multi-Select (verschieben/favorisieren), Zähler auf Chips.
- `[2026-08-04 02:10 UTC]` Canvas als Bild exportieren (Share / Fotos / Galerie-Upload).
- `[2026-08-04 02:10 UTC]` Quiz/Choices/Emoji-Rätsel Ergebnisse in den Chat teilen.
- `[2026-08-04 02:10 UTC]` **Streak-Widget** + bessere Widget-Deeplinks; Coupon „Nochmal schenken“ + Ablauf-Reminder. IPA **1.5.1**.

### Iteration 20 — Forward, Stats-Share, Server-Version 💌
- `[2026-08-04 02:20 UTC]` Briefe als neuen Brief weiterleiten; Top-Moods & Date-Ideen in den Chat; Server-Version in Einstellungen; +20 Content. IPA **1.5.2**.

### Iteration 21 — Welle 21: Pins, 💭-Button, Frische-Momente-Leiste 📌
- `[2026-08-04 02:35 UTC]` **📌 Nachrichten anpinnen** (lokal, pro Gerät): Kontextmenü auf allen Bubble-Typen (Text/Brief/Sprach/Foto), Banner oben im Chat zeigt den neuesten Pin (+Zähler bei mehreren) — Tipp springt zur Nachricht (oder erklärt, wie ältere Seiten nachgeladen werden), Pin-lösen-Button direkt im Banner. Bis 30 Pins pro Paar, UserDefaults mit Vorschau-Snapshot.
- `[2026-08-04 02:35 UTC]` **💭 Schwebender „Denk an dich“-Button** auf dem Dashboard — die liebste Berührung ohne Scrollen zum Touch-Grid, mit Pop-Animation.
- `[2026-08-04 02:35 UTC]` **„Zuletzt bei euch“-Leiste** im Wir-Tab: neuestes Foto (Thumb + Bildunterschrift/Uploader), neuester Song, neuester Gutschein — je mit relativer Zeit, tippen führt direkt in Galerie/Soundtrack/Coupons; live-aktualisiert über die Server-Events.
- `[2026-08-04 02:35 UTC]` **Verbindungs-Pill poliert**: pulsierender Punkt beim Verbinden, klares 📶-Offline-Badge mit farbigem Rand, kurzes mintgrünes „Verbunden“-Aufblitzen nach jedem Reconnect, A11y-Labels.
- `[2026-08-04 02:35 UTC]` **+15 Content-Items** (8 This-or-That, 7 Würdest-du-eher, DE/EN). IPA **1.5.3** (Build 22) · Logic **50/50** Tests grün · Parse aller 83 Swift-Dateien sauber.

### Iteration 22 — Welle 22: Song-Teilen, Momente-Filter, Flashback-Teilen 🎵🗓️
- `[2026-08-04 02:45 UTC]` **🎵 Songs in den Chat teilen**: Kontextmenü auf jeder Song-Karte (auch bei Songs vom Schatz) — schickt „🎵 Aus unserem Soundtrack:“ mit Titel — Artist, eurer Notiz in Anführungszeichen und dem Anhören-Link als Chat-Nachricht.
- `[2026-08-04 02:45 UTC]` **Momente-Filter**: Chips Alle / Bevorstehend ⏳ / Vergangen 🕰️ über der Momente-Liste (wie bei der Bucket List) — mit eigenen Leer-Hinweisen pro Filter; der Monatstag-Vorschlag versteckt sich unter „Vergangen“.
- `[2026-08-04 02:45 UTC]` **💭 Flashback in den Chat teilen**: Kontextmenü auf der Erinnerungs-Karte am Dashboard — alte Fotos gehen als echte Foto-Bubble (mit „💭 Erinnerung von vor {n} Tagen“-Text + Bildunterschrift), alte Tagesfragen als Text mit euren beiden Antworten von damals.
- `[2026-08-04 02:45 UTC]` **+12 Quizfragen** (DE/EN, jetzt 138): Superkraft, Koffer-Packstil, Immer-dabei-Dinge, Bestes Gericht, inneres Alter, Zeitreise, Alltagsluxus, Filmcharakter, Kino vs. Couch, Jeden-Tag-Gericht, Lieblingsgeräusch, Jahres-Traum.
- `[2026-08-04 02:45 UTC]` **A11y**: alle 5 Haupt-Tabs haben jetzt explizite Accessibility-Labels; der Chat-Tab sagt VoiceOver zusätzlich die Ungelesen-Zahl an („Chat, {n} ungelesen“).
- `[2026-08-04 02:45 UTC]` IPA **1.5.4** (Build 23) · Logic **50/50** Tests grün · Parse aller 93 Swift-Dateien sauber.

### Iteration 2.0 — Das große 2.0-Release 💜🚀
- `[2026-08-08 10:45 UTC]` **Version 2.0.0** (Build 24) überall: App, Widget-Extension, Server. Vollständiges Changelog neu in `docs/CHANGELOG.md`.
- **🧩 Widgets 2.0**: alle 8 Widgets in allen Größen (Small/Medium/Large, Days auch ExtraLarge, Lock Screen circular/rectangular/inline), tickende Countdowns (`Text(timerInterval:)`), vordatierte Timelines, **interaktive AppIntent-Buttons** („Herzklopfen senden" direkt vom Widget), Themes/Layouts/Datenquelle pro Widget via `AppIntentConfiguration`; Snapshot-Datenfluss & Deep-Links repariert.
- **🎨 Widget-Studio** in den Einstellungen: Live-Vorschau aller Widgets, Theme/Layout/Foto/Countdown wählen — landet im App-Group-Storage, Reload sofort.
- **⚡ Live Activities 2.0**: Lifecycle sauber (staleDate, Dismissal), Dynamic Island poliert, animierte Timer/Progress/Herz-Puls, Einstellungs-Sheet (Stil/Farbschema/Elemente → ContentState). Countdown + Couple Pulse.
- **🔄 Background Refresh**: `BGAppRefreshTask` holt Partner-Status/Momente/Tagesfrage und aktualisiert die Widgets; ehrliche iOS-Limits-Doku im README.
- **💎 Liquid Glass Design 2.0**: geschichtete Glas-Karten mit Refraktions-/Specular-Gradienten, Innenschatten, Glanzkanten, animierte Hintergrund-Blobs — alle Screens migriert, Dark/Light. **App-Icon** jetzt mehrschichtiges Glas-Herz (weiter 100 % prozedural).
- **🎬 Videos**: Aufnehmen/Hochladen mit Client-Transcoding + Thumbnails, Server-Streaming mit Range-Requests, Vollbild-Player, Sichern in Fotos.
- **☁️ iCloud**: CloudKit-Backup (Server-Verbindungen + Einstellungen) + JSON-Export nach iCloud Drive; Laufzeit-Erkennung fehlender Sideload-Entitlements mit sauberem Degradieren.
- **🌶️ Spicy Vault**: E2E-verschlüsselt (PBKDF2 210k → AES-GCM, Schlüssel bleibt beim Paar), eigene PIN + Face ID, Blur-Vorschau, Panik-Schütteln, nie in Widgets/Backups.
- **🎛️ Haptik-Studio**: Muster aufnehmen (Druckdauer = Stärke), AHAP-Wiedergabe, gemeinsame Bibliothek + 6 Presets, Senden mit Vollbild-Empfangsmoment + Verlauf.
- **🔊 Sound-Engine 2.0**: Stereo-Synthese (Detune, ADSR, Glocken-Spektren, Echo, Soft-Sättigung), 7 neue Sounds, Lautstärke pro Kategorie regelbar.
- **🎮 Drei neue Live-Spiele**: 4 Gewinnt, Foto-Memory (eure Galerie-Fotos), Liebes-Quiz-Duell mit Buzzer-Scoring — deterministisch übers Server-Move-Relay.
- **💞 Sechs neue Couple-Features**: Morgen-/Gutenacht-Check-in mit 🔥-Serie, Umarmungs-Warteschlange 🫂, gemeinsame Listen 📝, Foto des Tages 📷, „Gerade am Hören" 🎧 (60-min-Verfall), „Unser Jahr" ✨ (Rückblick, teilbar).
- **📚 Content**: 229 Tagesfragen (+20), 160 ToD-Karten (+20), 142 Date-Ideen (+15), Wordle 535 DE / 487 EN (+21/+26).
- **✅ Qualität**: Server-Suite 38 → **125 E2E-Tests**, iOS-Logic-Tests 50 → **77** (inkl. Reducer der neuen Spiele), CI grün mit IPA-Artefakt nach jedem Meilenstein.

### Iteration 3.0-A — Rituale & Beziehung (Agent A) 💞
- `[2026-08-08 21:55 UTC]` **🎙️ „Wie war dein Tag?"-Audio-Check-in**: euer Abendritual — beide nehmen bis zu 60 s auf, die Enthüllung kommt erst, wenn BEIDE Memos da sind (der Server hält das Partner-Memo zurück, wie bei der Tagesfrage). Mit 🔥-Streak, Verlauf vergangener Abende, Re-Recording und Dashboard-Karte mit Live-Status.
- `[2026-08-08 21:55 UTC]` **💌 Zeitkapsel-Briefe**: Brief (+ optionales Foto) schreiben und bis zu einem Datum versiegeln — der Server gibt den Inhalt erst nach `unlockAt` und nur an den Empfänger heraus. Dramatische Öffnungs-Zeremonie (Umschlag-Animation + Konfetti), Kapsel-Archiv (versiegelt/geöffnet), Lösch-Recht nur für ungeöffnete eigene Kapseln.
- `[2026-08-08 21:55 UTC]` **🫶 Bedürfnis-Knopf „Ich brauche gerade…"**: Raum für mich 🌿 / Zuspruch 🫂 / Ablenkung 🎈 / Nähe 💞 / Zuhören 👂 — 1 Tap auf dem Dashboard, beim Partner erscheint es sanft prominent mit „Bin für dich da 🤍"-Antwort. Verlauf mit optionaler Notiz; ehrlich ohne Push-Illusion: WS live + `needsForMe`-Bucket im App-Open-Digest.
- `[2026-08-08 21:55 UTC]` **🎯 Gemeinsame Ziele & Sparziele**: Zielwert/Einheit/Datum, beide buchen Fortschritt (auch Korrekturen), Meilenstein-Konfetti bei 25/50/75/100 % auf BEIDEN Handys, Verlauf pro Ziel, Top-Ziel als Widget-Snapshot-Feld (für Agent C).
- `[2026-08-08 21:55 UTC]` **🗓️ „Unsere Woche"**: 7-Tage-Board — jeder markiert Frei/Voll/Telefonieren/Date!, Überschneidungen funkeln ✨; gemeinsame Slots (Telefon-Date 📞, Filmabend 🍿, …) einmalig oder wöchentlich wiederkehrend, mit Uhrzeit; Erinnerungs-Banner am Tag selbst auf dem Dashboard.
- `[2026-08-08 21:55 UTC]` **🚦 Energie-Ampel**: 🟢 Voller Akku / 🟡 Geht so / 🔴 Auf Reserve nach Feierabend — 12-h-TTL wie Now-Playing, Partner-Ampel im Dashboard + Widget-Snapshot, sanfter Toast beim Partner.
- `[2026-08-08 21:55 UTC]` **📖 „Unser Monat"-Magazin**: der Server aggregiert jeden Monat deterministisch zu einer blätterbaren Ausgabe — Cover, Top-5-Momente, Zitat des Monats (eure längste beidseitig beantwortete Tagesfrage), Song des Monats, 12-Zahlen-Spread. Mit Archiv aller Monate und Lese-Quittung („Ihr habt diese Ausgabe beide gelesen 💜").
- `[2026-08-08 21:55 UTC]` **⚙️ Meilenstein-Event-API** (`server/src/events.js`): zentrales App-Event-Log (`app_event`-WS + `GET /api/app-events`) — Agent A emittiert `daymemo_first/both/streak`, `capsule_sealed/opened`, `need_sent`, `goal_milestone/completed`, `weekplan_slot` für das Level-/Badge-System von Agent C.
- `[2026-08-08 21:55 UTC]` **✅ Qualität**: +25 Server-E2E-Tests (135 → 160 in meiner Zone, Suite grün), 119 Swift-Logic-Tests grün (L10n-Scan inkl. aller neuen DE/EN-Strings), `docs/API.md` um den kompletten v3.0-Rituale-Abschnitt ergänzt.

### Iteration 3.0-B — Spiele-Offensive (Agent B) 🎮
- `[2026-08-08 23:15 UTC]` **🧩 Spiele-Infrastruktur v3.0**: (a) **Parallele Game-Sessions** — ein neues Spiel beendet nur noch laufende Partien DESSELBEN Typs; Schiffe versenken und Kniffel laufen jetzt nebeneinander (Session-Liste `GET /api/games/open`, Einzelabruf `GET /api/games/:id`, iOS: ein Engine pro Spieltyp via GamesCoordinator, Session-Banner im Play-Hub). (b) **„games"-Bucket im Inbox-Digest** — beim App-Öffnen zeigt der Play-Tab ein „Du bist dran!"-Badge (offene Einladungen + Partien, in denen der letzte Zug vom Schatz kam). (c) **Commit-Reveal-Helfer im Relay** — Geheimnisse gehen als `sha256(secret+salt)`-Commit auf den Server, Reveals werden vom Relay gegen den Commit **beglaubigt** (`verified`-Flag); reine Swift-SHA-256 im Client, bit-identisch zu Node. (d) **Seed-im-Payload-Konvention** dokumentiert + serverseitig erzwungen: fehlt der Seed, injiziert ihn der Server — kein Client kann sich seine Mischung aussuchen.
- `[2026-08-08 23:15 UTC]` **🚢 Schiffe versenken**: Flotten-Setup mit Würfel-Shuffle, versiegelte Flotten (Commit-Reveal!), 2-Schuss-Salven, Treffer-Grid mit versenkten Schiffen, Auto-Antwort des Verteidigers, am Ende **kryptografischer Fair-Play-Beweis** beider Bretter + Ergebnis-Grid in den Chat teilbar.
- `[2026-08-08 23:15 UTC]` **🎨 Montagsmaler**: Live-Zeichnen über die Canvas-Pipeline, Rate-Timer (Server-Zeitanker — keine Uhr-Schummelei), Wortlisten DE/EN (120 Begriffe), Punkte für schnelles Raten, Rollentausch pro Runde.
- `[2026-08-08 23:15 UTC]` **🎲 Kniffel-Liebesedition**: deterministische Seed-Würfel (beide Handys sehen dieselben Würfe — voll async-tauglich), Halten & Neuwerfen mit Würfel-Animation, kompletter Punkteblock mit Bonus + Vorschau-Punkten.
- `[2026-08-08 23:15 UTC]` **🍿 Film-Roulette**: beide swipen denselben Seed-Stapel (60 kuratierte Filme DE/EN + bis zu 5 eigene Titel), Match-Overlay 💞, `movie_match`-App-Event als Filmabend-Hook für den Wochenplan von Agent A.
- `[2026-08-08 23:15 UTC]` **🗺️ Stadt-Land-Fluss Paar-Edition**: Anti-Spoiler-Commit (aufgedeckt wird erst, wenn BEIDE versiegelt haben — vom Relay beglaubigt), gegenseitiges Bewerten mit Auto-Buchstaben-Check, klassische 20/10/5-Punkte, eigene Kategorien, „Stop!"-Countdown mit Auto-Abgabe.
- `[2026-08-08 23:15 UTC]` **🤥 Zwei Wahrheiten, eine Lüge**: 3 Moves pro Runde — die Lüge wird MIT den Aussagen versiegelt (nachträglich beweisbar nicht tauschbar), Rollentausch, freche Auflösungs-Overlays.
- `[2026-08-08 23:15 UTC]` **⚔️ Paar-Tagesquests**: 3 Mini-Missionen täglich, deterministisch aus `coupleId + dateKey` (48 Quests DE/EN — „Schickt euch heute ein Foto von eurem Frühstück"), geteilte Häkchen (wer zuerst tippt, hakt für beide ab), 🔥-Streak mit Schonfrist, jeder Haken emittiert ein `quest_done`-Event für das XP-System von Agent C.
- `[2026-08-08 23:15 UTC]` **🥇 Turnier-Modus & Saison-Trophäen**: Monats-Saison über ALLE Spiele (3 Punkte pro Sieg, 1 pro Remis — deterministisch aus `GET /api/games` abgeleitet, beide Handys rechnen identisch), Saison-Ende-Zeremonie mit Fanfare, Trophäen-Regal mit Gold-, Geteilt- und **Koop-Trophäen** (Marathon-Paar 15+ Partien, Entdecker-Duo 6+ Spielarten).
- `[2026-08-08 23:15 UTC]` **🎬 Replay & Zuschauer-Modus**: jede beendete Partie als Film — Züge in Originalreihenfolge, Async-Pausen im Zeitraffer, Play/Pause/Scrubber/1-2-4×, der **Wende-Moment** ⭐️ wird markiert, Recap in den Chat teilbar; offene Partien lassen sich live beobachten (Zweitgerät/iPad — read-only, die Architektur schenkt uns das).
- `[2026-08-08 23:15 UTC]` **✅ Qualität**: +31 Server-E2E-Tests in meiner Zone (Suite 125 → 191 mit A+C, grün), iOS-Logic-Tests 77 → 161 (Reducer aller 7 neuen Spiele + Commit-Reveal + Saison + Replay, alle Linux-getestet), alle GUIs im Liquid-Glass-Stil mit Delight-Engine-Feiern, DE/EN komplett, `docs/API.md` um Spiele-Konventionen (Seed, Commit-Reveal, Event-Hooks) ergänzt.

### Iteration 3.0-C — Level, Delight & Plattform (Agent C) ✨
- `[2026-08-08 22:30 UTC]` **🎉 Delight-Engine**: zentrale Mikro-Feier-Schicht für die ganze App — Partikel + Haptik + prozeduraler Sound in 3 Intensitäten (`Delight.celebrate(.small/.medium/.epic)`), ein Overlay in RootView, wiederverwendbar für alle Features (Agents A/B hängen sich dran).
- `[2026-08-08 22:30 UTC]` **💜 Beziehungs-Level**: XP für ALLES, was ihr zusammen macht (Nachrichten, Berührungen, Spiele, Fotos, beidseitige Tagesfragen-/Check-in-Tage, Meilenstein-Events von A/B, …) — rückwirkend fair aus eurer Historie berechnet: am Tag des Updates habt ihr sofort das Level, das eure Geschichte verdient (ohne Zeremonien-Spam). Level-Kurve 100·(n−1)·n/2, Titel von „Frisch verliebt" über „Turteltauben" bis „Legendäres Duo" (Level 10), Level-Ring auf dem Dashboard, Level-Up-Vollbild-Zeremonie auf BEIDEN Handys, Level-Feld im Widget-Snapshot.
- `[2026-08-08 22:30 UTC]` **🏅 Abzeichen-Sammlung**: 20 Abzeichen als prozedural gezeichnete Glas-Medaillen (kein einziges Binär-Asset), davon 4 geheime (nur „???" bis zur Freischaltung 👀) — Trophäen-Regal mit Fortschrittsbalken, Verleihungs-Zeremonie live bei Freischaltung, einmal freigeschaltet bleibt freigeschaltet (auch wenn die Serie reißt).
- `[2026-08-08 22:30 UTC]` **🎁 App-Icon-Geschenke**: 9 prozedural gerenderte Icon-Varianten (Classic, Sunset, Midnight, Mint, Rose, Ocean, Gold, Lavender, Blossom) — such dir deins aus ODER schenk deinem Schatz eins: beim nächsten App-Öffnen gibt's die Auspack-Zeremonie 🎀 und das Icon wechselt.
- `[2026-08-08 22:30 UTC]` **🎛️ iOS-18-Controls**: „Herzklopfen senden" und „Bedürfnis-Knopf öffnen" fürs Kontrollzentrum, den Lock Screen und den Action Button (auf iOS 17 unsichtbar, sauber ge-guarded).
- `[2026-08-08 22:30 UTC]` **🫀 Haptik-Duett + Live-Herzschlag**: dasselbe Haptik-Muster startet auf BEIDEN iPhones im selben Augenblick (NTP-light-Uhrenabgleich über die WebSocket-Verbindung, 2 s Vorlauf) — und im Live-Modus streamen deine Taps in Echtzeit aufs 3D-Herz des Partners.
- `[2026-08-08 22:30 UTC]` **🌃 Date-Night-Live-Activity**: Abend planen (Titel, Emoji, Uhrzeit) → auf beiden Handys läuft der Countdown im Lock Screen / in der Dynamic Island, mit Phasen Vorfreude → Los! → Ausklang und „Weiter"-Button direkt in der Live Activity.
- `[2026-08-08 22:30 UTC]` **🍂 Saison-Themes**: Jahreszeiten-Partikel überm Dashboard (Blüten 🌸, Glühwürmchen ✨, Blätter 🍁, Schnee ❄️) — automatisch nach Datum oder manuell festgelegt, abschaltbar in den Einstellungen.
- `[2026-08-08 22:30 UTC]` **📸 Polaroid-Foto-Widgets**: Rahmen-Stile Polaroid / Filmstreifen / Scrapbook fürs Foto-Widget — im Widget-Studio wählbar oder pro Widget direkt (langes Drücken → bearbeiten), rein SwiftUI-gezeichnet.
- `[2026-08-08 22:30 UTC]` **🗺️ „Erste Woche"-Quest**: 7 geführte Mini-Aufgaben für frische Paare (Berührung, Nachricht, Tagesfrage zu zweit, Foto, Leinwand, Check-in zu zweit, erstes Spiel) — Finale bringt +150 XP, ein Abzeichen und die große Zeremonie.
- `[2026-08-08 22:30 UTC]` **✅ Qualität**: +22 Server-E2E-Tests (Level-Kurve, XP-Aggregation, Legacy-Baseline, Badges, Quest, Icon-Gift, Duett, Date-Night; Suite 188 grün), +7 Swift-Logic-Tests (LevelMath-Spiegel + SeasonLogic), `docs/API.md` um den kompletten Level-&-Plattform-Abschnitt ergänzt, DE/EN vollständig.

### Iteration 3.0 — Das große 3.0-Release 💜🚀
- `[2026-08-08 22:50 UTC]` **Version 3.0.0** (Build 25) überall: App + Widget-Extension (`project.yml`), Server (`package.json` → `/api/health` meldet 3.0.0). Vollständiges Changelog in `docs/CHANGELOG.md`, README-Features aktualisiert, `docs/API.md` auf v3.0.
- **Drei Wellen in einem Release**: 💞 Rituale & Beziehung (Audio-Check-in, Zeitkapseln, Bedürfnis-Knopf, Ziele, Wochenplan, Energie-Ampel, Monatsmagazin), 🎮 Spiele-Offensive (7 neue Spiele + parallele Sessions, Turnier-Saisons, Replay & Zuschauer-Modus), ✨ Level, Delight & Plattform (Beziehungs-Level, 20 Abzeichen, Icon-Geschenke, Haptik-Duett, Date-Night-Live-Activity, Saison-Themes, Polaroid-Widgets, iOS-18-Controls, Erste-Woche-Quest, Delight-Engine).
- **Alles greift ineinander**: Rituale und Spiele emittieren Meilenstein-Events (`events.js`) → das Level-/Badge-System verwandelt sie in XP und Zeremonien; die Delight-Engine feiert in allen drei Wellen; Wochenplan konsumiert Film-Roulette-Matches.
- **✅ Qualität**: Server-Suite **191 Tests grün** (125 → 191), Swift-Logic **161 Tests grün** auf Linux (77 → 161), DE/EN vollständig (L10n-Scan erzwingt es), CI grün inkl. unsigniertem IPA mit allen 9 Icon-Varianten.
- **Update-Pfad**: Server `git pull && npm install && npm start` — alle Bestandsdaten bleiben, euer Level ist ab der ersten Sekunde rückwirkend fair berechnet. IPA 3.0.0 wie immer über das rollende Release sideloaden.
- ⚠️ Hinweis: Die 3.0.0-CI-Läufe (Runs 31282365161, 31282782502, 23–23:20 UTC) wurden von GitHub wegen eines **Billing-Limits des Accounts** nicht gestartet („recent account payments have failed or your spending limit needs to be increased") — kein Code-Problem; die identische Codebasis war einen Commit vor dem Versions-Bump komplett grün (Server + Logic + IPA, Run 31282147674). Bitte einmal GitHub → Settings → Billing prüfen, dann baut der nächste Push (oder ein manueller „Run workflow" auf dem SoooDreamy-Workflow) das 3.0.0-IPA.

## 🔄 Als Nächstes
- IPA 3.0.0 sideloaden (AltStore/SideStore) + Server auf 3.0.0 aktualisieren (`git pull && npm install && npm start` — Daten bleiben erhalten).
- Feedback einfach oben in „💬 Dein Feedback" schreiben — wird jede Iteration gelesen.
