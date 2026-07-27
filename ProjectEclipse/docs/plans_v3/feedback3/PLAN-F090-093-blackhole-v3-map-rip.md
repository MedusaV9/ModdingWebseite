# PLAN F-090/F-093 — Black-Hole Finale "Map-Zerreißen V3" (map-rip)

> **Feedback** (UserFeedback.md, F-090 + F-093): _"Die Credits Scene muss noch mehr
> verbessert werden."_ + _"Das Schwarze loch ist nicht krass genug die Map soll richtig
> kaputt gerissen werden mit heftigen Animations und Effekten."_
> Long-standing user preference: **depth & height & MASS** — thousands of BlockDisplays,
> huge scale.
>
> Naming note: code comments already use "F-072 V3" for the previous polish pass. This
> plan is the **feedback-facing V3 ("Map-Zerreißen V3")** — in code lineage it is the
> 4th pass (F-056 → F-068 → F-072 → **F-090/093**). All new cue/asset ids therefore use
> the `credits4_` prefix to avoid colliding with the shipped `credits3_*` assets.

---

## 1. Current state (audited 2026-07-27)

### 1.1 Key files

| Layer | File | Role |
|---|---|---|
| Server controller | `src/main/java/dev/projecteclipse/eclipse/ritual/CreditsSequence.java` | Time-driven phase machine for the whole credits run; owns every payload send, all beats, the display budget (`DISPLAY_HARD_CAP = 3600`), stray-sweep, skip/end_event/replay |
| Server act | `ritual/CreditsBlackHoleAct.java` | Black-hole finale stage manager: vantage/anchor geometry, terrain-palette sampling, 840 recycled accretion displays, gulp (`swallowPulse`) + flicker (`horizonFlash`) schedules |
| Server acts (siblings) | `ritual/CreditsShatterAct.java`, `ritual/CreditsFormationAct.java` | Island shatter prologue (~1400+420 displays), beach formation backdrop (1800 displays) — pattern donors for the new act |
| Config | `ritual/CreditsConfig.java` | `creditsEnabled` (common), `allowFinaleClose` (client) |
| Network | `network/credits/CreditsPayloads.java` | `begin/auto_run/roll/title/close/fov/sky/pulse` payloads (version group `credits2`), installable client consumer seams |
| Network (shared FX) | `network/fx/FxPayloads.java`, `network/fx/FxCues.java`, `network/S2CShakePayload.java`, `network/fx/S2CScreenFadePayload.java` | `S2CFxEventPayload(id, pos, a, b)` cue bus (`FX_SHOCKWAVE`, `CUE_BLACK_HOLE = eclipse:fx/cue/black_hole`, …), camera shake, screen fades |
| Client sky/post state | `client/credits/CreditsSkyFx.java` | Eased `skyDarken`/`starBrightness`/`holeAmount` scalars + the gulp `Pulse` envelope (3t attack / 15t decay) |
| Client post pass | `client/credits/CreditsBlackHolePostFx.java` | Veil pipeline `eclipse:black_hole` (FEATURE priority), feeds `Strength/Hole/Aspect/Time/Detail/Pulse`; hole center re-projected per frame via `SunTracker.worldToNdc` |
| Shader | `src/main/resources/assets/eclipse/pinwheel/shaders/program/black_hole.fsh` (+ `post/black_hole.json`, `program/black_hole.json`) | Lensing pull+swirl, chromatic aberration, event horizon + photon ring + Einstein sub-ring with beads, Doppler accretion bands + orbiting hotspots, polar jets, infalling star streaks, lensed starfield, "Ergrauen" desaturation, Pulse breathing |
| Photon rows | `veilfx/CreditsFinaleFxRows.java`, `veilfx/CreditsFinale3FxRows.java` | Register `black_hole_maw`, `credits_collapse`, `credits3_precrack`, `credits3_nebula` (AMBIENT / LAYER, null Quasar leg) |
| Photon assets | `assets/eclipse/fx/black_hole_maw.fx`, `credits3_nebula.fx`, … authored by `tools/photon/credits2_fx.py` / `credits3_fx.py` (fxlib) | Never hand-edit the gzip-NBT — regenerate + `python3 tools/photon/fxlib.py validate` |
| Client cards | `client/credits/TitleCardLayer.java` (`STYLE_FINALE` dust-materialize), `client/credits/CreditsPanel.java`, `client/credits/CreditsClient.java` (nonce, FOV ramp, HUD suppression, guarded close) | |
| Dev commands | `devtools/dev/DevCreditsCommands.java` (`/dev credits start|skip`, `/dev end_event`), `devtools/dev/DevReplayCommands.java` (`/dev replay play credits <PHASE>`) | |

### 1.2 The finale shot & the screen-alignment trick

Beats (run ticks): `T_FINALE_TELE = 3640` (players parked frozen+invisible at the
vantage, FOV crushed to `0.25`, SPACE sky armed at 0.35, `victory_theme` starts) →
`T_FINALE_REVEAL = 3720` (black releases) → `T_FINALE_DARK = 5020` (melt to black; the
devour window is exactly `CreditsBlackHoleAct.SPIRAL_TICKS = 1300`t = 65 s) →
`T_FINALE_TITLE = 5200` → `T_FINALE_HOLD = 5240` (players home, displays discarded,
black held until `/dev end_event`).

Geometry (`CreditsBlackHoleAct.prepare`): hole center = sanctum column, `islandTop +
30`; vantage = `430` blocks south, `y = 300`. **The true hole center is outside both
chunk render distance and display tracking range — nothing visual is staged there.**
Every display and the Photon maw anchor at `fxAnchor()` = 110 blocks along the exact
view ray; through the crushed FOV the ~26-block-radius authored maw reads ~4.3× larger,
pixel-aligned with the true center, which the post pass projects independently per
frame. **Consequence (the root of F-093): the real map is never actually in frame
during the finale — the "map being eaten" is currently carried ONLY by 840 recycled
generic terrain-palette cubes spiraling at the anchor. Nothing that looks like THE map
ever visibly breaks.** That is what V3 fixes.

### 1.3 How terrain "swallowing" works today

- `sampleTerrainPalette`: 96 golden-angle surface columns out to r = 170 around the
  hole column, top block + ~50% hashed strata picks → a **palette** (list of
  BlockStates), NOT a spatial model of the map.
- `COUNT = 840` BlockDisplays in 140 tear-off clusters of 6 (shared shell slot, launch
  phase, palette pocket), spawned 48/t, all parked at `fxAnchor`, animated by absolute
  poses (pure function of `(index, actTick)` — the stateless-push law) on
  `PUSH_STRIDE = 10`t interpolation windows.
- Infall: accretion shell radius 24–92 (anchor frame), 3 tilted ring planes, disc
  squash 0.55, accelerating spiral (`(1-q)^1.45`), spaghettification from q = 0.72
  (radial stretch → 2.6×, inverse-sqrt crosswise thinning, slerp to radial alignment),
  heat-ignite at q = 0.78 (magma/shroomlight full-bright), filament arc-trailing
  (+0.34 rad/member), swallow drain from q = 0.88, per-cluster recycle every 460–700t.
- Doppler brightness ladder (sky 3–13), refreshed 1/4 of the field per push wave,
  NBT writes only on value change (cached).
- Server-side dramaturgy: maw + nebula cue re-fired every 300t; 6-step sky/post
  intensity ladder (offsets 120…1100, 0.45 → 1.0, 260t eased ramps); gulps every
  ~115t±34 (shockwave ring (0.3+0.35p, 18) at the anchor + white-violet blink + shake +
  Pulse payload + thump); weak horizon flashes every ~47t±21; ambient tremor every 80t
  (0.06 → 0.12); 4-waypoint FOV beat-map (0.275 → 0.215 dolly-push).

### 1.4 Current performance measures & budget

- Hard cap **3600** live credits displays of all kinds (`LIVE_DISPLAYS` set,
  `capReached` logs once, spawns beyond are dropped).
- F-068 audited concurrent worst cases: beach act ≈ 2570, shatter act ≈ 1820,
  **black-hole act = 840** — the finale is by far the emptiest phase; ~2700 of budget
  is idle exactly when the user wants maximum violence.
- Push cost today: 840/10 ≈ 84 entity transform updates/t (worst audited case
  elsewhere in the sequence ≈ 185/t + strided brightness writes).
- All spawns budgeted (48/t), `view_range` widened to 4.0, brightness/state NBT writes
  edge-triggered only, every act discards behind a fade + belt-and-braces in
  `endEvent`, `TAG`-based crash-stray sweep on entity join.

### 1.5 Existing audio hooks

- Music: `MusicCues.play("victory_theme", …)` at TELE (asset frozen at 3600t);
  `day_final`, `title_theme` earlier. No dedicated finale SFX assets.
- SFX today are vanilla events fired server-side (`playNotifySound`):
  `END_PORTAL_SPAWN` (maw drone + gulp thump), `LIGHTNING_BOLT_THUNDER`,
  `DEEPSLATE_BREAK`, `GENERIC_EXPLODE`.
- **Registered mod sounds that fit the rip and are unused here**:
  `EclipseSounds.EVENT_END_SHATTER_RUMBLE` / `EVENT_END_SHATTER_CRACK`
  (`event.end_shatter_rumble/crack` in `sounds.json`, used by `EndShatterSequence`).

---

## 2. V3 design — "Map-Zerreißen": make the destruction physical

### 2.0 The core move: a pixel-aligned map effigy that rips apart

Extend the anchor-frame trick from a maw-only stage to the **whole map**: at prepare
time, sample the REAL overworld disc as a coarse **heightmap grid** (position + top
BlockState + strata per cell) and build a **1 : 3.9 scale replica** of the visible disc
sector along the true line of sight (`replicaPos = vantage + (realPos − vantage) ×
(ANCHOR_AHEAD / VANTAGE_DIST) ≈ × 0.256`). Because every replica cell sits ON the view
ray of its real counterpart, the effigy is **pixel-aligned with where the real map
would be** — when the black releases, players see *their* map (real biome colors, real
shorelines, the sanctum scar) lying under the hole. Then it gets torn apart. The world
itself is never modified (Kulisse law, same as the shatter act).

Evaluation of the proposed idea set (kept / cut):

| Idea | Verdict |
|---|---|
| Continent-scale crust plates | **KEEP** — the centerpiece; carried by the effigy grid |
| Crack fronts before liftoff | **KEEP** — sells "gerissen", cheap (seam displays + Photon + shake) |
| Underside reveal | **KEEP** — bedrock slabs + hanging stalactite displays, recycled pool |
| Gravity waves | **KEEP** — traveling sine bob on un-lifted cells + surface stripping; very cheap (pose-side only) |
| Ejecta / relativistic jets | **KEEP (scoped)** — jets already exist in the shader; add a `JetPulse` flare + display "plate shred" sprays; a separate Veil beam pass is CUT (post pass already draws the jets — a second geometry beam would double-draw, the storm "eggshell" lesson) |
| Sound | **KEEP** — layered from existing registered sounds; optional new shepard-riser OGG as polish |
| LOD | **KEEP** — far/rim cells merge 2×2 at 2× scale |

### 2.1 The effigy grid (sampling + LOD)

- Sample radius = current stage radius (`RingGrowthService`; stage-0 main disc 96,
  stage-1+ ≥ `PLAYER_DISC_RING_RADIUS + PLAYER_DISC_RADIUS = 194`), clamped to 220.
- Only the **camera-facing ~200° sector** is built (the far sliver hides behind the
  maw/horizon glow and the space dome).
- **LOD**: near half (map distance from vantage-side rim < 55%) grid step **6** map
  blocks → display scale ≈ 1.53 anchor-frame; far half step **10** → scale ≈ 2.56
  ("far plates = fewer, bigger displays"). Budget-first sampling: steps are widened
  until cell count ≤ **1300**. Expected ≈ 1250 crust cells.
- Per cell: real top BlockState (`MOTION_BLOCKING_NO_LEAVES`, fluid → seabed block
  under it), 1 hashed strata state (for the flank of lifted plates), cell height →
  a small per-cell y-offset in the effigy so the replica has real relief
  ("depth & height").
- Sampling is **budgeted** (≤ 60 columns/t) across the post-card black window
  (t ≈ 3400 → 3640) — ~1300 forced chunk reads never land in one tick. Spawn (30/t,
  identity poses, dim space brightness sky 5/block 2) also completes behind the black:
  the reveal at 3720 opens on the finished intact map.

### 2.2 Tectonic plates

- The sector is carved into **40 plates** by a hashed Voronoi over 40 golden-angle
  seeds (deterministic from the run nonce): **5 mega-plates** (~70 cells), **15 large**
  (~36), **20 medium** (~18) → ≈ 1250 members. Poly-region carving = nearest-seed
  assignment; ragged edges come free from the grid resolution.
- **Rigid-body fake** (per the stateless-push law): member pose =
  `plateOrigin(t) + R_plate(t) · (cellOffset − plateCentroid)` with a shared
  `R_plate` quaternion (tilt + spiral) and per-member jitter only in the tumble
  during shred/filament phases. One transform "root" is faked exactly as requested —
  per-plate origin + same rotation.
- **Plate life cycle** (all pure functions of `(plateId, memberIndex, actTick)`):
  1. **rest** — intact map, gravity-wave bobbing;
  2. **lift** (60t) — rises 4–9 anchor-blocks, tilts 8–25° toward the hole, eased
     kick-back shake; underside slabs fade in beneath it (see 2.4);
  3. **sub-fracture** at lift+40t — the plate splits into 2–4 **sub-plates**
     (hashed member partition; centroids/rotations switch to the sub-plate frame in
     one 4t snap window + `credits4_platebreak` burst + crack SFX);
  4. **infall** (240–380t) — sub-plates spiral into the hole; angular velocity ∝ q²
     (rising, per the ask), **plate-level spaghettization**: the sub-plate frame
     stretches radially to 2.2× and thins crosswise (inverse-sqrt), members widen
     their arc-trailing into filaments (reuse the F-072 `FILAMENT_TRAIL` law),
     heat-ignite from q ≥ 0.75 (existing magma/shroomlight edge-swap law);
  5. **swallow/recycle** — drain to scale floor over the horizon; the member displays
     **recycle into the deep layer** (see below), never despawn mid-act.
- **Lift waves** (offsets from `T_FINALE_REVEAL`): wave 1 at **260** (8 plates nearest
  the hole — the hole tears out what it touches first), waves 2–5 at **400 / 560 /
  720 / 880** (8+9+8+7, walking toward the camera; wave 5 = the camera-nearest
  mega-plates, the biggest silhouettes crossing highest through the frame — the
  height/mass thrill).
- **Deep layer**: recycled members re-pose as a dark slab layer (BEDROCK / DEEPSLATE /
  TUFF palette, brightness sky 2) 3 anchor-blocks under where the crust was — lifting
  a plate reveals that the map has a body, not a skin. At offset **1000** the deep
  layer itself rips in one accelerating cascade (single wave, all remaining cells) —
  the "nothing survives" beat, flowing straight into the act wind-down (1160–1300).

### 2.3 Crack fronts (before any liftoff)

- Offsets **100 / 170 / 240**: three fronts race across the intact effigy from the
  hole-side rim outward/toward camera (angles hashed ±50°), each ~90t in 6 × 15t
  propagation steps.
- Per step: (a) **seam slats** light up along the segment — a pool of **160**
  thin BlockDisplays (violet stained glass / amethyst, full-bright, scaled
  ~0.22 × 0.15 × seg-length) placed along the front polyline; (b) the new
  `credits4_crackfront` Photon cue fires at the step midpoint (glow motes hugging the
  seam + a rising dust curtain + a short upward debris jet); (c) a camera-shake pulse
  `shake(0.3 + 0.25·frontProgress, 14)` + `EVENT_END_SHATTER_CRACK` (pitch
  0.55–0.8) — "camera-shake pulses per crack propagation step" as asked.
- Crack polylines follow plate borders (Voronoi edges), so the later tear follows the
  glowing seams — cause and effect read as one system.

### 2.4 Underside reveal

- Pool of **500** recycled displays. When a plate lifts, its underside spawns/re-poses
  under the plate frame: ~1 dark slab per 2.5 members (BEDROCK/DEEPSLATE, scaled to
  the plate LOD) + ~1 hanging "root/stalactite" per 6 members (POINTED_DRIPSTONE or
  DEEPSLATE column scaled 0.4 × 2.2 × 0.4, hanging off the plate's belly, swinging
  ±4° on the plate tumble). Undersides ride the same plate transform (zero extra
  math beyond an offset) and drain with the plate; the pool re-arms for the next wave.

### 2.5 Gravity waves

- Offsets **300 / 460 / 620 / 780 / 940 / 1100**: a ring shockwave expands from the
  hole across the effigy (~1.4 anchor-blocks/t). Un-lifted cells bob in a traveling
  sine (±1.4 anchor-blocks over the 40t crossing window, eased; pure pose-side —
  zero extra packets beyond the normal push stride).
- As the crest passes, ~8% of touched cells (hashed) **strip**: a shard pops off the
  surface from a recycled pool of **280** small displays (0.3–0.5×), hops 2–4 blocks
  up, then gets dragged into the hole on a fast flat spiral.
- Beat dressing per wave: `FX_SHOCKWAVE (0.3 + 0.05·waveIdx, 26)` at the anchor +
  `EVENT_END_SHATTER_RUMBLE` (pitch 0.45) + `shake(0.3, 30)`.

### 2.6 Ejecta + relativistic jets

- **Shader**: the polar jets already exist (`black_hole.fsh` [b5], gated in from
  strength 0.45–0.8). Add a **`JetPulse`** uniform: on a jet burst the jet columns
  flare (× (1 + 1.4·jetPulse)), the knot phase speed doubles and the axial window
  lengthens to (0.5, 0.95) — the jets visibly STROBE.
- **Displays**: whenever a big gulp (strength ≥ 0.6) coincides with a sub-plate
  crossing the horizon (both schedules are deterministic — the act exposes
  `plateCrossing(actTick)` and `devourPulse` takes the max), that sub-plate **shreds**:
  its members re-target along ±jet axis (the disc minor axis in the anchor frame) as a
  fast spray over 50t (ignited, stretching 3× along the axis, draining at the tips).
  Roughly every 3rd–4th gulp from offset ~520 on.
- **Photon**: new `credits4_jetburst` cue at the anchor — two opposed fast particle
  streams + a handful of stretched sparks, ~60t one-shot per burst.
- **Gulp sync upgrade**: `swallowPulse` keeps its hash schedule as the floor, but
  plate horizon-crossings now boost the gulp strength (0.75–1.0) so the shockwave/
  blink/thump/Pulse land exactly when a continent visibly pours over the edge.

### 2.7 Sound (layered, mostly zero new assets)

- **Crack fronts**: `EVENT_END_SHATTER_CRACK` per step (0.55–0.8 pitch ladder) +
  `DEEPSLATE_BREAK` doubles.
- **Lift waves**: `EVENT_END_SHATTER_RUMBLE` at 0.45 pitch, vol 0.9 + delayed
  `GENERIC_EXPLODE` (0.35 vol, 0.4 pitch) — the "continent groan".
- **Sub-bass devour bed**: keep the existing `END_PORTAL_SPAWN` ladder; add a second
  `EVENT_END_SHATTER_RUMBLE` layer every 120t whose pitch cycles 0.5 → 0.7 → 1.0 →
  1.4 with crossfaded volumes — a poor-man's **shepard riser** from existing assets.
- **Optional polish** (separate checklist item): author a true
  `event.blackhole_shepard` loop (Treblo/ffmpeg pipeline, OGG **Vorbis**, −16 LUFS,
  validated by `tools/music/validate_oggs.py`) and swap the fake riser for it.
- All sends stay server-side `playNotifySound` from `CreditsSequence` beats (the
  house pattern; no client audio code needed).

### 2.8 Post/shader tweaks (minimal delta)

`black_hole.fsh`: add `uniform float JetPulse` (flare law above; strict no-op at 0,
`Detail`-gated like the jets themselves). Everything else (crack glow, plates,
waves) is geometry/Photon-side — the pass stays cheap and the Iris fallback story
(`VeilPostController` gates the stack off under shaderpacks) is unchanged: on
photon-less/Iris clients the rip still reads fully through the display entities.

---

## 3. Timeline (offsets from `T_FINALE_REVEAL = 3720`; devour window 0–1300 unchanged)

| Offset (t) | Beat | Displays live (approx) |
|---|---|---|
| −320…0 | Budgeted grid sampling + crust/deep spawn behind the black (identity poses) | → 1250 crust |
| 0–100 | Reveal: intact pixel-aligned map replica under the maw; ambient tremor; existing sky ladder step 1 | 1250 + 700 accretion |
| 100 / 170 / 240 | Crack fronts 1–3 race along plate borders (seam slats + `credits4_crackfront` + shake/crack per step) | +160 seams |
| 260 | Lift wave 1 (8 hole-side plates): lift → tilt → underside reveal | +≈300 underside |
| 300…1100 (×6) | Gravity waves every 160t: cell bob + surface stripping | +280 shards (pool) |
| lift+40 (per plate) | Sub-fracture into 2–4 sub-plates (`credits4_platebreak`, snap window, crack SFX) | — |
| 400 / 560 / 720 / 880 | Lift waves 2–5 (walking toward camera; wave 5 = nearest mega-plates) | underside pool re-arms |
| ~520 on | Jet shreds on big gulps (`JetPulse` strobe + `credits4_jetburst` + member spray) | — |
| 1000 | Deep-layer rip: everything remaining cascades in | — |
| 1160–1300 | Wind-down: all pools drain to floor (existing law); sky ladder at 1.0 | → 0 visible |
| 1300 = `T_FINALE_DARK` | Melt to black (unchanged); title/hold beats unchanged | discard at HOLD |

No shifts to `T_FINALE_*`, the music contract (`victory_theme` 3600t), the FOV
beat-map, or the 6-step intensity ladder — V3 slots entirely inside the existing
window.

## 4. Performance budget & LOD

| Set | Live displays (peak) |
|---|---|
| Crust plate members (LOD-sampled) | 1250 |
| Underside pool (slabs + stalactites, recycled per wave) | 500 |
| Crack seam slats (pool) | 160 |
| Gravity-wave shard pool (recycled) | 280 |
| Accretion field (existing act, `COUNT` 840 → **700**) | 700 |
| **Total finale peak** | **≈ 2890** |

- Under the audited < 3000 simultaneous target and the 3600 hard cap (still enforced;
  the new act calls `CreditsSequence.actCapReached()` before every spawn like its
  siblings). The finale phase overlaps no other act, so this is also the sequence peak
  (beach act remains ≈ 2570).
- Push cost: 2890/10 ≈ **289 transform updates/t** — same order as the audited beach
  worst case (≈ 185/t + brightness waves); plate poses are O(members) with shared
  per-plate quaternions computed once per plate per push.
- NBT writes stay edge-triggered (ignite/recycle/doppler caches — reuse the
  `hotCache`/`dopplerCache` pattern).
- Spawn rates: crust 30/t behind the black; underside 40/t per lift wave; shards/seams
  are pools (spawned once, re-posed).
- `reducedFx` clients: post pass drops jets/rings/starfield already; the new act adds
  a `reducedFx`-independent geometry read (displays always render) — acceptable, the
  display count is the same as any other act phase.

## 5. New / changed pieces

### New
1. `ritual/CreditsMapRipAct.java` — the V3 stage manager: budgeted disc sampling,
   Voronoi plates, crack-front/lift/wave/shred deterministic schedules
   (`crackStep(actTick)`, `plateCrossing(actTick)`, `waveFront(actTick)` — the
   `swallowPulse` pattern), all poses pure functions, own `TAG =
   "eclipse_credits_maprip"`, pools + recycling, `discard()`.
2. `veilfx/CreditsFinale4FxRows.java` — registers `credits4_crackfront`,
   `credits4_platebreak`, `credits4_jetburst` rows (AMBIENT / LAYER, null Quasar leg —
   the `CUE_LANDMARK_ECHO` precedent; ids via `FxCues.cue(...)` so `FxCues` stays
   frozen).
3. `tools/photon/credits4_fx.py` — authors the three .fx assets with fxlib (violet
   finale palette; validate round-trip).
4. (Optional) `assets/eclipse/sounds/music/…` shepard riser OGG + `sounds.json` entry
   `event.blackhole_shepard` + `EclipseSounds` registration.

### Changed
5. `ritual/CreditsSequence.java` — wire the act: prepare at `begin()` (grid sampling
   scheduled into the 3400–3640 window), spawn/animate windows in `onServerTick`,
   crack/lift/wave/shred beat dressing (shakes, fades, cues, layered SFX), gulp-sync
   (`devourPulse` takes `max(swallowPulse, plateCrossing)`), `onEntityJoin` tag list +
   `LIVE_DISPLAYS` tracking, discard in `skip`/`endEvent`/`beatFinaleHold`,
   budget-doc update on `DISPLAY_HARD_CAP`, FX-only `replay("BLACKHOLE")` extension
   (fire one crackfront + one jetburst + JetPulse sample at the watcher).
6. `ritual/CreditsBlackHoleAct.java` — `COUNT` 840 → 700; expose the gulp/crossing
   hook.
7. `network/credits/CreditsPayloads.java` — new `S2CCreditsJetPayload(float strength)`
   (id `eclipse:credits/jet`) + consumer seam. Additive only; the shipped payload set
   stays byte-identical (event pack: server+client always update together).
8. `client/credits/CreditsSkyFx.java` — second envelope `jetPulse(partialTick)`
   (4t attack / 22t decay) driven by the new payload.
9. `client/credits/CreditsBlackHolePostFx.java` — feed `JetPulse`.
10. `pinwheel/shaders/program/black_hole.fsh` — `JetPulse` uniform + jet flare law
    (remember: no anonymous `{}` scopes — Veil flattens them; unique local names).

No lang changes (no new UI text) — the langdrop workflow is not needed.

## 6. Ordered implementation checklist

1. [ ] `CreditsMapRipAct` skeleton: budgeted grid sampling (stage radius via
   `RingGrowthService`, LOD steps, ≤ 1300 cells) + identity-pose spawn + discard +
   tag sweep; wire prepare/spawn/discard into `CreditsSequence` behind the post-card
   black. **Verify**: reveal shows the intact pixel-aligned replica; log line with
   cell/plate counts; no cap warning.
2. [ ] Voronoi plates + lift waves + rigid plate poses + sub-fracture + infall with
   plate-level spaghettization and heat/recycle reuse. **Verify**: plates lift as
   coherent slabs, split mid-air, spiral in with rising angular velocity.
3. [ ] Deep layer (recycle target) + final deep rip at offset 1000.
4. [ ] Crack fronts: seam-slat pool + propagation schedule + per-step shake/SFX;
   `credits4_crackfront` asset + row (author via `credits4_fx.py`, `/dev photon test
   eclipse:fx/cue/credits4_crackfront` standalone).
5. [ ] Underside pool (slabs + stalactites riding the plate frame).
6. [ ] Gravity waves: cell bob + shard stripping pool + wave beat dressing.
7. [ ] Jet shreds: `plateCrossing` schedule + member spray poses +
   `credits4_jetburst` asset/row + `S2CCreditsJetPayload` + `CreditsSkyFx.jetPulse` +
   `JetPulse` uniform/shader law; gulp-sync boost in `devourPulse`.
8. [ ] `credits4_platebreak` asset + sub-fracture dressing; layered SFX pass
   (crack/rumble/shepard-fake ladders).
9. [ ] Reduce `CreditsBlackHoleAct.COUNT` to 700; re-audit budget comment on
   `DISPLAY_HARD_CAP`; extend the FX-only `BLACKHOLE` replay.
10. [ ] (Optional polish) true shepard-riser OGG via the music pipeline.
11. [ ] Full-run verification (below) + `./gradlew build` strict compile.

## 7. Manual test recipe

> VM notes (ProjectEclipse/AGENTS.md): no GPU — `runClient` uses llvmpipe at
> seconds-per-frame; drive via computerUse with long waits; the desktop client window
> can capture at **1920×1080** (screenshots at key beats; smooth video is not
> realistic on llvmpipe). Only ONE `run*` task at a time. **Do not run any of this
> while the 4K trailer render occupies the CPU.**

1. **Server up**: ensure `run/eula.txt` (`eula=true`) and `run/server.properties` has
   `enable-rcon=true`, `rcon.password=eclipsedev`, `allow-flight=true` (regenerated
   defaults silently drop these). `./gradlew runServer` from `ProjectEclipse/`.
2. **Client up** (visuals live only client-side): `./gradlew runClient`, join
   `localhost`, F1 optional, window at 1920×1080. Make sure `run/mods-client` jars are
   NOT in `run/mods` for the server run.
3. **Asset smoke tests first** (cheap, no sequence):
   `python3 tools/rcon/rcon.py "/dev photon test eclipse:fx/cue/credits4_crackfront"`
   (repeat for `credits4_platebreak`, `credits4_jetburst`); FX-only shot:
   `/dev replay play credits BLACKHOLE` (perm 2) — checks SPACE sky, post pass,
   maw/nebula, FOV, one gulp Pulse and (new) one JetPulse sample at the watcher.
   **Note: FX-only replays never spawn displays — the map-rip itself needs the real
   run.**
4. **Real run**: op the test player, then
   `python3 tools/rcon/rcon.py "/dev credits start"` and immediately
   `"/dev credits skip"` (jumps to `T_WHITE_FADE`; the outro cards play, then
   ~50 s later the finale tele beat lands, reveal ~4 s after that; total wait after
   skip ≈ 1 min to reveal, devour = 65 s).
5. **What to look for** (capture a 1920×1080 screenshot per row):
   - reveal: intact terrain replica pixel-aligned under the maw (real biome colors,
     relief);
   - crack fronts: violet seams racing along future plate borders + dust + per-step
     shake, BEFORE anything lifts;
   - lift wave: coherent continent slabs tilting up, dark underside + hanging
     stalactites visible ("mass");
   - mid-air sub-fracture snap + burst;
   - infall: sub-plates stringing into glowing filaments, igniting, pouring over the
     horizon exactly on gulp shockwaves;
   - gravity wave: visible ripple rolling across remaining terrain + shards stripping;
   - jet strobe on a big gulp (screen jets flare + display spray along the axis);
   - deep-layer rip → clean wind-down → gray-out → dark → letter-materialize title.
6. **Logs/health**: watch server log for `CreditsMapRipAct: … cell(s) / … plate(s)`,
   `CreditsBlackHoleAct: accretion field live — 700 …`, and the ABSENCE of
   `display hard cap 3600 reached`; `/dev status` for tick health during the devour
   (target: no sustained > 50 ms ticks on the dev VM).
7. **Teardown**: `python3 tools/rcon/rcon.py "/dev end_event"` (releases the hold,
   restores players/HUD/FOV, discards every display), then stop the server/client by
   **specific PID** (`ps -eo pid,args | grep devlaunch.Main`). Re-run `/dev credits
   start` on the same world logs a "running again" warning — fine for rehearsal.
8. **Regression**: one un-skipped full run end-to-end (≈ 4.5 min to the finale) to
   confirm the earlier acts (shatter/beach/burst) still fit the budget and the hold +
   `/dev end_event` contract is intact.
