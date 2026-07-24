# IDEA-17 — Nether Identity & Wonder (Eclipse Event, wave 4, collector 17/20)

**User demand (hard requirements):**
1. The nether disc becomes **1:1 the same size as the overworld disc**, reading as sitting
   **directly under the overworld's bedrock seal** (no 8:1 scale).
2. The breach transfer becomes a **GLITCH-DRIFT**: a slow downward glitch-float through the
   breach (replacing the current teleport + Slow Falling "40-block drop"), and an **upward
   tractor pull to the ceiling** on the return trip.
3. Nether terrain must become INTERESTING: ceiling stalactite forests, glowstone chandelier
   fields, lava-fall curtains at sector seams, humming basalt organ pipes, soul-sand whisper
   valleys, ceiling-inverted structures.

**Code ground truth (read for this report):**
- `worldgen/DiscProfile.java` — `NETHER = ("nether", minY 0, height 256, seaLevel 32,
  surfaceBaseY 138, centerBottomY 32, rimBottomY 56, lensNormRadius 160)`. Overworld
  `lensNormRadius` is 480, final radius 440.
- `worldgen/FrozenParams.java` — `DEFAULT_NETHER_RADII = {0, 64, 110, 150}` vs
  `DEFAULT_OVERWORLD_RADII = {96, 150, 210, 280, 360, 440}`.
- `worldgen/DiscTerrainFunction.java` — nether surface branch of `computeSurfaceY`
  (base 138, clamp 100–150, flat fortress pad r<20), nether strata branch of
  `strataBlock` (moat lip magma, glowstone-sprinkled blackstone fringe below
  `undersideY`, deepslate→blackstone), moat carve in `column()`, cave band
  (`CaveDensity`) active for the nether too. Hash salts used through 28, noises through
  32 — **next free: 29+ hash / 33+ noise** (registry: `wiring/P1-W1.2_wiring.md`).
- `worldgen/DiscMapDefaults.netherDefaults()` — 5×72° wedges (nether_wastes,
  soul_sand_valley, basalt_deltas, crimson_forest, warped_forest), `Moat(50, 4,
  bridges {0°,180°}, 6°)`, landmarks `fortress_core (0,0)`, `breach_arrival (48,35)`,
  `bastion_remnant (−25,−76)`, `hanging_court (60,−60)`.
- `worldgen/nether/BreachTransferService.java` — descent teleports with the **8:1 divide**
  (`localX = (player.getX() − centerX)/8`), grants 160t Slow Falling; return is the
  soul-updraft column (`UPDRAFT_HEIGHT 22`, `UPDRAFT_STRENGTH 0.42`) → teleport to
  `returnPad() + 6y`.
- `worldgen/nether/BreachBuilder.java` — arrival chimney (r≈4, `CHIMNEY_HEIGHT 22`,
  basalt helix), budgeted `BuildJob` pattern (3 ms/tick, 4096 writes, finalize relight).
- `worldgen/nether/NetherUndersideDecor.java` — the `DiscGenPipeline.registerExtraDecor`
  seam + `inPatch` cell-hash pattern (glowstone stains, shroomlight, weeping vines) and
  the `AshEvents` player-proximity ambience tick.
- `worldgen/nether/HangingCourtBuilder.java` — async two-phase set-piece placer
  (pending registry + completion marker + budgeted writes) — the clone template for any
  new nether set piece.
- `worldgen/BreachGeometry.java` — overworld funnel (crater r16, chimney r5.5,
  `FUNNEL_DEPTH 44`, `SPOUT_DEPTH 14`), `carveAt`/`creepAt` pure overrides.
- `network/S2CBreachPayload.java` — Phase {QUAKE, OPEN, SETTLED}; P2 owns presentation.
- `veilfx/EclipseFxState.java` — `startTransitionGlitch(in, hold, out)` /
  `transitionGlitch(pt)` / `transitionFade(pt)` client glitch-post plumbing already exists.
- `data/minecraft/dimension_type/the_nether.json` — **`coordinate_scale: 8.0`**, height
  256, min_y 0. `data/minecraft/dimension/the_nether.json` → `eclipse:disc / nether`.

---

## Ranked ideas (1 = do first)

### 1. "Under-Bedrock" nether: 1:1 disc scale + ceiling roof shell — **M** (foundation)
The single change that delivers the demanded fiction: the nether IS the cavern directly
under the overworld's bedrock. Two coupled edits:

**(a) 1:1 footprint.**
- `FrozenParams.DEFAULT_NETHER_RADII {0, 64, 110, 150}` → `{0, 150, 280, 440}`
  (stage-aligned with the overworld radii so each overworld growth beat still has a
  matching nether beat; keep index 0 = 0 — nether stage 0 stays "not yet born").
  Guard: `FrozenParams` freezes radii per save, so this only affects NEW saves; document
  in the changelog. `StageRadii.set` path (stages.json) must ship matching values.
- `DiscProfile.NETHER lensNormRadius 160 → 480` (rim-normalised lens stays
  stage-reproducible; contract in `DiscProfile` javadoc is preserved).
- `dimension_type/the_nether.json coordinate_scale 8.0 → 1.0` — vanilla maps, compasses
  and the F3 coordinate fiction all become 1:1.
- `BreachTransferService.descend()` — delete the `/ 8.0D` local-offset divide (and the
  `fall.x / 8` on velocity): the player exits the overworld chimney at (x, z) and arrives
  at the SAME (x, z) in the nether. `BreachGeometry` center (92, 92) must therefore lie
  inside the nether stage-1 radius — with 150 it does (r≈130 < 150); move
  `eclipse:breach_arrival` in `DiscMapDefaults.netherDefaults()` to (92, 92) so the
  arrival chimney is vertically under the overworld funnel.
- `DiscMapDefaults.netherDefaults()` rescale: moat `(50,4)` → `(150−? …)` — recommend
  `Moat(190, 6, {0°,180°}, 4°)` (a mid-ring barrier the stage-2 growth crosses), wedge
  angles unchanged (angular wedges scale for free), landmarks pushed out
  (`fortress_core` stays (0,0); `bastion_remnant` → r≈210 crimson; `hanging_court` →
  r≈240 warped).

**(b) Ceiling roof shell ("the bedrock you are under").**
- Add a roof lens to the nether column: in `DiscTerrainFunction.column()` (nether branch)
  compute `ceilingBottomY(r)` as a mirrored lens — e.g. `232 − (232−200)·(r/480)²` so the
  cavern is tallest at the center — and thread `ceilingBottomY`/`ceilingTopY` through
  `DiscColumn` (2 new components; `topY = max(topY, ceilingTopY)`).
- In `stateInColumn` nether path: `y >= ceilingBottomY` → netherrack/blackstone body with
  the top 3 layers BEDROCK (mirror of the floor seal at `groundBottomY()+2`), edge-gated
  by the same `edgeFactor` so the roof tapers and crumbles at the rim exactly like the
  floor (rim band stays inside `RIM_REWRITE_MARGIN` → ring-sweep contract holds).
- `has_ceiling: true` is already set in the dimension_type — the fiction was pre-paid.
- Interactions to audit: `HangingCourtBuilder.chainToUnderside` and `ladderShaft`
  (surface probes unaffected), `BreachBuilder.chimneyWrites` (chimney must now PIERCE the
  new ceiling — see idea 2), ghast/spawn heightmaps (ceiling adds MOTION_BLOCKING tops —
  spawns under the roof still work since light is block-light only).

### 2. Glitch-drift breach transfer (descent float + return tractor) — **M**
Full design below ("Glitch-drift transfer — concrete design"). Hooks:
`BreachTransferService` (all four methods), `BreachBuilder.chimneyWrites` (ceiling
piercing), `S2CBreachPayload.Phase` + `BreachPayloads`, `EclipseFxState.startTransitionGlitch`.

### 3. Ceiling stalactite forests — **S** (once idea 1 lands)
Mirror the existing floor fringe formula onto the roof. In the nether branch of
`column()`, after `ceilingBottomY`: reuse `terrainNoises().fringe()` with an offset domain
(`x/22 + 1024, z/22 + 1024`) and the same `f²·f²·18 + hf²·f·10` needle profile to EXTEND
`ceilingBottomY` downward up to 24 blocks. In `strataBlock`, blocks between the needle tip
and the roof body reuse the existing fringe palette line
(`hash01x3(H_GLOW,…) < 0.10 ? GLOWSTONE : BLACKSTONE`) — glowing-tipped fangs for free.
Cluster the needles with a cell mask (`hash01(29, x>>4, z>>4) < 0.35`) so they read as
FORESTS with clearings, not uniform stubble. New hash salt 29. Single-file change
(`DiscTerrainFunction`), pure, stage-safe (keyed to final radius only).

### 4. Glowstone chandelier fields — **S**
A second `ExtraDecor` registered exactly like `NetherUndersideDecor.Setup` (new class
`worldgen/nether/NetherCeilingDecor.java`, `DiscGenPipeline.registerExtraDecor(NETHER, …)`).
Reuse the `inPatch(x, z, cell 24, salt, chance 0.30, radius 2.2)` helper: at patch
centers, hang a chandelier from `ceilingBottomY`: 2–5 CHAIN blocks, then a 3×3 diamond of
GLOWSTONE with 4 single-block drops (deterministic from the cell hash). Field density
peaks in the nether_wastes wedge (gate on `map.biomeAt == nether_wastes`). Sub-idea:
1-in-8 chandeliers get a SHROOMLIGHT core (warm/cold mix). All `setIfAir` writes — never
breaks the roof seal. Perf: identical cost profile to the existing underside decor.

### 5. Lava-fall curtains at sector seams — **M**
Make the five wedge boundaries VISIBLE monuments: sheets of lava pouring from ceiling to
floor at the seams. Hook: in `column()` nether branch call
`map.sectorBlendAt(NETHER, x, z)` (exists; currently overworld-only usage) — columns with
`blend.t() > 0.42` (within ~1.3° of the wobbled boundary) AND a radial gate
(`hash01(30, angleBucket, rBucket) < 0.5` per 24-block run so curtains are broken into
segments, not a solid 440-block wall) set a `seamCurtain` flag on `DiscColumn`. In
`stateInColumn`: paint one LAVA source at `ceilingBottomY − 1` and a MAGMA_BLOCK splash
basin (3-wide, 1-deep bowl with lava fill) at the local surface; the vertical stream
itself is vanilla flowing lava (only ONE source per column keeps light/flow updates
bounded — this is the same trick as the overworld rim spill curtains). Guards: suppress
within `moat.withinBridge(angle, 4°)` and within 24 blocks of any landmark clearance.
Sizing M because it needs a flow-perf pass on the live ring sweep (seam columns fall in
the rewritten annulus, so replay is already handled).

### 6. Basalt organ pipes that hum — **M**
Basalt-deltas wedge identity. Two parts:
- **Geometry (S):** in `computeSurfaceY` nether branch, for BASALT-style columns add a
  columnar field: `pipe = ridged simplex (new noise salt 33) sampled on a 9-block hex-ish
  cell`; where `pipe > 0.55`, quantize the surface UP by `8 + (hash & 15)` blocks and mark
  the column `organPipe` so `strataBlock` renders pure BASALT (axis Y) with a
  POLISHED_BASALT cap — clustered floor-to-mid-air pipe ranks. Tallest cells
  (`pipe > 0.8`) weld all the way to `ceilingBottomY` (full floor-to-ceiling columns).
- **The hum (S):** clone the `NetherUndersideDecor.AshEvents` pattern into an
  `OrganHumEvents` tick handler: every 60–100 ticks, for each nether player, if the
  player's 48-block neighborhood contains an organPipe cell (re-evaluate the same noise —
  pure function, no world scan), `playSound(BASALT_BREAK-family drone)` — concretely
  `SoundEvents.RESPAWN_ANCHOR_AMBIENT` or `BEACON_AMBIENT` at volume 0.35, pitch
  `0.6 + 0.5·hash01(cell)` so each pipe cluster has a FIXED chord note. Wind-gust gate:
  only hum on ticks where `sin(gameTime/160)` > 0.3 (the organ "breathes").

### 7. Soul-sand whisper valleys — **S**
Soul wedge identity. `SectorStyle.SOUL surfaceOffset −2 → −9` and `surfaceAmp 0.7 → 0.45`
(one-line each) sinks the wedge into a fog-flat basin between the wastes and deltas —
combined with the ceiling this reads as a low, oppressive crypt. Strata: in `strataBlock`
nether branch, SOUL columns get `hash01x3 < 0.06` SOUL_FIRE-ready SOUL_SOIL top patches
(soul fire ignition is vanilla behavior over soul soil near fire — place 1-in-40 eternal
SOUL_FIRE via the ceiling-decor ExtraDecor instead to stay deterministic). The whisper:
extend the existing `AshEvents` loop — players in a SOUL column
(`map.biomeAt == soul_sand_valley`) get, every ~200±hash ticks,
`playSound(SoundEvents.SOUL_ESCAPE / SCULK_CLICKING, volume 0.15, pitch 0.5)` offset
6–10 blocks BEHIND the player's look vector (`player.getViewVector(1.0).scale(-8)`) —
cheap, server-only, deeply unsettling. Mirrors the overworld "whisper wells" concept
(the nether `MapProfile.wells` list is currently empty — populate 3 wells in the soul
wedge as landmark-lite anchor points for P2's fog FX).

### 8. Ceiling-inverted structures: the Roothold gallery — **M**
The Hanging Court proved the pattern; invert it. New set piece `eclipse:roothold`
(landmark in `netherDefaults()`, warped wedge, r≈300, stage 3): a ruined bastion
courtyard built UPSIDE-DOWN against the ceiling — floors are ceilings, stairs run
inverted, a gilded-blackstone "throne" hangs point-down at the center, entered by
climbing one of idea 6's floor-to-ceiling basalt pipes (carve a 2×2 ladder bore through
one adjacent pipe). Implementation: clone `HangingCourtBuilder` (async placer +
completion marker + budgeted `BuildJob`); `courtAnchor` becomes
`ceilingAnchor = ceilingBottomY(landmark) + 2` and every `dy` in `buildPlan` negates.
Loot: second `nether/roothold` loot table. The two-phase
`StructurePendingRegistry` handles replay/repair identically. Also retro-fit: the
existing `hanging_court` chains (`chainToUnderside`) become dramatically longer under the
1:1 disc — verify `PLATFORM_HALF` clearance vs the new moat radius.

### 9. Titan fungus pillars (crimson/warped floor-to-ceiling forest) — **S**
With a ceiling ~60–100 blocks up, the crimson/warped wedges can hold wonder-scale flora.
ExtraDecor (same registration seam): cell-hash (`inPatch`, cell 48, chance 0.25) selects
pillar sites; build a 3–5-radius tapered trunk of CRIMSON_STEM / WARPED_STEM (axis Y)
from surface to `ceilingBottomY`, flare a 7-radius WART_BLOCK / WARPED_WART_BLOCK canopy
disk at 2/3 height and a root flare at the base, sprinkle SHROOMLIGHT (`hash < 0.08`)
through the canopy. All writes deterministic from cell hash; skip cells overlapping
landmark clearances and the moat. ~2k blocks per pillar — fine inside chunk decoration;
live-sweep replay comes free via the ExtraDecor seam.

### 10. False-sky constellations on the ceiling underside — **S**
Make looking UP in the nether always rewarding: re-run the `NetherUndersideDecor`
glowstone/shroomlight patch logic (new salts) against the CEILING underside
(`ceilingBottomY − 1`) but with tiny radii (1.15) and higher cell frequency — a field of
single glowing "stars", plus 1-in-200 columns dropping a lone 1-block CRYING_OBSIDIAN
"tear" (purple drip particles are free from vanilla). Combined with idea 4's chandeliers
this gives the nether a starry vault instead of the void-red fog. One new class or an
extension of `NetherCeilingDecor` from idea 4.

---

## Glitch-drift transfer — concrete design (FX + mechanics)

Replaces the teleport-with-Slow-Falling descent and caps the return updraft with a
ceiling pull-through. Server-authoritative, all in `BreachTransferService` + one payload.

### State
Add a `Map<UUID, DriftState> DRIFTING` (mirror of `TRANSFER_COOLDOWN` lifecycle:
cleared in `onPlayerLoggedOut`/`onServerStopped`). `DriftState{Phase phase, int ticks}`
with phases `DESCENT_OVERWORLD, DESCENT_NETHER, ASCENT_NETHER, ASCENT_OVERWORLD`.

### Descent (overworld funnel → nether floor)
1. **Capture** — in `tickOverworld`, keep the existing funnel-wall guard, but replace the
   `player.getY() <= transferY → descend()` branch: when the player passes
   `BreachGeometry.lipY() − 4` inside `DESCENT_RADIUS`, enter `DESCENT_OVERWORLD` and
   send the new phase payload (below). No more free-fall to `transferY`.
2. **Drift physics (per tick while in the chimney)** —
   `setDeltaMovement(centerPullX, DRIFT_SPEED, centerPullZ)` with `DRIFT_SPEED = −0.10`
   (≈2 blocks/s; the 44-block funnel takes ~11 s — a scene, not a drop), center pull
   `−dx·0.10` as today, `fallDistance = 0`, `hurtMarked = true`. **Glitch stutter:** on
   ticks where `hash(mapSeed, playerId, tick/7) < 0.25`, add a one-tick lateral jolt of
   ±0.12 and hold Y (delta y = 0) — the fall visibly "skips frames". Elytra/pearls
   already guarded by existing hooks.
3. **Handoff** — when `player.getY() <= transferY` (existing formula:
   `groundBottomY − 16` at the breach column), teleport 1:1 (idea 1: same x/z) to the
   NETHER CEILING breach mouth: `BreachBuilder.chimneyWrites` gains a ceiling bore —
   extend the existing r≈3.2 air shaft from the chimney top THROUGH the new roof shell
   (idea 1b) so there is a physical hole; arrival Y = `ceilingTopY + 2`, then enter
   `DESCENT_NETHER` and keep the same drift physics until landing on the netherrack
   funnel floor (`onGround()` → clear state, start `TRANSFER_COOLDOWN`, fire
   `QuestApi.completeTeamBeat("crossing_survived")` exactly where it fires today).
   Keep a 160-tick Slow Falling as a **safety net only** (covers server-side kicks,
   dismounts, chunk hiccups) — the drift controller normally overrides it.
4. **Abort safety** — if the player leaves the chimney radius or the state exceeds
   600 ticks, drop to the current behavior (Slow Falling + nothing else). Creative and
   spectator bypass at capture.

### Return (nether updraft → overworld crater)
1. **Tractor pull** — `tickNether`'s updraft column stays, but `UPDRAFT_HEIGHT` extends
   from 22 to `ceilingBottomY − updraft.getY()` (the column now reaches the roof) and the
   pull becomes velocity-clamped rather than additive:
   `setDeltaMovement(−dx·0.10, +0.18, −dz·0.10)` — a firm, constant tractor (slower than
   today's 0.42 burst; the ride up the chimney + roof is the return scene). Same glitch
   stutter hash as descent, inverted (one-tick Y hold + jolt).
2. **Ceiling pull-through** — at `player.getY() >= ceilingBottomY − 2` (instead of
   `updraft.getY() + UPDRAFT_HEIGHT`), teleport into the OVERWORLD chimney at
   `BreachGeometry` center, Y = `transferY + 4`, enter `ASCENT_OVERWORLD`: continue
   +0.18 upward drift INSIDE the funnel until `lipY() + 1`, then a final gentle arc
   (`setDeltaMovement(toward returnPad ×0.25, 0.1, …)`) deposits the player on the crater
   rim — the `returnPad()` teleport becomes the fallback only (abort path). The player
   experiences one continuous upward pull from nether floor to overworld surface.
3. Existing `clampNetherBorder`, pearl guards and cooldowns unchanged.

### FX (client, via P2's existing plumbing)
- **Payload:** add `Phase.DRIFT_DOWN` / `Phase.DRIFT_UP` / `Phase.DRIFT_END` to
  `S2CBreachPayload.Phase` (append-only — the read clamp in `S2CBreachPayload.read`
  already tolerates unknown ordinals on old clients) and send them player-targeted from
  the capture/handoff/landing points via `BreachPayloads`.
- **Post glitch:** on `DRIFT_DOWN`/`DRIFT_UP` the client handler calls
  `EclipseFxState.startTransitionGlitch(in 10, hold <driftEstimate>, out 15)` — the Veil
  glitch post-shader (`VeilPostController`) and screen-tear already exist; the dimension
  swap at handoff hides the teleport seam inside the glitch hold. On `DRIFT_END`, force
  `transitionGlitch → out` ramp.
- **Audio:** capture = `SOUL_ESCAPE` at pitch 0.6; every ~20 drift ticks a
  `SCULK_CLICKING`/`AMBIENT_CAVE` tick at randomized ±0.3 pitch with occasional
  hard cutoffs (audio "dropouts" sell the glitch); pull-through = one
  `RESPAWN_ANCHOR_DEPLETE` boom.
- **Particles (server, cheap):** replace the current descent ASH burst with a per-drift
  ring — 6× `REVERSE_PORTAL` orbiting the player (`sendParticles` every 4 ticks while a
  `DriftState` exists, angle = `tick·0.3`), plus `WHITE_ASH` trickle above on descent /
  below on ascent (motion cue). The existing baseline chimney FX in `onServerTick`
  stays.
- **Body language:** while drifting, apply `MobEffects.SLOW_FALLING` (already granted)
  so the falling pose animation reads as floating; on ascent no effect is needed
  (upward velocity does it).

**Sizing:** M — `BreachTransferService` (~120 new lines), `BreachBuilder` ceiling bore
(~15), payload enum + client handler wiring (P2 seam), no new systems.

---

## Cross-cutting guards
- All new worldgen is pure (map seed + coords + frozen params only) — every idea above
  names its salt; register salts 29+ (hash) / 33+ (noise) in `wiring/P1-W1.2_wiring.md`.
- Ceiling + 1:1 radii change generation output ⇒ NEW SAVES ONLY semantics via
  `FrozenParams` freeze; the ring-sweep reproducibility contract is preserved because
  the roof lens is normalised against the final radius exactly like the floor lens.
- Ideas 3/4/9/10 ride the `ExtraDecor` seam ⇒ live-sweep replay is automatic.
- Ideas 5/6 add flow/sound budgets — cap lava curtain segments per chunk (≤3 sources)
  and hum probes per player (1 per tick handler pass).
