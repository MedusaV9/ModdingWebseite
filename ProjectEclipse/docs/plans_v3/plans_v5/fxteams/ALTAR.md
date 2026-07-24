# FX Team — ALTAR (round: next-level pass, W-P-ALTAR2)

Team process per component: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `client/sky/AltarVeilSky.java`, `client/drama/AltarCeremonyFx.java` +
`AltarIdleMotes.java` + `OfferingSwallowFx.java`, quasar emitters `altar_*`,
`offering_swallow`, `sanctum_lightfall`, `door_glow_motes`, `heart_burst`, plus the
FX aspects of `worldgen/structure/SanctumOrbitals.java` (visual only — orbital
gameplay/anchors/packets untouched).

Context from last round (frozen): 5 sky tiers (ring → constellation → aurora → halo
beams → corona crown) keyed off the synced `ClientStateCache.altarLevel`, per-level
tick-scripted ceremonies in `AltarCeremonyFx`, the offering swallow spiral with
beam-hold, idle mote window, level-scaled orbitals. Hard rules this round: reducedFx
ladder + `FxBudget` respected (ceremony beats ride SEQUENCE, idle rides AMBIENT,
swallow rides BURST), no new packets/payload shapes, offering VALUES stay secret
(split-chime law). Self-checks: `javac --release 21` against the moddev merged jar
(+ veil/geckolib/voicechat-api), `python3 -m json.tool` on every touched emitter.
No gradle, no git.

---

## Component 1 — `AltarVeilSky.java` (per-tier sky MOTIFS)

### PLAN
The five layers read as static decals once you've seen them for a minute. Brief: one
signature BEHAVIOR per tier — L1 writes itself on first appearance, L2 re-arranges
with a chime pulse, L3 answers offerings, L4 casts ground light (ground half lives in
Component 3), L5 fires a map-wide crown flare. All in the existing untextured
position-color celestial pass; zero per-frame allocations beyond the shared
Tesselator; tier ladder (2/1/0) preserved.

### IDEATE
1. **L1 write-in arc** — track `altarLevel` from the render side; a genuine mid-session
   0→1 increase arms a one-shot: the ring draws as a partial soft arc sweeping 360°
   over ~3.2 s behind a bright flickering pen-tip diamond. Login/resync adopts
   silently (no replay spam). **CHOSEN**
2. **L2 permutation glide** — every 34 s the seven glyphs glide (2.6 s smoothstep) from
   jitter/scatter row `(i+N)` to `(i+N+1)` — an index-shift permutation, so the end
   of cycle N IS the start of cycle N+1: continuous by construction, zero RNG in the
   render loop. A `sin(π·t)` "chime" swell brightens glyphs + companion sparks during
   the glide. Tier 2 only; tier 1 pins cycle 0/blend 1 (static, no snap). **CHOSEN**
3. **L3 offering response** — `AltarCeremonyFx.offeringSkyGlow()` (0..1 envelope armed
   on swallow ARRIVAL, rise 5 t / release 35 t) multiplies aurora alpha (×1 → ×2.6)
   and ripple amplitude (×1 → ×1.4). Value-agnostic: every offering brightens the sky
   equally — worth never leaks map-wide. **CHOSEN**
4. **L4 ground read** — faking "cast light" from the sky beams needs world geometry;
   done as ground-projected quasar patches in `AltarIdleMotes` (Component 3), synced
   to `BEAM_SPIN_DEG_PER_SEC[0]` = 2.1 °/s wall-clock azimuth. **CHOSEN (split)**
5. **L5 crown flare** — a second, rarer envelope over the crown: every 45 s (co-prime-ish
   vs the 12 s pulse, so beats rarely stack) a 2.8 s `sin(π)` flare stretches spikes
   (+75 % length), blooms radius/alpha, and (tier 2) fires the echo ring. Tier 1 keeps
   a half-strength flare — its only crown beat, hence still map-wide on reduced. **CHOSEN**
6. **L2 glyph "shooting-star" swap** — glyphs dart across the disc when re-arranging.
   **REJECTED**: darting reads as an event/alarm; the constellation should breathe,
   not signal.
7. **L3 aurora hue shift on offerings** — color response instead of brightness.
   **REJECTED**: hue changes read as state changes (day/stage tells live in color);
   brightness is the safe axis.

### IMPLEMENT
- `trackLevel()` + `ringWriteStart` (NaN = idle) + `ringWriteProgress()`; write-in draws
  via new `drawSoftArc(start, sweep)` (the old `drawSoftRing` is now the 2π case;
  segment count scales with sweep) + pen-tip diamond at the head, over-bright ×1.35.
- Rearrange: `cycle`/`windowT`/`blend`/`chime` computed once per frame; `from/to` row
  indices per glyph; angle scatter row (`GLYPH_ANGLE_SCATTER`) added beside the radius
  jitter row so re-arrangements move glyphs in BOTH axes.
- `drawAuroraBands(..., offeringGlow)`; `drawCoronaCrown` gains the flare envelope and
  a three-way echo driver (surge > pulse > flare priority).

### POLISH 2
- Fixed tier-1 snap: rearrange window is tier-2 gated but `cycle` still advanced at
  tier 1 → pinned `cycle = 0`, `windowT = 1` when not rearranging.
- Hour-wrap safety on the write-in: negative `t` (seconds clock wrapped) resolves to
  "fully written" instead of a stuck partial ring.

### POLISH 3
- Confirmed `trackLevel` runs BEFORE the `level <= 0 || rainAlpha` early-out so level
  observation never stalls under rain; write-in still triggers post-rain correctly
  (progress just completes silently if it rained through the window — acceptable).
- Echo driver: pulse branch requires `surge < pulse` so the ceremony surge echo (its
  own monotonic travel clock) is never double-fired by the pulse window.

---

## Component 2 — `AltarCeremonyFx.java` (anticipation + settle phases)

### PLAN
Ceremonies currently START at maximum intensity (the burst). Brief: 2 s anticipation
(inward-spiraling motes + rising hum) before the burst, and a "settle" afterglow
(drifting ash-light) after it. The server's own t=0 beam/ring can't be delayed
(no wire change) — recast it as the "altar answers" spark the anticipation builds on.

### IDEATE
1. **Lead-shift script** — one `lead = 40 t` constant added to every existing beat's
   tick; sting stays at t=0 as the look-up announcement; three `EVENT_BEAM_HUM` plays
   at rising pitch (0.78 → 1.0 → 1.24) at t=2/16/30 carry the "rising hum". **CHOSEN**
2. **`altar_indraw` emitter** — ONE long-lived (36 t) emitter, cylinder-surface spawns,
   `veil:vortex` (tangential swirl) + `veil:point_attractor` (inward pull, strength
   2.4, verified positive-strength = attract in the Veil bytecode) → genuine inward
   SPIRAL, not just drift. Single SEQUENCE charge for the whole window. **CHOSEN**
3. **Settle afterglow** — `altar_afterglow`: slow gold→violet ash-light rising on a weak
   wind; two spawns staggered +22 t at 1.2/2.4 blocks, start = `lead + 34 + 6·level`
   (higher ceremonies ring longer); one falling hum (pitch 0.6). **CHOSEN**
4. **Anticipation screen-space vignette** — darken edges while motes draw in.
   **REJECTED**: fullscreen touches are reserved for the L4 sky-crack flash; two
   fullscreen beats per ceremony is one too many.
5. **Reverse-time glyph rain during anticipation** (motes rising INTO the sky).
   **REJECTED**: contradicts the "in-draw" read; the altar is inhaling, not exhaling.
6. **Per-level anticipation length scaling.** **REJECTED**: the held breath is a fixed
   musical figure; stretching it per level makes high ceremonies drag.
7. **Offering sky-glow envelope home** — the L3 aurora response state (armed by
   `OfferingSwallowFx`, read by `AltarVeilSky`) lives HERE beside `skySurge` so the
   sky reads all ceremony-ish envelopes from one place. **CHOSEN**

### IMPLEMENT
- `ANTICIPATION_TICKS = 40` (tier ≥ 1; tier 0 keeps `lead = 0` — minimal profile law),
  `SETTLE_BASE_DELAY_TICKS = 34` + `SETTLE_PER_LEVEL_TICKS = 6`; INDRAW/AFTERGLOW ids;
  all L1–L5 beats shifted `+lead`; settle block appended (tier ≥ 1, emitters
  near-gated like every particle beat).
- `notifyOfferingSwallowed()` + `offeringSkyGlow(partialTick)` (rise 5 t/release 35 t
  smoothstep envelope on the pause-frozen ceremony clock); reset on logout/level-null.

### POLISH 2
- Caption beat also shifted `+lead` so the whisper still lands after the visual peak.
- Anticipation emitter spawn near-gated (it was world-visible in the first pass —
  only screen/sound beats may skip the distance gate).

### POLISH 3
- Verified a re-triggered ceremony mid-anticipation clears STEPS first (existing
  `STEPS.clear()`), so lead beats never stack; envelopes intentionally survive the
  clear (surge/glow are timestamps, not steps).

---

## Component 3 — `AltarIdleMotes.java` (L3+ double helix, L4 halo ground patches)

### PLAN
Idle motes are a formless cloud. Brief: at L3+ they should trace a faint slow
double-helix column; plus the L4 sky-beam ground read (Component 1 idea 4). Both must
stay inside the AMBIENT budget and the existing rolling-window law (loops never
self-expire; oldest culled beyond the cap).

### IDEATE
1. **Deterministic strand placement** — keep the SAME spawn cadence/window; at L3+ two
   of every three spawns land ON a helix strand: strand angle = slow whole-helix spin
   (460 t period) + strand offset (0/π) + climb·twist (1.5π over 3.4 blocks); climb =
   `gameTime % 360 t`. The rolling window itself traces the helix; each mote's own
   upward wind animates it. Zero new emitters, zero extra budget. **CHOSEN**
2. **Third ambient spawn kept** — every third spawn stays on the old ambient ring so
   the island floor never goes bare around the column. **CHOSEN**
3. **Halo patch cadence** — separate slow countdown (55–80 t) spawning ONE
   `altar_halo_patch` one-shot at ground level (hover 0.12), azimuth =
   `wall-clock · 2.1 °/s + beamIndex · 90°` (beamIndex round-robins 0..3) — exactly the
   sky fan's phase family, so pools genuinely sweep with the sky. L4+ only. **CHOSEN**
4. **Dedicated helix emitter JSON with veil:vortex.** **REJECTED**: a vortex bends
   trajectories but can't hold a two-strand phase relationship; placement is the only
   robust way to draw a helix with one-shot loops.
5. **Patches as looping emitters with managed handles.** **REJECTED**: one-shots need
   no handle bookkeeping and a budget refusal just skips one pool — strictly simpler.
6. **Raycast to actual ground height per patch.** **REJECTED**: the altar island top is
   flat by construction (worldgen disc); anchor-Y + hover is correct and free.
7. **Helix strands colored differently per strand.** **REJECTED**: door_glow_motes is
   a shared emitter; forking it for a tint doubles maintenance for a subliminal cue.

### IMPLEMENT
- `spawnCounter` round-robin (helix/helix/ring), `pickSpawnPos` takes the level for
  `getGameTime()`; radius ±0.15 jitter keeps strands soft. `tickHaloPatches` +
  `patchCountdown`/`patchBeamIndex`; `PATCH_DEG_PER_SEC` documented as MUST-MATCH
  `AltarVeilSky.BEAM_SPIN_DEG_PER_SEC[0]`.

### POLISH 2
- Patch radius gains `+0.4/level` above L4 and ±0.6 jitter so pools wander rather
  than stamping one circle.
- `patchCountdown` reset in `clear()` and while below L4 (no stale short fuse when
  leveling into L4).

### POLISH 3
- Confirmed patches spawn inside the same distance/reducedFx/dimension gates as the
  window (the early-outs run before `tickHaloPatches`), so reduced clients pay zero.

---

## Component 4 — Offering value tell + item-color glow
(`S2CQuasarPayload.java`, `ritual/AltarBlockEntity.java`, `OfferingSwallowFx.java`)

### PLAN
Brief: swallow gets item-color sampling (else violet-gold dual tone) and a "value
tell" — richer offerings = brighter swallow. Hook check: `AltarBlockEntity` already
computes `OfferingService.acceptWithValue` and quantizes it into the private PITCH
tell (IDEA-12 #2 buckets). Constraint: exact values stay secret; the pitch tell is
offerer-only (split chime) — the visual tell must match that privacy split.

### IDEATE
1. **Tier-in-id transport** — no new payload shape: the offerer's swallow id becomes
   `eclipse:offering_swallow/t<0..2>/<ns>/<path>`; bystanders get the neutral untiered
   id via `sendToPlayersNear(exclude = offerer)`. `t<d>/` can't collide with a real
   item namespace (single char + digit). Parser: `offeringSwallowTier` (default mid=1),
   `offeringSwallowRest` strips the segment so `offeringSwallowItem` is tier-blind. **CHOSEN**
2. **Shared bucket helper** — `offeringTellTier(exactValue)` (≤5 junk / ≤40 mid / rich)
   extracted and used by BOTH `offeringTellPitch` and the swallow id, so ear and eye
   can never disagree. **CHOSEN**
3. **Sprite-sampled glow color** — average opaque pixels of the item's particle icon
   (4×4 probe grid, first animation frame via `SpriteContents.getOriginalImage`,
   ABGR order), normalize dominant channel to 1 (additive needs brightness), fold 30 %
   toward the warm gold house tone; near-black or unreadable sprites → violet-gold
   dual tone. Sampled ONCE per flight at begin, try/caught. **CHOSEN**
4. **Additive glow fan renderer** — camera-facing radial fan (10 slices as degenerate
   quads), core = sampled color, rim = house violet at alpha 0; alpha per tier
   (0.24/0.40/0.62) + subtle sine shimmer; one POSITION_COLOR mesh for ALL flights,
   drawn after `endBatch()` with SRC_ALPHA/ONE + `depthMask(false)` (SupplyBeamRenderer
   state discipline), nudged 0.08 toward the camera to clear the item sprite. Zero
   particles, zero budget. **CHOSEN**
5. **Tier also scales the item billboard** — ±6/8 % (0.94/1.0/1.08): felt more than
   seen; the glow carries the tell. **CHOSEN**
6. **Trail emitter recolored per item via runtime module injection.** **REJECTED**:
   Quasar gradients are data; runtime patching is deep API surgery for a 6-tick trail.
7. **Brighter swallow for bystanders too.** **REJECTED**: leaks the daily-winner
   metagame; violates the split-chime law.
8. **Tier via a second parallel payload.** **REJECTED**: ordering between the two
   packets is not guaranteed cheap; the id already rides the information for free.

### IMPLEMENT
- Payload: `offeringSwallow(item, tier)` overload + tier parse/strip helpers.
- Block entity: offerer gets the tiered id (`sendToPlayer`), bystanders the neutral id
  (`sendToPlayersNear` excluding offerer); beam unchanged.
- Client: `Flight` carries `tier` + `glowColor`; arrival fires
  `AltarCeremonyFx.notifyOfferingSwallowed()` (Component 1 L3 motif); render split into
  item-batch pass + `renderGlowFans` mesh pass.

### POLISH 2
- Replaced the first-pass `RenderType.lightning()` fan (writes depth → transparent
  quads occlude particles/weather; mixed render types force batch flushes) with the
  explicit mesh + state block above.
- `getParticleIcon()` deprecation → `getParticleIcon(ModelData.EMPTY)`.

### POLISH 3
- Verified reducedFx path ignores the tier entirely (degrades to the plain burst
  before the tier is read) and that `intercept` still routes tiered ids because the
  item parser strips `t<d>/` first.

---

## Component 5 — new emitters (`altar_indraw`, `altar_afterglow`, `altar_halo_patch`)

### PLAN
Three one-shot JSONs, all on the existing `purple_wisp` sprite, additive billboards,
schema-matched to the existing altar kit.

### IDEATE (structure choices)
1. Indraw: cylinder-surface spawn ring (r 3.2) so motes visibly ARRIVE from outside;
   vortex strength 1.1 vs attractor 2.4 → decaying spiral, drag 0.14 stops overshoot
   ping-pong. **CHOSEN**
2. Afterglow: 70 t ± 20 lifetimes, speed 0.03, weak wind up — ash-light hangs, alpha
   caps at 0.5 (settle must be quieter than any burst beat). **CHOSEN**
3. Halo patch: few LARGE (0.85 ± 0.25) near-static particles, alpha ≤ 0.2, flat spawn
   disc, gentle lateral wind = a light pool sliding, not a particle effect. **CHOSEN**
4. Patch as a `veil:cube` ground-aligned quad render style. **REJECTED**: billboards at
   0.12 hover read fine from player eye heights; cube style needs rotation fiddling.
5. Indraw via `initial_velocity` aimed inward per-particle. **REJECTED**: straight-line
   convergence, no swirl — the vortex+attractor pair is the actual spiral.
6. One merged "ceremony bookend" emitter with long dead-time. **REJECTED**: dead-time
   costs budget for nothing; two small one-shots schedule cleaner.

### IMPLEMENT / POLISH
As landed; validated via `python3 -m json.tool`; module names checked against the
Veil 4.3.0 jar registry (`veil:vortex`, `veil:point_attractor`, `veil:wind`,
`veil:drag`, `veil:color`). Indraw alpha peaks 0.75 early then decays (arrivals bright,
absorbed motes dim). Afterglow gold→violet mirrors the crown palette.

---

## Component 6 — crispness pass
(`door_glow_motes`, `heart_burst`, `sanctum_lightfall`, `offering_swallow`)

### PLAN
Contrast + timing only — no behavioral changes, budgets identical.

### IDEATE → CHOSEN tweaks
1. `door_glow_motes`: lifetime 55 → 48 (±12), fade-in reaches peak at 12 % (was
   slower), peak alpha 0.62 → 0.68, start color `#B98CFF` → `#D8C2FF` (brighter head,
   same violet family) — motes read as sparks, not fog.
2. `heart_burst`: speed 0.5 → 0.62, lifetime 16 → 13 (±5), gravity 0.34 → 0.4, sharper
   white→magenta ramp, alpha holds 0.95 to 55 % then drops — a SNAP, not a puff
   (it accompanies a life sacrifice; it should sting).
3. `sanctum_lightfall`: start `#EFE4FF` → `#F6EFFF`, alpha peak earlier/higher
   (0.78 @ 10 %), tail trimmed (0.42 @ 78 %) — the fall reads as light, decay happens
   in the air not on the floor.
4. `offering_swallow`: trail 6 → 7 @ alpha 0.45 → 0.5, head alpha 0.85 → 0.9 — the
   spiral path reads at one glance now that a glow fan rides the item.
5. Bigger particle sizes across the kit. **REJECTED**: size raises fill cost and blur;
   contrast/timing buys crispness for free.
6. Shorter `door_glow_motes` loops (faster window turnover). **REJECTED**: cadence is
   an `AltarIdleMotes` gameplay-feel constant, out of a crispness pass's lane.

---

## Component 7 — `SanctumOrbitals.java` (FX aspect only)

### PLAN
One subtle presentation-only polish; anchors, packets, reconciliation, gameplay
untouched.

### IDEATE
1. **Ring-radius breath** — ±0.22 blocks over 640 t, phase-offset per anchor
   (`phase·2`), big rings only — the debris ring undulates instead of pumping.
   Interpolation-safe: one 40 t tween window covers ~22.5° of breath phase, far under
   the ~90° linear-flattening threshold (VFXPOLISH-3 law). **CHOSEN**
2. Scale breathing (shards swell). **REJECTED**: reads as LOD popping at distance.
3. Per-shard glint via display brightness override. **REJECTED**: brightness packets
   per shard per window = real bandwidth for a subliminal effect.
4. Tumble-rate wobble. **REJECTED**: tumble is already per-shard varied; wobble on
   wobble reads as jitter.
5. Companion-shard breath (ring 2). **REJECTED**: their tight islet orbits (r ≈ 2.2)
   would visibly clip the islets at +0.22.
6. Bob-amplitude breath. **REJECTED**: bob already carries the level tell
   (`LEVEL_BOB_BONUS`); breathing it muddies that read.

### IMPLEMENT / POLISH
`RADIUS_BREATH`/`RADIUS_BREATH_PERIOD_TICKS` + `breath` term in `poseAt` (big rings
only). Verified max radius (14.8 level cap + 0.22) stays inside the scan margin.

---

## Validation (this round)

- `javac --release 21 -proc:none` over the seven touched Java files with
  `-sourcepath src/main/java` against `build/moddev/artifacts/neoforge-21.1.238-merged.jar`
  + `clientLegacyClasspath.txt` + Veil 4.3.0 + Geckolib 4.9.2 + voicechat-api 2.6.20:
  **exit 0, zero errors, zero warnings in touched files** (the 26 removal warnings are
  pre-existing `EventBusSubscriber.Bus.MOD` uses in unrelated config classes).
- `python3 -m json.tool` clean on all seven touched/new emitter JSONs.
- No gradle, no git, no wire-format changes, no gameplay changes outside the
  offerer-only visual tell (which mirrors the already-shipped pitch tell exactly).
