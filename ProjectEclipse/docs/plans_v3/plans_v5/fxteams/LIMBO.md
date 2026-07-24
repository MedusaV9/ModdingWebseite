# FXTEAM-LIMBO — Limbo scene craft pass (v4)

Team log for the LIMBO effect cluster: `limbo.fsh`/`pinwheel/post/limbo.json`,
quasar emitters `limbo_fog` / `limbo_fogbank` / `limbo_godray` / `limbo_motes`
(+ new `limbo_motes_near`), Java `veilfx/LimboAmbience`, `client/sky/LimboSpecialEffects`,
`client/sky/LimboHorizonShips`.

**Mandate:** the NEXT level of craft on a scene that was heavily reworked last round —
depth-based water mask, ray-elevation curvature, voyage drift, stable zenith disc, horizon
ships are all FROZEN fixes and none of them may move. Budget-conscious: emitter counts stay
sane; `reducedFx` tiers follow the existing ladder exactly (cadence doubling for windows,
`CurveAmount = 0`-style uniform zeroing for post features, full skip for garnish à la the
drift-cue foam glints).

**Validation (per task constraints — no gradle, no git):**
- `limbo.fsh` compiled clean with `glslangValidator` (Veil preprocessing emulated:
  `#version 430` header + `#include eclipse:eclipse_common` resolved).
- All three Java files compiled clean with `javac -proc:none` against the real
  NeoForge 21.1.238 merged jar + Veil 4.3.0 + full modules cache classpath +
  `build/classes/java/main` (`-sourcepath src/main/java` for in-project deps).
- All 5 emitter JSONs + both pipeline JSONs parse (`python3 json.load`).
- Uniform feed ↔ declaration parity re-audited (VFXPOLISH-1 checklist): 11 non-sampler
  uniforms declared, 11 fed, no dead uniforms.

---

## Component 1 — post pipeline (`limbo.fsh` + `pinwheel/post/limbo.json`)

**PLAN.** The post pass owns everything painted on the water and the horizon air. Success =
the sea reads as *water at three distance scales* instead of one shimmer sheet, plus new
rare "someone/something is out there" beats — with zero change to the frozen v3 machinery
(depth mask, ray-elevation curvature, voyage drift, uniform names §3.3-style stability).

**IDEATE (7).**
1. Secondary micro-ripple octave near the hull (higher-frequency `causticWeb`, faded by
   ~16 blocks) — near-field scale. **PICKED.**
2. Long-wavelength swells far out (very low-frequency noise re-shading web brightness
   beyond ~18 blocks) — far-field scale. **PICKED.**
3. Sparse bioluminescent glints trailing the voyage drift (rare hash cells of the
   world-anchored field, elongated along +X, slow blink). **PICKED.**
4. Wave-broken reflection smear: modulate the zenith-disc smear with world-anchored ripple
   noise. **PICKED** (pairs with the sky-pass streak rework, Component 7).
5. Far storm-glow pulses on one horizon azimuth (glow only, no bolts) driven by a new
   `LightningGlow` uniform — pure ray geometry like the curvature. **PICKED** (this is the
   shader half of the fogbank idea, Component 3).
6. Water reflection of the storm glow (mirrored belt below the horizon). **REJECTED** —
   restraint: the glow already lands on the melted-horizon water band via `horizonMix`;
   a second mirrored term risks reading as a bug ("why is the sea flashing?").
7. Depth-of-field blur on near water (multi-tap). **REJECTED** — multi-tap cost on a
   fullscreen pass for an effect the near-mote bokeh layer (Component 5) sells cheaper.

**IMPLEMENT.**
- New uniform `vec3 LightningGlow` (xy = world-XZ azimuth unit dir, z = strength 0..1).
- View ray hoisted out of the curvature branch and shared with the glow
  (`CurveAmount > 0.001 || LightningGlow.z > 0.001` — under reducedFx both are fed 0 and
  the reconstruction is skipped entirely, same cost as before).
- Layered-water block: `webAmp = mix(1, 0.55 + 0.9·swell, smoothstep(18, 60, dist))`
  (swells), `micro`-web at 3.1× frequency weighted `1 − smoothstep(5, 16, dist)`
  (near-hull ripple), both multiplied into the existing violet water term.
- Glints: ~1.8% of ~4.4-block cells of `wp` (which already contains `VoyageOffset`, so
  glints stream astern with the drift for free), gaussian spot stretched along +X,
  `sin²` blink on per-cell phase, soul-green `(0.28, 0.95, 0.55)` — the star/lantern hue.
- Smear ripple: `0.70 + 0.30·efxNoise(wp·1.3 + Time·0.20)` multiplies the reflection smear.
- Storm glow: `pow(max(dot(az, dir), 0), 6) · belt(rayDir.y) · strength · (sky + horizonMix) · 0.30`,
  violet-white `(0.62, 0.42, 1.00)`.
- The whole water block is now gated `if (water > 0.001)` so every v4 octave costs nothing
  on sky/hull/deckhand pixels (previously web+sparkle ran unconditionally).
- `pinwheel/post/limbo.json` and `pinwheel/shaders/program/limbo.json`: **no change needed**
  (single `veil:blit` stage, vertex/fragment refs unchanged — consistent with the family).

**POLISH 2 (first pass findings → fixed).**
- The glow comment claimed fog banks/ships "stay dark in front of the glow" — overstated:
  they sit at sky depth and receive the same additive term; their darkening survives in
  absolute terms (silhouette still reads) but the exclusion claim was wrong. Comment
  corrected to say exactly that.
- Spurious-glow window: `LightningGlow.z > 0` while `InvViewProj` is parked at identity
  (first frame / mid-resize) would push the glow through a garbage ray. Fixed CPU-side:
  the feeder holds strength at 0 unless `haveFrameMatrices` (Component 6).

**POLISH 3 (final audit).**
- Straight-up rays: `az` normalization floor (`max(len, 1e-4)`) is safe and `belt` is 0
  there anyway — no pole artifact.
- Glint peak (0.5 weight × gaussian spot × sin² blink × calm) sits below the sparkle term's
  integrated energy — pinpricks, not lamps. Kept.
- Confirmed no v3 behavior change when all v4 inputs are idle: `LightningGlow.z = 0`,
  `webAmp → 1` near the ship, `micro` weight 0 beyond 16 blocks, ripple averages ~0.85 on
  the smear (slightly dimmer than before — intended, it was the "solid blob" complaint).

---

## Component 2 — `limbo_fog.json` (water-hugging fog sheets)

**PLAN.** The near fog layer's job is subsurface depth right around the hull. Success =
sheets stop popping in visible sync and carry a hint of depth in their late life.

**IDEATE (6).**
1. Lifetime desync (variation 20 → 35) so two sheets spawned together never die together.
   **PICKED.**
2. Asymmetric alpha envelope — quicker drift-in, longer melt-out (fog lingers, then lets
   go). **PICKED.**
3. Late-life indigo dip (4-point RGB gradient, deeper `#381D63` at 80%) — sheets read as
   sinking into the water as they die. **PICKED.**
4. Bigger size variation (6 → 7) for silhouette variety. **PICKED.**
5. Second fog color family (teal shift) for variety. **REJECTED** — palette discipline:
   teal/green is reserved for the soul accents (stars, lanterns, glints).
6. Slight downward gravity module so sheets settle. **REJECTED** — the sheets hug the
   waterline already; settling would clip them into the water plane and fight the
   post-pass water mask band.

**IMPLEMENT.** Lifetime 50±35; alpha `0 → 0.10@25% → 0.13@55% → 0`; RGB
`#2B1546 → #47257A@45% → #381D63@80% → #1E0F33`; size 8±7. Counts/rate/cap untouched
(rate 8, count 2, max 20).

**POLISH 2.** Checked steady state: ~50/8×2 ≈ 12.5 live ≤ 20 cap even at max lifetime
roll (85/8×2 ≈ 21 → occasionally cap-thinned; acceptable, it only softens bursts).
**POLISH 3.** Alpha peak kept ≤ 0.13 — alpha-blended sheets stack (2 emitters × up to
20 particles); 0.13 × ~3 overlaps ≈ 0.35 worst-case occlusion, same ballpark as before.

---

## Component 3 — `limbo_fogbank.json` (horizon fog banks) + shader glow crosslink

**PLAN.** Middle-distance banks should read as a *horizon wall* that things silhouette
against — flatter, wider, darker than the sky gradient — and occasionally back-light with
a far storm pulse (glow only, no bolts).

**IDEATE (6).**
1. Wider + flatter spawn volume (18×2.5×18 → 26×1.8×26) and bigger sprites (20 → 26):
   banks, not blobs. **PICKED.**
2. Darker color set (`#1C0D33 / #2E1755 / #120826`, all darker than the post shader's
   horizon-melt `vec3(0.030, 0.018, 0.062)`) so horizon ships and the banks themselves
   read as silhouettes. **PICKED.**
3. Longer, more varied lives (90±30 → 110±40) — the wall churns slowly instead of
   re-rolling. **PICKED.**
4. Lightning-glow pulses INSIDE the emitter (bright alpha flashes on the sprites).
   **REJECTED** — per-particle flashing looks like popcorn; the correct composite is the
   whole horizon sky glowing BEHIND the dark banks. Implemented as the post-shader
   `LightningGlow` belt (Component 1) + deterministic feeder (Component 6): banks sit at
   sky depth and keep their darkness against the lit sky — the silhouette-gradient read.
5. Per-particle vertical color gradient (dark base, lighter crown). **REJECTED** — not
   expressible in the quasar color module (gradients are lifetime-interpolated, not
   height-interpolated); the darker-than-sky tuning delivers the same silhouette effect.
6. Third fogbank window further out. **REJECTED** — budget; the post pass horizon melt
   already owns the > 70-block band.

**IMPLEMENT.** As picked; alpha plateau 0.08 → 0.10 (compensates the darker colors so
coverage stays constant), plateau shifted 0.25–0.7. Wind (the +X sailing cue) untouched.

**POLISH 2.** Steady state 110/20 ≈ 5.5 ≤ 8 cap — safe even at 150-tick rolls (7.5).
**POLISH 3.** Verified the storm-glow color `(0.62, 0.42, 1.00)·0.30·0.85` peaks ~0.16
additive at the azimuth center — banks at alpha 0.10 in front of it still read darker;
the pulse silhouettes, never floodlights.

---

## Component 4 — `limbo_godray.json` (volumetric shafts) + Java sway crosslink

**PLAN.** The shafts should read as tall volumetric light columns from the zenith that
*sway with the ship roll* — currently they are stubby and rigidly placed.

**IDEATE (6).**
1. Taller, tighter spawn cylinder (1.2×7 → 0.9×9.5) + more velocity stretch (2.5 → 3.4):
   columns, not blobs. **PICKED.**
2. Slower sink (0.03 → 0.022) — stately, and the stretch stays readable. **PICKED.**
3. Lifetime 80 → 100 with ±20 desync so the colonnade churns organically. **PICKED.**
4. Roll sway: lean the emitter positions on a shared ~12.5 s roll phase (ship rolls about
   its +X long axis → Z-dominant sway + slight slower X lean). Done Java-side via
   `ParticleEmitter.setPosition` on the live window handles — new particles spawn from the
   leaned origin and the 5 s particle lifetime makes the whole shaft lag into the lean,
   exactly the pendulous read a hanging light column should have. **PICKED**
   (implementation in Component 6).
5. Tilt `initial_direction` toward the zenith azimuth per spawn. **REJECTED** — direction
   is baked in the JSON; faking it by rotating the emitter shape reads identical at these
   heights and would desync from the actual zenith anchor.
6. Sub-emitter dust at the shaft foot. **REJECTED** — budget (each shaft would double its
   particle count); the motes windows already populate that band.

**IMPLEMENT.** JSON as picked; alpha plateau 0.12 → 0.10 (taller + stretched sprites carry
more integrated light per particle), plateau 0.2–0.7.

**POLISH 2.** Steady state 100/10 = 10 = cap exactly; high lifetime rolls (120) get
cap-thinned — deliberate, it varies the colonnade instead of metronoming it. Noted, kept.
**POLISH 3.** Sway wrap audit: `gameTime % 12000` = exactly 48 roll periods (and 24 lean
periods) — the wrap is seamless by construction (see Component 6).

---

## Component 5 — `limbo_motes.json` + new `limbo_motes_near.json` (depth-layered dust)

**PLAN.** "Depth-layered dust with focus falloff — bigger, blurrier near camera." Success =
a bokeh foreground layer + a crisper in-focus mid layer, at near-zero extra budget.

**IDEATE (6).**
1. Per-particle camera-distance size/blur via molang (`veil:size`/`init_size`). **REJECTED**
   — the quasar molang env exposes lifetime/age queries only (verified against the Veil
   4.3.0 jar: `q.agePercent`/lifetime setQuery), no camera distance; and untested-at-runtime
   molang in this no-gradle task is exactly the kind of load-time risk the cluster ban
   exists for.
2. Split the depth layers across the Java spawn windows instead: a NEW near window
   (3–7 blocks) with its own JSON — few, LARGE (0.55±0.30), very faint (α 0.07), slow —
   big + dim + soft sprite = out-of-focus read; the existing motes JSON becomes the
   in-focus mid layer. **PICKED.**
3. Retune far motes smaller + crisper (0.07±0.04 → 0.055±0.03, α 0.25 → 0.28) — sharpens
   the "in focus" contrast against the bokeh layer. **PICKED.**
4. Lifetime desync ±20 → ±30 on the mid layer. **PICKED.**
5. Third even-farther dust layer. **REJECTED** — invisible at 0.05 sizes beyond ~25 blocks;
   pure waste.
6. Near-layer under `reducedFx`: drop entirely (the drift-cue foam-glint ladder) rather
   than cadence-halve — near-camera billboards are the scene's most expensive overdraw.
   **PICKED** (implementation in Component 6, including the mid-session-toggle clear).

**IMPLEMENT.** `limbo_motes_near.json`: sphere 3.5×2×3.5, rate 8/count 1/cap 12, speed
0.004, size 0.55±0.30, life 90±30, additive, same wisp sprite + violet ramp as the mid
layer, α plateau 0.07 @ 35–65%. Mid layer retuned as picked.

**POLISH 2 (found → fixed).** First draft had rate 5 → steady state 90/5 = 18 > cap 12,
which makes Quasar drop spawns erratically. Retuned to rate 8 (≈ 11.25 steady ≤ 12).
**POLISH 3.** Overdraw estimate for the near layer: ≤ 2 emitters × 12 particles × ~0.85
blocks at 3–7 m — worst case a handful of quarter-screen faint quads; acceptable, and the
whole window vanishes under reducedFx.

---

## Component 6 — `veilfx/LimboAmbience.java` (feeder + windows)

**PLAN.** Carry the three cross-component features (storm-glow uniform, godray sway,
near-motes window) without disturbing the proven rolling-window/budget machinery.

**IDEATE (6).**
1. `LightningGlow` feeder: deterministic slot schedule (37 s slots, ~55% flash → ~67 s
   average) hashed off `ECLIPSE_SEED` + the hourly wall-clock `Time` base, so every client
   flashes together; ≤ 2 s lead+echo envelope (sharp attack, exp decay, dimmer echo at
   +0.45 s — the classic distant cloud-lightning double pulse). **PICKED.**
2. Storm events as spawned glow emitters at the horizon. **REJECTED** — 60+ blocks out the
   sprite would be fog-culled and budget-charged for a 2 s event; the post shader does it
   for literally zero particles.
3. Window sway support: per-window `swayAmplitude`, live entries become
   `Live(emitter, base, phase)` records, per-tick `setPosition(base + roll offset)` —
   Z-dominant + slight X lean, shared phase with small per-emitter offsets (±0.4 rad).
   **PICKED** (GODRAYS: 0.9 blocks; everything else 0).
4. Per-window `skipUnderReducedFx` garnish flag that *clears* (not just skips) so a
   mid-session settings toggle can't leak looping emitters. **PICKED** (NEAR_MOTES only).
5. Sway via re-spawning emitters at offset positions each cadence. **REJECTED** — churns
   the budget channel and pops; `setPosition` on the kept handles is free (verified the
   Veil 4.3.0 emitter tick: position = offset for unattached emitters, so `setPosition`
   persists).
6. Feed a reducedFx uniform into the shader and tier the water octaves too. **REJECTED** —
   the existing post ladder zeroes *feature* uniforms (`CurveAmount`) rather than adding
   config uniforms; the v4 octaves are cheap ALU inside the water mask and don't warrant a
   new tier knob.

**IMPLEMENT.** As picked. New emitter id constant `limbo_motes_near`; `WINDOWS` grows to 5;
`feedStormGlow` + local `hash01` (the `LimboSeascape` mixer with its own salt so storm
slots can't correlate with horizon-ship reseeds); sway clock `gameTime % 12000` = exactly
48 × 12.5 s roll periods (seamless wrap); class javadoc updated with the v4 section.

**POLISH 2 (found → fixed).** `LightningGlow` could go nonzero on a frame where
`InvViewProj` is parked at identity (first frame / mid-resize) → spurious glow through a
garbage ray. Now gated on `haveFrameMatrices`.
**POLISH 3.** Confirmed: sway runs before the countdown gate (leans every tick, not only
on spawn ticks); `prune`/`clear` handle the new record type; reducedFx cadence-doubling
still applies to all five windows on top of the garnish skip; no allocations in the feeder
path (records allocate only at spawn, in the tick path, which was already allocating).

---

## Component 7 — `client/sky/LimboSpecialEffects.java` (disc, aura, streak)

**PLAN.** The eclipse disc is the scene's anchor — it must stay pixel-stable (C2 freeze).
Craft goals: the corona should *breathe*, occasionally shed a coronal-mass wisp, the aura
rays should rotate VERY slowly with parallax depth layering, and the water streak should
break across waves. None of this may touch the disc quad or the smoothed direction.

**IDEATE (8).**
1. Corona breathing: glow-fan radius ±5% on a slow ~27 s cycle, center alpha dimming as it
   expands (energy conservation → physical read, not scale wobble); layered UNDER the
   existing dual-frequency alpha pulse so the periods beat organically. **PICKED.**
2. Coronal-mass wisps: rare (41 s slots, ~45% occupancy, ~10 s life) curved plume from the
   disc rim — two chained quads, mid bulging perpendicular (the CME loop), ease-out
   growth, sin-in-out alpha peaking at 0.15·pulse, root inside the disc silhouette so the
   black core occludes it (the ray-root trick). Deterministic via the shared
   `ECLIPSE_SEED` mixer. **PICKED**; skipped under reducedFx (garnish ladder).
3. Slow the ray spin 1.2 → 0.35 °/s ("VERY slowly rotate"). **PICKED.**
4. Parallax depth layering: layer B (the counter-rotating fan) translates opposite the
   camera's walk offset from the ship anchor (0.06 units/block, clamped ±5) while layer A
   stays disc-locked — walking the deck separates the fans into near/far sheets, standing
   at the anchor re-converges them. Continuous in camera position → cannot pop (C2 law).
   **PICKED.**
5. A third, even nearer ray layer. **REJECTED** — restraint; two counter-rotating layers +
   differential parallax already read as depth, a third muddies the R5-frozen aura look.
6. Wave-broken streak: replace the solid reflection fan with 6 glitter dashes (2 quads
   each: transparent → bright mid-seam → transparent) along the SAME mirror-locked tangent
   basis, each shimmering on its own frequency with golden-angle phase spread (2.399 rad —
   no two ever beat in sync) and wandering slightly sideways. **PICKED.**
7. Streak dashes as world-space quads on the actual water plane. **REJECTED** — that is
   the pre-C2 bug (independent world placement tore away from the disc); the dashes stay
   camera-relative at sky distance, mirror-locked like the fan they replace.
8. Disc-edge diffraction ring on the disc quad. **REJECTED** — touches the frozen disc.

**IMPLEMENT.** As picked: `drawAuraGlow(pose, pulse, breath)`,
`drawAuraRays(pose, seconds, pulse, parX, parZ)`, new `drawCoronalWisp` (between rays and
disc, additive blend still active), `drawWaterReflection(..., seconds)` rewritten to
dashes; class javadoc gained the v4 section. Layer-B roots stay hidden: radius 30 −
max parallax ~7 ≈ 23 « 52.5 disc half-extent.

**POLISH 2 (found → fixed).** With `heightFade` near its 0.01 floor every dash can drop
below the alpha epsilon → empty `BufferBuilder` → `buildOrThrow()` would CRASH. Switched
to nullable `build()` + null check (the one hard-crash bug this pass; the old fan always
had vertices, the dashes don't).
**POLISH 3.** Alpha-budget parity: dash mid-seam peak = 0.35·(1−u²)·shimmer ≤ the old fan
center 0.35; average is lower — intended (the "solid streak" was the complaint). Dash
count 6 × 2 quads = 48 verts vs the old 18-vert fan — negligible. Wisp slots verified
against the hourly `Time` wrap (last partial slot simply never activates — one skipped
wisp per hour at worst, invisible).

---

## Component 8 — `client/sky/LimboHorizonShips.java` (passing lantern)

**PLAN.** A rare "passing lantern" — a distant light crossing the horizon. It must feel
like an event (you were lucky to see it), cost nothing, and not break the ships'
vanish-when-observed determinism.

**IDEATE (6).**
1. Warm-amber light (core dot + soft halo) crossing 29–49° of horizon over 30–45 s, every
   4–8 min, with a slow 6 s bob — the only non-violet/non-soul-green light in limbo:
   *someone else is sailing*. **PICKED.**
2. Soul-green like the ship lanterns. **REJECTED** — it would read as just another ghost
   ship; the warm accent is the story beat (and the palette exception is deliberate and
   logged).
3. Gaze-latch it like the ships. **REJECTED** — the ships vanish when observed; the
   lantern is the one thing that lets itself be watched. That asymmetry IS the design.
4. Attach a faint hull silhouette under it. **REJECTED** — a bare light is more unsettling;
   also keeps it clearly distinct from the SHIP_COUNT machinery.
5. Deterministic per-event hashes (`ECLIPSE_SEED` mixer on an event counter) but scheduled
   off the local first-draw time — cosmetic per-client timing like the ship fade, azimuths
   reproducible. **PICKED.**
6. reducedFx: skip scheduling + drawing entirely (garnish ladder, same as the foam
   glints). **PICKED.**

**IMPLEMENT.** New lantern state block + `tickAndDrawLantern` (shares the ships' lazy
buffer and no-fog window; creates the buffer itself when a lantern is up with no ships
visible), `emitLanternQuad` core + `emitLanternHalo`, sin-eased crossing envelope, 120-tick
bob (mod = exactly one cycle, seamless). Schedule self-heals: a world swap that rewinds
game time re-arms within a minute instead of parking the event hours out; a rewind
mid-crossing cancels cleanly. `hash01` widened to package-private (shared with
Component 7's wisp scheduler — same mixer, disjoint salts).

**POLISH 2 (found → fixed).**
- The halo was a uniform-alpha quad — at 1.5 half-size it read as a hard SQUARE; replaced
  with a 4-triangle diamond gradient (bright center vertex, transparent rim points),
  written longhand — no scratch arrays in the per-frame path (§3.5).
- First bob draft used `gameTime % 126` with a 40-tick period — wrap pop AND too fast;
  fixed to `% 120` with a 120-tick period (exactly one cycle per wrap).
**POLISH 3.** Verified the lantern cannot interact with the ship reseed determinism (its
hashes use salts 911–929 on the event counter, ships use `i·197+31` on sightings); alpha
envelope keeps it under the stern-lantern brightness at all times; total added geometry
when active: 18 verts.

---

## Cross-cutting budget & tier summary

| Feature | Cost | reducedFx behavior |
|---|---|---|
| Water octaves + glints + smear ripple (fsh) | ~5 extra noise/hash calls, water pixels only | unchanged (cheap ALU; the post ladder's knob stays `CurveAmount`) |
| Storm glow (fsh + feeder) | 1 uniform, ray math on glowing frames only | strength fed 0 (CurveAmount ladder) |
| God-ray sway | ≤ 3 `setPosition`/tick, 0 particles | window cadence doubles as before (sway itself is free) |
| Near-focus motes | +1 window: ≤ 2 emitters × 12 particles | skipped AND cleared (foam-glint ladder) |
| Fog/fogbank/godray/motes retunes | same or lower steady-state counts | cadence doubling as before |
| Corona breathing + parallax rays | 0 extra draw calls | unchanged (core sky) |
| Coronal-mass wisp | 2 quads, ≤ 1 active, ~11% duty | skipped (garnish ladder) |
| Wave-broken streak | 12 quads vs old 18-vert fan | unchanged (was already core) |
| Passing lantern | 18 verts, ~0.7% duty | skipped (garnish ladder) |

Frozen v3/C1/C2 fixes verified untouched: water-mask band math, ray-elevation curvature
warp, `VoyageOffset` stream, smoothed zenith direction + disc quad, mirror-locked streak
basis, ship drift/reseed determinism, all §3.3-frozen uniform names.
