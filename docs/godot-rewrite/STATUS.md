# STATUS — GOOBY-Godot-Rewrite (ehrlicher Ist-Stand)

Stand: Ende Welle W4/Polish (M1-Session). Quellen: `GODOT-PLAN.md` (bindend),
Handoffs unter `/tmp/gooby-godot/handoffs/`, Test-Runner-Ausgaben.
Dieses Dokument sagt ehrlich, **was fertig ist (M1)** und **was Backlog ist (M2/M3)** —
die vollständige, nichts-verlierende Backlog-Liste steht in `GODOT-PLAN.md` §6.

## M1 — fertig (spielbarer Kern, diese Session)

| Bereich | Geliefert | Ehrliche Anmerkung |
|---|---|---|
| Fundament (W1a) | Bootfähiges Godot-4.4.1-Projekt, SceneRouter (EIN Transition-System), OrientationService, Test-Runner + W1c-UI-Runner, CI `gooby-godot.yml` (Import→Tests→Lint→Boot-Smoke) | iOS-Job im CI ist bewusst deaktiviertes Skeleton (`if: false`) |
| Gooby (W1b) | Blender-Pipeline → `gooby.glb` (Rig, Clips, Morphs), Runtime-Rig + Gebrabbel-Stimme (gebackene Silben-WAVs), Charakter-Editor-Morphs | P1/P2-Zusatz-Clips (dance, ragdoll …) sind Backlog F §1.4 |
| UI-Kit (W1c) | AC-Theme 2.0 aus Tokens (`themes/`), HUD in beiden Orientierungen, Onboarding (DE, knuffig), Settings, Toasts/Sheets/Bubbles, Strings-System (DE führend, EN-Parität testgetrieben) | — |
| State (W1d) | Save v5 (atomar, 3 Backup-Generationen, Korruptions-Recovery), Migrationskette Web v0–v4→v5 mit echten Fixtures, Umzugskoffer-Import (`GOOBY5.…`-Codec), Kern-Logik-Ports (Economy, Stats, Leveling …) | iOS-NSUserDefaults-Legacy-Reader ist dokumentierter Stub (Backlog H §5.3); Recovery-Hinweis-Toast beim Boot: Strings (`sys.save.*`) + Verdrahtungs-Schnipsel liegen bereit (W4P4-Handoff), Einbau gehört dem Boot-Owner |
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
- **iOS-Legacy-Save-Reader + Notification-Plugin sind Stubs** mit dokumentiertem Goldweg
  (Umzugskoffer-Import funktioniert immer als Fallback).
- **Presence-Labels kommen DE-only vom Server** (presence.js-Templates); EN-Client zeigt
  deutsche Aktivitätstexte.

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
  Rarity-Effekten, Cosmetics 2.0, Radio 2.0, GOB.TY, Girlanden, Goobyman-Laden,
  natives Legacy-Reader-Plugin. M3: bplist-Fallback.
- **Prozess:** regelmäßige IPA-Builds nach scharfem ipa-Workflow; Blockbench nur bei Bedarf.
