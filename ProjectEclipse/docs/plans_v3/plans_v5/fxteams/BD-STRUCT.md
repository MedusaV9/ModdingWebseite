# FXTEAM-BD-STRUCT — BLOCK DISPLAY animation cluster

Team log (planner + ideators + polishers), process per system: PLAN → IDEATE 6+ →
IMPLEMENT → POLISH 2 → POLISH 3. Cluster: `worldgen/stage/StructureFlightFx.java`
(rift piece delivery), `worldgen/end/EndShatterSequence.java` DISPLAY/debris portions
(the carve pass is untouched), intro/other display usages
(`limbo/StartEventCutscene` + `sequence/FloatingDecor`, `limbo/OarAnimator` verified),
devtools display placer (`devtools/display/DisplayPlacerService` + `DisplayAnimator`,
`devtools/dev/DevDisplayCommands` seam, `worldgen/structure/SanctumOrbitals.rebuild`).
CUT-EXPANSION owns `ExpansionSequence.java` + cutscene JSONs — this team owns
`StructureFlightFx` internals + shatter display code only. Self-checks: `javac`
(release 21) against the cached moddev merged-jar (`neoforge-21.1.238-merged.jar`) +
`serverLegacyClasspath.txt` + `build/classes/java/main`. NO gradle, NO git.

Shared transform-interpolation craft laws applied throughout:
- **Keyframe transport**: `setTransformationInterpolationDelay(0)` +
  `setTransformationInterpolationDuration(cadence)` + `setTransformation(poseAt(t + cadence))`
  — the pushed pose is the one the window ENDS on, so the client tween covers between
  keyframes; NEVER per-tick teleports, NEVER a pose that trails the send tick.
- **Angular momentum consistency** on tumbling debris: one fixed tilted axis + one fixed
  signed rate per piece, plus slow pole precession — never re-rolled axes / flips.
- **Overshoot-settle** scale reads (1.06 → 1.0), **2-tick landing squash** (y 0.94)
  anchored at the piece bottom, **brightness override ramps** (glow out of the rift →
  ambient on land; dissolve = shrink + brightness-down over the last 20 %).
- **Seam timing**: dust/shake/thud fire when the relevant keyframe's interpolation ENDS
  on the client, never at the server send tick.
- **Budgets frozen**: existing display caps kept (80/delivery, 12 orbitals, 28 decor,
  120 debris); updates stay batched on the existing cadences.

New shared utility: `worldgen/stage/DisplayBrightnessFx` — brightness override via a
vanilla `saveWithoutId`/`load` NBT round-trip. `Display.setBrightnessOverride` is
private and NOT AT-opened, and a new accesstransformer line is unusable in this lane
(the cached moddev merged-jar only reflects AT changes after a gradle rerun). Every
other NBT key round-trips to its current value — `SynchedEntityData` no-ops equal sets,
so the only wire delta is the brightness itself and in-flight interpolation is
untouched. Law: brightness syncs UN-interpolated (snaps) → ≤ 3 coarse steps per piece
life, hidden inside motion.

---

## 1. STRUCTURE DELIVERY — `StructureFlightFx.java`

**PLAN.** Interpolation transport verified present (2 t cadence == duration — no
teleports; the entity never moves, motion lives in the transformation ✔), but four
craft gaps: (1) keyframes pushed the pose of the SEND tick, so the client permanently
trailed one interval and the landing visually happened 2 t after the fx; (2) launch
stagger was scatter-order (random hail); (3) scale was constant ×1.02 — no
overshoot-settle, no squash, and the settle "dip" intersected the grid cell; (4) no
brightness story — pieces sample light at their GROUND entity anchor, so sky pieces
rendered ground-dim while exiting a luminous tear.

**IDEATE.**
1. Keyframe lead: push `poseAt(t + UPDATE_INTERVAL)` (the SanctumOrbitals/FloatingDecor
   transport law), clamped to phase boundaries. ✔
2. Center-out SPIRAL launch order: sort pieces on `radius + turnFraction·3 blocks` and
   assign batch launch ticks from the sorted order — the footprint fills as one
   deliberate outward spiral. ✔ (pure function of deterministic targets + stable sort —
   replay-identical)
3. Scale craft: emerge ×0.85 growing on the flight ease into a ×1.06 hover overshoot,
   settle eases back to ×1.0; ground contact clamps the height offset to 0 and spends
   the residual dip energy as a ~2 t y-squash to 0.94 (half-strength x/z counter-bulge),
   BOTTOM-anchored so the base stays glued to the cell while the top compresses. ✔
4. Brightness ramp via `DisplayBrightnessFx`: (15,15) at spawn → (8,15) at 55 % flight →
   cleared exactly at the landing seam. ✔
5. Landing seam on interpolation END: the push whose window crosses contact
   (settleT ≥ 0.58, where `0.35·(1−s)² − 0.07·sin(πs)` crosses zero) schedules
   `fxDueAge = age + UPDATE_INTERVAL`; the thud/shake/brightness-clear fire when the
   flight clock reaches it. ✔
6. Per-piece glow_color_override outline pulse on landing: rejected — setter private,
   not AT-openable in this lane, and `setGlowingTag` (the available seam) is a vanilla
   team-color outline, wrong read for masonry.
7. Rotation wobble (secondary nutation) during flight: rejected — spin already runs
   integer turns on a damped ease that lands grid-aligned; nutation would break the
   exact-alignment guarantee for zero added read at 30–60 t flight lengths.
8. Continuous brightness fade (per-push steps): rejected — brightness is synced
   un-interpolated; 15–30 NBT round-trips per piece for a strobe-y read violates both
   the batching law and the snap-hiding law.

**IMPLEMENT.** `Piece` gains `glowStage`/`fxDueAge` (and `launchTick` is assigned
post-sort). `animate()` targets `min(pieceAge + 2, flight + settle end)`; contact
scheduling + mid-flight glow step live there; the due-fx check runs at the top of the
flight tick loop (fires even if the piece settles first — it can't, contact ≤ settle−2,
but the order is safe by construction). `poseAt` carries per-axis scale (xz, y) with
the plunge branch preserved: cavity pieces keep an accelerating monotonic descent
THROUGH the surface (no clamp, no squash — a full block deep at discard) so the
punch-in read survives. `buildPieces` sorts on `spiralKey` (radius + fractional-turn ×
3-block pitch) and assigns `launchTick = (order / 8) · 6`.

**POLISH 2 (correctness).** Rest pose byte-identical to pre-craft (settleT = 1 →
yOff 0, squash sin(π) = 0, uniform ×1.02 — grid-exact, encloses the real block).
Continuity audited at both phase seams: hover scale 1.06·1.02 matches settle-start
base; integer spin turns mean settle-start identity rotation is exact. The
flight→settle anchor switch (center → bottom) moves the visual base +0.031 blocks
inside one interpolated window — invisible, accepted. Plunge contact fx still fires
(~s 0.45 when the deep dip crosses the surface — thud at entry, correct). Watchdog,
PLACED sweep, stray-join discard and `LIVE_DISPLAYS` bookkeeping untouched;
`display.load()` keeps UUID and tags, so sweep doctrine is unaffected.

**POLISH 3 (budget + tuning).** Zero new entities; packet cadence unchanged (1
entity-data push / 2 t per unsettled piece). Brightness adds ≤ 3 NBT round-trips per
piece (~240 worst-case per delivery, spread over the whole window — off the hot path).
Spiral pitch 3.0 blocks/turn chosen so a 64-footprint delivery sweeps ~9 revolutions —
reads as a spiral at batch size 8 without degenerating into rings (1 block) or radial
spokes (10+). Squash 0.94 with 0.5× counter-bulge keeps apparent volume within 3 %.

---

## 2. END SHATTER DEBRIS — `EndShatterSequence.java` (displays only; carve untouched)

**PLAN.** The one true teleporter in the cluster: debris drove `entity.teleportTo` every
tick with `teleport_duration: 2` NBT — per-tick position packets for up to 120 entities
× 300 t, no tumble at all (bare unrotated blocks), a hard `vy −= 0.012` gravity (heavy,
not "gravity-lite"), and a pop-out removal (TTL cliff / y < 200). Everything the craft
brief bans. Full rework onto the keyframe transport; the CUT-END ember-trail bursts
(added by that team in `tickDebris`) must survive and follow the visual position.

**IDEATE.**
1. Fixed entity anchor + closed-form drift in the transformation translation (position
   = pure function of age: stateless pushes, the C7/orbitals doctrine). ✔
2. Keyframes every 4 t (== interpolation duration), all chunks sharing the
   separation-beat spawn tick → every push lands batched on one server tick. ✔
3. Angular momentum consistency: per-chunk fixed tilted axis (seed-mixed off the spawn
   column), fixed signed rate 0.6–1.6°/t, slow pole precession 0.08–0.20°/t around Y. ✔
4. Gravity-lite arcs: launch +0.06 vy, G = −0.003/t², terminal −0.35/t (closed-form
   parabola with a linear tail) — a lazy tear-off drift, ≤ 1.4 blocks per 4 t window so
   tweens stay dense; total sink ~77 blocks over the TTL, an arcing fall into the void
   fog rather than a brick drop. ✔
5. Dissolve = shrink + brightness-down over the last 20 % of TTL: scale eases in
   (1 − 0.97·d²) to a 3 % floor (never 0 — degenerate matrix), brightness steps
   (4,8) → (1,3) at d 0.34/0.67 via `DisplayBrightnessFx`. ✔
6. Per-chunk size spread ×0.70–1.15 (was uniform full blocks) — seam rubble reads as
   rubble. ✔
7. Keep `teleport_duration` but batch teleports every 4 t: rejected — pos-rot
   interpolation caps at short windows, still one position packet per entity per push,
   and the tumble/dissolve need the transformation anyway; half-measure with no win.
8. Verlet-integrated per-tick velocities (old shape, new transport): rejected —
   stateful integration breaks the "absolute function of age" law; closed form replays
   identically and costs the same.
9. Angular velocity damping as chunks fall: rejected — real tumbling rock in vacuum
   keeps its spin; damping reads as underwater.

**IMPLEMENT.** `Debris` rebuilt (final kinematic identity + `age`/`dissolveStage`;
`driftAt`/`fallAt` closed forms). `spawnDebrisDisplay` constructs
`Display.BlockDisplay` directly (AT-opened setters; born posed at t = 0, duration 0) —
the NBT `loadEntityRecursive` + `teleport_duration` path deleted. `tickDebris` keeps
per-tick TTL/removal bookkeeping but pushes ONE interpolated keyframe per chunk per
4 t targeting `age + 4`; void removal keys off the computed arc
(`origin.y + fallAt(age) < 200`), since the entity itself never moves. CUT-END's
rotating ember-trail sampler preserved verbatim — bursts now fire at `driftAt(age)`
(the visual position) instead of the stationary entity anchor.

**POLISH 2 (correctness).** Removal audit: TTL cliff no longer pops — the dissolve has
shrunk chunks to 3 % scale before discard; `isRemoved` and void-arc guards keep the
iterator safe. Deterministic params all mix off `SALT_DEBRIS` + spawn column (spin sign
reuses the drift jitter hash — no new salts). `DEBRIS_TAG`, boot `sweepDebris`, cap,
and `DEBRIS.clear()` on stop untouched. Trail-burst index math (rotating cursor)
untouched. Culling: displays keep width/height 0 (vanilla = culling disabled), so
large translations from the fixed anchor render fine; view-range anchors at the seam,
correct for disc-side viewers.

**POLISH 3 (budget + tuning).** Wire math: OLD ≈ 120 position packets/t for 300 t
(~36 000); NEW ≈ 120 entity-data pushes / 4 t (~9 000) + ≤ 240 brightness round-trips
in the last 60 t — a ~4× reduction while ADDING tumble + dissolve. Spin ceiling
1.6°/t = 6.4°/window and terminal fall 1.4 blocks/window both sit far inside the
VFXPOLISH-3 linear-tween comfort zone at the 4 t cadence. Cap 120 and TTL 300 frozen.

---

## 3. INTRO / OTHER DISPLAYS — `sequence/FloatingDecor.java` (+ limbo verification)

**PLAN.** `FloatingDecor` (the R10 reveal rubble) already runs the correct transport:
4 t cadence == duration, poses absolute functions of game time, keyframes target
`gameTime + cadence` (the lead law), fixed per-index tumble axes, deterministic hash —
no teleports anywhere. `StartEventCutscene` owns no displays (it drives the Deckhand
tilt flag); `OarAnimator` is cleanup/migration-only since P6-W2 (discard-only display
code — the sweep doctrine source). Verification result: CLEAN; one craft upgrade
applies (tumble-pole precession, the system-2 law).

**IDEATE.**
1. Slow pole precession around Y per fragment (period 80–120 s, phase-hashed): long
   reveal shots stop reading the rubble as mechanically pinned. ✔ (salts 15/16 —
   deterministic, ensure/reconcile rebuilds the identical cloud)
2. Keyframe lead: verified already present (`poseAt(i, gameTime + 4)`) — no change. ✔
3. Bob window law: verified — worst case 4 t / 80 t = 18° per window, safe. ✔
4. Brightness ramp on decor: rejected — the rip cloud hangs between a lit crater and
   the island underside; ambient sampling at the anchors is the truthful read, and
   idle-loop NBT round-trips every reconcile would be pure cost.
5. Scale breathing (orbitals' W-P-ALTAR2 read): rejected — decor sells torn mass, not
   held-by-magic; breathing rubble reads alive and fights the sanctum ring's signature.
6. Bob-phase coupling to precession (nutation read): rejected — two visible periods per
   fragment turns 28 fragments into visual noise; one slow secondary motion is the cap.
7. Re-order spawn indices center-out (system-1 law): rejected — the cloud spawns as one
   ensure() batch mid-cinematic with no stagger to order; golden-angle placement
   already avoids clumping.

**IMPLEMENT.** `poseAt` rotates the (still fixed) normalized axis by
`rotateY(2π/(1600 + 800·hash01(i,15))·t + hash01(i,16)·2π)` before building the
quaternion; class doc updated (animation paragraph + method javadoc).

**POLISH 2 (correctness).** Precession preserves axis length (pure Y-rotation of a
normalized vector — `rotationAxis` stays valid); pose remains an absolute function of
game time (stateless pushes, restart/adopt-safe); determinism holds (new salts only).
`StartEventCutscene`/`OarAnimator` audited: zero display animation surfaces — logged
as verified, untouched.

**POLISH 3 (budget + tuning).** Zero packet delta (same pushes, same cadence). Pole
movement ≤ ~0.45°/window — an order of magnitude inside the tween threshold. Periods
straddle 80–120 s so no two fragments' poles sync within a session.

---

## 4. DEVTOOLS PLACER — `DisplayPlacerService.java` / `DisplayAnimator` (+ orbitals rebuild)

**PLAN.** The reference animator everyone cites had two craft violations of its own:
`applyAnimation` computed the pose at the CURRENT game time (client trails one 2 t
interval — the exact anti-pattern the flight fx copied), and the command floor allows
0.1 s bob periods that alias to mush at the 2 t window (720°/window). Plus the
`/dev display orbitals_rebuild` seam: `SanctumOrbitals.rebuild` respawned the ring but
left it FROZEN until the next 40 t cadence boundary (an up-to-2 s hitch right where an
operator is staring).

**IDEATE.**
1. Keyframe lead in `applyAnimation`: pose at `gameTime + TICK_INTERVAL`. ✔
2. Present sub-0.4 s bob periods AS 0.4 s inside `applyAnimation` only (VFXPOLISH-3:
   ≥ 8 t period keeps ≤ 90°/window at 2 t cadence); SavedData/commands keep the raw
   value so `/dev display param` stays lossless. ✔
3. `rebuild()` pushes one interpolated keyframe immediately after the force-reconcile —
   the ring glides the same tick; the next boundary push retargets mid-tween (delay 0
   restarts from the currently rendered pose — no snap). ✔
4. Tighten the command's period floatArg floor to 0.4: rejected — changes a frozen dev
   command surface and silently invalidates persisted entries; presentation clamp wins.
5. Respawned-display interpolated "grow-in" (scale 0→1) on rebuild: rejected — dev tool,
   not a show; the glide fix already removes the jarring part.
6. Per-entry update cadence override (fast displays get 1 t): rejected — the 2 t
   animator interval is a frozen shared budget; a lead-corrected 2 t tween is already
   sub-perceptual at ≤ 360°/s.
7. Glow ramp via brightness on `glow on`: rejected — `glow` is the vanilla outline flag
   (a debugging aid), not a lighting effect; conflating them breaks operator intuition.

**IMPLEMENT.** Both `applyAnimation` fixes (lead + presentation clamp, commented with
the law names); `SanctumOrbitals.rebuild` now calls `animate(overworld, altarPos,
gameTime)` right after `reconcile(force=true)`.

**POLISH 2 (correctness).** Lead shift is a pure phase offset of an absolute-time pose —
no discontinuity at takeover, existing worlds' displays glide seamlessly on next tick.
Clamp only widens periods (never shrinks user intent into aliasing); `bobPeriodSec`
persistence unchanged. Rebuild's immediate animate targets `gameTime + 40` with
duration 40 — if the dev command lands ON a cadence boundary the tick-loop push is a
same-value no-op (SynchedEntityData equality). `DevDisplayCommands` itself needed no
change — verified seam-only.

**POLISH 3 (budget + tuning).** Zero steady-state packet delta; rebuild adds exactly
one push per orbital display, once, on operator command. Doc law reaffirmed for future
cluster teams: DisplayPlacerService is the citable reference implementation again
(lead-corrected), matching SanctumOrbitals/FloatingDecor.

---

## Self-check matrix

| Files | Check | Result |
| --- | --- | --- |
| `DisplayBrightnessFx` (new), `StructureFlightFx`, `EndShatterSequence`, `FloatingDecor`, `DisplayPlacerService`, `DisplayAnimator`, `SanctumOrbitals`, `DevDisplayCommands` (unchanged, compile-guarded) | `javac` release 21, moddev merged-jar + legacy classpath + `build/classes/java/main` | OK |
| `StartEventCutscene`, `OarAnimator` | audit only — no display animation surfaces | verified clean |
