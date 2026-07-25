# Photon `.fx` Concepts — BOSS FIGHT domain (PHOTON-IDEAS-1, 2026-07)

Scope: fully-specified Photon effect concepts for the four bosses — **Herald**
(`entity/boss/HeraldEntity`), **Ferryman** (`entity/boss/FerrymanEntity`), **Fog Tyrant**
(`entity/boss/fog/FogTyrantEntity`), **Rift Warden** (`entity/boss/rift/RiftWardenEntity`).
Grounded exclusively in the definitive companions: `API.md` (runtime surface),
`FX_FORMAT.md` (schema — all field names/enums below are verbatim from it),
`INTEGRATION.md` (wiring laws: server photon-blind, `FxCues` → `PhotonFxRegistry` rows over
the existing `S2CFxEventPayload` lane, LAYER-over-Quasar degradation, `reducedFx` kill
switch, no `FxBudget` charge on the Photon leg).

Conventions used below:

- **Asset ids** are `eclipse:boss/<name>` → `src/main/resources/assets/eclipse/fx/boss/<name>.fx`
  (compressed NBT; author in `/photon_editor`, commit the `.fxproj` beside it — binary-blob law).
- **NF** = NumberFunction (`constant` / `random_constant` / `curve` / `gradient` …); curves are
  cubic-Bézier over the module's t axis; times in **ticks**, sizes in **blocks**.
- **HDR** = material `hdr: [r,g,b,1]` + `hdrMode: "ADDITIVE"` — values > 0 push pixels over the
  bloom threshold (client `photon-client.toml` default threshold 1.0, intensity 0.7).
- Every concept is **non-looping one-shot** unless stated (INTEGRATION.md §4 law: Photon rows are
  sequence-grade one-shots; loops only via the re-fire+dedup pattern documented per concept).
- **Trigger** rows name the exact server method + the proposed `FxCues` id; all ride the existing
  `S2CFxEventPayload` (`FxPayloads.sendFxEvent(level, id, pos, a, b, range)`) — no protocol bump.
- **Quasar fallback** = the `PhotonFxRegistry.Entry(photonFx, quasarEmitter, channel, mode)` row;
  emitters cited exist in `assets/eclipse/quasar/emitters/`.

## Prerequisites / blockers (read first)

1. **`PhotonBridge` today only reflects `BlockEffectExecutor`** (block-anchored, no rotation).
   Concepts 3, 5, 8 need TWO mechanical, verified-available extensions (API.md §1/§6,
   INTEGRATION.md design law #5): `EntityEffectExecutor(FX, Level, Entity, AutoRotate)` +
   `AutoRotate.valueOf(...)` (→ `PhotonBridge.spawnOnEntity(fxId, entity, autoRotate)`), and
   `setRotation(Quaternionf)` / `setOffset(Vector3f)` on the abstract executor (→ yaw-aimed
   block-anchored effects; yaw crosses the wire in the payload's free `a` float).
2. **No stop API in the bridge** — long-lived states (kneel corona #9, fog arms #10) use finite
   `duration` + server **re-fire on cadence**; `allowMulti=false` dedup makes the re-fire a free
   no-op while the previous runtime is alive (API.md §3 repeat-fire gotcha, used as a feature).
3. **Sub-emitter concepts ship ≥ 2 `.fx` files** (`subEmitters.emitters[].fxLocation` references
   another whole `.fx` by ResourceLocation) — both files must land or the child event silently
   no-ops (fail-soft, FX_FORMAT.md §8).
4. `mesh` shape / `Model` render mode use **baked block/item models only** — geckolib geo
   (Fog Tyrant, Rift Warden bodies) is not emission geometry. Concepts needing silhouettes use
   vanilla baked models (`block/soul_lantern`) or a tiny shipped JSON model (`eclipse:item/fog_tendril`).
5. Editor is **singleplayer-only**; no `.fx` exists in the repo yet — every concept below is an
   authoring work item. Multiplayer reminder (INTEGRATION.md §2 Verdict C): photon+ldlib2 must be
   installed on the dedicated server for Photon-equipped clients to join at all.

---

## Ranked concepts

### 1. `eclipse:boss/roar_shockwave` — Herald arrival roar ring (HDR bloom) — **highest impact**

One shared, boss-agnostic "roar" ring: a ground-hugging expanding HDR ring + vertical light
column + spark sheet. Reused by all four bosses (summon arrival + phase breaks), so one authored
asset upgrades ~10 existing beats.

**.fx object list** (3 objects, flat, all parented to root):

| name | type | config |
|---|---|---|
| `roar_ring` | `particle_emitter` | `duration: 30, looping: 0b, maxParticles: 4`; emission rate 0 + one burst `{time: 0, count: 1, cycles: 1, probability: 1.0}`; `shape: dot`; `startLifetime: constant 26`; `startSize: NF3 constant (1,1,1)`; `startSpeed: 0`; `simulationSpace: World`. `renderer.renderMode: "Horizontal"` (flat on the floor), `facingMode: DEFAULT`, `shade: 0b`. `sizeOverLifetime` NF3 `curve` lower 0 upper 30, one segment `[0,0.04, 0.15,0.9, 0.6,1, 1,1]` (fast-out ease ≈ the FX_SHOCKWAVE read). `colorOverLifetime: gradient` a=`[0,1, 0.7,0.8, 1,0]`, rgb violet-white `[0, 0.9,0.8,1,  1, 0.45,0.2,0.7]` |
| `roar_column` | `particle_emitter` | burst 1, `shape: dot`, lifetime 18, `renderMode: "VerticalBillboard"`, `startSize: (2.5, 10, 2.5)`, `sizeOverLifetime` shrink-X curve (upper 1 → 0.1); same gradient; `lights {_enable:1b, skyLight/blockLight: constant 15}` |
| `roar_sparks` | `particle_emitter` | `duration: 30, looping: 0b, maxParticles: 96`; burst `{time: 2, count: 64}`; `shape: sphere {radius: 1.2, radiusThickness: 0f}` (shell → clean radial); `startSpeed: random_constant 0.5–1.1`; `startLifetime: random_constant 10–22`; `startSize: random_constant 0.05–0.12` ×3; `physics {_enable:1b, gravity: constant 0.2, friction: 0.97, bounceChance: 0}`; `colorOverLifetime` white→violet fade |

**Material/blend (all three)**: `texture` material — ring uses a shipped
`eclipse:textures/particle/ring_soft.png`, column/sparks reuse the bundled
`photon:textures/particle/circle.png`. `hdr: [1.6, 1.1, 2.2, 1]`, `hdrMode: "ADDITIVE"` on ring +
column (bloom halo); sparks `hdr: [0.8, 0.6, 1.2, 1]`. Blend: `srcColorFactor: "SRC_ALPHA",
dstColorFactor: "ONE"` (additive), `blendFunc: "ADD"`, `depthMask: 0b`, `layer: "Translucent"`,
`vertexSortingMode: "NONE"` (additive is order-independent).

**Cull box**: `renderer.cull {_enable:1b, cullBox: {min:[-32,-2,-32], max:[32,12,32]}}` on the
ring (it grows to r=30); `[-4,-1,-4]..[4,11,4]` on column/sparks.

**Trigger**: new `FxCues.CUE_BOSS_ROAR`. Server sends from (a) `HeraldEntity.summon` beside the
existing `ALTAR_BEAM` quasar + `BOSS_HERALD_ROAR_FAR` sound, (b) `HeraldEntity.updatePhase` P3
branch beside its `BOSS_SLAM` send, (c) `FerrymanEntity.summonAtStern`'s `BOSS_SLAM`,
(d) `FogTyrantEntity`/`RiftWardenEntity` summon + phase-break sites. Client:
`PhotonFxRegistry.dispatch` tail branch in `FxPayloads.handleFxEvent` (INTEGRATION.md §3 flow).

**Quasar fallback**: `Entry(boss/roar_shockwave, boss_slam, FxBudget.Channel.BURST, Mode.LAYER)` —
the Veil `FX_SHOCKWAVE`/`boss_slam` layer keeps running on photon-less clients; identical wire bytes.

**Budget**: ≤ 101 particles, ~30t life, one-shot, ≤ 6 sends per whole fight. `allowMulti` stays
false — a double summon dedups. Cheapest concept per screen-impact unit; do this one first.

---

### 2. `eclipse:boss/tyrant_death_implosion` (+ child `eclipse:boss/fog_debris_puff`) — Fog Tyrant death implosion with collision sub-emitters

The C8 thunderclap keyframe (storm explodes, site retires) gets a physical read: the storm
**inhales** into the chest core, then detonates into debris that **bounces off the real arena
floor** and puffs fog where it lands — Photon-only capability (world-collider physics +
`Collision` sub-emitters, FX_FORMAT.md §7 pts 5/4).

**.fx object list — `tyrant_death_implosion`** (4 objects):

| name | type | config |
|---|---|---|
| `indraw` | `particle_emitter` | `duration: 24, looping: 0b`; burst `{time: 0, count: 90}`; `shape: sphere {radius: 7, radiusThickness: 0.15}`; `startSpeed: constant 0` — motion comes from `velocityOverLifetime {_enable:1b, radial: curve lower −1.4 upper 0, seg [0,0.1, 0.4,0.6, 1,1]}` (accelerating inward suck); `startLifetime: random_constant 16–24`; `startSize` 0.15–0.35; `colorOverLifetime` gradient white-ash → storm-teal, alpha peak mid-life |
| `core_flash` | `particle_emitter` | `startDelay: constant 24`; burst 1; dot; lifetime 8; `renderMode: Billboard`; `startSize (4,4,4)` with `sizeOverLifetime` pop curve `[0,1, 0.2,0.4, 1,0.05]`; HDR `[3,3,3.5,1]` — the bloom white-out beat |
| `debris` | `particle_emitter` | `startDelay: 24`; `duration: 50, looping: 0b, maxParticles: 80`; burst `{time: 0, count: 56}`; `shape: sphere {radius: 0.6, radiusThickness: 1}`; `startSpeed: random_constant 0.6–1.6`; `simulationSpace: "World"`; `physics {_enable:1b, hasCollision:1b, gravity: constant 0.5, friction: 0.99, collidedFriction: 0.55, bounceChance: 0.5, bounceRate: 0.35, bounceSpreadRate: 0.15, removedWhenCollided: 0b}`; `renderMode: "StretchedBillboard"`, `velocityScale: 0.6, lengthScale: 1.5`; `subEmitters {_enable:1b, emitters: [{fxLocation: "eclipse:boss/fog_debris_puff", event: "FirstCollision", emitProbability: constant 0.6, inheritColor: 1b, inheritLifetime: 0b}]}` |
| `ground_ring` | `particle_emitter` | `startDelay: 26`; the concept-1 ring recipe scaled to r=14, teal-white gradient (visual echo under the `StormRegistry.explode` shell burst) |

**Child `fog_debris_puff`** (1 object): `particle_emitter`, `duration: 20, looping: 0b`, burst
`{count: 5}`, `shape: sphere {radius: 0.25}`, lifetime 12–18, `startSize` 0.3–0.6 growing via
`sizeOverLifetime` (upper 2), CLOUD-grey `colorOverLifetime` fade, **alpha blend**
(`dstColorFactor: "ONE_MINUS_SRC_ALPHA"`, `vertexSortingMode: "DISTANCE"`), no HDR, `shade: 1b`.

**Materials**: `indraw`/`debris` additive `photon:textures/particle/circle.png`, debris HDR
`[1.2,1.4,1.6,1]`; `core_flash` HDR as above; puff plain.

**Cull box**: `{min:[-16,-3,-16], max:[16,10,16]}` on the parent objects; puff `±2`.

**Trigger**: `FogTyrantEntity.tickDeath` at `DEATH_THUNDERCLAP_TICK` (t=60), directly beside the
existing `fogBurstFx(...)` + `explodeHostStorm(...)` calls — new `FxCues.CUE_TYRANT_DEATH_IMPLOSION`
sent once at `position()+ (0,1.5,0)`. (Timeline fits: implosion 24t + burst lands inside the
70t collapse window; the existing `FX_SHOCKWAVE` at range 160 stays untouched.)

**Quasar fallback**: `Entry(boss/tyrant_death_implosion, boss_slam, BURST, Mode.LAYER)` — the
shipped thunderclap already carries `fogBurstFx` + `FX_SHOCKWAVE`; Photon-less clients lose
nothing.

**Budget**: physics collision is Photon's most expensive module (FX_FORMAT.md §9) — capped at 80
debris, once per boss LIFETIME. Child puffs ≤ 5 particles × ≤ 34 spawns worst-case. Keep
`parallelUpdate: 0b` (collision needs level access). Two-asset delivery (blocker #3).

---

### 3. `eclipse:boss/warden_eye_laser` — Rift Warden `beam_emitter` volley telegraph

The 20t rooted volley raise (`RiftWardenEntity.tickVolley`, `VOLLEY_TELEGRAPH_TICKS = 20`)
currently reads as sound + WITCH boil. A raycast-clipped violet laser from the void-half "eye"
sweeping onto the aimed player makes the dodge readable at a glance — first use of
`beam_emitter` + `raycast: BLOCKS` (beam visibly stops at pillars, teaching that blocks stop bolts).

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `eye_laser` | `beam_emitter` | `duration: 20, looping: 0b`; `end: [0, 0, -24]` (local −Z, clamped by `raycast: "BLOCKS"`, `raycastBlockMode: "VISUAL"`, `raycastFluidMode: "NONE"`); `width: curve` lower 0.04 upper 0.28, one segment `[0,0.15, 0.55,0.35, 0.9,1, 1,1]` (thin flicker → committed beam right before release); `emitRate: 0` (continuous); `color: gradient` over the beam — a=`[0,0.85, 1,0.35]`, rgb `[0, 0.75,0.3,1,  1, 0.3,0.1,0.5]`; `uvAnimation {_enable:1b, tiles:[1,4], animation:"SingleRow", frameOverTime: curve 0→1}` scrolling energy; `lights {_enable:1b, 15/15}` |
| `eye_charge` | `particle_emitter` | `duration: 20, looping: 0b`; `emissionRate: constant 2.5`; `shape: sphere {radius: 0.9, radiusThickness: 0}`; `velocityOverLifetime {radial: constant −0.5}` (motes sucked INTO the eye — classic charge tell); lifetime 8–12, size 0.04–0.1, additive violet, HDR `[1.5,0.8,2.2,1]` |

**Material/blend**: beam `texture` `eclipse:textures/particle/beam_core.png` (authored 4-frame
strip), `hdr: [2.0, 0.9, 3.0, 1]` ADDITIVE — the beam itself blooms; additive blend, `depthTest: 1b`,
`depthMask: 0b`.

**Cull box**: `{min:[-1,-1,-26], max:[1,3,1]}` (beam volume, local).

**Trigger**: needs **`spawnOnEntity` (blocker #1)** — `EntityEffectExecutor(FX, Level, warden,
AutoRotate.LOOK)`: the executor re-anchors to `entity.getEyePosition()` every frame and `LOOK`
orients −Z along facing; the warden already `getNavigation().stop()`s and faces the target during
the raise, so aim is free. Client entry: `FxPayloads.handleFxEvent` on new
`FxCues.CUE_WARDEN_VOLLEY_TELEGRAPH` (sent in `RiftWardenEntity.tickVolley` at telegraph start,
beside the BEACON_POWER_SELECT sound), resolving the warden via
`nearestEntityOfType(RiftWardenEntity.class, pos)` on the client level (glide-trail
`nearestPlayer` pattern already in `FxPayloads`). Auto-cleanup: entity death kills the runtime.

**Quasar fallback**: no matching Quasar shape — `Entry(boss/warden_eye_laser, null, BURST,
Mode.LAYER)`; the shipped WITCH-boil + resonate telegraph remains the base layer.

**Budget**: 1 beam quad + ~50 motes for 20t, fires every 120t (P1) / 70t (P2). Highest cadence in
this list but trivially cheap (beam = one raycast + one quad per frame). Non-looping duration
exactly matches the telegraph, so no stop call is ever needed.

---

### 4. `eclipse:boss/ferry_lantern_swarm` — Ferryman P2 soul-lantern swarm (mesh/model particles)

When the Ferryman kneels (`startCrewPhase`), the blown-out deck lanterns visually "rise": a swarm
of **actual soul-lantern models** (`renderMode: "Model"` + `block_atlas` — Photon-only capability)
spirals out of the boss and disperses toward the ring, selling "the crew phase stole the light".

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `lantern_swarm` | `particle_emitter` | `duration: 80, looping: 0b, maxParticles: 24`; bursts `{time: 0, count: 6}, {time: 10, count: 6, cycles: 3, interval: 10}`; `shape: circle {radius: 2.2, radiusThickness: 0.3, arc: 360, shapeArc {arcMode: "BurstSpread"}}` (even spacing per burst); `startSpeed: constant 0.05`; `startLifetime: random_constant 50–70`; `startSize: random_constant 0.5–0.7` ×3 (lantern-scale); `startRotation` yaw `random_constant 0–360`; `renderer {renderMode: "Model", useBlockUV: 1b, modelPivot: [0.5, 0.5, 0.5]}` with the mesh shape's model — **`shape` alt-config note**: author via editor's mesh shape `meshData {modelLocation: "block/soul_lantern"}` so the renderer bakes the vanilla soul-lantern model; `facingMode: "ROTATE_Y"`; `velocityOverLifetime {_enable:1b, linear: (0, random 0.02–0.05, 0), orbitalMode: "AngularVelocity", orbital: (0, 0.35, 0), offset: (0,0,0)}` — slow rising counter-clockwise carousel; `rotationOverLifetime {yaw: random_constant −3–3}` lazy tumble; `noise {_enable:1b, frequency: 0.5, quality: "Noise2D", position: (0.04, 0.02, 0.04)}` bobbing; `simulationSpace: "Local"` (follows the kneel anchor); `shade: 1b` (models must take deck lighting) |
| `soul_leak` | `particle_emitter` | `duration: 80, looping: 0b`; `emissionRate: 1.2`; `shape: circle {radius: 2.4}`; teal soul-flame motes, lifetime 20–30, size 0.06–0.14, additive `photon:textures/particle/circle.png`, HDR `[0.4, 1.3, 1.2, 1]` (teal bloom kiss), `lights 15/15` |

**Material/blend**: swarm = `block_atlas` material (singleton, no HDR field — models stay diegetic),
`layer: "Translucent"`, `cull: 1b`, `depthMask` **1b** for the opaque lantern models
(order-correct against the ship); motes additive as usual.

**Cull box**: `{min:[-8,-1,-8], max:[8,7,8]}`.

**Trigger**: `FerrymanEntity.startCrewPhase` (both the ship branch after `ShipLanterns.extinguish`
and the arena branch after `ArenaBuilder.extinguishRing`) — new `FxCues.CUE_FERRY_LANTERN_SWARM`
at the stern anchor. One-shot 80t; the kneel lasts far longer, but the swarm is the *entrance*
beat — the sustain is concept 9.

**Quasar fallback**: `Entry(boss/ferry_lantern_swarm, limbo_motes, AMBIENT, Mode.LAYER)` — soul
motes at the stern approximate the read; the SOUL flicker walk in `tickArenaKneel` stays.

**Budget**: 24 model particles is the heavy renderer path — but once per crew phase (≤ 2 per
fight). Keep `useGPUInstance: 0b` at this count. Verify soul-lantern model bakes with correct
pivot in the editor before shipping (drop to `"block/lantern"` if the soul variant reads muddy).

---

### 5. `eclipse:boss/herald_shard_trail` — Herald shard barrage `ara_trail` ribbons

Every `HeraldShardProjectile` (3 per volley, `HeraldEntity.tickVolley`) drags a physics-lagged
violet ribbon (`ara_trail_emitter`: Catmull-Rom smoothing, segment inertia — Photon-only vs
Quasar's point trail). Homing curves become visible arcs; the END_ROD breadcrumb becomes a comet.

**.fx object list** (1 object):

| name | type | config |
|---|---|---|
| `shard_ribbon` | `ara_trail_emitter` | `duration: 100, looping: 1b` (**loop is safe here**: the runtime is entity-bound and dies with the projectile ≤ ~5 s later); `section`: default flat strip; `space: "World"` (ribbon must hang in the air behind the shard); `alignment: "View"`; `sorting: "NewerOnTop"`; `thickness: 0.18`; `smoothness: 4`; `highQualityCorners: 0b`; `time: 0.45` (segment life s ≈ 9t tail), `timeInterval: 0.05`, `minDistance: 0.05`; `thicknessOverLength: curve` lower 0 upper 1, seg `[0,1, 0.4,0.85, 0.9,0.2, 1,0]` (taper to nothing); `colorOverLength: gradient` a=`[0,0.9, 1,0]`, rgb white-hot head → deep violet tail `[0, 1,0.95,1,  0.35, 0.75,0.4,1,  1, 0.3,0.1,0.5]`; `physicsSetting {gravity: [0,−0.4,0], inertia: 0.25, velocitySmoothing: 0.75, damping: 0.8}` — the tail sags and whips on homing turns |

**Material/blend**: `texture` `photon:textures/particle/circle.png` stretched
(`textureMode: "Stretch"`), additive, `hdr: [1.3, 0.7, 2.0, 1]` ADDITIVE — the head blooms softly;
`depthMask: 0b`.

**Cull box**: `{min:[-3,-3,-3], max:[3,3,3]}` (executor follows the projectile, box rides along).

**Trigger**: needs **`spawnOnEntity` (blocker #1)** with `AutoRotate.NONE`. Cleanest seam is
client-side, NOT a payload: in `HeraldShardProjectile.tick()`'s existing `isClientSide` branch
(where the END_ROD breadcrumb spawns), on first client tick call
`PhotonBridge.spawnOnEntity(HERALD_SHARD_TRAIL, this, NONE)` — per-entity `CACHE` dedup makes
repeats free, entity death auto-destroys the ribbon at `shatter()`. No wire change at all.

**Quasar fallback**: none needed — the vanilla END_ROD breadcrumb in the same branch stays
(LAYER semantics in code: Photon spawn failure changes nothing). Registry row not required since
this is not payload-driven (same exemption as `RiftFx.openRift`, INTEGRATION.md §3 law 4).

**Budget**: 3 ribbons per volley, volleys every 60t (P1) / 90t (P2) — this **bends the
"sequence-grade one-shots" law**; justification: ara ribbons are vertex strips, not particles
(~40 verts each), auto-cleaned, and the whole cost is 3 live ribbons max. Gate: skip spawns when
> 6 `EntityEffectExecutor.CACHE` entries alive (belt-and-braces in the bridge helper).

---

### 6. `eclipse:boss/tyrant_blind_burst` — Fog Tyrant blind-squall HDR flash

`releaseSquall` is an audio-first dodge ("break LOS by ear"); the release itself deserves a
retina-burn: a bloom white-out sphere + three expanding fog shells replacing the flat CLOUD rings.
The flash punishes exactly the players who could SEE the tyrant — thematically perfect for HDR.

**.fx object list** (3 objects):

| name | type | config |
|---|---|---|
| `flash_core` | `particle_emitter` | burst 1 at t=0; dot; lifetime 6; `renderMode: Billboard`; `startSize (6,6,6)`; `sizeOverLifetime` curve `[0,0.3, 0.1,1, 1,0.65]` with `colorOverLifetime` alpha crash `[0,1, 0.5,0.9, 1,0]`; **HDR `[4,4,4,1]`** — deliberately over-driven so the bloom bright-pass whites the area out for ~4t |
| `fog_shells` | `particle_emitter` | `duration: 26, looping: 0b, maxParticles: 180`; bursts `{time: 0, count: 60}, {time: 5, count: 60}, {time: 10, count: 60}` on `shape: sphere {radius: 0.8, radiusThickness: 0}` with `startSpeed` per-burst spread via `random_constant 0.9–1.3` (three staggered shells ≈ the shipped 3/7/12 radii); lifetime 14–22; `startSize` 0.4–0.8 growing (`sizeOverLifetime` upper 2.2); grey-white alpha-blend cloud gradient, `vertexSortingMode: "DISTANCE"`, `shade: 1b` |
| `crown_arcs` | `particle_emitter` | `duration: 8`; burst `{count: 10}`; `shape: circle {radius: 1.6}` at crown height (transform `localPosition [0, 3.4, 0]`); `renderMode: "StretchedBillboard"`, `velocityScale: 1.2`; electric white, HDR `[2.2, 2.2, 2.6, 1]`; lifetime 4–7 |

**Material/blend**: flash + arcs additive HDR (above); shells plain alpha blend, no HDR (fog must
occlude, not glow).

**Cull box**: `{min:[-14,-2,-14], max:[14,8,14]}`.

**Trigger**: `FogTyrantEntity.releaseSquall`, beside the WARDEN_SONIC_BOOM/ELDER_GUARDIAN_CURSE
pair — new `FxCues.CUE_TYRANT_SQUALL` at `position()+(0,1.2,0)`. (Optional second send at
`maybeStartSquall` for a windup shimmer was considered and dropped — the windup already has the
WHITE_ASH inhale; keep Photon on the release beat only.)

**Quasar fallback**: `Entry(boss/tyrant_blind_burst, boss_slam, BURST, Mode.LAYER)`; shipped
CLOUD rings remain the base.

**Budget**: ≤ 191 particles, 26t, every 300t (scaled by enrage) in P2+ — comfortably inside the
one-shot law. The 4.0 HDR flash is the one flag to sanity-check against `bloom_threshold 1.0` on
Iris (INTEGRATION.md §4 watch item) — if the Iris pair test shows clipping, drop to `[2.5,2.5,2.5,1]`.

---

### 7. `eclipse:boss/warden_glitch_orbit` — Rift Warden stagger glitch-shard orbit (GL blend-equation tricks)

During the P2 weakpoint (`beginStagger`, 40t rooted, ×1.5 damage), the void half destabilizes:
obsidian glitch shards orbit the core, rendered with **`blendFunc: "REVERSE_SUB"`** (subtractive —
they *darken* the scene into "holes in reality", impossible in Quasar) interleaved with additive
counterparts, plus a MAX-blend static flicker. Multi-material multi-pass on one emitter.

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `glitch_shards` | `particle_emitter` | `duration: 40, looping: 0b, maxParticles: 26`; burst `{time: 0, count: 22}`; `shape: sphere {radius: 1.1, radiusThickness: 0.2}` centered on the core (transform `localPosition [0, 1.6, 0]`); `startSpeed: 0`; `velocityOverLifetime {_enable:1b, orbitalMode: "AngularVelocity", orbital: (0, random_constant 2.5–4.5, 0), offset: (0,0,0)}` — fast Y orbit at mixed rates so the ring shears; `startLifetime: random_constant 30–40`; `startSize: random_constant 0.1–0.3`; `startRotation` roll 0–360 + `rotationOverLifetime {roll: random_constant −25–25}` deg/t jitter; `noise {_enable:1b, frequency: 3.0, quality: "Noise3D", position: (0.12, 0.12, 0.12), remap {_enable:1b, remapCurve: step-ish curve [0,0, 0.45,0, 0.55,1, 1,1]}}` — remapped noise = **teleport-snap displacement**, the glitch signature; `uvAnimation {_enable:1b, tiles: [2,2], animation: "WholeSheet", frameOverTime: random_curve (two ramps), cycle: 3}` flipbook flicker. **`renderer.materials` ROM-list with 2 passes** (`{uid: 2, payload: [...]}`): pass 1 `texture eclipse:textures/particle/glitch_shard.png` (2×2 sheet), `blendMode {srcColorFactor: "SRC_ALPHA", dstColorFactor: "ONE", blendFunc: "REVERSE_SUB"}` — subtracts scene color under shard alpha (void bite); pass 2 same texture, standard additive `ADD` with `hdr [1.4, 0.5, 2.0, 1]`, drawn as thin violet rims (`discardThreshold: 0.45` eats the fill, leaving edges). `orderInLayer: 1` above concurrent effects |
| `static_veil` | `particle_emitter` | `emissionRate: 1.0`, `duration: 40`; `shape: box {emitFrom: "Shell"}` scaled `(1.2, 2.6, 1.2)`; lifetime 4–7 (strobing motes); material `texture` white-noise strip with `blendFunc: "MAX"` (lighten-only sparkle that never over-accumulates); size 0.05–0.1 |

**Cull box**: `{min:[-3,-1,-3], max:[3,4,3]}`.

**Trigger**: `RiftWardenEntity.beginStagger` beside the AMETHYST_CLUSTER_BREAK sound — new
`FxCues.CUE_WARDEN_STAGGER` at `position()`. Duration 40t = `STAGGER_TICKS` exactly, so the orbit
collapses the moment the weakpoint closes; a block-anchored spawn is fine (the warden is rooted
for the whole window) — **no entity executor needed**, works with today's bridge + `setOffset`.

**Quasar fallback**: `Entry(boss/warden_glitch_orbit, border_glitch, BURST, Mode.LAYER)` —
`border_glitch` is the house glitch vocabulary; the shipped END_ROD core sparks in `tickStagger`
stay under both.

**Budget**: ≤ 30 particles, 2 render passes (multi-material = multi-pass; ~60 quad-draws worst
case), every 70t volley in P2 — fine. REVERSE_SUB depth-tests against the warden model; keep
`depthTest: 1b` so shards vanish behind the body (correct read). Sanity-check REVERSE_SUB under an
Iris pack (blend-equation state is exactly the §4 watch item).

---

### 8. `eclipse:boss/ferry_oar_tear` — Ferryman oar-sweep water-tear ribbon

The 180° oar sweep (`doSweep`, after the 25t raise) currently shows 6 vanilla SWEEP_ATTACK
puffs. Concept: the oar **tears the limbo water surface** — a luminous arc of spray swept along
the exact front half-circle using the `function` expression shape (FX_FORMAT.md §6), plus a
per-particle ara ribbon (`trails` module) so the arc smears like ripped water.

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `tear_arc` | `particle_emitter` | `duration: 8, looping: 0b, maxParticles: 60` — the sweep visual is FAST (8t); `emissionRate: constant 7` (≈ 56 over the cycle, dense arc); `shape: function {x: "4.5*cos((t-0.5)*PI)", z: "-4.5*sin((t-0.5)*PI)", y: "0.1", speedX: "0.6*cos((t-0.5)*PI)", speedZ: "-0.6*sin((t-0.5)*PI)", speedY: "0.35+0.3*randomA"}` — emission origin sweeps the front half-circle left→right over the cycle (executor yaw-aligned, see trigger), spray flies outward+up; `startLifetime: random_constant 10–18`; `startSize: random_constant 0.1–0.25`; `physics {_enable:1b, gravity: constant 0.45, hasCollision: 1b, removedWhenCollided: 1b, bounceChance: 0}` — droplets die on the deck; `trails {_enable:1b, ratio: 0.5, lifetime: constant 0.5, trailType: "ARA_TRAIL", inheritParticleColor: 1b, sizeAffectsWidth: 1b, araConfig: {space: "World", thickness: 0.08, time: 0.25, smoothness: 3, thicknessOverLength: taper curve, physicsSetting {gravity: [0,−0.3,0], damping: 0.8}}}` — every 2nd droplet drags a short water ribbon; `colorOverLifetime` gradient pale-cyan → deep teal, alpha `[0,0.9, 1,0]` |
| `tear_glint` | `particle_emitter` | burst `{time: 2, count: 8}` on the same function shape via matching `duration: 8`; lifetime 4–6; size 0.05; HDR `[1.2, 1.8, 2.0, 1]` sparkle highlights |

**Material/blend**: additive `photon:textures/particle/circle.png`; droplets mild HDR
`[0.5, 1.0, 1.1, 1]`; ribbons `textureMode: "Stretch"`.

**Cull box**: `{min:[-7,-2,-7], max:[7,4,7]}`.

**Trigger**: `FerrymanEntity.doSweep`, beside the PLAYER_ATTACK_SWEEP sound — new
`FxCues.CUE_FERRY_OAR_SWEEP` with **`a = this.getYRot()`** (yaw crosses in the free float,
INTEGRATION.md wire shape `(id, pos, a, b)`); client handler applies
`PhotonBridge` **`setRotation(0, a, 0)` (blocker #1, rotation reflection)** before `start()` so
local −Z/+X of the function shape aligns with the boss's forward. Block-anchored is correct — the
sweep is an instant world event, not a follower.

**Quasar fallback**: `Entry(boss/ferry_oar_tear, glut_welle_ring, BURST, Mode.LAYER)` (the house
expanding-wave emitter); vanilla SWEEP_ATTACK stays.

**Budget**: ≤ 60 droplets + ≤ 30 short ribbons + collision for 8t, at most every 70t
(`SWEEP_COOLDOWN_TICKS`) and only when a target is in melee range — acceptable; this is the
highest-cadence *collision* user, so `removedWhenCollided: 1b` keeps live counts tiny.

---

### 9. `eclipse:boss/ferry_kneel_corona` — Ferryman P2 kneel corona (re-fire sustained)

While the Ferryman kneels invulnerable, a quiet teal corona marks "damage is pointless — do the
mechanic": a slow halo of soul-light + upward-peeling wisps around the kneeling silhouette,
sustained for the whole variable-length phase via the dedup re-fire pattern (blocker #2).

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `corona_halo` | `particle_emitter` | `duration: 100, looping: 0b, prewarm: 10`; `emissionRate: constant 0.8`; `shape: cylinder {radius: 1.3, radiusThickness: 0.1, shapeArc {arcMode: "Loop", arcSpeed: constant 0.5}}` — emission point orbits the kneel (Template-B recipe); `startLifetime: random_constant 30–50`; `startSize` 0.12–0.25; `velocityOverLifetime {linear: (0, random 0.015–0.04, 0), orbitalMode: "AngularVelocity", orbital: (0, 0.5, 0)}`; `colorOverLifetime` loop-safe fade-in/out gradient (a=`[0,0, 0.2,0.6, 0.8,0.5, 1,0]`), teal `rgb [0, 0.4,0.95,0.85, 1, 0.15,0.5,0.55]`; `simulationSpace: "Local"`; `lights 15/15` |
| `invuln_shell` | `particle_emitter` | `duration: 100, looping: 0b`; `emissionRate: 0.25` + burst `{time: 0, count: 1}`; dot; lifetime 90; ONE ghost-bell dome: `renderMode: Billboard`, `startSize (3.2, 3.2, 3.2)`, near-static, alpha 0.12 shell texture (`eclipse:textures/particle/dome_faint.png`), `colorOverLifetime` slow pulse via 2-segment alpha curve; NO HDR (deliberately dim — the READ is "inert", bloom would say "power up") |

**Material/blend**: halo additive mild HDR `[0.3, 0.9, 0.8, 1]`; shell alpha-blend,
`vertexSortingMode: "DISTANCE"`.

**Cull box**: `{min:[-4,-1,-4], max:[4,5,4]}`.

**Trigger + sustain**: first send in `FerrymanEntity.startCrewPhase`; re-send the same
`FxCues.CUE_FERRY_KNEEL_CORONA` from `tickCrewPhase`'s existing `CREW_CHECK_TICKS` (20t) cadence
gate while `crewActive` — each re-send is a **silent dedup no-op while the 100t runtime lives**
(`allowMulti=false`, API.md §3), and after `endCrewPhase` stops the re-fire the last cycle fades
out within ≤ 100t naturally. No stop API needed; a mid-phase `/reload` self-heals on the next
cadence tick. Also fires in the C10 arena branch (same anchor).

**Quasar fallback**: `Entry(boss/ferry_kneel_corona, limbo_motes, AMBIENT, Mode.LAYER)`; the
kneel-hit SOUL sparks (`playKneelCue`) stay the hit-feedback layer.

**Budget**: ~80 live particles sustained for the whole crew phase — the one deliberate
"long-running" Photon row; acceptable because it exists once per fight phase at a single anchor,
and `reducedFx` kills it wholesale. Do NOT copy this pattern to high-frequency cues (house law).

---

### 10. `eclipse:boss/tyrant_fog_arms` — Fog Tyrant fog-arm mesh tendrils — **rank last / law-bending**

Desperation-phase dressing: 5 tendril arms of fog claw outward from the tyrant, each a chain of
**model particles** emitted along a shipped baked tendril model (`mesh` shape, `Triangle` emit)
with heavy noise — the "reaching arms" read from the plan §2.4 concept art.

**.fx object list** (2 objects):

| name | type | config |
|---|---|---|
| `arm_pivot` | `empty` | grouping node at `localPosition [0, 1.8, 0]`; 1 child. Photon has no transform keyframes — rotation motion comes from the CHILD's orbital velocity, the pivot only centers the rig |
| `fog_arms` | `particle_emitter` (child of `arm_pivot`) | `duration: 200, looping: 0b, maxParticles: 150`; `emissionRate: constant 1.6`; `shape: mesh {type: "Triangle", meshData {modelLocation: "eclipse:item/fog_tendril"}}` — a shipped ~20-tri curved-claw JSON item model; shape `scale` NF3 `curve` breathing 0.8↔1.15 over emitter t (animated emission origin, FX_FORMAT.md §3.2); shape `rotation` NF3 y-axis `curve` lower 0 upper 72 — the emission volume slowly precesses so 5 successive "arms" trace around the body; `startLifetime: random_constant 25–40`; `startSize` 0.35–0.7 growing (sizeOverLifetime upper 1.8); `startSpeed: constant 0.05` along mesh normals; `noise {_enable:1b, frequency: 0.6, quality: "Noise3D", position: (0.15, 0.06, 0.15), size: constant 0.1}` — writhing; alpha-blend fog grey-teal `colorOverLifetime` (a peak 0.55 — translucent, never a wall), `vertexSortingMode: "DISTANCE"`, `shade: 1b`; `simulationSpace: "Local"` (arms ride the stalking boss via re-anchor…) — **caveat: `BlockEffectExecutor` is static; the tyrant WALKS.** Ship this as `spawnOnEntity(…, AutoRotate.FORWARD)` (blocker #1) so the rig follows and faces with the body |

**Material/blend**: `texture` soft fog puff `eclipse:textures/particle/fog_puff.png`, alpha
blend, NO HDR, `depthMask: 0b`, `layer: "Translucent"`.

**Cull box**: `{min:[-9,-2,-9], max:[9,6,9]}`.

**Trigger + sustain**: `FogTyrantEntity` P3 entry (the colossus-call phase transition in
`updatePhase`) — `FxCues.CUE_TYRANT_FOG_ARMS`; re-fired every 160t from the P3 fight tick while
alive (dedup pattern, 200t duration ⇒ seamless overlap-free sustain); entity death auto-kills it,
so the death implosion (#2) never fights a live loop.

**Quasar fallback**: `Entry(boss/tyrant_fog_arms, limbo_fogbank, AMBIENT, Mode.LAYER)`.

**Budget**: the most expensive sustained concept (150 alpha-sorted particles + Noise3D + entity
re-anchor) and an aesthetic-only payoff — hence **rank 10**; ship only after 1–9 hold 60 fps in
the (Iris pack + Photon) pair test, and drop `maxParticles` to 90 if the P3 scene (colossus +
lances + hounds) dips. Requires the shipped `eclipse:item/fog_tendril` model asset (blocker #4).

---

## Cross-cutting notes

- **New `FxCues` ids introduced**: `CUE_BOSS_ROAR`, `CUE_TYRANT_DEATH_IMPLOSION`,
  `CUE_WARDEN_VOLLEY_TELEGRAPH`, `CUE_FERRY_LANTERN_SWARM`, `CUE_TYRANT_SQUALL`,
  `CUE_WARDEN_STAGGER`, `CUE_FERRY_OAR_SWEEP`, `CUE_FERRY_KNEEL_CORONA`, `CUE_TYRANT_FOG_ARMS`
  (9 ids; concept 5 is client-seam-only, no cue). All are `eclipse:fx/cue/...` per the
  INTEGRATION.md §3 naming law; server stays photon-blind; zero registrar changes.
- **Bridge work items** (one PR, mechanical, all signatures pre-verified in API.md §1/§6):
  `spawnOnEntity(fxId, entity, autoRotate)` (concepts 3, 5, 10), `setRotation`/`setOffset`
  reflection (concept 8), optional live-executor count gate (concept 5).
- **New texture/model assets to author**: `ring_soft.png`, `beam_core.png` (4-frame),
  `glitch_shard.png` (2×2), `dome_faint.png`, `fog_puff.png`, noise strip, `item/fog_tendril.json`
  — plus 11 `.fx` exports (10 concepts + 1 sub-emitter child) and their `.fxproj` sources.
- **Test order per asset** (INTEGRATION.md §6): author in singleplayer editor → trigger via the
  boss dev commands (`/eclipse boss … summon`) → confirm no `MISSING_FX` INFO and visible layer →
  the two pair tests (Veil post + Photon; Iris pack + Photon) before flipping any row to
  `Mode.REPLACE` (all rows above ship as `Mode.LAYER`).
