# FX Team GRADE — post-pipeline upgrade log (planner → ideators → polishers)

Cluster: `eclipse:world_grade`, `eclipse:ghost_grade`, `eclipse:sun_halo`,
`eclipse:altar_aberration` — fsh/json under `assets/eclipse/pinwheel/`, binders in
`veilfx/` (`VeilPostController`) plus `client/GhostGradeFx`, `client/AltarAberration`.

Ground rules honored throughout:

- Every pre-existing uniform keeps its name, type and semantics; every NEW uniform lands
  in the same commit as its Java feeder (the §3.3 frozen set is extended additively, never
  changed — the additive precedent is limbo v3's C1 uniform set).
- `reducedFx` gates every animated/pulsing addition through a CPU-fed `Detail` uniform
  (0 under reducedFx, 1 otherwise — the `CurveAmount` pattern from `LimboAmbience`); the
  readability-critical grade cores stay on in both modes.
- Validation after every pass: `glslangValidator` on the Veil-preprocessing-emulated
  assembly (`#version` header + `eclipse:eclipse_common` resolved — the VFXPOLISH-1
  harness), `javac --release 21` against the cached moddev merged-jar + Veil 4.3.0
  classpath for every touched binder.

---

## 1. eclipse:world_grade

### PLAN

Job: the consolidated night/eclipse grade — crushes the FINAL frame so darkness defeats
user gamma (the R3 "sky never darkens" fix). Players see it every night and through every
eclipse phase; it is the single most-seen pass in the mod. Emotional target: the eclipse
as a LIVING PRESSURE — the dark should feel like weather leaning on you, not like a
brightness slider. Current weaknesses (from code read): the grade is completely static
(zero time input — a paused screenshot is indistinguishable from gameplay), the deep
crush + exposure dip produces visible 8-bit banding on smooth sky gradients with nothing
to mask it, the frame darkens uniformly (no radial pressure, nothing breathes with
EclipseAmount), and the sky is one flat dim (no horizon depth cue — the dome reads as a
ceiling, not a world edge).

### IDEATE

1. **Animated film grain, shadow-masked** — `efxHash` grain re-seeded at ~18 fps (film
   cadence, not per-frame TV static), strongest in the crushed shadows and near-zero on
   highlights, scaled by the crush amount so plain day stays perfectly clean. Doubles as
   the banding mask exactly where the crush creates banding.
2. **Radial darkening that breathes with EclipseAmount** — a soft corner vignette whose
   static part rides the crush and whose slow (~14 s period) breathing amplitude rides
   EclipseAmount: totality visibly "inhales". Keep corner loss subtle (readability).
3. **Horizon tint band** — a dusky magenta-violet band hugging the world horizon on sky
   pixels. CPU projects the true horizon line (a point at camera height 4 km along the
   horizontal forward, through the exact SunTracker frame matrices) into a new `HorizonY`
   uniform, so the band tracks pitch/bobbing perfectly and costs one uniform.
4. **Split-tone color depth** — shadows pulled cool violet-blue, highlights faintly warm
   rose, multiplicative (never lifts blacks, never clips whites), scaled by crush: color
   depth without touching the tuned 0.196 totality mid-gray.
5. **Output dither** — ±0.5/255 hash dither on the final value, always on (including
   reducedFx): kills the remaining quantization banding for free.
6. **Sky "pressure waves"** — ultra-low-frequency drifting noise (±2%) over sky pixels
   only during eclipse, so the dome itself seems to seethe. (Deferred to pass 2 as the
   secondary detail layer candidate.)
7. Depth-graded fog crush (crush grows with scene depth) — REJECTED: fights the fog
   system's own color pipeline and risks re-introducing the R3 over-darkness trap.

New uniforms (with binder, same commit): `Time` (hour-wrap seconds, limbo clock pattern),
`HorizonY` (NDC y of the horizon, ±10 park while unprojectable), `Detail` (reducedFx
gate). Fed from `VeilPostController.feedWorldGrade`.

### IMPLEMENT (pass 1)

Implemented ideas 1–5. Order of operations: crush → violet desat → split-tone → sky dim →
horizon band → breathing vignette → exposure → grain+dither (grain after the exposure mul
so it survives — and masks — the darkest totality frames). `VeilPostController` gained
the three uniform feeds plus `horizonNdcY()` (projects through `SunTracker.worldToNdc`;
one small `Vec3` per frame — the `LimboAmbience.zenithWorldPoint` precedent).

### POLISH PASS 2 (fresh-eyes art director)

- The horizon band was a hard sky-only mask — it clipped to zero at the sea/terrain
  silhouette, drawing a bright line ABOVE distant hills and reading as a sticker. Now the
  band also spills 35% onto far geometry (depth > 0.998) so it melts over the silhouette.
- Breathing was a pure sine — too metronomic for "weather". Added a second incommensurate
  sine (0.44 + 0.31 rad/s) so the inhale timing never quite repeats.
- Split-tone highlight rose was fighting the violet desat at totality (muddy ochre cast
  on torchlight); highlight tint now eases off with EclipseAmount and stays for plain
  nights (where torchlight warmth is the point).
- Added the secondary detail layer (idea 6): sky seethe — one extra `efxNoise` octave,
  ±2% luminance, ~40 s drift, sky pixels only, scaled by `EclipseAmount * Detail`.
- Grain got a luma knee (`smoothstep(0.0, 0.45, luma)` inverse) instead of a linear mask
  so mid-tones keep a whisper of texture instead of a hard clean/dirty boundary.
- Vignette coefficients re-derived against the ACTUAL corner distance (d ≈ 0.707, where
  the smoothstep reaches ~0.65) instead of the offscreen saturation point — the first
  sizing read ~40% weaker on screen than on paper. Totality corners now swing ~7→11%
  with the breath; plain night sits at a gentle ~4%.

### POLISH PASS 3 (micro-pass)

- **Driver-safety bug caught**: the horizon band used `pow(base, 2.0)` with a SIGNED
  base — `pow` is undefined for negative bases in GLSL (fine on some drivers, NaN on
  others). Replaced with explicit `h*h`. glslang does not flag this; it would have been
  a "black band on some GPUs" field bug.
- Banding: grain clock quantization (`floor(Time*18)`) fed the hash directly with big
  numbers (precision loss near the hour wrap) — now wrapped `mod(..., 289.0)` before the
  hash, matching the hash's stable range.
- reducedFx degradation re-checked: grain, breathing amplitude, and sky seethe all die
  with `Detail`; static vignette, band, split-tone and dither stay (non-pulsing by
  definition). Verified no `Time` term survives `Detail = 0` except the ±1/255 dither
  reseed, which is sub-perceptual by construction.
- Performance: worst case adds 2 `efxHash` + 1 `efxNoise` + arithmetic — no new texture
  taps beyond the existing 2. Fine for a fullscreen GRADE pass.
- Cleanup: hoisted the shared `screenPx` computation, named the magic breathing
  frequencies, comment-tagged each layer with its ideation number.
- `glslangValidator` clean; `VeilPostController` javac clean.

**world_grade across 3 passes:** static gamma-crush → living pressure: shadow-masked
film grain + double-sine breathing vignette + true-horizon dusk band + split-tone depth +
sky seethe + output dither, all reducedFx-gated via `Detail`, readability caps intact.

---

## 2. eclipse:ghost_grade

### PLAN

Job: the 0-lives spectral grade — the whole world through dead eyes, active for however
long a run's ghost phase lasts (can be many minutes of continuous viewing, so it must be
beautiful, not merely gray). Emotional target: hauntingly beautiful — loss with a memory
of what mattered. Current weaknesses (code read): the recipe is a monolithic single
scalar — desat, lift, cast and vignette all throb together on the CPU breath (nothing
has independent life); the desat is hue-blind (the eclipse sun and altar glow gray out
with the dirt — the one thing a ghost should still SEE); no spectral detail of any kind;
the CPU breath is a pulsing overlay yet is NOT reducedFx-gated (a genuine gap); the lift
raises blacks into the banding-prone range with no dither.

### IDEATE

1. **Violet memory-color highlights** — hue-selective desat: a violet/magenta chroma
   mask (bright pixels only) resists up to 85% of the graying and keeps a touch of
   re-saturation. The eclipse is the last thing a ghost remembers.
2. **Spectral edge shimmer** — one-sided luma-gradient edge field (2 extra taps) catches
   a noise-drifting cold violet-white glint: the world as a remembered outline.
3. **Heartbeat-adjacent vignette pulse** — a lub-dub double gaussian at ~32 bpm
   (heartbeat-ADJACENT: far too slow to be alive) breathing +3.5% on the 12% vignette.
4. **reducedFx-gate the CPU breath** — the ±4% Ghost-scalar throb flattens under
   reducedFx (the eased grade itself stays: state feedback, not decoration).
5. **Void sky** — depth-masked pull of the dome toward deep violet-black; ghosts look up
   into nothing. Static, so it survives reducedFx.
6. **Ectoplasmic UV drift** (slow large-scale warp making the world swim) — REJECTED:
   motion-sickness risk on a grade that can stay on for minutes.
7. **Lucidity window** (reduced desat at screen center) — REJECTED: fights idea 1 (the
   memory mask already gives the eye selective anchors; two competing masks read muddy).

New uniforms (with binder, same commit): `Time` (pause-frozen — derived from the
feeder's existing pause-gated breath tick counter, hour wrap), `Detail` (reducedFx
gate). `DiffuseDepthSampler` newly bound (Veil blit convention, not CPU-fed).

### IMPLEMENT (pass 1)

Ideas 1–4: memory mask (`violetness = chroma.b·1.2 + chroma.r·0.4 − chroma.g·1.6`,
gated by a 0.18..0.55 luma knee so only HIGHLIGHTS remember), edge shimmer, heartbeat
vignette, and the `GhostGradeFx` feeder changes (breath flattened under reducedFx +
`Time`/`Detail` feeds). Order: fringe → edge field → memory desat → lift/cast →
shimmer → heartbeat vignette.

### POLISH PASS 2 (fresh-eyes art director)

- The memory re-saturation (`graded += chroma · memory`) could push green NEGATIVE on
  strongly violet pixels (violet chroma has negative g) and poison every multiplicative
  stage after it — clamped at zero.
- Edge shimmer read as highlight bloom on bright-over-dark edges; now weighted to the
  DARK side (`× (1 − lumaC·0.6)`) so it reads as spectral rim light instead.
- Added the secondary detail layer (idea 5): void sky — depth-masked 45% pull toward a
  deep violet void with a tiny violet floor, placed before the shimmer so silhouette
  glints ride over the sky boundary. Deliberately composes with world_grade's night
  dim (both GRADE passes run together at night; the double-darkening is the point).

### POLISH PASS 3 (micro-pass)

- Output dither ±0.5/255 added (the lift + vignette gradients band in the dark range);
  kept under reducedFx — it is a correctness layer, not decoration.
- Heartbeat gaussians use explicit squares (`(p−c)·(p−c)`), never `pow` — the world_grade
  pass-3 lesson applied family-wide.
- `Time` wrap verified hour-safe (int modulo BEFORE the float divide — no precision
  cliff after long sessions); pause-freeze verified (breath ticks only advance unpaused).
- reducedFx audit: shimmer and heartbeat die with `Detail`; CPU breath flattens; memory
  mask, void sky, lift, cast, fringe, static 12% vignette stay. Grade core intact.
- Performance: 7 texture taps + 1 noise + 1 hash worst case, ghost-state only. Fine.
- `glslangValidator` clean; `GhostGradeFx` javac clean (jar-classpath harness — see
  footnote at the end of this file).

**ghost_grade across 3 passes:** monolithic gray throb → haunting memory: hue-selective
violet memory highlights + dark-side spectral edge shimmer + ~32 bpm lub-dub vignette +
void sky + dither, breath finally reducedFx-flattened, frozen Ghost semantics untouched.

---

## 3. eclipse:sun_halo

### PLAN

Job: the purple sun's screen-space halo around the CPU-projected `SunScreen` point (the
R2 alignment fix) — visible all day every day at the 0.15 permanent-rim floor, and the
main event during eclipse buildup/totality. Emotional target: VOLUMETRIC — a body of
violet gas around a star, not a radial-gradient decal. Current weaknesses (code read):
one exp glow + one rim = zero optical structure; occlusion is double-binary (one depth
step OR a binary CPU flag → the glow POPS when walking behind a tree line); nothing
moves, ever; the tint is one flat vec3 across rim and glow; the exp gradient bands
visibly on dark skies.

### IDEATE

1. **Multi-ring diffraction corona** — three gaussian rings (2.2/3.6/5.4 × sunRadius),
   spread widening slightly with HaloStrength, spectral progression violet-white →
   magenta → deep blue-violet, weights fading outward.
2. **Anamorphic streak option** — thin horizontal violet-white streak (gaussian in y,
   exponential in x), gated to high-strength moments (`smoothstep(0.55, 0.90,
   HaloStrength)` — i.e. the eclipse boost) and off under reducedFx; screen-edge fade so
   it never hard-clips.
3. **Occlusion-aware fade, both halves** — shader: 5-tap depth probe around the sun
   point → a visibility FRACTION (partial cover by leaves dims proportionally); CPU:
   `RimOnly` becomes a ~6-tick eased 0..1 (`VeilPostController.tickSunOcclusionEase`) —
   semantics only widened, the shader always clamped it.
4. **Azimuthal shimmer** — ring intensity breathing around the circle (6-fold, slow
   rotation): living diffraction. reducedFx-gated.
5. **Chromatic glow dispersion** — per-channel glow radii (r reaches 7% further, g 7%
   shorter): magenta skirt, violet-white core. Free (pure math).
6. **Halo-local dither** — hash dither scaled by halo luminance only (never touches the
   rest of the frame).
7. **Volumetric radius breath** — ±3% glow radius on an incommensurate double sine.
8. Screen-space crepuscular rays from the sun point — REJECTED: the limbo pass owns the
   god-ray look (12-tap loop), and a second ray look on the overworld sun would read as
   a reskin AND double the tap budget of a pass that runs all day.

New uniforms (with binder, same commit): `Time` (hour-wrap), `Detail` (reducedFx gate).

### IMPLEMENT (pass 1)

Ideas 1–6. `VeilPostController`: `easedRimOnly` slew (0.18/tick) hooked into the
existing client tick, `Time`/`Detail` feeds, `RimOnly` now fed eased.

### POLISH PASS 2 (fresh-eyes art director)

- Verified the ring stack against the day floor: at HaloStrength 0.15 the rings land at
  ~0.03 additive — a ghost of structure around the everyday sun; at the 1.35 totality
  boost they peak ~0.28 — the drama beat owns them. No retune needed.
- Cleaned a restructuring artifact in the halo accumulation (a dead `dot(glow3, vec3(0))`
  term left from splitting rim/glow tinting).
- Added the secondary detail layer (idea 7): volumetric radius breath, ±3% double-sine
  on the glow radius — the single change that most sells "gas, not decal".

### POLISH PASS 3 (micro-pass)

- `atan(0, 0)` is undefined in GLSL and the exact sun-center pixel hits it — epsilon on
  the x argument (NaN there would have propagated through the ring shimmer).
- Ring gaussians use explicit `-h·h` exponent form (no negative-base `pow` anywhere in
  the family after this pass).
- Occlusion path re-checked end to end: 5-tap fraction (0/0.2/…/1) → `max` with eased
  CPU flag → rim dims to 0.35, glow fades on a 0.10..0.85 smoothstep. A sapling leaf
  layer now costs ~20% glow instead of 100%.
- reducedFx: streak, shimmer and breath die with `Detail`; rings, dispersion glow, soft
  occlusion and dither stay (static structure + correctness layers).
- Performance: 7 taps worst case (was 3) — acceptable for a FEATURE pass that is
  overworld-day-only; no loops, no matrix work.
- `glslangValidator` clean; `VeilPostController` javac clean.

**sun_halo across 3 passes:** flat decal glow → volumetric corona: 3-ring spectral
diffraction + eased two-stage occlusion fade + chromatic dispersion + gated anamorphic
streak + radius breath + halo-local dither; frozen uniform names/semantics preserved
(RimOnly widened binary→eased, always-clamped).

---

## 4. eclipse:altar_aberration

### PLAN

Job: the "reality is not normal here" lens gradient around the altar — active whenever a
player is inside the spawn-disc zone, which is where every offering, level-up and
ceremony happens. Emotional target: SACRED-TECH — an ancient machine bending light, not
a broken monitor. Current weaknesses (code read): it is a pure passive lens (nothing in
it ever RESPONDS — yet the altar is exactly where level-ups fire); the RGB split is one
hard tap per channel (a double-image, not a prismatic smear, once the split passes a few
px); the CPU 0.3 Hz breath is not reducedFx-gated (same gap ghost_grade had); no
level-up uniform exists; no dither under the violet lift/ring-scale gradients.

### IDEATE

1. **Glyph-flash ghosting on level-ups** — no uniform exists, so add `GlyphFlash` WITH
   its binder: `AltarAberration` watches the same `ClientStateCache.skillLevel` state as
   `LevelUpOverlay` with the same seeding rules (login sync seeds silently, downward
   admin-set re-seeds without theater), arms a 16-tick envelope, and respects
   `levelUpCelebrations` + `reducedFx` exactly like the overlay. Shader: a rotated
   (~3°) contracted (~4.5%) luma-weighted violet echo of the scene + a brief 5% lift.
2. **Resonance rings** — slow concentric interference crawling INWARD toward the altar
   (±2% luminance, donut-masked so crosshair and edges stay clean): the zone hums.
3. **Two-tap prismatic split** — half-strength second tap per channel: spectral smear
   instead of hard double-image at high strengths.
4. **reducedFx-flatten the CPU breath** — to its MEAN (0.9), not to 1.0: same average
   zone strength, no pulse.
5. **Split-direction micro-torque** (rotating the split axis near center) — REJECTED:
   even small rotational shear on a persistent zone effect is a nausea risk (the R9
   "never nauseating" guarantee outranks the idea).
6. **Time-jittered split strength** — REJECTED, same guarantee.
7. **Output dither** — the ring modulation and violet lift write long smooth gradients.

New uniforms (with binder, same commit): `Time` (the feeder's existing 100 s wrap clock,
shared with the breath), `GlyphFlash` (0..1 envelope), `Detail` (reducedFx gate — rings;
the split/barrel core is zone feedback and stays, the flash is already CPU-gated).

### IMPLEMENT (pass 1)

Ideas 1–4 + 7. Binder: `tickGlyphFlash` (seed/increase/downward rules, pause-frozen
drain), `glyphFlash()` envelope (instant pop, smoothstep ease-out — a flash IS a pop),
breath flatten, three new uniform feeds.

### POLISH PASS 2 (fresh-eyes art director)

- **Regression caught**: the two-tap smear moved the split CENTROID to 0.8× — quietly
  re-breaking the VFXPOLISH-1 rim-visibility fix (the whole reason `aResp` exists).
  Retuned to `split = 0.0145`, mix weight 0.35: centroid ≈ 0.012 (the tuned value), so
  rim visibility AND the ~10 px center cap both hold with the smear on top.
- Added the secondary detail layer: **flash→ring coupling** — a live glyph flash surges
  the ring amplitude (0.02 → 0.05) and lifts the ring floor via `max(aResp, gf·0.5)`,
  so a level-up at the zone rim briefly summons the hum. The two new layers read as one
  mechanism instead of two overlays.

### POLISH PASS 3 (micro-pass)

- Envelope easing verified: smoothstep drain over 16 ticks, pause-frozen (the drain
  checks `isPaused`), partial-tick interpolated in the feeder — no 20 Hz stepping.
- Ring wavelength sanity: ~4 rings in the donut band (0.08..0.72 aspect-corrected rr),
  one wavelength per ~4.8 s — a crawl, not a strobe.
- Echo UV clamped (rotation near corners can leave [0,1]); no negative-base `pow`
  anywhere; dither reseed prime (89) deliberately different from the grade passes (97)
  so the two dither fields can never correlate when stacked.
- reducedFx audit: rings dead via `Detail`, flash dead via CPU gate, breath flattened
  to mean, split/barrel/violet core intact (zone feedback, R9).
- Performance: 5 taps + 1 conditional echo tap + 1 hash (was 3 taps). FEATURE pass,
  zone-local. Fine.
- `glslangValidator` clean; `AltarAberration` javac clean.

**altar_aberration across 3 passes:** passive lens → sacred-tech instrument: level-up
glyph-flash ghosting (new GlyphFlash uniform + binder, LevelUpOverlay-mirrored gating) +
inward-crawling resonance rings with flash coupling + prismatic two-tap smear
(centroid-preserving retune) + mean-flattened reducedFx breath + dither.

---

## Validation footnote (whole cluster)

- Shaders: all 4 assembled with the Veil-preprocessing emulation (`#version 450 core`
  header + `#include eclipse:eclipse_common` textually resolved) and compiled with
  `glslangValidator -S frag` — clean after every pass.
- Java: `VeilPostController`, `GhostGradeFx`, `AltarAberration` compiled with
  `javac --release 21 -proc:none -implicit:none` against `build/libs/eclipse-2.1.0.jar`
  + the moddev merged NeoForge 21.1.238 jar + Veil 4.3.0 + GeckoLib 4.9.2 +
  voicechat-api 2.6.20 + `build/moddev/clientLegacyClasspath.txt` — exit 0. (The
  `-sourcepath` harness variant is currently unusable tree-wide: `stormfx/
  StormWallRenderer.java` calls four methods that do not exist — `emitExplosionShards`,
  `emitClearSkyRing`, `emitTyrantSilhouette`, `explodeRadiusScale` — a PRE-EXISTING
  breakage outside this cluster's scope, flagged here for the storm team.)
- Uniform feed ↔ declaration audit re-run after the work: every declared uniform in the
  4 shaders is fed by its binder and consumed by the shader body; no orphans in either
  direction (`DiffuseSampler0`/`DiffuseDepthSampler` remain Veil-bound conventions).
- No pipeline/post JSON changes needed (all four stay single-stage `veil:blit`
  `minecraft:main → veil:post`); no §3.3 frozen name touched; gradle/git untouched per
  the team charter.
