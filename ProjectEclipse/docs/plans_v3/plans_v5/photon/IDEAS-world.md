# PHOTON IDEAS — WORLD / LANDMARK AMBIENCE (PHOTON-IDEAS-2, 2026-07)

Domain: the eight standing landmarks — altar sanctum, expansion rift, nether breach, fog
storm sites, sky launcher, wizard hut (observatory), end disc, supply drops.
Companion docs (read first, all specs below conform to them):
`photon/API.md` (runtime API, reflection recipe), `photon/FX_FORMAT.md` (full `.fx`
schema — §3 particle_emitter, §4 beam/trail/ara, §5 materials/bloom, §9 perf),
`photon/INTEGRATION.md` (PhotonBridge guard chain, PhotonFxRegistry target architecture,
design laws). Every trigger point below was re-verified against the current sources:
`veilfx/PhotonBridge.java`, `network/fx/FxPayloads.java`, `veilfx/rift/RiftFx.java`,
`client/drama/AltarCeremonyFx.java`, `client/drama/AltarIdleMotes.java`,
`client/sanctum/SanctumLightfall.java`, `stormfx/StormFxClient.java`,
`worldgen/nether/BreachTransferService.java` + `BreachGeometry.java`,
`worldgen/structure/SkyLauncher.java` + `WizardObservatory.java`,
`worldgen/end/EndShatterSequence.java`, `economy/SupplyBeacon.java`,
`veilfx/SupplyBeamClient.java`, `veilfx/FxAnchors.java`.

---

## 0. Cross-cutting rules + new machinery these concepts need

**Laws carried over (do not renegotiate — INTEGRATION.md §3/§4):**

1. Server stays photon-blind: only logical ids (`FxCues`, existing payloads) cross the
   wire. Every concept below anchors on an EXISTING payload/anchor or adds one `FxCues`
   id over the existing `S2CFxEventPayload` lane (no registrar bump).
2. Every Photon leg is additive (`Mode.LAYER`) or degrades to the exact current visuals
   (`Mode.REPLACE` + fallback). Photon absent/missing-asset/`reducedFx` ⇒ bit-identical
   to today.
3. Photon spawns stay un-charged by `FxBudget`; `reducedFx` is the wholesale kill switch
   (`PhotonBridge.available()` already enforces it).
4. Ship `assets/eclipse/fx/<id>.fx` in-jar AND commit the `.fxproj` next to it
   (binary-blob diff law, FX_FORMAT.md §7 trade-offs).

**The loop question (must be settled before concepts 7–10 ship).** INTEGRATION.md §4
reserves *payload-driven Photon cues* for SEQUENCE-grade one-shots and bans ambient-loop
cues. Concepts 7–10 are ambience, so they deliberately do NOT ride the cue registry:
they use a new client-local **`PhotonLoopWindow`** pattern — the exact
`SanctumLightfall`/`AltarIdleMotes` school (materialize/release hysteresis band, one
distance check per tick while far, everything torn down on `reducedFx`/logout/dimension
change) but holding a Photon executor instead of a Quasar `ParticleEmitter` handle.
That needs three small additive `PhotonBridge` growths, all pre-verified against the
2.1.5 jar in API.md:

- `spawnLoop(fxId, pos) → LoopHandle` — same `BlockEffectExecutor` path plus reflected
  `getRuntime()` and `FXRuntime.destroy(boolean)` handles (API.md §6 shows the exact
  recipe); `LoopHandle.release()` calls `destroy(false)` (graceful fade) and
  `LoopHandle.alive()` proxies `FXRuntime.isAlive()` for pruning.
- `setAllowMulti(true)` reflection (API.md §5 refinement 3) for stackable bursts
  (concept 3) — default-false dedup at one BlockPos is otherwise a silent no-op.
- `spawnOnEntity(fxId, entity, autoRotate)` — reflect
  `EntityEffectExecutor(FX, Level, Entity, AutoRotate)` + `AutoRotate.valueOf("NONE")`
  (INTEGRATION.md §3 rule 5 sanctions adding this once a cue actually needs it —
  concepts 4 and 5 do). Entity death auto-destroys the runtime (API.md §1), which
  concept 4 exploits directly.

Every looping asset below carries a `renderer.cull` box (cheap off-screen skip),
a hard `maxParticles`, and `vertexSortingMode: NONE` wherever the blend is additive
(order-independent). Physics-collision emitters keep `parallelUpdate: 0b` — the
collision module does real level queries, which the parallel path forbids
(FX_FORMAT.md §3.1/§3.3). Times below are ticks, sizes blocks, colors ARGB.

**Bloom recipe used throughout** (FX_FORMAT.md §5): `texture`/`sprite` material with
`hdr: [r,g,b,1]` > 0 + `hdrMode: "ADDITIVE"`, blend `SRC_ALPHA/ONE` (additive) on
`layer: "Translucent"`. Photon's bright-pass (threshold 1.0, intensity 0.7) does the
rest; Iris-compat is built in.

---

## Ranked concept table

| # | Concept | Landmark | Kind | Trigger wiring cost |
|---|---|---|---|---|
| 1 | Sanctum Ring 2.0 (`altar_levelup`) | Altar | burst | ZERO — seam shipped, asset absent |
| 2 | Event-Horizon Ring (`expansion_rift_glow`) | Expansion rift | finite (rift-life) | ZERO — seam shipped, asset absent |
| 3 | Piece-Launch Muzzle Flash | Expansion rift | burst ×6/launch window | 1 client line in `RiftFx` surge |
| 4 | Descent Contrail + Landing Dust Ring | Supply drops | entity-attached + sub-emitter burst | small client seam in `SupplyBeamClient` |
| 5 | Charge Helix + Launch Contrail | Sky launcher | burst (15 t) + entity-attached | 2 new `FxCues` sends |
| 6 | Crack Light-Bleeds + Void Wisps | End disc | burst race + GPU loop | bleeds ~ZERO (rides `FX_RIFT_OPEN` race); wisps need a loop window |
| 7 | Ash Geysers + Ember Ribbon Updrafts | Nether breach | loop | new `BreachAmbience` loop window |
| 8 | Wall Lightning Veins + Crown Halo | Fog storms | scheduled bursts + loop | layer inside `StormFxClient` |
| 9 | Idle L5 Corona Ribbons | Altar | loop (L5-gated) | loop window off `ALTAR_CENTER` anchor |
| 10 | Chimney Sparks + Window Glow Motes | Wizard hut | loop | loop window, client-derived anchor |

Ranking = (seam already wired) → spectacle-per-effort → loop-machinery dependency.
1–2 are pure asset authoring against shipped code; 3–5 are SEQUENCE-grade one-shots that
fit the existing cue law as-is; 6–10 escalate from "near-free" to "needs the
`PhotonLoopWindow` pattern blessed".

---

## 1. Sanctum Ring 2.0 — `eclipse:altar_levelup` (altar milestone level-up)

The flagship. The Quasar `altar_levelup_ring` keeps playing underneath (LAYER law); the
Photon layer adds what Quasar cannot: an HDR shock ring that blooms, amethyst-model
glyph shards, and a sky spear.

**`.fx` object spec** — 4 objects under one `empty` root (`name: "altar_levelup_root"`,
identity transform; children give shared origin):

- `particle_emitter` `"ring_shock"` — the bloom ring.
  - main: `duration: 30, looping: 0b, startLifetime: {random_constant 14–20},
    startSpeed: {constant 2.4}` (radial from the shape), `startSize: NF3 {random_constant
    0.22–0.4}`, `startColor: {color -1}`, `simulationSpace: "World"`, `maxParticles: 160`.
  - emission: `emissionRate 0`, one burst `{time: 0, count: {constant 96}, cycles: 1,
    interval: 1, probability: 1.0}`.
  - shape: `circle` `{radius: 0.6, radiusThickness: 0f, arc: 360}` (XZ shell ⇒ a clean
    expanding ring), `shapeArc.arcMode: "BurstSpread"` (even spacing, no clumping).
  - renderer: `renderMode: "Billboard"`, material `texture`
    `{texture: "photon:textures/particle/circle.png", discardThreshold: 0.05,
    hdr: [2.6, 1.7, 3.2, 1], hdrMode: "ADDITIVE"}`, blend
    `{src SRC_ALPHA, dst ONE, blendFunc ADD}`, `depthMask: 0b`, `layer: "Translucent"`,
    `vertexSortingMode: "NONE"`, `shade: 0b`, emitter cull box
    `{min: [-10,-1,-10], max: [10,6,10]}`.
  - modules: `colorOverLifetime` gradient white→`#E7C9FF`→violet `#7B3FD9`, alpha
    1→0.85→0; `sizeOverLifetime` single-segment Bézier `[[0,0.4, 0.15,1, 0.7,0.95, 1,0]]`
    (pop then dissolve); `lights {_enable:1b, sky 15, block 15}`.
- `particle_emitter` `"glyph_shards"` — mesh-model shards, the "Photon can, Quasar
  can't" hero.
  - main: `duration: 30, looping: 0b, startLifetime: {random_constant 26–44},
    startSpeed: {random_constant 0.5–1.1}, startSize: NF3 {random_constant 0.18–0.3},
    startRotation: [0,0,{random_constant 0–360}], simulationSpace: "World",
    maxParticles: 40`.
  - emission: burst `{time: 2, count: {constant 26}, cycles: 1}`.
  - shape: `mesh` `{type: "Triangle", meshData.modelLocation:
    "minecraft:block/amethyst_cluster"}` — shards spray from the cluster's own geometry.
  - renderer: `renderMode: "Model"` + material `block_atlas` + `useBlockUV: 1b`,
    `shade: 1b`, blend disabled (`layer: "Opaque"` model pass reads crisper for solid
    shards), `modelPivot: [0,0,0]`.
  - modules: `physics {_enable:1b, hasCollision:1b, gravity {constant 0.18},
    friction {constant 0.985}, collidedFriction {constant 0.55}, bounceChance
    {constant 0.5}, bounceRate {constant 0.35}}` (shards clatter onto the altar floor);
    `rotationOverLifetime {roll {random_constant −9–9}, yaw {random_constant −6–6}}`;
    `lights 15/15` (fresh shards glow) — NOTE `parallelUpdate: 0b` (collision).
- `particle_emitter` `"spark_ribbons"` — 12 rising sparks that drag short ribbons.
  - main: `duration: 30, looping: 0b, startLifetime: {random_constant 20–30},
    startSpeed: {random_constant 0.7–1.2}, startSize: NF3 {constant 0.09},
    maxParticles: 16`; burst `{time: 1, count: {constant 12}}`.
  - shape: `cone {angle: 18, radius: 0.4}` pointed +Y.
  - `trails {_enable:1b, ratio: 1.0, lifetime: {constant 0.5}, inheritParticleColor: 1b,
    trailType: "TRAIL", config: {time: 8, minVertexDistance: 0.05, widthOverTrail:
    {curve 0.12→0}, colorOverTrail: gradient violet→transparent}}`; material as
    `ring_shock` with `hdr [1.6,1.1,2.2,1]`.
- `beam_emitter` `"sky_spear"` — a 2 s vertical lance.
  - `duration: 40, looping: 0b, end: [0, 48, 0], width: {curve lower 0 upper 0.9, one
    segment [[0,1, 0.1,1, 0.5,0.35, 1,0]]}` (thick flash → needle → gone),
    `emitRate: {constant 0}` (continuous), `raycast: "NONE"`,
    `color: gradient white→`#B388FF``, material `texture circle.png,
    hdr [2.0,1.4,2.8,1]`, additive blend, `lights 15/15`.

**Trigger point (SHIPPED — zero code):** server
`ritual/AltarBlockEntity.completeMilestone` → `S2CQuasarPayload(ALTAR_LEVELUP_RING)` →
client `EclipsePayloads.handleQuasar` → `PhotonBridge.enhanceQuasarCue` →
`spawn(eclipse:altar_levelup, pos)`. Executor anchors at altar block center. The
ceremony script (`AltarCeremonyFx`, `FX_ALTAR_LEVELUP`) deliberately does NOT re-fire
the Photon layer — one Photon play per level-up, per the D12 note. The bridge does not
see the level (`a`), so the asset is level-agnostic; per-level escalation stays on the
Quasar/script side (correct — the ceremony already escalates L1→L5).

**Quasar fallback:** existing `altar_levelup_ring` + the whole `AltarCeremonyFx`
composition run regardless (Mode.LAYER). Photon-less clients see exactly today's show.

**Loop vs burst + perf:** one-shot, ~60 t total life, ≤ 220 live particles worst case.
Collision only on 26 shards (the expensive module, bounded). `allowMulti=false` dedup is
desirable here: double-sends at one altar pos while alive are absorbed. Bloom cost is a
handful of HDR quads — SEQUENCE-grade by design.

---

## 2. Event-Horizon Ring — `eclipse:expansion_rift_glow` (structure-drop rift tears)

A slow ara ribbon carousel around the tear mouth + matter visibly falling IN — reads as
an accretion disc over `RiftFx`'s star-polygon geometry.

**`.fx` object spec** — 2 emitters, one root `empty` `"rift_glow_root"`:

- `particle_emitter` `"horizon_orbiters"` — 3 orbiting carriers dragging physics ribbons.
  - main: `duration: 200, looping: 0b` (see lifetime note below),
    `startLifetime: {constant 190}, startSpeed: {constant 0}, startSize: NF3
    {constant 0.12}, simulationSpace: "Local"`, `maxParticles: 3`.
  - emission: `emissionRate 0`; burst `{time: 0, count: {constant 3}}`.
  - shape: `circle {radius: 3.2, radiusThickness: 0f}` with
    `shapeArc {arcMode: "BurstSpread"}` (3 carriers evenly spaced).
  - modules: `velocityOverLifetime {orbitalMode: "AngularVelocity",
    orbital: [0, {constant 1.1}, 0]}` (rad/tick·-ish sweep around Y);
    `trails {_enable:1b, ratio 1.0, lifetime {constant 0.22}, trailType: "ARA_TRAIL",
    araConfig: {section: default strip, space: "World", alignment: "View",
    thickness: 0.35, smoothness: 5, cornerRoundness: 6, time: 0.9,
    timeInterval: 0.05, colorOverLength: gradient `#D0B3FF`→transparent,
    thicknessOverLength: curve 1→0.15, physicsSetting: {inertia: 0.35,
    velocitySmoothing: 0.75, damping: 0.7}}}` — the ribbon lags and swings behind each
    carrier (the premium look, FX_FORMAT §4.3).
  - carrier renderer: additive `circle.png`, `hdr [1.8,1.2,2.6,1]`; cull box
    `{min:[-8,-4,-8], max:[8,6,8]}`.
- `particle_emitter` `"infall_streaks"` — dust sucked into the mouth.
  - main: `duration: 200, looping: 0b, startLifetime: {random_constant 18–30},
    startSpeed: {constant 0}` (velocity comes from the radial module),
    `startSize: NF3 {random_constant 0.05–0.12}, maxParticles: 140`.
  - emission: `emissionRate: {constant 1.2}`.
  - shape: `sphere {radius: 4.5, radiusThickness: 0.15}`.
  - modules: `velocityOverLifetime {radial: {constant −0.35}}` (inward pull);
    `sizeOverLifetime` curve 1→0.2; `colorOverLifetime` `#9C7BE0`→white flash at end
    (t 0.85 rgb spike — matter "ignites" at the horizon).
  - renderer: `renderMode: "StretchedBillboard", velocityScale: 1.6, lengthScale: 2.5`,
    additive, small hdr `[1.2,0.9,1.8,1]`, `vertexSortingMode: NONE`.

**Trigger point (SHIPPED — zero code):** every tear open calls
`RiftFx.openRift(...)` → `PhotonBridge.spawn(EXPANSION_RIFT_GLOW, pos)` — reached from
`S2CStructureRiftPayload`, `FxPayloads FX_RIFT_OPEN` (ExpansionSequence,
StructureFlightFx, XboxPortal, BackroomsPortal, MinigamePortal, wand, `/eclipsefx rift
open`). Anchors at the tear-center BlockPos.

**Asset-lifetime gotcha (why `looping: 0b, duration 200`):** the bridge never calls
`destroy` — a `looping:1b` asset would outlive the tear forever. 200 t (10 s) covers the
structure-delivery window (surge 20+36 t + flights ≤ 60 t + settle) and portal opens;
re-opens at the same BlockPos while alive are dedup-absorbed (`allowMulti=false`), and a
replaced/re-opened rift simply re-fires after death. If a future pass wires
`RiftFx.closeRift` → `LoopHandle.release()` (the §0 machinery), the asset can graduate
to `looping:1b` and die exactly with the tear. Note the executor cannot scale per rift
width today (bridge doesn't reflect `setScale`); the asset is authored for the common
structure-tear width ≈ 6–8 blocks — acceptable, the ribbon ring reads correct inside the
star at any payload width; reflect `setScale(width/7)` later if it bothers.

**Quasar fallback:** `rift_spark` rim crackle + `portal_surface_motes` + the
`RiftRenderer` mesh — the entire current stack keeps running (LAYER; registry row
already sketched in INTEGRATION.md §3 with `quasarEmitter: null`).

**Loop vs burst + perf:** finite 10 s, ≤ 145 live particles + 3 ara ribbons. Ara ribbons
are the costly bit (Catmull-Rom subdivision) — 3 ribbons, smoothness 5 is well inside
budget. No physics collision. Cull box keeps off-screen rifts free.

---

## 3. Piece-Launch Muzzle Flash — `eclipse:rift_piece_flash`

Every structure-piece batch that launches out of the delivery tear gets a bloom muzzle
flash at the mouth — the tear visibly *fires* the buildings out.

**`.fx` object spec** — 3 emitters, no root needed:

- `particle_emitter` `"flash_core"` — single HDR pop.
  - `duration: 6, looping: 0b, startLifetime: {constant 4}, startSpeed: {constant 0},
    startSize: NF3 {constant 2.8}, maxParticles: 1`; burst `{time: 0, count: 1}`;
    shape `dot`.
  - renderer: Billboard, `circle.png`, `hdr [3.5, 2.6, 4.0, 1]` (the loudest bloom in
    this doc — it is 4 ticks long), additive, `shade: 0b`.
  - `sizeOverLifetime` curve `[[0,0.55, 0.1,1, 0.6,0.8, 1,0.2]]`;
    `colorOverLifetime` white→`#CBA8FF`, alpha 1→0.
- `particle_emitter` `"flash_petals"` — directional spray down the launch axis.
  - `duration: 6, looping: 0b, startLifetime: {random_constant 6–10},
    startSpeed: {random_constant 0.9–1.7}, startSize: NF3 {random_constant 0.1–0.2},
    maxParticles: 20`; burst `{time: 0, count: {constant 14}}`;
    shape `cone {angle: 65, radius: 0.3}` (asset authored +Y — the tear opens flat in
    the sky and fires downward-out; the executor's default rotation is fine since the
    cone reads as an omni-flash at 4–10 t lifetimes).
  - renderer: `StretchedBillboard, velocityScale: 2.2, lengthScale: 3`, additive,
    `hdr [1.8,1.4,2.4,1]`; `colorBySpeed` gradient (fast = white, slow = violet,
    `speedRange {0.2, 1.7}`).
- `particle_emitter` `"smoke_kick"` — 8 alpha-blended `photon:textures/particle/smoke.png`
  puffs, `startLifetime 14–22`, cone as above, blend
  `{src SRC_ALPHA, dst ONE_MINUS_SRC_ALPHA}`, `vertexSortingMode: "DISTANCE"`,
  `colorOverLifetime` grey-violet fade-out. `maxParticles: 10`.

**Trigger point (ONE client line):** `veilfx/rift/RiftFx.Rift` delivery surge —
`tickSurge` already pops a `map_expand_materialize` Quasar burst at the mouth every
`SURGE_BURST_PERIOD = 6` t for `SURGE_BURST_TICKS = 36` t, deliberately matched to the
server's `StructureFlightFx` batch cadence (`BATCH_STAGGER_TICKS = 6`). Add
`PhotonBridge.spawn(RIFT_PIECE_FLASH, mouthPos)` beside that spawn. No payload, no cue:
the surge is already the client-visible "pieces are launching" signature. IMPORTANT:
asset `duration: 6` ≤ the 6 t cadence, so the default `allowMulti=false` BlockPos dedup
never eats a flash (the previous runtime is dead when the next fires). If the asset ever
grows past 6 t, use the §0 `setAllowMulti(true)` handle instead.

**Quasar fallback:** the existing `map_expand_materialize` surge burst IS the fallback
(LAYER) — plus rift groan/whoosh audio from `StructureFlightFx`. `reducedFx` already
halves the surge cadence and skips Photon wholesale.

**Loop vs burst + perf:** pure burst, ≤ 31 particles per flash, ≤ 6 flashes per
delivery window, dead in 22 t. Zero physics. This is the cheapest concept in the doc
and the most visible after #1 — hence rank 3.

---

## 4. Supply Drop — descent contrail + landing dust ring
(`eclipse:supply_drop_contrail` + `eclipse:supply_landing_dust`)

The falling barrel crate drags an ember contrail; the moment its embers strike the
ground, a collision **sub-emitter** stamps the landing dust ring — Photon's
`subEmitters` module spawning a second whole `.fx` file on `FirstCollision`
(FX_FORMAT §3.3), no landing packet needed.

**`.fx` object spec:**

`supply_drop_contrail.fx` (attached to the crate entity):

- `ara_trail_emitter` `"crate_ribbon"` — the main contrail.
  - `duration: 160, looping: 1b` (entity-executor auto-destroy is the stop, see
    trigger), `space: "World", alignment: "View", thickness: 0.4, smoothness: 4,
    time: 1.4` (s of tail), `timeInterval: 0.05, minDistance: 0.05,
    thicknessOverLength: curve 1→0.1, colorOverLength: gradient `#FFE2B0`→`#B37DFF`→
    transparent, textureMode: "Stretch"`, physicsSetting
    `{gravity: [0, −0.02, 0], inertia: 0.2, damping: 0.8}` (tail sags — reads like a
    real drop streamer). Material: additive `circle.png`, `hdr [1.6,1.2,1.0,1]`.
- `particle_emitter` `"ember_shed"` — sparse embers shed off the crate; these carry the
  landing detection.
  - `duration: 160, looping: 1b, startLifetime: {random_constant 30–50},
    startSpeed: {random_constant 0.05–0.15}, startSize: NF3 {random_constant 0.06–0.12},
    simulationSpace: "World", maxParticles: 60`; `emissionRate: {constant 0.8}`;
    shape `sphere {radius: 0.5}`.
  - `inheritVelocity {_enable:1b, mode: "CURRENT", multiply: {constant 0.85}}` — embers
    fall WITH the crate.
  - `physics {_enable:1b, hasCollision: 1b, removedWhenCollided: 1b,
    gravity: {constant 0.12}}`, `parallelUpdate: 0b`.
  - `subEmitters {_enable:1b, emitters: {uid:1, payload:[{fxLocation:
    "eclipse:supply_landing_dust", event: "FirstCollision",
    emitProbability: {constant 0.12}, inheritColor: 0b, inheritSize: 0b}]}}` — the first
    embers that hit the landing surface stamp the dust ring exactly where the crate
    lands, even down a ravine (probability keeps it to ~1–3 stamps).
  - renderer: additive, `hdr [1.4,0.9,0.5,1]` warm embers; `colorOverLifetime` amber→red
    →out.

`supply_landing_dust.fx` (spawned BY the sub-emitter, also usable standalone):

- `particle_emitter` `"dust_ring"` — `duration: 20, looping: 0b`, burst
  `{time: 0, count: {constant 36}}`, shape `circle {radius: 0.8, radiusThickness: 0f}`,
  `startSpeed: {random_constant 0.5–0.9}` (radial skirt), `startLifetime 16–26`,
  `physics {gravity {constant 0.06}, hasCollision: 0b}` (cheap — no collision needed on
  dust), smoke.png alpha blend, `DISTANCE` sort, earth-tone `colorOverLifetime`,
  `maxParticles: 40`.
- `particle_emitter` `"pop_sparks"` — 10 additive HDR sparks, burst t 0, cone up,
  `hdr [1.8,1.4,0.9,1]`, life 8–14.

**Trigger point (small client seam):** `veilfx/SupplyBeamClient.add(pos, fadeTicks)` —
the fresh-drop branch (`fadeTicks > 0`, camera ≤ `BURST_FX_RANGE = 128`) already spawns
`altar_beam` + `supply_spark`. Add: scan the drop column
(`level.getEntitiesOfClass(FallingBlockEntity.class, new AABB(pos).inflate(2, 80, 2))` —
the crate spawns at surface+60 in that exact column, `SupplyBeacon.drop`) and call
`PhotonBridge.spawnOnEntity(SUPPLY_DROP_CONTRAIL, crate, NONE)` (§0 machinery). Photon's
`EntityEffectExecutor` re-anchors to the entity eye position every frame and
**auto-destroys the runtime when the crate entity dies on landing** (API.md §1) —
`forcedDeath=false` default lets the ribbon tail fade out naturally in the air above the
barrel. No landing payload exists and none is needed: the collision sub-emitter is the
landing FX.

**Quasar fallback:** shipped `altar_beam` landing burst + `supply_spark` pop + the
`SupplyBeamRenderer` beam and its budgeted point light — all unchanged (LAYER).

**Loop vs burst + perf:** the contrail is `looping:1b` but entity-bounded (crate falls
~60 blocks ≈ 3–4 s; entity death is the guaranteed stop — no leak path). ≤ 60 embers +
1 ara ribbon + ≤ 50 dust particles per stamp. Collision is on at most 60 particles for a
few seconds, once per drop. `removedWhenCollided:1b` keeps post-landing cost zero.

---

## 5. Sky Launcher — charge helix + launch contrail
(`eclipse:sky_launch_charge` + `eclipse:sky_launch_contrail`)

The 15 t wind-altar charge becomes a solid triple-helix ribbon of light (today: 3
END_ROD dots/tick); the launched player streaks a contrail toward the End disc.

**`.fx` object spec:**

`sky_launch_charge.fx` (block-anchored at the pad):

- `particle_emitter` `"helix_carriers"` — 3 carriers that FLY the golden-angle spiral
  via the `function` shape (FX_FORMAT §6), dragging ara ribbons.
  - `duration: 15, looping: 0b` (exactly `SkyLauncher.CHARGE_TICKS`),
    `startLifetime: {constant 15}, startSpeed: {constant 0.01}, maxParticles: 3`,
    burst `{time: 0, count: 3}`.
  - shape `function`: `x: "1.4*cos(t*4*PI + randomA*2*PI)"`,
    `z: "1.4*sin(t*4*PI + randomA*2*PI)"`, `y: "t*2.5"` — the exact server spiral
    (progress·4π sweep, r 1.4, y progress·2.5, `SkyLauncher.tickCharges`) with a random
    phase per carrier standing in for the three golden-angle arms; `speedX/Y/Z:
    "0"`. (Carriers are *placed* along the spiral over emitter t; near-zero speed keeps
    them there while the ribbons connect the dots.)
  - `trails {_enable:1b, trailType: "ARA_TRAIL", lifetime {constant 1.0},
    araConfig {thickness: 0.22, smoothness: 6, highQualityCorners: 1b, time: 0.8,
    colorOverLength: gradient `#E8FFF6`→`#7FE7FF`→transparent, physicsSetting
    {inertia: 0.15, damping: 0.85}}}`; carrier material additive `circle.png`,
    `hdr [1.5, 2.2, 2.0, 1]` (cold wind-light bloom).
- `particle_emitter` `"apex_burst"` — at `time: 14` one burst of 20 up-cone sparks
  (`speed 1.2–2.0`, StretchedBillboard) — the "release" flash synced to the throw.

`sky_launch_contrail.fx` (entity-attached to the launched player):

- `ara_trail_emitter` `"launch_ribbon"` — `duration: 70, looping: 0b`, `space: "World",
  alignment: "View", thickness: 0.5, smoothness: 5, time: 1.8, timeInterval: 0.05,
  thicknessOverLength: curve 1→0.05, colorOverLength: `#FFFFFF`→`#9BE8FF`→transparent,
  physicsSetting {gravity: [0,−0.01,0], inertia: 0.25, damping: 0.8}`, additive,
  `hdr [1.3,1.9,2.1,1]`.
- `particle_emitter` `"slip_rings"` — every 6 t one ring burst (bursts
  `{time:0,count:6,cycles:10,interval:6}`) of 6 tiny particles on a
  `circle {radius: 0.7}` shell in Local space, `inheritVelocity` off — reads as speed
  rings slipping past the flyer. `maxParticles: 60`, additive, faint hdr.

**Trigger point (2 new cues over the EXISTING `S2CFxEventPayload` lane — the
INTEGRATION.md §3 `FxCues`/`PhotonFxRegistry` shape, no protocol change):**

- `FxCues.CUE_SKY_LAUNCH_CHARGE` — sent from `SkyLauncher` at charge start (beside the
  `AMETHYST_BLOCK_CHIME` in the interaction handler), `pos = pad center`, range 64.
  Registry row: block-anchored, `Mode.LAYER`, `quasarEmitter: null`.
- `FxCues.CUE_SKY_LAUNCH` — sent from `SkyLauncher.launch(...)` (beside
  `EVENT_SKY_LAUNCH` sound), `pos = player`. Client handler resolves the nearest player
  (the `FxPayloads.nearestPlayer` glide pattern, 8-block match) and calls
  `PhotonBridge.spawnOnEntity(SKY_LAUNCH_CONTRAIL, player, "NONE")`.

Charge cancel (walk-off) needs no stop wiring: the charge asset is 15 t finite and the
server simply doesn't send the launch cue. These are SEQUENCE-grade one-shots — fully
inside the current cue law.

**Quasar/vanilla fallback:** the server's existing END_ROD golden-angle spiral +
CLOUD/END_ROD launch bursts + shake (`SkyLauncher.tickCharges`/`launch`) are untouched
and remain the only visuals for photon-less clients. Optional later: a `quasar`
`sky_launch_trail` row in REPLACE mode; not required.

**Loop vs burst + perf:** both finite (15 t / 70 t). 3 + ~80 particles, 4 ara ribbons
total. Entity executor auto-cleans if the player dies mid-flight. Zero collision. The
`function`-shape helix is evaluated per emission only — negligible.

---

## 6. End Disc — dragon-death crack light-bleeds + void wisps
(`eclipse:end_crack_bleed` + `eclipse:end_void_wisps`)

**(a) Crack light-bleeds (burst race).** When the disc shatters, violet light races up
out of the future seams. `EndShatterSequence` already sends `FX_RIFT_OPEN`
(`a = 6.0`) at each seam midpoint, one every `CRACK_RACE_STEP_TICKS = 4` t
(`onDragonVictory`, CUT-END shot 2) — and `RiftFx.openRift` already fires
`PhotonBridge.spawn(EXPANSION_RIFT_GLOW, …)` on every one. Two options:

- **Option A (ZERO code):** ship concept #2's asset and the crack race inherits the
  event-horizon ring at every seam flash. Acceptable but thematically off (accretion
  ring on a ground fissure).
- **Option B (recommended, 1 client branch):** in `RiftFx.openRift`, when
  `style == STYLE_STRUCTURE && width >= 5.5 && normal is up && level is overworld &&
  pos.y > 340` (the crack race is the only sender matching that fingerprint at disc
  altitude) — or cleaner, a dedicated `FxCues.CUE_END_CRACK` sent by
  `EndShatterSequence` instead of the second `FX_RIFT_OPEN` — spawn
  `eclipse:end_crack_bleed`:
  - `beam_emitter` ×3 `"bleed_shaft_a/b/c"` under an `empty`: `end: [±1.5, 26, ±1.5]`
    variants (a slightly splayed fan of light shafts), `width: {random_curve 0.5–1.1,
    flicker}`, `duration: 36, looping: 0b`, `raycast: "NONE"`, color gradient
    `#E7D6FF`→`#7B3FD9`, additive, `hdr [2.2,1.5,3.0,1]` — bloom columns punching out of
    the fissure.
  - `particle_emitter` `"fissure_embers"` — burst 30 from shape
    `box {emitFrom: "Edge"}` scaled `[6, 0.2, 1.2]` (a seam-aligned strip), up-speed
    0.4–0.9, `mesh`-free, additive violet embers, life 20–35, slight gravity, no
    collision. `maxParticles: 34`.
  - Dedup note: race steps are 4 t apart at DIFFERENT BlockPos — `allowMulti` is a
    non-issue.

**(b) Void wisps (GPU-instanced loop).** Standing ambience under/around the disc rim —
ghost-light plankton drifting in the void, the Photon GPU-instancing showcase
(FX_FORMAT §7 item 3).

- `particle_emitter` `"void_wisps"` single emitter:
  - main: `duration: 100, looping: 1b, prewarm: 40, startLifetime: {random_constant
    120–220}, startSpeed: {constant 0}, startSize: NF3 {random_constant 0.04–0.1},
    simulationSpace: "World", maxParticles: 1200`,
    **`parallelUpdate: 1b, parallelRendering: 1b`** (legal: no physics/level access),
    renderer **`useGPUInstance: 1b`**, Billboard, additive `circle.png`,
    faint `hdr [0.9,0.7,1.4,1]`, `vertexSortingMode: "NONE"`, `shade: 0b`.
  - emission: `emissionRate: {constant 8}` (≈ 1200 steady-state at 150 t mean life).
  - shape: `cylinder {radius: 104, radiusThickness: 0.12}`, shape scale `[1, 0.25, 1]` —
    a thin torus-ish band hugging the rim (disc radius 96 + margin), authored at emitter
    origin = disc center `(END_DISC_CENTER_X, END_DISC_SURFACE_Y − 6, END_DISC_CENTER_Z)`.
  - modules: `noise {_enable:1b, frequency: 0.35, quality: "Noise3D",
    position: NF3 {constant 0.08}}` (the whole motion — pure drift);
    `colorOverLifetime` gradient in-hold-out (alpha 0→0.5→0, rgb `#8F7BD9`→`#4B3B8C`);
    `sizeOverLifetime` gentle 0.7→1→0.6.
  - `renderer.cull {_enable:1b, cullBox: {min:[-110,−20,−110], max:[110,30,110]}}`.

**Trigger points:** (a) `EndShatterSequence.onDragonVictory` crack-race beats (existing
sends; Option B adds one `FxCues` id or one style-fingerprint branch). (b) a
`PhotonLoopWindow` client class keyed on frozen client-safe constants
(`DiscProfile.END_DISC_RADIUS/SURFACE_Y/CENTER_*` — `DiscMapData`/`DiscTerrainFunction`
are already used client-side by `MapTab`): window = overworld + camera within 160 of the
disc rim + a `SanctumLightfall`-style physical probe (`hasChunk` + disc-surface block
non-air at center) so wisps never run before materialization. Release with hysteresis
(160/180), `LoopHandle.release()` on exit.

**Quasar fallback:** (a) the crack stinger sounds + `GROWTH_DUST_WALL` curtains + the
`FX_RIFT_OPEN` star tears — today's full show (LAYER). (b) none — pure garnish by
design; photon-less clients keep the current (empty) void, zero regression.

**Loop vs burst + perf:** (a) 6–8 bursts of ≤ 70 objects each across the ~40 t race —
trivial. (b) THE big-count experiment: 1200 GPU-instanced billboards ≈ what Quasar could
never afford; with instancing + parallel paths + cull box it is one draw call and no
main-thread particle ticks of consequence. If it still reads heavy on min-spec, halve
`emissionRate` — density is the only knob that matters here.

---

## 7. Nether Breach — ash geyser loops + ember ribbon updrafts
(`eclipse:breach_ash_geyser` + `eclipse:breach_ember_updraft`)

The crater becomes a breathing vent: periodic ash geysers erupt from the chimney and
the ash **bounces off the crater lip** (real Photon collision vs the funnel blocks —
the module Quasar can't match), while ember ribbons ride the thermal out of the bowl.

**`.fx` object spec:**

`breach_ash_geyser.fx` (anchored at chimney mouth, `(centerX, lipY − 6, centerZ)`):

- `particle_emitter` `"geyser_core"`:
  - main: `duration: 160, looping: 1b, prewarm: 0, startLifetime: {random_constant
    40–70}, startSpeed: {curve over emitter t: lower 0.3, upper 1.6, two humps —
    segments [[0,0.2, 0.15,1, 0.3,0.25, 0.5,0.2],[0.5,0.2, 0.62,0.9, 0.8,0.2, 1,0.1]]}`
    (two eruption breaths per 8 s cycle), `startSize: NF3 {random_constant 0.15–0.35},
    simulationSpace: "World", maxParticles: 220`, **`parallelUpdate: 0b`** (collision).
  - emission: `emissionRate: {curve, same two-hump envelope, lower 0.4 upper 6}` —
    rate and speed pulse together = geyser breath; no bursts (loop-safe).
  - shape: `cylinder {radius: 2.2, radiusThickness: 0.35, arc: 360}` aimed +Y.
  - `physics {_enable:1b, hasCollision: 1b, removedWhenCollided: 0b,
    gravity: {constant 0.11}, friction: {constant 0.985},
    collidedFriction: {constant 0.6}, bounceChance: {constant 0.75},
    bounceRate: {constant 0.35}, bounceSpreadRate: {constant 0.25}}` — ash arcs up out
    of the throat, clips the overhanging lip ring and funnel wall
    (`BreachGeometry` netherrack/blackstone colliders) and scatters outward over the
    crimson-creep halo. The bounce IS the effect.
  - renderer: Billboard `smoke.png`, alpha blend `SRC_ALPHA/ONE_MINUS_SRC_ALPHA`,
    `vertexSortingMode: "DISTANCE"`, `shade: 1b` (lit like real ash),
    `colorOverLifetime` `#5A4A46`→`#2B2224`, alpha 0→0.8→0;
    cull box `{min:[-24,−10,−24], max:[24,26,24]}`.
- `particle_emitter` `"vent_glow"` — 20-particle soul-fire shimmer parked in the throat
  (`sphere r 1.6`, additive, `hdr [0.8,1.3,1.6,1]`, life 20–30, rate 0.6) — cheap light
  read under the geyser.

`breach_ember_updraft.fx` (same anchor):

- `particle_emitter` `"ember_risers"` — 4 carriers with ara ribbons.
  - `duration: 200, looping: 1b, startLifetime: {constant 190}, maxParticles: 4`,
    `emissionRate {constant 0.021}` (≈ one new riser as one dies),
    shape `circle {radius: 3.5, radiusThickness: 0.2}`.
  - `velocityOverLifetime {linear: [0, {random_constant 0.12–0.2}, 0],
    orbitalMode: "AngularVelocity", orbital: [0, {constant 0.5}, 0]}` — corkscrew
    thermal; `noise {frequency 0.6, Noise2D, position NF3 0.06}` wobble.
  - `trails {trailType: "ARA_TRAIL", lifetime {constant 0.35}, araConfig
    {thickness: 0.18, smoothness: 4, time: 1.2, colorOverLength `#FF9E4A`→`#6B1E10`→
    transparent, physicsSetting {gravity: [0,−0.05,0], inertia: 0.4, damping: 0.7}}}` —
    ribbons lag and whip in the updraft.
  - carrier material additive, `hdr [1.7, 0.9, 0.4, 1]` (ember bloom);
    `lights {_enable:1b, block 15}`.

**Trigger point (new loop window):** client class `BreachAmbience`
(`PhotonLoopWindow` school, §0). Anchor is client-computable with ZERO new sync:
`BreachGeometry.centerX()/centerZ()/lipY()` derive from `DiscMapData`/
`DiscTerrainFunction`, both already exercised client-side (`MapTab`,
`LimboHorizonShips`). Gate: overworld + camera within 96/110 hysteresis of the lip +
physical probe "crater interior is air at `lipY − 4`" (breach actually built — the
`SanctumLightfall` probe trick; `S2CBreachPayload OPEN/SETTLED` in `BreachClientFx`
can additionally warm the window instantly on the build beat). Release →
`LoopHandle.release()` (graceful).

**Quasar/vanilla fallback:** today's server ambience is untouched — the
`CAMPFIRE_COSY_SMOKE` lip ring + nether `SOUL_FIRE_FLAME/ASH` updraft
(`BreachTransferService.ambientTick`) keep running for everyone (LAYER). No new Quasar
asset required.

**Loop vs burst + perf:** true loop — the reason it ranks below the one-shots. Cost
ceiling: 220 colliding ash + ~24 glow + 4 ribbons, only while a camera is within ~110
blocks of ONE landmark. Collision on 220 particles is the most expensive item in this
doc (FX_FORMAT §9) — it is the point of the concept; if min-spec profiling complains,
drop `maxParticles` to 140 and `bounceChance` to 0.5 before touching anything else.
`reducedFx` kills it wholesale (bridge gate) — correct, this is garnish.

---

## 8. Fog Storm Sites — wall lightning veins + crown halo
(`eclipse:storm_wall_veins` + `eclipse:storm_crown_halo`)

Living electricity crawling the fog wall (beam_emitters with flicker + flipbook) and a
thin halo ring rotating above the storm crown.

**`.fx` object spec:**

`storm_wall_veins.fx` (spawned at a shell surface point, one per arc-flash):

- `empty` `"vein_root"` + 4 `beam_emitter` children `"seg_0..3"` forming one jagged
  vertical vein (beams are straight quads — chain them): seg_0
  `end: [0.8, 3.2, 0.3]`, seg_1 transform-offset to seg_0's tip, `end: [−1.1, 2.8, −0.4]`,
  seg_2 `end: [0.6, 3.5, 0.2]`, seg_3 `end: [−0.3, 2.6, 0.5]` (authored once in the
  editor; the per-spawn variety comes from the flicker curves + spawn position).
  - each: `duration: 5, looping: 0b` (= `StormFxClient.ARC_LIFE_TICKS`),
    `width: {random_curve, curves0/curves1 spiky 0.28→0.06 with different jitter}`
    (flicker), `emitRate: {constant 0}`, `raycast: "NONE"`,
    `color: gradient white core→`#B79CFF``, material `texture circle.png,
    hdr [2.4, 1.8, 3.2, 1]`, additive, `uvAnimation {_enable:1b, tiles: [1,4],
    animation: "WholeSheet", frameOverTime: curve 0→1}` if we ship a 4-frame crawl
    strip (optional; plain flicker already reads), `lights 15/15`.
- `particle_emitter` `"vein_sparks"` — 8 sparks burst off the vein base, life 6–10,
  additive, tiny.

`storm_crown_halo.fx` (one per storm, parked above the shell top):

- `particle_emitter` `"halo_ring"`:
  - `duration: 120, looping: 1b, startLifetime: {constant 110}, startSpeed 0,
    maxParticles: 90, emissionRate {constant 0.9}`;
    shape `circle {radius: 8, radiusThickness: 0.05}` with
    `shapeArc {arcMode: "Loop", arcSpeed: {constant 0.4}}` — the emission point orbits,
    laying a slowly rotating pearl-string crown;
    `velocityOverLifetime {orbital: [0, {constant 0.25}, 0]}` keeps laid particles
    revolving.
  - renderer: additive, faint `hdr [1.1, 0.9, 1.8, 1]`, sizes 0.15–0.3,
    `colorOverLifetime` violet in-hold-out; cull box `±12`.
  - Authored at unit storm (radius 8 wall). Storms vary — either accept the fixed crown
    (reads fine parked at `center + [0, wallHeight + 2, 0]` for all current storm
    sizes) or reflect `setScale(radius/8)` (API.md optional refinement 1) when the
    window spawns it.

**Trigger points (client-side layer inside the existing orchestrator — NOT new cues):**
`stormfx/StormFxClient` already owns per-storm client scheduling:

- Veins: the shell arc-flash scheduler (every 20–60 t per storm inside
  `ARC_RANGE = 160`) already picks a shell surface point and spawns `storm_arc` +
  micro-bolts — add `PhotonBridge.spawn(STORM_WALL_VEINS, arcPos)` beside it. Finite
  5 t asset, different BlockPos each flash → dedup never bites. This matches the
  "SEQUENCE-grade one-shot" law (low, storm-bounded frequency, distance-gated).
- Crown: one `PhotonLoopWindow` handle per `ClientStorm` while
  `camera within ARC_RANGE` (attach) / +20 hysteresis (release), spawned at
  `storm.center + [0, wallTop + 2, 0]`; released when the storm is removed from
  `STORMS` or the window closes.

**Quasar fallback:** the complete current stack — `StormWallRenderer` mesh,
`storm_arc` bursts, `vortex_wisp` spirals, bolts, churn loop, dread ladder — unchanged
(LAYER). Photon-less storms look exactly like today.

**Loop vs burst + perf:** veins are 5 t bursts of 4 beams + 8 sparks at ≤ 3/min/storm —
noise-level cost with big readability payoff. The crown is a 90-particle loop per
near-LOD storm (≤ 2 storms visible in practice). Beams have no per-tick particle cost
(two-point quad). `reducedFx` already halves the STORM budget on the Quasar side and
kills the Photon layer entirely.

---

## 9. Altar Sanctum — idle L5 corona ribbons (`eclipse:altar_corona_idle`)

The permanent "you finished the altar" tell: three lazy gold-violet ara ribbons
orbiting the altar crown, only at level 5, only up close. Complements #1 (the burst) —
this is the standing state.

**`.fx` object spec:**

- `particle_emitter` `"corona_carriers"` — 3 eternal orbiters with ribbons.
  - `duration: 100, looping: 1b, prewarm: 100` (the ring is already formed when the
    window materializes — no cold start), `startLifetime: {constant 95},
    maxParticles: 3, emissionRate {constant 0.032}`;
    shape `circle {radius: 2.6, radiusThickness: 0f}` with
    `shapeArc {arcMode: "Loop", arcSpeed {constant 0.33}}` (carriers born evenly around
    the ring);
  - `velocityOverLifetime {orbitalMode: "AngularVelocity", orbital: [0,
    {constant 0.6}, 0], offset: [0,0,0]}` + a slow vertical breathing via
    `linear: [0, {curve −0.02→0.02 sine-ish two-segment}, 0]`.
  - `trails {trailType: "ARA_TRAIL", ratio 1.0, lifetime {constant 0.4},
    inheritParticleColor: 0b, araConfig {section: default strip, thickness: 0.16,
    smoothness: 6, highQualityCorners: 1b, cornerRoundness: 8, time: 1.6,
    timeInterval: 0.05, colorOverLength: gradient `#FFE9B0`→`#B47DFF`→transparent,
    thicknessOverLength: curve 0.6→1→0.1 (leaf-shaped ribbon),
    physicsSetting {inertia: 0.3, velocitySmoothing: 0.8, damping: 0.75}}}`.
  - carrier renderer: additive `circle.png`, `hdr [1.6, 1.3, 1.0, 1]` — warm bloom
    beads leading each ribbon; `lights 15/15`;
    cull box `{min:[-5,-1,-5], max:[5,6,5]}`.
- `particle_emitter` `"corona_dust"` — 30-cap glitter inside the ring volume
  (`sphere r 2.4, thickness 0.6`), rate 0.4, life 30–50, size 0.03–0.07, additive faint
  hdr — fills the ring's body between ribbons.

**Trigger point (loop window):** extend the existing altar idle machinery — a
`PhotonLoopWindow` beside `client/drama/AltarIdleMotes` (same event class or a sibling):
window = `FxAnchors.get(ALTAR_CENTER) != null` (shipped anchor, login-resynced) +
`ClientStateCache.altarLevel >= 5` (shipped sync via `S2CDayStatePayload`) + camera
within 48/60 hysteresis; spawn at `anchor + [0, 3.2, 0]` (above `AltarVeilSky`'s crown
read); `LoopHandle.release()` on any gate failing. The L5 gate means at most ONE such
loop exists per world, endgame only.

**Quasar fallback:** the shipped idle stack — `AltarIdleMotes` (level-scaled motes +
L4 halo patches + L3 helix), `SanctumLightfall`, `AltarVeilSky` crown — unchanged
(LAYER). Photon-less clients keep today's full L5 read.

**Loop vs burst + perf:** loop, but the cheapest possible one: 3 carriers + 3 ribbons +
≤ 30 dust. Ara smoothing on 3 ribbons is negligible. Prewarm 100 = one-time cost at
window entry (FX_FORMAT §9 warns prewarm ≤ duration — it is exactly duration, fine).

---

## 10. Wizard Hut (Orin's Observatory) — chimney spark loop + window glow motes
(`eclipse:wizard_hearth`)

Cozy-scale ambience: hearth sparks curling from the copper dome seam and warm motes
hanging in the lantern light. Smallest concept, lowest priority — pure charm.

**`.fx` object spec** — one file, 3 emitters (root `empty` at the hut anchor =
summit surface pos, so offsets are authorable against the deterministic build):

- `particle_emitter` `"chimney_sparks"` — offset `[1.5, 6.5, −1]`-ish (dome seam vent;
  exact offset read from `WizardObservatory.buildAt` geometry in the editor session).
  - `duration: 90, looping: 1b, startLifetime: {random_constant 24–40},
    startSpeed: {random_constant 0.08–0.18}, startSize NF3 {random_constant 0.04–0.09},
    maxParticles: 40, emissionRate {curve gusty: lower 0.1 upper 1.2, two random humps}`;
    shape `cone {angle: 12, radius: 0.15}`.
  - `noise {frequency 0.9, Noise2D, position NF3 0.05}` (wind curl);
    `velocityOverLifetime {linear [ {random_constant −0.02–0.02}, {constant 0.06},
    {random_constant −0.02–0.02} ]}`;
    `colorOverLifetime` `#FFD27A`→`#E2571E`→out; additive, `hdr [1.5, 0.8, 0.3, 1]`
    (tiny ember bloom); `lights {block 15}`.
- `trail_emitter` `"smoke_wisp"` — one thin standalone smoke strip rising from the same
  vent: `duration: 90, looping: 1b, time: 30, minVertexDistance: 0.05,
  smoothInterpolation: 1b, widthOverTrail: {curve 0.25→0.05},
  colorOverTrail: gradient `#3A3430` alpha 0.35→0`, smoke.png alpha blend — the emitter
  itself is static, so drive drift with the shape position NF3 curves (slow sway over
  emitter t). (Cheapest ribbon in the doc — plain `trail_emitter`, no ara physics.)
- `particle_emitter` `"window_motes"` — offset into the interior band
  (`[0, 1.5, 0]`, shape `box {emitFrom: "Volume"}` scale `[3.4, 1.6, 3.4]` ≈ the
  hut interior).
  - `duration: 120, looping: 1b, startLifetime {random_constant 60–100}, startSpeed 0,
    size 0.02–0.05, maxParticles: 50, emissionRate {constant 0.5}`;
    `noise` drift only; warm `colorOverLifetime` `#FFE9C0` alpha 0→0.35→0;
    additive faint (`hdr [0.6,0.5,0.3,1]`), `lights {block 15}` — dust motes floating
    in lantern light, visible through the windows at night.
  - cull box whole-hut `{min:[-7,-2,-7], max:[7,9,7]}`.

**Trigger point (loop window, zero new packets preferred):** `PhotonLoopWindow` class
`ObservatoryAmbience`: the anchor is client-derivable — `DiscMapData.get()
.profile(OVERWORLD).mountain()` center + `DiscTerrainFunction.surfaceY` (both proven
client-side, `MapTab`), which is exactly `WizardObservatory`'s summit anchor. Gate with
the physical probe "hut wall block present at anchor+known offset" (only true once the
observatory is stamped — the `SanctumLightfall` probe law), window 48/60 hysteresis.
Alternative (if the probe feels brittle in review): one new `FxAnchors.WIZARD_HUT`
published where the build completes / `ObservatoryVersionData` is found stamped —
anchors are login-resynced for free, but it costs a server-side touch; the probe
version costs nothing.

**Quasar fallback:** none exists today and none is required (pure garnish — absence is
today's behavior). If reviewers want parity for photon-less clients, author a 10-line
Quasar `wizard_hearth_motes` loop and run it as the base layer with Photon in
`Mode.REPLACE`; recommended but optional.

**Loop vs burst + perf:** loop; ≤ 90 tiny particles + one plain trail strip, one
landmark, ≤ 60-block window. The cheapest concept in the doc — ranked last only because
it depends on the loop-window pattern and no gameplay beat points at it.

---

## Authoring / shipping checklist (applies to all 10)

1. Author in the singleplayer dev client (`run/mods-client` already carries
   photon 2.1.5 + ldlib2 2.2.29 via `tools/modpack/fetch_dev_mods.py`):
   `/photon_editor fx_editor` → export `.fx` → `src/main/resources/assets/eclipse/fx/`,
   commit the `.fxproj` beside it (INTEGRATION.md §6).
2. Iterate in-world against the REAL cue: `/eclipsefx rift open|close`,
   `/eclipsefx supplybeam test`, `/eclipsefx storm add …`, `/eclipsefx emitter …`
   (`FxDevCommands`), plus `/photon fx eclipse:<id> block ~ ~ ~` for raw placement and
   `/photon_client clear_client_fx_cache` after re-export.
3. New ids: add the `ResourceLocation` constant to `PhotonBridge` (or a
   `PhotonFxRegistry` row once that lands) — nothing else registers anywhere.
4. Verify the degradation ladder per effect: photon absent → missing asset (one INFO)
   → `reducedFx` → all must render exactly today's visuals (risk table,
   INTEGRATION.md §5).
5. Loops (7–10) land only WITH the `PhotonLoopWindow` pattern + the
   `getRuntime/destroy` bridge growth (§0) and a one-paragraph law amendment in
   INTEGRATION.md §4 ("client-windowed Photon loops: hysteresis window, cull box,
   maxParticles cap, release-on-reducedFx mandatory").
