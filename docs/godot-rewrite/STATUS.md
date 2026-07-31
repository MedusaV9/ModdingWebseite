# STATUS — GOOBY-Godot-Rewrite (ehrlicher Ist-Stand)

Stand: **W13-Beginn (31. Juli 2026)** — nach den Wellen W1–W5 (M1-Kern), Mega-Eval +
Fix-Wellen, W6–W12 (Games/IPA, Ranch-DLC, Feedback, Polish, Complete, Final/IPA, Visuals,
Emotionen/Trailer) sowie den REST-1…5-/FERTIG-1-Pässen. Quellen: `GODOT-PLAN.md` (bindend),
`EVAL-VOLLSTAENDIGKEIT.md` (Revision FERTIG-1 + W13), die statischen Code-Verifikationen
der W13-Planungswelle, Test-Runner- und CI-Ausgaben. Dieses Dokument sagt ehrlich,
**was fertig ist** und **was Backlog ist** — die vollständige, nichts-verlierende
Backlog-Liste steht in `GODOT-PLAN.md` §6 (dort seit W13 mit ✅-Annotationen für Erledigtes).

## Gesamtbild in Zahlen

- **Vollständigkeit:** 70 von 79 prüfbaren Web-Features vollständig, 5 teilweise,
  3 fehlend, 1 offiziell gestrichen (Gooby Welt) — rund 90 %
  (`EVAL-VOLLSTAENDIGKEIT.md`, Rev. FERTIG-1). Einordnung dort: „inhaltlich
  komplettes Spiel in der Feinschliff-Phase — kein Alpha-Zustand mehr“.
- **Tests:** 2.074+ Haupt-Tests, ~15.000 UI-Checks (W1c-Runner), 99 Server-Tests —
  0 Failures. `gdlint`/`gdformat` sauber, alles headless reproduzierbar.
- **CI:** `gooby-godot.yml` grün **inklusive `ios-ipa`-Job** — jeder Push baut eine
  forensisch verifizierte, unsignierte .ipa (Artefakt `GOOBY-godot-unsigned-ipa`,
  ~189 MB). Sideload-Runbook: `docs/godot-rewrite/IOS-BUILD.md`.
- **Spiele:** 37 startbare Spiele — 30 portierte Web-Spiele + GvZ + GOB NOM +
  5 Ranch-Spiele.

## Was ist fertig (W1–W12)

| Bereich | Geliefert | Ehrliche Anmerkung |
|---|---|---|
| Fundament/Engine | Godot-4.4.1-Projekt, SceneRouter (EIN Transition-System inkl. `DOOR_TRAVEL`-Tür-Wisch mit threaded Preload), OrientationService, zwei Test-Runner, CI (Import→Tests→Lint→Boot-Smoke→ios-ipa) | Additives Tür-Laden + CamPath-Kamerafahrt = bewusste Backlog-Alternative (A §1.4); der Wisch ist die getestete EF-3-Lösung |
| Gooby/Charakter | Blender-Pipeline → `gooby.glb` (Rig, 11 Clips, Morphs), Gebrabbel-Stimme, Soul-/Mood-System (Launen, 6 Idle-Akte, Absichten, deterministisches Zuhause-Wetter `soul_wetter.gd`), **12 expressive Emotionen mit Kopf-Symbolen + Postprocessing-Stack** (W12) | P1-Zusatz-Clips (dance, ragdoll…) weiterhin Backlog F; Idle-Akte nutzen Posen/Tweens statt eigener Rig-Clips |
| UI/Meta-Loop | AC-Theme, HUD, Onboarding inkl. handlungsgeführter Tour, **Profil** (GOOBY-PASS mit 3D-Porträt + Abschluss-Karte), **44 Erfolge**, **Tagesquests** (Pool 24) + Tagesbonus-Streak, **Stickeralbum (141 Sticker, 23 Seiten)**, Codes-Screen, Galerie mit Foto-Export, Postkartenarchiv + Tagespaket, Radio-UI, News-Panel, Settings (Grafik-Presets, UI-Skalierung), DE führend + EN-Parität (testgetrieben) | Sammlungsset-UI, Rarity-Unlock-FX und Reisepass 2.0 (Passfoto) fehlen; Sammlungssets sind W13-Paket |
| State/Save | Save v5 (atomar, 3 Backups, Recovery), Migrationskette Web v0–v4→v5, Umzugskoffer-Codec, **iOS-Legacy-Import komplett** (GDScript-bplist-Parser + Auto-Import beim Erststart + Settings-Zeile „Spielstand übertragen“, FIX-6) | Recovery-Hinweis-Toast beim Boot weiterhin unverdrahtet (String + `state_loaded`-Signal existieren, kein Konsument) |
| Haus/Bau/Garten | 5 Räume, Tür-Gag, Baumodus mit RUG/FLOOR/SURFACE/WALL-Layern, **207 Möbel (203 mit GLB)** + Lager, Fenster-Diorama (Straße mit Autos / Garten), Haus von außen sichtbar + Dachschrägen/Deckenbalken (W12), Werkstatt + Crafting (5 Rezepte), Goobay-Verhandlung, Garten 2.0 (Stufen, Kanten-Zäune, Gewächshaus, Sprinkler, Echtzeitwachstum), Shed L1–L3, Möbel-Bestell-Cutscene | CEILING-Layer fehlt (Decken-Items laufen als WALL); Keller/Etage/Balkon, Garage, Layout-Presets = M3 |
| Stadt/Orte | 15×12-Stadt mit Verkehr, Fußgängern, Tag/Nacht, Near-Miss-Hupe; **9 begehbare Orte-Interieurs** (u. a. Tierarzt „Dr. Dr. Möhrchen“, Baumarkt „Bodo Balken“, Autohaus „Blechbert“, Wochenmarkt Sa 8–14 mit Preiselastizität); Dialog-System (9 DE-Bäume + EN); IGohbie-Phone mit 6 Apps (Taxi, Guber, GOOBERANDO, Kamera, Freunde, GoobyPal); Fotomodus + POW-Kamera-Gate; Minimap mit Pins; Urlaub mit 9 buchbaren Zielen | GOOBERANDO: 1 Restaurant + Prep-Timer statt Fahrer-Sim; Raumstation-GOOB-1-Hub, InstantGooby-/Snap-Apps fehlen |
| Minigames | Framework (Host/Pregame/Results/JuiceKit, GoobyRng bit-identisch), **37 startbare Spiele**, Endless-Modi (29/33 Manifeste + Lock), Modifier-Engine (6 Typen, wirkt via Framework auf alle Spiele), GvZ-Kampagne (15 Level, 12 Türme + Goldi-Code-Gate), GOB NOM (15 SP- + 10 Coop-Level, alle solver-bewiesen; Coop lokal/hot-seat) | City Drive fehlt als Arcade-Runde; Web-Fixture-Zertifizierung nur für 2 Ports; GvZ-Sticker/Goldi-Code waren bis W13 unverdrahtet (W13-Paket) |
| Ranch-DLC (W6–W9) | Open World (9 Zonen + Bergmassiv + 7 weitere Zonen, Wegenetz, 9 Entdeckungsorte), 12 Pferderassen (Pflege/Leveln/Zähmen/Zucht/Stammbaum), 13 NPCs mit Freundschaftswerten, 27 Quests/10 Kapitel + Warte-Quests, Bau-Grid, Dorf Hufingen, 7 Wettbewerbe + Liga, deterministisches Wetter **mit sichtbaren Regen-/Schnee-FX**, 5 Ranch-Minigames, Ranch-MP (Besuche, Gruppen-Ausritt, 3 Live-Kurse, Ghost-Leaderboards), verstecktes Dev-Menü | Freischalt-Level ist noch 20 — W13 senkt auf 15 (User-Wunsch); ranch-spezifische Random-Events fehlen (W13-Paket) |
| Funkelpark (W10) | Plaza, Coaster, Riesenrad, Autoscooter, Karussell, Naschgassen-Stände mit echten Katalog-Speisen | — |
| Cosmetics | **92 Einträge** (alle 42 Web-Outfits 1:1 + 37 neue + 7 alte und 6 neue Fellfarben), Garderobe mit Live-Vorschau, geteilter SubViewport-Icon-Renderer, Pack-Format | Galaxie-Fell-Shader fehlt; Laufzeit-glb bewusst durch prozedurale Builder ersetzt (für Pack-Updates gleichwertig) |
| Updates/Packs | PackLoader + Boot-Guard (2-Crash-Regel), ContentRegistry-Merge, **14 Pack-Quellordner** unter `content/`, Pack-CI (`gooby-packs.yml`), config-Sofortkanal (Server-IP/Port ohne IPA, bei jedem Connect frisch gelesen), Handbuch `docs/UPDATES.md` | `gooby-updates`-Release-Repo = User-Action; `gooby-packs.yml` lief noch nie → kein Ende-zu-Ende-Release-Test; `latest_native`-Bump beim IPA-Release existiert noch nicht (geplant, B §5.2) |
| Server | `GOOBY-SERVER/`: express+ws, ein Port, JSON-Storage, HELLO/WELCOME/TOFU, Freunde+Presence, GoobyPal (250/Tag), Codes, Events, **Analytics mit Spielzeit-Panel**, Besuche, Brettspiele (**Schiffe versenken + Schach**), Ranch-MP, Webpanel (fail-closed, 6 Seiten), AMP-Anleitung | Post/Mail + InstantGooby fehlen (Blob-Storage-Fundament liegt bereit); Presence-Labels DE-only |
| Trailer (W12) | Finale MP4 **57,6 s, 1080p60** (h264+aac), Remotion-Projekt + reproduzierbare Capture-Pipeline (68 Clip-Skripte, Movie-Maker 60 fps); Musik „Glitter Blast“ (Kevin MacLeod, CC BY 4.0), Schnitt aufs 100-BPM-Beat-Grid | Track bewusst instrumental — dokumentierte Abwägung des Lyrics-Wunschs (s. GODOT-PLAN §6/Prozess-Notiz) |
| Bug-Sweep (W10/REST5) | „533 warnings → 5“: Lambda-Captures (B2), Nav-Map-Sync (B3), GPU-Navmesh-Bake (B5), SubViewport-Resize (B8), `specular`-Warnungen (B9), Nav-Präzision (B10) **behoben** — Details + Belege in `EVAL-VOLLSTAENDIGKEIT.md` (Revision W13) | B4-Leaks nur teilweise (kein systematisches Leak-Gate); B11 (GvZ-Anchor-Warnung) offen — W13-Paket |

## Bekannte Lücken (nicht verschweigen)

- **Feature-Restpunkte** laut EVAL (FERTIG-1): Ball-Wurf, Sammlungsset-UI im Album,
  sichtbare Wetter-FX in Haus/Garten/Stadt (nur die Ranch hat sie), 12 fehlende
  Speisen (6 davon mit vorhandenen Assets), Nougatschleuse, Fotomodus-Werkzeuge
  (Pose/Emotion/Rahmen), Gyro-Parallax (Entscheid offen), City Drive als
  Arcade-Runde, semantischer E2E-„erste Stunde“-Test. Mehrere davon sind
  W13-Pakete (s. u.).
- **Technik:** B11 (non-equal-opposite-anchors-Warnung in GvZ) offen — W13;
  B4-Leaks teilweise behoben, ein systematisches Leak-Gate fehlt.
- **`gooby-updates`-Release-Repo + `GH_CONTENT_TOKEN` fehlen** (User-Action) →
  das Update-System ist nur gegen lokale/Fixture-Manifeste getestet.
- **iOS:** CI liefert grüne unsignierte .ipas als Artefakt; Release-Asset +
  `latest_native`-Bump fehlen (B §5.2). Store-/Dauer-Signing gibt es bewusst
  nicht (Sideload-Modell, 7-Tage-Signatur mit freier Apple-ID); echtes
  iPhone-Profiling steht aus (User-Action: .ipa sideloaden, Rückmeldung).
- **Natives Notification-Plugin fehlt** — bei geschlossener App kommt nichts an
  (dokumentierter Andockpunkt `_os_schedule()`); ActivityKit-Live-Activity = M3
  (braucht Signing).
- **Recovery-Hinweis-Toast beim Boot unverdrahtet:** String
  (`system.recovered_backup`) und Signal (`state_loaded`) existieren, aber kein
  Konsument.
- **Presence-Labels kommen DE-only vom Server**; der EN-Client zeigt deutsche
  Aktivitätstexte.
- **Tote UI-Drähte** (W13 in Arbeit): „Wo ist mein Gooby?“-Chip und Auge-Button
  hatten keine Consumer; GvZ-Sticker-Counter und Goldi-Code waren unerreichbar.
- **Garderobe-HUD-Knopf:** Das H-Doc wollte ihn entfernen (Spiegel + Shop), W6
  hat ihn bewusst zurückgebracht — offener User-Entscheid, aktuell existieren
  BEIDE Wege (Knopf + Spiegel). Dokumentiert in GODOT-PLAN §6/H-Notiz.

## Mehrspieler + Save-Transfer — ehrlicher Ist-Stand

**Funktioniert JETZT** (Client + Server zusammen getestet; 99 Server-Tests grün,
Godot-Hauptsuite 2.074+ Tests grün):

- Verbindung: HELLO/WELCOME-Handshake (TOFU), PING/PONG, automatische
  Wiederverbindung mit Backoff; Offline-Outbox (Redeem/Events/Presence/Analytics);
  Verbindungsanzeige (Online/Verbinde…/Offline-Chip).
- Freunde: Freundescode (`GOOBY-XXXX`), Einladung/Annahme, Presence-Liste.
- Besuche: Haus-Snapshot beim Gastgeber, beide Goobys sichtbar (POS-Relay 5 Hz),
  Besuch beenden/Timeout.
- GoobyPal: Münztransfer mit Tageslimit 250 (serverseitig), Pending-Zustellung
  mit Ack. (Die Verlaufs-LISTE wird im Client noch nicht gerendert — Backlog C.)
- **Schiffe versenken KOMPLETT**: Vollpartie, Emotes + Tomate 1×/Runde, Aufgeben,
  Revanche mit Rollentausch, 120-s-Rejoin-Fenster mit History-Replay.
- **Schach KOMPLETT** (seit den W6–W12-Wellen): Client-Legalität
  (`chess_logic.gd`) + AI + Session; der Server relayt über dieselbe
  Brettspiel-Turn-Maschine (`boardgames.js`, `GAMES = ['battleship','chess']`) —
  Rejoin/Rematch/Forfeit/Tomate identisch.
- **Ranch-MP**: Besuche, Gruppen-Ausritte, 3 Live-Kurse (Rennen/Fangen/Parcours),
  Ghost-Leaderboards, Reaktions-Relay; offline-first (`{ok:false, code:"OFFLINE"}`
  blockiert nichts).
- Analytics: Spielzeit-Erfassung ab t=0 + Offline-Outbox; Webpanel zeigt
  Minuten/Tag, Pro-Spieler-Tabelle, Stunden-Histogramm.
- Save-Transfer: Umzugskoffer-Codec, bplist-Legacy-Import (GDScript, ohne
  Plugin), Auto-Import beim Erststart, Settings-Zeile — komplett (FIX-6).

**Fehlt noch (ehrlich):**

- Post/Mail (Briefe/Fotos/Item-Geschenke) + InstantGooby — der Post-Ort und das
  Blob-Storage-Fundament existieren, das Mail-Modul fehlt (Backlog C, größtes
  offenes Backend-Paket).
- Coop-Fahrt mit Radio-Sync (Server-`drive:`-Room fertig, Client fehlt);
  Besucher-schläft-auf-Couch-Regel; Snap A Gooby.
- GvZ PvP/Coop und GOB-NOM-Netz-Coop: Simulationen sind netz-vorbereitet
  (Lockstep/`state_hash`, `mg:`-Rooms laufen fürs Ranch-MP), die Netz-Sessions
  fehlen; GvZ-Coop-Level existieren noch gar nicht.
- `ws://`-Heimnetz-Gate im Client (die wss/TLS-Deploy-Doku existiert im
  Server-README); TOFU statt CA-Pinning.
- Kein öffentlicher Produktiv-Server: Betrieb weiterhin selbst hosten
  (`GOOBY-SERVER/README.md`).
- Matchmaking/zufällige Gegner gibt es nicht (bewusst: nur Freunde).

## W13 — läuft gerade (in Arbeit)

9 parallele Code-Pakete (Stand 31. Juli, Ergebnisse werden nach der Runde hier
und in GODOT-PLAN §6 nachgeführt):

1. **GvZ-Verdrahtung** — Sticker-Counter + Kampagnen-Hook + Goldi-Code-Effekt
   einlösbar machen; dazu der B11-Layout-Fix.
2. **Gooby-Suche + Auge** — „Wo ist mein Gooby?“-Kamera-Fokus + Tat-Bubble;
   Auge-Button → sichtbare Interaktions-Anzeige.
3. **Ball** — Ball-Wurf/Fetch im Haus (letzte fehlende Kern-Care-Interaktion).
4. **Wetter-FX** — sichtbarer Regen/Schnee in Haus, Garten und Stadt
   (Generalisierung des Ranch-Controllers).
5. **Sammlungssets** — die 4 alten Sets (Fische/Gemüse/Landmarks/Leckereien)
   als Set-/Claim-UI im Album.
6. **Speisen + Nougat** — 6 fehlende Katalog-Speisen mit vorhandenen Assets +
   Nutella/Nougatschleuse.
7. **Radio-Gates** — Bordmusik nur pausierbar, Skip/Sender erst nach IKEA-Kauf.
8. **Ranch-Level-15 + Events** — Freischaltung ab Level 15 (statt 20) +
   ranch-spezifische Random-Events.
9. **Netz-Kleinpaket** — kleine Multiplayer-Nachzügler aus Backlog C.

## M2/M3 — Backlog (Kurzfassung; vollständig + bindend in GODOT-PLAN §6)

Real noch offen nach dem W13-Planungsabgleich (Erledigtes ist in §6 mit ✅
annotiert; W13-Pakete oben nicht erneut gelistet):

- **A Engine:** DOOR_TRAVEL-Kamerafahrt (Polish), echtes iPhone-Profiling
  (User-Action), LightmapGI-Option. M3: Shader-Warmup-Quad, Ragdoll-Experiment.
- **B Updates:** `gooby-updates`-Repo (User-Action) + Ende-zu-Ende-Release-Test,
  Release-Asset + `latest_native`-Bump, Soft-Restart-Flow. M3: RSA-Signierung,
  Mirror #2 über den Node-Server.
- **C Backend:** Post/Mail + InstantGooby, GoobyPal-Verlaufs-Liste,
  `ws://`-Heimnetz-Gate, Besucher-Couch, Snap A Gooby, natives
  Notification-Plugin. M3: Coop-Fahrt, Koop-Minigames-Relay, Taxi-Live-Activity,
  Account-Umzugs-Code, Companion-App-Modus (W13 neu erfasst).
- **D Haus:** CEILING-Layer, Wochenmarkt-Eigenstand. M3: Keller/Etage/Balkon,
  Garage, Layout-Presets.
- **E Stadt:** GOOBERANDO-Vollausbau (3 Restaurants + Fahrer-Sim), Raumstation
  GOOB-1, Urlaubs-Boni (Weltengooby/Erholungs-Boost/GOOBY-FREE-Shop),
  Stadt-Polish (Near-Miss-Funken, Guber-Surge, Ziel-GPS-Pfeil). M3:
  Ambient-Audio-Distrikte, Traffic-Vollausbau.
- **F Gooby:** Schüttel-Secret, P1-Clips, Geschichten-Stunde-Ausbau,
  `klopapier_mumie`-Event, Fotomodus-Werkzeuge. M3: Laufband-Gag,
  GOBBULL-Zocken, P2-Clips, PhysicalBone-Ragdoll.
- **G Minigames:** City Drive + 3-Strikes-Cutscene, Auto-Stats in Fahr-Spielen,
  Difficulty-Zertifizierung ausweiten (cross_check auf alle Ports),
  GOB-NOM-@tool-Editor. M3: HDR-Glow-Telemetrie, danceParty-Latenz-Kalibrierung.
- **H UI/Content:** Reisepass 2.0 (Passfoto — expliziter User-Wunsch),
  Abflugtafel-Optik, Sticker-Rarity-FX, Galaxie-Fell, GOB.TY,
  Girlanden/Spann-Deko, Goobyman-Laden, Presence-i18n.
- **Qualität:** semantischer E2E-„erste Stunde“-Test, B4-Leak-Gate.
