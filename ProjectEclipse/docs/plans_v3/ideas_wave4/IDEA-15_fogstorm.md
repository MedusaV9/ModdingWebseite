# IDEA-15 — Fog Storm Dread & Payoff (Eclipse Event collector 15/20)

Scope: `stormfx/` (StormFxClient, StormWallRenderer, StormInteriorFx, StormReveal, StormRegistry),
`worldgen/fog/` (FogStormSites, StormLootData), fog mobs (`entity/fog/`), Fog Tyrant lair
(`entity/boss/fog/`). Read against `eval/EVAL-4_vfx_sequences.md` — especially the post-eval live
observations (vortex interior over-reach, `storm bolt` anchor, daylight wall contrast) and M2/M5.

Design thesis: the storm currently has one emotional register — "big wall". The approach is silent
until 56 blocks (`StormFxClient.LOOP_SOUND_RANGE`), the interior is a uniform 24-block gray
(`StormInteriorFx.INTERIOR_FOG_FAR`), and the loot camp gives no pull once you are blind inside.
These ideas build a dread ladder OUTSIDE, readable terror INSIDE, and a payoff beacon at the center
— using hooks that already tick per storm per frame, so almost everything is S.

Sizes: S = one file, < ~80 lines. M = 2–3 files or a small payload/protocol addition.

---

## 1. Approach dread ladder — heartbeat + fog tendrils at 60/40/20 blocks (M) ★

The storm should reach for you before you reach it.

- **Hook:** `StormFxClient.tickStorm` already computes `shellDist` per storm per tick (used for
  `tickArcs`/`tickWisps`/`tickLoopSound`). Add a `tickApproachDread(storm, shellDist, camera)` call
  with three bands, gated on `visibility > 0.5` and `StormInteriorFx.interiorAmount() < 0.1`
  (outside only):
  - **≤ 60:** faint heartbeat — `level.playLocalSound(camera…, SoundEvents.WARDEN_HEARTBEAT,
    SoundSource.AMBIENT, vol 0.25, pitch 0.8)` on a cadence that tightens with distance:
    `interval = Mth.lerp((60 - shellDist)/40, 50, 22)` ticks (store `nextHeartbeatTick` on
    `ClientStorm` next to `nextArcTick`). It sits under the churn loop that fades in at 56.
  - **≤ 40:** ground tendrils — 2–3 `CAMPFIRE_COSY_SMOKE`/`CLOUD` "fingers" per second crawling
    OUT from the wall base along the camera bearing: spawn at
    `center + dir(camAngle)·(radius − t·shellDist·0.5)`, y = wall base (reuse the `camAngle`
    math from `tickArcs`), velocity pointed at the player (`addParticle` with a small outward vx/vz).
  - **≤ 20:** tendrils reach the player's feet (spawn ring at `camera ± 2`, drifting inward past
    them) + heartbeat gains a second thump (two plays 6 ticks apart).
- **Grade pre-tint:** expose a smoothed `approachAmount = smoothstep(60, 20, shellDist)` from
  `StormInteriorFx` and blend `onComputeFogColor` up to 15 % toward `FOG_R/G/B` before entry —
  daylight visibly drains as you close (also softens the daylight-wall pop, see idea 5).
- **Budget:** particles via `QuasarSpawner.spawn(..., FxBudget.Channel.STORM)` where emitters are
  used; raw `addParticle` fingers are ~6/s, negligible.
- **Prerequisite:** EVAL-4 M2 (keepalive-proof `StormFxClient.handle`) so a resend doesn't reset
  band state mid-approach; idea 6 so "outside" is trustworthy for vortexes.

## 2. Interior lightning silhouette reveals — the flash shows you what shares the fog (S) ★

Inside, the 24-block clamp means mobs are invisible until they are on you. Make every arc flash a
horror beat: for 4–6 ticks the fog LIFTS and everything within ~56 blocks reads as a black shape.

- **Hook:** add `static int flashTicks` + `flash(int ticks)` to `StormInteriorFx`. Call it from
  the two existing bolt entry points when the camera is interior
  (`StormInteriorFx.interiorAmount() > 0.5`): `StormFxClient.strikeLightning(...)` (flash 6) and
  `StormFxClient.tickArcs(...)` (flash 4).
- **In `onRenderFog`:** `float lift = flashTicks / 6F;` then
  `far = Mth.lerp(interior, far, Mth.lerp(lift, INTERIOR_FOG_FAR, 56F))` — near plane stays at 6 so
  the world snaps into silhouette depth, not clarity.
- **In `onComputeFogColor`:** lerp the slate up to a violet-white (`0.55, 0.5, 0.7`) by
  `lift * 0.7F` — mobs (revenant robes, hound spines, the colossus hump) become backlit cutouts.
  Decrement `flashTicks` in `onClientTick` (pause-safe, same guard as `smoothedInterior`).
- Zero new draw calls, works under Iris (fog path is the Iris-safe tier per the class doc). The
  existing 20–60-tick arc cadence (`ARC_MIN/MAX_INTERVAL`) gives a free ~2/min scare rhythm.

## 3. Loot-room glow through fog cracks — a warm smudge to walk toward (S) ★

The camp (`FogStormSites.placeCamp`: FIRE + CAMPFIRE at center offsets) is the payoff, but inside
24-block fog you find it by luck. Give it a bleed-through glow that reads at ~35 blocks.

- **Hook:** `StormInteriorFx.onClientTick`, after `tickRainSheets`: when `smoothedInterior > 0.6`,
  find the nearest storm (`StormFxClient.storms()` is package-visible; both classes share
  `stormfx`) and, if `camera` is 12–45 blocks from `storm.center`, keep alive ONE budgeted warm
  point light at `center + (0, 3, 0)` — `FxBudget.tryLight()` + `PointLightData` color
  `(1.0, 0.62, 0.25)`, radius 14, brightness `0.5 · smoothedInterior` (exact pattern:
  `Bolt.claimImpactLight`). Release below 0.3 interior or > 50 blocks.
- **Fog "cracks":** 1 ember mote per ~10 ticks — `addParticle(SMALL_FLAME / LAVA pops)` rising from
  `center ± 1.5` so the smudge flickers instead of reading as a bug.
- The warm orange against the slate `FOG_R/G/B` is the only warm hue anywhere in the storm palette
  — an unmistakable "that way" without UI. Deliberately NOT visible from outside (the occluder
  never-see-inside guarantee in `StormWallRenderer` is untouched — light lives inside the shell).

## 4. Storm death = the fog swallows the scream (M) ★

A player dying inside a storm should be a broadcastable horror beat, inside and out.

- **Hook (server):** new `stormfx/StormDeathFx` subscribing `LivingDeathEvent` at
  `EventPriority.LOW` (house precedent: `lives/DeathFlowHooks`, `drama/WitnessedLossService`).
  Guard: `event.getEntity() instanceof ServerPlayer p` and `p` horizontally inside any
  `StormRegistry.storms(level)` radius (public frozen API).
- **At the corpse:** fog inhale — `sendParticles(CLOUD, 24, spread 1.2)` converging (negative
  speed toward the point is not supported; stamp two shrinking rings 6→2 over 10 ticks) + a quiet
  `EVENT_STORM_BURST` at pitch 0.6.
- **For listeners OUTSIDE the wall** (players in-dimension within 96 blocks of the shell but
  outside `radius`): a muffled scream from the nearest shell point — reuse the
  `StormLoopSound.updatePosition` projection (`center + n̂·radius`) and play
  `SoundEvents.PLAYER_HURT` vol 0.9 pitch 0.55 followed 8 ticks later by `EVENT_LIGHTNING_FAR`
  pitch 0.7. The wall ate someone, and everyone camped outside knows it.
- **For players INSIDE:** a 15-tick rain surge — send the existing `FxPayloads.sendFxEvent` with a
  new `FX_STORM_SURGE` id (client: temporarily feed `EclipseFxState.setStormInterior(interior,
  min(1, rain·1.6))`); the `storm_interior` post grade's `RainAmount` uniform is already wired.
- Pairs with `WitnessedLossService` without touching it (different priority slot, no shared state).

## 5. Daylight wall read: sun-aware contrast + additive rim (S) — EVAL-4 post-eval obs. #3

From ~40 blocks in daylight the wall reads as a flat solid cylinder (noise contrast collapses
against bright sky).

- **Hook:** `StormWallRenderer.onRenderLevelStage` — compute once per frame
  `float dayBoost = 1.0F - level.getSkyDarken(partialTick)/15F` (0 at night, ~1 at noon) and pass
  into `buildShells`/`emitShell`.
- **In `emitShell`:** (a) widen the churn band in daylight — `churn = (0.45 − 0.2·dayBoost) +
  (0.55 + 0.2·dayBoost)·hash3(...)` so gray variance survives sky brightness; (b) on the OUTER
  additive shell only (`shellIndex == 0`), add a rim boost near the top third:
  `alpha *= 1 + 0.5·dayBoost` — the violet additive glow becomes the silhouette edge the alpha
  shells can't provide against a bright sky.
- Constants only; no new geometry, no LOD interaction (also fold in EVAL-4 M4's occluder
  hysteresis while editing the file — same 10 lines of neighborhood).

## 6. Vortex interior clamp + teleport snap — trust gate for ideas 1–3 (S) — EVAL-4 obs. #1 + M5

The post-eval observation (interior rain/black sky at 44 blocks from an r=14 vortex) means
"inside/outside" is currently a lie for vortexes, and M5 keeps interior fog ~1–2 s after teleports.

- **Hook:** `StormInteriorFx.interiorTargetAt` — for `storm.type == TYPE_VORTEX`, evaluate the
  horizontal band against the TILTED radius at camera height:
  `rAtY = max(radius·0.25, radius − (cameraY − center.y)·StormWallRenderer.TAN_TILT)` (mirror of
  `emitShell`'s `topRadius` math) instead of the base radius; also verify the black-sky repro isn't
  the occluder cone lid (`buildOccluder` vortex spire, 0.30·height) clipping the camera frustum
  from outside — if it is, skip the lid when `centerDist > radius + 8`.
- **M5 fix in the same file:** track `lastCameraPos`; if the camera moved > 32 blocks in one tick
  (or on `ClientPlayerNetworkEvent.Clone`), snap `smoothedInterior = target` instead of easing.
- Without this, idea 1's "outside only" gate and idea 3's interior gate misfire around vortexes and
  teleports. Ship first.

## 7. First-breach swallow beat — crossing the wall is a threshold, not a gradient (S)

- **Hook:** `StormInteriorFx.onClientTick` — edge-detect `prevSmoothed < 0.5 && smoothedInterior
  >= 0.5` (rising only). Fire once per crossing: `playLocalSound(EVENT_STORM_BURST, vol 1.2,
  pitch 0.5)` + `TransitionFx.glitchPulse(0.15F, 10)` (wrapped in the existing
  `glitchPulseSafe` pattern from `StormFxClient`) + pinch the fog near plane 6→2 over 10 ticks
  (a `breachTicks` counter read by `onRenderFog`, same shape as idea 2's `flashTicks`).
- The world "gulps" as the wall closes behind you. Falling edge (< 0.3): a single exhale —
  `AMBIENT_CAVE`-family or `EVENT_LIGHTNING_FAR` pitch 1.4, quiet.

## 8. Fog-mob glowmasks breathe with the fog — eyes first, body later (S)

Storm hounds already have `glow_spine` glowmask shards (`StormHoundEntity` doc); revenants and the
colossus have emissive accents in their sheets.

- **Hook:** `client/entity/fog/FogRenderers` / `StormHoundRenderer` / `FogColossusRenderer` — the
  emissive layer's alpha (or `getRenderColor` on the glow layer) scales with
  `StormInteriorFx.interiorAmount()`: `emissive = base · (0.6 + 0.8·interior)`.
- Outside a storm, mobs look normal; inside, the first thing the fog gives you at 24 blocks is
  paired glow points and a floating spine — silhouettes for idea 2's flash to confirm. Pure
  client-side multiplier; zero server/protocol changes.

## 9. Lair-aware dread — the heartbeat doubles where the Tyrant sleeps (S)

The Tyrant lair (`FogBankMarker`, TRIGGER_RANGE 20) currently telegraphs nothing until the summon.

- **Hook (server, ambience):** `FogBankMarker.stampBankPillars` — bias the pillar ring toward the
  nearest watching player: add `+ 0.35·sin(bearing(player) − angle)` weighting to the per-pillar
  smoke count so the bank visibly "leans" at whoever approaches (positions already computed there;
  `tickLair` already finds the nearest player).
- **Hook (client, heartbeat):** idea 1's ladder checks `FogBossEntities.FOG_TYRANT.isBound()`-style
  cheap state — simplest: server sends the lair pos piggybacked on the existing per-dimension
  resync (`StormRegistry.resync`) as one extra payload field, or skip protocol work entirely and
  key off proximity to the storm CENTER (lairs are always the site center per
  `FogStormSites.reconcileTyrantLair`): within 30 blocks of center while interior > 0.6, the
  heartbeat from idea 1 continues INSIDE, double-thump, cadence 16 ticks.
- Outcome: the deepest storm has a pulse, and players learn "double heartbeat = boss" for free.

## 10. Chest-open storm reaction — loot has a price (M)

Payoff sting that converts the camp from "free chests" into a scene.

- **Hook (server):** new listener in `worldgen/fog/` on `PlayerContainerEvent.Open` (or
  `PlayerInteractEvent.RightClickBlock` on `Blocks.CHEST`): match position against
  `EclipseWorldgenState.fogSiteState(siteId).chests()` for active sites (positions persisted by
  `FogStormSites.materializeSite`). First open per chest per session (a `Set<BlockPos>`):
  - one shell arc volley — `FxPayloads.sendFxEvent(level, FX_LIGHTNING_STRIKE, wallPoint,
    intensity 0.5, …)` at the shell point facing the chest (same projection as idea 4);
  - `EVENT_LIGHTNING_FAR` at the chest, pitch 0.8;
  - 30 % chance: one `fog_revenant` materializes 12–16 blocks out via the
    `EventSpawnRules.findStormSpawn` placement contract (respect `SpawnGates.FOG_STORM` and the
    revenant caps — call through a small public hook added to `EventSpawnRules` rather than
    duplicating the gate).
- Honors the EVAL-4 `storm bolt` observation: anchor the arc at the WALL point computed
  server-side, never at the command/player source.

---

## Ranked summary

| # | Idea | Size | Files touched |
|---|------|------|----------------|
| 1 | Approach dread ladder (heartbeat + tendrils 60/40/20) | M | StormFxClient, StormInteriorFx |
| 2 | Interior lightning silhouette reveals | S | StormInteriorFx, StormFxClient |
| 3 | Loot-camp glow through fog cracks | S | StormInteriorFx |
| 4 | Storm death = fog swallows the scream | M | new StormDeathFx, FxPayloads |
| 5 | Daylight wall contrast + additive rim (EVAL-4 obs #3) | S | StormWallRenderer |
| 6 | Vortex interior clamp + teleport snap (EVAL-4 obs #1, M5) | S | StormInteriorFx |
| 7 | First-breach swallow beat | S | StormInteriorFx |
| 8 | Fog-mob glowmasks breathe with the fog | S | client/entity/fog renderers |
| 9 | Lair-aware dread (double heartbeat, leaning banks) | S | FogBankMarker (+ idea 1) |
| 10 | Chest-open storm reaction | M | new fog listener, EventSpawnRules hook |

Ship order note: **6 before 1–3** (inside/outside detection must be correct), and EVAL-4 **M2**
(keepalive-proof `StormFxClient.handle`) before 1 (band/clock state survives resends).
