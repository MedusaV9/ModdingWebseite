# IDEA-14 — Map Expansion Spectacle (Eclipse Event, collector 14/20)

Focus: `sequence/ExpansionSequence` (SKYWARD / FLYOVER / GROWTH / STRUCTURES / END), growth-wave
FX, structure rift-slams, reveal-delay. Read-only survey; no code changes.

**Context absorbed from EVAL-4** (`docs/plans_v3/eval/EVAL-4_vfx_sequences.md`): the flyover
"static aerial hold" quick-win parameters are ALREADY applied in
`assets/eclipse/cutscenes/expansion_flyover.json` (220 ticks, lowered y keyframes, spread
lookAts, shake events at t 0.25/0.5), and the anchor-lead projection from quick win #1 is
implemented in `ExpansionSequence.resolveGrowthFront` (the `lead` term). The C1 ACK-reorder and
M6 static-anchor caveats still apply to anything that depends on the gather actually holding.
Everything below is therefore additive spectacle, not pacing repair. All client spawns must go
through `FxBudget` (`SEQUENCE` bursts ≤ 60/s for ≤ 3 s — really 2 s until EVAL-4 M3 is fixed;
`AMBIENT` ≤ 12/window, off at tier 0) via `QuasarSpawner.spawn(id, pos, channel)`.

Sizes: **S** = one file / < ~60 lines or one JSON asset. **M** = 2–3 files, new asset or small
protocol addition, replay-parity work included.

---

## Ranked ideas

### 1. Wavefront ground-shake ripples under feet (S)
The growth rumble is dimension-wide and flat: `RingGrowthService.Job.maybeEmitWavePulse`
sends `S2CShakePayload.shake(0.35F, 15)` to everyone every `growth.shakeEveryRings` (25) rings,
whether the front is 8 or 800 blocks away. Make the wave *arrive*:
- **Server** (`RingGrowthService.maybeEmitWavePulse`): replace
  `PacketDistributor.sendToPlayersInDimension(...)` with a per-player loop scaling strength by
  radial distance to the front: `strength = Mth.lerp(Mth.clamp(1 - |playerR - waveRing| / 128, 0, 1), 0.08F, 0.5F)`
  (playerR = `sqrt(x²+z²)`). Keep the `fusionOrdered` suppression as-is.
- **Client** (`ExpansionSequence.ClientHooks.handleWavePulse`): the front is monotonic outward, so
  latch a per-sweep `frontCrossedPlayer` boolean (reset on `pulseIndex == 0`); the first pulse
  where `payload.waveR() >= playerR` fires the underfoot beat: `EclipseFxState.startShockwave(feetSurfacePos, 0.25F, 18)`
  (rides the existing `eclipse:shockwave` post pass — zero new assets) plus one `growth_dust_wall`
  spawn at the feet (SEQUENCE channel). Keep the existing intro-fusion guard
  (`fromStage == 0` overworld pulses are skipped).
- Payoff: players feel the wave *pass through them* instead of a generic global rumble.

### 2. Structure slam crater dust rings + delayed debris rain (M)
`ExpansionSequence.slamFx` today: one center `structure_slam_dust` burst, corner bursts only for
footprint ≥ 64, `fx/shockwave (0.5, 30)`, `event.rift_slam`, shake 0.4. Upgrade to a three-beat
crater read using the class's own `schedule(server, ticks, action)` helper:
- **Expanding dust rings** (replaces the 4-corner special case): t+0 center burst as now; t+6 a
  ring of 6 `S2CQuasarPayload(STRUCTURE_SLAM_DUST, …)` spawns on a circle of radius
  `footprint * 0.35`; t+12 a second ring of 6 at `footprint * 0.6` (positions =
  `slamPos.add(cos/sin(k·60°)·r)`, y re-snapped via the existing `surfaceCenterOf` heightmap
  logic or just `slamPos.y`). Reads as a shock ring racing outward from the impact.
- **Delayed debris rain**: new emitter `assets/eclipse/quasar/emitters/slam_debris.json` (clone
  `structure_slam_dust`: `veil:gravity` 0.8, initial speed ~0.8 up, `random_initial_direction`,
  size 0.3–0.5, lifetime ~50, `velocity_stretch_factor` 0.25) spawned twice at `beat.riftPos`
  (t+8 and t+20, before the rift close at `RIFT_CLOSE_DELAY_TICKS`+hold) — chunks arc out of the
  closing sky tear and rain down over the fresh paste.
- **Replay parity**: mirror rings + debris in `replay("STRUCTURES")` (the per-player fake beat
  already schedules the slam at `RIFT_HOLD_TICKS`).
- Hooks: `ExpansionSequence.slamFx` / `slamBeat` / `replay`; one new JSON. All spawns are
  server-cued `S2CQuasarPayload` → client BURST budget; 12 extra spawns spread over 20 ticks
  stays inside `BURST_PER_WINDOW` (15/window).

### 3. Post-expansion "new land" ambient glow, fading over 10 min (M)
The event currently hard-stops at END (grade releases over 100 ticks, done). Give fresh land an
afterglow so exploring the new ring right after the event feels charged:
- **Server** (`ExpansionSequence.beginEnd`): broadcast one new frozen FX id
  `FX_NEW_LAND_GLOW = fx("new_land_glow")` via `FxPayloads.sendFxEvent(level, id, Vec3.ZERO, innerR, outerR, -1)`
  — a/b carry the band radii (`StageRadii.radius(profile, fromStage/toStage)`), matching the
  documented a/b float payload contract. (Server truth for the band already exists —
  `NewRingRegistry.onRingCommitted` records exactly this annulus — but its freshness window is
  `glitch.freshTicks` = 3 days; the glow wants its own 10-min envelope, hence the one-shot cue.)
- **Client** (`FxPayloads.handleFxEvent` + a small blackboard on `EclipseFxState`): store
  `(innerR, outerR, startTick)`; `glow = 1 - (clientTicks - startTick)/12000` clamped to 0.
  While the camera stands inside the band and `glow > 0`:
  - AMBIENT-channel upwelling motes: 1 spawn / ~2 s of a `new_land_motes.json` (clone
    `door_glow_motes`, slow rise, alpha scaled — or reuse `map_expand_materialize` at reduced
    rate) at a random surface point within 24 blocks, probability × `glow`.
  - Optional fog kiss: +`0.10 * glow` extra blend in `OverworldFogTint.onComputeFogColor`
    toward the purple — but respect EVAL-4 M7 (must not fight `StormInteriorFx`; skip when
    `interiorAmount() > 0.5`).
- Restart-safe by design: the blackboard is transient; rejoin simply loses the last minutes of
  glow (acceptable, matches the eclipse-grade rejoin behavior documented on the sequence).

### 4. Birds/motes fleeing the wave (S)
The dust wall is stationary where it spawns; nothing *reacts* to the front. Add a startled-scatter
beat: in `ExpansionSequence.ClientHooks.handleWavePulse`, alongside the dust wall, spawn ≤ 1
`growth_flee_motes.json` per pulse (new JSON: `purple_wisp` sprite, size 0.3–0.6,
`veil:sphere` shape, `random_initial_direction`, speed ~0.5, slight `veil:wind` up-and-inward
`[0,0.6,0]`, lifetime ~40) at the nearest front-arc point (`clampToArc` math already computes it)
when it is within 64 blocks, y = `MOTION_BLOCKING` surface + 2, SEQUENCE channel. The wisps burst
up and scatter over the player's head like startled birds as the front sweeps the old rim band.
Same intro-fusion guard as the dust wall. One JSON + ~15 lines in the existing handler.

### 5. Rolling refraction ripple riding the front (S)
Reuse the shockwave post pass as a *travelling* heat-shimmer: in `handleWavePulse`, every 4th
`pulseIndex` where the nearest front point is within 48 blocks, call
`EclipseFxState.startShockwave(frontPoint, 0.12F * distanceFade, 12)`. At the 5-tick pulse
cadence this reads as a refraction ring continuously sweeping past with the wavefront — the
"growth is bending the air" read for zero new assets and zero protocol. (Single-slot shockwave
state is fine: each call replaces the last, and 12-tick envelopes at ≥ 20-tick spacing never
overlap.) Hook: `ExpansionSequence.ClientHooks.handleWavePulse`, ~10 lines.

### 6. Rift-hold anticipation: converging motes + pre-impact hush shake (S)
The 40-tick `RIFT_HOLD_TICKS` between sky-tear open and the paste trigger is currently silent.
In `maybeStartNextBeat` after the `FX_RIFT_OPEN` send, add `schedule(server, 10/20/30, …)` →
`PacketDistributor.sendToPlayersNear(..., 192, new S2CQuasarPayload(PORTAL_SURFACE_MOTES, beat.riftPos))`
(asset exists: `portal_surface_motes.json`) so energy visibly gathers at the tear, and at t+34 a
micro-shake `S2CShakePayload.shake(0.1F, 6)` — the "inhale" before the slam. Mirror the three
mote beats in `replay("STRUCTURES")`. ~15 lines, no new assets.

### 7. The wave gets a voice: positioned rolling rumble (S)
All growth audio today is the global cutscene drone; the front itself is mute. In
`handleWavePulse`, every 16th `pulseIndex`, `level.playLocalSound(frontX, surfaceY, frontZ,
EclipseSounds.EVENT_STORM_BURST.get(), SoundSource.AMBIENT, volume = clamp(1 - dist/160, 0, 0.8),
pitch 0.55–0.7, false)` at the nearest front point. Positioned audio makes the wave audibly
approach, pass, and recede — huge presence win for one throttled `playLocalSound` call. (If
`event.storm_burst` reads too stormy in playtests, register a dedicated `event.growth_rumble`
in `EclipseSounds` — still S.)

### 8. Reveal-delay pop mask: dust skirt on chunk resend (S)
Design D11 holds a rewritten chunk's relight/resend until `revealDelayTicks` after its covering
pulse, but the resend itself can still read as a subtle full-chunk snap (relight + decoration
appear at once), especially when the dust wall was budget-refused. Client-side mask: in
`ClientHooks`, track "sweep active" (last pulse < 40 ticks ago, band = `innerR..outerR`); subscribe
to chunk load on the client (NeoForge `ChunkEvent.Load` with `level.isClientSide()`), and when a
chunk whose center radius lies in `[innerR − 16, waveR]` (re)loads during an active sweep, spawn
one `growth_dust_wall` at its center surface (SEQUENCE, 96-block range gate as usual). The pop
happens inside a rising dust curtain. ~25 lines in `ClientHooks`.

### 9. Slam impact light flash (S)
The slam is dust + screen shockwave but casts no light. In `slamFx`, add one
`S2CQuasarPayload(S2CQuasarPayload.IMPACT_LIGHT, slamPos)` (emitter asset `impact_light.json`
already exists and is budget/light-law compliant — lights are Java-side `FxBudget.tryLight`
claims per EVAL-4's verified-clean note). One line server-side + the same line in
`replay("STRUCTURES")`; instant depth win at night and inside the eclipse grade.

### 10. END payoff: rim salute at the new edge (S)
END currently: caption + grade release + award roulette. Add a horizon beat that points players
at what they just gained: in `beginEnd`, for each watcher compute the nearest NEW rim point
(`edgeAnchorFor(run.level, player.position(), StageRadii.radius(run.profile, run.toStage) - 8)` —
helper already in the class) and `schedule(server, i * 8, …)` three staggered
`S2CQuasarPayload(UNLOCK_BURST, rimPos)` spawns (asset `unlock_burst.json` exists) plus one
positioned `EclipseSounds.EVENT_EMERGE` at the rim. Skip in `replay("END")` or mirror FX-only —
either is contract-clean since replay already suppresses `sendRevealNow`. ~20 lines.

---

## Cross-cutting cautions
- **Budget law**: ideas 4/5/8 all add SEQUENCE-channel spawns inside the same window as the dust
  wall (≤ 2/pulse). Worst case stacked: dust wall 2 + flee motes 1 + skirt 1 = 4 per pulse ≈ 16/s,
  well under the 60/s burst — but fix EVAL-4 M3 (`SEQUENCE_BURST_HISTORY_CAP` 120 → 180) first if
  all are adopted, since sweeps run 30–75 s and the burst window collapses to the 30/s floor after
  2 s.
- **Replay parity** (R12): every server-cued addition (2, 6, 9, 10) needs its FX-only mirror in
  `ExpansionSequence.replay` — no world mutation, no `trigger()`, no award writes.
- **Nether reduced runs**: ideas 1, 4, 5, 7, 8 ride `S2CGrowthWavePayload` and therefore work
  unchanged for the cutscene-less nether variant — nice: the reduced run gains most of the feel
  upgrades for free.
