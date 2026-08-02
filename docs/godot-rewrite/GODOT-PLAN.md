# GODOT-PLAN.md — VERBINDLICHER Plan für den GOOBY-Godot-Rewrite

Chefarchitekt-Dokument. Quellen (bindend): `/tmp/gooby-godot/USER-WISHES.md` +
`/tmp/gooby-godot/ideas/{A-engine,B-updates,C-backend,D-house,E-city,F-gooby,G-minigames,H-ui-content}.md`.
Umgebung verifiziert: Godot **4.4.1.stable** (`godot`), Blender **4.0.2** (`blender`), Node **22.14**,
Branch `cursor/gooby-godot-rewrite-d1d8` (historisch — das Projekt ist seither zweimal umgezogen
und lebt seit W18 in `MedusaV9/ModdingWebseite` auf `cursor/bubble-shield-loop`, s. AGENTS.md),
Web-Referenz `/workspace/GOOBY` (bleibt unangetastet als Lesequelle),
`/workspace/GOOBY-GODOT/project.godot` existiert als leerer Bootstrap, `/workspace/GOOBY-SERVER` wird neu angelegt.

---

## 1) Meilenstein-Ehrlichkeit (keine Kalenderzeit — Wellen/Dateien/LOC)

Der Gesamtscope der 8 Design-Docs summiert sich auf **~450 Dateien / ~100 000 LOC**
(A ~170 Dateien/31k inkl. Voll-Port aller Logiken · B ~16/1,9k · C ~50/11k · D ~72/16k ·
E ~78/10k · F ~56/8k · G ~189/38k · H ~64/6,5k, mit Überschneidungen konsolidiert).
Das ist NICHT in einer Session lieferbar. Deshalb:

- **M1 = DIESE SESSION** (Wellen W1–W4): Fundament + Kern-Features, spielbarer Kern.
  Ziel-Scope M1: **~360 Dateien / ~60 000 LOC** + Assets (GLB/WAV/PNG).
  - W1 Fundament: ~90 Dateien / ~15k LOC
  - W2 Systeme: ~120 Dateien / ~22k LOC
  - W3 Content: ~110 Dateien / ~20k LOC
  - W4 Polish/Eval/Fix: ~40 Dateien / ~5k LOC (Deltas)
- **M2/M3 = präziser Backlog** (§6): ALLE übrigen User-Wünsche, nichts geht verloren.
  Rest-Scope ~90–120 Dateien / ~40 000 LOC, jeweils mit Doc-Verweis.

Meilensteine werden ausschließlich in **Wellen, Dateien, LOC und Acceptance-Kriterien**
gemessen — niemals in Tagen/Wochen.

---

## 2) Session-Wellen W1–W4

Regeln für ALLE Wellen:
- Pro Welle 4–5 parallele Agents mit **strikt disjunkter File-Ownership** (Owned-Files
  unten sind exklusiv; wer fremde Dateien braucht → Handoff-Request, §3).
- Modelle: nur Fable 5 Max Thinking (zusätzlich erlaubt: Opus 5 Max Thinking fast) —
  Prozess-Anforderung des Users.
- Jeder Agent: liest die für ihn relevanten Design-Docs KOMPLETT, liest alle Handoffs
  der Vorwellen, schreibt am Ende genau einen Handoff (§3.3).
- Commit-Konvention: `GODOT W<n>/<TAG>: <präzise Beschreibung>` — mehrere logische
  Commits pro Agent erlaubt/erwünscht, immer mit Welle+Tag.
- Alle Acceptance-Kriterien sind **headless testbar** (`godot --headless`), UI-Szenen
  über Instanziierungs-Smoke-Tests (Szene laden, instanzieren, Node-Pfade asserten,
  keine Script-Errors) — Muster liefert W1a im Test-Runner.

### 2.1 W1 — Fundament (4 Agents)

#### W1a `CORE` — Projekt-Core, Router, Test-Runner, CI
- **Ziel:** Bootfähiges Godot-Projekt mit der A-§1-Architektur; ein Transition-System
  statt zwei (Web-Bug!); Test- & CI-Fundament, auf dem alle anderen bauen.
- **Owned-Files (exklusiv):**
  - `GOOBY-GODOT/project.godot` (EINZIGER Schreiber in W1; registriert ALLE in diesem
    Plan fixierten Autoload-Pfade vorab, auch die von W1b/c/d — Pfad-Kontrakt s. u.)
  - `GOOBY-GODOT/autoload/event_bus.gd`, `scene_router.gd`, `loading_veil.tscn/.gd`,
    `orientation_service.gd`, `settings.gd`, `app_config.gd` (Stub für §B),
    `audio_director.gd` (Gerüst)
  - `GOOBY-GODOT/main/main.tscn/.gd` (World/UILayer/PopupLayer/Vignette-Layer, A §1.3/§6)
  - `GOOBY-GODOT/components/ui/safe_area_container.gd`
  - `GOOBY-GODOT/gfx/env_home.tres`, `env_garden.tres`, `env_minigame_punchy.tres` (A §6)
  - `GOOBY-GODOT/tests/run_tests.gd`, `tests/test_case.gd`, `tests/test_router.gd`,
    `tests/test_orientation.gd`, `tests/scene_smoke.gd` (Instanziierungs-Helfer)
  - `.github/workflows/godot-ci.yml` (Import + Tests + gdlint/gdformat + Linux-Smoke
    `godot --headless --quit`), `.github/workflows/ios-ipa.yml` (**Skeleton**:
    macos-Runner, Godot 4.4.1 + Export-Templates cachen, unsigned-ipa-Export-Schritte
    als dokumentiertes Gerüst — läuft erst, wenn Export-Preset existiert; Backlog B§5.2)
  - `tools/ci/install_godot.sh`, `.gdlintrc` + `gdformatrc`-Äquivalent (gdtoolkit-Config)
  - `GOOBY-GODOT/.gitattributes`/`.gitignore` (Godot-spezifisch: `.godot/` ignoriert)
- **Entscheidungen (bindend):** Renderer `mobile`; Stretch `canvas_items`/`expand`,
  Basis 1280×720 landscape; Orientation `sensor`; Lint = **gdtoolkit via `pip install
  "gdtoolkit==4.*"`** (gdlint + gdformat — es gibt kein natives Godot-Lint);
  Test-Runner = eigener Mini-Runner (A §9), KEIN Addon; CI macht ZWINGEND
  `godot --headless --import` vor Tests.
- **Autoload-Pfad-Kontrakt** (W1a registriert, Owner liefert Datei):
  `EventBus, AppConfig, SaveManager*, GameState*, AudioDirector, OrientationService,
  Settings, SceneRouter` (* = Datei von W1d bei `autoload/save_manager.gd`,
  `autoload/game_state.gd`). W1a legt für fremde Autoloads minimale, von den Ownern
  ERSETZBARE Platzhalter NICHT an — stattdessen: Registrierung + Wave-Ende-Integration;
  W1a-Tests dürfen nicht auf fremde Autoloads angewiesen sein.
- **Acceptance (headless):**
  1. `godot --headless --import` Exit 0, keine Fehlerzeilen.
  2. `godot --headless --script res://tests/run_tests.gd` grün; darin: Router-Statemaschine
     `IDLE→COVER→SWAP→WAIT_READY→REVEAL→IDLE` als Unit-Test (Fake-Szenen), Replace-Queue
     (nur letzte Anfrage), 8-s-Force-Reveal-Timeout; OrientationService-Klassifikation
     für 6 Auflösungen.
  3. `gdlint`/`gdformat --check` sauber auf allen Owned-Files.
  4. CI-Workflow-YAML valide (lokal `act`-frei: YAML-Parse-Test genügt) + Push → CI grün.
- **Commits:** `GODOT W1/CORE: ...`

#### W1b `GOOBY` — Charakter-Pipeline, GLB, AnimationTree, Stimme, Morphs
- **Ziel:** Der neue Gooby aus Doc F §1: deterministisches Blender-Skript → GLB mit
  Rig + Clips; Godot-Runtime mit AnimationTree, Face-/Look-/Jiggle-Layern, Gebrabbel.
- **Owned-Files:**
  - `tools/blender/gooby_build/` (build_gooby.py, gooby_params.py, mesh.py, rig.py,
    shapekeys.py, anims.py, materials.py, export.py, preview.py)
  - `tools/voice/bake_syllables.py` (numpy-WAVs, ~14 Silben + One-Shots, F §1.6)
  - `GOOBY-GODOT/assets/gooby/` (gooby.glb, Palette-PNG, `voice/*.wav`)
  - `GOOBY-GODOT/gooby/` (gooby.tscn, gooby.gd, gooby_face.gd, gooby_look.gd,
    gooby_jiggle.gd, gooby_voice.gd, gooby_customizer.gd, gooby_locomotion.gd)
  - `GOOBY-GODOT/tests/test_gooby_pipeline.gd`, `tests/test_gooby_voice.gd`,
    `tests/test_gooby_customizer.gd`
- **M1-Clip-Liste (bindend):** `idle, walk, hop, sit, sleep, wave, door_squeeze
  ("squeeze"), toothbrush ("brush"), hammer_build ("build")` + `run, wake_up, eat,
  sad_slump, happy_bounce` (P0-Rest aus F §1.4, wenn ohne Mehrrisiko machbar).
  Shape Keys ≤ 24 inkl. `body_squeeze_door`, Editor-Morphs `eyes_apart/eyes_together`,
  `head_chubby`; Ohr-/Augen-Größe via Bone-Scale. SpringBones auf Ohren+Tail.
- **Acceptance (headless):**
  1. `blender --background --python tools/blender/gooby_build/build_gooby.py` läuft
     ohne Fehler, erzeugt GLB < 8 000 Tris (Skript printet Tri-Count, Test prüft Datei).
  2. `godot --headless --import` importiert das GLB fehlerfrei; Test lädt `gooby.tscn`,
     assertet: AnimationPlayer enthält alle M1-Clips (Namen), Blendshape-Liste enthält
     die Pflicht-Morphs, `gooby.gd.play("wave")` liefert Signal.
  3. `bake_syllables.py` erzeugt alle WAVs; Test prüft Existenz + Sample-Rate 44100.
  4. Preview-PNGs (Turntable + 1/Clip) unter `/tmp/gooby_previews/` erzeugt (Review-Artefakte).
  5. gdlint/gdformat sauber.
- **Commits:** `GODOT W1/GOOBY: ...`

#### W1c `UIKIT` — Theme AC 2.0, HUD, Onboarding, Settings
- **Ziel:** Doc H §1/§2.3: Theme-Ressource aus Tokens, Drift-Wallpaper-Shader, HUD in
  BEIDEN Orientierungen (P1 „Daumen-Bogen“ / L1 „Cockpit“), Panels/Toasts/Sheets,
  Onboarding (DEUTSCH, knuffig, F §2.2 — OHNE Bett-Schritt, Extension-Point für W2a),
  Settings-Screen.
- **Owned-Files:**
  - `GOOBY-GODOT/theme/` (tokens.gd, theme_builder.gd, ac_theme.tres, fonts/Baloo2*.ttf,
    squish_button.gd, ac_card/ac_chip/ac_tabs/ac_stamp/ac_ribbon/ac_empty_state-Szenen)
  - `GOOBY-GODOT/shaders/pattern_drift.gdshader`, `GOOBY-GODOT/ui/components/ac_backdrop.tscn`
  - `GOOBY-GODOT/ui/hud/` (hud_layout.gd, Status-Kapsel, Daumen-Bogen, Cockpit,
    Interaktions-Auge-Button als Stub-Signal, „Wo ist mein Gooby?“-Chip als Stub)
  - `GOOBY-GODOT/ui/components/` (toast.tscn, bottom_sheet.tscn, confirm_dialog.tscn,
    page_indicator.tscn)
  - `GOOBY-GODOT/ui/onboarding/` (Flow: Aufwachen→Name→Spitzname→Spiegel/Char-Editor;
    definierter Extension-Point `onboarding_flow.gd::register_final_step(Callable)` für
    W2a-Bett-Schritt)
  - `GOOBY-GODOT/ui/settings/settings_screen.tscn/.gd` (inkl. **„Suche nach Updates“-
    Platzhalter-Button** (disabled + Tooltip, W2b ersetzt), Tür-Animations-Toggle,
    globale Minigame-Orientierung, Reduced Motion, Lautstärken, Sprache fest DE)
  - `GOOBY-GODOT/strings/de/ui.json`, `strings/de/onboarding.json`
  - `GOOBY-GODOT/tests/test_theme_tokens.gd`, `tests/test_hud_layout.gd`,
    `tests/test_onboarding_flow.gd`
- **Acceptance (headless):**
  1. Theme-Builder erzeugt `.tres`; Test assertet Token-Werte (Farben exakt aus H §1.1).
  2. HUD-Szene instanziert headless; `apply_layout(PORTRAIT)`/`(LANDSCAPE)` verschiebt
     die 5 Hauptbuttons in die korrekten Container (Node-Pfad-Asserts).
  3. Onboarding-Statemaschine als Unit-Test: Name Pflicht, Spitzname Default „Gooby“,
     Editor überspringbar, Abschluss-Signal mit Profil-Dict `{player_name, gooby_nickname,
     editor:{eyes_apart, eye_scale, ear_len, chubby}}`.
  4. Alle DE-Strings kommen aus `strings/de/*.json` (Test: kein hartkodierter UI-String
     in .gd der Owned-Files — Grep-Test auf Umlaut-Literale).
  5. gdlint/gdformat sauber; Import fehlerfrei.
- **Commits:** `GODOT W1/UIKIT: ...`

#### W1d `STATE` — GameState, Save v5, Migration v4→v5, System-Ports
- **Ziel:** Doc H §5 komplett (ohne natives iOS-Plugin): Save-Schema v5, Konverter
  Web-v0–v4→v5 mit ECHTEN Fixture-Saves aus dem Web-Code, Umzugskoffer-Import
  (JSON-String einfügen, `GOOBY5.<base64url(gzip)>.<crc32>`-Format), Ports der puren
  Kern-Systeme aus `GOOBY/src/systems/*.js`.
- **Owned-Files:**
  - `GOOBY-GODOT/autoload/save_manager.gd`, `autoload/game_state.gd`
    (inkl. **Slice-Registry-API**: `GameState.register_slice(name, default, validator)` —
    der Mechanismus, mit dem W2/W3-Agents Save-Slices hinzufügen, OHNE game_state.gd zu
    editieren; API nach W1 FROZEN, §3.2)
  - `GOOBY-GODOT/logic/` W1-Umfang: `economy.gd, stats.gd, leveling.gd, health.gd,
    weight.gd, inventory.gd, daily_bonus.gd, sleep.gd, day_night.gd, codes_engine.gd`
    (pure RefCounted-Ports der entsprechenden `systems/*.js`; Leveling = NEUE
    Multiplayer-Kurve laut USER-WISHES §C36, Level-Übernahme 1:1, XP→0)
  - `GOOBY-GODOT/migration/` (web_import.gd, migration_chain.gd v0→v4, koffer_codec.gd,
    `migration/ui/umzugskoffer.tscn/.gd`, `migration/ios_legacy_reader.gd` = **Stub** mit
    vollständiger Doku des NSUserDefaults-Goldwegs aus H §5.3; natives Plugin = Backlog)
  - `GOOBY-GODOT/content/base/migration/legacy_furniture_map.json`
  - `tools/export_web_saves.mjs` (erzeugt aus `/workspace/GOOBY`-Code deterministische
    Beispiel-Saves: frisch, midgame Lv23, maxed Lv40, korrupt, v2-alt)
  - `GOOBY-GODOT/tests/fixtures/saves/*.json`, `tests/test_migration.gd`,
    `tests/test_economy.gd`, `tests/test_leveling.gd`, `tests/test_stats.gd`,
    `tests/test_save_roundtrip.gd`, `tests/test_koffer_codec.gd`
  - `GOOBY-GODOT/strings/de/migration.json`
- **Acceptance (headless):**
  1. `node tools/export_web_saves.mjs` erzeugt die 5 Fixtures (committet).
  2. Migration-Test: jedes Fixture → v5; Feld-Asserts exakt nach H §5.2-Tabelle
     (Level 1:1, XP 0, +250-Umzugsbonus, furniture.placed→Lager, Grandfathering
     Radio/Kamera, `whats_new_5_seen=false`, Sticker-IDs 1:1, laufender Urlaub erstattet).
  3. Koffer-Codec: encode→decode-Roundtrip + CRC-Fehlererkennung + roher v4-JSON wird
     akzeptiert.
  4. Ökonomie/Stats/Leveling-Ports: Zahlen-Tests aus `GOOBY/test/*` übernommen und grün.
  5. Save-Roundtrip: v5 speichern→laden→identisch (atomar: tmp→rename).
  6. gdlint/gdformat sauber; Import fehlerfrei.
- **Commits:** `GODOT W1/STATE: ...`

### 2.2 W2 — Systeme (4 Agents)

#### W2a `HOUSE` — Haus, Räume, Türen, Grid-Baumodus, Navigation
- **Ziel:** Doc D M1-Kern + Doc A §5: 5 Raum-Szenen aus vorhandenen GLB-Kits,
  DoorTransition mit Steckenbleib-Gag, Grid-Baumodus (Boden-Layer M1), Lager 100,
  NavigationRegion + Gooby-Wandern/Standplatz, Onboarding-Bett-Schritt.
- **Owned-Files:**
  - `GOOBY-GODOT/rooms/` (_base/room_base.gd+.tscn, camera_anchor.gd, furniture_slot,
    bedroom/, living/, kitchen/, bathroom/, garden/ als .tscn)
  - `GOOBY-GODOT/components/door/door_transition.tscn/.gd` (Gag: stuck_chance 0.07,
    TapMash-Overlay, Skip, Settings-Toggle-Respekt; M1-Reisemodus = kurzer Veil/Cut,
    additives DOOR_TRAVEL = Backlog A §1.4)
  - `GOOBY-GODOT/components/camera/camera_rig.tscn/.gd` (A §4: fly_to, SpringArm,
    Dither-Fade)
  - `GOOBY-GODOT/home/` (grid_data.gd PURE, build_controller.gd, build_ui/ Drawer+Ghost,
    furniture_catalog.gd, storage_service.gd, home_state.gd als Save-Slice via
    GameState-API)
  - `GOOBY-GODOT/content/base/furniture/*.json` (~85 Items aus kenney/kaykit/itch,
    D §1.3-Schema), `content/base/rooms.json`
  - `GOOBY-GODOT/assets/kits/` (kuratierte Kopien der benötigten GLBs aus
    `GOOBY/public/assets/{kenney,kaykit,itch}` — einziger Agent, der diesen Ordner in
    W2 anlegt; spätere Wellen ergänzen nur eigene Unterordner)
  - `GOOBY-GODOT/ui/onboarding/bed_step.tscn/.gd` (dockt an W1c-Extension-Point an;
    Hammer-Qualm-Animation nutzt W1b-Clip `hammer_build`)
  - `GOOBY-GODOT/strings/de/house.json`
  - `tests/test_grid_data.gd` (Footprints, Rotation 0..3, Kollision, RUG-Regel,
    Pflichtmöbel-Zähler, blocked-Zellen), `tests/test_storage.gd`,
    `tests/test_furniture_catalog.gd`, `tests/test_rooms_smoke.gd`, `tests/test_door.gd`
- **Acceptance (headless):** GridData 100 % headless-getestet inkl. Lagerpunkte
  (Gewichte 1–4, Kapazität 100, Pflichtmöbel bett/couch/kuehlschrank); alle 5
  Raum-Szenen instanzieren fehlerfrei + `ready_for_reveal` feuert; Katalog-JSON
  validiert (jede GLB-Referenz existiert — Test iteriert Dateisystem); Tür-Statemaschine
  Unit-Test (Gag nie 2× hintereinander, Skip, Toggle). Import + Lint sauber.
- **Commits:** `GODOT W2/HOUSE: ...`

#### W2b `UPDATES` — PCK-Pack-System, Boot-Guard, ContentRegistry, docs/UPDATES.md
- **Ziel:** Doc B komplett (client- & CI-seitig): PackLoader, Boot-Guard (2-Crash-Regel),
  Manifest-Flow, Update-UI, ContentRegistry-Merge, Doku, pack-build-CI.
- **Owned-Files:**
  - `GOOBY-GODOT/autoload/pack_loader.gd`, `autoload/semver.gd`,
    `autoload/update_manager.gd`, `autoload/content_registry.gd`
    (Autoload-Registrierung via Handoff-Request → Orchestrator, §3.1)
  - `GOOBY-GODOT/content/{core,balance,events,cosmetics,stickers,codes}/pack.json`
    (7. „Pack“ config = plain JSON, Schema + Beispiel `config.example.json`)
  - `GOOBY-GODOT/ui/settings/update_panel.tscn/.gd` (ersetzt W1c-Platzhalter-Button —
    Übergabe per Handoff: W1c hat den Button als benannten Extension-Slot exportiert)
  - `docs/UPDATES.md` (**DEUTSCH, ausführlich**, Gliederung exakt B §6)
  - `.github/workflows/pack-build.yml`, `tools/build_manifest.mjs`,
    `GOOBY-GODOT/export_presets.cfg` (Pack-Presets `pack-<id>` mit Include-Filtern +
    `*.json`-Exportfilter; iOS-Preset-Skeleton für W1a-ipa-Workflow)
  - `tests/test_semver.gd`, `tests/test_pack_loader.gd` (Boot-Guard-Simulation:
    attempts 1/2/3 → Retry/Rollback/Safe-Mode; Stale-Cleanup),
    `tests/test_content_registry.gd` (append-by-id, deep-merge-override,
    last-writer-wins), `tests/test_pack_roundtrip.gd` (lokal gebautes Pck laden)
  - `GOOBY-GODOT/strings/de/updates.json`
- **Acceptance (headless):** Boot-Guard-Tests grün (installed.json-Zustände simuliert);
  Registry-Merge-Tests grün; ein lokal per `godot --headless --export-pack` gebautes
  Test-Pack wird geladen und `pack.json` daraus gelesen (CI-Smoketest aus B §7);
  `docs/UPDATES.md` existiert mit allen 9 Abschnitten; manifest-Builder erzeugt aus
  Fixture-Releases valides Manifest (node-Test). Import + Lint sauber.
  (Öffentliches Repo `gooby-updates` anlegen = User-Action → Handoff + Backlog-Vermerk.)
- **Commits:** `GODOT W2/UPDATES: ...`

#### W2c `SERVER` — GOOBY-SERVER komplett (M1-Umfang aus Doc C)
- **Ziel:** Ein Node-Prozess, ein Port: express + ws, JSON-Storage, HELLO/WELCOME/
  Heartbeat, FriendCode, Freunde+Presence+Coins-Cache, GoobyPal (250/Tag), Analytics-
  Sessions, Codes (Online-CRUD+Redeem), Events (Push+Pull), Webpanel 6 Seiten,
  AMP-README.
- **Owned-Files:** `GOOBY-SERVER/**` komplett (server.js, package.json — deps NUR
  express/ws/cookie-session, src/{config,store,auth,protocol,hub,rooms,friends,pal,
  analytics,codes,events,ratelimit}.js, panel/views+static, test/*.test.js,
  config.example.json, README.md mit AMP-„Node.js App Runner“-Anleitung + ENV-Tabelle;
  `data/` gitignored). Rooms/visits/boardgames/mail-Module: rooms.js generisch in W2c,
  visits.js/boardgames.js kommen in W3c (disjunkt, neue Dateien).
- **Acceptance:** `node --test` grün (pal-Tageslimit inkl. TZ-dayKey, codes-Lifecycle,
  store-Atomik, protocol-Envelope/v-Check, ratelimit-Buckets, analytics-Idempotenz);
  Server startet lokal, `/health` liefert `{ok:true}`; Panel ohne
  `GOOBY_ADMIN_PASSWORD` → 503 (fail-closed-Test); WS-Smoke per Node-Client
  (HELLO→WELCOME→PING/PONG) als Test; keine nativen Dependencies (`npm ls` Check im Test).
- **Commits:** `GODOT W2/SERVER: ...`

#### W2d `NETMG` — NetClient, Freunde-UI, Minigame-Framework + 2 Erstports
- **Ziel:** Doc C §6 (NetClient offline-first mit Outbox) + Doc G §1/§2 (Host, Ctx,
  GoobyRng, Pregame mit Orientierungswahl, JuiceKit) + Beweis-Ports `teaParty` +
  `carrotCatch` mit Bot-Headless-Zertifizierung.
- **Owned-Files:**
  - `GOOBY-GODOT/autoload/net_client.gd`, `autoload/net/{ws_link,protocol,outbox,
    identity,rooms}.gd` (+ FakeLink für Tests)
  - `GOOBY-GODOT/ui/friends/` (Freunde-Tab: Liste, Requests, Presence-Texte,
    Offline-Chip; Coins-Anzeige)
  - `GOOBY-GODOT/minigames/framework/` (minigame_host.tscn/.gd, minigame_base.gd,
    minigame_ctx.gd, gooby_rng.gd, pregame.tscn/.gd (Difficulty + **Orientierung
    3-fach-Toggle**, pro Spiel gemerkt), countdown, pause_menu, results, juice_kit.gd,
    juice_layer.tscn), `minigames/registry.gd`
  - `GOOBY-GODOT/logic/games/{tea_party_logic,carrot_catch_logic}.gd`,
    `logic/orientation_logic.gd`, `logic/minigame_framework_logic.gd`
    (Coin-Formel/Difficulty-Policy-Port)
  - `GOOBY-GODOT/minigames/games/tea_party/`, `minigames/games/carrot_catch/`
  - `GOOBY-GODOT/content/base/minigames/minigames.json` (M1: 2 Einträge + Schema)
  - `tools/cross_check.mjs` + `GOOBY-GODOT/tests/expected/{teaParty,carrotCatch}.json`
  - `GOOBY-GODOT/assets/covers/` (Kopie der 2 benötigten Cover aus Web)
  - `tests/test_gooby_rng.gd` (mulberry32 bit-identisch: Referenzwerte aus Node),
    `tests/test_tea_party_logic.gd`, `tests/test_carrot_catch_logic.gd`,
    `tests/test_net_client.gd` (FakeLink: HELLO/WELCOME, Outbox-Flush, Backoff),
    `tests/test_minigame_host.gd`
  - `GOOBY-GODOT/strings/de/minigames.json`, `strings/de/friends.json`
- **Acceptance (headless):** GoobyRng-Werte == Node-Referenz (Seeds 1..10);
  Bot-Zertifizierung beider Spiele: `simulate_autoplay` Seeds 1..50 × 4 Modi ==
  `expected/*.json` exakt; NetClient-Zustandsmaschine OFFLINE→CONNECTING→ONLINE mit
  FakeLink getestet, Outbox persistiert/flusht; Host-Lifecycle-Test (setup→start→end,
  Coin-Berechnung, 3-Strikes); Pregame speichert Orientierungswahl in Save-Slice.
  Optional-Integrationstest gegen laufenden W2c-Server, wenn vorhanden (skip-bar).
  Import + Lint sauber.
- **Commits:** `GODOT W2/NETMG: ...`

### 2.3 W3 — Content (4 Agents)

#### W3a `CITY` — Stadt, freie Fahrt, Reise-Cutscene, Taxi, Vacation
- **Ziel:** Doc E M1: 15×12-Stadt, freie Fahrt (Energie erst bei Ankunft,
  Nach-Hause-Knopf), „Laden“→„Reise“, Reise-Cutscene NEU (Tür→Straße→Taxi→Flughafen,
  Bestätigen+Warnung+NUTZEN), Taxi-Warte-Statemaschine + lokale Notification-Planung,
  Vacation-Port (Postkarten/souvenirCoins/visited als Urlaubs-NUTZEN).
- **Owned-Files:**
  - `GOOBY-GODOT/city/` (city_layout.gd 15×12 aus E §1.2, road_graph.gd A*, city.tscn,
    parking_trigger.gd, `city/car/{car_feel,player_car,chase_cam,drive_hud}.gd`
    — car_feel = Zahlen-Port von carFeel.js, `city/traffic/agents.gd` light 6 Autos)
  - `GOOBY-GODOT/cutscenes/{reise_abflug,reise_rueckkehr}.tscn/.gd`
  - `GOOBY-GODOT/systems/{taxi_service,vacation,notify_scheduler}.gd`
    (notify_scheduler = plattformneutrale Planung; iOS-Plugin-Aufrufe als dokumentierter
    Stub → Backlog C §8)
  - `GOOBY-GODOT/orte/_base/ort_scene.gd+.tscn`, `orte/flughafen/` (minimale
    Buchungs-UI: Ziel-Liste aus `data/vacations.js`-Port, Bestätigen-Dialog mit
    Warnung + Nutzen-Box)
  - `GOOBY-GODOT/content/base/city/{orte_katalog,vacations}.json`
  - `tools/blender/build_city_assets.py` + `assets/city_palette.png` (M1-Umfang:
    Flughafen-Terminal, Rollkoffer, Low-Poly-Flugzeug, 3 Wohnhaus-Korpusse; Ladenfronten
    im Detail = W4/Backlog), `GOOBY-GODOT/assets/kits/city/` (eigener Unterordner)
  - `tests/test_road_graph.gd`, `tests/test_car_feel.gd` (Web-Testzahlen),
    `tests/test_taxi_service.gd` (alle Übergänge inkl. VERPASST + App-Start-Recovery,
    Timestamps statt Countdown), `tests/test_vacation.gd`, `tests/test_city_smoke.gd`
  - `GOOBY-GODOT/strings/de/city.json`
- **Acceptance (headless):** road_graph-A*-Tests; car_feel zahlengleich zum Web;
  Taxi-Statemaschine komplett headless (Zeit injizierbar); Vacation-Phasen +
  Postkarten-Cap 36 + souvenirCoins-Gutschrift getestet; Stadt- und Cutscene-Szenen
  instanzieren fehlerfrei; Energie-Regel als Unit-Test (Fahren 0, Ankunft-Prompt-Kosten,
  nach Hause 0). Import + Lint sauber.
- **Commits:** `GODOT W3/CITY: ...`

#### W3b `GVZ` — Goobys vs Zombies, Singleplayer komplett
- **Ziel:** Doc G §4: 15-Level-Kampagne, 12 Türme + Goldi (Code-Gate), 10 Zombies +
  Boss Knurps, NUTELLA-Ökonomie, Dampfwalzen, Balancing als JSON (Pack-updatebar),
  Cover + Level-Select mit Sternen.
- **Owned-Files:**
  - `GOOBY-GODOT/logic/games/gvz_logic.gd` (20-Hz-Fixed-Tick, **int-Arithmetik**,
    deterministisch — PvP-ready laut G §R3)
  - `GOOBY-GODOT/minigames/games/gvz/` (gvz_board.tscn/.gd, Sprite-Rigs/Pools,
    level_select.tscn/.gd, gvz_bot.gd)
  - `GOOBY-GODOT/content/base/minigames/gvz/{balance.json,levels/L01..L15.json,pvp.json}`
    (pvp.json nur Daten, Feature = Backlog)
  - `GOOBY-GODOT/assets/covers/gvz.png` (vom Orchestrator generiert, §7 — W3b bindet ein;
    Platzhalter-Fallback erlaubt), Sprite-Assets unter `assets/gvz/`
  - Registry-Eintrag: NICHT via Edit von `minigames.json` (W2d-owned) — sondern
    `content/base/minigames/gvz/pack-entry.json`, das die Registry per dokumentiertem
    Merge-Hook lädt (Hook-API steht im W2d-Handoff)
  - `tests/test_gvz_logic.gd` (Determinismus: 2 Läufe gleicher Seed == identischer
    State-Hash; Bot gewinnt L1–L5 Seeds 1..20; Schwierigkeits-Monotonie; Goldi nur mit
    Code-Flag), `tests/test_gvz_levels.gd` (alle 15 JSONs schema-valide, jede Mechanik-
    Einführung laut G §4.4-Tabelle vorhanden)
  - `GOOBY-GODOT/strings/de/gvz.json`
- **Acceptance (headless):** alle o. g. Tests grün; Board-Szene instanziert; Level-Select
  liest Sterne aus Save-Slice; Sieg schreibt Münzen über MinigameCtx (kein eigener
  Economy-Pfad). Import + Lint sauber.
- **Commits:** `GODOT W3/GVZ: ...`

#### W3c `VISIT` — Besuchs-Multiplayer M1 + EIN Brettspiel
- **Ziel:** Doc C §3.4/§3.5: Haus-Snapshot-Sync (REST) + Besuch mit 2 sichtbaren Goobys
  (POS-Relay 5 Hz) + **Schiffe versenken** (ENTSCHIEDEN: statt Schach — deterministisch,
  keine Legalitäts-Engine, Server bleibt Turn-Relay) vollständig mit Emotes + Tomate
  (1×/Runde, Wurf-Animation via W1b-Clip `tomato_throw` falls vorhanden, sonst `wave`-
  Fallback + Backlog-Vermerk).
- **Owned-Files:**
  - `GOOBY-SERVER/src/visits.js`, `GOOBY-SERVER/src/boardgames.js`,
    `GOOBY-SERVER/test/{visits,boardgames}.test.js` (neue Dateien im W2c-Baum — per
    Handoff mit W2c-Modul-Kontrakt registriert)
  - `GOOBY-GODOT/multiplayer/` (visit_manager.gd, remote_gooby.gd Interpolation,
    board_table.gd, battleship_ui.tscn/.gd, emote_bar.tscn, tomato_overlay.tscn)
  - `GOOBY-GODOT/logic/games/battleship_logic.gd` (pure: Platzierung, Schuss-Auflösung,
    Zugnummern)
  - `GOOBY-GODOT/ui/visit/` (Besuchs-HUD, Bau-Warnung-Dialog „kann zu Problemen führen“)
  - `tests/test_battleship_logic.gd`, `tests/test_visit_manager.gd` (FakeLink-Skripte:
    Request→Accept→Join→POS→BUILD_DELTA→End; Konflikt „Gast steht auf Zelle“ →
    Tür-Teleport), Server-Tests s. o.
  - `GOOBY-GODOT/strings/de/visit.json`
- **Acceptance:** `node --test` (Server: Turn-Ownership, Tomate 1×/Runde erzwungen,
  Rejoin nach Disconnect ≤ 120 s, Snapshot-rev-Bump); Godot-Tests headless mit FakeLink
  grün; Battleship-Logik vollständig unit-getestet (Treffer/Versenken/Sieg); Besuchs-
  Flow-Integrationstest gegen lokal gestarteten Server (im CI: Server-Job startet Node).
  Import + Lint sauber.
- **Commits:** `GODOT W3/VISIT: ...`

#### W3d `CONTENT` — Random-Events, Sticker, Interactables, 5.0-Panel
- **Ziel:** Doc F §3/§4 (M1-Schnitt) + Doc H §2.3/§3: 6 Random-Events mit Timern +
  Notification-Planung, Sticker-Datenformat + Registry + Album + Einbindung der vom
  Orchestrator generierten Set-Bilder, Lampen-Schalter + Klo/Dusche(Schatten-Silhouette)
  + Spiegel(öffnet Editor) + Zähneputzen-Pflicht, 5.0-Neuigkeiten-Panel.
- **Owned-Files:**
  - `GOOBY-GODOT/components/interactable/` (interactable.tscn/.gd,
    interaction_manager.gd (Autoload-Request via Handoff), highlight-Shader,
    „Zeige alles“-Anbindung an W1c-Auge-Button-Signal)
  - `GOOBY-GODOT/interactions/` (lamp.gd+ui, bathroom_suite.gd (Klo/Dusche/Silhouetten-
    Shader/Duschvorhang-Peek-Grundfall), mirror.gd, toothbrush.gd inkl.
    `needs_brushing`-Blocker)
  - `GOOBY-GODOT/events/` (event_scheduler.gd, buffs.gd, event_runner.gd,
    `events/defs/{hingefallen,kuehlschrank,glas_teller,nutella_nacht,sockensuche,
    klopapier_mumie}.json` — 6 Stück M1, Texte final DE aus F §4.2)
  - `GOOBY-GODOT/stickers/` (sticker_registry.gd, album.tscn/.gd, sticker_card.tscn
    (Label ÜBER Bild, H §3.1), `content/base/stickers/sticker_texts_de.json`
    (85 germanisierte Bestands-IDs) + `content/base/stickers/sets/*.json` (neue Sets,
    soweit Bilder geliefert; fehlende Sets → „?“-Slots))
  - `GOOBY-GODOT/assets/stickers/` (85 Bestands-PNGs kopiert + generierte neue)
  - `GOOBY-GODOT/ui/news_panel/` (5.0-Panel, 4–5 Seiten, `whats_new_5_seen`-Gate)
  - `tests/test_event_scheduler.gd` (Zeitfenster, Timeout 5–10 min, Fail-Text, Cooldown,
    max 1 aktiv), `tests/test_buffs.gd`, `tests/test_sticker_registry.gd` (Merge,
    additiv-only, cond-Whitelist counter/special/event), `tests/test_interactables.gd`
  - `GOOBY-GODOT/strings/de/{events,stickers,interactions}.json`
- **Acceptance (headless):** Event-Scheduler komplett zeitinjiziert getestet;
  Sticker-Registry-Merge + Unlock-Bedingungen getestet; Album instanziert (Seiten =
  TabContainer, kein Rebuild-Bug); Zähneputz-Blocker-Logik unit-getestet; News-Panel
  zeigt sich genau 1× (Save-Flag-Test). Import + Lint sauber.
- **Commits:** `GODOT W3/CONTENT: ...`

### 2.4 W4 — Polish → Mega-Eval → Fix

#### Phase 1: Polish (10–20 kleine Agents, je eng umrissen, disjunkte Files)
Polish-Ziele (Liste; Orchestrator vergibt je 1 Agent, Commit `GODOT W4/POLISH-<k>: ...`):
1. Juice-Pass Minigames (JuiceKit-Verdrahtung teaParty/carrotCatch/GvZ)
2. SFX-Pass (Kenney interface/impact-Sounds systematisch verdrahten, AudioDirector-Busse)
3. LoadingVeil-Optik (Kachel-Pattern, Cover-Karte, Tips, hüpfender Gooby)
4. HUD-Feinschliff (Status-Kapsel-Sheet, Badge-Animationen, Safe-Area-Audit iPhone-Notch)
5. Onboarding-Charme (Gebrabbel-Sync, Kamera-Fahrten, Konfetti)
6. Raum-Licht & Kamera-Framing pro Raum (Budgets A §7 einhalten, Blob-Shadows)
7. Tür-Gag-Feintuning (Partikel, TapMash-Kurve, SFX)
8. Stadt-Ambiente (Tag/Nacht-Kurve, Streetlight-Emissive, Hupe)
9. GvZ-Balance-Pass (Bot-Telemetrie → balance.json nachziehen)
10. DE-Text-Korrektur (alle strings/de/*.json Rechtschreibung/Ton, Komposita-Umbrüche)
11. Fehlerpfade & Toasts (Offline-Chips, Update-Fehlertexte, Save-Korrupt-Dialog)
12. gdlint/gdformat-Vollsweep + tote Ressourcen/Imports aufräumen
13. Test-Lücken schließen (Coverage-Blick: ungetestete public funcs in logic/)
14. Performance-Overlay + Draw-Call-Messung Stadt/Räume (Dev-Panel 3-Finger-Tap)
15. README.md GOOBY-GODOT + GOOBY-SERVER (Build/Run/Test, DEUTSCH)
16. Reduced-Motion-Audit (alle Tweens/Shaker respektieren Setting)
17. Icons/Cover-Integration (generierte Assets einbinden, Arcade-Preload gegen Flacker-Bug)
18. Save-Migrations-Härtetest (Fuzz: kaputte/halbe v4-Saves → nie Crash, immer Bericht)
19. Freunde-/Besuchs-UI-Polish (Presence-Texte, Offline-Degradation sichtbar)
20. CI-Beschleunigung (Godot-Binary-Cache, Job-Parallelisierung, Artefakt-Uploads)

#### Phase 2: Mega-Eval (15 Agents: 5 Fable Max + 5 Opus Max fast + 5 Sol 5.6 Max fast)
Jeder Eval-Agent bekommt genau EINEN Blickwinkel, liefert `/tmp/gooby-godot/eval/E<nr>-<thema>.md`
mit Findings (Schweregrad P0–P3, Datei:Zeile, Repro headless):
1. Frisch-Boot & Onboarding (E2E headless-Skript + Szenen-Smoke)
2. Save-Migration mit allen Fixtures + Fuzz (Datenverlust = P0)
3. Test-/CI-Integrität (flaky Tests, Import-Warnungen, Runner-Exit-Codes)
4. Performance-Budgets (A §7-Tabelle nachmessen, Draw Calls/Tris via Overlay-Dump)
5. Orientierung/Resize-Matrix (6 Auflösungen × 2 Lagen × HUD/Pregame/Minigames)
6. Deutsch-Qualität & Ton (alle strings/de, Bubble-Längen 2×38, Knuffigkeit)
7. Theme-Treue (Token-Verstöße, hartkodierte Farben/Fonts, Touch-Floor 48 px)
8. Gooby-Charakter (Clips vorhanden/benannt, Morph-Budget, Voice-Sync, Preview-Renders)
9. Baumodus-Edgecases (Grid-Kollisionen, Lager voll, Pflichtmöbel, Undo, Katalog-Drift)
10. Minigame-Fairness (Bot-Zertifizierung, Difficulty-Targets, Coin-Ökonomie-Caps)
11. GvZ-Kampagnen-Kurve (L1–L15 Monotonie, Boss-Machbarkeit, Balance-JSON-Konsistenz)
12. Update-System-Robustheit (Boot-Guard-Fälle, Stale-Cleanup, Manifest-Fehler, Doku-Abgleich)
13. Server-Sicherheit (Rate-Limits, fail-closed-Panel, Input-Härtung, PII-Freiheit, Quotas)
14. Offline-first-Degradation (jedes Netz-Feature ohne Server: Chip statt Fehler, Outbox)
15. Architektur-Treue zu Docs A–H (Frozen-Contracts verletzt? Autoload-Disziplin? logic/ node-frei?)

#### Phase 3: Fix-Welle
Orchestrator konsolidiert Findings → P0/P1 werden von Fix-Agents (Fable Max) behoben,
Commit `GODOT W4/FIX: ...`; P2/P3 wandern in den Backlog §6 (mit Eval-Referenz).
DoD wie jede Welle (§4) + alle P0 geschlossen.

---

## 3) Shared-File-Regeln & Handoff-Konvention

### 3.1 Shared-File-Ownership (bindend)
| Datei/Bereich | Regel |
|---|---|
| `GOOBY-GODOT/project.godot` | Schreiber NUR W1a. Ab W2: Änderungen (Autoloads, Input-Map, Settings) ausschließlich vom **Orchestrator zwischen den Wellen**, gespeist aus `handoffs/project-godot-requests.md` (Append-only, jeder Agent trägt Wünsche ein). |
| `GOOBY-GODOT/theme/**` | NUR W1c. Danach FROZEN; Änderungswünsche via Handoff, umgesetzt in W4/POLISH. Kein Agent definiert eigene Farben/Fonts — nur `tokens.gd`. |
| `autoload/game_state.gd`, `save_manager.gd`, Save-Schema v5 | NUR W1d. API + Schema nach W1 FROZEN. Erweiterung ausschließlich über `GameState.register_slice(...)` aus eigenen Dateien (W2a: `home`, W2b: `packs`, W2d: `net`+`minigames`, W3a: `city`+`vacation`+`taxi`, W3b: `gvz`, W3c: `visits`, W3d: `events`+`stickers`+`buffs`). |
| Strings | KEIN gemeinsames `de.json`. Pro Domain eine Datei `GOOBY-GODOT/strings/de/<domain>.json`, Owner = Domain-Agent (Tabelle in den Wellen). Loader (W1c) mergt alle Dateien; Key-Kollisionen = Test-Fehler. |
| `tests/run_tests.gd` + `test_case.gd` | NUR W1a. Auto-Discovery `tests/test_*.gd` — jeder Agent legt nur eigene Testdateien an, editiert nie den Runner. |
| `content/base/minigames/minigames.json` | Owner W2d. Andere Spiele registrieren sich über eigene `pack-entry.json` im eigenen Ordner (Merge-Hook, W2d-Handoff dokumentiert das Format). |
| `GOOBY-GODOT/assets/kits/**` | Anlage durch W2a; spätere Agents ergänzen NUR eigene Unterordner (`kits/city/`, `gvz/`…), überschreiben nie fremde Dateien. |
| `export_presets.cfg` | Owner W2b (Pack- + iOS-Preset). Wünsche via Handoff. |
| `.github/workflows/**` | `godot-ci.yml`+`ios-ipa.yml` = W1a; `pack-build.yml` = W2b. Sonst Handoff. |
| `GOOBY-SERVER/**` | W2c-Baum; W3c darf NUR die im Plan genannten NEUEN Dateien anlegen (visits.js, boardgames.js + Tests) und `server.js`-Registrierung via 1-Zeilen-Hook, den W2c als dokumentierten Modul-Loader bereitstellt (`src/modules.js`-Liste, Owner W2c, Eintrag per Handoff-Request an Orchestrator). |
| `GOOBY/**` (Web-Referenz) | READ-ONLY für alle. Niemals editieren. |

### 3.2 Frozen-Contracts (nach der jeweiligen Welle unveränderlich)
- Nach W1: Autoload-Namen/-Pfade, SceneRouter-API (`goto`, Reise-Typen), Gooby-API
  (`play/set_emotion/look_at_point/anchors`), GameState-Slice-API, Save-v5-Grundschema,
  Theme-Tokens, Test-Runner-Konventionen, Strings-Loader-Format.
- Nach W2: GridData-Datenmodell + Katalog-Schema, Pack-/Manifest-Schema (B §1),
  Server-Protokoll-Envelope `{v,t,seq,ts,d}` + Message-Typen, MinigameBase/Ctx-Contract,
  GoobyRng.
- Bruch eines Frozen-Contracts = nur mit explizitem Orchestrator-Beschluss + Migration
  aller Aufrufer im selben Commit.

### 3.3 Handoff-Konvention
- Verzeichnis: `/tmp/gooby-godot/handoffs/`; Dateiname `W<welle><tag>.md`
  (z. B. `W1a-core.md`, `W2c-server.md`), Eval: `eval/E<nr>-<thema>.md`.
- Pflicht-Struktur: **(1) Geliefert** (Dateien + LOC + Commits), **(2) API-Verträge**
  (Signaturen, Schemas, Beispiele), **(3) project.godot-/Shared-File-Requests**,
  **(4) Bekannte Lücken/Warnungen**, **(5) Tipps für Nachfolger** (inkl. Import-Fallen).
- Zusätzlich Append-only-Sammeldateien: `handoffs/project-godot-requests.md`,
  `handoffs/asset-requests.md` (Bilder/Blender-Wünsche an den Orchestrator, §7).
- Jeder Agent liest zu Beginn ALLE Handoffs vorheriger Wellen (Pflicht im Agent-Prompt).

---

## 4) Definition of Done — PRO WELLE (jede einzelne, keine Ausnahme)

1. `godot --headless --import` über `GOOBY-GODOT/` → Exit 0, **keine** ERROR-Zeilen.
2. `godot --headless --script res://tests/run_tests.gd` → `failed: 0`.
3. `gdlint` sauber + `gdformat --check` sauber (gdtoolkit, über alle `.gd` des Repos).
4. Wo Server berührt: `node --test` in `GOOBY-SERVER/` grün.
5. Blender-Pipelines (wo berührt) laufen headless ohne Fehler durch.
6. `git add` (nur Owned-Files!) + Commits `GODOT W<n>/<TAG>: ...` + **Push**; CI grün.
7. Handoff-Datei geschrieben (§3.3).
Der Orchestrator startet Welle n+1 erst, wenn ALLE Agents der Welle n die DoD erfüllen
und die project.godot-/Shared-Requests eingepflegt sind (Integrations-Commit
`GODOT W<n>/INTEGRATE: ...`).

---

## 5) M1-Inhaltsübersicht (was nach dieser Session spielbar ist)

Onboarding (Name/Spitzname/Editor) → Haus mit 5 Räumen, Tür-Gag, Grid-Baumodus + Lager,
Gooby mit Rig/Stimme/Interactables (Lampe, Bad-Suite, Spiegel, Zähneputzen) →
Stadt mit freier Fahrt + Flughafen/Urlaub + neuer Reise-Cutscene + Taxi-Warteschleife →
Arcade mit Framework + teaParty + carrotCatch + **GvZ-Kampagne (15 Level)** →
6 Random-Events, Stickerbuch (85 + neue Sets), 5.0-Panel → Update-System (Packs,
Boot-Guard, Settings-Knopf, docs/UPDATES.md) → GOOBY-SERVER (Freunde, Presence,
GoobyPal, Codes, Analytics, Panel) + Besuch beim Freund mit 2 Goobys + Schiffe
versenken (Emotes+Tomate) → Save-Migration v4→v5 inkl. Umzugskoffer.

---

## 6) Backlog M2/M3 — ALLE übrigen User-Wünsche (nichts verlieren)

Format: `[M2|M3] Wunsch — Doc-Verweis`. M2 = nächste Ausbaustufe, M3 = Kirsche/Stretch.

### A — Engine (Doc A)
- [M2] DOOR_TRAVEL additiv (Zielraum additiv laden, Kamera fährt DURCH die Tür, Path3D-CamPath) statt M1-Cut — A §1.4/§4/§5 **→ teilweise (bewusste Alternative):** eigener `DOOR_TRAVEL`-Tür-Wisch ohne Voll-Veil + threaded Preload (`scene_router.gd`, `door_transition.gd`; getestet, EF-3/EVAL-1-abgesegnet); additives Laden + CamPath-Kamerafahrt bleiben offen (Polish)
- [M2] Rückblick (Recap) 2.0: korrekt rotiert + generell verbessert; recapEngine/Director/History-Port — USER §A12, A §8 **✅ erledigt (W6/FIX):** voller Port `scripts/recap/{recap_engine,recap_director,recap_scene,recap_service}.gd`, Kino im Querformat (`_lock_landscape`); Tests `test_recap_*.gd`
- [M2] Restliche System-Logik-Ports (~23: quests, garden-Voll, weather, achievementsEngine, collections, stickerBook-Engine, profileStats, offline, notifyRules, musicRegistry, modifierEngine, cutscene, shopTrip, themePark, postcards-Rest, gallery, nougat, radioQueue, furniturePlacement…) — A §8 **→ Stand W13: 16/19 erledigt;** real offen nur Sammlungsset-UI im Album, sichtbare Wetter-FX Haus/Stadt und Nougatschleuse — alle drei in W13 in Arbeit
- [M2] Performance-Profiling auf echtem iPhone + `scaling_3d`-Regler + LightmapGI-Option — A §7/§6 **→ teilweise:** `scaling_3d`-Regler ✅ (`quality_service.gd` + Settings-Grafiksektion, dazu Auto-Profil + Perf-Notbremse); echtes iPhone-Profiling (User-Action: .ipa sideloaden) und LightmapGI-Option offen
- [M3] Shader-Warmup-Quad im Veil (R2), PhysicalBone-Ragdoll-Experiment (F) — A §Risiken

### B — Updates (Doc B)
- [M2] Öffentliches Artefakt-Repo `MedusaV9/gooby-updates` anlegen + `GH_CONTENT_TOKEN` (User-Action!) + Ende-zu-Ende-Release-Test — B §3/§5 **→ SEIT W15 ÜBERHOLT:** User-Entscheidung, die Updates laufen über das private Haupt-Repo selbst (GitHub-Release-API + Spieler-Token, `docs/UPDATES.md` §1/§6a) — das separate public Repo entfällt endgültig; real offen bleibt nur der erste echte E2E-Release-Test (`updates`-Release im aktuellen Repo `MedusaV9/ModdingWebseite`)
- [M2] ipa-build.yml voll funktionsfähig (Godot-iOS-Export + xcodebuild unsigned + Release-Asset + latest_native-Bump) — B §5.2, W1a-Skeleton vorhanden **→ Build-Kern ✅ (W6 + W11):** `ios-ipa`-Job in `gooby-godot.yml` baut + verifiziert bei jedem Push grüne unsignierte .ipas (Artefakt `GOOBY-godot-unsigned-ipa`, `tools/ci/verify_ipa.py`); offen nur Release-Asset-Step + `latest_native`-Bump
- [M2] Soft-Restart-Flow im Client + „wirksam ab Neustart“-UX-Feinschliff — B §2.4 **→ teilweise:** Toast „wirksam ab Neustart“ + `ContentRegistry.reload()` existieren; der „Jetzt neu laden“-Soft-Restart-Flow hat keinen Aufrufer
- [M2] Server-IP/Port live aus config.json bei jedem Connect (NetClient-Anbindung) — B §1.1/USER §B19 **✅ erledigt (W2d):** `net_client.gd::_resolve_net_config()` liest bei JEDEM Verbindungsaufbau frisch aus der ContentRegistry; E2E-Test `test_updates_flow.gd`, Kontrakt `docs/UPDATES.md` §7
- [M3] Manifest-RSA-Signierung (Härtung V2) — B §7
- [M3] Mirror #2 über Node-Server — B §3(C)

### C — Backend/Multiplayer (Doc C)
- [M2] Post/Mail: Briefe + Fotos (REST-Upload, Quota, Prune) + Item-Geschenke + Post-Ort — C §3.7, USER §C33 **→ Ort + Storage-Fundament ✅** (`orte/post.gd` mit Offline-Tagespaket; `storage.js` mit Blob-Ablage + Size-Limits); das Mail-Modul selbst (REST, Quota, WS-Push) fehlt
- [M2] InstantGooby (Feed-UI überm Mail-Backend) — C §3.9
- [M2] GoobyPal-App-UI (Verlauf, 250/Tag-Anzeige; Server-Seite existiert ab W2c) — C §3.3 **→ teilweise:** Sheet mit Senden + „Heute noch X“-Anzeige ✅ (`goobypal_sheet.gd`, im IGohbie verdrahtet); die Verlaufs-LISTE wird nicht gerendert (Daten liegen in `fetch_history().entries` bereit)
- [M2] Zweites Brettspiel: **Schach** (UCI-Relay, Client-Legalität) — C §3.5 (M1 lieferte Schiffe versenken) **✅ erledigt:** Client komplett (`scripts/social/boardgame/chess_{logic,ai,session,scene}.gd`), Server relayt über dieselbe Turn-Maschine (`boardgames.js`, `GAMES = ['battleship','chess']`; Zug reist bewusst als `SHOT {move}` statt eigenem `MOVE`-Kind → null Server-Sonderlogik); 12 Boardgame-Tests
- [M2] Snap A Gooby (First-Person-Selfies + `phone_up`-Emote im Besuch) — USER §E60, C §3.9
- [M3] Coop-Fahrt: einer fährt, einer steuert Radio (Radio-Sync `drive:`-Room) — C §3.6, USER §C31 **→ Server-Room fertig** (`drive:` in `rooms.js`, Presence-Template existiert); Client fehlt komplett
- [M3] Koop-Minigames-Relay: GvZ PvP + GvZ Coop (15 Level) + GOB-NOM-Coop (10 Level) — C §3.8, G §4.5/§4.6/§5.4 **→ GOB-NOM-Coop ✅ lokal/hot-seat** (10 Level spielbar, Sim lockstep-vorbereitet mit `state_hash`); GvZ PvP nur Daten-Stub (`gvz_pvp.json`), GvZ-Coop-Level existieren nicht, Netz-Relay überall offen (Ranch-MP liefert das `mg:`-Room-Muster als Kopiervorlage)
- [M3] ActivityKit-Live-Activity fürs Taxi (Widget-Extension, eigenes Design) — C §8, USER §C37 (M1: lokale Notifications geplant, Plugin-Stub)
- [M2] `gooby_notify`-iOS-Plugin nativ bauen (UNUserNotificationCenter, ~200 LOC ObjC) — C §8 M1-Plugin, W3a-Stub vorhanden **→ Andockpunkt ✅ dokumentiert** (`notification_service.gd::_os_schedule()`; Kategorien/Ruhezeiten in `notify_rules.gd` getestet); das native Plugin selbst fehlt
- [M3] Account-Umzugs-Code (Panel-generiert) — C §7
- [M2] Besucher-schläft-auf-Couch-Regel (abends/0 Energie, Couch-Pflichtmöbel-Hook) — USER §C32
- [M2] wss/TLS-Deploy-Doku + `ws://`-Nur-Heimnetz-Gate — C §7 **→ Doku-Teil ✅** (`GOOBY-SERVER/README.md` §TLS: Reverse-Proxy → wss, Heimnetz-Hinweis); das `ws://`-Heimnetz-Gate im Client fehlt noch (verbindet vorbehaltlos)
- [M3] Companion-App-Modus: Zweitgerät (Handy) zeigt Map/Quests, während auf dem Hauptgerät gespielt wird — expliziter User-Wunsch, bis zur W13-Planungswelle nirgends erfasst (neu aufgenommen W13). Bau = L: eigener Read-only-Client + Server-Room-Typ; Vorstufen: GoobyPal-/IGohbie-Konzepte wiederverwenden

### D — Haus/Bau/Garten (Doc D)
- [M2] Wand-/Decken-Layer im Baumodus (WALL/CEILING-Modi, Fenster als WALL-Items mit exterior-Flag) — D §1.2/§2.1 **→ WALL-Layer ✅** (`grid_data.gd` WALLS N/E/S/W + `build_mode.gd`, Fenster mit `exterior`-Flag; Tests `test_home_grid.gd`); CEILING fehlt — Decken-Items laufen als WALL-Items
- [M2] Fenster-Diorama (Straße mit vorbeifahrenden Autos hinterm Portal-Quad) — D §1.2, USER §D43 **✅ erledigt:** `street_diorama.gd` (Straße mit fahrenden Autos) + `exterior/garten_diorama.gd`, Zuordnung über `house_layout.gd`; bewusst Kulisse hinter der Wand statt Portal-Quad-Shader (dokumentiert im Header)
- [M2] Werkstatt + Materialien (Stöcke/Holz/Eisen/Nägel) + Rezepte/Baupläne + Crafting-UI — D §5.1–5.3, USER §D46 **✅ erledigt:** `scripts/home/craft/` (Materialien mit Quellen, 5 Rezepte + Bauplan-Gate, Crafting-Panel, Werkstatt als Garten-Outbuilding); Tests `test_craft_*.gd`
- [M2] Goobay-Verhandlungs-Minispiel (Emoji-Eskalation, Abholung/Post-Versand) — D §5.4, USER §D49 **✅ erledigt:** `scripts/home/goobay/` (Verhandlung exakt nach D §5.4 inkl. Käufertypen + Versand-Bonus); Test `test_home_goobay.gd`
- [M2] Garten 2.0: Wind/Schatten-Faktoren, Erweiterungsstufen, Zäune als Kanten, Bewässerungsanlage, Gewächshaus (2×3, Tür-Zelle, Exoten-Crops) — D §6, USER §D50 **✅ erledigt:** `garden_grid/growth/state.gd` (Kanten-Zäune, Gewächshaus mit Tür-Zelle, Sprinkler 3×3, Wind/Schatten, Stufen 6×5→12×10 — Maße bewusst an die Raumgröße angepasst); Test `test_home_garden.gd`
- [M2] Wochenmarkt als ECHTER Ort (Samstag, eigener Stand, Preiselastizität, Info-Schild + Erste-Male-Karte) — D §6.3, USER §D51 **✅ erledigt (Kernumfang):** `orte/wochenmarkt.gd` + `markt_preise.gd` (Sa 8–14, Preiselastizität −5 %/Stück, Erste-Male-Karte); nur der eigene Verkaufs-Stand mit Preis-Slider + Kunden-Sim bleibt offen
- [M2] Möbel-Bestell-Cutscene (LKW + Clipboard, delivery.glb) — D §3.2, USER §D42 **✅ erledigt:** `delivery_cutscene.gd` + `assets/city/autos/delivery.glb` (Klemmbrett, Skip, läuft beim nächsten Gartenbetreten)
- [M2] Shed L2/L3-Upgrades (M1: L1) — D §2.3 **✅ erledigt:** `shed_logic.gd` (Stufen 0–3, Preise 500/1500/4000) + `shed_l1–l3.glb`; Test `test_home_shed.gd`
- [M2] Baumarkt-Ort (Einkauf, Baupläne, Zäune, „Bodo Balken“) — D §5/E §2.3, USER §D47 **✅ erledigt:** `orte/baumarkt.gd` („Bodo Balken“) + `baumarkt_katalog.json` (Materialien + Baupläne) + Dialog-JSON; Zäune craftbar über Werkstatt-Rezept
- [M3] Haus-Upgrades: Keller, 2. Etage, Balkon (+ Treppen/Portale, Bau-Overlay) — D §4.1, USER §D43 **→ nur Etagen-OPTIK ✅** (EG-Deckenbalken/DG-Dachschräge via `house_layout.gd`); Keller/Balkon/kaufbare Etagen/Treppen fehlen
- [M3] Garage (Rolltor, Bau-Anim) + Autohaus-Ort + Autos kaufen/Farben (car-kit-Material-Split-Skript) + Auto-Stats — D §7, USER §D48 **→ Autohaus ✅** („Blechbert“: `autohaus.gd` + `auto_katalog.gd`, Kauf + Farbwahl + Stats, aktives Auto als Contract); Garage am Haus (Rolltor) fehlt
- [M3] IKEA-Großladen: 3D-Ausstellung (drehbare Modelle, Kategorien, Farbe/Muster/Stoff, Grid-Bedarf sichtbar, Brettspieltisch, Radio, SEHR viele Möbel) — USER §D52, D/E-Schnittstelle **✅ erledigt (W6, Kernumfang):** `ikea_screen.gd` (Suche, Kategorie-Chips) + 3D-Vitrine mit Drehteller (`furniture_showcase.gd`) + Farb-/Stoff-Varianten + Footprint-Label; 207 Möbel (203 GLB) inkl. Brettspieltisch + Radio. Begehbarer 3D-Ausstellungs-RAUM bleibt Kür
- [M3] SURFACE-Layer-Feinschliff + Layout-Presets („Raum speichern“) — D §10 M3 **→ SURFACE ✅** (Träger-vor-Aufbau-Ordnung, W4/FIX-D); „Raum speichern“-Presets fehlen komplett
- [M2] proc:*-Deko-Nachbauten in Blender (Migration reaktiviert `__unknown__`-Items) — D §8/§9 **✅ erledigt:** 203/207 Katalog-Items mit GLB, nur noch 4 gewollte proc-Items (parametrische Fensterrahmen, Postkartenwand, Souvenirregal); `__unknown__`-Items bleiben im Lager erhalten und reaktivieren sich

### E — Stadt/Orte (Doc E)
- [M2] Orte-Interieurs: REHWEI, GOOBYTHEKE, GOOUHBUS (Rezept-Flow-Quest!), POW! (Kamera + 3 Tagesangebote), Post, Autohaus, Wochenmarkt — E §2.3/2.4, USER §E59 (M1 hat nur Flughafen minimal) **✅ erledigt:** 9 begehbare Interieurs unter `scripts/city/orte/` (inkl. Rezept-Flow im GOOUHBUS, POW!-Kamera-Gate + deterministische Tagesangebote, Tierarzt); Tests `test_city_orte.gd`, `test_city_pow.gd`
- [M2] Dialog-System (JSON-Bäume, dialog_runner, Typewriter-Bubbles, Sprecher-Pitch-Gebrabbel) + alle DE-Dialoge — E §2.2/2.4 **✅ erledigt (weitgehend):** `dialog_runner.gd` (cond/effekt, EN-Fallback) + Pitch-Gebrabbel (`gooby_voice.gd`), 9 DE-Dialogbäume + EN; nur der Buchstaben-Typewriter fehlt (Bubble poppt zeilenweise)
- [M2] GOOBERANDO komplett: 3 Restaurants, Bestell-UI, deterministische Fahrer-Sim auf road_graph, oranger Liefer-Gooby, Übergabe, Trinkgeld-Buff+Hinweis, Logo — E §5, USER §E60 **→ teilweise:** Bestell-Flow + oranger Liefer-Gooby + Trinkgeld-Buff + Logo ✅ (`gooberando.gd`/`gooberando_state.gd`); nur 1 Restaurant (REHWEI) und Prep-Timer statt Fahrer-Sim auf dem road_graph
- [M2] IGohbie-Handy-Shell + Apps (Taxi, Guber, GOOBERANDO, GoobyPal, InstantGooby, Snap A Gooby, Kamera, Freunde-Status) — USER §E60, E §5.1/C §3.9 (M1: Taxi-Ruf minimal) **→ 6 Apps ✅** (Taxi, Guber, GOOBERANDO, Kamera mit POW-Gate, Freunde, GoobyPal — `phone_shell.gd`/`phone_apps.gd`); InstantGooby + Snap A Gooby fehlen
- [M2] Stadtkarte/2D-Minimap mit Pins + GPS-Pfeil — E §1.3 **→ Minimap ✅** (Karten-Kachel im Fahr-HUD, Orts-Pins, Fahrtrichtungs-Dreieck, `minimap.gd`); Ziel-GPS-Pfeil und Vollbild-Karte fehlen
- [M2] Guber (30 ᴳ, sedan-sports, vornehmer Fahrer-Dialog, Surge-Gag) — E §4 **✅ erledigt (mit Detail-Abweichungen):** `fahrdienst.gd` (25 statt 30 ᴳ = Design-Entscheid, schneller als Taxi, vornehmer Fahrer-Dialog); Surge-Gag + eigenes Cutscene-Fahrzeug (sedan-sports) fehlen
- [M2] Fußgänger-Goobys, Hupe-Reaktionen, Tag/Nacht-Stadt, Near-Miss-Funken — E §1.4/1.5 **✅ erledigt (weitgehend):** `city_fussgaenger.gd` (bis 14 Goobys), `city_verkehr.gd` (Ampeln, Nacht-Gelbblinken), Tag/Nacht-Lichtkurve, Near-Miss → Hupe + Toast; Funken-Partikel + Fußgänger-Reaktion auf die Spieler-Hupe fehlen
- [M2] Urlaubs-Nutzen-Ausbau: physische Souvenirs + Souvenir-Regal + Set-Bonus „Weltengooby“, Erholungs-Boost 48 h, GOOBY-FREE-Shop, Postkarten als WALL-Items — E §3.3 (M1: souvenirCoins+Postkarten+visited) **→ teilweise:** Souvenirregal + Set-Bonus-Stufen + Postkarten-WALL-Item ✅ (`postkarten_logic.gd`/`postkarten_props.gd`); „Weltengooby“-Titel, 48-h-Erholungs-Boost und GOOBY-FREE-Shop fehlen
- [M2] POW!-Kamera-Gate + Fotomodus + Galerie (Kamera nötig für Fotos) — USER §E61, H §6.5 **✅ erledigt:** `pow_angebote.gd` (`hat_kamera()`-Gate), `foto_modus.gd`, `kamera_app.gd`; Tests `test_city_pow.gd`, `test_rest4_galerie.gd`
- [M3] Ambient-Audio-Distrikte, Wohnhaus-Varianten, Traffic-Vollausbau (10–14 Wander-Agenten) — E §1.5/§7 M3
- [M2] Alle Rückblick-Orte erreichbar; Weltraum = „Raumstation GOOB-1“-Hub (rocketRescue+starHopper-Terminals) — USER §E59/§G89, G §7 **→ alle 9 Reiseziele buchbar ✅** (inkl. `space`; CatalogSync-Test); der begehbare „Raumstation GOOB-1“-Hub mit den 2 Spiel-Terminals fehlt

### F — Gooby/Interaktionen (Doc F)
- [M2] Restliche Random-Events: robo_jagd, kleber_stuhl, wurm_freund, fernbedienung, karton_gooby, gewitter_angst, mehl_unfall + Nutella-Nacht-Voll-Fenster-Mechanik-Feinschliff — F §4.2 (M1: 6 Events) **✅ erledigt:** alle 7 in `content/events/data/events.json` (13 Events gesamt, komplett spielbar via `event_runner.gd`) inkl. Nutella-Voll-Fenster; Tests `test_events_*.gd`. Restlücke: `klopapier_mumie` (M1-Soll aus F §4.2) existiert nirgends
- [M2] Idle-Wandern + „Wo ist mein Gooby?“-Kamera-Teleport + Tat-Bubbles — F §4.2/§7, USER §F81 **→ Idle-Wandern ✅** (`gooby_home.gd`, BFS im Raum, Test `test_fix2_movement.gd`); der HUD-Chip „Wo ist mein Gooby?“ existierte ohne Consumer — Verkabelung (Kamera-Fokus + Tat-Bubble) in W13 in Arbeit
- [M2] Schüttel-Secret (Accelerometer, 3 Stufen, Fake-Tumble-Ragdoll, Sticker) — F §5, USER §F69
- [M2] BODEN-IST-LAVA / SPIDERGOOBY-Flow (Blockade-Erkennung → Choice → Decke) — F §6, USER §F78 **✅ erledigt:** Blockade-BFS (`grid_data.gd`) → Beschwerde-Bubble + Choice → `spidergooby_flow` mit Decken-Gag (`room_base.gd`/`gooby_home.gd`); Test `test_home_blocked.gd`
- [M2] Geschichten-Stunde (Buch-UI Lückentext, Bücher-Katalog, Entertainment-Abnutzung) — F §3.2, USER §F74 **→ Lückentext-UI ✅** (`story_time.gd`, am Bett angebunden); Abnutzungsformel + Bücher-Shop fehlen, Katalog hat erst 2 Stories (expliziter M2-Marker im Code)
- [M2] Duschvorhang-Peek-Varianten (>45 s-Gag mit rotierenden Bubbles) — F §3.2 (M1: Grundfall) **✅ erledigt:** `klo_dusche.gd` (>45-s-Peek je Fenster, 3 rotierende Sprüche, Silhouette + `duschvorhang.glb`)
- [M2] P1-Clips (dance, refuse, ragdoll_flail, grip_floor, tomato_throw, ceiling_cling) — F §1.4
- [M3] Laufband-Gag-Minigame + Sticker, PC/GOBBULL-Zocken (+GOBBULL-Konsole kaufbar) — F §3.2, USER §F75/76
- [M3] P2-Clips (treadmill, pc_gaming, idle-variety, book_listen), PhysicalBone-Ragdoll — F §1.4/§5
- [M2] Mehr passive Animationen overall (Idle-Variety-Rotation) — USER §F68 **→ Verhaltens-Variety ✅** (6 Idle-Akte im Soul-Pack mit Cooldown-Rotation + 12 W12-Emotionen); zusätzliche Idle-Rig-CLIPS fehlen (Rig hat nur idle/idle_lookaround)
- [M2] „Interaktions-Anzeige“-Vollausbau (Screen-Space-Icons + Rand-Pfeile) — F §3.1 (M1: Rim-Puls) **→ W13 in Arbeit:** der HUD-Auge-Button existierte ohne Consumer (toter Draht, auch der M1-Rim-Puls fehlte); wird in W13 verdrahtet

### G — Minigames (Doc G)
- [M2] 28 restliche Logic-Ports + Szenen (Reihenfolge laut G §3-Tabelle; carrotGuard früh als GvZ-Vorstudie; shoppingSurf zuletzt; cityDrive/deliveryRush/toyRacer nach Autohaus-CarDefs) — G §3 **✅ erledigt (bis auf City Drive):** 37 registrierte Spiele (30 Web-Ports + GvZ + GOB NOM + 5 Ranch); einzig `cityDrive` fehlt als Arcade-Runde (die freie Stadtfahrt existiert)
- [M2] GOB NOM komplett: RopeLink-Physik, 8 Element-Bausteine, 15 SP-Level, Nutella-Glas-Sammlung, @tool-Level-Editor — G §5 (Coop → M3, s. C) **→ Spiel ✅** (Verlet-Physik, 15 SP- + 10 Coop-Level, alle per `gobnom_solver.gd` lösbar bewiesen, 5 Testdateien); der `@tool`-Level-Editor fehlt
- [M2] Difficulty-Targets-Zertifizierung aller Ports (cross_check.mjs ausweiten, expected/*.json committen) — G §2.5 **→ teilweise:** echte Web-Fixture-Zertifizierung nur für teaParty + carrotCatch (4 Fixtures unter `tests/expected/`); breite Godot-Bot-Abdeckung (Monotonie-/Plausibilitätstests in 27+ Testdateien) existiert
- [M2] Auto-Stats-Integration in Fahr-Spiele (car_stats_logic, Pregame-Anzeige) — G §6
- [M2] Endless-Modi + Endlos-Lock + 3-Strikes-Cutscene-Vollausbau — G §1.2 **→ Endless ✅** (29/33 Manifeste + teaParty/carrotCatch, Lock `endless_unlocked`, Award-Pfad); `ctx.strike()` + 3-Strikes-Teleport-Cutscene fehlen (die pure `apply_strike`-Logik existiert ungenutzt)
- [M3] HDR-2D-Glow-Auto-Downgrade-Telemetrie, danceParty-Audio-Latenz-Kalibrierung — G §9
- [M2] GvZ: Goldi-Code im Codes-Pack ausliefern; Sticker-Trigger L5/10/15 — G §4.2/4.4 **→ W13 in Arbeit:** die Hooks lagen brach (kein Goldi-Code im Codes-Pack, GvZ-Sticker-Counter wurden nirgends inkrementiert → 6 GvZ-Sticker unerreichbar); wird im W13-GvZ-Paket verdrahtet

### H — UI/Content (Doc H)
- [M2] Profil-Tab NEU (Reisepass-Karte, Werdegang, Statistiken, Erfolge-Grid 44, Sticker-Schnellzugriff, Web-Rekorde-Karte, Freunde-Karte) — H §2.1, USER §H95 **✅ erledigt (W10, kleine Kür-Abweichungen):** `profil_screen.gd` (Pass-Karte mit drehbarem 3D-Porträt, Abschluss-Karte, Lifetime-Statistiken, Erfolge n/44 → `achievements_screen.gd`, Sticker-Fortschritt, Rekorde inkl. Web-Rekorde, Freunde-Karte); Tests `test_rest1_profil.gd`, `test_abschluss_logic.gd`
- [M2] Reisepass 2.0 (Flip-Karte, Passfoto aus Fotomodus, Stempelseite, MRZ-Gag, „5.0 UMZUG“-Stempel) — H §2.2
- [M2] Flughafen-Abflugtafel-UI im Design-System (Flip-Board, Boarding-Pass) — H §2.4, USER §H94 (M1: minimale Buchung)
- [M2] Restliche Sticker-Sets ausliefern bis 126+1 (7 Sets × 6; M1 nur gelieferte Bilder) + Rarity-Effekte (Silber/Gold/Glitzer) — H §3.3/3.4 **→ Menge übererfüllt:** 141 Sticker (140 regulär + 1 geheim) in 23 Seiten mit validierter Rarity (`stickers.json`, Pack v1.1.0); die Rarity-Unlock-FX (Silber-Funkel/Gold-Glitzer) fehlen noch. Set-Struktur weicht bewusst von §3.3 ab — IDs sind Save-referenziert, NICHT umbauen
- [M2] Cosmetics 2.0: Pack-Format + Laufzeit-glb + 36 neue Items + 7 neue Fellfarben (inkl. Galaxie-Shader) + SubViewport-Icon-Renderer; 42 Alt-Outfits + 7 Fellfarben 1:1 — H §4, USER §H99 **→ weitgehend ✅:** 92 Einträge (alle 42 Web-Outfits 1:1 + 37 neue + 7 alte und 6 neue Fellfarben), Pack-Format + geteilter SubViewport-Renderer; offen nur Galaxie-Fell + Shimmer-Shader. Laufzeit-glb bewusst durch prozedurale Builder ersetzt (für Pack-Updates gleichwertig — dokumentierte Abweichung)
- [M2] Radio 2.0: IKEA-Kauf-Gate, Bordmusik-Loop (nur Pause), Sender-Picker, Cover-Art, „Was läuft?“-Ticker — H §6.1, USER §H101 (Grandfathering ist in M1-Migration drin) **→ Sender-Picker/Now-Playing/Level-Schlösser/Likes ✅** (`radio_sheet.gd`/`radio_logic.gd`, De-facto-Gate übers platzierte IKEA-Radio-Möbel, Grandfathering in der Migration); Bordmusik-Regel (nur Pause) + Kauf-Gate-Härtung + Ticker in W13 in Arbeit; Cover-Art fehlt
- [M2] GOB.TY: 5 Puppet-Clips als SubViewport-TV — H §6.2, USER §H102
- [M2] Girlanden/Spann-Deko (Path3D-Catenary, Lichterkette mit echten Lights) — H §6.3, USER §H103
- [M2] Goobyman-Laden (Zahnbürsten-Haltbarkeit, Bruch-Chance remote-config!) — H §6.4, USER §H104/§B21 **→ nur der Bürstenbruch-Gag ✅ remote-konfigurierbar** (`zahnbuersten_bruch_chance` im Balance-Pack); Laden, Haltbarkeit/Blocker und Quest fehlen
- [M2] iOS-NSUserDefaults-Legacy-Reader als NATIVES Plugin (`legacy_save_reader`, ~40 LOC ObjC) + Gerätetest Bundle-Id/`CapacitorStorage.`-Prefix — H §5.3 (M1: dokumentierter Stub + Umzugskoffer-Fallback funktioniert immer) **✅ erledigt (FIX-6, als GDScript-Lösung statt nativem Plugin):** `state/import/bplist.gd` + `legacy_capacitor.gd` + Boot-Hook beim Erststart (`home_entry.gd`) + Settings-Zeile; 12 Tests (`test_migration_transfer.gd`). Das native ~40-LOC-Plugin bleibt Kür für den Gerätetest
- [M3] bplist-Parser-Fallback in GDScript (~200 LOC) — H §5.3 **✅ erledigt** — ist die produktive Hauptlösung geworden (s. Zeile darüber)
- [M2] uiScale-Setting → content_scale_factor-Stufen — H §5.2-settings-Mapping **✅ erledigt (andere, zentralere Mechanik):** Slider 0.85–1.3 → `UiScale.user_factor` in der zentralen Skalierungsregel (Safe-Area-/Touch-Floor-bewusst) statt grobem `content_scale_factor`; Web-`uiScale` wird migriert
- [Notiz] Garderobe-HUD-Knopf: H §„Garderobe-Knopf weg“ wollte ihn entfernen (Anpassen nur über Spiegel im Haus + Shop), W6 hat ihn bewusst zurückgebracht (Sichtbarkeit der 92 Cosmetics). Unprotokollierter Plan↔Code-Konflikt → offener User-Entscheid; aktuell existieren BEIDE Wege (HUD-Knopf + Spiegel)

### Prozess
- [M2] Regelmäßige IPA-Builds über Actions ab funktionsfähigem ipa-build.yml — USER §Prozess **✅ erledigt:** der `ios-ipa`-Job läuft bei jedem GOOBY-GODOT-Push mit (Artefakt `GOOBY-godot-unsigned-ipa`), zuletzt durchgehend grün
- [M2] Blockbench-Installation nur falls konkreter Bedarf (bisher deckt Blender alles) — USER §Prozess **✅ erledigt (nie gebraucht):** alle Assets kamen über die Blender-Headless-Pipeline
- [Notiz] Trailer-Musik: der finale 57,6-s-Trailer (W12) nutzt bewusst den instrumentalen CC-BY-Track „Glitter Blast“ (Kevin MacLeod). Der ursprüngliche Lyrics-Wunsch wurde abgewogen: das Instrumental passt zum Beat-genauen Gameplay-Schnitt (100 BPM = exaktes 36-Frame-Raster bei 60 fps), und eine saubere CC-Lizenz + Beat-Grid sind mit Gesang schwer kombinierbar — dokumentierte Entscheidung (Details: `trailer/CREDITS.md`)
- [Notiz] Ranch-DLC (W6–W9; lief außerhalb dieses Backlogs über die RANCH-DLC-IDEAS-Docs): Freischalt-Level wird in W13 von 20 auf 15 gesenkt (expliziter User-Wunsch; reine Pack-Daten `content/ranch/data/balance.json`), dazu Ranch-spezifische Random-Events (ebenfalls W13 in Arbeit)

---

## 7) Asset-Listen

### 7.1 Bild-Generierungsliste für den ORCHESTRATOR (GenerateImage)
Stil-Anker überall: „GOOBY-Spiel-Stil: cremefarbener flauschiger Hase (#F2E5CE), riesige
Schlappohren rosa Innenseite, rosa Wangen, Pastell (#FFF6EC/#FF7BA9/#59C9B9/#FFD166),
runde Formen, dicke Outlines #4A3B36, KEIN Text im Bild“ (Logo-Ausnahmen markiert ⚠,
je einzeln reviewen). Priorität: ★ = in dieser Session (W1c/W3b/W3d binden ein),
Rest = M2-Backlog-Assets.

| Prio | Asset | Format | Ziel-Pfad | Spec-Quelle |
|---|---|---|---|---|
| ★ | GvZ-Cover | 1024×768 | `assets/covers/gvz.png` | G §1.5 (Gooby mit Möhren-Blaster vs. niedliche Zombie-Goobys am Gartenzaun) |
| ★ | GOB-NOM-Cover (Backlog-Spiel, Cover schon fürs Arcade-Grid) | 1024×768 | `assets/covers/gobnom.png` | G §1.5 |
| ★ | Sticker-Set „Garten“ (6) | je 512² transparent | `assets/stickers/garten*.png` | H §3.3-Tabelle (Bild-Spec je Zeile, weißer 12-px-Rand) |
| ★ | Sticker-Set „Stadt“ (6) | 512² | `assets/stickers/stadt*.png` | H §3.3 |
| ★ | Sticker-Set „GvZ“ (6) | 512² | `assets/stickers/gvz*.png` | H §3.3 |
| ★ | Patterns: travel, city, gvz, news (4 von 11) | 512² seamless, monochrome Linien-Icons | `assets/acui/pattern_*.png` | H §7 #1–11 |
| ★ | 5.0-News-Header | 1024×512 | `assets/acui/news5_header.png` | H §7 #55 |
| ★ | Umzugskoffer-Illustration | 768² | `assets/acui/umzugskoffer.png` | H §7 #69 |
| M2 | Sticker-Sets „Fische&Teich“, „Orte“, „Freunde“, „GOB NOM“ (24) | 512² | — | H §3.3 |
| M2 | Patterns: pond, friends, post, baumarkt, market, gobnom, goobyman (7) | 512² seamless | — | H §7 |
| M2 | GOOBERANDO-Set ⚠: App-Icon 1024², Wordmark, Tüten-Aufdruck weiß, Map-Pin 128² | div. | — | E §5.3 (exakte Farb-/Form-Specs) |
| M2 | Laden-Logos ⚠: REHWEI, GOOBYTHEKE, GOOUHBUS, POW!, Baumarkt, Post, Autohaus | je 512² | Schild-Quads der Blender-Ladenfronten | E §6.2, H §7 #70+ |
| M2 | Goobyman-Logo ⚠, POW!-Kamera-Icon ⚠, GOB.TY-Senderlogo ⚠ | 512² | — | H §7 #61–63 |
| M2 | Reisepass-Cover-Wappen | 1024² | — | H §7 #54 |
| M2 | 5 Radio-Sender-Cover | 512² | — | H §7 #56–60 |
| M2 | GOB.TY-Clip-Spritesheets (5 Sets) | Sheets | — | H §7 #64–68 |
| M2 | App-Icon GOOBY 5.0 (iOS, 1024²) | 1024² | iOS-Export | B §5.2 |

Anlieferung: Orchestrator legt generierte Dateien nach `/tmp/gooby-godot/assets_in/`
+ Eintrag in `handoffs/asset-requests.md` (Status erfüllt); Owner-Agent kopiert in
seinen Ziel-Pfad und committet.

### 7.2 Blender-Bau-Liste (headless-Skripte, Kenney-Stil, Palette-Methode E §6.3)
| Prio | Asset | Owner/Skript | Quelle |
|---|---|---|---|
| ★ W1 | Gooby-Charakter (Mesh/Rig/Morphs/Clips/GLB) | W1b `tools/blender/gooby_build/` | F §1 |
| ★ W2 | Fenster-Modul (2 Größen), Hammer+Clipboard+Kartonstapel-Props, Shed L1 | W2a (kleines `tools/blender/build_house_props.py`) | D §9 #1–3 |
| ★ W3 | Flughafen-Terminal+Tower, Low-Poly-Flugzeug, Rollkoffer, 3 Wohnhaus-Korpusse | W3a `tools/blender/build_city_assets.py` | E §6.2 |
| M2 | proc:*-Nachbauten (5 Canvases, Gnome, Birdbath, miniGooby, Bänke, Gießkanne, Toy-City, Candy-Jar, Goldfischglas) | Backlog | D §9 #4 |
| M2 | 7 Ladenfronten + IKEA-Box + `ort_interior_kit` + Marktstand + Info-Schild | Backlog | E §6.2, D §9 #7 |
| M2 | Werkbank+Werkstatt-Hütte, Gewächshaus, Sprinkler, Stock/Eisen/Nägel, Rustikal-Serie | Backlog | D §9 #5–9, #12 |
| M2 | GOOBERANDO-Papiertüte + Käppi (Gooby-Attachment), Souvenir-Regal + 9 Souvenirs | Backlog | E §6.2 |
| M3 | Treppen/Balkon-Geländer, Garage (Rolltor) + car-kit-Karosserie-Material-Split, Shed L2/3 | Backlog | D §9 #10–11 |

---

## 8) Start-Reihenfolge (Orchestrator-Checkliste)

1. `mkdir -p /tmp/gooby-godot/handoffs /tmp/gooby-godot/eval /tmp/gooby-godot/assets_in`
2. W1: 4 Agents (CORE, GOOBY, UIKIT, STATE) parallel starten — jeder mit: Plan-§ seiner
   Welle + relevante Docs + Owned-Files + DoD.
3. Parallel: ★-Bilder aus §7.1 generieren (mind. GvZ-Cover + 3 Sticker-Sets + 4 Patterns
   + News-Header + Koffer-Illustration) → `assets_in/`.
4. W1-DoD prüfen → `GODOT W1/INTEGRATE`-Commit (project.godot-Requests) → W2 starten.
5. W2-DoD → Integrate → W3 starten. W3-DoD → Integrate → W4 (Polish → Eval → Fix).
6. Abschluss: Backlog §6 gegen Ist-Stand abgleichen, Abweichungen im Backlog vermerken,
   finaler Handoff `handoffs/SESSION-FINAL.md` (was M1 liefert, was exakt fehlt).
