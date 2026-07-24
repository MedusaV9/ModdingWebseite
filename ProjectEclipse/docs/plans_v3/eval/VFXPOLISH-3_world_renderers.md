# VFXPOLISH-3 — World-Space FX Renderer Polish Pass (Fable)

Full review of the world-space (non-post) FX renderers per the four-point checklist:
(1) vertex math sanity, (2) alpha/brightness readable in BOTH day and night, (3) eased
curves instead of linear ramps, (4) §3.5 budget respect. Includes the EVAL-4 post-eval
appendix items (daylight wall flatness, daylight bolt visibility) and the EVAL-4 M4
occluder LOD pop. Safe tunings were applied directly; frozen contracts (§3.2 entry
points, §3.3 uniforms, R14/R15 palette + occluder guarantee) were not touched.

**Validation:** every reviewed file (plus `LimboSpecialEffects`, `RiftWardenRenderer`,
`FogTyrantRenderer` as dependents) was compiled with plain `javac -proc:none` against the
real NeoForge 21.1.238 merged jar + Veil 4.3.0 + GeckoLib 4.9.2 classpath — all clean,
including against the sibling VFXPOLISH-1 in-flight `EclipseFxState` changes. No gradle
run per task constraints.

---

## Summary table

| Renderer | Vertex math | Day/night read | Curves | Budget | Change applied |
|---|---|---|---|---|---|
| `stormfx/StormWallRenderer` | ✅ (see notes) | ⚠️ flat at noon | ✅ smoothstep LODs | ✅ | **daylight contrast/alpha carve + additive boost; occluder 48-gon (M4)** |
| `stormfx/StormFxClient` (bolts/dread) | ✅ | ⚠️ bolts thin at noon | ⚠️ linear heartbeat | ✅ capped lists | **daylight bolt widen/glow lift; eased dread ladder** |
| `client/sky/OverworldPurpleEffects` | ✅ | ✅ | ⚠️ static rim/coronas | ✅ | **corona + rim breathing (avg strength unchanged)** |
| `client/sky/LimboSpecialEffects` | ✅ | n/a (limbo) | ✅ sine pulse | ✅ | none |
| `client/sky/LimboHorizonShips` | ✅ | n/a (limbo) | ⚠️ pop-in on reseed | ✅ 8 tris/ship | **eased 3 s re-appear + off-gaze reseed guard** |
| `border/client/BorderFxRenderer` | ✅ | ✅ additive+flicker | ⚠️ flat density | ✅ ≤ 54 quads | **proximity-eased patch densification** |
| `client/ShipDoorGlow` | n/a (light+motes) | ✅ | ✅ sine 0.5 Hz | ✅ 1 light slot | none |
| `veilfx/SupplyBeamRenderer` | ✅ | ✅ | ✅ | ✅ ≤ 16 quads | **distance-scaled core width (far presence)** |
| `veilfx/rift/RiftRenderer` | ✅ | ✅ | ⚠️ static core | ✅ ≤ 160 tris | **core breath + deeper tip flicker** |
| glow layers (`EnrageGlowLayer`/`StaggerGlowLayer`) | ✅ | ✅ | ✅ | ✅ | none |
| `worldgen/structure/SanctumOrbitals` | ✅ | n/a | ⚠️ bob undersampled | ✅ 0.3 pkt/s ea. | **bob period floor raise (40 t window ≤ ~90° phase)** |
| `client/sanctum/SanctumLightfall` | n/a (emitters) | ✅ | n/a | ✅ AMBIENT | none |

---

## Changes applied

### 1. `StormWallRenderer` — daylight readability (EVAL-4 post-eval) + occluder LOD pop (M4)

**Root cause of the flat noon read from ~40 blocks:** the dense base band (bottom 72 % of
the wall) held a CONSTANT 0.86 alpha; per-column variation existed only in color
(`gray ∈ [0.72, 1.0]` × the ~0.10 slate palette ⇒ ≤ 0.03 RGB spread — invisible against a
bright sky) and in the mid band's `aMid` churn, which sits near the top edge. Against
night skies the constant band is exactly the R14 look; against a noon sky it collapses to
a featureless dark cylinder. The additive violet band also washes out at noon (additive
light on an already-bright framebuffer).

**Fix (all gated on a per-frame `daylight` factor, 0 night → 1 midday, from the same
cosine `OverworldPurpleEffects.dayFactor` curve the sky pass uses; dimensions without sky
light stay on the frozen night look — zero change at night):**
- base band: churn now carves up to `DAY_BASE_CARVE = 0.28` × (1 − churn) out of each
  column's alpha at noon (per-column striping 0.73–0.86 ⇒ ~10 % luminance banding against
  sky — the swirl reads). The opaque occluder sits 5 blocks further in, so the
  never-see-inside guarantee is untouched.
- churn gray floor widens 0.72 → 0.44 at noon (`DAY_GRAY_SPREAD`) for color contrast.
- additive shells + vortex cone alpha × (1 + 0.55·daylight) (`DAY_ADDITIVE_BOOST`) — the
  violet rim survives the bright sky.
- **M4**: occluder segment count fixed at 48 (was 48/24 stepping at shellDist 176 — the
  opaque rim silhouette popped ~0.9 blocks against the sky once per approach). Cost:
  +96 quads per far storm — trivial, and the crossfaded translucent shells already spent
  far more.

**Vertex math notes (verified, no changes):** tangent-arc culling
(`acos(r/d) + 0.5 margin`) correct for exterior cameras and full-circle inside; the
degenerate cone-lid quads (apex repeated twice) are an intentional cheap triangle;
`emitColumn` twist/taper consistent between occluder inset and shells; bolt ribbon frame
(`v = dir × u`, `w = dir × v`, camera-relative midpoint as view dir) is sound — `w` is
implicitly unit-length since `dir/len ⊥ v̂` are orthonormal. Budget: unchanged quad
counts except the occluder note.

### 2. `StormFxClient` — daylight bolts + eased dread ladder

- **Bolts (post-eval "bolt not visible in daylight"):** ribbons widen ×(1 + 0.35·daylight)
  (`DAY_BOLT_WIDEN`, applied in `StormWallRenderer.buildBolt` where the geometry lives)
  and the outer violet glow layer's alpha lifts ×(1 + 0.35·daylight), capped at 0.8 —
  additive strikes trade a little width for the punch the noon sky steals. The white-hot
  2-tick core alpha (0.95) is already near-saturating and stays frozen. Note: the OTHER
  half of that observation (`/eclipsefx storm bolt` reading the command SOURCE position
  under `execute positioned`) is a server command-plumbing issue, out of a render-polish
  pass's scope — left documented here.
- **Dread ladder:** heartbeat cadence tightening was a LINEAR lerp over the 60→20 block
  approach; now smoothstep-eased, so the tightening accelerates near the wall (the last
  20 blocks feel like the storm noticed you). Tendril inward crawl speed now scales
  0.010→0.022 with the same eased closeness (it was a flat 0.015; at the 40-block
  tendril gate the new value matches the old, weaker further out, harder near).
- **Keepalive (EVAL-4 M2): verified already fixed** — `handle()` early-returns on
  same-state resends, touching only center/radius/height/type; clocks/glitch/reveal
  style survive. Wisp swirl, loop-sound hysteresis, capped bolt/arc lists all check out.

### 3. `OverworldPurpleEffects` — corona + rim life

- Corona quads (90/140/200 units, verified against the R1 doc) held three frozen alphas;
  now each layer breathes ±10 % on a slow phase-offset sine (`0.7 rad/s`, layer phase
  `i·2.1`) — a living corona instead of three static rings. Rotation speeds/sizes kept.
- Permanent sun rim: frozen 0.50 alpha → `0.50 + 0.04·sin(0.45·s)` — same average
  strength, no longer a static decal. Rim size (×1.35 sun) kept.
- Verified: celestial pose shares `SunTracker.sunAngleRadians` (one source of truth),
  sky-crush lerp targets sane, `dayFactor` matches the vanilla curve, moon/stars vanilla.

### 4. `LimboSpecialEffects` — verdict clean (no changes)

Zenith rotation math (`rotationTo` from +Y), cached zenith point, aura ray fan (tapered
quads, root alpha 0.4 → 0 tips), counter-rotating layers, water-reflection streak
(world-oriented, height-faded, shares the aura pulse) all verified. The known zenith flip
above y≈deck+480 (EVAL-4 LOW) is unreachable in legit play — left as documented.

### 5. `LimboHorizonShips` — eased re-appearance

Silhouette triangle table, azimuth-tangent plane math and the deterministic
`ECLIPSE_SEED` hash verified; alphas (hull 0.85, lantern 0.9) read well against the
near-black dome. Two fixes for the "vanish when observed" fiction:
- **Off-gaze reseed guard:** `reseed()` is idempotent for a fixed sighting counter, so
  the candidate direction is computed first and the un-latch is HELD while the player is
  looking within ~0.82 dot of the fresh azimuth — a ship never materializes mid-gaze
  (per-client, like the fade itself; azimuths stay deterministic across clients).
- **Eased 3 s fade-in** (`APPEAR_TICKS = 60`, smoothstep) replaces the instant
  `fade = 1.0` pop. The one-way fade latch while sighted is unchanged.

### 6. `BorderFxRenderer` — approach densification

Patch quad math (tangent×up in-plane axes with per-quad roll), UV jitter, flicker hash,
additive blending and the ≤ 9×6 quad budget verified. Change: cluster count now scales
`×(0.45 + 0.55·smoothstep(prox))` (floor 2) on top of the quality-tier roll — a sparse
crackle at the fxRange edge rising to full tier density on the ring, so the push-back
boundary reads as a rising wall of static instead of a constant-density field that only
brightens. Post `Proximity^1.5` curve, GlitchDir NDC projection and the throttle-reset
lore (`-1000L`, never `Long.MIN_VALUE`) all check out — untouched.

### 7. `ShipDoorGlow` — verdict clean (no changes)

Single budgeted light (≤ 1 slot invariant upheld on every path incl. the session fuse),
0.8–1.2 sine pulse at 0.5 Hz (already an eased curve; freezes with pause by design),
materialize/release hysteresis 48/56, level-swap release. Nothing to tune.

### 8. `SupplyBeamRenderer` — far presence

Crossed-plane + disc math and the ≤ 16-quad budget verified. Problem: past the 192-block
core-only LOD the 0.35-block core planes subtend ~1–2 px, so the "readable from 200+
blocks" beam faded into noise long before the 512 cutoff. Fix: core half-width scales
`clamp(dist/192, 1, 2.5)` — continuous in distance (no LOD pop), ~constant screen width
from 192 out to ~480, capped so a near beam is untouched. Alpha/pulse curves kept
(per-beam phase already prevents lockstep throbbing).

### 9. `RiftRenderer` — tear drama

Perimeter star math (tip/valley alternation, in-plane outward dirs), two-pass
alpha→additive ordering, parallax swirl push and the ≤ 160-tri budget verified. Two
tunings within the same budget/cadence:
- tip flicker radius deepened 0.86–1.0 → 0.82–1.0 — the arms visibly convulse instead of
  shimmering;
- hot core alpha breathes ±8 % on a slow sine, phase from the rift seed's low bits (`&
  31`, keeps the sine argument small) so neighbouring tears never pulse in lockstep.
The frozen R17 numbers (SWIRL_SCALE 0.85, PARALLAX 0.4, fringe 0.10) untouched.

### 10. Glow layers — verdict clean (no changes)

- `FogTyrantRenderer.EnrageGlowLayer`: alpha `(0.10 + 0.11·stacks)(0.35 + 0.65·pulse)` is
  bounded — `ENRAGE_MAX_STACKS = 5` caps it at 0.65 at pulse peak; pulse quickening per
  stack is the intended readability tell; `reducedFx` flattens to steady. Subtle enough.
- `EnrageSpeedLines`: ≤ 0.16 alpha, tent-faded band cycle, double-winding for the culled
  lightning render type — correct and whisper-quiet.
- `RiftWardenRenderer.StaggerGlowLayer`: two incommensurate sines gutter brightness in
  [0.30, 0.75] at full slump — irregular, never a strobe, never fully dark; death
  implosion correctly owns its own glow. Slump pose re-runs identically in the re-render
  pass. Nothing to tune.

### 11. `SanctumOrbitals` — 40 t interpolation smoothness

Orbit and tumble are safely under-sampled: 6° orbit chord and ≤ 7.5° tumble per 40 t
window (chord radius error ~0.14 % — invisible). The BOB was not: the fastest period
(`140 × 0.8 = 112 t`) put **129° of bob phase into one linear 40 t window**, visibly
flattening the sine's crests (the fragment "hitches" at the top/bottom of its bob).
Fix: variation row floor raised `0.8 → 1.2` (periods 168–315 t ≈ 8.5–16 s), so no window
spans more than ~86° — under the ~90° threshold where linear tweening of a sine stays
visually smooth. Same packet budget (0.3/s per display), same absolute-time statelessness.

### 12. `SanctumLightfall` — verdict clean (no changes)

Manager-only class (no vertex math): hysteresis window 96/110, floating-gate block probe,
prune/release paths, AMBIENT-channel budget retries every 40 t all verified correct.

---

## Not applied (out of scope, documented)

- `/eclipsefx storm bolt` anchoring under `execute positioned` (server command plumbing —
  EVAL-4 post-eval item 2, needs a command-source fix, not a renderer fix).
- Vortex interior over-reach (EVAL-4 post-eval item 1) — already addressed in
  `StormInteriorFx` via the tilted-radius evaluation (`StormWallRenderer.TAN_TILT`
  package hook); verified present, no further change here.
- Limbo zenith flip above y≈deck+480 (EVAL-4 LOW, unreachable in legit play).
