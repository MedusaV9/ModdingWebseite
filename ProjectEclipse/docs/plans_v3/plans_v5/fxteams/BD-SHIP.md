# FX Team — BD-SHIP (block-display animation pass, W-P-BDSHIP1)

Team process per system: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `ferryman/ArenaFight.java` (transform-beat morph displays),
`ferryman/ArenaBuilder.java` (arena display accents), `ritual/CreditsSequence.java`
(helm wheel + debris flyers), `worldgen/structure/SkyLauncher.java` (pad visual
pieces), `ferryman/AltarDoor.java` (dead-door materialization), plus a display-usage
audit of `worldgen/nether/BreachBuilder.java` / `network/breach/BreachClientFx.java`.

Hard rules this round: transformation interpolation (duration + start delay) instead
of per-tick teleports wherever a display currently moves; ship-transform pieces ARC on
eased paths and ROLL into place with a 1.05 overshoot; spiral patterns get golden-angle
(137.5077°) phase offsets; the credits wheel turns continuously with rate noise plus a
spoke-light glint via brightness ramp; flyers get staggered ballistic arcs with tumble
damping; the altar dead door materializes as a rising assembly (float up + snap)
instead of an instant stamp. All existing command tags, sweep patterns and packet/push
budgets stay. Ownership seams: CUT-CREDITS owns `client/credits/*` and the credits
PHASE TIMINGS (untouched — we only add display-motion internals inside existing
overlap windows); CUT-END owns the `ArenaFight` beat TIMING (`TRANSFORM_TICKS`,
`WHITEOUT_TICK`, shake cadence — all untouched; only the morph pose math changed).
Self-checks: `javac --release 21` against the moddev merged jar (+ veil / geckolib /
voicechat-api); no gradle, no git.

Shared craft laws applied throughout (SanctumOrbitals/OarAnimator precedent):
- **Stateless pushes** — every pose is an absolute function of a tick clock, so
  re-pushes always agree and a paused display glides (never snaps) back on track.
- **VFXPOLISH-3 window law** — no interpolation window may cover more than ~90° of
  rotation (linear-flattening threshold); keyframe spacing chosen accordingly.
- **Center-pivot law** — `translation = offset − R·(s/2)` so scaled/rotated blocks
  pivot around their own center (the credits-wheel math, reused everywhere).

---

## System 0 — breach display audit (`BreachBuilder`, `BreachClientFx`)

### PLAN
The cluster brief says "worldgen/nether breach displays if any — check for display
usage". Audit both files (and the rest of `worldgen/nether/`) for
`Display`/`BLOCK_DISPLAY` code paths before planning work.

### FINDING (no ideation needed)
Zero display-entity usage: `BreachBuilder` is a budgeted block writer plus REAL
visual-only lightning + server particles; `BreachClientFx` consumes phase payloads
into camera shake, quasar emitters and the transition glitch. Nothing teleports a
display, nothing to convert. **No changes** — the breach stays out of this round.

---

## System 1 — `ArenaFight.java` (transform-beat morph displays)

### PLAN
The C10 transformation beat lifts ~40 deck-plank/mast block displays with ONE linear
interpolation push each (CUT-END's pass added per-piece staggered launch ticks — deck
0–8t, masts 6–16t — but each piece still gets a single linear window to the arrive
tick). One linear window means: no arc, no easing, and the ±2.75π corkscrew inside a
single window was quaternion-slerp-flattened to ≤135° on the client (one window can
only ever show the shortest arc — the spin read as a slow constant drift). Brief:
pieces should ARC on eased paths, ROLL into place with a 1.05 overshoot, and the
ensemble's spiral should carry golden-angle phase offsets. CUT-END's beat TIMING is
frozen (60t total, whiteout at 25, per-piece launch staggering, escalating shakes),
as are `MORPH_TAG`, the UUID list, both sweeps and the spawn lattice.

### IDEATE
1. **Keyframe transport** — interpolated pushes every 8t from t=2 through the arrive
   tick (t=50), plus a settle window running to t=58, sampling an eased trajectory;
   piecewise-linear segments between eased waypoints approximate the curve, and every
   window stays under ~90° of rotation. Progress is normalized PER PIECE from its
   CUT-END launch tick (staggering preserved); pieces still pre-launch re-push their
   identity pose — equal synched values never dirty, so held pieces cost no packets.
   7 × ~40 pieces ≈ 280 pushes across 60t — trivial next to the shake payloads.
   **CHOSEN**
2. **Arc shape from split easing** — outward drift eases OUT (fast early) while rise
   eases IN-OUT (slow-fast-slow): the path bows outward low, then climbs — a genuine
   arc without any per-tick position sets. **CHOSEN**
3. **Roll into place** — each DECK piece rolls a half turn (π; planks are symmetric,
   so "one flip" lands looking seated) about its horizontal tangent axis
   (`up × radial`), eased in-out; the window ending at t=50 targets 1.05× (rise,
   drift AND roll 5% past), the settle window relaxes back to exactly 1.0 — the
   overshoot-and-settle read. Masts don't roll — they keep their corkscrew as pure
   yaw (a rolling mast column reads as broken, not dramatic). **CHOSEN**
4. **Golden-angle spiral** — per-piece azimuth swirl `wrap(i·137.5077°)·0.4·ease(s)`
   rotates each drift vector around the ship axis, and the same golden term seeds the
   deck yaw target: the rising ensemble forms a phyllotaxis spiral instead of hash
   noise (hash01 keeps carrying per-piece magnitudes and CUT-END's launch staggering —
   rise/drift ranges stay as shipped). **CHOSEN**
5. **Full-magnitude corkscrew (±2.75π)** — rejected: even across 8t keyframes the
   hardest mast window would cover ~180° of yaw, straight through the flattening
   threshold; ±1.2π eased in-out is the same visible energy actually rendered
   (worst window ≈78°).
6. **Per-tick pose sets for the arc** — rejected: exactly the anti-pattern this round
   exists to remove (60 pushes/piece/beat, and client-side motion would stutter at
   20Hz instead of tweening).
7. **Scale swell during flight** — rejected: the pieces mirror REAL ship blocks
   underneath; growing them breaks the "the deck itself lifts" illusion.
8. **Spiral formation re-sort (pieces fly to sorted golden slots)** — rejected: pieces
   crossing each other's paths reads as chaos from deck level; each piece keeps its
   own radial lane.

### IMPLEMENT
- `MORPH_LAUNCH_TICK 2` / `MORPH_KEY_SPACING 8` / `MORPH_ARRIVE_TICK 50` /
  `MORPH_SETTLE_TICK TRANSFORM_TICKS−2`; `tickTransform` fires
  `pushMorphKeyframe(limbo, t)` every 8t (window = distance to the next key, the
  push at t=50 runs the settle window to t=58).
- `pushMorphKeyframe`: per piece, recompute CUT-END's launch tick from the same hash,
  normalize `s = (windowEnd − launch) / (MORPH_ARRIVE_TICK − launch)` (clamped);
  the window that reaches t=50 carries overshoot 1.05, pushes at/after t=50 settle
  at s=1 / overshoot 1.
- `morphPose(display, index, mast, h, s, overshoot)`: golden swirl of the radial
  drift vector (deck only), ease-out drift + ease-in-out rise (both ×overshoot);
  deck yaw = (golden·0.35 + hash·±0.35π)·easeOut(s) with roll = π·easeInOut(s)
  ·overshoot about the horizontal tangent axis; mast yaw = ±1.2π·easeInOut(s)
  (alternating sign per mast, no roll).
- `easeInOut` (smoothstep) + `easeOut` helpers; `hash01` untouched; spawn pose,
  `MORPH_TAG`, sweeps, whiteout/shake beats and CUT-END's timing all byte-identical.

### POLISH 2
- Rotation-window audit: the initial draft eased mast yaw with ease-OUT, whose
  initial slope (×2) busted the ~90° law on the hardest-hashed mast (±1.2π, late
  launch → short span); switched masts to ease-IN-OUT — worst window now ≈78° of
  yaw (masts) / roll+yaw composite ≈75° (deck), both under the law.
- Degenerate-radial guard kept (`lengthSqr > 1e-4`), now ALSO used as the roll-axis
  fallback (+X) so center-line pieces still roll instead of throwing NaNs into the
  quaternion.

### POLISH 3
- Verified a piece killed mid-beat just skips its remaining keyframes (same
  `instanceof` guard as the old single push) and the sweep still catches it by tag.
- Confirmed pieces are back at EXACT formation pose (overshoot fully settled) by
  t=58 < `TRANSFORM_TICKS`, so the final frame before the arena transport is clean —
  and the class javadoc's "one interpolated pose push" line updated to "keyframed
  interpolated pose pushes" (doc-only; the C7-transport doctrine reference stays).

---

## System 2 — `ArenaBuilder.java` (arena display accents)

### PLAN
The arena is a pure block stamp — the "ship remembered at its true size" has no
moving memory. Brief: presentation-only display accents that live with the FIGHT
(spawned when the crossing completes, animated on the existing fight-watch stride,
discarded when the fight ends), never persisted decor. Accent code lives in
`ArenaBuilder` (the arena's builder owns its dressing); `ArenaFight` only calls
spawn/animate/sweep from the existing lifecycle seams.

### IDEATE
1. **Ghost helm wheel** — one dark-oak-trapdoor block display (the credits-wheel
   prop, scale 2.6) hovering over the stern rise behind the Ferryman's anchor,
   turning with the same continuous-rotation-plus-rate-noise craft as the credits
   wheel: the remembered ship still steers itself through the fight. **CHOSEN**
2. **Witness lanterns** — four soul-lantern displays hovering above the four pillar
   crowns, bobbing and slowly yawing with golden-angle phase offsets per pillar
   (never in lockstep — the crew that watches). **CHOSEN**
3. **Fight-watch transport** — `tickFightWatch` already strides every 20t: each
   stride pushes one interpolated 20t window per accent (SanctumOrbitals cadence
   law) → continuous motion, 5 displays × 1 push/s while the fight runs, zero
   otherwise. **CHOSEN**
4. **Lifecycle** — `spawnAccentDisplays` (sweep-then-spawn, returns UUIDs in fixed
   index order), `animateAccentDisplays(arena, uuids)`, `sweepAccentDisplays`;
   ArenaFight spawns at `finishTransform` + the fight-resume restart path, animates
   in the watch, sweeps at `endFight` and belt-and-braces at both gate arms.
   **CHOSEN**
5. **Ghost sails (scaled wool/banner displays on the pillar "masts")** — rejected:
   banners are BE-rendered (invisible in block displays) and big wool sheets occlude
   the fight's sweep/slam telegraphs — readability beats set dressing.
6. **Persistent accents stamped by `ensureBuilt`** — rejected: `ensureBuilt` is
   version-gated (runs once ever); persisted decor needs join-time stray sweeps and
   pays entity cost forever in a dimension nobody visits between fights.
7. **Spectator-ship accents** — rejected: default display view range won't reliably
   carry 80 blocks to spectators anyway; the fighters are the audience.
8. **Wheel spin rate keyed to boss phase** — rejected: cross-class coupling into
   `FerrymanEntity` phase state for a subliminal tell; also boss internals belong to
   the boss team.

### IMPLEMENT
- `ACCENT_TAG "eclipse_arena_accent"`, `GOLDEN_ANGLE`, wheel/lantern constants;
  `spawnAccentDisplays` (index 0 = wheel at stern x=−17, pit+7; 1..4 = lanterns at
  `PILLARS[i]`, crown+2.4), `accentPose(index, gameTime)` (wheel: 0.5°/t + two
  incommensurate sine noise terms — 4°@90t and 2.5°@217t, ~17°/window worst case;
  lanterns: ±0.35 bob + 0.2°/t yaw, golden phase per index), `animateAccentDisplays`
  (delay 0, duration 20, pose at `gameTime + 20`), `sweepAccentDisplays` (tag sweep
  over the arena box).
- `ArenaFight`: `accentDisplays` UUID list beside `morphDisplays`; spawn at
  `finishTransform` and the restart fight-resume; animate inside `tickFightWatch`
  after the arena null-check; sweep+clear in `endFight`, both gate arms, and
  `onServerStopping`.

### POLISH 2
- Wheel pose reuses the credits center-pivot math but anchors the pivot at the
  entity position (translation = −R·(s/2) + upright offset) so the big 2.6-scale
  trapdoor spins on its hub, not its corner.
- Lantern bob period de-tuned per index (90 + 14·i ticks) on TOP of the golden phase
  so two lanterns can never phase-lock even after long fights.

### POLISH 3
- Confirmed `animateAccentDisplays` tolerates missing/killed accents (skip, no
  respawn mid-fight — the sweep on the next spawn reconciles) and that `endFight`
  sweeps by TAG (not the UUID list), so even displays orphaned by a mid-fight
  `/kill` + restart never leak.
- Join-time stray guard (`ArenaFight.onEntityJoin`, StructureFlightFx doctrine): a
  tagged accent loading in that THIS session did not spawn is a crash leftover or an
  async chunk load racing the resume respawn — discarded on join. `spawnAccent` adds
  the UUID to the live list BEFORE `addFreshEntity` so the guard never eats its own
  fresh spawn.
- Verified the watch's victory/abandon early-returns can at worst waste one 20t push
  on the tick the fight ends — the sweep in `endFight` runs the same tick, harmless.

---

## System 3 — `CreditsSequence.java` (wheel + flyers motion quality)

### PLAN
The helm wheel is a STATIC prop (one 45° pose) for the entire 140t push-in — the
single most-watched display of the finale never moves. The 24 debris flyers all
launch at the same instant and tumble at constant rate (steady spin reads as
weightless CGI). Brief: wheel = gentle continuous rotation with rate noise (living
feel) + spoke-light glint via brightness ramp; flyers = staggered ballistic arcs
with tumble damping. CUT-CREDITS owns the phase timings — every beat constant,
payload, and the 2t flyer cadence stay; we only add motion internals inside the
existing overlap section.

### IDEATE
1. **Wheel rotation with rate noise** — angle(t) = 0.85°/t · t + 6.5°·sin(2πt/46) +
   4°·sin(2πt/117 + 2.1): two incommensurate sine terms modulate the rate so the
   wheel drifts, hesitates, and pulls like a helm riding a swell — never a metronome.
   Absolute function of the run clock (stateless pushes). 4t windows (~5–11° each,
   noise + grip envelope at worst), one entity — 5 pushes/s. **CHOSEN**
2. **Spoke-light glint via brightness ramp** — the trapdoor "wheel caught mid-turn"
   reads as 4-spoked; every 50t (≈ one 45° spoke crossing at the base rate) a 14t
   `sin(π·x)` brightness-override ramp (block+sky rising 6→15 and back, then
   override CLEARED to natural light) sweeps across — moonlight catching a spoke.
   `Display#setBrightnessOverride` is private, but no accesstransformer is needed:
   round-trip the entity through its own save NBT with a `brightness` compound (the
   vanilla data path — `Display.load` sets the override from the tag, and RESETS it
   when the tag is absent, which is the clear). Nothing reflective, nothing
   version-fragile beyond the tag name. **CHOSEN**
3. **Flyer stagger** — per-flyer launch delay `hash01(i,14)·0.3` of the flight span,
   normalized so every arc still completes by `T_FLYERS_END` (late starters fly
   faster arcs); replaces the old `speedJitter` clip-at-1 trick. **CHOSEN**
4. **Tumble damping** — spin angle = total·(p − 0.325p²)/0.675: tumble rate decays
   to ~35% by landing — debris stabilizing as it falls, not a pinwheel. Total spin
   magnitude unchanged (still 2π–6π), so per-window deltas stay ≤ ~8°. **CHOSEN**
5. **Golden-angle tumble phases** — flyer i's spin phase = i·137.5077° (replaces
   `hash01(i,8)·2π`): neighboring flyers are maximally de-phased by construction, so
   no two adjacent arcs ever tumble in sync. **CHOSEN**
6. **Scale envelope at the arc ends** — flyers ease from 2% → full scale over the
   first 12% of their (staggered) flight and back down over the last 12%: pre-launch
   holds are invisible (staggered pieces no longer sit visibly at the below-beach
   west end), and the `T_FLYERS_END` discard no longer pops 24 blocks out of the sky
   mid-air. **CHOSEN**
7. **Wheel counter-rotation kick at the lightning beat** — rejected: the wheel is
   discarded at `T_EPILOGUE` (t=260), the lightning starts at t=420 — it's never
   on stage; and cross-beat coupling is CUT-CREDITS' lane.
8. **Glint via glow-color override** — rejected: the glowing outline is a gameplay
   affordance (team/target marking) and reads as UI, not light; also equally private
   API for a worse look.
9. **Per-flyer Z-drift (S-curved arcs)** — rejected: arcs must stay parallel to the
   auto-run camera axis or they read as targeting the runners; the brief says
   ballistic, not homing.

### IMPLEMENT
- Overlap hook (`onServerTick`): `if (t > T_SHIP && t < T_EPILOGUE && (t − T_SHIP)
  % 4 == 0) animateWheel(current, t)` — inside the existing overlapping-work block,
  no beat constant touched.
- `animateWheel`: 4t interpolation window, pose = `wheelPose(wheelAngle(t + 4))`
  (lookahead like the flyer pattern); `wheelPose` keeps the exact spawn math
  (upright ZY, center pivot, 1.1 scale) with `wheelAngle` (base rate + two noise
  sines + `gripOffset`) replacing the fixed 45°; `applyWheelGlint` drives the ramp
  through `applyBrightnessOverride(wheel, b, b)` / `clearBrightnessOverride(wheel)`
  — NBT save-data round trips, no accesstransformer (`clearBrightnessOverride` is
  new; `applyBrightnessOverride` is CUT-CREDITS' existing flyer-dimming helper).
- CUT-CREDITS' hands-settle beat (`nudgeWheel` pushes) is now `gripOffset(t)`: the
  same pull-back/relax magnitudes ride the continuous rotation as a deterministic
  angle envelope — `WHEEL_SETTLE_AT` / `WHEEL_RELAX_AT` / `WHEEL_REST_SPIN_DEGREES`
  (CUT-CREDITS' timing constants) still rule; only the transport changed.
- Flyers: `flyerPose(index, progress)` now derives `p` from the staggered
  normalization (`staggeredProgress`), golden tumble phase, damped spin
  (`dampedTumble`) and the scale envelope (`scaleEnvelope`); `shadowPose` mirrors
  all three so the low-arc shadow pucks stay under their flyers;
  spawn/launch/2t-cadence/`T_FLYERS_END` discard, `FLYER_TAG`, `LIVE_DISPLAYS` and
  the join-time stray sweep all unchanged.

### POLISH 2
- Wheel glint tied to the run clock, not `angle mod 45°`: the noise terms make true
  spoke-crossing detection wobble around the trigger (double-blinks); a fixed 50t
  cycle at the mean crossing rate reads identically and is branch-free.
- Flyer scale floor 0.02 (never exactly 0): a zero scale column degenerates the
  affine decomposition on the client interpolator.

### POLISH 3
- Confirmed `animateWheel` guards `wheel == null || isRemoved` (helm-skip path nulls
  the wheel via `discardWheel` before t reaches the window's end) and that the glint
  clears the override rather than leaving a stale bright frame on discard.
- Verified FX-only replays are untouched: replays never spawn wheel/flyers, so no
  replay path can reach the new motion code (R12 contract intact).

---

## System 4 — `AltarDoor.java` (dead-door materialization)

### PLAN
The dead door currently STAMPS instantly (15 blocks + BE in one tick) with a veil
puff — the finale's most ominous prop just pops. Brief: rising assembly — pieces
float up from the dais and snap into the aperture, THEN the real multiblock stamps.
Constraints: `ArenaState` door record + walk volume + removal cascade + the C10.5
restart law stay intact; a crash mid-assembly must never leave a recorded door
without blocks or stray displays.

### IDEATE
1. **Deferred stamp behind a display assembly** — `place()` records the door in
   `ArenaState` FIRST (restart law anchor), spawns 15 tagged block-display pieces
   (one per aperture cell) in a ground-scattered pose, and arms a 36t transient
   assembly; the REAL controller+fillers stamp fires at t=36 in the driver. The
   walk-through volume is armed the whole time (crossing a still-forming door is
   fine — the gate beat owns crossings, not the blocks). **CHOSEN**
2. **Stagger via interpolation start delay** — one rise push per piece at t=1 with
   `setTransformationInterpolationDelay(goldenStagger(i))` (0–8t, golden-sequence
   ordering so the aperture fills in a pleasing non-row scatter) + 18t duration:
   float-up needs exactly ONE push per piece, the delay does the choreography.
   **CHOSEN**
3. **Unison snap** — at t=28 every piece gets one 6t push to its exact cell pose
   (identity transform by the center-pivot construction: entity sits at the cell
   corner) + ONE deepslate place-sound and a brightness-override flash (14/14) —
   fifteen stones locking as one beat. **CHOSEN**
4. **Restart repair seam** — `ensureStamped(server)`: if a door is recorded but the
   controller block is missing (crash inside the 36t window), sweep stray pieces and
   stamp instantly — "a restart never resumes mid-assembly", the exact C10.5 mirror.
   Called from ArenaFight's existing door-re-arm restart branch; `remove()` and
   `onServerStopping` cancel the transient assembly. **CHOSEN**
5. **Piece palette** — the run's grave-stone memory: polished blackstone bricks /
   deepslate tiles / bone block, hashed per cell (the credits FLYER_PALETTE's "altar
   stone" family, not the door's own look — the GeckoLib door model replaces them at
   stamp time, so the pieces must read as raw material, not a fake door). **CHOSEN**
6. **Drive the assembly from ArenaFight's gate tick** — `AltarDoor.tickAssembly`
   called from `tickGate` (the door only ever assembles inside the GATE stage; if the
   gate drops, `remove()` cancels the assembly with it) — no new event subscriber for
   a 36t one-shot. **CHOSEN**
7. **Animate the actual door model rising** — rejected: the multiblock renders via
   the GeckoLib BE (blocks are `RenderShape.INVISIBLE`); moving the REAL blocks means
   moving the BE, and CUT owns nothing here — the door model is `limbo/door` team
   surface. Displays around/before it are the only clean seam.
8. **Assembly as pure overlay on an instant stamp** — rejected: the GeckoLib door is
   fully visible at t=0 underneath, so "pieces assembling INTO an already-standing
   door" reads backwards. The 1.8s deferred stamp is the honest version, and the
   repair seam (idea 4) closes its crash window completely.
9. **Persist assembly progress in ArenaState** — rejected: 36 ticks of transient
   choreography does not deserve persisted state; the restart law already says
   "skip to the end state", which `ensureStamped` implements for free.

### IMPLEMENT
- `ASSEMBLY_TAG "eclipse_altar_door_rise"`, tick table (rise push t=1, snap t=28,
  stamp t=36), palette, golden stagger; transient `Assembly` record (level dim +
  controller + facing + start game time + piece UUIDs), server-thread only.
- `place()` split: record + sweep + spawn pieces + arm assembly (veil +
  END_PORTAL_SPAWN stay at t=0 as the "materialize begins" cue);
  `stampBlocks(...)` extracted (controller + fillers + BE OPEN + the WOODEN_DOOR_OPEN
  sound, which MOVED from t=0 to the stamp — the door should creak when it exists);
  `tickAssembly(server)` drives rise/snap/stamp; `ensureStamped(server)` +
  `cancelAssembly()` + `sweepAssemblyPieces(...)` close every abnormal path.
- `ArenaFight`: `tickGate` head calls `AltarDoor.tickAssembly(server)`; the restart
  door-re-arm branch calls `AltarDoor.ensureStamped(server)`; `onServerStopping`
  calls `AltarDoor.cancelAssembly()`.

### POLISH 2
- Rise target hovers 0.25 blocks SHY of the cell at 92% scale with an 8° residual
  tilt — the snap push then has real work (alignment + last quarter block + scale)
  so it reads as a SNAP, not a stop.
- Stagger capped at 8t with an 18t rise so the LAST piece finishes rising (t=27)
  before the unison snap push (t=28) — no piece gets its float-up truncated.

### POLISH 3
- Re-arm path audited: `place()` → `remove()` of a previous door cancels its
  assembly BEFORE the new record overwrites it (never two assemblies, mirroring the
  "never two doors" law); `remove()` sweeps by tag around the recorded controller so
  even UUID-list drift can't leak a piece.
- Crash matrix: crash before t=36 → boot: door recorded, controller missing →
  `ensureStamped` stamps + sweeps; normal stop mid-assembly → `cancelAssembly`
  discards pre-save; crash AFTER stamp → controller present → sweep-only. Ghost
  clients: pieces are plain displays (no ghost-visibility rule involvement — the
  door's own ghost rule starts working when the real blocks stamp).
- Async-load seam closed: persisted crash-leftover pieces can stream in AFTER
  `ensureStamped`'s boot sweep ran over a not-yet-loaded chunk — the
  `ArenaFight.onEntityJoin` guard discards any `ASSEMBLY_TAG` joiner that is not a
  CURRENT assembly piece (`AltarDoor.isLivePiece`); `spawnAssemblyPieces` registers
  each UUID in the assembly BEFORE `addFreshEntity` so the guard never eats a live
  spawn.

---

## System 5 — `SkyLauncher.java` (pad visual pieces)

### PLAN
The wind altar's visual pieces are the interaction entities (functional, self-healed
— untouched) plus particles; there are no displays at all, and the charge-up spiral
is a single END_ROD arm. Brief: give the pad a display accent worth the "wind altar"
name and apply the golden-angle spiral law to the charge-up.

### IDEATE
1. **Wind shard** — ONE amethyst-block display (scale 0.38) hovering above the spire
   cluster, slowly yawing (1.4°/t) with a fixed 12° tilt and a 160t sine bob; poses
   are absolute functions of game time, pushed as 20t windows from the EXISTING
   `ambientTick` stride (only while the pad chunk is loaded — same gate as the
   particles). One display, 1 push/s, zero new tick paths. **CHOSEN**
2. **Charge spin-up** — while a charge runs, the shard gets 3t-window pushes (on the
   existing every-3rd-tick chime stride) adding an eased extra yaw of 60°·progress²
   on top of the ambient absolute clock: the shard whips up with the chimes, and
   after launch the ambient driver's boost-free clock pulls it back over one 20t
   window — the "recoil settle" is free (SanctumOrbitals stateless-push law).
   **CHOSEN**
3. **Golden-angle charge spiral** — the charge-up END_ROD spiral becomes three arms
   phase-offset by 137.5077° each (same 3 particles/tick budget: 3×1 instead of
   1×3), so the column reads as a living triple helix instead of one dotted line.
   **CHOSEN**
4. **Sweep + self-heal integration** — the shard rides the EXISTING patterns: its tag
   joins `sweepPadEntities` (placement sweeps stay one predicate) and the 200t
   interaction self-heal also respawns a missing shard (a `/kill`ed accent heals like
   a `/kill`ed interaction). **CHOSEN**
5. **Return-pad shard** — rejected: the return pad is a utility ring on the disc rim;
   doubling persistent entities + ambient pushes for a pad players use once per trip
   fails the budget-for-value test. (The launch pad is the authored hero.)
6. **Orbiting shard ring (3–4 displays)** — rejected: the pad already has four
   chain-pylon soul lanterns as satellites; a ring of floating blocks over an 8×8 pad
   crowds the launch sightline players aim through.
7. **Launch "shatter" burst (shard splits into micro-displays)** — rejected:
   spawn/discard churn per launch for a 10-tick moment; the existing CLOUD/END_ROD
   burst + shake already owns that beat.
8. **Interaction-entity resize pulse during charge** — rejected: interaction extents
   are GAMEPLAY surface (click targets); animating hitboxes for looks is exactly the
   kind of form-over-function this team must not do.

### IMPLEMENT
- `SHARD_TAG "eclipse_sky_launcher_shard"`, `GOLDEN_ANGLE`, shard constants;
  `spawnWindShard` (placement + self-heal), `shardPose(gameTime, chargeBoost)`
  (center-pivot, tilt→yaw composition), ambient 20t pushes in `ambientAt` (launch pad
  only), charge-stride 3t pushes in `tickCharges`, triple-arm golden spiral in the
  same loop; `sweepPadEntities` predicate + self-heal extended.

### POLISH 2
- Ambient shard query rides the same small AABB as the self-heal but every 20t; kept
  cheap by inflating only (2, 6, 2) around the recorded pad anchor — no arena-sized
  scans (the pad anchor is exact, unlike the arena accents).
- Charge boost capped so the fastest 3t window stays ≤ ~25° (window law) even at
  progress 1.

### POLISH 3
- Verified the shard persists across restarts and the ambient driver's absolute
  game-time clock makes it glide back on track (no snap) on the first push after
  boot; `/kill` matrix: shard gone → 200t self-heal respawns it born mid-pose.
- Confirmed `placeReturnPad` spawns no shard and its sweep (shared predicate) stays
  a no-op for the new tag there.

---

## Validation (this round)

- `javac --release 21 -proc:none` over the five touched Java files with
  `-sourcepath src/main/java` against `build/moddev/artifacts/neoforge-21.1.238-merged.jar`
  + `clientLegacyClasspath.txt` + Veil 4.3.0 + Geckolib 4.9.2 + voicechat-api 2.6.20:
  **exit 0, zero errors** (the only javac notes are the repo-wide pre-existing
  deprecation notes, unchanged from the baseline compile of the same files).
- No accesstransformer change was needed after all: both brightness effects (credits
  glint + door snap flash) go through the entity's own save-NBT round trip (the
  vanilla `Display` data path), so the merged jar is compiled against as-is.
- No gradle, no git, no wire-format changes, no beat-timing changes, no gameplay
  changes; every new display carries a command tag covered by a sweep, and every
  push budget is ≤ the SanctumOrbitals cadence law.
