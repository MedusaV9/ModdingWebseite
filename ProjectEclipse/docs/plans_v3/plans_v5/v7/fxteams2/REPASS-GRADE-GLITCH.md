# REPASS-GRADE-GLITCH — VEIL-REPASS-1 fresh-eyes second polish (post-v6)

Team log. Scope: the eight post pipelines `world_grade`, `ghost_grade`, `sun_halo`,
`altar_aberration`, `border_glitch`, `rift_glitch`, `shockwave`, `xbox_era` (fsh + json +
Java binders). Prior team logs: `plans_v5/fxteams/GRADE.md` + `GLITCH.md` (v6); the
reverse-smoothstep/NaN fix wave is `plans_v5/AUDIT-v7.md`. Process per effect, full team
law: **re-PLAN** (fresh eyes) → **IDEATE** (6+ ideas NOT in the v6 logs) → **IMPLEMENT**
(the best) → **POLISH PASS 2** (fresh-eyes re-review) → **POLISH PASS 3** (reducedFx /
photosensitivity / contract audit). Frozen uniform contracts untouched; every new uniform
is additive with its Java feeder in the same commit (the limbo-v3 / Kick / RiftCenter
precedent — Veil pipeline JSONs declare no uniforms, confirmed against every existing
pipeline JSON, so fsh + binder is the complete wiring).

Self-checks: `glslangValidator -S frag` on a Veil-preamble composite (`#version 410 core`
+ `eclipse_common.glsl` spliced in place of the `#include`) for all 8 shaders, and `javac`
(`-proc:none`, moddev neoforge-21.1.238 classpath + veil/geckolib/voicechat-api jars +
`build/classes/java/main`) for the 4 modified binders. NO gradle, NO git.

## Cluster-wide VERIFY (fix wave still holds)

Re-checked every descending ramp and degenerate-input site in the 8 shaders before
touching anything:

| Site | Law | Verdict |
| --- | --- | --- |
| `sun_halo` rim ramps | descending ramps written `1.0 - smoothstep(lo, hi, x)` | ✔ (2 sites) |
| `sun_halo` `atan(delta.y, delta.x + 1e-6)` | azimuth defined at sun center | ✔ |
| `world_grade` horizon band | `exp(-h*h)`, never `pow(negative, 2.0)` | ✔ |
| `ghost_grade` heartbeat | squares by multiplication, not `pow` | ✔ |
| `ghost_grade` `normalize(fromCenter + 1e-5)` | chroma dir defined at center pixel | ✔ |
| `rift_glitch` shard branch | `if (shardZone > 0.003 && lensDist > 1e-4)` NaN guard | ✔ |
| `shockwave` `dir` | `dist > 1e-4 ? delta/dist : vec2(0)` | ✔ |
| `border_glitch` `tearDir` | `tearLen > 1e-4` guard | ✔ |

All new v3/v4 layers below were written to the same laws (the new spiral branch reuses
the shard guard pattern; the new sparkle uses `normalize(delta + 1e-5)`; every new ramp
is ascending or `1 - smoothstep`).

## 1. eclipse:world_grade — phase color script + clarity

### re-PLAN
v6 gave the night pressure (grain/breath/band/split-tone/seethe). Fresh eyes: the grade
is *timeless* — a 6 pm dusk and a 5 am pre-dawn render identically, and the crush
flattens texture into mud at high strength. The night needs a color SCRIPT (time has a
direction) and local depth.

### IDEATE (new, not in GRADE.md)
1. **[r1] signed phase color script** — one `PhaseTint` uniform in [−1, 1]: dusk/eclipse
   BUILDUP lean ember-magenta (light being taken), dawn/ENDING lean cool rose (light
   given back). **CHOSEN** (mandate frontier).
2. **[r2] micro-contrast "clarity"** — 4-tap diagonal luma unsharp, mid-tone weighted,
   crush-scaled. **CHOSEN** (mandate frontier).
3. Star-twinkle boost on sky pixels — REJECTED: a grade must not invent geometry; sky
   content belongs to the sky renderers.
4. Depth-graded fog tint — REJECTED: non-linear depth + fog is owned by dimension
   effects; double-authoring risk.
5. Left/right temperature split during BUILDUP — REJECTED: gimmick; violates
   "corruption is a texture, not a color filter".
6. Moon-position counter-glow — REJECTED: a second CPU projection feed for a
   whisper-level term; cost/benefit fails.
7. Breath-synced grain amplitude — REJECTED: grain doubles as the banding mask and must
   stay constant-energy.

### IMPLEMENT
`world_grade.fsh`: new additive uniform `PhaseTint`; [r1] leans the violet desat target
and the horizon band color (`dusk = max(-PhaseTint,0)`, `dawn = max(PhaseTint,0)` —
mutually exclusive by construction); [r2] clarity samples 4 diagonals (~1.2 px) of the
RAW frame pre-crush, applies the luma-only gain AFTER the crush (mid-tone window
`smoothstep(0.05,0.20) · (1−smoothstep(0.55,0.85))`, swing clamped ±5.4% · crush).
`VeilPostController`: feeds `PhaseTint = clamp(dayTint + easedPhaseLean, −1, 1)` — the
overworld sun-elevation edge (smoothstepped `1 − |cos angle|/0.30`, signed by the
setting/rising half of the cycle) plus a 0.025/tick slewed eclipse-phase lean (BUILDUP
−0.6, ENDING +0.6); both inputs continuous, so the script can never pop. Lean reset in
`onLoggingOut`.

### POLISH PASS 2 (fresh-eyes re-review) — 1 fix
The dawn tint target `(0.88, 0.68, 1.04)` sat at Rec.601 luma 0.781 vs the base violet's
0.7345 — ~6% hot at full lean, contradicting the "hue-only, crush owns brightness"
contract and nudging the tuned totality mid-gray. **Renormalized both leans**: dusk
`(0.98, 0.58, 0.90)` (Δluma +0.2%), dawn `(0.84, 0.64, 0.95)` (Δluma +0.09%). Comment now
states the 0.734–0.736 luma law explicitly.

### POLISH PASS 3 (audit)
[r1] and [r2] are static state feedback → deliberately NOT `Detail`-gated (same class as
the grade core; nothing pulses). Clarity cannot amplify grain: it samples the raw frame
before grain exists. Photosensitivity: no new animated term. Cost: +4 texture taps.

## 2. eclipse:ghost_grade — soul-echo double vision

### re-PLAN
v6 gave memory color, shimmer, heartbeat, void sky. Fresh eyes: the ghost still sees ONE
world. Death should leave a seam between the ghost and the image itself.

### IDEATE (new, not in GRADE.md)
1. **[g5] soul-echo double vision** — one offset tap max()-screened in as a violet copy
   at 2% mix, drifting sub-pixel on a ~10 s noise walk. **CHOSEN** (mandate, "subtle!").
2. Edge aura on OTHER ghosts — **ASSESSED, SKIPPED** (mandate pre-authorized): the pass
   is a single-stage `veil:blit`; only color + depth buffers exist, no entity/stencil
   mask, and faking one from depth halos every silhouette.
3. Depth-parallax echo — REJECTED: a depth-driven offset swims with camera motion;
   comfort risk on a grade that stays on for minutes.
4. Whisper glyphs in deep shadow — REJECTED: readable content is HUD territory.
5. Desat pulse on the heartbeat — REJECTED: the heartbeat owns the vignette; a second
   synced channel makes it a metronome.
6. Inverted-luma peripheral flicker — REJECTED: photosensitivity red line.
7. Memory-mask bloom — REJECTED: needs a blur chain that roughly doubles pass cost for
   a subliminal term.

### IMPLEMENT
`ghost_grade.fsh` [g5]: echo tap at ~0.45% frame height offset, tinted
`(0.62, 0.56, 0.92) · luma`, screened via `max()` (undecayed-exposure read), mix
`0.02 · smoothstep(0.20, 0.60, echoLuma) · ghost · Detail` — highlights only (dark has
nothing to echo). Offset x walks ±0.075% on `efxNoise(Time · 0.10)`. No new uniforms
(rides the existing v2 `Time`/`Detail`).

### POLISH PASS 2 — 1 real bug found and fixed
The echo sampled at **+y**: the echo at pixel P shows scene content from P + off, i.e.
the copy renders BELOW the true image — upside-down against the "souls rise" intent
(texCoord y is up, GL convention; cross-checked against `world_grade`'s
`ndcY = texCoord.y * 2 − 1` horizon math). **Flipped the offset sign** (sample −y →
copy hovers above) and documented the sampling direction law in the comment.

### POLISH PASS 3 (audit)
`Detail`-gated (double vision on a minutes-long grade is a comfort risk → dead under
reducedFx). 2% mix at 0.1 Hz drift: zero photosensitivity budget. Cost: +1 tap.

## 3. eclipse:sun_halo — anamorphic evolution + altar temperature

### re-PLAN
v6 gave rings/streak/occlusion/shimmer/dispersion/breath. Fresh eyes: the streak is
binary (gate on/off, fixed reach) and the halo ignores the player's altar progress — the
sky's centerpiece should register the campaign.

### IDEATE (new, not in GRADE.md)
1. **[s8] occlusion-aware anamorphic evolution** — streak reach grows with strength past
   the gate AND collapses with occlusion. **CHOSEN** (mandate frontier).
2. **[s9] altar-level temperature shift** — `AltarWarmth` uniform from
   `ClientStateCache.altarLevel` (wiring confirmed: synced field, `clamp(·,0,5)/5` is the
   established client ladder normalization used by AltarVeilSky/AltarIdleMotes).
   **CHOSEN** (mandate frontier).
3. Lens-ghost counter-flare — REJECTED (re-affirming the v6 spirit): the eclipse is an
   eye, not a camera.
4. Ray-marched crepuscular shafts — REJECTED: per-pixel depth march; budget.
5. Halo phase hue script — REJECTED: `PhaseTint` belongs to `world_grade`; two scripts
   fighting on the same pixels.
6. Diffraction spike star — REJECTED: wrong iconography for this sun.
7. Low-sun vertical streak — REJECTED: anamorphic is horizontal by definition.

### IMPLEMENT
`sun_halo.fsh`: [s8] `streakReach = glowRadius · (2.0 + 1.5·smoothstep(0.55, 1.30,
HaloStrength)) · (0.35 + 0.65·glowVis)` — totality stretches the streak ~1.75×, partial
cover shortens it to a stub at the disc (geometry now agrees with the glowVis brightness
fade). [s9] new additive uniform `AltarWarmth`; halo/streak tints mix ≤45% toward hotter
magenta-violet — never gold (style guide reserves gold for reward beats; this pass is
ambient). `VeilPostController.feedSunHalo` feeds the normalized ladder.

### POLISH PASS 2 — verified, no change
Re-derived the exp-argument floor: `streakReach ≥ 0.12 · 2.0 · 0.35 = 0.084` NDC > 0, so
`exp(-|Δx|/streakReach)` is always finite. Confirmed [s9] is static state feedback
(survives reducedFx like the rings) and the ≤45% mix keeps both endpoints inside the
violet family.

### POLISH PASS 3 (audit)
Streak still `Detail`-gated (v6 law); [s8] changes only its shape. `AltarWarmth` is
CPU-clamped 0..1. No new animated terms; cost: pure ALU, no new taps.

## 4. eclipse:altar_aberration — micro-prism sparkle

### re-PLAN
v6 gave the glyph-flash echo + resonance rings + prismatic split. Fresh eyes: the flash
is an echo of light, but the LENS never resolves that light into color — the one moment
the aberration fantasy could pay off literally.

### IDEATE (new, not in GRADE.md)
1. **[a4] micro-prism sparkle on the glyph flash** — sparse glints refracting into
   miniature spectra along the radial split axis. **CHOSEN** (mandate frontier).
2. Sparkle motion trails — REJECTED: attention theft at a moment LevelUpOverlay owns.
3. Zone-edge lensing ring — REJECTED: barrel already owns geometry.
4. Always-on sparkle at zone center — REJECTED: sparkle is a reward accent, not
   ambience ("loud moments" pillar).
5. Split-axis rotation during the flash — REJECTED: rotating the aberration axis is a
   nausea vector.
6. Flash afterimage decay — REJECTED: [a1] IS the afterimage; double-authoring.
7. HUD chromatic fringing — REJECTED: the post pass must not know about HUD.

### IMPLEMENT
`altar_aberration.fsh` [a4], inside the existing `gf > 0.001` branch: 9-px cell grid,
~0.3% of cells armed per ~10 Hz roll (`step(0.997, hash)`), one 2-px gaussian glint per
armed cell, hue dispersed along the radial split axis via a cos-palette
(`0.5 + 0.5·cos(2π(hue + (0, ⅓, ⅔)))`), highlight-weighted
(`smoothstep(0.22, 0.55, luma)` — glints need light to refract), donut-masked with the
rings (aim point + edges stay clean), amplitude ≤ 0.26·gf. No new uniforms.

### POLISH PASS 2 — verified, no change
Density math: ~28 800 cells at 1080p × 0.3% ≈ 86 live glints per roll — sparse, reads as
glitter not snow. `normalize(delta + 1e-5)` keeps the radial axis defined on the center
pixel (donut mask already zeroes it there; the guard is for NaN propagation only).

### POLISH PASS 3 (audit)
Everything rides `gf`, which the binder arms only under `levelUpCelebrations() &&
!reducedFx()` (verified in `AltarAberration.tickGlyphFlash`) — the sparkle is dead under
reducedFx by inheritance. Photosensitivity: tiny local glints, no full-field modulation,
0.8 s one-shot. Cost inside the flash branch only.

## 5. eclipse:border_glitch — impact frame tear

### re-PLAN
v6 gave the kick (desync burst + quantized pull surge + invert eligibility). Fresh eyes:
the kick is loud but the IMPACT INSTANT itself has no unique signature — the shove
deserves one frame where the border owns every pixel.

### IDEATE (new, not in GLITCH.md)
1. **[1d] 2-frame full-screen tear at impact** — the frame shears in two along a
   seed-rolled line for the first ~35 ms. **CHOSEN** (mandate frontier).
2. Tear-seam luminance glow — REJECTED: adds a flash to the impact; the tear stays
   displacement-only so the photosensitivity budget is untouched.
3. Frame-hold stutter — REJECTED: needs a history buffer; single-blit pipeline.
4. Kick-synced datamosh cell-size jump — REJECTED: the cell relayout already pops with
   `frameSeed`; a second pop source reads as a rendering error.
5. Diagonal tear variants — REJECTED: horizontal reads "signal tear", diagonal reads
   "broken shader".
6. Double tear (two lines) — REJECTED: three shearing strips are unparseable in 35 ms.
7. Audio-amplitude-reactive grain — REJECTED: no audio uniform; AV sync is already
   solved by the shared prox² law (v6).

### IMPLEMENT
`border_glitch.fsh` [1d], inside the existing `kick > 0.003` branch: `impact =
smoothstep(0.85, 0.97, kick)` — the quadratic 420 ms decay puts `kick > 0.85` at exactly
the first ~33 ms (≈2 frames at 60 fps). Halves split at `tearLine = 0.25 +
0.5·hash(seed)`, shearing opposite directions along `tearUv` at ±0.030 UV. No new
uniforms (rides the v3 `Kick`).

### POLISH PASS 2 — verified, no change
`tearLine` hashes the SEED, not Time — the line cannot jitter within the pulse (the two
frames tear at the same place; re-rolls only with the world-patch reseed). Re-derived
the window: `(1−t)² > 0.85 ⇔ t < 7.8% · 420 ms ≈ 33 ms`. The final `uv` clamp already
bounds the shear at frame edges.

### POLISH PASS 3 (audit)
`Kick` is fed 0 under reducedFx at the trigger site (verified in
`BorderFxRenderer.kickValue` + rising-edge suppression) — the whole branch is dead there.
Displacement-only: no luminance/invert added at impact (the existing invert-pop
eligibility during kicks is unchanged v6 behavior).

## 6. eclipse:rift_glitch — quantized spiral warp

### re-PLAN
v6 gave voxel-sort streaks, mirror shards, time-jitter echo — and REJECTED a "slow UV
swirl" (water/portal cliché that fights the shards). Fresh eyes: the ambition behind
that rejection was right — near the tear, space should be WOUND — the execution was
wrong. Re-answer it inside the glitch grammar.

### IDEATE (new, not in GLITCH.md)
1. **[v3] QUANTIZED spiral warp** — the twist snaps in ~2° angular steps, is static in
   time, and stays at sub-shard amplitude. **CHOSEN** — both v6 objections addressed:
   nothing flows (discrete shear rings = glitch snap), nothing rotates over time (angle
   tracks proximity only; no motion-sickness vector).
2. Continuous animated swirl — RE-REJECTED: the original objection stands.
3. Spiral-synced chroma rotation — REJECTED: the chroma axis is the displacement axis
   by v2 contract.
4. Inward particle streaks — REJECTED: world-space; RiftFx territory.
5. Shard-boundary glow lines — REJECTED: additive luminance where players stare.
6. Handedness-signed spiral direction — REJECTED: no handedness in the state payload;
   inventing one is fake data.
7. Twist breathing on Time — REJECTED: time-static is exactly what makes it comfortable.

### IMPLEMENT
`rift_glitch.fsh` [v3], between the streak and shard layers: `twistZone = (1 −
smoothstep(0.05, 0.45, lensDist)) · rift`; `spiral = twistZone² · 0.45` quantized
`floor(spiral·28)/28` (≈2.05° steps); applied as an ADDITIVE uv offset (rotation of
`fromLens` mapped back through the aspect and NDC→UV scale), so datamosh/streaks survive
underneath and gated shards still win their sectors. Guard: `twistZone > 0.003 &&
lensDist > 1e-4` (the shard-branch NaN-guard pattern; no `atan` — only cos/sin of a
bounded angle). No new uniforms (rides v2 `RiftAmount`/`RiftCenter`).

### POLISH PASS 2 — verified, no change
Max twist under the RiftAmount 0.6 cap: `twistZone ≤ 0.6 → spiral ≤ 0.36·0.45 =
0.162 rad`, quantized down to `4/28 ≈ 0.143 rad` — the "≤ ~0.16 rad" header claim holds
and the twist stays well below the shard displacement in its zone. The `(wound − p)`
offset is exactly zero at the lens center (rotation fixes the origin), so the epsilon
guard skips dead work only.

### POLISH PASS 3 (audit)
`RiftAmount` is 0 under reducedFx at the source (v2 contract) → the spiral is dead there.
Static in time; the only temporal change is proximity easing. R11 spirit intact: no new
strobe-adjacent term near a rift.

## 7. eclipse:shockwave — material-reactive ring tint

### re-PLAN
v6 gave the crisp front / dimple / double-pulse / travel attenuation. Fresh eyes: every
slam kicks the SAME colorless pressure. Real blasts carry their ground with them.
Feasibility check passed (biome color via a CPU uniform), so the mandate's "else skip"
clause was not needed.

### IDEATE (new, not in GLITCH.md)
1. **[v4] biome-reactive `ShockTint`** — feeder samples the biome grass color at the
   blast origin, desaturates 55%, luma-normalizes; the shader leans the crest (40%) and
   the inside-ring desat target (30%) toward it. **CHOSEN** (mandate frontier).
2. True hit-block palette sampling — REJECTED: needs server payload changes; frozen
   packet.
3. Dust particle ring — REJECTED: world-space; the shockwave's particle author owns it.
4. Tinting the chromatic fringe — REJECTED: the fringe is a lens artifact, not dust;
   physically the wrong layer.
5. Submerge-only vertical tint — REJECTED: the cold slate default already carries the
   underwater read.
6. Distance-based tint desat — REJECTED: over-parameterizes a 30–40% lean.
7. Weather modifiers — REJECTED: the grass-color API already folds biome state.

### IMPLEMENT
`shockwave.fsh`: new additive uniform `ShockTint` (vec3); crest
`mix(vec3(1), ShockTint, 0.4)` inside the existing ≤10% luma ride; inside-ring gray
target `mix(vec3(1), ShockTint, 0.3)`. Neutral (1,1,1) is a bit-exact no-op.
`EclipseFxState`: new `shockwaveOrigin()` getter (world origin of the live wave).
`WaveOverlay.updateShockTint`: tick-path only, one biome lookup per EVENT
(reference-identity check on the origin), 55% desat toward white, luma-normalized
(mean-brightness 1) then clamped 0.7–1.3; submerge/no-wave default is a cold slate
`(0.88, 0.95, 1.10)`-derived tint. Feeder emits the 3 cached floats — alloc-free.

### POLISH PASS 2 — verified, no change
Frozen uniforms untouched (ShockCenter/Progress/Strength semantics identical). Worst-case
luma-exactness dent from the post-normalization clamp (extreme biome greens):
~10% clamp loss × 40% lean × 10% crest = ≤0.4% of final luma — accepted. The tint is
sampled once per event, so a wave cannot color-shift mid-flight.

### POLISH PASS 3 (audit)
reducedFx path unchanged (`×0.6` strength scale; tint itself is comfort-neutral — it
recolors existing modulation, adds none). The biome lookup runs on the tick path, never
the render path.

## 8. eclipse:xbox_era — rolling scan band

### re-PLAN
v6 gave the era grade (soft resolve, gamma, bloom, LUT, vignette) and rejected scanlines.
Fresh eyes: the grade is a photograph — an era CRT filmed by a camera has exactly one
motion: the slow refresh interference band. That is a BAND, not scanlines.

### IDEATE (new, not in GLITCH.md)
1. **[v3] rolling scan band** — one soft luma wave (σ ≈ 8% frame height, ±~1.1%)
   drifting up the frame on an ~11 s loop. **CHOSEN** (mandate: "a slow vertical luma
   wave").
2. Literal scanlines — RE-REJECTED: v2 objection stands (aliasing at non-integer DPI).
3. Interlace combing on motion — REJECTED: needs motion vectors/history buffer.
4. Band-synced chroma shift — REJECTED: the band must stay luma-only to stay
   subliminal.
5. VHS dropouts — REJECTED: wrong era (component/HDMI console, not tape).
6. Boot-moment bloom flash — REJECTED: one-shot theater belongs to the dimension enter
   sequence, not a hold-state grade.
7. 50/60 Hz region toggle — REJECTED: config surface creep for a joke.

### IMPLEMENT
`xbox_era.fsh`: new additive uniform `Time`; gaussian band in wrapped frame-height
distance, rolling one frame per ~11 s (0.09 Hz), applied `graded *= 1 + (band − 0.15) ·
0.013 · amount` — the −0.15 floor makes the term near-zero-mean (the wrapped gaussian's
average is ≈0.142), so average brightness holds. Placed before the dither.
`XboxEraFx`: pause-frozen `bandTicks` clock (increments only while unpaused), fed as
`(bandTicks % TIME_WRAP_TICKS + partialTick) / 20` — int modulo before the float divide.

### POLISH PASS 2 — 1 fix
The wrap was `72 000` ticks (plain hour), which is NOT a multiple of the 11 s band
period — `Time/11` would jump phase at every wrap and the band would teleport ~27% of
frame height once per hour. **Snapped the wrap to whole band periods:**
`TIME_WRAP_TICKS = 71 940` (= 327 × 11 s × 20) — still ~an hour, and
`71 940 / 220 = 327` exactly, so the band phase is continuous across the wrap.
Header + javadoc updated to state the alignment law.

### POLISH PASS 3 (audit)
`Amount` is 0 under reducedFx (the whole row deactivates), so the grade's only animated
term dies there wholesale. 0.09 Hz / ~1.1% swing: no photosensitivity budget spent. The
band moves ~2 px/s under a 100+ px gaussian — far below the static dither's masking
threshold, so the v2 "no temporal dither needed" claim still holds (comment documents
this).

## Micro-audit summary (cluster-wide)

| Effect | New uniform(s) | Feeder | reducedFx state of the new layer |
| --- | --- | --- | --- |
| world_grade | `PhaseTint` | VeilPostController | stays (static state feedback, like the crush core) |
| ghost_grade | — | — | dead (`Detail` gate — comfort) |
| sun_halo | `AltarWarmth` | VeilPostController | [s9] stays (static); [s8] inherits the streak's `Detail` gate |
| altar_aberration | — | — | dead (rides `GlyphFlash`, armed only under celebrations + !reducedFx) |
| border_glitch | — | — | dead (rides `Kick`, fed 0 under reducedFx) |
| rift_glitch | — | — | dead (rides `RiftAmount`, 0 under reducedFx at source) |
| shockwave | `ShockTint` | WaveOverlay | stays at ×0.6 strength (recolors existing modulation, adds none) |
| xbox_era | `Time` | XboxEraFx | dead (`Amount` = 0 kills the row) |

Photosensitivity: no new luminance flash anywhere — the impact tear and spiral warp are
pure displacement; the scan band is 0.09 Hz/±1.1%; the sparkle is sparse local glints
inside a CPU-gated 0.8 s envelope; the soul echo is a 2% screen at 0.1 Hz drift.

Fixes found by the polish passes themselves (the reason the team law exists): the
ghost-echo direction bug (copy rendered below instead of above), the world_grade dawn
luma drift (~6% hot), and the xbox_era wrap/period misalignment (hourly band teleport).

## Validation footnote (whole cluster)

- `glslangValidator -S frag` (Veil preamble composite): **all 8 shaders OK** after the
  polish edits.
- `javac` (moddev neoforge-21.1.238 + veil 4.3.0 + geckolib 4.9.2 + voicechat-api 2.6.20
  + `build/classes/java/main`): **VeilPostController, EclipseFxState, WaveOverlay,
  XboxEraFx compile clean** (the four binders touched by this pass; GhostGradeFx,
  AltarAberration, BorderFxRenderer, TransitionFx were consumed unmodified).
- Pipeline JSONs: unchanged — Veil pipelines declare no uniforms (verified across every
  existing `pinwheel/post` JSON); fsh + binder is the complete additive-uniform wiring.
