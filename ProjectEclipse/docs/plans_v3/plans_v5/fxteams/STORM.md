# FX Team — STORM (round: next-level pass)

Team process per component: PLAN → IDEATE 6+ → IMPLEMENT → POLISH 2 → POLISH 3.
Cluster: `storm_interior` post (fsh/json), `stormfx/StormWallRenderer.java`,
`StormInteriorFx.java`, `StormFxClient.java`, quasar emitters `storm_arc.json`,
`storm_rain_sheet.json`, plus the fog-storm sphere interior kit.

Context from last round (frozen): sphere-type site storms with green-violet interior grade
(`Sphere` uniform), camera-centered tangent-arc walls (EVAL-POL-F #1), explosion on Tyrant
death (`STATE_EXPLODE`). Hard rules this round: never-see-inside occluder untouched, wire
format untouched (`S2CStormStatePayload` is FROZEN), reducedFx ladder + FxBudget caps
respected (STORM channel 12/window full / 6 reduced, ≤ 1500 live particles, ≤ 16 lights),
uniforms `Interior/RainAmount/Time/Sphere` frozen (additive-only uniform growth allowed).
Self-checks: `glslangValidator` on the composed fsh, full-tree `javac` against the moddev
classpath, `json.load` on every touched emitter. No gradle, no git.

"Tyrant alive" proxy (no wire change): a SPHERE storm in `STATE_ACTIVE` *is* the living
Tyrant's storm — `explode()` is his death beat — so silhouette beats key off ACTIVE, not
off a new flag.

---

## Component 1 — `StormWallRenderer.java` (wall + explosion geometry)

### PLAN
The sphere dome reads as ONE churn layer; the brief asks for depth (two-layer churn),
life on the surface (crawling lightning veins), grounding (dust skirt), a crown beat for
the vortex, a 4-stage explosion, and the alive-Tyrant silhouette. All of it must stay
per-vertex procedural (zero textures, zero per-frame heap), keep the camera-centered
tangent-arc window, and never touch the occluder guarantee. Quad-budget envelope: ≤ ~150
extra quads near-tier steady-state, ≤ ~100 extra during the 2 s explosion.

### IDEATE
1. **Two-layer churn** — per-shell noise clocks + band-lead multipliers: outer additive
   shell becomes the SLOW BILLOW (coarse noise cells, ~1/3 pattern speed, 0.6× band
   lead), inner additive shell becomes the FAST SHEET (fine cells, ~2.5× speed, 1.5×
   lead, counter-drift). Zero new quads. **CHOSEN**
2. **Lightning veins with UV crawl** — per (longitude-cell, shell) hash gate opens a vein
   for ~2 s; a bright head crawls UP the latitude range (`fract(time·speed + hash)`),
   columns near the head lerp toward white and gain alpha. Color-only, zero new quads,
   outer shell + near tier + quality tier ≥ 1 only. **CHOSEN**
3. **Vortex crown swirl** — second counter-rotating collar band above the cone rim
   (48 columns, opposite twist, 0.8× speed) so the cap reads as a sheared double swirl.
   **CHOSEN**
4. **Ground skirt dust** — flared low-alpha dust band (`r+2.2 → r+0.3` over `y∈[cy−1,
   cy+2.5]`) where the wall meets terrain, near tier, alpha pass; warm-gray neutral so it
   reads as kicked-up dust, not palette. Spheres + wall cylinders (not the vortex — its
   base is the intro crater). **CHOSEN**
5. **Multi-stage explosion** — stage curve on `explodeProgress`: implosion pinch (radius
   −10% over the first 18%), white flash retimed to peak at pinch release, expansion to
   the frozen 1.8× extra radii, plus ≤ 22 wall-fragment shard cross-quads riding the ring
   that dissolve via hash flicker ("glitch voxel" alpha gating), plus a late thin
   clear-sky bloom ring (last 40% of the burst). **CHOSEN**
6. **Tyrant wall silhouette** — while a sphere storm is ACTIVE and the camera is interior,
   every silhouette flicker (`StormInteriorFx.flash`) pins a ~7-block dark humanoid
   cutout (5 quads) to the inner wall at a per-flicker hash bearing near the camera
   bearing, alpha riding the flash lift with a hash strobe. Dead Tyrant (EXPLODE) never
   draws it. **CHOSEN**
7. Per-column sun-side self-shadowing of the wall. **REJECTED** — the daylight carve
   (EVAL-4) already buys the daytime read; extra dot-product per column for little gain.
8. Parallax far-side dome rendered dimly through the near side. **REJECTED** — fights the
   never-see-inside guarantee (R14/R15 frozen) and Sodium depth-sort risk.
9. Exterior rim god-rays streaming off the dome silhouette. **REJECTED** — the interior
   god-fingers own the light-shaft read; exterior shafts would imply the dome leaks light.

### IMPLEMENT
- Two-layer churn: `SPHERE_CHURN_TICKS {9,5,2}` + `SPHERE_BAND_LEAD {0.6,−0.8,1.6}` per
  sphere shell (outer billow also coarsens to 2-column noise cells); cylinders get
  `SHELL_CHURN_TICKS {8,5,3,2}` replacing the old parity split. Zero new quads.
- Veins: gate `hash > 0.80` per 4-column longitude cell re-rolled every 44 t; head
  `fract(time·0.016 + hash)` crawls base→apex in ~3 s; columns within ±0.16 latFrac of the
  head lerp toward white and gain up to +0.40 additive alpha. Outer shell, near tier,
  tier ≥ 1, suppressed during the burst.
- Ground skirt: flared dust band (`r+2.2+jitter → r+0.3`, `y ∈ [cy−1.2, cy+2.6]`, neutral
  `DUST_*` gray) on the main alpha shell — sphere equator ring + wall cylinders, near tier.
- Crown swirl: 48-column counter-rotating collar (−0.8× swirl speed, −0.5 twist) under the
  vortex cone rim.
- Explosion: `explodeRadiusScale` = 10% pinch over the first 18% (releasing by 2.2×18%),
  then eased t² expansion to the frozen 1.8× extra radii; `explodeWhite` retimed to charge
  through the implosion (→0.55) and PEAK at pinch release; `emitExplosionShards` (22/12
  cross-quad shards, hash-strobed glitch dropout with odds rising along the flight,
  band-palette→white); `emitClearSkyRing` (thin pale ground ring, 60→100% of expansion).
- Tyrant silhouette: `emitTyrantSilhouette` — 4 `silQuad`s (legs/torso/shoulders/head,
  ~7.5 blocks, swaying, wrong proportions), pinned at `r − OCCLUDER_INSET − 1.5` at a
  per-flicker hash bearing (±0.8 rad off camera), alpha = 0.85 × `flashAmount()`, extra
  hash strobe, ACTIVE spheres + interior camera + vis ≥ 0.8 only.

### POLISH 2
- **Bug found & fixed:** the deep-interior d² early-out in `buildShells` returned before
  the silhouette could ever draw (the camera is always deep interior when it matters).
  The silhouette now draws inside that early-out branch, before the return.
- **Vein continuity fix:** the vein gate hashed the per-ring ROTATED pattern index, so
  band leads broke veins apart vertically; the gate/head now hash the RAW angle cell, so
  one vein lines up across every latitude band it crosses (the crawl supplies the motion).
- Vein glow now rides `DAY_ADDITIVE_BOOST` like every other additive alpha (noon washout).

### POLISH 3
- Class javadoc updated with the FX-STORM paragraph (churn layers, veins, skirt, crown,
  staged burst, silhouette + the occluder-guarantee note: the Tyrant is drawn ON the
  occluder, never through it).
- Budget audit: steady-state additions are color math + ≤ ~150 near-tier quads (skirt ≤ 96,
  collar 48, silhouette 4); burst additions ≤ ~92 quads for 2 s. No allocations added to
  any per-frame path. `javac` + composed-fsh `glslangValidator` green.

---

## Component 2 — `StormInteriorFx.java` (interior kit)

### PLAN
The sphere interior kit (motes, ribbons, flickers, drone, pulses) gets its hero beats:
god-fingers of light, ash-devil mini-whirls, the explosion's clear-sky bloom; the vortex
interior gets rotating rain sheets with roar-timed wind gusts. Everything runs through
the existing gates (`SPHERE_AMBIENCE_GATE`, reducedFx cadences, STORM channel) and the
teleport-snap/reset hygiene. New cross-talk surface: `gustAmount()`, `flashAmount()`,
`flashSerial()`, and a smoothed wall-proximity scalar feeding the new `WallProx` uniform.

### IDEATE
1. **God-fingers through the eye** — up to 2 managed loop emitters (new
   `storm_godfinger.json`) drifting slowly around the storm center at ~0.35r offset,
   engaged above 0.5 interior within 48 blocks of center; tier 2 = 2 fingers, tier 1 = 1,
   tier 0 = none. Pale sick-green shafts — light through the dome apex "eye". **CHOSEN**
2. **Rotating rain sheets** — vortex interior: sheet spawn bearing advances ~0.02
   rad/tick instead of uniform random, so the sheets orbit the player like a rain band.
   **CHOSEN**
3. **Wind-gust bursts timed to the roar loop** — 160-tick gust clock (= the 8 s roar-loop
   bar) with a 30-tick smoothstep gust envelope: rain interval halves, the grade's
   `RainAmount` lifts ×1.35, the roar loop volume rides `gustAmount()` (+18%), wisp rise
   accelerates. One clock, four consumers. **CHOSEN**
4. **Ash-devil mini-whirls** — 2 whirl anchors (1 reduced) wandering 8–16 blocks from the
   camera near the ground; each spawns 1 tangential-velocity ASH/WHITE_ASH per cadence
   tick spiraling upward; anchors re-seed every ~9 s. Raw `addParticle`, sphere interior
   only. **CHOSEN**
5. **Clear-sky bloom moment** — when the explosion white-out expires, a 40-tick bloom
   tail lifts the fog color gently toward pale morning blue-white (feathered by the
   original white-out strength) before releasing — the "sky opens" beat. **CHOSEN**
6. **WallProx cross-talk** — smoothed 0..1 "how close inside the shell" scalar (1 within
   ~2 blocks of the occluder band, 0 at 10 blocks in), feeding the shader's heat-shimmer;
   also `flashAmount()`/`flashSerial()` accessors so the renderer can pin the Tyrant
   silhouette per flicker. **CHOSEN**
7. Gust-synced camera push/screen shake. **REJECTED** — accessibility risk (motion), and
   the gust already reads through rain + roar + rain-uniform lift.
8. Creaking/groan positional stingers under ash devils. **REJECTED** — audio-spam risk
   next to the drone + pulses; heartbeatSound() opt-out semantics would get murky.
9. Warm ember motes spiraling into god-finger beams. **REJECTED** — warm hue is reserved
   for the loot-camp beacon (IDEA-15 §3); polluting it breaks the "over there" language.

### IMPLEMENT
- Gust clock: `tickGust()` — 160 t period, 30 t envelope (smoothstep, 40% attack / 60%
  release), scaled by `smoothedInterior`; exposed as `gustAmount()`.
- Rain: `rainAngle` advances 0.02 rad/t (×2.5 in gusts) and sheets spawn on that bearing
  (±0.6 rad, 2–7 blocks out); cadence halves while `gust > 0.5`; the grade rain uniform is
  fed `interior × (1 + 0.35·gust)` (still hard-zero in sphere interiors).
- God-fingers: `tickGodFingers()` — ≤ 2 managed `storm_godfinger` loops at `0.35r` off the
  eye, `0.45r` up, drifting ±0.003 rad/t in opposite directions; engage: sphere interior
  > 0.5 within 48 blocks of center; ladder 2/1/0 by quality tier; refused spawns retry
  next tick (wisp rule); released in `reset()` and the moment the gate drops.
- Ash devils: 2 anchors (1 reduced, cadence also halved) re-seeded every 180 t at 8–16
  blocks; anchor wanders; one tangential ASH (1-in-5 WHITE_ASH) per cadence tick spirals a
  0.5–1.1-radius column ~2.5 blocks tall.
- Clear-sky bloom: white-out expiry hands its strength to a 40 t `bloomTicks` tail that
  lerps the fog color toward pale morning blue-white (≤ 0.35 blend) — the sky-opens beat.
- Cross-talk: `wallProxTarget` (1 at the fully-interior line → 0 eight blocks in, scaled
  by the interior amount) smoothed with the standard 0.16 ease + teleport snap, fed to the
  new `WallProx` uniform; `flashAmount()`/`flashSerial()` accessors (serial bumps only on
  a FRESH flicker so the silhouette bearing holds for the whole flicker).

### POLISH 2
- God-fingers now verify the nearest storm is actually a SPHERE before using its center
  (a wall storm could be nearest while sphere-interior is latched at range edges).
- Confirmed `rainAngle` only advances behind the existing interior gate (no drift while
  outside), and gust cadence floor is 4 t (max 5 STORM spawns/window — see budget audit).

### POLISH 3
- Class javadoc updated with the FX-STORM paragraph. `reset()` audited: gust, bloom,
  wall-prox, devils and god-fingers all clear on logout/respawn (M5 hygiene); drone,
  camp light, rain unchanged.
- Budget audit at full tier: rain ≤ 5/window (gust worst case), god-fingers ≈ one-time
  spawns + retries, devils/motes/ribbons are vanilla `addParticle`; STORM channel worst
  case ≈ 7/12 per window with arcs. reducedFx: everything halves or drops a finger/devil;
  tier 0 loses god-fingers (and veins on the wall).

---

## Component 3 — `StormFxClient.java` (orchestration + audio coupling)

### PLAN
Own the explosion's particle staging (matching the renderer's stage curve), couple the
roar loop to the gust clock, and keep every cadence inside the STORM channel budget.
No new lists, no per-frame allocation in hot paths.

### IDEATE
1. **Explosion stage machine in `tickExplosionDebris`** — progress < 0.18: implosion
   (debris spawns ON the shell with INWARD velocity, no smoke column — the suck-in);
   0.18–0.35: quiet flash beat (white owns the frame, minimal spawns); > 0.35: expanding
   debris ring on the same radius law as the renderer + rising center column. **CHOSEN**
2. **Glitch-voxel shard support** — during the expansion stage, ~1 `border_glitch`
   emitter burst per 5 ticks on the ring (its strobing alpha ladder IS the glitch-voxel
   dissolve), STORM-channel charged, tier ≥ 1 only. **CHOSEN**
3. **Roar-gust coupling** — `StormLoopSound.tick()` volume rides
   `StormInteriorFx.gustAmount()` (+18% at gust peak) so the roar swells exactly when
   the rain sheets burst. **CHOSEN**
4. **Gust-riding wisps** — vortex wisp rise speed ×(1 + 0.5·gust): the updraft gusts with
   the same clock. One line. **CHOSEN**
5. Exterior base-dust particle ring near walls. **REJECTED** — the renderer's skirt band
   does it for free; spending STORM budget on standing storms fights arcs/rain.
6. Arc scheduling biased toward live vein positions. **REJECTED** — veins are
   renderer-local color math; sharing state across the render/tick boundary for a
   coincidence nobody can verify on screen isn't worth the coupling.
7. Double-strike echo bolts during the explosion. **REJECTED** — the death beat is
   white-out + shockwave; extra bolts fight the read and the light budget.

### IMPLEMENT
- `tickExplosionDebris` staged on `StormWallRenderer.EXPLODE_IMPLODE_FRAC` (shared
  constant — the client and renderer can never drift apart): implosion = 6 (3 reduced)
  inward-streaming CLOUD/LARGE_SMOKE per tick ON the shell, no column; flash beat
  (0.18–0.30) = one ash flake per 4 t; expansion = the debris ring moved onto the
  renderer's eased `1 + 1.8·t²` law + the center column + one `border_glitch` strobe
  burst per 5 t on the ring (STORM-charged, tier ≥ 1).
- `explodeWhite` retimed in `ClientStorm` (charge → peak at pinch release → 15 t decay).
- `StormLoopSound.tick()` volume rides `gustAmount()` (+18% peak, clamped ≤ 1.0).
- Vortex wisp updraft rides the same gust (+50% rise at peak) — one line, same clock.

### POLISH 2
- Volume clamp added (0.85 × 1.18 fractionally exceeded 1.0).
- Verified EXPLODE still bypasses arcs/wisps/dread (early return in `tickStorm`) so the
  staged debris is the only particle voice during the burst.

### POLISH 3
- Re-checked budget: glitch bursts are 4/s for ~1.6 s once per Tyrant death — transient
  ≤ 4/12 window spend on a channel with no other sphere traffic at that moment (arcs are
  gated off, rain is sphere-zero). Javadoc on the debris method documents the stages.

---

## Component 4 — `storm_interior` post (`storm_interior.fsh` + pipeline jsons)

### PLAN
Two shader beats from the brief: interior depth-fog with a height gradient (ground mist
that thickens with distance and screen depth) and subtle heat-shimmer refraction near the
wall inside. Frozen uniforms stay; one additive uniform (`WallProx`) is allowed because
`StormInteriorFx` owns the feeder row. Iris note unchanged: the whole pipeline is gated
off under shaderpacks, so no Iris interaction to re-audit.

### IDEATE
1. **Depth-fog height gradient** — non-sky pixels sink toward the storm palette with
   `depth^` falloff × a screen-space height gradient (bottom of frame = denser mist), so
   the ground ahead drowns first — the "wading through it" read. **CHOSEN**
2. **Heat-shimmer refraction near the wall** — `WallProx`-scaled UV wobble
   (`efxNoise`-driven, ~0.004 UV max, vertically rising), computed BEFORE the first
   sample; depth is sampled at the same wobbled UV so the sky mask can't halo. **CHOSEN**
3. Gust shear in the rain streaks. **CHOSEN (free)** — no shader change needed: gusts
   ride the already-fed `RainAmount`, and layer 3 of `rainLayer` already wind-shears.
4. Radial blur burst during flashes. **REJECTED** — extra taps per pixel every frame for
   a 6-tick event; the fog-plane lift already carries the flash.
5. Interior film grain. **REJECTED** — the global grade owns grain; layering doubles it.
6. Chromatic aberration at the vignette edge. **REJECTED** — glitch language belongs to
   rift/border FX; the storm should feel thick, not digital.
7. Depth-edge silhouette boost for entities during flashes. **REJECTED** — needs
   normals/entity IDs the post pass doesn't have.

### IMPLEMENT
- `uniform float WallProx` added (fed by `StormInteriorFx`; used, so never optimized out).
- Heat shimmer: two `efxNoise` fields (34/21 UV scale, opposing drifts) bend the sample UV
  by ≤ 0.8% × `WallProx` × `Interior`, computed BEFORE the first color sample; the depth
  read moved to the same wobbled UV so the sky-sink mask can't halo around bent geometry.
- Depth-fog height gradient: `smoothstep(0.995, 0.9998, depth)` mist window (× non-sky),
  palette-matched mist color per `Sphere`, weighted `0.18 + 0.38 × (1 − smoothstep(0,
  0.75, texCoord.y))` — densest low in the frame.
- Rain overlay + vignette still sample/weigh at the un-wobbled `texCoord` (screen-space
  layers must not shimmer).

### POLISH 2
- **Retune found & fixed:** the first mist window (`0.97 → 0.9999`) maps to ~2 blocks on
  a hyperbolic depth buffer (near ≈ 0.05) — it fogged essentially the whole frame. New
  window `0.995 → 0.9998` ≈ 10 → 56 blocks: ramps across the pinched fog band AND keeps
  misting through the 24→56 flash lift, so flash-revealed silhouettes stay smoky.
  Strength softened 0.25+0.55 → 0.18+0.38.

### POLISH 3
- Header comment documents the new uniform and both effects. Frozen uniform set untouched
  (additive-only growth). Composed-source `glslangValidator -S frag` green.

---

## Component 5 — `storm_arc.json` (shell arc crackle emitter)

### PLAN
The arc crackle should read as a whip-crack of the wall surface: brighter, snappier,
cheaper. Spawn cadence is Java-owned and untouched; only the per-spawn particle read
changes.

### IDEATE
1. **Whip-crack dynamics** — velocity stretch 1.2 → 1.7, drag 0.08 → 0.14 (violent start,
   dead stop), lifetime 5 → 4. **CHOSEN**
2. **Hotter core, earlier violet handoff** — white → pale-lilac at 25% → deep violet;
   alpha starts 1.0 and dumps faster. **CHOSEN**
3. **Count 6 → 5, size 0.22 → 0.26** — same visual mass, −17% particles per crackle
   (arc-count budget headroom for the vein-rich walls). **CHOSEN**
4. Ember drip second stage (gravity). **REJECTED** — arcs are surface electricity, not
   matter; drips read as sparks from a grinder.
5. Dedicated spark sprite. **REJECTED** — zero-new-textures doctrine; stretched
   `purple_wisp` already reads as a spark at 1.7× stretch.
6. Green arc variant for sphere storms. **REJECTED** — arcs are gated OFF inside spheres
   (C8 lightning-less interiors); exterior arcs keep the violet identity everywhere.

### IMPLEMENT
- `count 6 → 5`, `base_particle_size 0.22 → 0.26`, `particle_lifetime 5 → 4`,
  `velocity_stretch_factor 1.2 → 1.7`, `drag 0.08 → 0.14`, gradient
  `#FFFFFF → #E3D2FF@0.25 → #7B4FD0` with alpha `1.0 → 0.6@0.5 → 0`.

### POLISH 2
- Cross-checked against the bolt ribbons: the arc crackle now dies (4±2 t) inside the
  5 t `ARC_LIFE_TICKS` ribbon window, so the burst and the ribbon release together.

### POLISH 3
- JSON re-validated; per-crackle particle count −17% (5 × ~4 t) — headroom noted in the
  budget table for the vein-rich walls. No schema fields beyond those already used by
  sibling emitters.

---

## Component 6 — `storm_rain_sheet.json` (+ new `storm_godfinger.json`, interior kit)

### PLAN
Rain sheets should read as wind-driven curtains (they now orbit + gust from Java), and
the sphere interior kit gains its god-finger emitter. Loop-emitter caps unchanged
(≤ 3 sheets, ≤ 2 fingers, all `spawnManaged` on STORM).

### IDEATE
1. **Curtain stretch** — velocity stretch 1.6 → 2.2: longer streaks, sheet-like. **CHOSEN**
2. **`veil:wind` lateral shear** — slow sideways drift so sheets travel as curtains
   instead of falling in place. **CHOSEN**
3. **Cooler, deeper slate** — gradient nudged toward the wall's ALPHA slate; peak alpha
   0.28 → 0.31 (gusts read better against the fog). **CHOSEN**
4. **`storm_godfinger.json` (new)** — loop, rate 8/count 1/max 8, tall thin cylinder
   (1.4 × 9), size 4.5 ± 2.5, life 70, slow sink, additive pale sick-green gradient at
   ≤ 0.12 alpha: a soft volumetric shaft, not a laser. **CHOSEN**
5. Ground splash sub-emitter. **REJECTED** — `should_collide` stays false by perf design;
   fake splashes at a guessed ground Y would float.
6. One big sheet instead of 2 small. **REJECTED** — two small particles layer into a
   churning sheet; one big billboard flickers as it turns.
7. Rate changes for gusts in JSON. **REJECTED** — JSON is static; Java owns the gust
   cadence by halving the spawn interval (cleaner, budget-checked).

### IMPLEMENT
- `storm_rain_sheet.json`: `velocity_stretch_factor 1.6 → 2.2`, new `veil:wind` module
  (`[0.35, 0, 1] × 0.01 × 0.25` — sideways curtain drift), gradient cooled/deepened
  (`#8A94C8 → #525785`), alpha peak `0.28 → 0.31` / tail `0.22 → 0.24`.
- `storm_godfinger.json` (new): loop, rate 8 / count 1 / `max_particles 8`, cylinder
  1.4 × 9, size 4.5 ± 2.5, life 70 ± 10, slow sink (0.02) with 2.2× stretch, gentle
  `veil:wind`, additive pale sick-green gradient (`#D9FFE8 → #9BD8B4 → #6FA98C`) capped
  at 0.10 alpha — a soft volumetric shaft, deliberately dimmer than `limbo_godray`.

### POLISH 2
- Verified the wind module schema against `limbo_godray.json` (same field names) and that
  8 live godfinger particles × 2 fingers sit far under the live-particle cap alongside
  3 rain sheets.

### POLISH 3
- Both JSONs re-validated. Godfinger alpha kept ≤ 0.10 so the fingers never out-glow the
  loot-camp beacon (the only warm/bright interior light by design).

---

## Round summary (all components)

| Component | Self-check | Steady-state cost added | Burst cost added |
|---|---|---|---|
| `StormWallRenderer` | javac ✅ | color math + ≤ ~150 quads near tier | ≤ ~92 quads, 2 s |
| `StormInteriorFx` | javac ✅ | ≤ 2 loop emitters, 2-3 addParticle/t | 40 t fog-color tail |
| `StormFxClient` | javac ✅ | volume/rise multipliers only | ≤ 4 STORM spawns/s, ~1.6 s |
| `storm_interior.fsh` | glslang ✅ | 2 noise taps + 1 smoothstep/px | — |
| `storm_arc.json` | json ✅ | −17% particles per crackle | — |
| `storm_rain_sheet.json` / `storm_godfinger.json` | json ✅ | +1 wind module / ≤ 16 live motes | — |

reducedFx ladder recap: tier 1 halves rain/mote/ribbon/devil cadences, drops one
god-finger and one devil, flies 12 shards; tier 0 additionally loses veins, god-fingers
and the explosion glitch bursts. Frozen surfaces untouched: wire format, uniforms
(additive `WallProx` only), occluder guarantee, camera-centered tangent-arc windows.

Note for sibling teams: the full-tree javac baseline picked up in-flight errors in
`client/sky/Limbo*` (another team's cluster) mid-round — the storm cluster self-check is
therefore scoped `javac -sourcepath src/main/java stormfx/*.java`, which compiles every
transitive dependency it actually uses.
