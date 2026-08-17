# MONKEY MONEY — Status & Feedback-Log

## Welle 4 (iPad-Host + Internet-Links + UI-Perfektion 2) — ABGESCHLOSSEN

- **.ipa baut jetzt bei JEDEM Push** (ipa-gate entfernt) — aktuelles Artefakt:
  `monkey-money-unsigned-ipa` (107 MB, komplettes Standalone-Bundle: alle Fragen,
  Songs, Tutorial-Videos, Medien im Gerät)
- **Host-Button in der App**: Hero-Button „🎪 Party hosten — iPad ist der Server"
  → Adresse RIESIG + QR + WLAN/Hotspot-Hinweis; sekundär „Mit Server verbinden"
- **Lokale Speicherung im Standalone**: Save-Slots, 30s-Autosave, Boot-Wieder-
  belebung, Profile/AT/Level — alles in IndexedDB, überlebt App-Neustarts
  (bewiesen: Match speichern → Host-Reload → laden → nahtloser Resume)
- **Internet-Links per Cloudflare aus der UI**: Screen-Lobby-Knopf „Link
  erstellen" → echte trycloudflare-URL + eigener QR (von außen per curl
  bewiesen!), GM-Tunnel-Karte, freundliche Install-Hinweise wenn cloudflared
  fehlt; iPad-Standalone zeigt ehrlich „nur am PC/AMP-Server"
- **2 neue Formate (jetzt 27)**: Risiko-Leiter (8-Stufen-Gewinnleiter mit
  Absichern/Klettern + Sicherheitsstufe), Einer gegen alle (Führender vs.
  Mehrheits-Kollektiv, anonyme Abstimmung)
- **UI-Perfektion 2**: Auflösungs-Karten (Gold-Puls, Puppen-Kopf-Chips),
  Highlights mit Replay-Animationen + Count-up, Ende-Screen mit Revanche-CTA,
  K.O.-Zeitlupe + Sieger-Posen, 📌-Kernregel-Banner auf allen 27 Erklär-Demos,
  Admin-Token-Look; Shop-Vitrine (Slot-Sektionen, Seltenheits-Rahmen, Live-
  Thumbnails), Pass als Serpentinen-Bananen-Pfad, Profil als Affen-Ausweis,
  Training im Match-Look, Bestenlisten-Podest
- **+575 Fragen → 7660** (12 Kategorien auf 78-100 vertieft)
- 1062 Tests grün, CI komplett grün (inkl. .ipa bei jedem Push)

## Welle 3 (UI-Perfektion + Musik + neue Formate) — ABGESCHLOSSEN

- **UI/UX**: GM-Cockpit als Zonen-Regie (Regie-Zeile, Kontext-Karte, Akkordeons),
  Bühnen-Feinschliff (LED-Glow, Phasen-Crossfades, Medaillen-Zwischenstand,
  Opening-Spotlight-Beat 2, Rad-Sticker-Vorschau), Handy-Mikro-Feedback überall
  (View-Transitions, Press-States, Idle-Affen, Money-Count-up, Streak-Flammen,
  Join-Steps, Wett-Slider-Snap) — alles Reduced-Motion-gated
- **Echte Hintergrund-Musik**: `import.mjs --bett` (60-90s-Loops, −18 LUFS),
  4 Klassiker-Loops als Demo (Piaf/Armstrong/Garland/Miller), Playlist-Rotation
  pro Phase (deterministisch, kein Doppel), Musik-Control am Screen (Toggle/
  Volume/Skip/Track-Ticker mit Credits) + GM-Musik-Karte + Match-Setting
- **4 neue Formate (jetzt 25)**: Bananen-Tortenschlacht (Buzz-Klassiker: 3 Sahne-
  Schichten = raus, letzter Saubere gewinnt den Topf), Bananen-Boxkampf (1v1,
  Punches über Gelenk-Puppen, HP, K.O., Zuschauer-Wetten), Konter-Quiz (1v1-
  Blitz: Fehler zahlen den Gegner, nullsummig), Wer singt's? (Titel→Interpret,
  84er-Fakten-Pool, Schallplatten-Flip)
- **22 echte Cosmetics (73 Items)**: 8 Kopf- + 4 Gesichts-Accessoires, 5 Fell-
  MUSTER (SVG-Pattern: Tiger/Bananen-Punkte/Sterne/Camo/Gold-Glitzer),
  3 Podium-Rahmen, 2 Einlauf-Effekte — alle live am Affen/Podium/Opening
- **+600 Fragen → 7085** (12 Kategorien auf 78-100 vertieft, verrueckte_gesetze
  einzeln web-verifiziert)
- **QA-Playthrough**: Marathon mit allen neuen Formaten grün, 1 GM-Spickzettel-
  Bug bei roundBased-Formaten gefunden+gefixt; 959 Tests, CI grün

> Branch `cursor/monkey-money` — komplett eigenständiges Projekt (von null gebaut).
> Stand: v1 KOMPLETT + v2-Wellen 1+2 + RIESEN-CONTENT-RUNDE + Musik/Meta/Show-Welle +
> **Eval-Welle 1 ABGESCHLOSSEN (10 Juroren: 1×JA / 9×NEIN) — Fix-Welle 2 arbeitet die
> Blocker ab, danach Eval-Welle 2**. CI grün inkl. unsignierter iPad-.ipa.

## Neu: Musik-, Meta- & Show-Welle (aktueller Stand)

- **Musik-System komplett**: Song-Pack-Pipeline mit 1-Zeilen-Import zuhause
  (`node tools/musik/import.mjs --suche "Nena - 99 Luftballons" …` → yt-dlp-Download,
  −16-LUFS-Normalisierung, alle Snippets [Intro 5s / Buzz-Treppe 100–1000ms / Mitte 10s /
  Rückwärts 5s], Katalog + Credits automatisch, Volldownload wird gelöscht) + Validator;
  Starter-Pack: 19 echte Songs (docs/MUSIK-PACKS.md)
- **4 Musik-Formate** (jetzt 21 Plugins): Blitz-DJ (Buzz-Treppe mit Verfalls-Preis),
  Rückwärts-Banane, Stummfilm-Studio (Musikvideo ohne Ton), 7-Buchstaben-Telegramm
  (Song-Titel + Begriffe tippen)
- **Level & Dschungel-Pass**: 30 Stufen, XP aus Matches/Quests, 6 Quests, Saison-Logik
  (verdiente Items bleiben dauerhaft); Level-Badge reist im Avatar-Wire-Format mit
- **14 Affen-Puppen** (vorher 8): neu u. a. Kommissar Kokosnuss, Astro-Astrid, Iro-Ines,
  Abraka-Dieter, Kahuna-Kalle, Schnarch-Schorsch — alle als Gelenk-SVGs mit Palette-Swap
  und Gesichts-Attributen
- **Lobby-Browser**: öffentliche Lobbys live auf der Landing (erscheinen/verschwinden ohne
  Reload), Schnell-Beitritt wählt die vollste offene Lobby — Race-fest bewiesen
  (7/8-Lobby + 2 gleichzeitige Joins → genau EINER rein, sauberer Voll-Fehler)
- **Standalone-Host** (iPad ohne PC): Host-Logik läuft im Browser, Relay verbindet die
  Telefone, IndexedDB-Event-Log persistiert — Vollmatch bis Siegerehrung, Token-Reconnect
  und Relay-Neustart MITTEN im Match nahtlos bewiesen
- **Erklär-Demos**: je Format animierte SVG-Puppen-Demos auf der Erklärkarte statt reiner
  Regeltext-Wand (Bananen-Basics/Affenbank ohne Fließtext grob verständlich)

## Playtest-Welle: 4 Kritiker-Agents mit Scorecards + Fix-Status

Vier parallele Playtest-Agents haben LIVE gespielt (Musik-Formate · Standalone/Lobby/Teams ·
Quick-Match-UX · Meta-UX) und gnadenlos benotet. Dopamin-Scorecard Quick-Match: Join 7,
Frage 8, **Auflösung 9** (messbar: Riser → 650 ms echte Stille → Fanfare), Zwischenstand 6,
Rad 6, Ende 8 (je /10). Meta-Scorecard: Profil 4, Shop 5, Pass 7, Boards 6, Training 8,
Admin 4. Gesamturteil: „gute Beta, noch nicht Jackbox-Qualität" — die Befunde sind adressiert:

**Fix-Status P1/P2 (Stand Eval-Welle 1):**

- ✅ **Telegramm bekam NIE Song-Titel** (Engine-Lücke, 0/16 Beats): neues Meta-Flag
  `wuenschtSongs` — flow hängt den Song-Pool READ-ONLY an (bewusst OHNE
  usedSongIds-Verbrauch: Titel-Raten verbrennt kein Blitz-DJ-Kontingent)
- ✅ **Stummfilm-Studio in keiner Playlist**: Video-Zähler-Gate (`meta.minVideoSongs: 3`)
  - Marathon-Slot — mit dem 1-Video-Starter-Pack fällt der Slot ehrlich aufs
    Frage-Format zurück, ab 3 Video-Songs ist das Format drin
- ✅ **Auto-GM-+10s-Heuristik duck-typte auf View-Felder** (Blitz-DJ-Falle): explizites
  Opt-out `meta.autoVerlaengerung: false` statt Feldnamen-Raten
- ✅ **Relay-Shim clientId-Leak nach Relay-Neustart** (D3): reset-Frame beim Bridge-Attach
  räumt Leichen-Einträge auf + boot-eindeutige clientIds im Relay
- ✅ **pageerror-Telemetrie** (Play3-Wunsch): window.onerror/unhandledrejection → POST
  /api/fehler mit Phase/Minigame/URL (JSONL, Drossel 10/min/IP), Admin zeigt die letzten 20
- ✅ Von den Playtestern selbst gefixt + gepusht: Wettslider-lit-Crash (Player-UI fror ein),
  max-rooms-Endlos-Reload, Standalone-GM-Save-Hinweis, Join-CTA unter der Fold
  (Profil-Carousel), Ergebnis-Stempel-Overflow, Meta-Copy/Touchziele/Pass-Schriftgröße
- ✅ **Show-Fixes** (Fix-Agent Show): Quick-Affenbank kompakt (1 Durchgang × 45 s statt
  2 × 90 s — Klassik/Marathon behalten die lange Kette), formatspezifische
  Affenbank-Status (GEBANKT/NICHT GEBANKT/LEER AUSGEGANGEN statt falschem „ZU LANGSAM"),
  Ton-Schalter aus der schwebenden Ecke in die Spieler-Kopfzeile (überdeckte Antwort D),
  Münz-Overlay endet hart beim Phasenwechsel, Zwischenstand 7 s → 5 s + eine animierte
  Stand-Story pro Beat, Siegerehrung 20 s → 12 s mit Awards nacheinander, Rad-Live-Vorschau
  (anvisiertes Segment groß lesbar), Opening-Labels + Spotlight-Sweep, deutsche
  Kategorie-/Schwierigkeits-Labels statt Rohslugs, Joker-Labels mit Ellipsis auf 390 px
- ✅ **Meta-Fixes** (Fix-Agent Meta): „Willkommen zurück" listet NUR Profile dieses Geräts
  (fremde nur über bewussten „Anderes Profil laden"-Flow mit Name+PIN), PIN-Scheinprüfung
  beseitigt (explizite PIN wird IMMER wirklich geprüft), Willkommens-Paket (300 Start-AT +
  Gratis-Titel gegen die 0-AT-Sackgasse), Shop-Filter (Typ-Chips mit Counts, Kaufbar/Besitz,
  Preis-Sortierung), Profil-Karte meldet das 90-s-Analytics-Ruhefenster ehrlich,
  Admin-Fehlerhaft-Queue BEDIENBAR (Quarantäne/Entkräften/Geprüft + Refresh),
  Board-Fortschritt („Noch X bis zur Wertung")
- 📋 Dokumentiert (Betrieb/Design): MAX_ROOMS-Erschöpfung auf geteilten Test-Servern
  (leere Räume leben 30 min TTL — Env erhöhen oder nie-benutzte Räume schneller abbauen);
  Shop-„Anprobieren" vor dem Kauf + Admin-Suche/Pagination als nächste Meta-Ausbaustufe

## Offene Punkte (ehrlich)

- **Standalone-Save/Load**: der Meta-Service zieht node:fs und ist im Browser-Host bewusst
  NICHT verdrahtet (GM zeigt jetzt einen ehrlichen Hinweis statt roher Fehler). Die
  IndexedDB-Persistenz (Event-Log + Reconnect) funktioniert — echtes Save/Load bräuchte
  die Entkopplung von node:fs/Analytics (größerer Umbau, eingeplant)
- **Musikvideo-Nachschub**: das Starter-Pack hat erst 1 Video-Song, Stummfilm-Studio
  schaltet sich ab 3 frei. Nachschub geht NUR zuhause per 1-Zeilen-YouTube-Import
  (docs/MUSIK-PACKS.md, `--video`-Modus) — yt-dlp-Downloads laufen bewusst nicht in CI/Cloud
- `musik/intro_erkennen` (Fragen-Kategorie) wartet weiter auf lizenzierte Clips — das
  Song-Pack-System ist dafür der Weg

## Eval-Welle 1: Ergebnis der 10 Juroren (1×JA / 9×NEIN)

10 unabhängige Juror-Agents haben parallel und gnadenlos geprüft — jeder mit eigenem
Fokus, eigenem Live-Lauf und Release-Frage „Würdest du das HEUTE auf einer Party
spielen?". **Gesamturteil: 1×JA, 9×NEIN** — einhelliger Tenor: das Fundament trägt
(Robustheit/Reconnects/Engine top), aber Show-Politur, Deploy-Vollständigkeit und
Design-Konsequenz sind noch nicht Jackbox-Niveau. Kernbefunde je Juror (Belege als
Screenshots/Logs archiviert, u. a. `mm_eval1_*`–`mm_eval10_*`):

| Juror   | Fokus                             | Kernbefunde (Blocker fett)                                                                                                                                                                                               |
| ------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Eval 1  | Show-Dramaturgie Quick-Match      | **Auflösungs-Spoiler** (Wand verrät Ergebnis VOR der Fanfare), **AOB-Dead-Air** (Auto-GM streckt input-lose Phasen), Siegerehrungs-Audio läuft der Bühne davon                                                           |
| Eval 2  | Ersteindruck Join→Frage→Auflösung | Flow trägt, Feinschliff-Punkte an Join-Copy/Auflösungs-Beat                                                                                                                                                              |
| Eval 3  | Musik-Formate                     | Blitz-DJ-Treppe/Rückwärts-Aha funktionieren; **Musik-Dreiklang doppelt** (Formate mit eigener Regie bekamen die zentrale Fanfare obendrauf), Telegramm-Tastatur-Details                                                  |
| Eval 4  | Meta (Profil/Shop/Pass)           | Shop/Pass funktional, aber **„Admin-Oberflächen"-Optik** (Listen statt Show)                                                                                                                                             |
| Eval 5  | Screen-Lesbarkeit                 | LED-Wand gut lesbar; Kokosnussuhr-Antworten abgeschnitten, Kategorie-Ansage kam nur bei Alles-oder-Banane                                                                                                                |
| Eval 6  | Onboarding/Erstnutzer             | Fehlercode-/Doppelnamen-Fälle sauber; Erklärkarten tragen, GM-Einstieg findbar                                                                                                                                           |
| Eval 7  | Technik/Robustheit                | Reconnect-Matrix über alle Phasen grün, Kapazität/seq-Invariante grün — **Doppelgerät-Falsch-Offline** (2. Tab zu → Spieler dauerhaft „offline" trotz lebendem Tab 1)                                                    |
| Eval 8  | GM-Werkzeuge                      | Cockpit + Spickzettel + Beobachter-GM funktionieren im Live-Match                                                                                                                                                        |
| Eval 9  | Deploy/AMP                        | **Artefakt unvollständig: Opening-Stinger 404, Pixel-Bilder 404, 21 Tutorials 404, ALLE Songs 404** (assets/ + content/musik/ fehlten im dist-Artefakt); **git clone landet im Minecraft-Mod** (falscher Default-Branch) |
| Eval 10 | Design/Show-Look gesamt           | **Landing wirkt wie Funktionsmenü statt Show-Bühne**, **Token-Treue-Verstöße** (fremde Hexfarben, lineare Verläufe, Blur-Schatten, Bungee <32px), Shop/Pass ohne Show-Charakter                                          |

**Blocker → Fix-Welle 2 (6 Agents parallel, Datei-Hoheiten getrennt):**

- **Agent A (Show-Dramaturgie)** ✅ gelandet: Auflösung deckt exakt zur Fanfare auf
  (2-Stufen-Flip, Handys sofort), Auto-GM verlängert nur noch antwortbare Phasen
  (AOB-Reveal exakt 6 s), Siegerehrung koppelt an die Fanfare, Musik-Formate mit
  eigener Regie sind von der zentralen Regie ausgenommen
- **Agents B–D (Screen-Lesbarkeit, GM/Join-Polish, Technik)**: Kokosnussuhr/Ansagen,
  Join-/GM-Feinschliff, Doppelgerät-Falsch-Offline
- **Agent E (Meta-UX, .ts)**: Shop-Chips/Filter/Sortierung, Pass-Interaktion
- **Agent F (dieser Bericht)** ✅ gelandet: AMP-Artefakt komplett (assets/ +
  content/musik/ im Workflow + DEPLOY-AMP synchron, 404→200 real nachgestellt),
  git clone mit `-b cursor/monkey-money --single-branch`, README-Zahlen aktuell,
  Landing als Show-Bühne (echtes Logo, radiales Jungle-Night-Bühnenlicht,
  Hero-CTA-Hierarchie), Token-Treue-Sweep (196 Hex-Treffer → Token/color-mix,
  Ausnahmen dokumentiert), Shop/Pass-Sticker-Polish (nur CSS)

## Eval-Wellen-Plan (bis „alle glücklich")

Bis zu **10 Wellen à 10 Agents** (Eval-Juroren + Fix-Agents im Wechsel); nach jeder
Welle Scorecard-Vergleich gegen die Vorwelle, Abbruch-Kriterium: alle Kritiker geben
Release-Freigabe. **Zähler: Eval-Welle 1 ABGESCHLOSSEN (1×JA/9×NEIN), Fix-Welle 2
arbeitet die Blocker ab — Eval-Welle 2 prüft nach diesen Fixes nach.** (Davor: 4
Playtester + 3 Fix-Agents [Show/Meta/System] — siehe Playtest-Welle oben.)

## Riesen-Content-Runde (57 Fragen-Autor-Agents in 7 Wellen)

- **6485 geprüfte Fragen** in 248 Packs — ALLE 89 befüllbaren Unter-Kategorien haben Inhalt
  (Ausnahme: `musik/intro_erkennen` braucht lizenzierte Musik-Clips — bewusst offen, siehe unten)
- Kern-Kategorien auf 160-200 Fragen vertieft (LoL 160, Minecraft 152, Nintendo 160, Pokémon 140,
  Bundesliga 156, TV-Shows 156, Emoji-Rätsel 160, Flaggen 160, Hauptstädte 196 …)
- Typ-Mix: 74% Choice, 12% Wahr/Falsch, 7,6% Schätz, 3,4% Sortier, 1,8% Emoji, 1,1% Mehrfach
- **Anti-Halluzinations-Protokoll** je Agent: nur 100%-sichere zeitlose Fakten, Chunk-Sofort-Review,
  dokumentierte Streichungs-Listen (hunderte unsichere Kandidaten bewusst verworfen statt riskiert),
  „gilt als"-Rahmung bei Umstrittenem, Legenden explizit markiert, alle Fragen `faktencheck_status: entwurf`
- Selbst gefangene Fehler der Agents (Beispiele): Hans-Herrmann-Le-Mans-Irrtum, Kasparow-jüngster-WM
  (Gukesh 2024), Gretzky-Rekord (Owetschkin 2025), Tony-Parker-vor-Nowitzki, Costa-Cordalis-Tipp

## Neu seit v2-Welle 1

- **Team-Modus v1**: 2er/2v2v2v2/frei mit Stärke-Snake-Draft, Doppel-Affe-Regel bei ungerade,
  Team-Töpfe + Individual-Aufschlüsselung, Buzz-pro-Team-Gate, team-bezogener Underdog,
  AT-Team-Bonus, Team-Podest (39 Tests, Bot-Beweis `npm run bots -- --teams 2er`)
- **2 weitere v2-Formate** (jetzt 17 Plugins): Duell am Lianensteg (1v1 + Zuschauer-Wetten,
  pari-mutuel nullsummig), Der Goldene Affe (3-Stufen-Finale: Money-Drop → Schätz-Showdown →
  Buzzer-Best-of-3) — Marathon spielt 15 Runden / 71 Fragen komplett durch
- **Audio-Feinschliff**: Auflösungs-Dreiklang (Trommelwirbel/Riser → ECHTE Stille → Fanfare),
  8er-Buzzer-Timbre-Familie (jeder Slot klingt anders, Shop-Buzzer überstimmen), echter
  Rad-Holz-Ticker, 3-Stufen-Kassen-Kling, Loudness-Normalisierung auf −16 LUFS —
  13 neue CC0/CC-BY/PD-Sounds, alle in CREDITS.md attribuiert

## Was ist MONKEY MONEY?

Eine Jackbox/Buzz-artige Quiz-Show-Party-App: iPad/PC-Browser (oder die
unsignierte iPad-App) ist der große Bildschirm, 2-8 Mitspieler joinen per
QR-Code/Link mit dem iPhone (hochkant, Safari, kein Download). Optional
dirigiert ein menschlicher Show-Master vom eigenen Gerät — oder der Auto-GM
übernimmt. Ziel: das meiste MONKEY MONEY.

## Schnellstart

- **PC/Server**: `npm ci && npm run build && npm start` → `http://<lan-ip>:8080` (docs/DEPLOY-PC.md, inkl. Cloudflare-Tunnel)
- **AMP**: docs/DEPLOY-AMP.md (Generic Node App, HTTP-only ist eingeplant)
- **iPad-App**: GitHub-Actions-Artefakt `monkey-money-unsigned-ipa` + docs/IPAD-SETUP.md (Sideloadly/AltStore, Guided Access; App Clips gehen mit unsignierten Builds nicht — Begründung im Doc)

## Stand v1 (fertig, end-zu-end bewiesen)

- **11 Minispiel-Formate**: Vier Lianen, Bananen-Basics, Kokosnuss-Uhr, Bananen-Tresor, Affenleiter, Pixel-Dschungel (mit 12 generierten Bild-Motiven), Stinkbanane, Taschendieb, Affenbank (BANK!-Verrat), Alles oder Banane, Lianen-Finale
- **Engine**: Money-Ökonomie (100/250/500/1000 MM, Streak, Speed-Bonus, Jackpot-Glas, Underdog-Rückenwind, Finale-Aufholformel), Buzzer-Fairness (Median-RTT + 280ms-Fenster + Fotofinish), 7 Joker, Glücksrad (14 Segmente, GM-Rig), 8 Special-Rule-Settings, Modi Quick/Klassik/Marathon/Custom
- **GM-Cockpit**: alle 17 Werkzeuge (Punkte±, Zeit, Fragen-Regal + Maßanzug-Fragen pro Spieler, Tipp-Kanone + Flüster-Tipp aufs Einzelgerät, Votings, Fehlerhaft-Markierung mit Buchungs-Revert, Bestrafung, Underdog-Boost, 10-min-Bananen-Pause, Skip/Buggy-Flag, Feedback-Einsammeln, Auto-GM mit Drama-Meter) — alle 17 live per Playthrough verifiziert
- **Meta**: Profile (ohne Account-Zwang, PIN optional, Geräte-Wiedererkennung), All-time-Money, 4 Bestenlisten, Shop (20 Items, wirken im Match: Buzzer-Sounds, Konfetti-Stile, Avatar-Accessoires), Übungsmodus (Spaced-Repetition), AI-Mitspieler (5 Personas), Save/Load (3 Slots + Autosave, Server-Neustart-Roundtrip bewiesen), Admin-Analytics `/admin` (5 Reports: Fragen-Gesundheit, Schwierigkeits-Drift, Fehlerhaft-Queue, Lücken, Feedback-Inbox)
- **Show**: Studio-Bühne mit 8 Gelenk-Affen-Puppen, Cutscenes (Opening mit Blender-3D-Stinger, Runden-Karten, Siegerehrung), Sound-System (559 CC0-SFX + 6 CC-BY-Tracks, Credits in-App), Remotion-Trailer (72s) + 2 Tutorial-Videos
- **Content**: **1760 geprüfte Fragen** in 59 Packs (14 Ober-/90 Unter-Kategorien, 4 Schwierigkeiten inkl. ULTRAHARD, 3-Stufen-Tipps, DE/global-Flags), Validator mit 14 harten Regeln, eigene Fragen super leicht (docs/content/EIGENE-FRAGEN.md)
- **Qualität**: 448 vitest-Tests, Bot-Framework (komplette Matches headless, Chaos-Modus), Playwright-Touren, 2 menschliche Playthrough-Wellen (30-Fragen-Klassik + GM-Vollprüfung), CI mit Bots-E2E-Gate, alles grün

## Stand v2 (Welle 1 fertig)

- 4 neue Formate: Monkey Market (Chip-Handel), Bananen-Bluff (Lügen-Erkennung), Bananen-Börse (Herden-Quoten), Affen-Auktion (Antwortrecht ersteigern)
- Replay-Highlights am Match-Ende (6 Heuristiken aus der Match-Chronik + „DU warst das!")
- Foto-Finish-Share-Bild (Download auf Screen + Handys)
- Jubiläums-Erkennung (10./25./50./100. Abend der Gruppe, Rückblick-Stats)
- Sudden-Death Kokosnuss-Shake (Tap-Duell bei Gleichstand, rotes Studiolicht)

## Nächste Schritte

1. Fakten-Check-Runde 2 (Stichproben-Cross-Check läuft; die review-Flags der Autoren-Agents
   sind in den Wellen-Berichten dokumentiert — Vier-Augen-Prinzip pro Pack fortsetzen)
2. `musik/intro_erkennen`: braucht lizenzierte Musik-Clips (echte Song-Intros sind
   urheberrechtlich nicht bündelbar) — Vorschlag: eigene Aufnahmen/CC-Covers oder als
   Kategorie im GM-Editor den Nutzern überlassen
3. ~~Tutorial-Videos für die restlichen 15 Formate~~ ✅ ERLEDIGT: alle **21 Formate
   haben ein Tutorial-Video** (`assets/video/tutorial_*.mp4`, Remotion-Pipeline) —
   und seit Fix-Welle 2 reisen sie auch im AMP-Deploy-Artefakt mit
4. Affen-Laute/Publikums-Comedy-Sounds (ART-PLAN §4.3 Lücke 2)
5. Affenbank-Team-Ketten plugin-intern + GM-Cockpit-UI für manuelle Team-Zuweisung
6. Echte iPad/iPhone-Hardware-Runde (Wake-Lock/Safari-Eigenheiten über HTTP)

## Feedback bitte hier eintragen

- [ ] …
