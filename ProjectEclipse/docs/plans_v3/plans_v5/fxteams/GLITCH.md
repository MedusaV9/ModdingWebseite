# FX Team GLITCH — post-pipeline upgrade log (planner → ideators → polishers)

Cluster: `eclipse:border_glitch`, `eclipse:rift_glitch`, `eclipse:shockwave`,
`eclipse:xbox_era` — fsh/json under `assets/eclipse/pinwheel/`, binders in
`border/client/BorderFxRenderer`, `veilfx/TransitionFx` + `veilfx/rift/RiftFx`,
`client/WaveOverlay`, `client/xbox/XboxEraFx`.

Ground rules honored throughout:

- Every pre-existing §3.3 uniform keeps its name, type and semantics. New uniforms are
  ADDITIVE and land together with their Java feeder (`Kick` on border_glitch;
  `RiftCenter`/`RiftAmount` on rift_glitch). shockwave and xbox_era gained NO uniforms —
  all new behavior derives from the frozen set.
- `reducedFx` respected per effect: border_glitch suppresses the kick pulse at the trigger
  site (`Kick` fed 0); rift_glitch forces the ambient corruption feed to 0 at the source
  (`RiftFx.publishAmbient`) while the functional transition envelope stays; shockwave scales
  every fed `ShockStrength` ×0.6 (which also keeps it below the ≥0.75 double-pulse gate);
  xbox_era already eased `Amount` to 0 under reducedFx — unchanged.
- Banding prevention: new shared `efxDither` helper in `eclipse_common.glsl` (±1 LSB,
  temporal or spatial), applied in all four passes where gradients got stronger.
- Post/program JSONs unchanged — all four remain single-stage `veil:blit`
  `minecraft:main → veil:post`; uniforms are CPU-fed, not JSON-fed.
- NO gradle, NO git. Validation after every pass: `glslangValidator` on the
  Veil-preprocessing-emulated assembly (`#version 450` header + `eclipse:eclipse_common`
  resolved — the VFXPOLISH-1 harness) for all touched shaders, `javac` (release 21)
  against the cached moddev merged-jar + Veil 4.3.0 + `build/classes/java/main` classpath
  for every touched binder. All green at every checkpoint.

---

## 1. eclipse:border_glitch (→ v3)

### PLAN

Job: the "reality tears over there" lens glued to the soft border's screen position
(v2/R6). Emotional target: approaching the border should feel like REALITY TEARING — the
world is being rejected around you, and the pushback shove is the punch line. Current
weaknesses (code read + VFXPOLISH-1 verdict): the datamosh rows only ever slide
horizontally (no relationship to WHERE the border is), the RGB tear scales only with the
masked strength (mid-approach fringes stay constant width once the mask saturates), the
actual pushback kick — the single most physical beat the border has — has zero dedicated
screen feedback, and the audio static bed (`BorderStaticSound`, volume = prox² × 0.5) runs
completely decoupled from the visual grain.

### IDEATE

1. **Quantized datamosh pull toward the border** — coarse screen cells displace ALONG the
   tear direction in 4 discrete steps (0, ⅓, ⅔, 1 of full pull), re-laid-out with the
   existing 12 Hz frameSeed. Quantization is what sells datamosh (stale motion vectors),
   and the direction makes space visibly compress INTO the ring. **ADOPTED.**
2. **Scanline desync burst on the kick moment** — `SoftBorder` shoves at `d ≥ R`, which the
   client observes as proximity saturating at 1.0: a rising edge through ~1 IS the kick, no
   new payload needed. New `Kick` uniform (1→0 quadratic over ~420 ms, wall-clock so the
   decay is frame-smooth): sparse thin scanlines rip near-full-width + a gated vertical
   sync-roll. **ADOPTED** (suppressed wholesale under reducedFx).
3. **RGB tear scaling with proximity** — multiply the split by `(1 + 0.75·prox²)` on top of
   the masked strength (~14 px mid-approach → ~24 px touching at 1080p) + a kick spike.
   **ADOPTED.**
4. **AV-sync grain bed via existing uniforms** — the grain term follows the SAME
   `prox² × 0.5` law as `BorderStaticSound`'s whisper volume (70% lens-masked artifact
   share + 30% prox²-synced fullscreen bed), so visual static and the audio loop breathe
   as one. Zero new uniforms — `Proximity` already carries everything. **ADOPTED.**
5. Border-side corrupted vignette (screen-edge darkening on the ring's side) — **REJECTED**:
   competes with the lens mask and drifts back toward the v1 "fullscreen filter" read the
   R6 rewrite explicitly killed.
6. Previous-seed ghost echo (double-exposure of the last block layout) — **REJECTED** for
   this pass: the echo vocabulary belongs to rift_glitch (spacetime), border is about
   TEARING; keeping the vocabularies distinct keeps both readable.
7. Block-local hue rotation instead of full-frame invert pops — **REJECTED**: the 2-frame
   invert pops are an established beat (R6, already lens-masked); replacing them is churn,
   not polish.
8. **±1 LSB temporal dither** on the strengthened lens/palette gradients. **ADOPTED.**

### IMPLEMENT

Shader: new `Kick` uniform + layers 1b (quantized pull, 26×44 cells, gate density
0.45·amt) and 1c (kick desync: 130-row scanlines at 38% gate density, ±12% width rips,
±1% sync-roll wobble); tear direction converted to a proper UV-space unit vector `tearUv`
(v2 fed the aspect-space vector to `efxChroma`, overstretching the split horizontally on
wide screens — fixed); prox²-boosted chroma; AV-synced grain bed; kick joins the panic
floor (`mask ≥ 0.75·kick`) and the invert-pop gate. Java (`BorderFxRenderer`): kick
rising-edge detection in the tick handler (`KICK_EDGE 0.999`, reset on world-out/far
paths), `kickValue()` quadratic decay fed per frame, `EclipseClientConfig.reducedFx()`
guard at the trigger. Validated (glslang + javac).

### POLISH PASS 2

- Kick now also super-charges the quantized pull (`amt + 0.5·kick`, clamped): the shove
  reads as space slamming back toward the ring — ties the new desync layer and the
  datamosh field into one gesture instead of two overlays.
- Magnitude comment corrected (~24 px touching, kick spike ~+10 px transient, deliberate).

### POLISH PASS 3

- Cross-side audit: 5 shader uniforms ⇔ 5 feeder writes (`Proximity/Time/GlitchDir/Seed/
  Kick`), all statically used (no optimize-out risk for `getUniform`); `wantPost`
  unchanged (kick only fires at prox 1.0, so the row is always live when it matters);
  no-NaN check on both `normalize` fallbacks. Re-validated glslang + javac — no further
  number changes needed.

---

## 2. eclipse:rift_glitch (→ v2)

### PLAN

Job: the rift/portal/loading transition pass (R13/R17) — and per the GLITCH ambition, rift
PROXIMITY should now feel like corrupted spacetime even when no transition is running.
Current weaknesses: the pass is 100% event-driven (standing next to an open tear renders a
completely clean frame between open/close pulses), all artifacts are row-based (no
relationship to the rift's screen position), and there is no temporal corruption at all.
Constraint discovered up front: the pipeline is a single-stage `veil:blit` with NO history
buffer, so a true previous-frame ghost is impossible — the ambition text pre-authorizes
faking it with offset sampling.

### IDEATE

1. **Ambient rift-proximity feed** — `RiftFx` publishes the strongest live rift once per
   tick (`TransitionFx.setRiftAmbient`): distance falloff (full at 6 + width/2 blocks, zero
   by 26 + width/2) × the tear's own `openAmount` (opening ramps in, collapse winds down),
   capped at 0.6 so proximity is a simmer, never a transition. New uniforms
   `RiftCenter` (NDC, projected per frame through `SunTracker.worldToNdc`, parked ±1.9
   offscreen on the rift's side when behind the camera — the border_glitch trick) +
   `RiftAmount`. **ADOPTED** (0 under reducedFx at the source).
2. **Voxel-sort streaks** — lanes perpendicular to the away-from-rift axis drag outward by
   random QUANTIZED lengths (floor(hash·5)·0.012), gated per lane, re-rolled at the 12 Hz
   seed: the pixel-sorting read faked as a directional smear (a true sort needs unbounded
   taps). Driven by `corr = max(rift, g·0.55)` so heavy transitions inherit the same
   vocabulary. **ADOPTED.**
3. **Mirror-shard refraction near the rift center** — the disc around `RiftCenter`
   (aspect-corrected, radius 0.18→0.62 falloff) splits into 60° angular shards; gated
   shards resample the scene reflected across their bisector (kaleidoscope-lite, 65% max
   blend × zone × gate): space reassembled from shattered copies. **ADOPTED.**
4. **Time-jitter echo** — the faked previous-frame ghost: re-sample the CURRENT frame at a
   jitter offset (±0.9% UV) that re-rolls at ~8 Hz, mixed via `max(color, echo)` at ≤10%
   so the ghost reads additive-bright like an undecayed phosphor copy. **ADOPTED.**
5. True history buffer via a second render target + copy stage — **REJECTED**: changes the
   post JSON topology (frozen single-blit family invariant), and the offset fake sells the
   beat at zero architectural cost (explicitly sanctioned by the brief).
6. Ambient invert pops near rifts — **REJECTED**: R11's spirit ("routine rift traffic never
   strobes", VFXPOLISH-1) — pops stay gated on the TRANSITION envelope (`g ≥ 0.55`) only.
7. Radial time-dilation warp (slow UV swirl around the tear) — **REJECTED**: reads as a
   water/portal cliché and fights the shard layer for the same screen area.
8. **Dither** on the violet bleed/echo/shard gradients (the bleed was already the family's
   biggest banding source). **ADOPTED.**

### IMPLEMENT

Shader: `RiftCenter`/`RiftAmount` uniforms + the three layers above; scanline shimmer and
chroma get a half/smaller share from the ambient feed (~4 px simmer); iris fade contract
untouched. Java: `TransitionFx` — ambient state + tick-cached park bearing (alloc-free
feeder, the `BorderFxRenderer.toBorderX/Z` pattern), `wantPipeline` extended
(`riftAmbient > 0.004`), logout reset; `RiftFx` — `publishAmbient()` after the tick loop,
empty-list wind-down, reducedFx force-0. NOTE: `RiftFx` was being concurrently extended by
FXTEAM-RIFT (styles/surge/entry-watch) — re-read before every edit, additions kept
strictly additive, both teams' changes compile together. Validated (glslang + javac).

### POLISH PASS 2

- **Real catch:** the new dither was applied AFTER the iris multiply, so at `FadeAmount = 1`
  the "exactly black" portal-hold contract (frozen R13, verified in VFXPOLISH-1) was
  broken by ±1 LSB noise. Fixed: dither scaled by `(1 − black)` — the bleed gradient still
  gets dithered (black < 1 there), the full hold stays bit-exact black.

### POLISH PASS 3

- Documented the deliberate default park: with no rift near, `RiftCenter` rests at
  (0, −1.9) BELOW the screen, so pure-transition streaks drag vertically — the classic
  pixel-sort orientation, for free. Cross-side audit: 6 uniforms ⇔ 6 feeds; `atan`
  degenerate case bounded by the shard-zone radius; ambient winds down on empty list,
  dimension change (rifts die with the level) and logout. Re-validated.

---

## 3. eclipse:shockwave (→ v3)

### PLAN

Job: every world shockwave + the submerge rings (R8). Emotional target: impacts should
PUNCH. Current weaknesses (v2 already fixed easing + day readability): the 6-period sine
train under a broad `exp(-|ring|·7)` envelope reads as pond ripples rather than a blast
front; nothing distinguishes a 1.0-strength intro burst from a 0.25 expansion pulse except
amplitude; there is no pressure read behind the front; amplitude is constant over the
ring's whole travel (physically wrong — energy spreads); and the new brightness terms band
on flat skies. Hard constraint: §3.3 uniforms frozen AND no new ones needed — every
ambition derives from `ShockCenter/ShockProgress/ShockStrength`.

### IDEATE

1. **Crisp front** — ONE antisymmetric push/pull lobe (sin phase clamped to its first
   period) under a tight `exp(-|ring|·16)` envelope, plus a short trailing wake strictly
   inside the ring (cutoff at exactly −1/9 ring units — a sine zero, so the seam is
   continuous). **ADOPTED.**
2. **Chromatic fringe** hugging the crisp front (`exp(-|ring|·20)`, 0.022 amplitude —
   in v2's range, but concentrated on the front line). **ADOPTED.**
3. **Inner pressure dimple** — a −0.34..0 ring-space band behind the front that pulls the
   image back TOWARD the origin (0.014 UV) and dips brightness ≤5%: the "air sucked out"
   read that makes the crest feel like pressure, not glass. **ADOPTED.**
4. **Double-pulse for big events** — `smoothstep(0.72, 0.78, strength)·0.45` gates a second
   `ringTerms` evaluation at `progress − 0.16`: intro v3 (1.0) and wand (0.8) double-thump,
   structure slams (0.5) and expansion fronts (0.25) stay single. Derived from the frozen
   strength — no new uniform, and the reducedFx ×0.6 cap disables it by construction.
   **ADOPTED.**
5. **Distance attenuation** — amplitude × `1/(1 + 0.7·expand)`: bursts hard at the origin,
   dies like a real pressure wave; base displacement raised 0.045 → 0.055 so the origin
   punch is preserved. **ADOPTED.**
6. Screen-shake via UV wobble inside the ring — **REJECTED**: `reducedFx` documents screen
   shake as the canonical thing players opt out of, and HitStopService/camera systems own
   that axis; a post-pass shake would double-apply.
7. Persistent heat-haze afterimage behind the front — **REJECTED**: needs a history buffer
   (same constraint as rift_glitch) and the wake term already gives the front a tail.
8. **Activity-gated dither** for the crest/dimple gradients. **ADOPTED** (see pass 2).

### IMPLEMENT

Shader: `ringTerms(dist, progress)` helper returning (wave, front, dimple) with lifetime ×
travel attenuation baked in, called for the main ring and the gated echo (echo birth
ramp `smoothstep(0, 0.05, echoProgress)` suppresses the degenerate radius-0 ring while its
progress is still negative — no pulsing dot at the origin); desat stays on the LEAD ring
only (no double-desat). Java (`WaveOverlay`): `REDUCED_FX_STRENGTH = 0.6` scale on both
feed paths (world + submerge). Validated (glslang + javac).

### POLISH PASS 2

- Dither gated on local ring activity (`smoothstep(0, 0.02, |wave| + front + dimple +
  inside)`): pixels the wave is not touching stay BIT-IDENTICAL, and a behind-camera park
  at (10,10) now yields a mathematically untouched frame (previously the fullscreen dither
  would have jittered it).

### POLISH PASS 3

- Envelope math audit: wake seam continuous at −1/9 (sine zero), peak displacement ≈ v2's
  (0.023 vs 0.025 UV) but half the band width — same punch budget, twice the crispness;
  echo-after-main ordering verified (echo outlives the lead ring by design, fading on its
  own lifetime). Uniform audit: 3 fed ⇔ 3 declared. Re-validated.

---

## 4. eclipse:xbox_era (→ v2)

### PLAN

Job: the console-era grade for the Xbox tutorial dimensions (C17 fix 4). Emotional target:
LOVINGLY AUTHENTIC — a warm memory of 2008, comfy not gimmicky. Current weaknesses: the
grade is purely per-pixel (no resolve softness — era games never delivered razor-sharp
1080p), saturation is a flat 14% lift (the era's look was blown SATURATED brights, not
uniform vividness), the warm cast is one flat multiplier across all tonal zones, and the
lifted blacks + vignette are exactly the gradients that band on 8-bit output. Java binder
already model-correct (30-tick ease, reducedFx → 0, GRADE priority) — untouched.

### IDEATE

1. **720p-era soft resolve** — 4-tap diagonal blur (~1.3 px) blended 55%, then 30% of the
   lost high frequency added back: blur-then-sharpen, the soft-yet-edge-enhanced look of a
   720p render resolved onto a bigger panel. **ADOPTED.**
2. **Saturation bloom** — the SAME 4 blur taps double as a bloom source, weighted
   `luma² × saturation`: bright saturated regions glow softly, white light sources do NOT
   (it is a saturation bloom, not a glow filter). Flat saturation lift eased 14% → 12% to
   make room. **ADOPTED** (total cost: 4 extra taps, dimension-local).
3. **Era "LUT" feel** — three-zone procedural grade (cool shadows 0.985/1.000/1.035, warm
   mids 1.040/1.015/0.940, cream highlights 1.020/1.005/0.965; smoothstep zone weights
   summing to 1) replacing the single flat warm cast. **ADOPTED.**
4. **CRT-adjacent vignette refresh** — keep the pillarbox side shade + radial corner
   falloff, add a faint WARM lift inside the falloff (+0.012/0.008/0.004·corner): corners
   dim toward phosphor-warm, never toward cold black. **ADOPTED.**
5. Scanlines / aperture-grille overlay — **REJECTED BY BRIEF** (the explicit "WITHOUT
   scanline cliché" instruction; also aliases at non-integer DPI scales).
6. Temporal color wobble / composite-signal chroma noise — **REJECTED**: reads as VHS, not
   X360-over-HDMI/component; also fights the anti-gimmick target.
7. Barrel distortion — **REJECTED**: era output was flat panels as often as CRTs, and any
   geometry warp on a HUD-bearing frame reads as nausea, not nostalgia.
8. **Static ±1 LSB dither** (Amount is constant while inside the dimension, so spatial-only
   dither suffices — no temporal shimmer on a calm grade). **ADOPTED.**

### IMPLEMENT

Shader rewritten per the recipe above (now includes `eclipse:eclipse_common` for
`efxDither`); X360 gamma curve (pow 0.90 + black lift) kept verbatim from v1; early-out at
Amount ≤ 0.001 kept (taps only run in-dimension). JSONs and `XboxEraFx` untouched.
Validated (glslang).

### POLISH PASS 2

- LUT zones now classify on the POST-gamma luma (`zoneLuma` recomputed after gamma lift +
  bloom) instead of the pre-lift input — the mid-tone warmth lands on what the player
  actually sees; previously a lifted shadow could still be graded as "shadow" after the
  lift had already pushed it into the mids.

### POLISH PASS 3

- Honesty fix in the header math: the mids' −6% blue matches v1's established cast, so the
  "±4%" claim was corrected to "~±6%" rather than flattening the look to fit the comment.
  Zone-weight partition re-checked (no overlap: shadow ends at 0.42, highlight starts at
  0.55 — mid weight can never go negative). Re-validated.

---

## Final validation matrix

| Artifact | Tool | Result |
|---|---|---|
| all 4 rewritten `.fsh` + `eclipse_common.glsl` (and the other 5 family shaders against the new include) | `glslangValidator` (Veil preamble assembly) | OK |
| `BorderFxRenderer`, `TransitionFx`, `RiftFx`, `WaveOverlay` (+ unchanged `XboxEraFx` compile-checked) | `javac` release 21, moddev merged-jar + Veil 4.3.0 classpath | OK |
| 8 post/program JSONs of the cluster | `python3 -m json.tool` | OK (unchanged) |
