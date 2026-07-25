# PLAN-STORM2 — VOLUMETRIC STORM 2.0: "Kugeln aus Wind und Wetter"

Round goal (user priority #1): the storms must read as **spheres of wind and weather** —
a THICK MASS with real depth and height, not a few translucent shells. Nested layers,
stratified wind bands, weather EMBEDDED inside the wall, lit-from-within lightning,
orbiting debris, chunky cloud clumps — built on Veil (world geometry + Quasar + post) and
Photon (HDR ribbons/veins/dust), inside every frozen contract of the current stack.

Team process per package: PLAN → IMPLEMENT → POLISH ×2 → BUDGET AUDIT. 4 parallel
workers, disjoint file ownership (§6). Self-checks: full-tree `javac` against the moddev
classpath (see `javac.*.args` at repo root for the pattern), `glslangValidator` on the
composed fsh, `json.load` on every touched emitter, `python tools/photon/build_storm_fx.py`
round-trip for `.fx` blobs. **No gradle, no git** during authoring; integration compiles
everything together at the end.

---

## 1. Frozen ground rules (may not move — verified against current source)

- **Wire format FROZEN**: `S2CStormStatePayload {stormId, center, radius, height,
  stormType, state, ticks}`; `TYPE_WALL/VORTEX/SPHERE = 0/1/2`,
  `STATE_SPAWN/ACTIVE/DISSIPATE/EXPLODE = 0/1/2/3`. Nothing new on the wire; every
  upgrade is client-derived.
- **Never-see-inside occluder guarantee untouched** (R14/R15): the opaque dome/cylinder at
  `r − OCCLUDER_INSET (5.0)` stays exactly as-is, depth-writing, drawn first. New geometry
  obeys two clamps: EXO shells (outside the occluder) never displace below
  `occluderR + 0.3`; ENDO shells (interior-side) never displace above `occluderR − 0.3`.
- **Camera-centered tangent-arc windows** (EVAL-POL-F #1): geometry windows stay pinned to
  the camera bearing; ALL rotation (bands, strata, churn) lives in noise-pattern indices.
- **FxBudget caps**: STORM channel 12/window full, 6 reduced; ≤ 1500 live Quasar
  particles; ≤ 16 FX lights. Photon bypasses FxBudget but holds
  `PhotonBridge.MAX_LIVE_EXECUTORS = 24` — this round's Photon suite budgets **≤ 7
  executors, nearest sphere storm only** (audit in §5).
- **Post uniforms**: `Interior, RainAmount, Time, Sphere, WallProx` frozen; additive-only
  growth allowed (this round adds `EyeDim, BandFlow, InnerFlash` — §W-D).
- **Photon laws** (`photon/INTEGRATION.md`): LAYER mode only, photon-less baseline renders
  exactly this round's Veil frame (never a degraded old frame); loops WINDOWED-only with
  caller-owned hysteresis; per-storm loops owned by storm code, not
  `PhotonFxRegistry.ensureLoop` (crown-halo precedent).
- **Gameplay contracts kept**: `StormRegistry` API (`spawnSphere/dissipate/explode/
  handleFogSite/siteStormId`), reveal choreography (`REVEAL_TOTAL_TICKS` SPAWN semantics),
  Tyrant-alive proxy (ACTIVE sphere = living Tyrant; `explode()` = death beat — called from
  `FogTyrantEntity` line ~1424), interior seams (`interiorAmount/approachAmount/
  gustAmount/flash/flashAmount/flashSerial/explodeWhiteout`), Tyrant wall silhouette,
  loot-camp glow, MusicManager `fog_storm` hysteresis (rides `interiorAmount`, untouched).
- **Renderer law**: per-vertex procedural `POSITION_COLOR` + `BufferUploader.drawWithShader`
  at `AFTER_PARTICLES`, zero textures, zero per-frame heap allocations, no Iris gate for
  world geometry. Daylight rules (`DAY_ADDITIVE_BOOST/DAY_BASE_CARVE/DAY_GRAY_SPREAD`)
  apply to every NEW alpha too.

---

## 2. Architecture — how the mass illusion is built

The current sphere storm is 3 concentric dome shells (+2/0/−2) + an opaque occluder at
r−5. STORM 2.0 turns the 8-block band around the occluder into a **volume**:

```
 outside ──────────────────────────────────────────────────── inside
   r+3   r+2   r+1    r    r−1.2  r−2.4  r−3.6  r−4.4 │ r−5 │ r−5.6  r−6.4  r−7.4
    A     S     A     S      S      A      S      A    │ OCC │   S      A      S
   glow sheet  glow  BODY  sheet  glow   sheet  rim    │dome │  ENDO interior wall
   └────────────── EXO stack (8 shells) ──────────────┘      └── ENDO stack (3) ──┘
              weather lives BETWEEN these radii:
              rain curtains r+1.5 / r−0.8 / r−3.0 · debris orbits r−2/r+1/r+4
              intra-wall bolts r+2→r−4 · cloud clumps r+2.5±1
```

1. **EXO shell stack** — 8 nested dome shells (near tier, full quality) packed between
   r+3 and r−4.4, alternating additive glow / alpha sheet. Each shell carries
   **3D-noise radial displacement** (smoothed value noise over lat/lon/slow-time, amplitude
   1.6 blocks outermost → 0.4 innermost) so silhouettes wobble independently — parallax
   between 8 independently-billowing surfaces IS the volume read. Depth cues: inner shells
   are **darker** (gray ×0.80/×0.65), **slower** (longer churn clocks) and **less
   saturated**; outer shells are thin and fast. The camera moving past makes the stack
   parallax like a real 8-block-thick cloud bank.
2. **ENDO shell stack** — 3 shells INSIDE the occluder (r−5.6/−6.4/−7.4), drawn only from
   the deep-interior branch. The interior wall stops being "fog only": players inside see
   the same layered churning mass from the other side (fog clamps to 24, so it engages
   exactly in the `WallProx` band). The occluder between EXO and ENDO preserves the
   never-see-inside guarantee bit-for-bit.
3. **Vertical wind-band strata** — the dome's latitude rings group into 4 altitude strata
   with distinct pattern-rotation speeds and directions (heavy slow base 0.6×, mid 1.0×,
   fast upper 1.5×, counter-rotating polar 
   −0.8×). Stratum boundaries get a brightened
   **shear line** (color-only). Height stops being uniform: the sphere visibly does
   different things at different altitudes.
4. **Eyewall → eye gradient** — density envelope over latitude: full density up to
   latFrac 0.55, eyewall additive rim ring at 0.80–0.95, then alpha collapses ×0.15 above
   0.95 — the apex opens into a translucent **eye** whose "pit" is the dark occluder dome
   showing through (depth for free, guarantee untouched). A **polar vortex crown** of 6
   counter-rotating spiral arms twists into the eye.
5. **Weather inside the mass** — embedded rain curtains between shells, an intra-wall
   flash scheduler that pulses the INNER shells brighter than the outer (lit-from-within)
   while a short bolt ribbon arcs between shell radii, stateless debris streaks orbiting
   at 3 radii with vertical migration, and soft radial-gradient cloud-clump fans riding
   the strata for chunkiness.
6. **Photon layer on top** — HDR intra-bolt veins, `ara_trail` debris ribbons at 3
   radii/heights, mesh cloud clumps, collision skirt dust — nearest storm only, windowed,
   LAYER-mode (photon-less clients keep the full Veil mass).
7. **Ground interaction** — the dust skirt grows into a **debris torus**: two stacked
   flared bands plus tumbling hash-orbiter debris quads, plus Photon collision dust.
8. **Explosion 2.0** — the whole stack detonates: per-shell staggered release turns the
   single shockwave into 3+ visibly nested expanding shells; weather layers implode
   during the suck-in; the existing implosion→flash→shards→bloom staging and the
   white-out/bloom interior beats are preserved.

Vortex/wall (cylinder) storms inherit a scaled-down version (EXO 6 shells, no eye) —
the intro vortex gets thicker for free, but SPHERE site storms are the hero.

---

## 3. Cross-package contracts (FROZEN before work starts)

Parallel workers compile against these exact signatures. **W-B lands the skeleton file
with these methods (returning 0/no-op) as its FIRST commit** so A/C/D build green.

```java
// stormfx/StormWeatherFx.java (owner: W-B) — package-private statics, render/tick thread
static float  innerFlashAmount(int stormId);  // 0..1 envelope of the live intra-wall flash
static double innerFlashBearing(int stormId); // world bearing (rad) of the flash cell
static float  innerFlashLat(int stormId);     // latFrac 0..1 of the flash cell
static int    innerFlashSerial();             // bumps once per FRESH flash (any storm)
static float  innerFlashMax();                // max amount over all storms (for the grade)
```

- **W-A** reads `innerFlashAmount/Bearing/Lat` for the shell brightness pulse.
- **W-C** polls `innerFlashSerial()` + `innerFlashMax()` to fire the HDR Photon vein.
- **W-D** feeds `innerFlashMax()` into the new `InnerFlash` uniform.
- **No other cross-edits.** A's explosion stagger is self-contained
  (`explodeRadiusScale(max(0, boom − shellIndex * 0.02F))` — no new ClientStorm helper).
- Existing reads everyone may use (already public/package): `StormFxClient.storms()/
  ticks()`, `ClientStorm.visibility/explodeProgress/explodeWhite`, `StormInteriorFx.
  interiorAmount()/gustAmount()/flashAmount()/flashSerial()/flash(int)`,
  `FxBudget.qualityTier()/tryLight()/releaseLight()`, `PhotonBridge.*`.

---

## 4. Work packages (disjoint ownership)

### W-A — SHELLS/BANDS: the volumetric shell stack (`StormWallRenderer.java` ONLY)

**Owns:** `stormfx/StormWallRenderer.java`. Touches nothing else.

**A1 — smoothed 3D value noise.** Add `fvnoise3(float a, float b, float c)`: trilinear
interpolation of `hash3` at the 8 surrounding integer lattice points (smoothstep fade).
Pure math, no state, no alloc. This is the displacement/organics workhorse.

**A2 — EXO stack.** Replace `SPHERE_OFFSETS/SPHERE_ADDITIVE` with per-tier ladders:

```
tier2 near: OFF = {+3.0,+2.0,+1.0, 0.0,−1.2,−2.4,−3.6,−4.4}, ADD = {T,F,T,F,F,T,F,T}
tier1 near: indices {0,1,3,5,7}   (5 shells)     tier0 near: indices {1,3,5} (3 ≈ today)
far (all tiers): indices {0,3,5}  (3 shells)     impostor: unchanged
```

Per-shell character arrays (same index space): `CHURN_TICKS {2,3,4,5,6,8,10,12}` (outer
fast → inner slow), `GRAY_MUL {1.0,1.0,0.95,1.0,0.9,0.85,0.8,0.65}`, `ALPHA_MUL`
(body shell offset-0 keeps 0.88 base; deep sheets 0.55/0.45; additive glows 0.30 → rim
0.22), `BAND_LEAD {1.6,1.2,0.9,0.6,−0.4,−0.7,0.5,0.3}`, `DISP_AMP {1.6,1.4,1.2,1.0,
0.8,0.6,0.5,0.4}`. Displacement per column-ring vertex pair:
`disp = (fvnoise3(latFrac*3, (a0+shellPhase)/step*0.5, time/24) − 0.5) * DISP_AMP[s]`,
clamped so `radius + disp ≥ occluderR + 0.3`. Alpha-floor cull: skip a column when its
computed max alpha < 0.015 (fill-rate guard — the whole stack is overdraw-bound, not
vertex-bound). `SPHERE_RINGS_NEAR 10 → 12` (strata resolution).

**A3 — vertical band strata.** `STRATUM_OF_RING` (4 groups over the 12 rings),
`STRATUM_SPEED {0.6, 1.0, 1.5, −0.8}` multiplying the existing per-ring pattern rotation
(`SPHERE_BAND_RAD_PER_TICK`), still noise-index-only (EVAL-POL-F #1). Shear lines: rings
adjacent to a stratum boundary get `+0.08` additive alpha modulated by
`fvnoise3(lon, stratum, t/6)` — bright churning seams between counter-shearing bands.

**A4 — eyewall → eye + polar crown.** Latitude envelope on every sphere shell:
`eyeEnv(latFrac) = 1.0 (≤0.55) → smoothstep down to 0.35 at 0.95; ×0.15 above 0.95`
for alpha shells; additive shells get an **eyewall rim** `+0.25·churn` in latFrac
[0.80, 0.95] and the same ×0.15 collapse above. The dark occluder reads through the eye
as the pit. Polar crown: `emitPolarCrown` — 6 spiral arms × 8 segments (48 quads,
additive, counter-rotating at `−1.3×` base speed, violet-white tips) twisting from
latFrac 0.85 into the apex. Near tier, quality ≥ 1.

**A5 — ENDO stack.** In the deep-interior early-out branch of `buildShells` (where the
Tyrant silhouette draws), emit `ENDO_OFFSETS {−5.6,−6.4,−7.4}` (tier2; {−5.6,−6.8} tier1;
{−6.0} tier0) dome shells: full 2π windows are wrong here — keep the camera-bearing arc
(the fog clamps reads to ~24 blocks anyway), alpha modest (0.5/0.35/0.25), same churn +
strata + displacement (clamped ≤ occluderR − 0.3), plus the W-B inner-flash pulse (A6).
Also emit them for cylinders (2 shells) so the vortex interior wall thickens too.
Never during EXPLODE.

**A6 — lit-from-within pulse.** All sphere shells read
`StormWeatherFx.innerFlashAmount(storm.id)`: columns within ±0.5 rad of
`innerFlashBearing` and rings within ±0.18 of `innerFlashLat` lerp color toward
violet-white and gain additive alpha `+0.5 · amount · falloff` — with the multiplier
**scaled by shell depth** (`1.0` innermost EXO → `0.35` outermost, ENDO ×1.2): light
born INSIDE the mass, veiled by the outer layers. Color-only, zero quads.

**A7 — debris torus skirt.** Upgrade the equator dust band: second stacked band flaring
UP-and-out (`r+0.3 → r+2.6` over y [2.2, 4.6], reverse taper), both alpha-jittered by
`fvnoise3`; plus 12 (6 reduced) tumbling debris cross-quads (reuse `emitCrossFlash`) on
stateless hash orbits: `bearing(i,t) = hash·2π + t·(0.03+0.02·hash)`, radius r+0.5..r+3,
y 0.5..3.5 with `sin` bob, size 0.5–1.1, dust-gray. Near tier only.

**A8 — explosion stagger.** In `emitSphereShell`, per-shell boom:
`explodeRadiusScale(Math.max(0.0F, boom − s * 0.02F))` — outer shells release first, the
burst reads as 3+ nested shockwave shells. Shards/bloom-ring/white-out untouched. ENDO +
torus + crown drop at EXPLODE (existing occluder-drop pattern).

**A9 — cylinder inheritance.** `SHELL_OFFSETS` grows to 6 (tier2)
`{+3,+2,0,−1.5,−3,−4.4}` with the same character arrays/displacement (no strata/eye).
Vortex cone/collar untouched.

**Budget (near, tier2, ~55 visible columns):** shells 8×12×55 ≈ 5.3k quads (today ≈
1.65k), torus ≈ 130, crown 48. Far tier: 3×6×48 ≈ today. Alpha-floor cull typically
drops 15–25 % of columns. No allocations added to any per-frame path.

---

### W-B — WEATHER-IN-MASS: embedded weather layers (NEW files only)

**Owns:** NEW `stormfx/StormWeatherFx.java` (tick/state/contract §3) + NEW
`stormfx/StormWeatherRenderer.java` (geometry, own `RenderLevelStageEvent` subscription
at `AFTER_PARTICLES`). Touches nothing else. **All B geometry draws in ONE additive pass**
(order-independent → immune to listener-order vs. W-A's alpha pass).

**B0 — contract skeleton FIRST.** Land `StormWeatherFx` with the §3 signatures (0/no-op
bodies) immediately; A/C/D compile against it from day one.

**B1 — intra-wall flash scheduler** (`StormWeatherFx.onClientTick`, per storm): next
flash in 90–260 ticks (hash off storm id + window), duration 7 ticks, smoothstep
envelope; picks bearing = camAngle ± 1.2 rad and latFrac 0.15–0.7; bumps the serial on
fresh flashes only (flashSerial pattern). Effects owned here: ONE budgeted point light at
the wall surface point (`FxBudget.tryLight`, violet `0.7,0.5,1.0`, radius `8+8·amount`,
released with the envelope — Bolt.claimImpactLight pattern), and
`StormInteriorFx.flash(4)` when `interiorAmount() > 0.5` (existing interior-reveal rule,
same package). Gates: sphere storms, ACTIVE only, vis > 0.6, near-LOD (shellDist < 160),
quality ≥ 1; never during EXPLODE. Pause-safe decrement, `Clone`/`LoggingOut` reset.

**B2 — embedded bolt ribbons.** During a flash, `StormWeatherRenderer` draws 1–2 jittered
ribbons INSIDE the mass: from `(bearing±0.1, latFrac+0.25, radius r+2)` down to
`(bearing∓0.15, latFrac−0.1, radius r−4)` — radially inward paths between shell radii,
so W-A's outer shells veil them (the "inside the wall" read). File-local copy of the
6-segment ribbon math (scratch float[] like `BOLT_PTS` — ownership stays disjoint), core
+ glow, ≤ 14 quads per flash, white-violet.

**B3 — rain curtains between shells.** Near tier, quality ≥ 1, sphere + cylinder: 3
curtain radii `{r+1.5, r−0.8, r−3.0}`, each a camera-bearing arc of 14 columns × 3
stacked sub-quads (vertical span 65 % of height). Per column: hash gate (~40 % on,
re-rolled per fall cycle) and a falling bright band — sub-quad alphas keyed off
`fract(y·0.13 − t·(0.09+0.04·hash))` so a luminous streak slides DOWN each column
(pure vertex color, the storm_interior.fsh rainLayer trick in world space). Faint
slate-blue additive `(0.35,0.40,0.60)`, alpha ≤ 0.22·churn, daylight-boosted. Curtain
rotation rides stratum speeds (bearing offset per curtain radius). 126 quads max.

**B4 — debris streak orbiters.** Stateless: streak `i ∈ [0,24)` (tier2; 12 tier1; 0
tier0) fully derived from `(i, time)`: radius band from `hash(i) → {r−2, r+1, r+4}`,
angular speed `±(0.02..0.05) rad/t`, **vertical migration**
`y = (baseY + t·climb(i)) mod (0.9·height) + 1.5·sin(t·0.07+i)` — streaks corkscrew up
through the mass and wrap. Render: velocity-stretched 2-quad cross oriented along the
tangent (length 1.2–2.6, width 0.12–0.3), slate-gray with a brighter head. During
EXPLODE implosion (`explodeProgress < 0.18`) radii lerp toward 0 — the suck-in grabs the
debris field. Near tier only.

**B5 — cloud-clump fans.** The chunk read: soft radial-gradient billboards WITHOUT
textures — each clump is a 4-quad camera-facing octagon fan sharing a bright center
vertex (center alpha 0.30·churn → rim alpha 0): vertex interpolation gives the soft
falloff. 16 clumps tier2 / 8 tier1 / 0 tier0, hash-anchored on `(bearing_i + stratum
rotation at its ring, latFrac_i ∈ [0.1,0.8])` at radius `r+2.5 ± fvnoise-jitter`,
sizes 6–14 blocks, slate body tinted by the band hue (fog-green ↔ violet), slow size
breathing (`1 ± 0.08·sin`). Spheres only, near tier. 64 quads.

**B6 — gust coupling.** Curtain fall speed ×(1+0.6·gust), clump alpha ×(1+0.3·gust),
streak angular speed ×(1+0.4·gust) — everything breathes with the roar-loop bar
(`StormInteriorFx.gustAmount()`).

**Budget:** ≤ ~270 additive quads steady + ≤ 30 during a flash; ZERO Quasar spawns (no
STORM-channel pressure); 1 budgeted light per flash with refusal fallback (color pulse
still reads). No per-frame allocations (scratch arrays are static finals).

---

### W-C — PHOTON suite (NEW `stormfx/StormPhotonFx.java` + assets + generator)

**Owns:** NEW `stormfx/StormPhotonFx.java`, NEW `tools/photon/build_storm_fx.py`, the new
`assets/eclipse/fx/storm_*.fx` blobs, `tools/photon/README.md` row. Does NOT touch
`StormFxClient` (the crown halo stays where it is) or `PhotonBridge`.

**C1 — per-storm window manager.** Client-tick sweeper keyed by storm id (small parallel
arrays, no iterators): loops attach to **the nearest ACTIVE/SPAWN sphere storm only**
(hard executor budget: crown 1 [existing] + ribbons 3 + skirt dust 1 + clumps 1 = **6 of
24**, +1 transient intra-bolt = 7) inside `shellDist < 160`, release beyond 180
(hysteresis, crown-halo pattern), release on DISSIPATE/EXPLODE/removal/`available()`
false; refused spawns back off 40 ticks. `LoggingOut`/`Clone` → release all. WINDOWED-loop
law satisfied by construction.

**C2 — `storm_debris_ribbon_{low,mid,high}.fx`** — the ara_trail debris belts:
`ara_trail_emitter` ribbons (fxlib `AraTrailEmitter`, crown-halo orbital authoring:
cylinder shape + `shapeArc Loop` so spawn points march around the ring) at three
radii/heights — LOW skirt `0.95r / y 3`, MID band `0.75r / 0.45h`, HIGH crown approach
`0.55r / 0.8h`; 3–5 live ribbons each, widthOverTrail taper 0.5→0, HDR additive
slate-violet (low) → fog-green (mid) → violet-white (high), opposite orbital directions
per belt. Mandatory: `maxParticles ≤ 24`, renderer cull box ≈ 2.2r, `vertexSortingMode
NONE`. Anchored at storm center + height offset via `PhotonBridge.spawnLoop(id, anchor)`;
executor `setScale(r/24)` normalizes to authored radius 24.

**C3 — `storm_intra_bolt.fx`** — HDR lightning veins between layers: one-shot burst (a
beam/trail vein bundle, HDR white-violet, life ~8 t) fired when C's tick sees
`StormWeatherFx.innerFlashSerial()` advance: spawn at the wall point
`center + (cos/sin(innerFlashBearing) · 0.92r, innerFlashLat·h)` with `allowMulti=true`.
Photon-less baseline = W-B's ribbon + W-A's pulse (LAYER law satisfied). Skipped when the
flash storm isn't the managed nearest storm.

**C4 — `storm_skirt_dust.fx`** — collision dust at the skirt: looping base-ring emitter
(`shapeArc Loop`, radius ≈ r at y+2) dropping sparse heavy motes with a `FirstCollision`
sub-emitter (`supply_landing_dust` pattern) stamping flat dust puffs where they hit real
terrain — the storm physically kicks the ground.

**C5 — `storm_cloud_clump.fx`** — mesh cloud clumps: 5–7 huge soft LDR billboards
(or `mesh`-shape emission off a lumpy block model for cauliflower placement, FX_FORMAT §
mesh) drifting slowly around `0.8r` at eyewall height, additive-soft, long lifetimes,
size 8–16 — Photon's painterly layer over B5's geometric fans.

**C6 — generator + docs.** `tools/photon/build_storm_fx.py` (fxlib) builds all five
blobs, mirrors `build_world_fx.py` structure (builders dict + validation round-trip);
README table row per asset; `asset_audit.md` entries.

**Degradation audit:** no new Quasar fallback emitters (LAYER law — photon-less clients
render exactly the W-A/W-B frame); `reducedFx` kills the bridge → C1 windows release
outright; missing `.fx` → session-skip per id (bridge handles).

---

### W-D — INTERIOR + EXPLOSION upgrade (`StormInteriorFx.java`, `StormFxClient.java`, shader)

**Owns:** `stormfx/StormInteriorFx.java`, `stormfx/StormFxClient.java`,
`assets/eclipse/pinwheel/shaders/program/storm_interior.fsh` (+ its program `.json` only
if declarations demand). Additive uniform growth only.

**D1 — new uniforms** (frozen names, fed from `StormInteriorFx`'s registered pipeline
row): `EyeDim` — 0..1 "under the eye" factor (horizontal centerDist < 0.35r while
interior-sphere, smoothed 0.16 ease + teleport snap like every scalar); `BandFlow` —
signed stratum flow at camera height (−1..1, from the W-A stratum speed table applied to
`(camY − centerY)/height`); `InnerFlash` — `StormWeatherFx.innerFlashMax()`. All zero
under reducedFx where motion-bearing (BandFlow, InnerFlash follow the WallProx rule).

**D2 — fsh upgrades** (composed-fsh `glslangValidator` green, Iris-gated as today):
- **BandFlow shear**: the rain-streak layers gain a horizontal drift term
  `uv.x += Time · 0.05 · BandFlow · heightGrad` and the two layers shear AGAINST each
  other — inside the mass the weather visibly streams sideways at band speed.
- **EyeDim god-light**: vertical top-glow lift (`+0.10 · EyeDim` toward the sphere flash
  palette, strongest at the frame top) + mild vignette release — standing under the eye
  reads as the calm luminous core.
- **InnerFlash**: violet-white additive lift `+0.18 · InnerFlash` biased toward frame
  edges (the wall is where the light lives), stacking safely with the existing flash lift.
- **Wall-side mist bias**: the depth-fog mist term gains `+0.15·WallProx` weight so the
  view INTO the wall drowns before the open interior does.
- Sphere/vortex palettes, sky sink, shimmer, crush: untouched.

**D3 — interior weather coupling** (`StormInteriorFx`): rain-sheet spawn bearing biased
toward the nearest wall when `WallProx > 0.4` (the B3 curtain read continues seamlessly
across the wall); mote drift gains a tangential component at stratum speed (band flow
inside the mass); god-finger gate ANDs with `EyeDim > 0.3` (fingers = the eye's light,
not random shafts). Cadences/gates/reducedFx rules unchanged.

**D4 — explosion 2.0 debris** (`StormFxClient.tickExplosionDebris` — the renderer's
staggered shells are W-A's): implosion stage additionally pulls 2 spark-white streaks/t
toward center; expansion stage doubles ring bursts at tier 2 only (still `addParticle`,
budget-free) and adds a **vertical debris fountain** — 3 CAMPFIRE_SIGNAL/LARGE_SMOKE per
tick climbing from center to 0.6h during expand 0.3–0.8, so the burst has height, not
just radius. Glitch-strobe bursts (STORM-charged, ≤ 4/s transient) unchanged.

**D5 — pre-release "gulp"** (`StormInteriorFx.explodeWhiteout` path): 6 ticks before the
white-out peaks (i.e. during the implosion charge), fog-far pinches 24→14 and back — the
storm inhales before it dies. Bloom tail + sky-opens beat untouched.

**D6 — audio garnish** (existing sounds only): `SphereDroneSound` pitch −0.06·EyeDim
(deeper under the eye); `StormLoopSound` unchanged (gust swell already landed).

**Hygiene:** every new scalar resets in `reset()` (M5), snaps on teleport, and is
audited against `Clone`/`LoggingOut`.

---

## 5. Performance ladder (acceptance numbers)

Per storm, camera outside, visible-arc ≈ 55/48 columns. "q" = quads.

| Tier / LOD        | EXO | ENDO | rings | clumps | streaks | curtains | intra flash    | Photon        | ≈ steady q |
|--------------------|-----|------|-------|--------|---------|----------|----------------|---------------|------------|
| near · tier 2      | 8   | 3    | 12    | 16     | 24      | 3 radii  | light + ribbon | 6 executors   | ~5.8 k     |
| near · tier 1      | 5   | 2    | 10    | 8      | 12      | off      | color-only     | off (bridge)  | ~3.1 k     |
| near · tier 0      | 3   | 1    | 8     | 0      | 0       | off      | off            | off           | ~1.4 k     |
| far (160–320)      | 3   | 0    | 6     | 0      | 0       | off      | off            | crown only    | ~0.9 k     |
| impostor (>320)    | —   | —    | —     | —      | —       | —        | —              | —             | unchanged  |

- LOD crossfades keep the ±16-block `LOD_FADE`; ENDO ladder keys off `qualityTier()`.
- Fill-rate is the real cost (8 translucent layers): the W-A alpha-floor column cull is
  mandatory, and EXO shells 5–8 (the deep ones) also require `shellDist < 240`.
- Quasar: unchanged (no new emitters — B is pure geometry). STORM channel worst case
  stays ≈ 7/12 per window (arcs + rain + god-fingers + explosion transient).
- Lights: +1 per intra-flash (budgeted, ≤ 1 concurrent per storm, refusal-safe).
- Photon: ≤ 7 executors, nearest storm only; every loop carries maxParticles + cull box.
- Explosion transient: + ~0.4 k q for 2 s (staggered shells reuse existing columns).

## 6. Ownership matrix & integration

| Worker | Files (exclusive)                                                                 |
|--------|-----------------------------------------------------------------------------------|
| W-A    | `StormWallRenderer.java`                                                          |
| W-B    | NEW `StormWeatherFx.java`, NEW `StormWeatherRenderer.java`                        |
| W-C    | NEW `StormPhotonFx.java`, NEW `tools/photon/build_storm_fx.py`, NEW `fx/storm_*.fx`, photon README/audit rows |
| W-D    | `StormInteriorFx.java`, `StormFxClient.java`, `storm_interior.fsh` (+ program json) |

Order: **B0 (contract skeleton) lands first**, then all four proceed in parallel.
Integration pass: full-tree `javac`, `glslangValidator`, emitter `json.load`,
`build_storm_fx.py` run, then visual QA via the `/eclipsefx storm` dev commands (spawn
sphere near/far/inside, day + night, all three tiers, Tyrant `explode()` beat, reveal
choreography, dimension-swap/teleport hygiene).

## 7. Risks & mitigations

- **Fill-rate on 8-shell overdraw** → alpha-floor cull + distance gate on deep shells +
  tier ladder; if frame cost still spikes, drop tier-2 EXO to 7 before touching rings.
- **Sodium depth-sort artifacts** (§7 risk 2, unchanged) → everything stays
  `POSITION_COLOR` at `AFTER_PARTICLES`; W-B is additive-only so listener order vs W-A
  cannot produce alpha-sort seams; fallback stage swap remains documented in W-A's header.
- **Two render subscribers** → B draws only additive geometry; any future alpha-blended
  weather must move into W-A's file (noted in both class javadocs).
- **Photon executor pressure** → nearest-storm-only gating + the 24-cap refusal path is
  already load-bearing; C never retries faster than 40 t.
- **Occluder guarantee** → displacement clamps (§1) + no geometry change to the occluder;
  eye transparency exposes only the occluder itself.
- **EVAL-POL-F #1 regression** → every new rotation (strata, curtains, clumps) is
  pattern-index-only; geometry windows stay camera-centered; POLISH pass re-verifies by
  orbiting the camera at fixed distance.
