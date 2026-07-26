# PHOTON EDITOR CAPABILITIES — Erkundungsbericht (Photon 2.1.5 / LDLib2 2.2.29)

**Auftrag:** Reine Erkundung + Bericht — was kann der Photon-Editor, was nutzen wir schon,
was nicht, und wie machen wir unsere Effekte damit krasser. Keine Code-Änderungen am Mod.

**Quellen (alle verifiziert, nicht aus dem Gedächtnis):**

- Jar-Inspektion (`unzip -l`, `javap -p/-c`, `strings`) von
  `run/mods-client/photon-neoforge-1.21.1-2.1.5.jar` und
  `run/mods-client/ldlib2-neoforge-1.21.1-2.2.29-all.jar`.
- Nutzungszensus über **alle 145 geshippten `.fx`** unter
  `src/main/resources/assets/eclipse/fx/**` (geparst mit `tools/photon/fxlib.py
  read_fx_file`, Skript einmalig unter `/tmp/fx_census.py`, nicht committet).
- Bestehende interne Doku: `docs/plans_v3/plans_v5/photon/FX_FORMAT.md` (Format-Referenz),
  `photon/API.md` (Runtime-API), `photon/INTEGRATION.md`,
  `plans_v5/v7/PHOTON-ADVANCED-1.md`/`-2.md` (Custom-Shader- & Runtime-Deep-Dive),
  `v7/PHOTON-QUALITY.md`, `v7/FX-STYLE-GUIDE.md`.
- Web: offizielles Wiki [low-drag-mc.github.io/LowDragMC-Doc/en/photon2/](https://low-drag-mc.github.io/LowDragMC-Doc/en/photon2/)
  (Introduction, Commands, Resource Pack Integration, Materials, CustomShaderMaterial,
  ExtendedShader), [GitHub Low-Drag-MC/Photon](https://github.com/Low-Drag-MC/Photon),
  [Modrinth "Photon Editor"](https://modrinth.com/mod/photon-editor), CurseForge,
  offizielles Tutorial-Video "[Photon2] Minecraft VFX Tutorial I" (Sub-Emitter,
  Force-Field-Shader mit Fresnel/HDR/Intersection-Highlight).

---

## 1. Der Photon-Editor: Was er ist und wie man ihn öffnet

Photon2 ist ein "Unity-Particle-System-Klon" für Minecraft (Selbstbeschreibung des
Autors: *"90%+ feature parity with Unity"*). Der In-Game-Editor ist ein LDLib2-Editor-
Fenster (`com.lowdragmc.photon.gui.editor.FXEditor extends lowdraglib2.editor.ui.Editor`)
mit Hierarchie-Baum (`FXHierarchyView`), 3D-Szenen-Vorschau (`SceneView`,
`FXObjectAnimationView`, `FXObjectInfoView`) und Ressourcen-Panels für **Curves,
Gradients, Materials und Meshes** (`gui/editor/resource/{Curve,Gradient,Material,Mesh}Resource`).

**Öffnen & Befehle** (aus `ClientCommands`/`ServerCommands`-Bytecode + offiziellem Wiki):

| Befehl | Zweck |
|---|---|
| `/photon_editor fx_editor` | öffnet den visuellen FX-Editor (Client-Command; nur Singleplayer sinnvoll; Wiki nennt kurz `/photon_editor` bzw. `/photon particle_editor` für ältere Versionen) |
| `/photon_client clear_client_fx_cache` | FX-Cache leeren — Pflicht nach jeder `.fx`-Änderung |
| `/photon_client clear_particles` | alle Photon-Partikel entfernen |
| `/photon fx <fxFile> block <pos> [offset] [rotation] [scale] [delay] [force death] [allow multi] [check state]` | FX an Block binden (Server-Command → S2C-Payload) |
| `/photon fx <fxFile> entity <selector> [... ] [auto rotation]` | FX an Entity binden |
| `/photon fx remove block/entity ...` | gebundene FX stoppen |

Es gibt **kein Item und keine GUI-Taste** — der Editor ist rein command-getrieben.
Workflow laut Wiki: Kreativwelt → `/photon_editor` → FX-Projekt anlegen → Echtzeit-Vorschau
→ *File → Export* schreibt die `.fx`; das Projekt selbst wird als `.fxproj` gespeichert
(Arbeitsverzeichnis `.minecraft/ldlib2/assets/…`, für Distribution nach `assets/<ns>/fx/`
kopieren — Seite "Resource Pack Integration"). Unsere Pipeline invertiert das: `fxlib.py`
generiert `.fx` **und** die `.fxproj`-Siblings (`python3 tools/photon/fxlib.py write_fxproj`),
d. h. **jedes unserer 128 Asset-Paare ist im Editor öffn- und tunebar**.

Editor-Preview läuft über `FXProjectEffectExecutor` in einer LDLib2-`DummyWorld` —
In-World-Playback dagegen über die vanilla `ParticleEngine` (Details: `photon/API.md` §1).

**Lizenz-Hinweis (GitHub):** Photon ist CC BY-NC-SA 4.0; *mit* dem Mod erstellte Inhalte
(unsere `.fx`) sind explizit frei lizenzierbar. Fürs Bundling des Jars gilt die
Non-Commercial-Klausel (bereits bekanntes Thema, siehe `CREDITS.md`).

---

## 2. Vollständiger Feature-Katalog (aus dem Jar verifiziert)

Kompakte Übersicht; die Byte-genaue Format-Referenz steht in
`docs/plans_v3/plans_v5/photon/FX_FORMAT.md` und wird hier nicht dupliziert.

### 2.1 Emitter-Typen (Registry `photon:fx_object`)

| Typ | Klasse | Kern-Fähigkeit |
|---|---|---|
| `particle_emitter` | `ParticleEmitter` | Unity-Partikelsystem: Billboards/Modelle, ~17 Module (s. u.) |
| `trail_emitter` | `TrailEmitter` | einfacher Emitter-folgender Trail-Strip (Catmull-Rom optional per GPU-Compute `catmull_rom.comp`) |
| `ara_trail_emitter` | `AraTrailEmitter` | Premium-Ribbon: **eigenes 2D-Querschnitts-Polygon** (`section.vertices` — Stern/Röhre statt flachem Band), Segment-**Physik** (`AraPhysicsSetting`: warmup/gravity/inertia/velocitySmoothing/damping — Ribbon schwingt nach!), Alignment View/Velocity/Local, `highQualityCorners` + `cornerRoundness`, thickness/color über Length/Time/SegmentTime, TextureMode Stretch/Tile/WorldTile |
| `beam_emitter` | `BeamEmitter` | Start→Ende-Beam, `width`/`emitRate`/`color` als NumberFunctions, **Raycast-Clipping** `NONE\|BLOCKS\|ENTITIES\|BLOCKS_AND_ENTITIES` (+ ClipContext-Modi) |
| `empty` | `EmptyFXObject` | Gruppierungs-/Pivot-Knoten (gemeinsame Transform-Animation für Kinder) |

### 2.2 Partikel-Module (ParticleConfig, `javap`-verifiziert)

Hauptblock: `duration/looping/prewarm/startDelay/startLifetime/startSpeed/startSize(3D)/
startRotation(3D)/startColor/simulationSpace(Local|World)/maxParticles/parallelUpdate/
parallelRendering`.

Immer aktiv: **emission** (Rate + `distanceRate` [Partikel pro gelaufenem Block!] +
Bursts mit cycles/interval/probability, Modus Exacting/Random), **shape**, **renderer**.

Toggle-Module: `physics` (echte Welt-Kollision + Bounce-Chance/-Rate/-Spread,
`removedWhenCollided`, collidedFriction), `lights` (erzwungenes Lightmap sky/block über
Lifetime — Fake-Glow, **kein** dynamisches Licht), `velocityOverLifetime` (linear +
orbital + radial + speedModifier), `inheritVelocity` (CURRENT/INITIAL × Multiplikator),
`lifetimeByEmitterSpeed`, `forceOverLifetime` (Beschleunigung, Local/World),
`colorOverLifetime`, `colorBySpeed`, `sizeOverLifetime`, `sizeBySpeed`,
`rotationOverLifetime`, `rotationBySpeed`, `noise` (Perlin 1D/2D/3D auf
Position/Rotation/Größe, mit **Remap-Kurve**), `uvAnimation` (Flipbook WholeSheet/SingleRow,
frameOverTime-Kurve, startFrame, cycle), `trails` (pro Partikel ein Ribbon; Typ TRAIL oder
ARA_TRAIL mit voll eingebetteter Config), `subEmitters` (spawnt **andere `.fx`-Dateien**
bei `Birth|Death|Collision|FirstCollision|Tick`, mit Inherit-Flags für
Color/Size/Rotation/Lifetime/Duration + Wahrscheinlichkeit), `additionalGPUDataSetting`
(per-Partikel-Kanäle an eigene Shader: random/t/age/lifetime/position/velocity/isCollided/
emitter_*).

### 2.3 Shapes (Registry `photon:shape`)

`dot`, `sphere`, `circle`, `cone`, `cylinder` (alle mit radius/radiusThickness/arc +
**ShapeArcMode** `Random|Loop|PingPong|BurstSpread` + arcSpeed — orbitierende
Emissionspunkte), `box` (Volume/Shell/Edge), **`mesh`** (Emission von den
Vertices/Edges/Triangles **jedes beliebigen gebackenen Modells**, `meshData.modelLocation`),
`function` (6 Ausdrucks-Strings x/y/z/speedX/Y/Z in Photons Mini-Expression-Sprache:
`t`, `PI`, `randomA–E`, sin/cos/…, Bedingungsoperator — **kein Molang**; alles andere
animiert über Bézier-Kurven). ShapeSetting hat zusätzlich position/rotation/scale als
NumberFunction3 über Emitter-t → **animierbarer Emissionsursprung**.

### 2.4 Renderer & Materialien

- RenderModes: `None|Billboard|Horizontal|Vertical|VerticalBillboard|StretchedBillboard|Model`
  (Model = Partikel **als gebackenes Modell** gerendert, `useBlockUV` + block_atlas).
- FacingModes: `DEFAULT|ROTATE_Y|LOOKAT_XYZ|LOOKAT_Y|LOOKAT_DIRECTION|DIRECTION_X/Y/Z|
  EMITTER_TRANSFORM_XY/XZ/YZ` + FacingDirection (DERIVE_FROM_VELOCITY/CUSTOM_DIRECTION).
- **Multi-Material = Multi-Pass**: `renderer.materials` ist eine Liste; jeder Eintrag hat
  eigenen BlendMode (GL-Faktoren + Blend-Gleichung ADD/SUB/REVERSE_SUB/MIN/MAX), cull,
  depthTest, depthMask.
- Materialtypen: `texture` (PNG + `discardThreshold` + **HDR-Boost → Bloom** + PixelArt-AA),
  `sprite` (Partikel-Atlas-Sprites, inkl. animierter `.mcmeta`), `block_atlas`,
  **`custom_shader`** (eigene Core-Shader-JSON + GLSL; Kurven/Gradienten werden als
  128×128-LUTs hochgeladen), `ui_resource_material`, `missing`.
- Sonstiges: Layer Opaque/Translucent, `orderInLayer`, `vertexSortingMode NONE|DISTANCE`,
  **Cull-Box** (AABB-Render-Culling), `useGPUInstance` (GPU-Instancing-Pfad,
  `ParticleInstanceRenderer`), Render-Pass-Pipeline (`PhotonFXRenderPass`).

### 2.5 Custom-Shader / ExtendedShader (Wiki + Jar)

Photon2/LDLib2 erweitern Vanilla-Core-Shader (`ExtendedShader`):

- **Geometry-Shader** (`attach`) möglich; `#version 330 core` + `#moj_import
  <photon:particle.glsl>` → `getParticleData()` abstrahiert das Vertex-Layout
  (funktioniert für CPU- und GPU-Instance-Pfad gleich).
- Extra-Sampler: `Sampler2` (Lightmap), **`SamplerSceneColor`** (Welt-Farbe),
  **`SamplerSceneDepth`** (Welt-Tiefe → Soft Particles / Intersection-Highlights!),
  `SamplerCurve`/`SamplerGradient` (authored LUTs, `getCurveValue()`/`getGradientValue()`
  aus `photon:particle_utils.glsl`).
- Extra-Uniforms: `U_CameraPosition`, `U_InverseProjectionMatrix`, `U_InverseViewMatrix`,
  `U_ViewPort`. **Jede eigene Uniform wird automatisch als Editor-Knopf/Colorpicker im
  Inspector angezeigt und im `.fx` persistiert** (bestätigt durch Wiki + Tutorial-Video).
- Shader-Dateien müssen unter `assets/<ns>/shaders/core/` liegen; "Reload Shader"-Knopf
  im Editor. Kopiervorlagen: `assets/photon/shaders/core/{hdr_particle,sprite_hdr_particle,
  pixel_hdr_particle,circle}.json/.fsh` im Jar.
- Bloom-Pipeline im Jar: bright_pass → down/up_sampling → `unreal_composite` bzw.
  Scatter-Modus; Config `photon-client.toml` (enable_bloom, bloom_threshold/intensity,
  Iris-Kompatibilitätsmodus via Mixins in `core/mixins/iris`).

Der vollständige Deep-Dive inkl. auto-verdrahteter Sampler steht schon in
`v7/PHOTON-ADVANCED-1.md` §1 — vom offiziellen Wiki jetzt extern bestätigt.

### 2.6 Was Photon NICHT hat (negative Befunde, verifiziert)

- **Kein LOD-System** (PHOTON-ADVANCED-1 §5; im Jar existiert nichts dergleichen —
  "LOD/Culling" = nur Cull-Box + maxParticles + Distanz-Sortierung).
- **Kein Molang** — nur die eigene `expr`-Minisprache im `function`-Shape.
- **Keine dynamischen Welt-Lichter** — `lights` ist nur Lightmap-Forcing (Quasar/Veil
  bleibt dafür zuständig, siehe FX_FORMAT.md §7).
- **Keine Force-Field-/Attractor-Primitive** wie Unity — Kraftfelder baut man aus
  `forceOverLifetime` + `noise` + orbital velocity + `function`-Shape.
- Kein Sound-Hook, kein Server-Spawn-API (alles client-seitig; unsere Payload-Lane ist
  das richtige Muster — API.md §4, PHOTON-ADVANCED-2 §5).

---

## 3. Nutzungszensus: Was unsere 145 `.fx` heute wirklich verwenden

426 FX-Objekte insgesamt (25 Dateien mit 1 Emitter, Maximum 10; Median 2–3).

| Dimension | Genutzt | Auffällig ungenutzt/selten |
|---|---|---|
| Emitter-Typen | particle 345 · beam 38 · empty 29 · **ara_trail 14** | standalone `trail_emitter`: **0** (bewusst — ara ist besser) |
| Module (aktiviert) | colorOverLifetime 310 · sizeOverLifetime 181 · velocityOverLifetime 130 · lights 127 · noise 54 · physics 44 · trails 31 (25× ARA_TRAIL, 6× TRAIL) · rotationOverLifetime 31 · uvAnimation 16 · subEmitters 9 | **sizeBySpeed 0 · rotationBySpeed 0 · lifetimeByEmitterSpeed 0 · additionalGPUData 0** · forceOverLifetime 2 · colorBySpeed 2 · inheritVelocity 3 |
| Emission | Bursts 229 · Rate-Loops überall | **distanceRate: 0** (!) |
| Shapes | dot 86 · sphere 76 · circle 66 · cone 32 · function 31 (18 Dateien) · box 23 · cylinder 20 · mesh 11 | mesh nur in 7 Dateien; Mesh-Emission von **eigenen** Eclipse-Modellen: 0 (nur Vanilla-Modelle) |
| RenderModes | Billboard 273 · Stretched 27 · Horizontal 26 · Model 9 · Vertical(B) 10 | — |
| FacingModes | DEFAULT 339 | LOOKAT_XYZ 3 · EMITTER_TRANSFORM_XY 2 · ROTATE_Y 1 — praktisch ungenutzt |
| Materialien | texture 391 · block_atlas 9 | **custom_shader: 0 · sprite: 0** · Multi-Material nur 3 Dateien (`warden_glitch_orbit`, `glitch_pop`, `shadow_bolt_impact`) |
| NumberFunctions | constant 8584 · random_constant 1158 · curve 657 · gradient 394 | random_curve 19 · random_gradient 5 · random_color 15 (wenig Variation zwischen Wiederholungen) |
| Beam-Raycast | BLOCKS 12 · BLOCKS_AND_ENTITIES 1 | NONE 25 (einige Laser clippen nicht) |
| Perf/Sonstiges | HDR-Bloom 253 Materialien (!) · CullBox 100/145 Dateien · DISTANCE-Sort 74 · prewarm 46 | **useGPUInstance nur 5 Emitter in 3 Dateien** (`end_void_wisps`, `era_dust_motes`, `storm_cloud_belt`) · parallelUpdate/Rendering je 10 · noise-**Remap-Kurve 1/54** |
| SubEmitter-Events | Collision 4 · FirstCollision 3 · Death 3 · Tick 1 | **Birth: 0** |

### Stichproben (per `fxlib`-Parse gedumpt)

- **`storm_burst_shockwave.fx`** (5 Objekte): `empty`-Root + 2 Horizontal-Ringe (dot-Shape,
  HDR ~1.9/1.7/2.6) + Staub & Funken über `function`-Shape mit noise. Solide — aber:
  ein Material pro Emitter (kein Multi-Pass-Ring), Funken ohne `colorBySpeed`/`sizeBySpeed`,
  keine Trails an den Funken, kein Boden-Intersection-Glow.
- **`day_rift_maw.fx`** (4 Objekte): Rauch (circle), Puls (dot), Drips
  (StretchedBillboard). Kein noise auf dem Rauch, kein custom_shader-Verzerrungseffekt
  am "Maul", subEmitters ungenutzt (Drips könnten beim Aufprall spritzen — Collision-Event).
- **`nether_pit_plume.fx`** (4 Objekte, Loop): sehr sauberer Layer-Aufbau
  (Rauch/Feuer/Funken/Glut, noise + Stretched + HDR), aber Rauch ist Einzeltextur statt
  **UV-Flipbook**, Funken haben keine `trails`, Emitter läuft ohne GPU-Instancing trotz
  Dauerschleife mit ~230 maxParticles gesamt.

---

## 4. Abdeckung `tools/photon/fxlib.py` vs. Editor-Featureset

`fxlib.py` (2134 Zeilen, CLI: `selfcheck | templates | validate [--lint] | write_fxproj |
dump <file>`) ist der Haus-Standard und deckt **fast das komplette Format** ab:

**Vorhanden:** alle 5 Objekt-Typen (`ParticleEmitter`, `BeamEmitter`, `TrailEmitter`,
`AraTrailEmitter` inkl. `section`-Querschnitt, `EmptyObject`), alle 8 Shapes, alle
NumberFunction-Typen inkl. random_curve/random_gradient, alle Toggle-Module inkl.
`sub_emitter()`-Helper mit Inherit-Flags, `with_physics`, `with_lights`, `with_cull_box`,
`use_gpu_instance`, `additional_gpu_data`, Multi-Material (`with_material` mehrfach),
alle 4 Materialtypen inkl. **`custom_shader_material(shader=…, curves=…, gradients=…)`**,
`distance_rate`-Parameter in `with_emission`, `prewarm`, `parallel_*`, Facing-Modes über
`with_renderer(facing_mode=…)`, Lint-Kanal mit Baseline.

**Lücken (klein):** kein Builder-Convenience für `lifetimeByEmitterSpeed`
(nur generisch über `with_module`), Validator prüft Nicht-Partikel-Configs nur generisch
(bekannt, EVAL-V6-PHOTON §1). Fazit: **Die Gaps liegen nicht im Tooling, sondern in der
Asset-Nutzung** — jedes unten vorgeschlagene Feature ist mit fxlib heute schon baubar
(Ausnahme: neue GLSL-Dateien müssen zusätzlich unter `assets/eclipse/shaders/core/`
angelegt werden).

---

## 5. Gap-Analyse — die mächtigen ungenutzten Hebel

1. **`custom_shader`-Material (0 Nutzungen)** — der größte einzelne Hebel. Damit gehen:
   Soft Particles / Intersection-Highlight (`SamplerSceneDepth`), Fresnel-Schilde,
   Screen-Distortion via `SamplerSceneColor`, RGB-Split/Datamosh für die GLITCH-Palette,
   authored Curve/Gradient-LUTs, live tunebare Uniform-Knöpfe im Editor.
2. **`sprite`-Material (0)** — animierte Vanilla-/eigene Atlas-Sprites gratis
   (inkl. `.mcmeta`-Animation) statt statischer PNGs.
3. **`distanceRate`-Emission (0)** — bewegungsproportionale Emission; perfekt für alles,
   was an Entities hängt (Dash-Trails, Contrails, Glide).
4. **Speed-Mapping-Trio `sizeBySpeed`/`rotationBySpeed`/`colorBySpeed` (0/0/2)** +
   `inheritVelocity` (3) + `lifetimeByEmitterSpeed` (0) — die komplette "Partikel
   reagieren auf Bewegung"-Achse liegt brach.
5. **SubEmitter-Event `Birth` (0) und tiefere Ketten** — Ketten aus 2–3 `.fx`-Stufen
   (Komet → Birth-Glints → Collision-Splash) sind heute maximal 1-stufig.
6. **Ara-Trail-Vollausbau** — wir nutzen ara_trails, aber (Stichproben) ohne
   Custom-Querschnitt (`section`), ohne Segment-Physik (inertia/damping) und ohne
   `highQualityCorners`.
7. **Mesh-Emission von eigenen Modellen** — `mesh`-Shape kann jedes gebackene Modell;
   wir emittieren nur von Vanilla-Geometrie, nie von Eclipse-Modellen (Altar, Statue,
   Boss-Teile).
8. **GPU-Instancing + `additionalGPUData` (5 Emitter / 0)** — Zehntausende Partikel +
   Shader-seitige Animation wären möglich; unsere Ambient-Loops laufen fast alle auf dem
   CPU-Billboard-Pfad.
9. **Noise-Remap (1/54)** — Remap-Kurven machen aus gleichmäßigem Wobble "billowing"
   (Böen, Pulse); praktisch ungenutzt.
10. **Facing-Modes & Multi-Material** — LOOKAT/DIRECTION-Modi (z. B. Ringe, die immer
    zur Kamera kippen, Shards entlang Velocity) und Additive+Alpha-Doppel-Pass auf einem
    Emitter werden kaum eingesetzt.
11. **Variation über `random_gradient`/`random_curve`** — wiederholte Effekte (Wand-Casts,
    Mob-Deaths) sehen jedes Mal identisch aus; 5/19 Nutzungen insgesamt.
12. **Kein LOD in Photon** → unser Gegenstück bleibt CullBox (100/145 ✔) + maxParticles +
    Budget im `PhotonBridge`; die 45 Dateien ohne CullBox sind der billigste Perf-Fix.

---

## 6. Ideen-Katalog — 18 konkrete, priorisierte Vorschläge

Aufwand: **S** = nur fxlib-Generator-Änderung an bestehendem Asset · **M** = neues
Texture-/Shader-Asset oder neues Child-`.fx` nötig · **L** = neue GLSL-Pipeline +
Iterationsschleife im Editor. "Gewinn" = erwarteter visueller Sprung.

### P1 — Signature-Hebel (zuerst bauen)

| # | Effekt | Feature | Erwarteter Gewinn | Aufwand |
|---|---|---|---|---|
| 1 | `arena_mist_wall.fx`, `boss/tyrant_fog_arms.fx`, `day_rift_maw.fx` (Rauch) | **Soft Particles**: `custom_shader` mit `SamplerSceneDepth` — Alpha nahe Geometrie ausblenden | Nebel/Rauch schneidet nicht mehr hart in Blöcke; sofort "AAA-Look" für alle Volumetrics; ein Shader, viele Abnehmer | L (einmalig), danach S pro Asset |
| 2 | Boss-Schild/Dome (`boss_intro_shockwave`-Dome, Arena-Barriere) | **Fresnel-Force-Field**-Shader (offizielles Tutorial-Rezept): Fresnel-Term + HDR-Uniform + Intersection-Highlight, Mesh/Sphere-Emission | Halbtransparente Energiekuppel mit leuchtender Kante + Glow-Ring wo sie Boden/Wände berührt — bester "Boss-Phase"-Marker | L |
| 3 | `riss_glitch_pop.fx`, `glitch_pop.fx`, `boss/warden_glitch_orbit.fx` | **RGB-Split/Datamosh-Shader**: `custom_shader` + `SamplerSceneColor` (UV-Offset pro Kanal), Glitch-Stärke als Curve-LUT | Die GLITCH-Palette (FX-STYLE-GUIDE §1.3) bekommt echtes Chromatic-Aberration-Flackern statt nur Flipbook-Sprites | L |
| 4 | `hound_dash_trail.fx`, `supply_drop_contrail.fx`, `glide_trail.fx` | **`distanceRate`-Emission** statt/zusätzlich zu Rate | Dichte skaliert mit Tempo: schneller Dash = dichter Staub, Stillstand = nichts. Ein-Zeilen-Änderung pro Emitter | S |
| 5 | `stern_komet_fall.fx` → Komet | **Birth-SubEmitter-Kette**: Komet-Partikel spawnen bei Birth Micro-Glints (`_glint`-Child-fx), bei FirstCollision den bestehenden Impact | Dreistufige Effekt-Hierarchie; Funkenregen der dem Kometen "entfällt", ohne den Haupt-Emitter zu verkomplizieren | M (1 Child-Asset) |
| 6 | `boss/herald_shard_trail.fx`, `credits_contrail.fx` | **Ara-Querschnitt + Segment-Physik**: `section` = Stern/Dreieck-Polygon, `inertia`/`damping` an, `highQualityCorners` | Trails werden volumetrische, nachschwingende Bänder statt flacher Streifen — größter Ribbon-Sprung für 5 Zeilen | S |

### P2 — Bewegungs- & Reaktions-Paket (billig, breit wirksam)

| # | Effekt | Feature | Erwarteter Gewinn | Aufwand |
|---|---|---|---|---|
| 7 | `storm_skirt_dust.fx`, `storm_burst_shockwave.fx` (shock_dust) | **`sizeBySpeed` + `rotationBySpeed`** | Staub, der im Böenkern größer wird und schneller rotiert — "Wind hat Kraft"-Gefühl | S |
| 8 | `shock_sparks` (storm_burst), `boss/roar_shockwave.fx` | **`colorBySpeed`**: weißglühend bei hoher Geschwindigkeit → Ember-Orange beim Abbremsen | Physikalisch lesbare Funken; passt exakt zur STORM-Palette | S |
| 9 | alle Entity-Loop-Auren (Mob-FX aus `mobs_fx.py`) | **`inheritVelocity` (CURRENT, 0.4–0.8)** | Auren "reißen" realistisch nach, wenn der Mob sich bewegt, statt statisch zu kleben | S |
| 10 | `boss/warden_eye_laser.fx` + 24 weitere NONE-Beams | **Beam-Raycast BLOCKS** flächendeckend (12/38 nutzen es schon) | Laser/Strahlen enden an Wänden statt durchzuclippen; + Impact-Puff am Endpunkt als separates fx | S |
| 11 | `day_rift_maw.fx` (maw_drip) | **Collision-SubEmitter**: Drips spawnen Mini-Splash-fx bei Bodenkontakt (physics ist schon da) | Tropfen "landen" sichtbar — Detailtiefe für 1 Child-Asset | M |
| 12 | `nether_pit_plume.fx`, `breach_ash_geyser.fx` (Rauch) | **UV-Flipbook** (8×8-Sheet, `frameOverTime`-Kurve) | Filmischer, rollender Rauch statt statischer Wolken-PNGs; ein Sheet, viele Abnehmer | M (Textur-Autoring) |

### P3 — Skalierung, Geometrie & Variation

| # | Effekt | Feature | Erwarteter Gewinn | Aufwand |
|---|---|---|---|---|
| 13 | `altar_corona_idle.fx` | **Mesh-Emission vom Altar-Modell** (`mesh`-Shape, Edge-Modus, eclipse-Modell-Location) | Corona folgt exakt der Altar-Silhouette statt generischer Kugel — "das Objekt selbst glüht" | M |
| 14 | `era_dust_motes.fx`, `end_void_wisps.fx` (haben schon GPU) + `arena_mist_wall.fx`, `storm_cloud_belt.fx` | **GPU-Instancing breit ausrollen** + `additionalGPUData` (age/velocity) + Wobble im Vertex-Shader statt CPU-noise | 5–10× Partikelbudget für Ambient-Felder bei weniger CPU-Last; Grundlage für spätere Shader-Ideen | M |
| 15 | `storm_burst_shockwave.fx` (shock_ring) | **Multi-Material-Doppel-Pass**: additiver HDR-Kern + alpha-geblendeter Rauchrand auf demselben Ring-Emitter (Vorbild `shadow_bolt_impact.fx`) | Reichere Ringe ohne zweiten Emitter; weniger Objekte pro Datei | S |
| 16 | Wiederholte Casts (`wand2_fx.py`-Rows, Mob-Deaths) | **`random_gradient`/`random_curve`** statt fixer Gradienten | Jede Wiederholung sieht leicht anders aus — bekämpft "Partikel-Loop-Müdigkeit" | S |
| 17 | `boss/tyrant_fog_arms.fx`, `maw_smoke` | **Noise-Remap-Kurve** (`remap._enable` + Stufen-Kurve) | Böiges "Billowing" statt gleichmäßigem Perlin-Wobble; nur 1/54 noise-Nutzern hat das heute | S |
| 18 | die 45 Dateien ohne CullBox + Loops ohne `prewarm` | **CullBox-/Prewarm-Audit** (Photon hat kein LOD — das ist unser Ersatz) | Gratis-Perf + kein Kaltstart-Pop-in bei Loops; passt zur bestehenden Lint-Pipeline (`LINT`-Regel ergänzbar) | S |

### Ausdrücklich NICHT empfohlen

- Standalone `trail_emitter` reaktivieren (ara_trail ist strikt besser; 0 Nutzungen sind korrekt).
- `lights`-Modul als "echtes Licht" verkaufen — es bleibt Lightmap-Forcing; dynamische
  Lichter weiterhin über die Veil/Quasar-Lane (FX_FORMAT.md §7).
- Molang-artige Logik erzwingen — Photons `expr` gibt es nur im `function`-Shape; alles
  andere gehört in Bézier-Kurven (sonst kämpft man gegen das Format).

---

## 7. Empfohlene Reihenfolge

1. **Shader-Grundstein** (Ideen 1–3): ein `assets/eclipse/shaders/core/`-Setup + drei
   Fragment-Shader (soft-particle, fresnel, rgb-split). Einmalige L-Investition, danach
   ist jedes weitere custom_shader-Material eine S-Änderung in fxlib
   (`custom_shader_material()` existiert bereits ungenutzt).
2. **Bewegungs-Paket** (Ideen 4, 7–10): reine Generator-Flags, ~1 Sitzung, betrifft
   >20 Assets sichtbar.
3. **Ketten & Geometrie** (Ideen 5, 6, 11, 13): je 1 Child-Asset bzw. Modell-Referenz.
4. **Skalierung & Politur** (Ideen 12, 14–18).

Iterations-Workflow für alles davon: Asset per Generator bauen → `.fxproj` committen →
im Editor (`/photon_editor fx_editor`) öffnen und live tunen (Uniform-Knöpfe!) → Werte
zurück in den Generator portieren (Haus-Regel aus `INTEGRATION.md` §6) →
`/photon_client clear_client_fx_cache` zum Testen.
