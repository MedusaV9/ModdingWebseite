# EVAL-4 — VFX + Sequences Audit (Fable)

Read-only audit of `sequence/`, `cutscene/`, `veilfx/`, `stormfx/`, pinwheel shaders, quasar
emitters, `network/fx`, `client/sky/`. Excludes already-fixed items (grade cap, storm
keepalive, approach y-band, fade-hold cap, `storm_interior` reserved word).

---

## CRITICAL

### C1. Cutscene ACK handler undoes the freeze + gather of a synchronously chained scene
`cutscene/CutsceneService.java` — `handleClientState` (FINISHED/SKIPPED) and `handleSkipRequest`.

Order of operations is wrong:

```java
completeSession(player, ...);       // -> group.playerDone() -> onAllFinished.run()  (SYNCHRONOUS)
if (!session.preview()) FreezeService.unfreeze(player);
restoreReturn(player, ...);
```

`completeSession` runs the group callback synchronously. For the expansion chain
(`skyward` FINISHED → `beginFlyover`), the callback calls `CutsceneService.play(PATH_FLYOVER, …,
PlayOptions.global(12))`, which **gathers the player (records a `RETURNS` snapshot + teleports
to the viewpoint ring), freezes them, and installs the new session**. Control then returns to
the ACK handler which:

1. `FreezeService.unfreeze(player)` — kills the freeze that the *flyover* just applied. The
   player is walkable and vulnerable through the entire 15 s global cinematic while their
   camera is detached (fall damage, mobs, lava — no invuln, no rubber-band).
2. `restoreReturn(player, …)` — consumes the `RETURNS` snapshot the flyover's gather *just*
   created and teleports the player straight back to their origin. Net effect: two teleports in
   one tick, the "gathered group show" silently degrades to a local play from the origin, and
   the end-of-flyover return becomes a no-op (snapshot already spent).

The watchdog path (`onServerTick`) got the order right: unfreeze → restoreReturn → **then**
`session.group().playerDone()`. The ACK path must match it.

**Fix (3-line reorder):** in `handleClientState` and `handleSkipRequest` run
`FreezeService.unfreeze` + `restoreReturn` **before** `completeSession`. Alternatively (more
robust): defer the group callback to the next tick (`server.tell(new TickTask(...))`) so a
chained `play()` can never be re-entered by the frame that completed the previous scene.

### C2. `CutsceneService` statics survive world unload (singleplayer) — source of the stale y=38 returns
`cutscene/CutsceneService.java` — `SESSIONS` / `RETURNS` are static and there is **no
`ServerStopped(ing)Event` handler** (compare: `IntroSequence.onServerStopped`,
`ExpansionSequence.onServerStopped`, `ViewDistanceService.onServerStopping` all clear their
statics). A singleplayer client that leaves a world mid-cutscene leaves the UUID→snapshot rows
behind; on the next world, `RETURNS.putIfAbsent` ("FIRST origin wins") means the **stale
snapshot from the previous world blocks the fresh one** and the next restore teleports the
player to old-world coordinates — e.g. y=38 inside solid ground of a different world.

**KNOWN ISSUE (y=38 return spots) — proposed fix, three layers:**
1. **Lifecycle**: add `onServerStopped` clearing `SESSIONS` + `RETURNS` (and add the C1 reorder
   so snapshots are consumed at the right moment).
2. **Snapshot at the right time**: record the `ReturnSnapshot` at the *start of the whole
   chain* (first `play()` with `returnAfter`), never inside `gatherPlayers` of a chained link —
   with C1 unfixed the snapshot can be taken after a previous transport already moved the
   player.
3. **Validate at restore**: before `FreezeService.transport`, sanity-check the target the same
   way `gatherSpot` does — if the snapshot pos is inside solid blocks / below the heightmap
   (`MOTION_BLOCKING_NO_LEAVES`) or in void, re-snap Y to the heightmap top (keep x/z/rot).
   Cheap, and also heals legitimate cases where terrain changed while the player was away
   (ring growth rewrites terrain **during** the expansion cinematic — the origin column may
   literally not exist anymore when the return fires).

---

## MEDIUM

### M1. `ExpansionSequence.onGrowthStart` strands nether visitors on early-return paths
`sequence/ExpansionSequence.java`. `onGrowthStart` first does `RUNS.remove(profile)` +
`abortRun(previous, …)` — and `abortRun` explicitly does **not** return visitors ("carried or
returned by callers"). The visitors are only carried over on the path that builds a new `Run`.
The three early returns (`!animate || toStage <= fromStage`, `!freezeDuringUnlocks()`,
`"intro_fusion"` trigger) drop `previous.netherVisitors` on the floor: online visitors stay
parked at the overworld viewpoint until the *next* login applies their `NetherReturns` row.
**Fix**: call `returnNetherVisitors(server, previous)` before each early return (or make
`abortRun` return them when no successor run adopts them).

### M2. Storm keepalive resets client transition clocks
`stormfx/StormFxClient.handle` unconditionally does `storm.stateStartTick = clientTicks`,
`storm.glitchStarted = false`, and recomputes `revealStyle` on **every** payload. Now that the
server periodically re-sends state (the new keepalive), a resend of `STATE_SPAWN` mid-ramp
restarts the spawn/reveal choreography (visibility snaps back toward 0 and re-ramps; the
reveal glitch pulse re-fires). Same for a `STATE_DISSIPATE` resend. **Fix**: when
`state == storm.state`, update only center/radius/height/type and leave `stateStartTick` /
`glitchStarted` / `revealStyle` untouched.

### M3. `FxBudget` SEQUENCE burst is 2 s, not the documented 3 s
`veilfx/FxBudget.java`. `burstAllowed = (seqHist0+seqHist1+seqHist2) < SEQUENCE_BURST_HISTORY_CAP
(120)`. At the full 60/window burst rate the history hits 120 after **two** windows, so the
third window is throttled to 30 — the "burst to 60/s for ≤ 3 s" acceptance criterion actually
delivers 2 s. **Fix**: `SEQUENCE_BURST_HISTORY_CAP = 180` (3 × 60), or compare with `<=`.

### M4. Occluder LOD switches segment count with no crossfade
`stormfx/StormWallRenderer.buildOccluder`: `segments = shellDist < NEAR_LOD_END + LOD_FADE ?
48 : 24` — a hard step at 176 blocks. The translucent shells crossfade (`nearW/farW/impW`
smoothsteps) but the **opaque** occluder silhouette pops between a 48-gon and a 24-gon
(radius error ~0.9 blocks on a r=100 storm), visible as a rim "click" against the sky exactly
once per approach. **Fix**: pick the count from `centerDist` bucketed per storm with the same
±16-block hysteresis band used for the shells (swap only when fully inside a band), or just
always use 48 (the occluder is 2·segments quads — trivial).

### M5. Storm interior fog/grade lingers after instant exits, and pauses hold it
`stormfx/StormInteriorFx.java`. `smoothedInterior` only decays via the 0.16 smoothing —
~22 ticks to fall from 1.0 below the 0.02 fog gate, ~35 ticks below the 0.002 snap. After a
teleport out (cutscene gather, `/tp`, rift travel) the player keeps ~1–2 s of 24-block fog +
rain grade while standing somewhere else entirely — exactly the "interior clamp while NOT
inside" symptom. Also `onClientTick` returns early when `minecraft.isPaused()` but
`onRenderFog` keeps applying the frozen value (correct while inside, stale after a
pause-screen teleport, e.g. "Save & Quit to title" → other world uses the logout reset, but
LAN pause does not tick down). **Fix**: detect camera teleports > ~32 blocks/tick (or listen
to `ClientPlayerNetworkEvent.Clone`/dimension change, which already resets storms) and snap
`smoothedInterior = target` instead of easing.

### M6. `growth_front` dynamic anchor resolves once — flyover camera does not track the wave
`cutscene/CutsceneService.resolveDynamicAnchor` is called once in `play()`; the anchor rides
the payload as a constant. `expansion_flyover` (300 ticks) is choreographed as a sweep "over
the moving wave edge", but by mid-path the front has advanced (RingGrowthService keeps
sweeping during the cutscene) and every `lookAt` (offsets ≤ 24 blocks from the anchor) stares
at already-grown terrain. Combined with the high/far keyframes (y 20–70, up to 120 blocks
out) the shot reads as a near-static aerial hold. See Quick win #1.

### M7. Fog-color handler order is unspecified between `OverworldFogTint` and `StormInteriorFx`
Both subscribe to `ViewportEvent.ComputeFogColor` at default priority. If the purple day tint
runs **after** the interior slate blend, the inside-storm fog is re-lerped 35 % toward bright
purple at midday, washing out the R14 "storm slate" read. **Fix**: give
`StormInteriorFx.onComputeFogColor` `EventPriority.LOW` (run last), or make the tint skip when
`StormInteriorFx.interiorAmount() > 0.5`.

---

## LOW

- **`rift_glitch`/`storm_interior`/`border_glitch` `Time` wraps every 100 s**
  (`System.currentTimeMillis() % 100_000`): one visible pop of rain streaks / block layout /
  scanline phase per wrap. Harmless for glitch passes (they re-seed 12×/s anyway), mildly
  visible on `storm_interior` rain. Wrap on a multiple of the largest pattern period or use
  `% 3_600_000` like `limbo`.
- **`FxPayloads.handleFxEvent` glide events match "nearest player within 8 blocks"** — with
  two gliders crossing paths the trail can attach to the wrong one, and `FX_GLIDE_STOP` can
  remove the other's loop. Carry the entity id in `S2CFxEventPayload.b` instead.
- **`LimboSpecialEffects` zenith flip when camera is above the zenith point** —
  `ZENITH_DIR.y <= 0` snaps the disc to straight-up; flying above y≈deck+480 makes the disc
  jump 180°. Cosmetic (limbo has no legit flight that high).
- **`SunTracker` last-frame data crosses dimension changes** — `sunScreen()`/`sunOccluded()`
  keep the previous overworld frame's values for the first frames in the new dimension;
  `sun_halo` is gated by grade predicates so exposure is 1-frame. Cheap guard: clear the
  cached frame on `ClientPlayerNetworkEvent.LoggingOut`/respawn.
- **`IntroSequence` FX replays share one raw storm id (`999_006`)** — two overlapping replays
  (or FLIGHT replay + LIGHTNING replay from two operators) clobber each other's `ClientStorm`.
  QA-only surface; bump a counter within a reserved range.
- **`StormInteriorFx` bottom band reaches 14 blocks below storm center** — caves under a
  storm get interior fog/grade. Arguably "inside the storm"; flag only if caving under a fog
  storm feels wrong in playtests.

### Verified clean (no findings)
- **Shaders (all 9 programs + `eclipse_common.glsl`)**: no reserved-ish identifiers
  (`active/input/output/filter/sample/buffer`) used as variable names — grep hits are comments
  only. Every declared uniform is fed by its Java feeder (`world_grade`,
  `sun_halo`, `rift_glitch`, `limbo`, `storm_interior`, `shockwave`, `ghost_grade`,
  `altar_aberration`, `border_glitch` — cross-checked against all `getUniform(...)` call
  sites); no declared-but-unfed or fed-but-undeclared mismatches. Division guards
  (`max(screenSize.y,1)`, `1e-4` epsilons, `normalize(+1e-5)`) present everywhere.
- **Quasar emitters (26 files)**: all parse as valid JSON, consistent schema
  (`emitter_settings`/`particle_data`/`modules`), **no `veil:light` modules anywhere** (lights
  are Java-side `FxBudget` claims — correct per §3.5), counts are modest (max `count` 20 ×
  `rate` 1–10; worst case `cutscene_veil` 20×3), all sprites exist on disk
  (`purple_wisp.png`, `border_glitch.png`, `heart_full.png`).
- **`network/fx` handlers**: all client entry points are null-level guarded
  (`strikeLightning`, `RiftFx.openRift`, `nearestPlayer`, `BreachClientFx`) or touch only
  static blackboards (`EclipseFxState`, `FxAnchors`, `CaptionRenderer`). Payload registrar
  correctly on the MOD bus; client classes fully-qualified/lazy for dedicated servers.
- **`VeilPostController` priorities**: eviction order (TRANSITION > FEATURE > GRADE
  protection) implemented correctly; the Iris + config gate applies uniformly.
- **`PathSampler`**: arc-length LUT, Catmull-Rom/Bezier, binary search and end-clamping are
  correct; double precision world anchoring avoids far-coordinate jitter.
- **`FloatingDecor` / `QuasarSpawner` / `StormReveal`**: reconcile/adopt logic, broken-emitter
  latching, fallback particles, and strike scheduling check out. (`@EventBusSubscriber`
  without `bus = MOD` on `EclipseDimensionEffects` is fine — FML 4.0.43 auto-routes listeners
  per event type; verified against the shipped loader jar.)

---

## TOP 3 QUICK WINS

### 1. Expansion FLYOVER pacing (the observed "~50 s static aerial hold")
The path itself is only 300 ticks (15 s) and does move — the hold is the **sum of three
stacked effects**, all cheap to fix:

- **The ACK race (C1) degrades the gather**, so the shot is watched from wherever the player
  stood, often far from the front → tiny parallax → "static".
- **The anchor is resolved once (M6)** and the keyframes are high and far: y-offsets 70/38/20/
  24/48 with `lookAt` pitches 12–30° down from up to 130 blocks out. At that altitude the
  15 s sweep covers ~3.5 blocks/s of apparent ground motion.
- **After the cutscene ends, GROWTH holds** (`beginGrowth` shows a caption and waits for the
  terrain sweep — 30–75 s in live logs) with the player parked at the viewpoint (nether
  visitors stay until END). 15 s of flyover + the GROWTH wait ≈ the observed ~50 s.

Concrete parameter changes (all in `assets/eclipse/cutscenes/expansion_flyover.json` +
`ExpansionSequence`):

```
durationTicks: 300 → 220                     (11 s reads snappier at this scale)
keyframes y:   70/38/20/24/48 → 45/26/14/18/30   (halve apparent altitude)
keyframes x/z: pull first frame -120,-35 → -80,-25 (shorter approach leg)
lookAt:        spread laterally along the front instead of clustering near the anchor:
               [0,6,0] / [0,5,5] / [8,3,0] / [24,2,-16] → [-30,5,20] / [-10,4,10] /
               [12,3,-6] / [34,2,-24] / [10,2,8]        (camera pans across the wave)
fov:           74→68→62→62→70 keep, but add "shake" 0.1 at t 0.25 for texture
```

And in `resolveGrowthFront`: project the anchor **ahead** of the current front by
`(flyover duration / sweep duration) × remaining ring width` so the camera arrives where the
wave will be mid-shot (one-line lead calculation; no per-tick re-anchor needed). Finally,
return the gathered watchers at GROWTH start (they already got the payoff) instead of holding
them — nether visitors keep their END return.

### 2. Reorder `handleClientState` / `handleSkipRequest` (C1) — 3 lines each
Unfreeze + restoreReturn **before** `completeSession`, mirroring the watchdog. Single most
impactful correctness fix in the audit: restores freeze/invuln/gather/return semantics for
every chained scene (intro chains and expansion chains alike).

### 3. Keepalive-proof `StormFxClient.handle` (M2) — ~5 lines
`if (state == storm.state) { update center/radius/height/type; return; }` before the clock
writes. Prevents the new keepalive from visibly restarting spawn/dissipate ramps and
re-firing reveal glitches on every resend — protects the intro vortex and every fog-storm
reveal.

---

*Also recommended while in the area (from C2): add the `ServerStopped` cleanup to
`CutsceneService` and the heightmap re-snap in `restoreReturn` — together they close every
stale/low return-spot path we could construct, including the reported y=38.*
