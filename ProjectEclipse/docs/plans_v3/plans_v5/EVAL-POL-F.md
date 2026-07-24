# EVAL-POL-F — v5 Visual/Audio/UX Polish Review (Fable)

Read-only audit of the v5 polish work, reviewed as an art-direction pass. Verdict up front:
**7.5 / 10** — disciplined, budget-conscious craft almost everywhere (reducedFx ladders, one-seam
anchors, allocation-free hot paths), undermined by one real rendering-correctness bug (storm
tangent-arc drift), one asset-level palette bug (tinted wisp sprite muddying two of the three
wand paths), and a handful of medium silhouette/timing artifacts.

Scoring notes: correctness bugs that read on screen cost the most; deliberate stylization
(deadpan white loader, strobing rift static) is not penalized.

---

## 1. Limbo — `limbo.fsh` + `LimboAmbience` + `LimboSpecialEffects`

**Water mask (C1) — mostly robust.** Depth reconstruction uses the exact AFTER_SKY matrices
(`onRenderLevelStage`, determinant guard, `WaterlineY` parked at −1e5 until the anchor syncs) —
the SunTracker law is followed, so the mask and the depth buffer cannot disagree.

- **Underwater camera: handled.** `facing = step(surfaceY + 0.5, CameraPos.y) * step(rel.y, -0.01)`
  kills caustics for a submerged camera and for upward-looking rays. ✔
- **BUT the cut is binary**: swimming at the surface, the eye bobs across `surfaceY + 0.5` and the
  entire caustic field hard-toggles on/off frame to frame. Replace the outer `step` with a
  `smoothstep(surfaceY + 0.2, surfaceY + 0.8, CameraPos.y)`. *(low, 1-line)*
- **Rain: non-issue** (limbo dimension has no precipitation; the pipeline row is
  limbo-dimension-gated).
- **Other translucents**: water writes depth in the translucent pass, entities/hull reconstruct
  above the band — correct. Distant deck re-admittance: `eps = 0.55 + dist·0.012` reaches the
  deck's Δ≈2.1 at ~130 blocks, so far-away deck-height geometry regains *partial* caustic glow
  (full at ~300 blocks). The javadoc's "never re-admits the deck" claim only holds near-field.
  Cap `eps` at ~1.8. *(low)*
- **Hourly pop**: `Time` and `VoyageOffset` both wrap on the same 3 600 s modulus —
  `VoyageOffset` jumps ~1 980 blocks, fully decorrelating the caustic web once per hour (the sky
  pulse sines pop too). Cosmetic, but a wrap-to-period-multiple (`mod` by the noise tile period)
  would make it seamless. *(low)*

**Curvature warp (item 5) — smooth at the clamp, tears at silhouettes.**

- The border is fine: `edgeFade` (6 %/4 % smoothstep margins) + the `clamp(suv, 0, 1)` means no
  letterbox smear; `min(bend², 1)` is C¹. ✔
- **Silhouette tear (the real artifact):** `bend` derives from **this pixel's own depth**
  (`depth0`), so across a mast/rigging-vs-sky edge the warp jumps from ~0 (near geometry) to the
  full `0.085 · CurveAmount` (sky ⇒ `hd = FarDist`). Sky pixels beside the mast sample up to
  ~8.5 % of the screen lower — i.e. often the mast itself — smearing a ghost copy of rigging
  upward into the sky. In a scene whose only above-horizon content is the ship, this will be
  visible whenever the ship is against the sky mid-screen. Fix: compute `hd` from ray
  **elevation** (horizon proximity of the view direction) rather than per-pixel depth, or clamp
  the warp by the depth of the *destination* sample. *(medium-high)*
- The top/bottom `edgeFade` ramp compresses content ~1.4× locally inside the 6 % band — a subtle
  rubber-band at the screen top while pitching. Acceptable; widen to 10 % if noticed.

**Ambience/rest:** window pattern (spawn cadence, prune, disconnect reset) is the proven mote
pattern; loop sound single-owner with fade-in/out — clean. `LimboSpecialEffects` C2 disc
(low-pass dir, no-fog window, depth-test off) resolves the "glitchy purple thing" class of bug
correctly, and the reflection streak is mirror-locked to the same smoothed direction — good
craft. Aura pulse frequency (1.3 rad/s) deliberately matches the post shader's smear — nice.

## 2. Title screen — `gen_title_panorama.py`, `fix_logo_alpha.py`

- **Banding: measured, not guessed.** The shipped `panorama_*.png` were checked: the ±1.2 LSB
  pre-quantization dither works — longest identical-row run in a vertical gradient column is
  **1 px**, local σ ≈ 0.8 LSB. 512 px faces will *not* band. ✔
- **Star density sane**: 1 400 stars, upper hemisphere only, horizon-faded, disc-occluded.
  The 4 px edge-skip loses a statistically invisible sliver along cube edges at this density. ✔
- **One untestable-by-code risk**: seamlessness relies on the generator's face bases matching
  vanilla `CubeMap`'s uv→direction convention exactly (front/top edge continuity checks out on
  paper; a rotated top face would seam despite the "pure function of direction" argument).
  Needs one in-game eyeball of the zenith corners. *(verify)*
- **Logo alpha: real.** Shipped `logo.png` histogram: 69 456 transparent / 11 084 opaque /
  **1 380 feathered** px — the white box is gone and edges are genuinely feathered, with
  un-premultiply so no white halo. The whiteness key would eat white *highlights inside the
  glyph* if the art ever gains them — fine for the current dark glyph. `EclipseTitleScreen`
  blends it straight over the panorama with a pulse tint toward blue-violet — coherent.

## 3. 3D rift — `RiftRenderer` (5-shell)

- **Moiré/z-fighting: no.** All shells are additive with `depthMask(false)` — order-independent,
  nothing to fight. Counter-rotation at ±0.15–0.22 rad/s over 8–14-arm stars gives slow
  interference shimmer that the 90 ms flicker hash deliberately roughens — reads as intended
  "unstable static". Budget math in the javadoc (≤358 tris) checks out. ✔
- **Weakest viewing angle is the most common one**: STRUCTURE rifts open flat (normal = up) and
  are viewed from **directly below**. From there the 5 shells project with zero parallax (offsets
  are along the view axis), and the lightning-arc quads are extruded along the same normal —
  edge-on, near-invisible. The whole C7 volumetric upgrade mostly evaporates for the player
  standing under the reveal. Fix: extrude arc width camera-facing (billboard the ribbon like
  `StormWallRenderer.emitRibbon`), and consider a slight camera-facing bias on shell offsets.
  *(medium)*
- **Arc timing**: gate 0.45 per 90 ms per arc is a good strobe, but `baseAngle` re-rolls every
  270 ms — arcs *teleport* around the rim rather than "crawl" as the javadoc promises. Persist
  per-arc angles and drift them (`angle += hash·dt`) for genuine crawling. *(low-medium)*
- **Adaptive sizing law sane**: `max(footprint·√2·1.15, 4)` server-side, client clamp 1.5–48,
  glitch pulse scales with width but caps at 0.5, close tolerance scales with width. Tiny ruin ⇒
  ~8-block tear, trial chamber ⇒ clamped 48 — good spread; render cull 256 covers the reveal
  use case. ✔

## 4. Sphere storms — `StormWallRenderer`

- **THE bug of this review — tangent-arc window drifts with rotation.** For outside cameras,
  columns are placed at `a0 = camAngle − halfArc + i·step + rot` (cylinders) /
  `+ rot0` (sphere bands): the drawn 2·halfArc window is centered at **camAngle + rot**, not
  camAngle. `rot` grows unbounded (vortex 0.35 rad/s ⇒ full revolution ≈ 18 s; wall drift ≈ 157 s;
  sphere bands 0.08+ rad/s *per-ring-different* ⇒ ~78 s). The opaque occluder hides the far side,
  so the on-screen symptom is the near wall periodically losing its translucent churn and (for
  spheres) the rim-light sliding off the actual silhouette — standing close (halfArc ≈ 0.5 + margin)
  the dressed slice rotates away from you for most of each cycle, leaving bald occluder. Note the
  sphere rim factor already computes `edge` from `a0 − rot0 − camAngle` — the *color* math assumes
  camera-centered coverage that the *position* math doesn't deliver. Fix: place columns at
  `a0 = camAngle − halfArc + i·step` and fold `rot` into the noise/pattern lookup only
  (`noiseSeg = floor((a0 + rot)/step)`), which also preserves the "pattern moves with rot" intent.
  Repro: stand 5–10 blocks outside any vortex/sphere shell for 30 s and watch the churn/rim rotate
  off-bearing. *(high)*
- **Poles/seams: fine.** Band top-edge rotation (`rot1`) matches the next band's bottom edge —
  continuous shear ✔; the apex ring collapses to a point (`cos(π/2)`), dome self-closes, and the
  −0.16 rad skirt buries the rim ✔. Occluder dome mirrors the geometry ✔. Explosion path forces
  full-circle columns and drops the occluder immediately ✔.
- **Interior fog grade vs `world_grade`: a real hue conflict.** `storm_interior.fsh` still cools
  toward the *vortex blue-slate* (desat tint `0.86/0.83/1.05`, sky→`0.05/0.045/0.075`) with no
  sphere variant — only `RainAmount` is zeroed for spheres. The C8 identity ("green-violet, NOT
  the vortex slate") is carried solely by the fog color (`0.045/0.082/0.064`), which the post
  grade then desaturates back toward blue — inside a sphere the two pipelines mud each other into
  gray-green. Add a `Sphere` (or `GradeTint`) uniform fed by `interiorSphere`. Also note both
  `world_grade` and `storm_interior` are GRADE rows and stack at night (double crush) and that at
  >3 concurrent passes GRADE rows evict *first* — the green grade will drop during transitions
  (fog color survives, acceptable). *(medium)*
- Daylight readability ladder (base carve, additive boost, bolt widening) and the LOD crossfade
  are genuinely good; the fixed 48-gon occluder (EVAL-4 M4) is the right call.

## 5. Altar sky tiers — `AltarVeilSky`

- **L5 overdraw/saturation: mostly disciplined by radial separation** (ring 74, crown 58,
  glyphs 96, aurora 116–146, beams 58–162): steady-state additive stacking stays modest; only the
  pulse window pushes crown alpha toward ~0.57 + spikes — a deliberate flare. During the ceremony
  surge (`strength ×3.2`, `pulse = 1`) crown alpha computes to ~1.8 pre-clamp — it will white-clip
  gold around the disc for the beat. Intentional drama; if it reads blown at 1080p, cap
  `crownAlpha` at ~0.9. *(low)*
- **Echo ring retracts on the surge-out — reversed dramaturgy.** `travel = surge` on the ceremony
  path: the echo expands during surge-in ✔, then *parks* at radius 175 for the hold, then
  **contracts back into the crown** as `skySurge` decays 1→0. An echo should fire outward and
  dissipate. Give the surge echo its own 0→1 clock (e.g. `1 − surge` remapped, or reuse the
  natural `phase/PULSE_LENGTH` clock keyed off surge start). *(medium, small change)*
- **reducedFx degradation: graceful and legible.** Tier 2 full; tier 1 drops aurora + one beam
  layer + pulse beats, thins glyphs, ×0.6; tier 0 = ring only at half strength — the "altar level"
  tell survives every tier. ✔

## 6. HUD

- **DayTimerLayer collisions: clean.** Registered below `AnnouncementOverlay` *after* the vanilla
  status rows, so `Gui.leftHeight/rightHeight` are final when read. With hearts + food rendered,
  `statusStack + 3 ≥ 52` ⇒ digits occupy ≈ −69…−53; hearts top at −39, skill-XP numeral top at
  −35 (`LEVEL_BOTTOM_OFFSET 35`), bar at −29…−24, hotbar −22, offhand is left of the hotbar —
  no overlap in any stacking case checked (armor/absorption lift the block further). Nit: the
  documented `BOTTOM_ANCHOR 47` case is dead in survival (statusStack wins); comment or drop.
  Xbox-timer mutual exclusion (`XboxTimerLayer.active()`) prevents stacking ✔.
- **BossbarSkin max-2 + overflow: correct.** Vanilla bars are never hidden (early return before
  the cap), hidden skinned rows collapse via `setIncrement(0)`, "+N more" draws at the first
  hidden row's Y with the same scrim treatment, `observedBarsBottom` reserves the counter row for
  the announcement sweep, hidden bars leave no exit ghost, lerps stay warm. One accepted quirk:
  in a mixed stack (3 vanilla + 1 skinned) more than 2 rows show because only skinned bars can be
  capped — documented behavior. The A10 de-noising (no idle pulse, damage-only glow, time-based
  fill lerp) is exactly right.

## 7. Wand FX — 12 quasar emitter JSONs

- **Parameter sanity: good.** Burst emitters, `max_lifetime` 3–6 t, `rate` 1–2, `count` 6–15 ⇒
  ~18–45 particles per burst; lifetimes 7–26 t; sizes 0.07–0.42 with variation; gravity/drag
  per-family; gradients always end alpha 0. Nothing spammy; all spawns ride `FxBudget`.
- **THE palette bug: `purple_wisp.png` is lavender, not grayscale** (measured mean RGB of visible
  pixels **213/155/255** — green ≈ 0.61×blue). Every gradient multiplies against it:
  GLUT's `#FF9A4D`/`#FFB25E` fire-oranges render **salmon/brick**, STERN's `#FFD166` gold locks
  render **pink**, STERN's `#BFD9FF` ice-blue drifts violet. All three paths converge back toward
  violet — directly against the D10 goal of "one distinct composition per path". Fix: ship a
  white/grayscale `wisp_white.png` for the recolored families (or pre-divide the gradients by the
  sprite tint). *(medium-high, trivially cheap)*
- **Sparse risk**: `riss_wave_front` — 10 near-static cubes (speed 0.12, drag 0.55) across a
  3.2-block band will read as a dotted line, not a "scanline sweep"; bump `count` to ~18 and/or
  add a small along-band initial velocity. `stern_schauer_field` at 24 orbiting motes is thin for
  a "constellation ring" but is re-pulsed at the halfway beat — borderline OK. *(low-medium)*

## 8. Credits

- **Title-card beats land.** DE title (53 chars) decodes over ~116 t with rising-pitch typewriter
  ticks and a lock boom; hold 70 t; burst (t=650, white fade 8/6/10) fires **during the hold** —
  correct peak; correction card (t=665) arrives while the screen is still white, masking the
  ~15 t overlap with the doomsday card's fade-out. Auto-fit floor 0.8 keeps 320-wide GUIs safe.
  Correct call keeping the correction on `CaptionRenderer` TITLE — deadpan contrast to the gold
  decode. ✔
- **White-loading disguise: convincing.** Pure white + vanilla-worded "Landschaft wird
  generiert …" + a 99 %-asymptote counter (dropped under reducedFx) — the never-finishing
  percentage is the best gag in the sequence. Nit: `drawCenteredString` renders with a drop
  shadow, which reads slightly dirty on pure white — use the no-shadow overload for both lines.
  *(low)*
- `CreditsPanel` scrim + 3-step feathered edge over the sunrise is fine; lang-keyed roll with
  header grammar is clean.

## 9. Sound aliases

- Alias pitching is generally tasteful: `rift_open` = border_glitch @1.25 ✔, `rift_whoosh` =
  emerge @1.55 ✔, `rift_drone` = limbo_loop @0.42 + gazer_whisper @0.5 (creepy, good) ✔,
  `storm_flicker` = quiet border_glitch @0.5/0.45 vol matches the "silent flicker" design ✔,
  sphere-roar instance-pitch muffle bottoms at 0.58 — safely above the engine's 0.5 clamp ✔.
- **Wrong-source flag: `event.rift_slam` and `event.storm_shatter` are BOTH `ui/heart_shatter`
  at 0.5/0.45.** A UI glass-tink pitched down cannot carry a tyrant-death dome burst, and the two
  distinct dramatic events are near-identical. Layer `event/end_shatter_rumble` (already shipped)
  under `storm_shatter` and separate the pitches. *(medium)*
- `rift_thud` = submerge @0.62 may still read watery for "a chunk lands"; audition against
  end_shatter_rumble @1.2. *(low)*
- Latent phasing: three concurrent pitched copies of `limbo_loop` are possible (rift_drone 0.42 /
  storm_loop 0.8 / sphere_roar 0.68) if a rift opens near a storm — acceptable, but keep in mind.
- Arena stingers reuse UI aliases from code (`UI_ROULETTE_TICK` rising-pitch countdown,
  `UI_UNLOCK_STING` kit refresh @0.8, `UI_TIMER_ZERO` round end @0.7) — volumes/pitches sane.

## 10. i18n (German)

Full key parity (2 119/2 119). Quality is genuinely good — idiomatic, not machine-clunky:
"Der Fährmann gibt passend heraus" is a properly clever localization; the fake loading line
matches vanilla DE wording; timer day-unit "T" is wired to the `DayTimerLayer` glyph contract.
Nits:

- `subtitles.eclipse.event.rift_drone`: "Ein Riss **ächzt auf**" — "aufächzen" isn't standard;
  use "Ein Riss ächzt" or "Ein Riss knarrt auf". *(low)*
- Arena address inconsistency: "Mach dich bereit…" (singular) vs "KÄMPFT!" (plural) in the same
  countdown. Pick one (recommend plural "Macht euch bereit…"). *(low)*
- "Takedown(s)" anglicism with the "(s)" plural pattern is tolerable gamer-German but
  "Ausschaltung(en)" or restructuring to avoid the parenthetical would be tidier. *(low)*

---

## Consolidated fix list (priority order)

| # | Pri | Fix |
|---|-----|-----|
| 1 | HIGH | `StormWallRenderer.emitShell`/`emitSphereShell`: remove `rot`/`rot0` from the tangent-arc window start (`a0 = camAngle − halfArc + i·step`); fold rotation into the noise index only — coverage and rim-light currently drift off the camera bearing (vortex: full revolution ≈ 18 s). |
| 2 | HIGH | Add a grayscale wisp sprite (or pre-compensate gradients) for the 12 wand emitters — the lavender `purple_wisp.png` (G≈0.61) turns GLUT fire-orange salmon and STERN gold pink, killing path identity. |
| 3 | MED-HIGH | `limbo.fsh`: derive the curvature `bend` from ray elevation (or clamp by destination-sample depth) instead of per-pixel depth — sky beside near rigging warps ~8.5 % while the rigging doesn't ⇒ silhouette smear. |
| 4 | MED | `storm_interior.fsh`: add a sphere-variant uniform so the C8 green-violet interior isn't desaturated back to vortex blue-slate by the grade. |
| 5 | MED | `sounds.json`: give `event.storm_shatter` its own weight (layer `end_shatter_rumble`), decouple it from `event.rift_slam` (both are `ui/heart_shatter` @~0.5). |
| 6 | MED | `AltarVeilSky.drawCoronaCrown`: surge-path echo ring parks then retracts as `skySurge` decays — drive `travel` from a dedicated 0→1 surge clock. |
| 7 | MED | `RiftRenderer`: billboard the arc ribbon width toward the camera (arcs are edge-on from below a flat STRUCTURE rift) and persist/drift arc base angles so they crawl instead of teleporting every 270 ms. |
| 8 | LOW | `limbo.fsh`: smoothstep the `facing` camera-height cut (surface-swim caustic pop); cap band `eps` growth (~1.8) so distant deck-height geometry never re-glows; wrap `VoyageOffset` on a noise-period multiple (hourly pop). |
| 9 | LOW | `EclipseLoadingScreen.renderCreditsWhite`: draw both lines shadow-less for the vanilla-white disguise. |
| 10 | LOW | DE micro-fixes: "Ein Riss ächzt" (drop "auf"), plural "Macht euch bereit…" for arena parity, reconsider "Takedown(s)". |
| — | VERIFY | Eyeball the title panorama zenith corners in-game once (generator face-basis vs vanilla `CubeMap` top-face orientation). |
