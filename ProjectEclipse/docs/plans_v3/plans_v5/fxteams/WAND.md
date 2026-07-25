# WAND FX Team — Round D11 ("residue & ceremony")

Cluster: `quasar/emitters/{riss_*,glut_*,stern_*,arm_wisps,wand_soulbind_*}.json`,
`wand/WandPowers.java`, `wand/WandTickService.java` (+ the Phasenwelle FX block in
`wand/WandPhaseService.java`, which IS that power's FX code path). Visual/audio only —
zero balance, timing-of-damage or block changes. Verified via sandbox `javac --release 21`
(moddev merged jar + veil/geckolib + `build/classes/java/main` classpath) and
`json.load` over all 59 emitters (loop-law asserted for every payload-dispatched wand id).

Round theme (built on D10's per-path identity): every path now **leaves something
behind** — RISS scars reality, GLUT sheds ash and heat, STERN writes star maps — and the
first soulbind became a staged ceremony synced to the `wand_awakening` sting.

New emitters this round (all `loop:false`, budget-lean):
`riss_seam_scar`, `riss_maw_shimmer`, `glut_ash_flakes`, `glut_heat_column`,
`stern_constellation`, `wand_soulbind_orbit`, `wand_soulbind_flash`.

---

## RISS L1 — Blink

- **PLAN**: keep the D10 mirrored tear pair; add the requested afterimage doubling and
  make both endpoints leave 2 s "reality seam" scars.
- **IDEATE**: (1) full body-double ghost entity — rejected, entity spawn is not FX-budget
  territory; (2) laterally offset second `riss_blink_tear` at the departure point — the
  spot briefly reads as two overlapping selves ✔; (3) afterimage at the ARRIVAL —
  rejected, arrival already has the re-rez beat; (4) seam scar emitter: thin static line
  of voxel cubes, multi-peak alpha (glitch flicker) fading over ~1.8 s ✔; (5) a seam
  connecting from→to — rejected, payload has no orientation, axis-aligned long line would
  misalign with the blink ray; (6) scar sound: faint high "settle" chirp as seams appear ✔.
- **IMPLEMENT**: ghost tear at +3 t offset 0.35 perpendicular to the look ray; two
  `riss_seam_scar` at +5 t on both tear points + `border_glitch` 0.22/1.95.
- **POLISH 2**: scar alpha rewritten as 6-point flicker (0.85→0.35→0.7→0.3→0.5→0) so it
  reads glitch, not smoke; drag 0.9 pins the cubes in place.
- **POLISH 3**: budget audit — 7 emitter spawns in the cast window, exactly at the
  reducedFx BURST cap (7). Exactly AT cap the rate limiter alone sheds nothing, so the
  client sheds the seam scars (and the other D11 garnish cues) explicitly by id under
  reducedFx — the `QuasarSpawner.REDUCED_FX_GARNISH` set on the payload spawn path.

## RISS L2 — Phasenwelle

- **PLAN**: the scanline sweep must leave seams where it passed (the "effects passed
  here" case from the brief).
- **IDEATE**: (1) a seam on every de-rezzed block — rejected, up to 24 spawns; (2) seams
  riding the three band beats — rejected, that's simultaneous with the band, not
  "remains after"; (3) two seams at 30 %/75 % cone depth, 2–5 t AFTER the band passed ✔;
  (4) seam at the caster's feet — rejected, the caster already has the cast-hand beat;
  (5) restore-time seams when blocks knit back — rejected, restore is minutes later and
  crash-recovered, FX there would fire on boot sweeps; (6) raise seams 0.4 above foot
  level so they hang in the de-rezzed air ✔.
- **IMPLEMENT**: in the `castWave` FX block (WandPhaseService — that power's FX path):
  `riss_seam_scar` at +5 t (0.3·reach) and +8 t (0.75·reach), +0.4 y.
- **POLISH 2**: reach positions chosen between the band beats (1.5/0.55·reach/reach) so
  scars sit where a band just was, never where one is about to be.
- **POLISH 3**: confirmed no new imports into WandPhaseService (same-package statics);
  block engine, SavedData journal and audio untouched.

## RISS L3 — Rissschlag

- **PLAN**: pre-snap warning shimmer before the maw closes (brief: "schlag-maw gets a
  pre-snap warning shimmer").
- **IDEATE**: (1) re-fire the maw emitter smaller — rejected, reads as another gulp, not
  a warning; (2) dedicated `riss_maw_shimmer`: flickering torus ring just inside the maw
  lips, drifting INWARD (pre-suck) ✔; (3) camera shake tell — rejected, shakes are
  reserved for payoffs; (4) rising thin chirp under the shimmer ✔; (5) shimmer at
  openTicks−6, guarded for short-configured maws (openTicks < 10 skips it) ✔; (6) snap
  leaves a seam scar hanging where the maw was ✔ (path-wide residue rule).
- **IMPLEMENT**: shimmer + `border_glitch` 0.3/1.9 at openTicks−6; `riss_seam_scar` +3 t
  after the close tear (nested schedule — the task queue supports follow-ups mid-run).
- **POLISH 2**: shimmer point_force −0.8 → −1.2 so the inward drift actually reads at 8
  particle-ticks of life; double-peak alpha (0→0.75→0.25→0.8→0) for the flicker.
- **POLISH 3**: refactored the inlined `openTicks` param into a local so warning and
  close share one source of truth — close timing itself untouched (damage lands at cast,
  unchanged).

## GLUT L1 — Glutstoß

- **PLAN**: the ember lance leaves floating ash flakes.
- **IDEATE**: (1) ash along the whole ray — rejected, up to 24 spawn points; (2) ash at
  midpoint + impact only, 2 t after the lance beat passed ✔; (3) additive dark particles
  — rejected, additive black is invisible; the flakes are the path's ONE alpha-blended
  (non-glowing) emitter ✔; (4) cube render for flake read, gravity 0.05 + drag 0.3 for
  the slow flutter-down ✔; (5) fade-IN alpha (0→0.85 over 15 %) so flakes emerge from the
  flash instead of popping ✔; (6) soft campfire crackle under the impact ash ✔.
- **IMPLEMENT**: `glut_ash_flakes` at mid (+4 t) and impact (+6 t) +
  `CAMPFIRE_CRACKLE` 0.5/0.75.
- **POLISH 2**: base size 0.06 → 0.07 (flakes were sub-pixel past 20 blocks); fixed a
  lowercase hex typo (`#B9AFa6` → `#B9AFA6`).
- **POLISH 3**: 40±8 t flake life keeps the residue ~2 s, matching the RISS seam duration
  — the round's residue effects share one clock.

## GLUT L2 — Feuerwelle

- **PLAN**: the expanding ring ignites brief grass-tip flamelets (visual only — the
  ring's never-touch-a-block law is sacred).
- **IDEATE**: (1) quasar flamelet emitter per beat — rejected, the marching crescents
  already spend the path's emitter budget; (2) vanilla SMALL_FLAME licks just INSIDE the
  front (0.55–0.85·radius), 2 points every 4 ticks ✔; (3) one delayed re-lick per point
  (+3–6 t) so it flickers like a flamelet, not a spark ✔; (4) block-display flame decals
  — rejected, scorch decals already own the display-entity niche; (5) heightmap-snapped
  Y via the existing `groundY` clamp so slopes don't float flames ✔; (6) extra crackle
  layer — rejected, the existing FIRE_AMBIENT/LAVA_POP bed at age%8 already carries it.
- **IMPLEMENT**: in `FireWave.tick()` — gated on `radius > 1.5` so the caster isn't
  standing in flamelets on cast tick.
- **POLISH 2**: counts locked at 2+1 particles per point (≤ ~15 flame particles/s on top
  of the front — invisible against the front's 10–48/t budget).
- **POLISH 3**: verified lambda captures are effectively-final locals (fx/fy/fz) and the
  schedule is level-safe (dropped if the level unloads mid-march).

## GLUT L3 — Magmasprung

- **PLAN**: the crater gets a heat-shimmer column + slow smoke curl (launch scorch gets a
  short echo of it).
- **IDEATE**: (1) looping heat emitter until the decal dies — rejected, loop law for
  payload emitters; (2) one-shot `glut_heat_column`: center-anchored cylinder, faint
  (α ≤ 0.4) pale-ember billboards rising with slight velocity stretch = shimmer ✔;
  (3) smoke as quasar too — rejected, vanilla CAMPFIRE_COSY_SMOKE is exactly the "slow
  curl" and costs no emitter budget ✔ (3 beats × 2 particles at +10/+24/+38 t);
  (4) shimmer on launch too, smaller — ✔ (the take-off scorch smolders for a second);
  (5) steam hiss (FIRE_EXTINGUISH 0.35/0.6) as the smoke starts ✔; (6) ash flakes here
  too — rejected, ash is the lance's signature; keeping vocabularies distinct per power.
- **IMPLEMENT**: landing (in `MagmaJump.tick()` touchdown) + launch (in
  `castMagmasprung`).
- **POLISH 2**: smoke count kept to 2/beat — COSY_SMOKE is huge, more looks like a house
  fire.
- **POLISH 3**: caught a real bug — the column was spawned at +0.3 but the cylinder shape
  is CENTER-anchored (stern_funke_fall convention), which would bury half the column.
  Both call sites moved to +1.4 so the base sits on the crater.

## STERN L1 — Funkenruf

- **PLAN**: sparks leave micro-constellations that connect-the-dots, then fade.
- **IDEATE**: (1) pre-computed constellation shapes — impossible, emitters can't take
  per-spawn geometry; (2) 5 near-static star points with hairline `veil:trail` lines —
  slow drift draws the connecting lines organically ✔; (3) trails between DIFFERENT
  particles — not supported by quasar, drift-trails approximate it ✔; (4) twinkle via
  multi-peak alpha (0.95→0.55→0.9→0.5→0) ✔; (5) constellation at the sky origin —
  rejected, the payoff surface is the impact; spawned at +1.1 over it ✔; (6) one very
  quiet 1.95-pitch chime as the map appears ✔.
- **IMPLEMENT**: `stern_constellation` at +4 t after the strike (needle + pillar beats
  land first, the map is what REMAINS).
- **POLISH 2**: trail width 0.03/length 12 — hairlines, not ribbons; drag 0.12 so the
  dots settle mid-life and the finished "map" holds still before fading.
- **POLISH 3**: white→ice-blue→gold gradient matches the D10 STERN identity ramp exactly
  (same stops as the cast hand); 34 t life keeps it inside the ~2 s residue clock.

## STERN L2 — Sternschauer

- **PLAN**: field finale — all pillars pulse once in sync after the last star.
- **IDEATE**: (1) re-fire pillars at every impact — up to 12 spawns in one tick, over
  budget; (2) sample landed impacts down to ≤ 6 by stride and pulse those ✔; (3) pulse
  the telegraph ring instead — rejected, the brief says pillars; (4) collect impact
  positions in a captured list as each scheduled star lands ✔ (server tick is
  single-threaded, plain ArrayList); (5) finale audio: ONE held resonate + one high chime
  at the median impact, instead of 6 stacked sounds ✔; (6) sync shake — rejected, the
  last star already carries the field's shake; the finale is light, not another hit.
- **IMPLEMENT**: finale at telegraph+duration+6 t; guarded for zero-landed (level
  unloaded mid-shower drops star tasks).
- **POLISH 2**: pulse height +1.6 matches the per-star pillar spawn height — identical
  pillar read, so it registers as "the same pillars again", which is the point.
- **POLISH 3**: budget — 6 pulses in one window ≤ reducedFx BURST cap (7); stride
  sampling keeps the pulse spatially spread instead of clustering on early impacts.

## STERN L3 — Kometenschlag

- **PLAN**: the descent casts a growing ground light circle before impact.
- **IDEATE**: (1) quasar disc emitter per beat — 3 more emitter spends on an already
  emitter-heavy power; (2) vanilla END_ROD rings (14 motes) with growing radius riding
  the EXISTING descent beats ✔ (zero quasar budget); (3) an FX point light growing on the
  ground — rejected, light slots are precious (16 global) and the impact strike already
  brings one; (4) three radii 0.35/0.6/0.9·radius at telegraph−8/−4/−1 — the circle
  visibly swells as the comet closes ✔; (5) rising chime ladder (1.0→1.25→1.5) tracking
  the growth ✔; (6) full disc fill — rejected, a ring reads "landing zone", a disc reads
  "already burning".
- **IMPLEMENT**: new `groundLightRing` helper in WandPowers; third beat added at
  telegraph−1 (rings only — the comet core beats stay 2, unchanged).
- **POLISH 2**: ring y at +0.25 with 0.05 vertical jitter so the circle hugs the ground
  without z-fighting into it.
- **POLISH 3**: damage timing audited — impact still lands exactly at `telegraph`;
  everything added sits strictly BEFORE it (readability buff for the target, as briefed).

## Cast-hands ×3 (riss/glut/stern_cast_hand)

- **PLAN**: brief says "charge-up intensity scales with hold time if the code exposes
  it". **Checked the cast flow: it does not** — `EclipseWandItem#use` sends
  `C2SWandCastPayload` on the instant click; there is no use-duration/hold anywhere in
  the chain. Substitute intensity signal chosen: the cast's charge COST.
- **IDEATE**: (1) hold-time scaling — impossible (above); (2) per-cost emitter scale
  param — payload carries no params; (3) heavy casts (cost ≥ 30: rissschlag, feuerwelle,
  sternschauer, kometenschlag, phasenwelle + their _2 re-runs) fire a second flourish pop
  one tick later, 0.28 above the hand — reads as the flourish SWELLING ✔; (4) louder,
  lower-pitched path voice for heavy casts (RISS 0.45/1.5, GLUT 0.4/0.55, STERN
  0.55/1.7) ✔; (5) caster shake 0.06 → 0.08 on heavy (still caster-only, still tiny) ✔;
  (6) new charge-up emitter trio — rejected, the D10 hands are good; doubling them scales
  without new assets.
- **IMPLEMENT**: `castFlourish` now takes the `Power`; `HEAVY_CAST_COST = 30` documented
  as the one intensity signal the instant-click flow exposes.
- **POLISH 2**: echo rides +1 t (not same tick) so light/heavy differ in RHYTHM, not just
  quantity — a double-tap you can feel.
- **POLISH 3**: JSONs of all three hands untouched (identity frozen); config-edited costs
  move a power across the threshold automatically — no hardcoded power list.

## Soulbind moment (`handleChoosePath`)

- **PLAN**: first-bind ceremony — wisps orbit converging into the wand, one white flash,
  `wand_awakening` sting timing sync.
- **IDEATE**: (1) reuse `arm_wisps` — rejected, it's `loop:true` and the payload law
  forbids dispatching looping ids; (2) one-shot `wand_soulbind_orbit`: torus spawn,
  vortex 1.5 + inward point_force 1.8, white trail wisps spiraling into the wand over
  ~1 s ✔; (3) path-tinted ceremony — rejected, the bind is the WHITE moment; the chosen
  path's color arrives via its cast-hand ON the flash beat ✔; (4) `wand_soulbind_flash`:
  3 large (3.2) white billboards, 6 t life — one clean pop, modeled on `impact_light`
  but on the white sprite ✔; (5) sting sync: move `MusicCues.play("wand_awakening")`
  onto the flash tick (t+18) so the musical downbeat and the flash land together ✔
  (previously the sting fired at cast tick, 0.9 s before anything converged); (6) shake
  on the flash — rejected, this is a private ceremony, not an impact.
- **IMPLEMENT**: t0 orbit + soft resonate + ANIM_AWAKEN; t7 second orbit pulse (tracks
  the player); t18 flash + path cast-hand + celebration bursts + beacon + sting, guarded
  by `hasDisconnected()` (a player who logs out mid-ceremony keeps the sting unplayed
  rather than firing packets at a gone connection).
- **POLISH 2**: orbit alpha fades IN (0→0.95 over 15 %) so wisps materialize out of the
  dark instead of popping; trail width 0.04 for the comet-hair look.
- **POLISH 3**: ceremony budget = 7 emitter spawns across 26 ticks — inside the reducedFx
  window cap; death (not disconnect) during the 18 t deliberately still completes the
  ceremony: the path IS locked, the moment belongs to the player.

## arm_wisps.json — audited, unchanged

In-cluster but not briefed for changes. Kept as-is deliberately: it is the arm
artifact's looping attached emitter (also TheOther's despawn cue) — its purple-sprite ×
purple-gradient double-tint is that artifact's established look, and re-tinting it would
change non-wand content outside this round's mandate.

---

## Verification

- `javac --release 21 -proc:none` over `WandPowers.java`, `WandTickService.java`,
  `WandPhaseService.java` against the moddev merged jar + veil/geckolib +
  `build/classes/java/main`: **0 errors**.
- `python3 json.load` over all 59 emitter JSONs: **all parse**; asserted `loop:false` on
  every payload-dispatched wand id (riss_*/glut_*/stern_*/wand_soulbind_*).
- NOT verified by this team: `./gradlew build` (out of mandate). Note for the
  integrator: `stormfx/StormWallRenderer.java` is broken in the current tree (calls 4
  undefined methods — `emitExplosionShards`, `emitClearSkyRing`, `emitTyrantSilhouette`,
  `explodeRadiusScale`); pre-existing, another cluster's mid-flight work, untouched here.

## Budget & reducedFx audit (worst cases, BURST channel: 15/s full, 7/s reduced)

| Cast | Spawns/s (worst window) | Note |
| --- | --- | --- |
| Blink | 7 | seams shed under reducedFx by the client garnish id set |
| Rissschlag | 5 + 2 late | shimmer/close in a later window |
| Phasenwelle | 6 | bands + seams staggered 0–8 t |
| Glutstoß | 6 | ash rides +4/+6 t |
| Feuerwelle | ~6 | unchanged emitter cadence; flamelets are vanilla |
| Magmasprung | 3 launch / 2 landing | smoke is vanilla |
| Funkenruf | 4 | — |
| Sternschauer finale | 6 | ≤ reduced cap by construction |
| Kometenschlag | 7 | rings are vanilla END_ROD |
| Soulbind ceremony | ≤ 5 per window | spread across 26 t |

All sounds are existing registered events (`EclipseSounds.*` + vanilla) — `sounds.json`
untouched, no new oggs, no new aliases needed.
