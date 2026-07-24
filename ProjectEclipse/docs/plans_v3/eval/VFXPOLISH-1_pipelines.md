# VFXPOLISH-1 — Veil Post Pipeline + Shader Polish Pass (Fable)

Full review of every `assets/eclipse/pinwheel/post/*.json` pipeline, its
`pinwheel/shaders/program/*.fsh` (+ `include/eclipse_common.glsl`) and its Java feeder, per
the four-point checklist: (1) uniform feed ↔ shader declaration match, (2) readable-but-
dramatic ranges/curves (the R3 over-darkness lesson: totality is now crush 0.55 +
exposure 0.62 — the whole family was audited for the same trap), (3) easing where motion
felt linear, (4) dead/unused uniforms.

**Validation:** all 9 fragment shaders were compiled with `glslangValidator` (Veil
preprocessing emulated: `#version` header + `#include eclipse:eclipse_common` resolved)
— all OK after the changes. No pipeline/uniform names were touched (§3.3 stays frozen);
no Java logic changed (one stale comment corrected). All post JSONs are uniform
single-stage `veil:blit` `minecraft:main → veil:post` — consistent, correct.

---

## Summary table

| Pipeline | Feeder | Uniform feed | Ranges/curves | Easing | Dead uniforms | Change applied |
|---|---|---|---|---|---|---|
| `world_grade` | `VeilPostController` | ✅ match | ✅ (post-fix values) | ✅ CPU-eased | none | stale-comment fix |
| `sun_halo` | `VeilPostController` + `SunTracker` | ✅ match | ✅ | ✅ | none | none |
| `limbo` | `LimboAmbience` | ✅ match | ✅ | ✅ | none | none |
| `border_glitch` | `BorderFxRenderer` | ✅ match | ✅ | ✅ (`prox^1.5` deliberate) | none | none |
| `rift_glitch` | `TransitionFx` | ✅ match | ✅ | ✅ CPU smoothstep | none | none |
| `altar_aberration` | `AltarAberration` | ✅ match | ⚠️ zone edge invisible | — | none | **shader ease-out response** |
| `ghost_grade` | `GhostGradeFx` | ✅ match | ✅ not too dark (see math) | ✅ 30-tick CPU ease | none | none |
| `shockwave` | `WaveOverlay` + `EclipseFxState` | ✅ match | ⚠️ invisible on flat sky | ⚠️ linear expansion | none | **eased expansion + luma crest** |
| `storm_interior` | `StormInteriorFx` | ✅ match | ✅ | ✅ (exp smoothing CPU-side) | none | none |

---

## Changes applied

### 1. `altar_aberration.fsh` — perceptual ease-out response (zone edge was invisible)

**Problem** (the "aberration too subtle at zone edge" trap): the CPU zone curve is already
quadratic — `Aberration = (1 − d/r)² · 0.85` (`AltarAberration.zoneTarget`) — and the shader
then applied it **linearly** (`split = 0.012 · a`). Quadratic-in, linear-out means the outer
half of the zone produced sub-pixel fringes:

| d/r (dist from altar) | fed `a` | old split @1080p edge | new split |
|---|---|---|---|
| 0.00 (at altar) | 0.850 | 9.8 px | 11.3 px |
| 0.25 | 0.478 | 5.5 px | 8.4 px |
| 0.50 | 0.212 | 2.5 px | 4.4 px |
| 0.75 | 0.053 | **0.6 px — invisible** | 1.2 px |
| 0.90 | 0.008 | 0.1 px | 0.2 px |

**Fix**: shader-side `aResp = a · (2 − a)` (ease-out quad) drives the RGB split and the
violet lift. The zone rim roughly doubles (readable-but-subtle), the center cap barely
moves (~10 px preserved), and there is no activation pop (predicate gates at `a > 0.01`,
where `aResp` is still ≈ 0.02 → sub-pixel). The **barrel distortion stays gated on the RAW
amount** (`smoothstep(0.55, 0.7, a)`) so it remains a near-the-altar feature — the
"never nauseating" guarantee is untouched. The frozen CPU curve and the single frozen
uniform are unchanged.

### 2. `shockwave.fsh` — ease-out ring expansion + day-readability luma crest

Two problems, both in the shader, both fixed without touching the frozen uniforms:

- **Linear expansion** (`ring = dist − ShockProgress · R`): a constant-velocity ring reads
  mechanical; real blast fronts burst and decelerate. Now
  `expand = 1 − (1 − p)²` positions the ring front (at p = 0.25 the ring is already at 44 %
  radius; at p = 0.75 at 94 %) while `falloff`/`front`/desat all stay on the **raw**
  progress — the effect's lifetime, fade-out and the submerge loop cadence are unchanged;
  only the spatial motion is punchier.
- **Rings unreadable at day**: the effect was pure refraction + chroma + 8 % desat.
  Refraction of a *uniform* region is a no-op — against a flat noon sky (exactly where the
  intro-v3 storm burst and altar-milestone map-wide pulses fire, strengths 0.6–1.0) the
  ring vanished. Added a faint brightness crest/trough riding the wave:
  `color *= 1 + wave · falloff · clamp(strength) · 0.10` — ≤ ±10 % at full strength,
  ±5.5 % on the 0.55-strength submerge rings, and it dies with the same falloff, so
  night/dusk keeps the subtle glassy look (no new over-brightness trap: it modulates,
  never adds flat gain).

### 3. `world_grade.fsh` + `EclipseFxState.java` — stale "0.35" exposure comments

Both still documented the exposure dip as 0.35 — the exact over-darkness value the R3
lesson replaced with `TOTAL_EXPOSURE = 0.62`. Stale numbers on a tuned constant invite
re-regression; both comments now state 0.62 (the shader comment also records *why* 0.35
was abandoned). No behavior change.

---

## Per-pipeline verdicts (no change needed)

### `world_grade` — GOOD (post-lesson values verified)
Feed: `EclipseAmount/NightAmount/DesatAmount/ExposureMul` all fed by
`VeilPostController.feedWorldGrade`, all consumed. Numbers at full eclipse: crush
`max(night, eclipse·0.55)` → mid-gray 0.5 → 0.316 via `efxCrush`, × exposure 0.62 →
**0.196** plus ≤ 13.75 % extra sky dim — dark violet dusk, readable, matches the frozen
lesson. Night-only max is the same 0.55 crush at exposure 1.0 → 0.316. `nightAmount`
follows the cosine `dayFactor`, so dusk/dawn transitions are inherently smooth;
eclipse/exposure ramps are smoothstepped CPU-side (`EclipseFxState.easedProgress`). No
linear motion, no dead uniforms.

### `sun_halo` — GOOD
Feed: `SunScreen` (vec4 from `SunTracker`, one CPU projection shared with the sky quad —
the R2 alignment fix), `HaloStrength` (0..~1.35), `RimOnly`. All consumed. Rim/glow both
use smoothstep/exp falloffs; glow radius growth `0.12 → 0.55 NDC` saturates exactly at the
max strength (`(1.35 − 0.15)/1.05 ≥ 1`). Occlusion degrades to a 0.35 rim instead of
popping off; night idles off via the elevation term before the `0.01` predicate. The
additive peak (~1.15) clips only inside the corona at totality — that is the drama beat,
intentional.

### `limbo` — GOOD (richest of the family, all terms bounded)
Feed: `Intensity/GodrayDir/CausticsAmount/Time` from `LimboAmbience` — all consumed.
Caustics/sparkle/smear are all masked by `water` (non-sky ∧ dark ∧ lower-screen ∧
`CausticsAmount`), so the lantern-lit ship stays clean. God rays: `lookUp` ramp is already
smoothstepped and the CPU pushes `(10,10)` offscreen when the zenith is behind the camera
— guard verified. The 2 s enter fade is ease-out quad CPU-side. Vignette breathing (0.05
amplitude) and the mirrored-zenith smear share the sky-pass 1.3 rad/s clock — no desync.
Corner darkening peaks ≈ 34 % — atmospheric, not crushed. `Time` wraps hourly (documented;
single-frame pattern pop per hour is imperceptible in churning noise).

### `border_glitch` — GOOD
Feed: `Proximity/Time/GlitchDir/Seed` from `BorderFxRenderer.feedPost` — all consumed,
including the `+1000` nether palette flag on `Seed`. `prox^1.5` is the frozen R6 curve
(soft far, steep near — correct read for a danger gradient). The lens mask keeps the
effect localized with a 0.35 panic floor only at `prox > 0.85`; invert pops are 2-frame
and hash-gated (~1/s at touch range). The offscreen lens park (±1.9 NDC on the border's
side) means turning your back softens instead of snapping. No change.

### `rift_glitch` — GOOD ("rift glitch strength" verdict: adequate)
Feed: `GlitchAmount/FadeAmount/Time` (wall-clock — keeps animating through dimension-change
tick stalls, correct choice) from `TransitionFx` — all consumed. Strength audit: the
enter/exit envelope reaches 1.0 (full datamosh + 15 px chroma + invert pops); rift
open/close pulses cap at 0.5 by design (R11) which displaces ~25 % of rows ±up to 6 % UV —
clearly visible but below the invert-pop gate (0.55), so routine rift traffic never
strobes. Loading pulse ≤ 0.2 — correctly ambient. Fade iris: `f = 1` ⇒ front radius −0.48
⇒ mathematically fully black (holds the portal blackout); violet edge bleed is noise-
modulated. Envelope shapes are smoothstepped CPU-side (`TransitionFx.smooth01`,
`EclipseFxState.smooth`); the exit glitch triangle is deliberately sharp (it's a glitch).

### `ghost_grade` — GOOD ("too dark?" verdict: no)
Feed: single frozen `Ghost` with 0.2 Hz breath premultiplied CPU-side (±4 %, pause-frozen
clock) — consumed. Darkness math: 70 % desat preserves luma; the blue-violet **lift
raises** shadows (+0.02..0.075); the cool cast multiplies luma by ≈ 0.923; vignette −12 %
max at corners. Net mid-frame ≈ −8 % — spectral, not dark, and safely composable on top of
`world_grade`'s night crush (both GRADE). The 30-tick ease is smoothstepped. No change.

### `shockwave` — see changes applied
Feed: `ShockCenter/ShockProgress/ShockStrength` from `WaveOverlay.feedShockwave`; world
events win over submerge rings; behind-camera origins park at (10,10) where the exp
falloff kills the effect — verified against `EclipseFxState.shockwaveParams`. In-the-wild
strengths: 0.25 (expansion front), 0.5 (structure slams), 0.6 (altar milestone), 0.8
(wand), 1.0 (intro v3), 0.55 (submerge loop) — the new luma crest is clamped for all.

### `storm_interior` — GOOD
Feed: `Interior/RainAmount/Time` from the `StormInteriorFx` static-init row — all
consumed. Crush caps at `amt·0.7` **before** the slate remap and the sky wipe targets
0.05-luma slate at 85 % — dim but structured, matching the fog clamp so no double-crush
trap. Interior amount is exponentially smoothed CPU-side with teleport snap (EVAL-4 M5).
Rain streaks: three gated layers, linear fall is physically right for rain. The `Time`
wrap (100 s) causes a single-frame streak re-phase — invisible in sub-second fall cycles.
Vignette 28 % max — pressure, not blindness. No change.

### `eclipse_common.glsl` — GOOD
All four helpers are used across the family (`efxHash`/`efxNoise`/`efxChroma`/
`efxBlockOffset`/`efxCrush`); unused helpers per-shader are include-normal and cost
nothing after link-time DCE. `efxCrush`'s `pow(c,1.35)·0.42` floor is the shared crush
primitive the 0.55 caps were tuned against — left untouched.

---

## Dead/unused uniform audit

Every uniform declared in every `.fsh` is both fed by its Java feeder and consumed by the
shader body; every `pipeline.getUniform(...)` name in Java exists in the matching shader.
No orphans in either direction. (`DiffuseSampler0`/`DiffuseDepthSampler` are Veil-bound
sampler conventions, not CPU-fed.)
