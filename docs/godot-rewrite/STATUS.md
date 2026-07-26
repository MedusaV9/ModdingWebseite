# STATUS — GOOBY-Godot-Rewrite (ehrlicher Ist-Stand)

Stand: nach W4/Polish + Mega-Eval (15 Blickwinkel) + 2 Fix-Wellen (8 Agents) + W5/GOB-NOM.
Quellen: `GODOT-PLAN.md` (bindend), Eval-Berichte `E1..E15-*.md`, Test-Runner-Ausgaben.
Dieses Dokument sagt ehrlich, **was fertig ist (M1)** und **was Backlog ist (M2/M3)** —
die vollständige, nichts-verlierende Backlog-Liste steht in `GODOT-PLAN.md` §6.

## Mega-Eval + Fix (abgeschlossen)

15 Eval-Agents (5 Fable Max + 5 Opus Max + 5 Sol Max) haben Boot/Onboarding, Migration,
CI, Performance, Orientierung, Deutsch, Theme, Charakter, Baumodus, Fairness, GvZ-Kurve,
Update-System, Server, Offline-first und Architektur geprüft (Berichte `docs/godot-rewrite/E*.md`).
Die adversarialen Security-Blickwinkel (E12/E13) liefen als reine funktionale Robustheits-Reviews.
Alle gefundenen **P0** und **P1** wurden in 8 Fix-Agents behoben, u. a.:

- **P0 Theme-Zustellung:** Projekt-Default-Theme (`gui/theme/custom`) → AC-Look erreicht jetzt
  Controls unter CanvasLayer UND SubViewport (vorher „alles grau"); + fehlende Button-Variationen,
  AcCardButton (Arcade-Kacheln waren Ellipsen), Boot-Platzhalter entfernt.
- **P0 MinigameHost 0×0** → Host/SubViewport füllen den Viewport (Minigames waren über den Router
  unspielbar); gleicher Anchor-Bug in gvz/gobnom-Level-Select mitgefixt.
- **P0 Migration `String==bool`-Crash** → typsichere Koerzierung; `load_state` bootet jetzt bei
  jedem kaputten v4-Save sauber (Recovery statt Crash), vergessene Slices ergänzt.
- **P1** HUD-Hochkant-Bogen, HUD-über-Screens ausblenden, Baumodus (Wandmöbel entfernbar,
  Surface-Reihenfolge, Höhenclamp), GvZ-Monotonie easy/normal/hard, Energie-Gate + Coin-Cap,
  Rig-Emotionen (sichtbare Silhouetten) + Morph-Mapping + Squeeze, DE-Text + veil/Dialog-i18n,
  Offline-Wiring (Analytics ab t=0, Redeem/Events/Presence-Outbox, Visit-Timeout) + Server-Durability.

## W5 — GOB NOM (neu, explizit gefordert)

Cut-the-Rope-Pendant mit Verlet-Seilphysik, 15 Kampagnen- + 10 Coop-Level (alle per Auto-Solver
als lösbar bewiesen), Nutella-Gläser als Sterne. Zusammen mit Goobys-vs-Zombies (W3b) sind damit
**beide** vom User explizit gewünschten neuen Minispiele fertig + im Arcade-Grid.

## M1 — fertig (spielbarer Kern, diese Session)

| Bereich | Geliefert | Ehrliche Anmerkung |
|---|---|---|
| Fundament (W1a) | Bootfähiges Godot-4.4.1-Projekt, SceneRouter (EIN Transition-System), OrientationService, Test-Runner + W1c-UI-Runner, CI `gooby-godot.yml` (Import→Tests→Lint→Boot-Smoke) | iOS-Job im CI ist bewusst deaktiviertes Skeleton (`if: false`) |
| Gooby (W1b) | Blender-Pipeline → `gooby.glb` (Rig, Clips, Morphs), Runtime-Rig + Gebrabbel-Stimme (gebackene Silben-WAVs), Charakter-Editor-Morphs | P1/P2-Zusatz-Clips (dance, ragdoll …) sind Backlog F §1.4 |
| UI-Kit (W1c) | AC-Theme 2.0 aus Tokens (`themes/`), HUD in beiden Orientierungen, Onboarding (DE, knuffig), Settings, Toasts/Sheets/Bubbles, Strings-System (DE führend, EN-Parität testgetrieben) | — |
| State (W1d) | Save v5 (atomar, 3 Backup-Generationen, Korruptions-Recovery), Migrationskette Web v0–v4→v5 mit echten Fixtures, Umzugskoffer-Import (`GOOBY5.…`-Codec), Kern-Logik-Ports (Economy, Stats, Leveling …) | iOS-NSUserDefaults-Legacy-Reader ist seit FIX-6 KEIN Stub mehr (GDScript-bplist-Parser, ohne Plugin — `docs/godot-rewrite/SAVE-TRANSFER.md`); Recovery-Hinweis-Toast beim Boot: Strings (`sys.save.*`) + Verdrahtungs-Schnipsel liegen bereit (W4P4-Handoff), Einbau gehört dem Boot-Owner |
| Haus (W2a) | 5 Raum-Szenen, Tür-Übergang mit Steckenbleib-Gag, Grid-Baumodus (Boden-Layer) + Lager 100, Möbelkatalog, Navigation/Wandern | Wand-/Decken-Layer, Werkstatt, Garten 2.0 = Backlog D |
| Updates (W2b) | PackLoader + Boot-Guard (2-Crash-Regel), ContentRegistry-Merge, Update-UI in den Settings, Pack-CI (`gooby-packs.yml`), Handbuch `docs/UPDATES.md`, 7 Pack-Quellordner unter `content/` | Öffentliches Artefakt-Repo `gooby-updates` + Token = **User-Action**, bis dahin kein Ende-zu-Ende-Release-Test (B §3/§5) |
| Server (W2c) | `GOOBY-SERVER/`: express+ws, ein Port, JSON-Storage, HELLO/WELCOME/TOFU, Freunde+Presence, GoobyPal (250/Tag), Codes, Events, Analytics, Webpanel (fail-closed), AMP-Anleitung im README | Post/Mail, InstantGooby, Schach = Backlog C |
| Netz + Minigames (W2d) | NetClient offline-first (Outbox, Backoff), Freunde-Screen, Minigame-Framework (Host/Pregame/Results/JuiceKit, GoobyRng bit-identisch zum Web) + `teaParty` + `carrotCatch` mit Bot-Zertifizierung | — |
| Stadt (W3a) | 15×12-Stadt, freie Fahrt (car_feel zahlengleich), Reise-Cutscenes, Taxi-Warte-Statemaschine, Urlaubs-Port (Postkarten, Souvenir-Münzen), Flughafen-Buchung | Orte-Interieurs, Dialog-System, GOOBERANDO-Vollausbau, IGohbie-Apps = Backlog E; Notification-Planung nutzt Plugin-Stub (C §8) |
| GvZ (W3b) | Goobys vs. Zombies: deterministische 20-Hz-Logik, 15-Level-Kampagne, 12 Türme + Goldi (Code-Gate), Boss Knurps, Balance als Pack-JSON, Level-Select mit Sternen | PvP/Coop = Backlog (Daten liegen als `pvp.json` bereit) |
| Besuche (W3c) | Haus-Snapshot-Sync, Besuch mit 2 sichtbaren Goobys (POS-Relay 5 Hz), Schiffe versenken komplett (Emotes + Tomate 1×/Runde), GoobyPal-UI | Zweites Brettspiel (Schach) = Backlog C §3.5 |
| Content (W3d) | 6 Random-Events mit Timern, Sticker-System (105 Sticker inkl. germanisierte Bestands-IDs), Interactables (Lampe, Bad-Suite, Spiegel, Zähneputzen), 5.0-News-Panel | Restliche Events (robo_jagd …) + Sticker-Sets bis 126+1 = Backlog F/H |
| Polish (W4) | Parallel-Agents: Juice/SFX, Veil/HUD/Onboarding, Stadt/Haus-Ambiente, **Texte/Fehlerpfade/READMEs/Freunde-UI (dieses Dokument)**, Test-Infra | Mega-Eval (15 Blickwinkel) + Fix-Welle laut Plan §2.4 Phase 2/3 |

Querschnitt: beide Test-Runner grün (Haupt-Runner 400+ Tests, W1c-UI-Runner ~2600 Checks),
gdlint/gdformat sauber, alles headless reproduzierbar. Arcade zeigt `gobnom` als
ehrlichen „Bald!“-Platzhalter (Cover da, Spiel = Backlog G §5).

## Bekannte M1-Lücken (nicht verschweigen)

- **Kein lauffähiger iOS-Build**: `ios`-Export-Preset + CI-Skeleton existieren,
  Signing/Templates/Gerätetest fehlen → Backlog B §5.2 (Details: `GOOBY-GODOT/README.md`).
- **`gooby-updates`-Release-Repo fehlt** (User-Action) → Update-System ist nur gegen
  lokale/Fixture-Manifeste getestet.
- **Notification-Plugin ist ein Stub** mit dokumentiertem Goldweg. Der
  iOS-Legacy-Save-Reader ist seit FIX-6 implementiert (bplist-Parser ohne Plugin);
  der Auto-Import-Aufruf beim ALLERERSTEN Start wartet noch auf den Boot-Owner
  (Handoff `FIX6-boot-request.md`) — bis dahin: Einstellungen → „Spielstand übertragen".
- **Presence-Labels kommen DE-only vom Server** (presence.js-Templates); EN-Client zeigt
  deutsche Aktivitätstexte.

## Mehrspieler + Save-Transfer — ehrlicher Ist-Stand (FIX-6)

**Funktioniert JETZT (Client+Server zusammen getestet: Haupt-Runner-Integrationstest
gegen echten `GOOBY-SERVER` + Zwei-Client-Node-Smoke, Logs in
`/tmp/gooby-godot/artifacts/FIX6/`):**

- Verbindung: HELLO/WELCOME-Handshake (TOFU), PING/PONG, **automatische
  Wiederverbindung mit Backoff**; Offline-Outbox für Redeem/Events/Presence.
- **Verbindungsanzeige** (Online/Verbinde…/Offline-Chip) in Battleship- und
  Besuchs-Szene (`scripts/net/net_status_indicator.gd`).
- Freunde: **Freundescode** (`GOOBY-XXXX`), Einladung/Annahme, Presence-Liste.
- Besuche: Haus-Snapshot beim Gastgeber laden, **beide Goobys sichtbar**
  (POS-Relay 5 Hz), Besuch beenden/Timeout.
- GoobyPal: Münztransfer mit **Tageslimit 250** (serverseitig), Verlauf,
  PAL_RECEIVED-Zustellung mit Ack.
- **Schiffe versenken KOMPLETT**: Vollpartie (Turn-Relay, Treffer/Versenkt,
  Emotes, Tomate 1×/Runde), **Aufgeben** (Bestätigungsdialog), **Revanche**
  (beidseitige Zusage, Rollentausch, Ablehnungs-Push), **Verbindungsabbruch-
  Behandlung**: 120-s-Rejoin-Fenster, Gegner sieht BOARD_PEER_DOWN/UP, Client
  rejoint automatisch (BOARD_RESUME mit History-Replay), bewusstes Verlassen
  → sofortiger Forfeit-Sieg.
- Server-Tests: 82 Node-Tests grün; Godot-Haupt-Runner 1179 Tests grün.

**Fehlt noch (ehrlich):**

- Settings-Zeile zum Transfer-Screen + Auto-Import-Hook beim ersten Start
  (Handoffs an FIX-1/Boot-Owner liegen: `FIX6-settings-request.md`,
  `FIX6-boot-request.md`) — der Screen selbst ist fertig (`state/transfer`).
- Zweites Brettspiel (Schach) = Backlog C §3.5; Post/Mail, InstantGooby.
- Presence-Labels kommen DE-only vom Server (EN-Client zeigt deutsche Texte).
- Kein öffentlicher Produktiv-Server: Betrieb weiterhin selbst hosten
  (`GOOBY-SERVER/README.md`), TOFU statt CA-Pinning.
- Matchmaking/zufällige Gegner gibt es nicht (bewusst: nur Freunde).

## M2/M3 — Backlog (Kurzfassung; vollständig + bindend in GODOT-PLAN §6)

- **A Engine:** DOOR_TRAVEL additiv, Rückblick 2.0, ~23 restliche System-Ports,
  iPhone-Profiling. M3: Shader-Warmup, Ragdoll-Experiment.
- **B Updates:** `gooby-updates`-Repo + Ende-zu-Ende-Release, ipa-Workflow scharf,
  Soft-Restart-UX. M3: Manifest-Signierung, Mirror #2.
- **C Backend:** Post/Mail + InstantGooby, Schach, Snap A Gooby, natives
  Notification-Plugin, GoobyPal-App-UI. M3: Coop-Fahrt, Koop-Minigames-Relay,
  Taxi-Live-Activity, Account-Umzug.
- **D Haus:** Wand-/Decken-Layer, Fenster-Diorama, Werkstatt + Crafting, Goobay,
  Garten 2.0, Wochenmarkt, Baumarkt. M3: Keller/Etage/Balkon, Garage/Autohaus, IKEA-Großladen.
- **E Stadt:** Orte-Interieurs, Dialog-System, GOOBERANDO komplett, IGohbie-Apps,
  Minimap, Guber, Fußgänger + Tag/Nacht. M3: Ambient-Distrikte, Traffic-Vollausbau.
- **F Gooby:** 7 restliche Random-Events, Idle-Wandern + „Wo ist mein Gooby?“,
  Schüttel-Secret, Boden-ist-Lava, Geschichten-Stunde, P1-Clips. M3: Laufband-Gag,
  GOBBULL-Zocken, P2-Clips.
- **G Minigames:** 28 restliche Ports, GOB NOM komplett (+Editor),
  Difficulty-Zertifizierung aller Ports, Endless-Vollausbau. M3: HDR-Glow-Telemetrie,
  danceParty-Latenz-Kalibrierung.
- **H UI/Content:** Profil-Tab, Reisepass 2.0, Abflugtafel, Sticker bis 126+1 mit
  Rarity-Effekten, Cosmetics 2.0, Radio 2.0, GOB.TY, Girlanden, Goobyman-Laden.
  (Legacy-Reader: bplist-Fallback ist seit FIX-6 GEBAUT; das native Plugin ist
  nur noch optionale Kür.)
- **Prozess:** regelmäßige IPA-Builds nach scharfem ipa-Workflow; Blockbench nur bei Bedarf.
