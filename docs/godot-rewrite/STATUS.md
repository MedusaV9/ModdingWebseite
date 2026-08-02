# STATUS — GOOBY-Godot-Rewrite (ehrlicher Ist-Stand)

Stand: **nach W17/Welle G7 (2. August 2026)** — nach den Wellen W1–W5 (M1-Kern), Mega-Eval +
Fix-Wellen, W6–W12 (Games/IPA, Ranch-DLC, Feedback, Polish, Complete, Final/IPA, Visuals,
Emotionen/Trailer), den REST-1…5-/FERTIG-1-Pässen, **W13 A/B/C (Backlog-Großputz, 30 Pakete),
W14 (User-Feedback-Runde, 12 Pakete), W15 (Updates über dieses Repo + 9 weitere Pakete)
sowie den Feedback-Wellen G1–G7 aus W16/W17** (G1 Analyse, G2–G5 Umsetzung, G6 durch
VM-Neustart verloren und neu einsortiert, G7 „Spielgefühl“ P50–P58 + P38R — gelandet,
Abnahme s. u.). **Zuhause seit dem W18-Umzug: Repo `MedusaV9/ModdingWebseite`, Branch
`cursor/bubble-shield-loop`** (Umzugshistorie in `AGENTS.md`/`README.md`). Quellen:
`GODOT-PLAN.md` (bindend), `EVAL-VOLLSTAENDIGKEIT.md` (Rev. FERTIG-1 + W13 + W18-Notiz),
`UserFeedback.md` (Wellen-Abnahmen), git-Log der Wellen. Dieses Dokument sagt ehrlich,
**was fertig ist** und **was Backlog ist** — die vollständige, nichts-verlierende
Backlog-Liste steht in `GODOT-PLAN.md` §6 (dort seit W13 mit ✅-Annotationen für Erledigtes).

## Gesamtbild in Zahlen

- **Vollständigkeit (Web-Parität):** 70 von 79 prüfbaren Web-Features vollständig,
  5 teilweise, 3 fehlend, 1 offiziell gestrichen (Gooby Welt) — rund 90 %
  (`EVAL-VOLLSTAENDIGKEIT.md`, Rev. FERTIG-1). Einordnung dort: „inhaltlich
  komplettes Spiel in der Feinschliff-Phase — kein Alpha-Zustand mehr“.
  Diese Zahlen sind inzwischen KONSERVATIV: die damals offenen Restpunkte
  (Ball-Wurf, Sammlungssets, Wetter-FX, Speisen + Nougatschleuse,
  Fotomodus-Werkzeuge, Gyro-Parallax, City Drive) sind mit W13 gelandet
  (Revisionsnotiz W18 in der EVAL-Datei), und alles seit W14 (UI-Rework,
  DLC-Fundamente, Marktstand, Urlaubs-Besuche, Läden-Ambient …) liegt
  ZUSÄTZLICH über der alten Web-Parität.
- **Tests (letzte integrierte Voll-Abnahme = Welle G5, 1. August):** 3.387
  Haupt-Tests / 0 rot; String-Parität 25.962 Checks / 0; der W1c-UI-Runner lag
  zuletzt dokumentiert bei 25.026 Checks / 0 (W16/G2-Lauf). Server: 151
  Tests / 0 (Stand G7/P38R). `gdlint`/`gdformat` sauber, alles headless
  reproduzierbar. **Ehrlich:** die G7-Pakete sind einzeln mit ihren Suiten
  grün gelandet (u. a. Playtest `flow_arcade` 27/27 nach dem Router-Fix);
  die integrierte Gesamt-Abnahme des Voll-Laufs NACH G7 steht noch aus.
- **CI:** `gooby-godot.yml` grün **inklusive `ios-ipa`-Job** — jeder Push baut eine
  forensisch verifizierte, unsignierte .ipa (Artefakt `GOOBY-godot-unsigned-ipa`,
  ~189 MB). Seit dem W18-Umzug laufen die Actions unverändert im neuen Repo
  `MedusaV9/ModdingWebseite` (gleicher Workflow, gleiche paths-Trigger, gleicher
  Artefaktname). Sideload-Runbook: `docs/godot-rewrite/IOS-BUILD.md`.
  Server-CI `gooby-server.yml` seit W16/G3.
- **Spiele:** 38 startbare Spiele — 30 portierte Web-Spiele + GvZ + GOB NOM +
  City Drive (seit W13 echte Arcade-Runde) + 5 Ranch-Spiele (Zählung W16/G3:
  4 Registry-Spiele + 34 Manifeste).

## Was ist fertig (W1–W12)

_(Momentaufnahme nach W12 — die „Ehrliche Anmerkung“-Spalte beschreibt den
DAMALIGEN Stand; vieles davon ist seit W13–W17 geliefert und unten in den
Wellen-Absätzen dokumentiert.)_

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

## Bekannte Lücken (nicht verschweigen; Stand nach G7, 2. August)

- **G7-Abnahme:** Alle G7-Pakete (P50–P58, P38R) sind einzeln grün gelandet,
  aber der integrierte Voll-Lauf + das UserFeedback-Abhaken der Welle stehen
  noch aus.
- **UI-Restbefunde aus P57 (iPhone-17-Audit):** 23 offene Befunde nach der
  Nachmessung (114 → 23) — Guide-Karte über dem Bau-Dock, dock-interne
  Lager-/Dreh-Chip-Überlappungen, 3× `mg_results`; explizit an die nächste
  Welle übergeben.
- **Playtest-Befunde aus P58 (Pionier-Lauf):** Der Arcade-Zurück-BLOCKER ist
  gefixt (Router: flüchtige Ziele), offen bleiben: Overlay-Stau nach dem
  Onboarding (unsichtbarer Tagesbonus-Schleier schluckt Taps),
  Teestube-Streifen im Querformat, Bau-Ghost hinter der Knopfleiste,
  Onboarding-Karten links der Mitte.
- **Die verlorenen G6-Pakete** (VM-Neustart, transparent dokumentiert) sind neu
  einsortiert und offen: DLC Welle B beider Läden, Ball-Wurf-Paket,
  DLC-Ladebildschirme, Audio-Feel, B11 + Warn-Sweep-Nachfasser, McGooby-Bühne,
  Alwin-NPC, UI-Mitte-Sweep. (Das G6-Paket „Doku-Refresh“ ist mit diesem
  Dokumentstand erledigt.)
- **Update-Kanal nach dem W18-Umzug:** Der EINGEBAUTE config-Pack zeigt noch
  auf das alte Repo `MedusaV9/MinecraftBubbleShieldMod` — Code-Repoint inkl.
  config-Pack-Bump 1.1.0 → 1.2.0 und PAT-Migration ausstehend
  (`docs/UPDATES.md` §1/§6a). Außerdem wurde noch NIE ein echter
  `updates`-Pack-Release gefahren (in keinem Repo) → das Update-System ist
  weiterhin nur gegen lokale/Fixture-Manifeste getestet; der erste
  Ende-zu-Ende-Release-Test steht aus.
- **iOS:** Store-/Dauer-Signing gibt es bewusst nicht (Sideload-Modell,
  7-Tage-Signatur mit freier Apple-ID); echtes iPhone-Profiling steht aus
  (User-Action: .ipa sideloaden, Rückmeldung). Der `release`-Job (Tag
  `ipa-v*`) inkl. `latest_native`-Bump ist seit W13C/W15 scharf.
- **Natives Notification-Plugin fehlt** — bei geschlossener App kommt nichts an
  (dokumentierter Andockpunkt `_os_schedule()`); ActivityKit-Live-Activity +
  Homescreen-Widget bewusst zurückgestellt (brauchen eine SIGNIERTE App).
- **Recovery-Hinweis-Toast beim Boot unverdrahtet:** String
  (`system.recovered_backup`) und Signal (`state_loaded`) existieren, aber kein
  Konsument — kein Fix-Beleg im Log bis einschließlich G7.
- **GvZ-Coop existiert nicht** (gemeinsam verteidigen): seit G5+G7 gibt es
  GvZ-**PvP** Ende-zu-Ende; Coop-Level/Session fehlen weiterhin.
- **Difficulty-Zertifizierung:** 30 von 38 Spielen bit-genau gegen die
  Web-Referenz zertifiziert (W15) — 8 fehlen.
- **Garderobe-HUD-Knopf:** Das H-Doc wollte ihn entfernen (Spiegel + Shop), W6
  hat ihn bewusst zurückgebracht — offener User-Entscheid, aktuell existieren
  BEIDE Wege (Knopf + Spiegel). Dokumentiert in GODOT-PLAN §6/H-Notiz.

## Mehrspieler + Save-Transfer — ehrlicher Ist-Stand

**Funktioniert JETZT** (Client + Server zusammen getestet; 151 Server-Tests grün
— Stand G7/P38R; Godot-Hauptsuite zuletzt 3.387 Tests grün — G5-Abnahme):

- Verbindung: HELLO/WELCOME-Handshake (TOFU), PING/PONG, automatische
  Wiederverbindung mit Backoff; Offline-Outbox (Redeem/Events/Presence/Analytics);
  Verbindungsanzeige (Online/Verbinde…/Offline-Chip).
- Freunde: Freundescode (`GOOBY-XXXX`), Einladung/Annahme, Presence-Liste.
- Besuche: Haus-Snapshot beim Gastgeber, beide Goobys sichtbar (POS-Relay 5 Hz),
  Besuch beenden/Timeout.
- GoobyPal: Münztransfer mit Tageslimit 250 (serverseitig), Pending-Zustellung
  mit Ack; die Verlaufs-Liste wird seit W13 im Client gerendert.
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
- **Post/Mail KOMPLETT (W13):** Briefe, Fotos, Item-Geschenke an Freunde,
  Quota, Offline-Outbox — plus **InstantGooby-Feed**.
- **GOB-NOM-Coop übers Netz (W15):** 2 Geräte, Lockstep mit Desync-Wächter +
  Rejoin — zugleich die Kopiervorlage für GvZ-PvP.
- **GvZ-PvP übers Netz KOMPLETT (Client G5 + Server-Modul `gvzmp.js` G7/P38R):**
  Einladung über Freunde, deterministischer Start-Handshake (Server-Seed,
  Seiten gooby/zombie), Lockstep mit `state_hash`-Fence, Peer-Down/Up mit
  Warte-Frist, idempotentes Ergebnis mit Pending-Reward bis ACK.
- Coop-Fahrt mit Radio-Sync, Besucher-schläft-auf-Couch, Snap A Gooby — alle
  seit W13.
- `ws://`-Heimnetz-Gate im Client (W13); Presence-Labels lokalisiert
  (Presence-i18n, W13); Mehrspieler-Settings (Server/Port/Secret +
  „Verbindung testen“) in den Einstellungen (W14); Account-Umzugs-Code (W13C).
- Sichtbarer Ranch-MP-Einstieg im Spiel: RmpHub (Raum anlegen/beitreten/Code
  teilen) seit G4 — vorher hatte das W15-Lockstep-Protokoll keinen Zugang.

**Fehlt noch (ehrlich):**

- GvZ-**Coop** (gemeinsam verteidigen): nur PvP existiert; Coop-Level/Session
  fehlen weiterhin.
- TOFU statt CA-Pinning (bewusster Kompromiss, dokumentiert).
- Kein öffentlicher Produktiv-Server: Betrieb weiterhin selbst hosten
  (`GOOBY-SERVER/README.md`; Port-Stolperfalle: Client-Default 8765,
  Server-Default 8080).
- Matchmaking/zufällige Gegner gibt es nicht (bewusst: nur Freunde).

## W13 + W14 — GELIEFERT (31. Juli, drei Wellen + Feedback-Runde)

**W13 A/B/C (30 Arbeitspakete, alle grün):** GvZ-Verdrahtung (Sticker/Goldi/B11),
Gooby-Suche + Interaktions-Auge, Ball-Wurf, Wetter-FX überall, Sammlungssets im
Album inkl. Award-Verdrahtung, 9 neue Speisen + Nougatschleuse, Radio-Gates,
Ranch-Level-15 + 4 Ranch-Events, Netz-Kleinpaket (GoobyPal-Verlauf, ws://-Gate,
Presence-i18n), Post/Mail-Multiplayer (Briefe/Fotos/Geschenke) + InstantGooby-Feed,
GOOBERANDO-Vollausbau mit Fahrer-Sim, City Drive als Arcade-Runde + Auto-Stats +
ctx.strike(), Reisepass 2.0 + Abflugtafel, Raumstation GOOB-1 + Urlaubs-Nutzen-Paket,
Besucher-Couch + Coop-Fahrt mit Radio-Sync, Geschichten-Stunde-Vollausbau +
Schüttel-Secret (+Geheim-Sticker), Decken-Layer + Girlanden, Sticker-Rarity-FX +
2 GvZ-Meilenstein-Sticker, Galaxie-Fell, Klopapier-Mumie, Typewriter, GOB.TY,
Goobyman-Laden, Garage + Layout-Presets, Foto-Werkzeuge + Gyro-Parallax +
Snap A Gooby, E2E-„erste Stunde"-Test + Leak-Gate (38 Spiele, 0 Orphans),
Difficulty-Zertifizierung 2→12 Spiele, ipa-Release-Job + Soft-Restart,
Panel-Ausbau (Pal-Ledger/Spiele/Ranch/Bans) + Account-Umzugs-Code, 8 neue
Rig-Clips (dance/tomato_throw/ceiling_cling/…), 5 Kauf-Bugs (Lambda-Capture)
+ DailyQuest-Claim-Bug gefixt.

**W14 (User-Feedback-Runde, 12 Pakete):** UI-Full-Rework (Web-geeichte Tokens,
AcBubble-Sprechblasen, Haptik, UiAnchors gegen Overlaps; alle Screens),
Boot-Cover-Ladebildschirm mit echtem Fortschritt, Kühlschrank 2.0 mit
Fütter-Sequenz, 120+ neue Lines + Antwort-Chips + 3 Gebrabbel-Melodien,
Decken-Fade + Stadt-Top-5-Fixes, Mehrspieler-Settings (Server/Port/Secret) +
Dev-Werkzeugkasten (6 Tabs), DLC-Hub + 2 komplette DLC-Design-Docs
(Goo und Bye, McGooby), Minigame-Qualitätspass (38er-Audit, 6 Tiefen-Polituren
— u. a. unsichtbares Ranch-Wettkampf-HUD gefunden —, 7 Quick-Wins).

Zahlen nach W14: **2.872 Haupt-Tests / 24.027 UI-Checks / 129 Server-Tests — 0 rot.**

## W15 — GELIEFERT (31. Juli/1. August, 10 Pakete)

**Updates über DIESES Repo** (User-Entscheidung; Release-API + Spieler-Token,
`latest_native`-Bump scharf im `release`-Job — das separate `gooby-updates`-Repo
entfällt endgültig), Gooby im **Urlaub besuchen** (Strand/Berge/Stadt +
Raumstation, 24 neue Urlaubs-Sprüche), Minispiel-Gruppe 2 poliert
(purblePlace-Redesign, ranchHerde-Treiben, rocketRescue-Kamera,
gardenRush-Kulisse, danceParty-Publikum, AC-Level-Menüs), 4 neue Garten-Crops →
**alle 4 Sammlungen komplettierbar**, **GOB-NOM-Coop übers Netz** (Lockstep,
Kopiervorlage für GvZ-PvP), Kamera fährt **durch die Tür** (additiver Zielraum,
RM-Fallback), **Wochenmarkt-Eigenstand** (Preis-Slider, deterministische
Verkaufs-Sim, Abrechnungs-Karte) + 3 Craft-Rezepte mit 3D-Vorschau,
danceParty-Latenz-Kalibrierung, HDR-Glow-Auto-Downgrade, GOB-NOM-Level-Editor
im Godot-Editor, neue Clips `phone_up`/`phone_tap` + Streichel-Übermut-Gag,
**30/38 Spiele bit-genau zertifiziert** (vorher 12).
Zahlen: 3.010 Haupt-Tests / 24.815 UI-Checks / 140 Server-Tests — 0 rot.

## W16 — Repo-Umzug #1 + Wellen G1–G3 (1. August)

**Umzug:** von `MedusaV9/CustomServerPrivate` (Branch
`cursor/gooby-godot-rewrite-d1d8`) nach `MedusaV9/MinecraftBubbleShieldMod`
(Branch `cursor/gooby-godot-loop-2c10`), voller Verlauf; Update-Kanal-Repoint
im Code (config-Pack 1.0.0 → 1.1.0) + PAT-Migrations-Doku.
**G1 (Analyse):** 28 Scout-Berichte. **G2 (13 Pakete, 3.024 Tests):**
UI-Fundament „Inhaltsspalte“, Szenenwechsel-Karte + Blütenblätter-Wipe im
Alt-Web-Look, Arcade-Cover der 5 Ranch-Wettbewerbe, 5 Minispiel-Polituren
(starHopper, trampoline, hideSeek, cityDrive, Ranch-Arena), Boot ~55 ms
schneller mit echtem Fortschritt, 11 Prozess-/Robustheits-Fixe,
Save-Backup-Datenverlust-Fenster geschlossen. **G3 (12 Pakete, 3.078 Tests):**
Inhaltsspalte in die Fläche (Arcade, IKEA, Garderobe/Gestalten, Album),
Knopfleisten für 12 Stadt-Orte, Sozial + Post fühlbar (Squish/Sound/Haptik),
137 Text-Feinschliffe, Haptik-Stärken wirken echt, carrotGuard-Politur,
**Server-CI `gooby-server.yml`**, Trailer-Vorarbeiten (Storyboard v4).

## W17 — Wellen G4–G7 (1.–2. August)

**G4 (18 Pakete, 3.235 Tests, UI-Audit 21 Screens × 4 Formate = 0 Befunde):**
UI-Rework in der Fläche — Bau-Dock unten-mittig, IGohbie-Telefon skaliert,
Reise-Strecke (FlapBoard/Reise-App/Bordkarte), Radio/Kino/GOB.TY/Geschichten
fingergroß, **sichtbarer Ranch-MP-Einstieg (RmpHub)**, Level-Selects +
Brettspiel-Overlays, Boot-Möhren-Pill + Papier-Ladekarte im Alt-Web-Look,
Onboarding/Quests/Feiern, 7 Minispiel-Polituren, zentraler Punkte-Anker-Fix,
Test-Runner-Härtung.
**G5 (13 Pakete, 3.387 Tests, String-Parität 25.962 Checks):** **DLC „Goo und
Bye“ Welle A SPIELBAR** (DLC-Hub ab Level 12, kompletter Tag-Loop), **DLC
„McGooby“ Probeschicht**, GvZ-PvP-**Client** (Lockstep), **Trailer 5.1** (62 s,
alle 34 Clips neu), 11 Minispiel-Polituren, Freunde-App im Telefon, UI-Wache
auf 34 Screens ausgedehnt (Alt-Screens 0 Befunde; dickster Fang: Home-HUD über
dem Bau-Dock, 97 Befunde → G7-P50-Wurzelfix).
**G6: durch VM-Neustart VERLOREN,** bevor integriert/committet war —
transparent dokumentiert, die 13 Pakete sind neu einsortiert (kein gelandeter
Stand verloren).
**G7 „Spielgefühl“ (P50–P58 + P38R) — GELANDET:** HUD-Dynamik (P50: HUD gleitet
im Baumodus animiert weg, weicht bei offenen Blättern, Label-Fit),
Sprechblasen-/Text-Fit-Wurzelfix (P51), IGohbie-Telefon-Rework (P52),
einheitliches Sheet-System mit Runterwisch-Geste (P53), Garderobe + Gestalten
(P54), **Läden lebendig Teil 1** (P55: `ort_leben`-Ambient — REHWEI, Baumarkt,
IKEA-Schaufenster), **Ein-Spiel-Gefühl-Rahmen** für alle 38 Spiele (P56),
**iPhone-17-Pro-Max-Leitformat 2868×1320 quer** + Audit-Altbefunde 114 → 23
(P57), **Playtest-Harness „Subagents spielen das Spiel“** + Pionier-Lauf (P58,
`tools/ci/run_playtest.sh`) — der Pionier fand einen ECHTEN Blocker
(Arcade-Zurück startete eine frische Minispiel-Runde inkl. Belohnungs-Farm),
Wurzelfix im Router gelandet (flüchtige Ziele; Playtest `flow_arcade` 27/27).
**P38R:** `gvzmp.js`-Server-Modul — GvZ-PvP läuft Ende-zu-Ende (Server 151/0).
**Ehrlich offen nach G7:** integrierte Voll-Lauf-Abnahme + die P57/P58-Reste
(s. „Bekannte Lücken“).

## W18 — Repo-Umzug #2 (2. August)

Von `MedusaV9/MinecraftBubbleShieldMod` nach **`MedusaV9/ModdingWebseite`**
(Branch `cursor/bubble-shield-loop`), voller Verlauf übernommen. CI/Actions
laufen unverändert im neuen Repo (gleicher Workflow, gleiches Artefakt);
`main` dort ist ein ANDERES Projekt (BAPBAP-Modding-Website) — nicht anfassen.
Offen aus dem Umzug: Update-Kanal-Code-Repoint (config-Pack → 1.2.0) +
PAT-Migration (`docs/UPDATES.md` §1/§6a).

## Backlog (Kurzfassung; vollständig + bindend in GODOT-PLAN §6)

Real noch offen nach dem G7-Log-Abgleich (2. August; Erledigtes ist in
GODOT-PLAN §6 mit ✅ annotiert):

- **Direkt vor der Tür (UserFeedback „In Arbeit“):** Welle H Playtest ×10
  (das P58-Werkzeug steht bereit), Welle I 30+-Ideen-Planner, Wellen J+
  Umsetzung — inkl. der neu einsortierten G6-Pakete (DLC Welle B beider
  Läden, Ball-Wurf-Paket, DLC-Ladebildschirme, Audio-Feel, B11 + Warn-Sweep,
  McGooby-Bühne, Alwin-NPC, UI-Mitte-Sweep).
- **UI:** P57-Audit-Rest (23 Befunde), P58-Playtest-Befunde (Overlay-Stau nach
  Onboarding, Teestube-Streifen, Bau-Ghost, Onboarding-Karten-Versatz).
- **Updates:** W18-Code-Repoint + config-Pack 1.2.0, erster echter Pack-Release
  im neuen Repo (Ende-zu-Ende-Release-Test steht seit je aus). M3:
  Manifest-RSA-Signierung, Mirror #2 über den Node-Server.
- **A Engine:** echtes iPhone-Profiling (User-Action), LightmapGI-Option,
  DOOR_TRAVEL-CamPath-Polish. M3: Shader-Warmup-Quad, Ragdoll-Experiment.
- **C Backend:** natives Notification-Plugin, GvZ-Coop (nur PvP existiert),
  Recovery-Hinweis-Toast verdrahten. M3: Taxi-Live-Activity (Signing),
  Companion-App-Modus.
- **D Haus (M3):** Keller/Etage/Balkon.
- **E Stadt:** Stadt-Polish-Reste (Near-Miss-Funken, Ziel-GPS-Pfeil). M3:
  Ambient-Audio-Distrikte, Traffic-Vollausbau.
- **F Gooby (M3):** Laufband-Gag, GOBBULL-Zocken, P2-Clips,
  PhysicalBone-Ragdoll.
- **G Minigames:** Difficulty-Zertifizierung 30/38 → die restlichen 8. M3:
  HDR-Glow-Telemetrie.
- **H UI/Content:** Garderobe-HUD-Knopf-Entscheid (User; beide Wege existieren).
- **Signing-gebunden (bewusst zurückgestellt):** ActivityKit-Live-Activity,
  iOS-Homescreen-Widget.
