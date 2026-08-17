# A — Engine & Architektur (Godot 4.4) — konkretes Design

Ideen-Improver A. Bereich: USER-WISHES §A komplett + Kamera/Tür-Wünsche aus §F (Tür-System,
Steckenbleib-Gag). Verifiziert auf der VM: `godot` = 4.4.1.stable, `blender` = 4.0.2,
`/workspace/GOOBY-GODOT/project.godot` existiert als leerer Bootstrap. Referenz-Web-Spiel:
`/workspace/GOOBY` (three.js; `src/systems/*.js` + `src/minigames/games/*.logic.js` sind
größtenteils pure JS — siehe §8).

---

## 1) Projekt- & Szenenstruktur

### 1.1 Verzeichnislayout (`/workspace/GOOBY-GODOT`)

```
res://
├── project.godot
├── autoload/                 # NUR Skripte/Szenen der Autoloads
│   ├── event_bus.gd          # globale Signale (typed), KEIN State
│   ├── game_state.gd         # Stats/Coins/Level/Inventar — pure State + Signals
│   ├── save_manager.gd       # JSON-Save (user://save_v5.json), Migration §H
│   ├── scene_router.gd       # Raum-/Screen-Wechsel-Statemaschine (§1.4)
│   ├── loading_veil.tscn/.gd # CanvasLayer(100) — Ladescreen, gehört dem Router
│   ├── audio_director.gd     # Musik/SFX-Busse, Ducking, Radio-Queue-Host
│   ├── orientation_service.gd# §2 — Lock/Restore pro Minigame
│   └── app_config.gd         # gelesene Remote-/Update-Config (Hook für §B-Team)
├── main/
│   └── main.tscn             # Root-Szene (§1.3)
├── rooms/                    # 1 Ordner = 1 Raum = 1 .tscn (User-Wunsch §A)
│   ├── _base/room_base.gd, room_base.tscn, camera_anchor.gd, furniture_slot.tscn
│   ├── bedroom/bedroom.tscn (+ bedroom.gd nur wenn Sonderlogik)
│   ├── living/  kitchen/  bathroom/  garden/  …später: cellar/ floor2/ balcony/
├── components/               # wiederverwendbar, szenenfrei instanzierbar
│   ├── door/door_transition.tscn/.gd      # §5
│   ├── camera/camera_rig.tscn/.gd         # §4
│   ├── ui/safe_area_container.gd          # §3
│   ├── ui/speech_bubble.tscn
│   └── gfx/blob_shadow.tscn
├── gooby/gooby.tscn          # Charakter: Mesh+Skeleton+AnimationTree
├── minigames/
│   ├── framework/minigame_base.gd, pregame.tscn, results.tscn
│   └── bubble_pop/bubble_pop.tscn + bubble_pop_logic.gd   # Logik getrennt! (§8)
├── logic/                    # Ports der *.logic.js — PURE GDScript, keine Nodes
│   ├── economy.gd  leveling.gd  stats.gd  …
│   └── games/bubble_pop_logic.gd  …
├── ui/                       # HUD, Tabs, Screens (Bereich H, hier nur Gerüst)
├── gfx/env_home.tres  env_garden.tres  env_minigame_punchy.tres   # §6
├── assets/                   # GLBs/Sticker/Musik aus GOOBY/public/assets übernommen
└── tests/run_tests.gd  test_case.gd  test_economy.gd  …          # §9
```

Regeln:
- **Autoloads halten State + Orchestrierung, Szenen halten Darstellung.** Kein Autoload
  referenziert jemals eine konkrete Raum-Szene (nur `RoomBase`-Contract) — sonst zerbricht
  die Modularität aus §B (Content-Packs).
- `logic/` ist **node-frei** (nur `RefCounted`/`static func`) — exakt das Erfolgsmuster der
  Web-Version (`.logic.js` ohne three/DOM), damit §9-Tests headless ohne Szenen laufen.

### 1.2 Autoloads (Reihenfolge = Ladereihenfolge)

| Autoload | Verantwortung | Warum eigenständig |
|---|---|---|
| `EventBus` | typisierte globale Signale (`room_changed`, `coins_changed`, `gooby_stuck`…) | entkoppelt UI↔3D↔Systeme |
| `AppConfig` | Remote-/Update-Config lesen (Drop-Chancen, Server-IP) | Hook fürs §B-Update-Team, read-only für alle anderen |
| `SaveManager` | Laden/Speichern/Migration, Autosave-Timer, Schreibschutz während Transitions | zentrale Datei-I/O-Stelle |
| `GameState` | Spielzustand (Stats, Inventar, Unlocks) — delegiert Rechnen an `logic/` | Single Source of Truth |
| `AudioDirector` | Bus-Setup, Musik-Crossfade, „Bordmusik“-Loop, SFX-Pools | überlebt Szenenwechsel |
| `OrientationService` | §2 Lock/Restore, Resize-Broadcast | ein Ort für Plattform-Sonderfälle |
| `SceneRouter` (+ `LoadingVeil`-Szene) | §1.4 | der einzige Ort, der Szenen tauscht |

### 1.3 Root-Szene `main.tscn`

```
Main (Node)
├── World (Node3D)              # Router mountet hier Raum-/Minigame-3D
├── UILayer (CanvasLayer 10)    # HUD (Stats oben, Buttons unten — Bereich H)
├── PopupLayer (CanvasLayer 50) # Dialoge, Speech-Bubbles-2D, Toasts
└── (LoadingVeil = Autoload-CanvasLayer 100 — liegt IMMER über allem)
```

### 1.4 SceneRouter — Übergänge OHNE Overlap (Kern-Wunsch §A)

Der Web-Bug war: **zwei konkurrierende Systeme** (150-ms-Schwarzfade in `sceneManager.js` +
`loadingVeil.js` obendrauf) → Überschneidung + Lag. In Godot gibt es genau **ein**
Transition-Surface (`LoadingVeil`) und genau **eine** Statemaschine:

```
IDLE → COVER → SWAP → WAIT_READY → REVEAL → IDLE
```

- `goto(target: StringName, params: Dictionary)` — wenn `_busy`, wird die Anfrage **ersetzt**
  (nur die letzte gequeued), nie parallel gestartet. `Blocker`-Control frisst Input ab COVER.
- **COVER:** Veil-Iris zu (AnimationPlayer, 0.35 s; bei „Reduzierte Bewegung“: Fade).
- **SWAP:** alte Szene `queue_free()` + `await tree.process_frame`; neue Szene war bereits per
  `ResourceLoader.load_threaded_request()` beim *ersten Anfassen des Reiseziels* (z. B.
  Tür-Tap, Reise-Bestätigen-Dialog) vorgeladen → `load_threaded_get()` blockiert praktisch nie.
- **WAIT_READY:** Reveal erst wenn ALLE erfüllt: (a) neue Szene emittiert `ready_for_reveal`
  (RoomBase wartet selbst auf Texturen/GLB-Platzierung), (b) 2 idle-Frames vergangen
  (Shader-/Pipeline-Warmup; Godot 4.4-Pipeline-Precompile hilft, deckt aber nicht alles),
  (c) `min_shown_ms` (600) erreicht. **Hard-Timeout 8 s** → Force-Reveal + Log (nie
  Deadlock — 1:1 die bewährte Web-Veil-Semantik, aber in EINEM System).
- **Zwei Reise-Typen** (löst den scheinbaren Konflikt „Räume = eigene Szenen mit Ladescreen“
  vs. „Kamera fährt smooth durch Türen“):
  - `DOOR_TRAVEL` (Nachbarraum im Haus): Zielraum wird **additiv** ins `World` geladen
    (an seinem Welt-Offset, Räume haben feste Grid-Positionen), Kamera fährt durch die Tür
    (§4/§5), danach alter Raum `queue_free()`. **Kein Veil.** Fallback: dauert das
    threaded Load > 1.5 s, Veil einschieben.
  - `VEIL_TRAVEL` (Haus↔Stadt, Minigames, Orte): voller Ladescreen wie oben.

`LoadingVeil`-Szenenbaum (Optik: Port des cozy Web-Veils — Muster-Kachel, Cover-Karte,
hüpfender Gooby, Tips):

```
LoadingVeil (CanvasLayer, layer=100)
├── Blocker (Control, full-rect, mouse_filter=STOP)
├── Curtain (TextureRect, Kachel-Pattern, tile)
├── Card (PanelContainer, zentriert via anchors)
│   ├── CoverArt (TextureRect)      # Minigame-Cover aus assets/covers
│   ├── GoobyMotif (AnimatedSprite2D)
│   ├── Tip (Label, rotierend)
│   └── Progress (ProgressBar)      # gefüttert von load_threaded_get_status
└── AnimationPlayer                 # iris_in / iris_out / fade_in / fade_out
```

### 1.5 RoomBase-Contract (jeder Raum erbt)

```
bedroom.tscn — Bedroom (Node3D, extends RoomBase)
├── Geometry (Node3D)        # Wände/Boden (GridMap ODER gebakte Meshes)
├── Furniture (Node3D)       # FurnitureSlot-Instanzen (Bereich D dockt hier an)
├── Anchors (Node3D)         # Marker3D: goobyIdle, bed, lampSwitch, window …
├── Doors (Node3D)           # DoorTransition-Instanzen, export target_room
├── CameraAnchors (Node3D)   # CameraAnchor: overview, bed_detail, mirror …
├── Interactables (Node3D)   # Area3D-Tap-Ziele (input_ray_pickable)
├── Lights (Node3D)          # budgetiert, §7
└── RoomEnv (WorldEnvironment) # shared res://gfx/env_home.tres
```

API (Port der `roomManager.js`-Surface): `get_anchor(name:StringName)->Node3D`,
`enter_from(door_id)`, `set_ambience(band, weather, blend)`, Signal `ready_for_reveal`,
Signal `interactable_tapped(name, point)`.

---

## 2) Orientierung: Querformat bevorzugt, beides überall

- **project.godot:** `display/window/handheld/orientation = "sensor"` (alle 4 Lagen);
  Design-Basis **1280×720 (Landscape)**. iOS-Export: alle Interface-Orientations aktivieren.
- **Stretch:** `content_scale_mode = canvas_items`, `content_scale_aspect = expand`,
  `content_scale_size = 1280×720`. `expand` heißt: bei Portrait wächst die vertikale
  Canvas-Fläche — **UI ausschließlich über Anchors/Container**, nie absolute Pixel.
- **Layout-Umschalten:** `OrientationService` lauscht auf
  `get_viewport().size_changed`, klassifiziert `LANDSCAPE/PORTRAIT` und broadcastet
  `EventBus.orientation_changed`. HUD-Screens implementieren `apply_layout(o)` —
  meist nur Container-Umhängen (`HBoxContainer`↔`VBoxContainer`) statt zweiter Szenen.
- **3D „Raum nutzt den Platz“:** `RoomBase` berechnet bei Resize die Kamera-Framing neu:
  Raum-AABB → benötigte FOV/Distanz je Aspekt (`keep_aspect = KEEP_HEIGHT` landscape,
  Umschalten auf `KEEP_WIDTH` portrait, plus Distanz-Fit). Kein toter Rand, kein Crop.
- **Per-Minigame-Orientierung (§G-Wunsch, hier die Engine-Seite):**
  `OrientationService.lock(mode)` ruft `DisplayServer.screen_set_orientation(...)`
  (`SCREEN_SENSOR_LANDSCAPE` / `SCREEN_SENSOR_PORTRAIT` / `SCREEN_SENSOR`). Auf iOS ≥16
  triggert Godot `setNeedsUpdateOfSupportedInterfaceOrientations` — funktioniert, aber
  **Risiko R1 (§Risiken):** früh auf Gerät verifizieren; Fallback ist „Soft-Rotation“
  (Minigame in `SubViewport`, 90° gedrehtes `SubViewportContainer`). Gemerkte Wahl liegt
  im Save: `minigame_prefs[id].orientation`; Restore auf globales Setting beim Verlassen.

---

## 3) Dynamische Handy-Größen + Safe Areas (iOS)

- Stretch-Konfiguration aus §2 erledigt die Skalierung; zusätzlich:
- **`SafeAreaContainer` (Control-Script, `components/ui/`):** liest
  `DisplayServer.get_display_safe_area()` (Screen-Pixel!), rechnet in Canvas-Koordinaten um
  (`Rect2(safe) * get_viewport().get_final_transform().affine_inverse()`), setzt sich selbst
  `offset_*` als Padding. Aktualisiert bei `size_changed` (deckt Rotation ab). JEDES
  Full-Screen-UI (HUD, Tabs, Minigame-HUD) hat genau einen SafeAreaContainer als Wurzel.
- Notch/Home-Indicator: Buttons unten bekommen zusätzlich min. 8 px über Safe-Bottom.
- 3D braucht KEINE Safe-Area (darf hinter die Notch), nur Tap-Ziele nicht randbündig legen.
- iPad/ungewöhnliche Aspekte: Framing-Fit aus §2 deckt das ab; UI-Maximalbreite per
  `custom_minimum_size`/`size_flags` auf zentrale Panels (Tabs max ~900 px breit).

---

## 4) Kamera-System

```
CameraRig (Node3D, components/camera/camera_rig.gd)
├── Pivot (Node3D)                 # Look-Target, geglättet (lerp/critically damped)
│   └── SpringArm3D                # collision_mask = nur Layer "camera_blocker", margin 0.25
│       └── Camera3D               # near = 0.05, fov dynamisch (§2)
└── (im Script: FastNoiseLite für Schüttel-Secret-Shake §F — Hook, nicht mein Bereich)
```

- **Zustände:** `ROOM_OVERVIEW` (steht auf CameraAnchor „overview“ des aktiven Raums) →
  `TRAVEL` (fährt Curve) → `DETAIL` (z. B. Spiegel, Brettspieltisch). Wechsel ausschließlich
  über `CameraRig.fly_to(anchor|curve, dur)` mit `Tween` `TRANS_CUBIC/EASE_IN_OUT`;
  Positions- UND Look-Target-Kurve getrennt getweent (verhindert „Schwenk-Ruck“ an Türen).
- **Türfahrten:** jede `DoorTransition` liefert `CamPath (Path3D)` — eine im Editor
  autorierte `Curve3D` von Overview A durch die Türmitte zu Overview B. Design-Garantie
  (Kurve geht durch die Tür) ist die primäre Clipping-Vermeidung.
- **Clipping-Restfälle (Möbel im Weg, User baut frei — §D!):** dreifach abgesichert:
  1. **SpringArm3D** aktiv in ROOM_OVERVIEW/DETAIL (Follow-Situationen): zieht die Kamera
     vor Blocker. Nur GROSSE Möbel (Schrank, Regal) bekommen den Physics-Layer
     `camera_blocker`; Kleinkram nie (sonst zittert der Arm).
  2. **Raycast-Pullback während TRAVEL:** SpringArm nützt auf autorierten Kurven wenig →
     pro Frame Ray vom Look-Target zur Soll-Position; Hit ⇒ Kamera auf Hitpoint−margin.
  3. **Dither-Fade:** Möbel, deren AABB die Kamera-Nähe schneidet, blenden per
     `GeometryInstance3D.transparency` (0→0.85, 0.15 s) aus — Standard-Property, kein
     Custom-Shader nötig, läuft im Mobile-Renderer.
- `near = 0.05` + FOV-Fit aus §2 minimieren Near-Plane-Schnitte zusätzlich.

---

## 5) DoorTransition-Komponente (wiederverwendbar, §F-Gag inklusive)

```
door_transition.tscn — DoorTransition (Node3D)
├── DoorMesh (Node3D: Rahmen + Türblatt)
│   └── AnimationPlayer            # open / close / rattle (Steckenbleiben)
├── CamPath (Path3D)               # §4 — pro Instanz im Raumeditor angepasst
├── WalkPath (Path3D)              # Goobys Laufweg (kurz vor/nach Türblatt)
├── StuckPoint (Marker3D)          # Position des Gags im Türrahmen
├── StuckParticles (GPUParticles3D)# Staub/Sternchen
├── Sfx (AudioStreamPlayer3D)      # Knarzen, Plopp
└── door_transition.gd
```

Script-API: `@export var target_room: StringName`, `@export var stuck_chance := 0.07`,
`async func travel(gooby: Gooby, rig: CameraRig) -> void`, Signale
`travel_started/stuck_started/stuck_resolved/travel_finished`.

Ablauf von `travel()` (vom SceneRouter im `DOOR_TRAVEL`-Modus aufgerufen, NACHDEM der
Zielraum additiv geladen ist):
1. Gooby läuft `WalkPath` entlang (AnimationTree „walk“), Tür `open`.
2. Würfel `stuck_chance` (nie 2× hintereinander; über `AppConfig` tunebar): **Gag** —
   Gooby stoppt am `StuckPoint`, Body-Deform als **Squash-Scale auf dem Hüft-Bone via
   `SkeletonModifier3D`/`Skeleton3D.set_bone_pose_scale`** (kein Blendshape nötig, Kenney/
   KayKit-Rigs haben keine), `rattle`-Anim + Partikel, `SpeechBubble` „Gooby ist stecken
   geblieben!“, dann **TapMash-Overlay** (Control auf PopupLayer: N Taps mit Decay-Balken,
   ~3–5 s) → `stuck_resolved`: Plopp-SFX, Gooby stolpert durch, kurzer Kamera-Punch.
3. Kamera fährt parallel `CamPath` (§4), Gooby läuft in den Zielraum, Tür `close`,
   alter Raum wird freigegeben.
4. **Skip:** Tap irgendwo (außer TapMash) ⇒ Tween-Zeitraffer ×4 bis Ende; Settings-Flag
   `doors_animated=false` ⇒ `travel()` degradiert zu 0.3-s-Kamera-Cut ohne Lauf/Gag.

Dieselbe Komponente dient auch der Haustür (Ziel = Stadt ⇒ Router schaltet nach
`travel_finished` auf `VEIL_TRAVEL` weiter) und später Keller/2. Etage (§D).

---

## 6) Postprocessing (WorldEnvironment, mobile-tauglich)

Shared Ressourcen unter `res://gfx/` (Räume referenzieren, nie inline — 1 Ort zum Tunen):

| Ressource | Inhalt |
|---|---|
| `env_home.tres` | Tonemap **AgX**, Glow AN (`levels` 3+5, `intensity` 0.35, `hdr_threshold` 1.0, blend `SOFTLIGHT`), Ambient aus Sky-Farbe, Adjustments (Sättigung 1.05) |
| `env_garden.tres` | wie home + ProceduralSky, Glow etwas höher, Fog AUS (Volumetric Fog = Forward+-only!) |
| `env_minigame_punchy.tres` | Glow kräftiger (`intensity` 0.6) für §G „spannender mit Bloom“ |

- **SSAO: NEIN.** SSAO/SSR/SSIL/SDFGI existieren im Mobile-Renderer nicht. Ersatz:
  (a) AO im Vertex-Color/Textur der GLBs vorbaken (Blender 4.0.2 auf der VM — Batch-Bake-
  Script), (b) `blob_shadow.tscn` (Quad + Multiply-Material) unter Gooby/Möbeln,
  (c) später optional `LightmapGI` pro Raum (statisch, mobile-ok).
- **Vignette:** nicht in Environment → 1 `ColorRect` mit 6-Zeilen-Canvas-Shader auf
  eigener `CanvasLayer(90)` in `main.tscn`, Stärke per Settings/Szene tweenbar (Türfahrt
  darf die Vignette leicht anziehen — billiger Cinematic-Effekt).
- Glow läuft im Mobile-Renderer (3D-HDR intern RGBA16F) — auf iPhone ok, aber Levels klein
  halten. **Kein** Screen-Space-Effekt zusätzlich.

---

## 7) Performance-Budgets iPhone (Renderer: Mobile)

`project.godot`: `rendering/renderer/rendering_method = "mobile"` (Desktop-Preview darf
Forward+ per Feature-Override, aber **getestet wird gegen Mobile**).

| Budget | Zielwert (Raum) | Zielwert (Minigame) |
|---|---|---|
| Draw Calls sichtbar | ≤ 150 | ≤ 250 |
| Dreiecke sichtbar | ≤ 150 k | ≤ 250 k |
| Realtime-Lights mit Schatten | 0 innen (Blob/gebaked), 1 Directional außen (2048er Atlas) | 0–1 |
| OmniLights ohne Schatten | ≤ 4 pro Raum | ≤ 6 |
| Unique Materials | ≤ 25 pro Raum (Kenney-GLBs teilen Paletten-Material!) | ≤ 30 |
| GPUParticles3D gleichzeitig | ≤ 4 Systeme / 500 Partikel | ≤ 8 / 1000 |
| Texturspeicher | ≤ 350 MB (ASTC-Kompression im iOS-Export aktivieren) | — |
| Ziel-FPS | 60 auf iPhone 11+, 120-Hz nicht anvisieren | 60 |

Weitere Settings: MSAA 2× (Mobile verkraftet das, TAA gibt’s nicht), `scaling_3d/scale`
per Settings-Regler 0.75–1.0 für alte Geräte, `textures/vram_compression/import_etc2_astc=true`,
Shader-Hitches via 4.4-Pipeline-Precompile + WAIT_READY-Frames (§1.4) abfangen.
Mess-Werkzeug: `Performance.get_monitor()` auf Dev-Panel-Overlay (F-Taste/3-Finger-Tap).

---

## 8) Web-Code, der 1:1 als Logik portierbar ist

Muster bestätigt (stichprobenhaft gelesen): `.logic.js` sind pure Module (frozen Const-
Tabellen + Funktionen, keine three/DOM-Imports), inkl. eigener Tests unter `GOOBY/test/`.
Port-Regeln: JS-Objekt → `Dictionary` mit `StringName`-Keys, `Object.freeze` → Konvention
+ Test, seeded RNG → `RandomNumberGenerator(seed)`, Zahlen sind in beiden 64-bit-Float.
Tests aus `GOOBY/test/*.test.js` werden MIT portiert (§9-Runner).

**Minigame-Logik (`src/minigames/games/*.logic.js` → `res://logic/games/*_logic.gd`), 30 Stück:**
basketBounce, bubblePop, bunnyHop, burgerBuild, carrotCatch, carrotGuard, danceParty,
deliveryRush, fishingPond, gardenRush, ghostHunt, goalieGooby, goobySays, harborHopper,
hideSeek, lanternFloat, memoryMatch, miniGolf, pancakeTower, pipeFlow, purblePlace,
rocketRescue, runner, shoppingSurf, snailMail, starHopper, teaParty, toyRacer, trampoline,
veggieChop. — **NICHT portieren:** `goobyWelt.logic.js` (+`goobyWelt.paths.js`) — Splat-
Minigame wird laut §A entfernt. `cityDrive.js` hat keine `.logic.js` (Neu-Design nötig).
Dazu: `framework.logic.js` (Difficulty/Coin-Mult/Endless-Gates — wird `minigame_base.gd`-Kern).

**System-Logik (`src/systems/`), pure Kandidaten (~33):** economy, leveling, stats, health,
inventory, quests, garden, sleep, weather, weight, dailyBonus, achievementsEngine,
collections, stickerBook, profileStats, offline, notifyRules, musicRegistry, modifierEngine,
cutscene, recapEngine, recapDirector, recap, shopTrip, themePark, vacation, postcards,
gallery.logic, nougat.logic, radioQueue.logic, furniturePlacement. Fast pure (kleine
DOM-Berührung entfernen): codesEngine, dayNight.

**Pure Daten:** `home/rooms/*.js` (Raum-Definitionen → Basis der `.tscn`-Layouts),
`home/roomAudit.rules.js`, `home/ambientLife.data.js`, `data/constants.js`,
`ui/arcadeUi.logic.js`, `ui/modifierSurface.logic.js`, `ui/radioScreen.logic.js`.

**Nicht portierbar (Neuimplementierung in Godot):** sceneManager, loadingVeil, roomManager
(3D/DOM-gebunden — genau dafür sind §1/§4/§5 das Ersatz-Design), alle `games/*.js`-Render-
Hälften (werden `.tscn`-Szenen, die die portierte Logik konsumieren).

---

## 9) Headless-Testing (Godot 4.4, CI-tauglich)

**Empfehlung: eigener Mini-Runner, KEIN Addon (jetzt); gdUnit4 nur bei späterem Bedarf.**

Abwägung: gdUnit4 bietet Scene-Runner/Mocks/JUnit-XML, kostet aber eine Addon-Abhängigkeit
(Versions-Churn gegen 4.4.x, Update-Risiko — kollidiert mit der §B-Modularitäts-Idee) und
langsameren Start. Unsere Testmasse sind aber **Logik-Ports** (RefCounted, node-frei) —
dafür reichen ~120 LOC Runner. Migration zu gdUnit4 bleibt jederzeit möglich, weil Tests
klassenbasiert geschrieben werden.

```gdscript
# res://tests/run_tests.gd — Aufruf: godot --headless --script res://tests/run_tests.gd
extends SceneTree
func _initialize() -> void:
    var fails := 0; var total := 0
    for path in DirAccess.get_files_at("res://tests"):
        if not path.begins_with("test_"): continue
        var case = load("res://tests/" + path).new()   # extends TestCase
        for m in case.get_method_list():
            if m.name.begins_with("test_"):
                total += 1
                case._failures.clear()
                case.call(m.name)
                if case._failures.size() > 0:
                    fails += 1
                    print("FAIL %s::%s — %s" % [path, m.name, case._failures])
    print("tests: %d, failed: %d" % [total, fails])
    quit(1 if fails > 0 else 0)
```

`test_case.gd`: `class_name TestCase extends RefCounted` mit `assert_eq/assert_true/
assert_almost` (sammeln in `_failures` statt zu crashen). Konvention: 1 Logik-Port ⇒ 1
`tests/test_<name>.gd` (Zahlen aus den JS-Tests übernehmen — Bit-Gleichheit als Portbeweis).

**CI (GitHub Actions):** (1) Godot 4.4.1 headless binary cachen, (2) **zwingend zuerst
`godot --headless --import` laufen lassen** (frischer Checkout hat keinen `.godot/`-Import-
Cache — ohne diesen Schritt schlagen `load()` von Ressourcen fehl!), (3) Runner ausführen,
Exit-Code gated den Build. Lokal identisch: `godot --headless --import && godot --headless
--script res://tests/run_tests.gd`. Smoke zusätzlich: `godot --headless --quit` (Projekt
bootet fehlerfrei) als billigster CI-Job.

---

## Umsetzungsreihenfolge (Fundament zuerst)

1. **F0 — Projekt-Skeleton:** `project.godot` voll konfiguriert (Renderer mobile, Stretch,
   Orientation, Autoload-Liste), Verzeichnisse, `main.tscn`, Test-Runner + 1 Dummy-Test,
   CI-Workflow (`--import` + Tests). *~10 Dateien, ~400 LOC.*
2. **F1 — Autoloads:** EventBus, SaveManager (+Migrations-Stub), GameState, AppConfig-Stub,
   AudioDirector-Gerüst, OrientationService. *~7 Dateien, ~1.200 LOC.*
3. **F2 — SceneRouter + LoadingVeil:** Statemaschine, threaded Preload, WAIT_READY,
   beide Reise-Typen (DOOR_TRAVEL erst als Cut). *~4 Dateien, ~800 LOC.*
4. **F3 — UI-Fundament:** SafeAreaContainer, orientation-aware HUD-Gerüst, Vignette-Layer.
   *~6 Dateien, ~600 LOC.*
5. **F4 — CameraRig + RoomBase + 2 Räume** (bedroom, living; Geometrie aus
   `rooms/*.js`-Daten generiert oder in Blender gebaut), `env_home.tres`, Budgets-Overlay.
   *~12 Dateien, ~1.500 LOC.*
6. **F5 — DoorTransition** inkl. Gag + TapMash + Skip/Setting; DOOR_TRAVEL komplett.
   *~5 Dateien, ~900 LOC.*
7. **F6 — Logik-Ports Welle 1** (economy, stats, leveling, framework, 3 Minigame-Logiken)
   + Tests. *~20 Dateien, ~4.000 LOC.*
8. **F7 — Minigame-Framework-Szenen** (pregame mit Difficulty+Orientierung, results) und
   erstes spielbares Minigame end-to-end. *~8 Dateien, ~1.500 LOC.*

Danach übernehmen Bereiche B–H auf diesem Fundament. **Gesamt-Scope Engine-Fundament:
~70 Dateien / ~11.000 LOC GDScript+Szenen.** Voll-Port aller Logiken (30 Games + 33 Systeme
+ Tests) zusätzlich ~100 Dateien / ~20.000 LOC.

## Risiken

- **R1 — iOS-Orientation-Lock zur Laufzeit** (`screen_set_orientation`): funktioniert laut
  Godot-iOS-Backend (iOS-16-API), aber früh auf echtem Gerät testen; Fallback SubViewport-
  Rotation ist eingeplant (§2).
- **R2 — Shader-Compile-Hitches** beim ersten Reveal trotz 4.4-Precompile → WAIT_READY-
  Frames + ggf. unsichtbarer „Material-Warmup“-Quad im Veil.
- **R3 — DOOR_TRAVEL-Doppelbelegung** (2 Räume gleichzeitig im Speicher): Budget §7 pro
  Raum deshalb konservativ; Messen auf iPhone 11.
- **R4 — SpringArm-Zittern** bei freiem Möbelbau (§D): Layer-Disziplin (`camera_blocker`
  nur Großmöbel) muss ins FurnitureSlot-Datenmodell von Anfang an.
- **R5 — Port-Drift** JS→GDScript (RNG/Float-Reihenfolge): JS-Testzahlen als Fixtures
  übernehmen; jede Logik gilt erst als portiert, wenn ihre Zahlen-Tests grün sind.
- **R6 — Mobile-Renderer-Featurelücken** (kein SSAO/VolumetricFog): Design nutzt sie
  bewusst nicht; jede Grafik-Idee aus G/H gegen §6-Liste prüfen.
