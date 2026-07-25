# PHOTON-IDEAS-4 — Event-Sequence `.fx` Concepts (intro / expansion / portals / credits / drops)

Worker: PHOTON-IDEAS-4 (of 5), 2026-07. Domain: **event sequences** — the intro storm,
map expansion, portal events, tutorial worlds, the credits finale and the supply drop.
Read first: `photon/API.md` (runtime API), `photon/FX_FORMAT.md` (file format),
`photon/INTEGRATION.md` (bridge/laws). Code grounding (read-only):
`sequence/IntroSequence.java`, `sequence/ExpansionSequence.java`,
`ritual/CreditsSequence.java`, `worldgen/stage/StructureFlightFx.java`,
`xboxevent/XboxPortal.java`, `backrooms/BackroomsPortal.java`, `veilfx/rift/RiftFx.java`,
`economy/SupplyBeacon.java`, `veilfx/PhotonBridge.java`,
`eventdim/PortalEventScheduler.java`, `assets/eclipse/pinwheel/shaders/program/xbox_era.fsh`.

Every concept below follows the frozen laws (INTEGRATION.md §3, do not renegotiate):
server stays photon-blind (only logical cue ids on the wire), every Photon layer is
additive over a Quasar/vanilla base that keeps working without Photon, spawns are
uncharged to `FxBudget` (`reducedFx` is the kill switch), and Photon legs are reserved
for SEQUENCE-grade moments. Where a concept bends the "no ambient loops" guidance it is
ranked lower and flagged explicitly.

---

## Ranking

| # | Concept | Anchor sequence beat | New runtime surface needed | Risk |
|---|---------|----------------------|---------------------------|------|
| 1 | Intro final-burst HDR white-out ring | `IntroSequence` BURST | none (`PhotonBridge.spawn`) | low |
| 2 | Credits beach lightning ladder (staggered `beam_emitter`s) | `CreditsSequence` t=420–480 | `FxCues` row | low |
| 3 | Structure slam mushroom + collision sub-emitters | `ExpansionSequence` STRUCTURES slam | `FxCues` row | low |
| 4 | Traveling growth-wavefront dust ribbon (moving-executor trick) | `ExpansionSequence` GROWTH | `EntityEffectExecutor` reflection + front-rider entity | med |
| 5 | Portal-open iris ring (shared xbox/backrooms) | `RiftFx.openRift` portal styles | style branch in the existing `openRift` seam | low |
| 6 | DOOMSDAY burst confetti mesh shards | `CreditsSequence` t=650 | `FxCues` row | low |
| 7 | Intro vortex-wall lightning beams (storm-wall loop) | `IntroSequence` LIGHTNING→BURST | looping-executor handle (`destroy`) | med |
| 8 | Sunrise god-ray ribbons | `IntroSequence` SUNRISE | none | low |
| 9 | Supply-drop heat-shield plasma ribbon + credits flyover contrails | `SupplyBeacon` descent / credits t=420–560 | `EntityEffectExecutor` reflection (shared with #4) | med |
| 10 | Tutorial-world era dust motes (GPU-instanced ambient) | xbox tutorial dimensions | looping executor + **law renegotiation** | high |

Rationale: 1–3 and 5–6 are one-shots at already-broadcast sequence beats — pure
"author asset + one registry row" wins that fit today's laws exactly. 4, 7 and 9 need
one small, verified `PhotonBridge` extension each (all pre-authorized shapes per
INTEGRATION.md §3.5). 10 contradicts the written "never register ambient loops" guidance
and ships only with an explicit sign-off.

---

## 0. Shared integration groundwork (one-time, unblocks everything below)

1. **`PhotonFxRegistry` + `FxCues`** (INTEGRATION.md §3, not yet built): concepts #2,
   #3, #6 are ordinary `Entry` rows over the existing `S2CFxEventPayload` lane
   (`eclipse:fx/cue/*` ids) — no protocol change.
2. **Optional-knob reflections on `BlockEffectExecutor`** (all verified public on the
   2.1.5 jar, API.md §1): `setOffset(Vector3f)` (exact-Vec3 anchoring — several concepts
   anchor at non-block-center positions like `runnersCenter` or the rift mouth),
   `setAllowMulti(boolean)` (repeat bursts at one BlockPos, e.g. slam rings),
   `setScale(Vector3f)` (footprint-scaled slams, width-scaled irises),
   `setDelay(int)` (client-side stagger without server scheduling).
3. **Looping-effect handle**: `PhotonBridge.spawnLooping(fxId, pos)` returning an opaque
   handle wrapping the executor; `stop(handle, force)` reflects
   `getRuntime()` → `FXRuntime.destroy(boolean)` (`force=false` = graceful fade,
   API.md §3). Needed by #4, #7, #10 and the portal loops in #5. Keep a client-side
   registry of live handles keyed by our own cue key; Photon's own
   `BlockEffectExecutor.CACHE` is the fallback lookup.
4. **`EntityEffectExecutor` reflection** (pre-authorized by INTEGRATION.md §3.5 law 5 —
   "add when a cue actually needs it"; #4 and #9 need it):
   `EntityEffectExecutor(FX, Level, Entity, AutoRotate)` + `AutoRotate.valueOf("NONE")` +
   `start()`. Death-cleanup is automatic (API.md §1) — the crate lands, the flyer is
   discarded, the front rider despawns → runtime destroyed, no leak possible.
5. **Asset/author workflow**: per INTEGRATION.md §6 — author in `/photon_editor`
   (singleplayer dev client), export to `src/main/resources/assets/eclipse/fx/<id>.fx`,
   commit the `.fxproj` next to it (binary-diff law, FX_FORMAT.md §7). Missing assets are
   per-id session-skipped by the bridge (one INFO) — every concept ships dark until its
   asset lands.

### The moving-executor question (asked explicitly): block-executor chain vs entity anchor

Verdict: **entity anchor**, with a server-side "front rider".

- **Block-executor chain** (spawn a short one-shot `.fx` per growth pulse at successive
  front points): pulses arrive every 5 ticks and `ClientHooks` already spawns ≤2 Quasar
  emitters per pulse — mirroring that on the Photon side means up to 8 Photon
  spawns/second, each of which deep-copies `fxData` through the codec
  (`createRuntime()`, FX_FORMAT.md §9). That is exactly the "high-frequency cue" the
  Photon frequency law forbids, and it also reads as a strobing chain of curtains, not a
  traveling wall. Rejected for continuous travel (acceptable only as a sparse milestone
  accent, ~1 spawn per 100+ ticks).
- **Self-animating `.fx`** (animate `shape.position` NF3 curves or a `function` shape
  over emitter `t`, executor never moves): tempting — the emission *origin* can travel
  inside one runtime — but the real front speed is live-steered
  (`RingGrowthService.progressFraction` + `GrowthPacing.targetTicks`), so any baked
  curve drifts off the actual wavefront within seconds. Only usable for fixed-timeline
  shows (used in #2 and #7 below, where the timeline IS fixed).
- **Entity anchor** (recommended): the server already computes the exact front point
  every tick — `ExpansionSequence.resolveGrowthFront` feeds the `growth_front` dynamic
  camera anchor. Spawn one invisible `minecraft:marker`-style rider entity at sweep
  start, move it along the arc server-side (same math as `resolveGrowthFront`), discard
  it at terrain-complete. The client attaches ONE `EntityEffectExecutor` (AutoRotate
  `NONE`) with a looping curtain `.fx` in **World** simulation space: the emitter root
  follows the rider every render frame (API.md §1), while already-emitted dust stays
  behind in world space — the wall visibly *travels* and trails. One executor per sweep,
  one entity per sweep, automatic cleanup on discard. This is concept #4.

---

## 1. `eclipse:intro_burst_ring` — final-burst HDR white-out ring (intro BURST)

**The moment.** `IntroSequence.beginBurst` (R10 frozen): giant strike
(`FX_LIGHTNING_STRIKE` b=1) + `fx/shockwave (1.0, 50)` + vortex `DISSIPATE 60` + the
CUT-INTRO flash sandwich (`FLASH_WHITE` t+0 → `SHUTTER_BLACK` t+3 → `FLASH_VIOLET` t+6)
+ `altar_reveal_burst` Quasar cue at the altar. Photon's unique add: a **bloom-driving
HDR ring** that the flash sandwich appears to be *caused by* — the white-out gets a
physical source in the world.

**.fx spec** (one file, 3 emitters, all `looping:0b`):

- `ring_core` (`particle_emitter`): ONE particle. `duration:30`, burst `{time:0, count:1}`,
  `startLifetime:26`, `startSize` huge via `sizeOverLifetime` curve 0.5→(2×VORTEX_RADIUS≈44
  blocks)→hold; `renderMode:Horizontal` (flat ring lying on the terrain), material
  `texture` = authored soft annulus PNG, `hdr:[3.5,3.0,4.0,1]` `hdrMode:ADDITIVE` (drives
  `PhotonPostProcessing` bright-pass hard — this IS the white-out source), blend
  SRC_ALPHA/ONE, `depthMask:0b`, `colorOverLifetime` gradient white→violet
  (`0xCC8800FF` tail matches `FLASH_VIOLET`), alpha out by t=1.
- `ring_sparks` (`particle_emitter`): `shape: circle` r=1 (unit; executor `setScale`
  to vortex radius), `radiusThickness:0`, `shapeArc {arcMode:BurstSpread}` — one clean
  even ring of 48 sparks, burst at `time:2`. `startSpeed` random 0.6–1.2 radial,
  `physics {gravity:0.25, hasCollision:1b, bounceChance:0.4}` so sparks rain and skip
  off the fresh island rim. Additive, `lights {_enable, 15/15}`.
- `dome_wisp` (`particle_emitter`): 20 slow smoke billboards, `shape: sphere`
  hemisphere-ish (`arc:180`), World space, alpha ≤0.25 — the vortex "bursting open"
  read under the ring.

**Trigger + timing.** Client-local seam like `RiftFx.openRift`'s: `beginBurst` already
broadcasts `FX_SHOCKWAVE (1.0, 50)` at `current.center`. In the client
`FxPayloads.handleFxEvent` shockwave branch, when `a >= 1.0 && b >= 50` (the intro/credits
giant signature) layer `PhotonBridge.spawn(INTRO_BURST_RING, pos)`. Cleaner long-term:
`FxCues.CUE_INTRO_BURST` row (`Mode.LAYER`, quasar leg `null`) sent from `beginBurst`
one line after the shockwave. Timing needs nothing extra: emission starts the same tick
as `FLASH_WHITE`; the ring's own 26t life spans the shutter and hands the violet tail to
`FLASH_VIOLET` (t+6) exactly. Replay parity: `IntroSequence.replay("BURST")` sends the
same shockwave payload per-watcher — the same client branch fires, zero extra work.

**Fallback.** No Photon → today's flash sandwich + `altar_reveal_burst` Quasar cue,
bit-identical. Bloom disabled in `photon-client.toml` → ring still renders, just not
blinding (acceptable).

**Budget.** ≤70 particles for ~30 ticks, once per world (plus dev replays).
`maxParticles:128`, `vertexSortingMode:NONE` (additive), physics on 48 sparks only.
Uncharged; `reducedFx` gates. Negligible.

---

## 2. `eclipse:credits_strike_beam` — beach lightning ladder as staggered beams (credits t=420)

**The moment.** `CreditsSequence` t=420: 6 offshore strikes, interval 12t, intensity
0.6→1.0, deterministic near–far ladder `STRIKE_DEPTHS {64,10,34,78,16,6}` past the surf
line (x≈`BEACH_SAND_EAST_X`+depth), sides alternating, thunder delayed by distance
(~17 blocks/tick). Each strike already broadcasts `FX_LIGHTNING_STRIKE` + spawns a
visual-only vanilla bolt. Photon add: a **`beam_emitter` column** per strike — a real
volumetric HDR shaft from the storm ceiling into the sea, something neither the vanilla
bolt nor the Quasar impact can do (FX_FORMAT.md §7 — beams are Photon-only).

**.fx spec** (one file, 3 emitters; spawned once per strike at the impact point):

- `main_beam` (`beam_emitter`): `duration:14, looping:0b`, local `end:[0,90,0]` (the
  executor anchors at the impact; beam runs impact→zenith — visually identical to
  zenith→impact and keeps the anchor math trivial), `width` curve 1.4→0.25 over the 14t
  (fat flash collapsing to a filament), `raycast:NONE` (offshore, nothing to clip),
  `color` gradient white→electric violet, material `texture` 1×N gradient strip with
  `hdr:[2.5,2.2,3.0,1]` — the flash blooms over the whole horizon.
- `halo` (`beam_emitter`): same geometry, `width` 3.0 constant, alpha 0.15, 6t life —
  the corona sheath.
- `sea_splash` (`particle_emitter`): 16-spark burst, `shape: cone (angle 40)` pointing
  up, `physics {gravity:0.4, hasCollision:0b}`, additive, 20t — spray where the beam
  meets the water.

Per-strike variation WITHOUT extra assets: the ladder's intensity ramp maps to executor
`setScale(intensity)` (0.6→1.0), and the interval stagger stays server-side (the strikes
are already 12t apart) — no `startDelay` authoring needed. If we ever want the whole
ladder as ONE spawn instead, the six `beam_emitter`s can live in one `.fx` with
`startDelay` 0/12/24/36/48/60 and baked ladder offsets via per-emitter `transform`
`localPosition` — rejected here because the z-jitter (`hash01`) and runner-relative
framing make per-strike spawns read better.

**Trigger + timing.** New cue row `FxCues.CUE_CREDITS_STRIKE` → registry `Entry(photonFx
= credits_strike_beam, quasarEmitter = null, Mode.LAYER)`. `beatLightningStrike` sends it
one line after its existing `FX_LIGHTNING_STRIKE` broadcast, same impact Vec3, same
intensity in `a` (client maps to scale). Do NOT piggyback on `FX_LIGHTNING_STRIKE`
itself: that id also fires at 15-tick cadence during the intro's LIGHTNING hold — a
Photon leg there would violate the frequency law (see #7 for the intro treatment).
`setAllowMulti(true)` is unnecessary (each strike is a different BlockPos) but harmless.
Thunder stays server-side and already lands late by depth — the beam dying 14t before
far thunder arrives is exactly the read we want. Replay: `CreditsSequence.replay`'s
LIGHTNING branch sends the same cue per-watcher.

**Fallback.** Vanilla visual bolt + `FX_LIGHTNING_STRIKE` renderer, unchanged (today's
show). Missing asset → session-skip INFO, base layer untouched.

**Budget.** 2 beam quads + 16 sparks per strike, 6 strikes over 60t, once per world.
Beams are single quads — near-free. `maxParticles:64`. Uncharged; `reducedFx` gates.

---

## 3. `eclipse:structure_slam_mushroom` — slam column with collision sub-emitters (expansion STRUCTURES)

**The moment.** `ExpansionSequence.slamBeat`/`slamFx`: on PLACED — `structure_slam_dust`
Quasar burst + two expanding dust rings (t+6/t+12, 6 points each, radii 0.35/0.6 ×
footprint) + `fx/shockwave (0.5, 30)` + `event.rift_slam` + 0.4 shake, debris at
t+8/t+20, rift closes at t+8. Photon add: the **vertical mushroom** the flat rings
can't do — a dust column that punches up, blooms into a cap, and whose falling clods
use Photon's real collision physics to kick up **secondary dust puffs where they land**
(`subEmitters` on `Collision` — the headline feature, FX_FORMAT.md §3.3).

**.fx spec** (two files — sub-emitters reference a second `.fx` by `fxLocation`):

`structure_slam_mushroom.fx`:
- `column` (`particle_emitter`): `duration:16, looping:0b`, burst 40 at t=0,
  `shape: circle` r=0.15 (unit — executor `setScale(footprint·0.05)`),
  `startSpeed` random 1.2–2.0 straight up, `velocityOverLifetime.linear` Y curve
  +fast→0 (decelerating column), `sizeOverLifetime` 1→3 (the cap blooms as it slows),
  smoke texture, alpha blend (`ONE_MINUS_SRC_ALPHA`), `vertexSortingMode:DISTANCE`,
  earth-tone `colorOverLifetime` (dust brown → pale grit → fade), `shade:1b` (worldlit —
  this is dirt, not magic), World space, lifetime 30–45.
- `cap_roll` (`particle_emitter`): 24 slower billboards, `shape: sphere arc:180`
  (hemisphere), `startDelay:8`, `noise {frequency:0.6, position:0.08}` — the roiling
  mushroom head.
- `clods` (`particle_emitter`): 14 chunky particles, `renderMode:Model` +
  `shape: mesh {Triangle, modelLocation:"block/dirt"}` + `block_atlas` material +
  `useBlockUV` — real dirt-textured shards. `physics {_enable, hasCollision:1b,
  gravity:0.6, bounceChance:0.5, bounceRate:0.3, removedWhenCollided:0b,
  collidedFriction:0.6}`, `rotationOverLifetime` tumble.
  `subEmitters: {fxLocation:"eclipse:slam_dust_puff", event:Collision,
  emitProbability:0.5, inheritColor:1b}` — every clod impact spawns the puff file below.
- `subEmitters` on the column too: `event:Death` → nothing (keep off; death puffs at
  30–45t read as noise).

`slam_dust_puff.fx`: single tiny emitter — 5 ground-hugging dust billboards, 12t,
`shape: dot`, low alpha. **Keep this file minimal**: every collision instantiates a full
`FXRuntime` copy of it (FX_FORMAT.md §9).

**Trigger + timing.** Cue row `FxCues.CUE_STRUCTURE_SLAM` (`Mode.LAYER`, quasar leg
`null` — `slamFx` already sends `structure_slam_dust` itself, mirroring the altar
double-fire rule from INTEGRATION.md §1). `slamFx` sends the cue at `slamPos` with
`a = footprint` → client `setScale(footprint·k)`. Timing: fires the same tick as the
slam; the mushroom's 8t-delayed cap and the sequence's t+6/t+12 rings interleave into
one read; Photon clods land within the t+8/t+20 `slam_debris` window, so the collision
puffs and the Quasar debris share the beat. `StructureFlightFx` deliveries need nothing:
the big PLACED slam stays `ExpansionSequence`'s (its doc says so), so this cue rides it
automatically. Auto-placed-before-beat sites hit the same `slamFx` path → same cue.
`setAllowMulti(true)` required: bursty stages can slam two sites at nearby positions
that round to the same BlockPos.

**Fallback.** Today's rings + `structure_slam_dust` + `slam_debris` — already a complete
show. Physics collision is the most expensive module (FX_FORMAT.md §9): only the 14
clods carry it.

**Budget.** ~80 primary particles + ≤14 collision puffs (5 each, prob 0.5 ⇒ ~35) per
slam; slams are ≥50t apart (`BEAT_SPACING_TICKS`) and only during expansions.
`maxParticles:160`, cull box ±footprint. Uncharged; `reducedFx` gates.

---

## 4. `eclipse:growth_front_ribbon` — traveling wavefront dust ribbon (expansion GROWTH)

**The moment.** GROWTH: the ring sweep animates outward; `ClientHooks` walks
`growth_dust_wall` Quasar curtains along the wave arc (≤2 per 5-tick pulse, 96-block
range). Photon add: ONE **continuous traveling curtain** — an `ara_trail_emitter`
ribbon plus a dust skirt that *moves with the front* instead of strobing along it.

**Moving-executor verdict** (see §0): **entity anchor.** Server spawns one invisible
front-rider entity (Marker/invisible Display, new tag `eclipse_growth_rider`) at
`onGrowthStart` for cinematic overworld runs, repositions it every tick with the same
math as `resolveGrowthFront` (front point at the watchers' average angle, snapped to
terrain), discards it at `onStageTerrainComplete`. Client: on rider join (tag check is
server-side; client identifies via a tiny `FxCues.CUE_GROWTH_RIDER` cue carrying the
entity id in `a` — or simpler, the rider entity type itself is ours and the client
attaches on `EntityJoinLevelEvent`), attach `EntityEffectExecutor(fx, level, rider,
AutoRotate.NONE)` with:

**.fx spec** (looping, lives as long as the rider):

- `front_ribbon` (`ara_trail_emitter`): `space:World`, `alignment:View`,
  `thickness:2.5`, `time:1.6` (segments live ~1.6s → a ~20–40 block trailing veil at
  real front speeds), `timeInterval:0.05`, `smoothness:4`,
  `physicsSetting {inertia:0.35, damping:0.8}` — the ribbon lags and swings behind the
  rider like a curtain hem, `colorOverLength` dusty violet-grey fading to nothing,
  `textureMode:Stretch`, alpha-blend, `depthMask:0b`.
- `dust_skirt` (`particle_emitter`): `looping:1b, duration:20, prewarm:10`,
  `emissionRate:2.5/t`, **`simulationSpace:World`** (critical: emitted dust stays where
  the front passed — the trailing wall), `shape: box` scaled 12×1×2 (a short wall
  segment perpendicular-ish to travel; `EMITTER_TRANSFORM` facing keeps it upright),
  `startSpeed` 0.1 up, `velocityOverLifetime` Y +0.05, `noise {0.8, position 0.06}`,
  lifetime 30–50, smoke material, `shade:1b`.
- `crest_sparks` (`particle_emitter`): rate 0.4/t, additive violet pinpricks with
  `lights 15/15` riding the crest — ties the mundane dust to the eclipse palette.

**Trigger + timing.** Rider spawn at `beginGrowth` (control has returned; the flyover
camera already showed the front), discard on `onStageTerrainComplete` →
`EntityEffectExecutor` auto-destroys (graceful fade, `forcedDeath=false`) — the wall
dissolves as the caption `expansion.done` lands. Nether reduced runs: skip (no
cinematic). The Quasar pulse curtains KEEP running underneath (LAYER law) — with
Photon they read as reinforcements of one continuous wall; without, they are the wall.
`inheritVelocity {mode:CURRENT, multiply:0.4}` on the skirt makes emission smear
correctly at speed.

**Fallback.** No Photon / no rider (mod absent server-side is impossible — rider is our
own entity; but a client without Photon simply never attaches) → today's pulse-driven
Quasar curtains, unchanged. Rider despawn safety: `EntityJoinLevelEvent` stray-sweep
doctrine (`StructureFlightFx`/`CreditsSequence` pattern) for crash leftovers.

**Budget.** One ribbon (~32 live segments) + ~125 live dust particles + ~20 sparks,
for the sweep duration (minutes), ONE executor total. `maxParticles:300`, renderer cull
box ±24 around the rider, `parallelUpdate:1b` (no world access in its updates —
collision off). This is a long-lived loop but a **sequence-bounded single spawn**, not a
high-frequency cue — within the law's intent; flagged for review anyway.

---

## 5. `eclipse:portal_iris_open` + portal identity loops (xbox / backrooms)

**The moment.** Both portal variants are frameless: `XboxPortal.place` /
`BackroomsPortal.place` broadcast `FX_RIFT_OPEN (a=5.0, b=style)` (style 1 = xbox violet
star, 2 = backrooms wax-gold; `RiftFx` re-orients portal-like rifts upright, resyncs
per-player from `ambientTick`, closes via `FX_RIFT_CLOSE`). Today
`RiftFx.openRift` calls `PhotonBridge.spawn(EXPANSION_RIFT_GLOW, pos)` for **every**
style. Photon add, three parts:

**(a) `portal_iris_open` — the open moment** (one-shot, shared by both variants,
tinted by two variant files or one file + `startColor` executor tint — ship two files,
simpler): a camera-facing **iris ring** that snaps open exactly when the tear does.

- `iris` (`particle_emitter`): 1 particle, 18t, ring texture, `renderMode:Billboard`
  facing `LOOKAT_XYZ`, `sizeOverLifetime` 0.2→(width·1.3) with an overshoot Bézier
  (pop past, settle back — authored curve), `hdr:[2,1.8,2.6,1]` violet / `[2.6,2.3,1.4,1]`
  wax-gold, additive.
- `rim_flash` (`particle_emitter`): 24 sparks, `shape: circle` unit + `BurstSpread`,
  executor-scaled to width/2, radial 0.4, 12t, additive + `lights`.

**(b) `portal_loop_xbox` — era-pixel presence loop**: `looping:1b, duration:40,
prewarm:20`. Emitter 1 `era_pixels`: rate 0.6/t, `shape: mesh {Vertex,
modelLocation:"block/grass_block"}` — motes emitted from actual block-model geometry —
material `texture` with **`pixelArt {_enable:1b, bits:8}`** (chunky 8-bit quads, the
era read), slow orbit into the star via `velocityOverLifetime {orbitalMode:
AngularVelocity, orbital Y 0.5, radial −0.05}` (sucked in, matching
`portal_surface_motes`' vortex read). Emitter 2 `crt_flicker`: ONE screen-glow
billboard behind the star surface, `colorOverLifetime` **random_curve** brightness
(irregular flicker, memoized per cycle) + `uvAnimation` 2×2 subtle frame jitter.
Deliberately **no scanlines** — `xbox_era.fsh` v2 codifies "CRT-ADJACENT,
deliberately NO scanlines" as the era style law; flicker = luminance, not lines.

**(c) `portal_loop_backrooms` — fluorescent flicker + yellow haze**: `looping:1b,
duration:100` (matches the 100t hum cadence). Emitter 1 `tube_flicker`: one horizontal
thin billboard above the tear, `random_curve` alpha with long dark gaps and double-blink
clusters (authored curves0/curves1 — the classic dying-fluorescent stutter), pale
`0xFFFFF2CC`, small `hdr:[1.4,1.35,1.0,1]` so blinks kiss the bloom threshold. Emitter 2
`haze`: rate 0.3/t, big soft smoke billboards, wax-gold `0x26E8D9A0` (alpha ≤0.15),
near-zero velocity, 80–120t life, `noise` drift — the yellow soup leaking out. Emitter 3
`moth_motes`: 4–6 dark specks orbiting the tube erratically (`noise` position 0.15) —
grim little garnish, budget-free.

**Trigger + timing.** Replace the unconditional `EXPANSION_RIFT_GLOW` spawn in
`RiftFx.openRift` with a style branch (client-local seam, sanctioned by INTEGRATION.md
§3.5 law 4 — `openRift` "may stay" non-registry):
`STYLE_STRUCTURE → EXPANSION_RIFT_GLOW` (unchanged), `STYLE_PORTAL → portal_iris_open_xbox
+ spawnLooping(portal_loop_xbox)`, `STYLE_BACKROOMS → portal_iris_open_backrooms +
spawnLooping(portal_loop_backrooms)`. Loops are keyed by the rift's pos; `RiftFx`'s
`dispose`/`closeRift` path calls `PhotonBridge.stop(handle, false)` — the haze fades as
the star collapses. The per-player `FX_SYNCED` resync in `XboxPortal.ambientTick` means
late joiners re-enter through the same `openRift` → loops attach for them too.
`allowMulti` default-false is our friend here: resync repeats at the same BlockPos while
alive are silent no-ops (API.md §3 gotcha, used deliberately). The rift **entry moment**
(player crosses `width·ENTRY_RADIUS_FRACTION`) can later get a one-shot punch-through
`.fx`; out of scope here (that beat is FXTEAM-RIFT's).

**Fallback.** Today's full stack: volumetric star + `rift_spark` rim +
`portal_surface_motes` + server-side particle column & hum fallback. Zero regression.

**Budget.** Iris: ≤26 particles, 18t, once per open. Loops: xbox ~35 live particles +
1 glow quad; backrooms ~25 + 2 quads. At most 1–2 portals exist at once
(`PortalEventScheduler` opens one variant at a time). **Law note**: these are looping
ambients — but single-spawn, event-scoped (a portal existing IS an event), explicitly
destroyed, and each smaller than one Quasar `portal_surface_motes` loop already running
there. Recommend blessing as "portal-scoped loops" in the registry doc; ranked mid-table
on that condition. Cull box ±8, `maxParticles:96` each.

---

## 6. `eclipse:credits_confetti_burst` — DOOMSDAY burst confetti mesh shards (credits t=650)

**The moment.** `beatBurst`: `FX_SHOCKWAVE (1.0, 50)` at `runnersCenter` + tightened
6/4/6 white flash, dead by t=666 for the deadpan correction card at t=676. Photon add:
the flash leaves **glittering block-shard confetti** raining over the runners — mesh
particles rendered as real blocks in the flyer palette (planks, blackstone, basalt,
obsidian, amethyst — "the run's greatest hits" made literal), so the burst reads as the
DOOMSDAY title detonating the debris field overhead.

**.fx spec** (one file):

- `shards` (`particle_emitter`): `duration:12, looping:0b`, burst 60 at t=0,
  `shape: sphere` r=2 shell, `startSpeed` 0.8–1.6, **`renderMode:Model`** +
  `shape.meshData` per-emitter — five thin sibling emitters (12 shards each) with
  `modelLocation` = `block/dark_oak_planks`, `block/polished_blackstone_bricks`,
  `block/smooth_basalt`, `block/obsidian`, `block/amethyst_block`, `block_atlas`
  material + `useBlockUV` (mirrors `FLYER_PALETTE`), `startSize` 0.12–0.28,
  `rotationOverLifetime` fast tumble (roll+yaw 12–30°/t), `physics {gravity:0.35,
  hasCollision:0b}` (no world queries — they fall into the sea/sand and fade),
  lifetime 40–70, `sizeOverLifetime` shrink-out tail.
- `glint` (`particle_emitter`): 20 additive HDR pinpricks (`hdr:[2,2,2.4,1]`),
  8t — the flash itself sparkling off the shards, gone before t=666.

**Timing discipline (the comedy depends on it):** the white flash dies at t=666 and the
correction needs 500 ms of *stillness*. Falling confetti at low alpha tail is
acceptable motion (it reads as aftermath, not action) — but the `glint` emitter MUST be
finished by 666: lifetime 8t from a t=650 spawn ⇒ dead at 658. Keep every additive/HDR
element inside that envelope; only `shade:1b` world-lit shards persist into the
correction beat.

**Trigger + timing.** Cue row `FxCues.CUE_CREDITS_BURST` (`Mode.LAYER`), sent by
`beatBurst` at `runnersCenter` alongside the shockwave. Do not key off `FX_SHOCKWAVE`
(shared with intro BURST — #1 already claims the (1.0,50) signature there; two Photon
layers on one generic id is exactly the if-chain smell the registry exists to kill).
Replay: `credits` replay TITLE/CORRECTION branches send the cue per-watcher.

**Fallback.** Today's shockwave + flash. Confetti absent changes nothing structurally.

**Budget.** 80 particles, ≤70t, once per world. `Model` render mode on 60 small shards
is the cost center — `parallelRendering:1b`, `maxParticles:96`, cull box ±30.

---

## 7. `eclipse:intro_storm_wall` — vortex wall lightning beams (intro LIGHTNING→BURST)

**The moment.** LIGHTNING (600t + possible hold at 15t strike cadence): ramping purple
strikes from the eclipse zenith around the vortex (r=22, h=48). Per-strike Photon spawns
would be high-frequency (the hold alone is 4/s) — instead ONE looping **storm-wall**
`.fx` anchored at the vortex center for the whole phase: crawling arcs and short-lived
beams that live INSIDE the smoke wall, making the vortex itself electric between the
Quasar strikes.

**.fx spec** (looping, fixed timeline per cycle — the self-animating pattern from §0):

- `wall_arcs` (`beam_emitter` ×3 siblings): each `duration:40, looping:1b`,
  `emitRate:random 20–40` (re-trigger interval — sputtering, not synchronized),
  local `end` vectors chosen so each beam chords across the cylinder wall
  (e.g. `[14,26,-9]` from an executor-offset base), `width` 0.15,
  **`raycast:BLOCKS`** — beams clip against the (real, hidden-in-smoke) altar/terrain,
  selling "inside the storm", violet `color`, `hdr:[1.8,1.4,2.4,1]`,
  `uvAnimation` 4-frame crackle strip.
- `wall_glow` (`particle_emitter`): `looping:1b, duration:60, prewarm:30`, rate 1.2/t,
  `shape: cylinder {radius:1 (unit → setScale 22), radiusThickness:0.1, shapeArc
  {arcMode:Loop, arcSpeed:0.7}}` — emission point ORBITS the wall (Template B pattern);
  soft violet embers drifting up the wall, `lights {12/15}`, Local space (the wall owns
  them).
- `zenith_bloom` (`particle_emitter`): 1 faint HDR disc at local Y=+52 pulsing with a
  `curve` over the cycle — the underlit eclipse "eye" above the vortex.

**Trigger + timing.** `beginLightning` sends new cue `FxCues.CUE_INTRO_STORM_WALL`
(pos = `current.center`); client `spawnLooping` with `setScale(VORTEX_RADIUS,
VORTEX_HEIGHT/48, VORTEX_RADIUS)`. Destroy on the BURST beat: `beginBurst` sends
`FxCues.CUE_INTRO_STORM_WALL_END` (or the client watches the vortex `DISSIPATE` storm
payload it already receives — `S2CStormStatePayload STATE_DISSIPATE` is the cleaner
existing signal; recommend that seam, zero new sends) → `stop(handle, force=false)` —
arcs fade during the 60t dissipate, the last frames die behind the white flash.
Replay `LIGHTNING` already sends a replay storm spawn+dissipate pair under
`REPLAY_STORM_ID` — the same client watch gives replay parity for free.

**Fallback.** `IntroLightningPhase`'s ramped Quasar strikes + vanilla bolts — the
current full show. The wall loop is garnish between their beats.

**Budget.** 3 beam quads (sputtering) + ~70 live embers + 1 disc for ≤600t (+hold),
once per world. `maxParticles:128`, cull box ±(r+8) × h. Sequence-bounded loop, single
spawn — same legal footing as #4.

---

## 8. `eclipse:intro_sunrise_rays` — sunrise god-ray ribbons (intro SUNRISE)

**The moment.** SUNRISE: eclipse `ENDING` over 200t + permanent purple rim latched,
"IT BEGINS" title, warm gold bloom fade at +20t, 30t linger. Photon add: **physical
god-ray ribbons** climbing off the floating island's rim toward the risen sun — warm
volumetric streaks with the violet rim inheritance, bridging the sky grade (payload) and
the world (island) in the one shot everyone is staring at it.

**.fx spec** (one-shot, `duration:230, looping:0b` — spans ramp + linger):

- `ray_ribbons` (`ara_trail_emitter` ×4): `space:Local`, `alignment:View`,
  emitted rising from staggered island-rim offsets (per-emitter `transform.localPosition`
  ring at r≈10–14 around the altar anchor), `initialVelocity` up-and-sunward
  `[0.35, 0.55, 0]` (+X = east, the sun side), `thickness:0.9`,
  `thicknessOverLength` taper curve, `time:2.5`, `physicsSetting {gravity:[0,0.008,0],
  inertia:0.2, damping:0.9}` — slow heaven-bound drift with a living waver,
  `colorOverTime` gradient: gold `0xFFFFC994` (the exact `SUNRISE_WARM_BLOOM` tint)
  → violet rim `0x668800FF` → transparent. `startDelay` 20/50/85/120 — rays ignite one
  by one as the ramp brightens. Additive, mild `hdr:[1.5,1.3,1.0,1]`.
- `rim_motes` (`particle_emitter`): rate 0.5/t for the first 150t (emission `curve`),
  tiny gold sparks lifting off the rim, `lights {15/15}`, lifetime 40–60.

**Trigger + timing.** `beginSunrise` sends `FxCues.CUE_INTRO_SUNRISE` at the altar
anchor (it already computes/holds `FxAnchors.ALTAR_CENTER`); one-shot, dies on its own
at 230t ≈ `SUNRISE_RAMP_TICKS + SUNRISE_HOLD_EXTRA_TICKS`, i.e. exactly as `finish()`
runs — no destroy call needed. The 20t first-ray delay matches
`SUNRISE_BLOOM_DELAY_TICKS`, so the first ribbon and the warm screen bloom arrive
together. Replay `SUNRISE` sends the same cue.

**Fallback.** The `S2CEclipsePhasePayload` ENDING grade + warm fade — today's show.

**Budget.** 4 ribbons (~40 segments total) + ≤60 motes over 230t, once per world.
Trivial. `maxParticles:96`.

---

## 9. `eclipse:supply_reentry_ribbon` + `eclipse:credits_contrail` — the EntityEffectExecutor pair

Two concepts, one runtime unlock (the reflected `EntityEffectExecutor`, §0 item 4);
grouped because whichever ships first pays the integration cost for both.

### 9a. Supply-drop heat-shield plasma ribbon

**The moment.** `SupplyBeacon.drop`: a `FallingBlockEntity` barrel crate falls from
`spawnY` (hundreds of blocks) to the surface; ONE `S2CSupplyMarkerPayload` announces it
and `SupplyBeamClient` owns the beam visuals from there. Photon add: a **re-entry
plasma ribbon** on the crate itself — `ara_trail` streak with a heat-shield glow,
turning the (currently instant/abstract) descent into a visible fireball worth chasing.

**.fx spec:**
- `plasma_trail` (`ara_trail_emitter`): `space:World`, `alignment:Velocity`,
  `thickness:0.6`, `time:1.2`, `thicknessOverTime` taper, `colorOverTime`
  white-hot → orange → sooty grey → out, `hdr:[2.2,1.4,0.6,1]` on the hot end,
  `textureMode:Stretch`.
- `shield_glow` (`particle_emitter`): rate 1.5/t, tiny additive flares at the anchor,
  `inheritVelocity {CURRENT, 0.8}`, 6–10t life — the compression-glow cap.
- `soot_puffs` (`particle_emitter`): rate 0.4/t, World-space smoke, 40t — the dirty
  trail that hangs in the sky pointing at the landing site (gameplay-relevant garnish).

**Trigger + timing.** Client-local: when `SupplyBeamClient` processes a marker `add`
with `fadeTicks > 0` (the "fresh drop, play the burst FX" signal it already
distinguishes), scan the beam column for the `FallingBlockEntity` (the marker pos IS the
predicted column; the crate is the only falling block there) and attach
`EntityEffectExecutor(fx, level, crate, AutoRotate.NONE)`. Landing: the entity dies →
automatic `destroy` (graceful) — plasma fades right as the barrel thuds; the existing
beam + `supply_spark` take over. Crate-out-of-render-distance at spawn: attach lazily on
first sighting (retry from the beam's client tick while the marker is falling-phase).

**Fallback.** Today's beam + landing burst. **Budget:** one ribbon + ~25 live particles
for the fall (~5–10s), per drop; drops are minutes apart (economy-paced) — comfortably
"sequence-grade one-shot" in frequency terms. `maxParticles:64`.

### 9b. Credits block-display flyover contrails

**The moment.** Credits t=420–560: 24 `BLOCK_DISPLAY` debris flyers arc overhead toward
the sun (golden-angle de-phased, scale-ramped in/out, discarded at `T_FLYERS_END`).
Photon add: thin **contrail ribbons** on a subset — the debris field becomes a meteor
shower over the runners.

**.fx spec:** single `ara_trail_emitter`: `space:World`, `alignment:View`,
`thickness:0.25`, `time:0.9`, `colorOverTime` pale gold→violet→out (sunrise + rim
palette), `smoothness:3`, no physics lag (`inertia:0`) — crisp streaks, distinct from
9a's wobbling plasma.

**Trigger + timing.** Client-side attach on entity join: during an active credits roll
(`CreditsClient` knows), any `Display.BlockDisplay` joining the `eclipse:epilogue`
dimension **above y ≈ BEACH_Y+10** is a flyer (the wheel lives in limbo; the shadow
pucks hug the ground — the y filter excludes them; command tags don't sync to clients,
so the heuristic beats a protocol change). Attach to the first **8 nearest** only
(cap). Stagger comes free — the flyers themselves launch staggered
(`FLYER_STAGGER_MAX`), and each executor starts when its flyer joins/appears. Discard at
`T_FLYERS_END` → auto-destroy, ribbons fade before the t=650 burst (0.9s tail « 90t
gap). The scale ramp-in means a contrail on an invisible pre-launch flyer would leak —
attach on first *movement* (position delta > 0.1) instead of on join.

**Fallback.** The flyers themselves — already the show. **Budget:** 8 ribbons ×
~20 segments for 140t, once per world. Trivial.

---

## 10. `eclipse:era_dust_motes` — tutorial-world ambient era motes (GPU-instanced) — LAW FLAG

**The moment.** The xbox tutorial dimensions (TU-era variants, `xbox_era.fsh` console
grade). Photon add: an ambient **era-atmosphere loop** around the local player — chunky
`pixelArt` dust motes hanging in the air (the "dust in a CRT's light cone" read), plus
occasional single-frame "dead pixel" blinks. GPU-instanced: this is the one concept
that wants `useGPUInstance:1b` + `parallelUpdate/parallelRendering` (10⁴-scale budgets,
FX_FORMAT.md §7) — though we deliberately use ~1% of that headroom.

**.fx spec** (looping): one emitter, `duration:80, looping:1b, prewarm:40`,
rate 1.2/t, lifetime 100–160, `shape: box` 24×12×24 volume, near-zero drift + `noise
{0.4, position 0.03}`, `pixelArt {_enable:1b, bits:8}` square mote texture, alpha
≤0.35, `shade:1b`, `renderer {useGPUInstance:1b, parallelUpdate:1b,
parallelRendering:1b}` (no physics/no world access — parallel-safe),
`maxParticles:256`, cull box ±16. Second emitter `dead_pixels`: rate 0.05/t, 2t life,
single fullbright green/magenta pixel blink — subliminal.

**Trigger + timing.** Attach via `EntityEffectExecutor` on the **local player** when the
client enters an `eclipse:xboxworlds/*` dimension (the executor root follows the eye
position — the volume travels with the player; Local space so motes drift with you like
air, or World if we prefer them to hang — author both, pick in review). Destroy on
dimension leave (the client already tears rifts down on dimension change; same hook).

**Fallback.** Nothing — the era grade shader carries the mood alone (today's state).

**Law flag (why this is ranked last).** INTEGRATION.md §4 names "ambient loops" as
exactly what Photon rows must NOT be. This concept is a single spawn per dimension-entry
(not a high-frequency cue) and event-scoped (tutorial worlds exist only during a portal
event), but it is unambiguously ambient. Ship only with an explicit registry-doc
amendment ("player-scoped ambient loops allowed inside event dimensions, one per
client, `maxParticles ≤ 256`, GPU-instanced, no physics") — otherwise cut it and lose
nothing structural.

---

## Cross-cutting budget & risk summary

| Concept | Peak live particles | Duration | Frequency | New reflection surface |
|---|---|---|---|---|
| 1 intro burst ring | ~70 | 30t | once/world | none |
| 2 credits strike beams | ~20/strike | 6×14t | once/world | none |
| 3 slam mushroom | ~115 | ~70t | per structure beat (≥50t apart) | `setScale`,`setAllowMulti` |
| 4 growth ribbon | ~150 + ribbon | sweep-long | 1/sweep | `EntityEffectExecutor` |
| 5 portal iris + loops | ~35 loop | portal lifetime | 1–2 portals | `spawnLooping`/`stop` |
| 6 confetti burst | ~80 | ~70t | once/world | none |
| 7 storm wall | ~75 + 3 beams | ≤600t+hold | once/world | `spawnLooping`/`stop` |
| 8 sunrise rays | ~100 | 230t | once/world | none |
| 9 re-entry ribbon / contrails | ~30 / 8 ribbons | fall / 140t | per drop / once | `EntityEffectExecutor` |
| 10 era motes | ≤256 (GPU) | dimension visit | 1/client | `EntityEffectExecutor` + law change |

- **Ordering across docs:** every emitter above uses `layer:Translucent` with additive
  passes `vertexSortingMode:NONE` and alpha passes `DISTANCE`; where a concept overlaps
  a Quasar layer (3, 4, 5) set `orderInLayer` above the Quasar-equivalent so the Photon
  pass reads on top, never z-fights.
- **Veil-post / Iris pairing** stays the open BUNDLING.md risk; all concepts inherit the
  pre-authorized `photonFx=false` flip. Nothing here touches `FxBudget`.
- **Replay parity** is called out per-concept; every cue added must also be sent from the
  matching `replay(...)` branch (R12 law) — all three sequences already have the exact
  branch to extend.
- **Asset hygiene:** commit `.fxproj` sources beside every exported `.fx`; never commit
  third-party `.fx` (INTEGRATION.md §6). All ids resolve as
  `assets/eclipse/fx/<id>.fx`; sub-emitter file `slam_dust_puff.fx` counts as a
  first-class asset (referenced by `fxLocation` from #3).
