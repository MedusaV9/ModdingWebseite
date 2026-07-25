# IDEAS-STORM-2 — Technical Rendering Ideas for Volumetric Sphere Storms

**Collector:** IDEAS-STORM-2 (technical track; a reference-driven collector runs in parallel).
**Scope:** the C8 `TYPE_SPHERE` site-storm domes drawn by `stormfx/StormWallRenderer` — how to
make them read as THICK volumetric masses on the existing budget rules, without breaking the
never-see-inside occluder guarantee or the Iris fallback tier.

**Sources studied (verbatim from repo):**

- `src/main/java/dev/projecteclipse/eclipse/stormfx/StormWallRenderer.java` — current approach:
  3 sphere shells at r+2 / r / r−2 (additive / alpha / additive), 10 rings near tier ×
  ≤96 segments (48 far, 6 rings), camera-tangent-arc column culling, per-column CPU hash churn
  (`hash3`), banded rotation via pattern-index leads, a *bearing-only* rim heuristic
  (`edge`/`rim` in `emitSphereShell`), UV-crawl lightning veins (pure color modulation),
  opaque occluder dome at r−5, LOD 160/320 with ±16 crossfade, day-carve constants.
  Draw path: vanilla `Tesselator` → `BufferUploader.drawWithShader` with
  `POSITION_COLOR` + `GameRenderer::getPositionColorShader`; 3 passes (occluder depth-write,
  alpha, additive with separate blendFuncs). Zero textures, zero per-frame heap.
- `storm_interior.fsh` + `StormInteriorFx` — GRADE-priority post pass, uniforms
  `Interior, RainAmount, Time, Sphere, WallProx` fed via `VeilPostController` row;
  `WallProx` already encodes interior-side wall proximity (heat shimmer). Post is hard-gated
  off under Iris; world geometry is the fallback tier.
- Veil abstractions in use today: post pipelines + per-frame uniforms
  (`VeilPostController`, ≤3 concurrent fullscreen passes, GRADE evicted first), deferred
  point lights (`LightRenderHandle<PointLightData>`, ≤16 via `FxBudget.tryLight`), Quasar
  emitters (`QuasarSpawner`, STORM channel = 12 spawns/s window, ≤1500 live particles).
  NOT in use: Veil custom world shaders/geometry buffers — the wall is vanilla-pipeline.
- `docs/plans_v3/plans_v5/photon/FX_FORMAT.md` (+ `PhotonBridge`) — mesh particles, ara
  ribbons, raycast beams, custom shader materials with curve/gradient LUTs, per-material HDR
  bloom, GL blend equations (ADD/SUB/REVERSE_SUB/MIN/MAX), `useGPUInstance` +
  `parallelUpdate/parallelRendering` (10⁴–10⁵ budgets), per-emitter cull boxes, executor
  `setScale`. Bridge budget: ≤24 live executors, reflection-gated, silent no-op without the
  mod, disabled entirely under `reducedFx`. Per-storm windowed-loop precedent:
  `STORM_CROWN_HALO` (`tickCrownHalo`, hysteresis 160/180 blocks, 40t retry).
- Python tooling precedents: `tools/photon/fxlib.py` (author `.fx` from Python, validated
  round-trip), `tools/art/*.py` (procedural PNG generation, e.g. `gen_wisp_white.py`) —
  we can generate tileable flow/noise textures offline.

**Budget frame for every idea below:** near tier today ≈ 3 shells × 10 rings × ~50 visible
columns ≈ 1.5k quads + occluder ~0.4k. Headroom target: ≤2.5× current quad count at near
tier, zero new fullscreen passes (reuse the existing `storm_interior` row), ≤1 photon loop +
occasional one-shots per storm, no new Quasar emitter types beyond budget.

---

## Ranked ideas (1 = do first)

### 1. True N·V limb law — per-vertex view·normal opacity (shells get THICK at the rim for free)

**What.** Replace the bearing-only `rim`/`edge` heuristic in `emitSphereShell` with the real
optical-thickness law. For a thin spherical shell of thickness `t`, the chord a view ray cuts
through it is `t / |dot(V, N)|` — path length (and thus opacity) diverges at the limb. That is
exactly the "spheres look thick at the rim automatically" effect: encode
`alpha *= clamp(t / max(|N·V|, 0.12), 1, limbMax)` on the alpha shell (limb *thickening*) and
`glow *= pow(1 − |N·V|, 2)` on the additive shells (limb *brightening* — forward-scatter rim).
Optionally invert on the body: `1 − 0.3·|N·V|` face darkening = limb-darkened "dense core" read.

**How, concretely.** Everything is camera-relative already: at each emitted vertex,
`N = (pos − centerRel) / r` and `V = normalize(pos)` (camera at origin), so
`|N·V| = |dot(pos − c, pos)| / (r·|pos|)` — ~8 flops per vertex inside the existing loops, per
vertex not per column, so it also fixes the top-down failure of the current heuristic (the
`edge` fraction only measures longitude; looking down at the apex the rim light sits wrong —
N·V is correct from every camera angle, including inside). Blend it with the existing
`latFrac` density ramp; keep the current `rim` as the far-tier cheap path if desired.

**Cost.** ~0 (arithmetic inside loops that already run; no new quads/draws/textures).
**Feasibility.** Trivial — pure CPU math in `emitSphereShell`/`buildSphereOccluder` callers.
**Risk.** None structural. Tune `limbMax` ≤ ~2.2 so the silhouette doesn't clip to solid and
fight the day-carve striping.

### 2. Textured shells: `POSITION_TEX_COLOR` + one tileable cloud-density texture (biggest read-per-cost jump)

**What.** The single largest visual upgrade available without any custom pipeline: switch the
sphere shell passes from `POSITION_COLOR` to `DefaultVertexFormat.POSITION_TEX_COLOR` +
`GameRenderer::getPositionTexColorShader` + `RenderSystem.setShaderTexture(0, …)`, sampling a
Python-baked tileable fBm cloud-density texture. UV = `(longitude·repeat + flowOffset(shell,
band, time), latFrac)`. Per-vertex churn color stays; the texture supplies the *intra-quad*
detail the current flat quads cannot — silhouettes stop being 96-gon facets and start being
cloud.

**How, concretely.** Wraps cleanly: `emitColumn`/sphere emission gain a `u0,u1,v0,v1`
overload; each shell gets its own `repeat` (outer coarse 4×, body 6×, inner fine 10×) and its
own continuous flow offset (reuse `SPHERE_CHURN_TICKS`/`SPHERE_BAND_LEAD` as *continuous*
scroll speeds instead of stepped noise clocks — per-shell UV flow speeds are one multiply).
The vanilla position-tex-color shader keeps the Iris fallback property (world geometry, no
custom program). Alpha from texture × vertex alpha preserves every existing ramp (day carve,
latFrac, explode white). Occluder stays untextured `POSITION_COLOR` — the guarantee is
untouched.

**Cost.** +1 texture fetch/fragment on wall pixels; same quad count; one 512² RGBA texture in
VRAM. One extra `setShader`/texture bind per pass.
**Feasibility.** High — all vanilla API, ~1 day of plumbing; texture generation is idea #3.
**Risk.** Mipmap shimmer at grazing angles (generate mips, bias toward blur); seam at the
longitude wrap (bake the texture tileable — trivial in Python).

### 3. The Python texture set to bake (`tools/art/gen_storm_textures.py`)

**What.** The concrete offline-generation recommendation (verdict on shader-noise vs textures
is in the rationale below). Generate once, commit as assets:

| file | size | contents | consumer |
|---|---|---|---|
| `storm_cloud_tile.png` | 512², RGBA, mips | tileable 4-octave fBm density; R = density, G = density at 2× freq (detail re-mix), B = large-scale cell mask, A = alpha copy of R | idea #2 shells |
| `storm_curl_flow.png` | 256², RG | tileable curl-noise flowmap (divergence-free 2D vectors, RG = 0.5 + 0.5·v) baked from a scalar potential | CPU band-scroll offsets now (sample once per column per frame at column center); per-fragment advection later if idea #15 lands |
| `storm_puff_atlas.png` | 1024², 4×4 cells | 16 soft cloud puffs, alpha-only shape + baked top-light/bottom-shadow gradient in RGB, 2 hue temperature variants (green cast / violet cast) in alternating cells | idea #7 billboard clumps, idea #8 photon clumps (photon `sprite`/`texture` material + `uvAnimation tiles [4,4]`) |
| `storm_grad_lut.png` | 256×4 | row 0: latitude density ramp; row 1: rim-glow ramp (indexed by 1−|N·V|); row 2: day-carve curve; row 3: explosion white ramp | replaces hand-tuned constants; also directly importable as photon `gradientTexture` LUT rows for custom-shader materials |
| `storm_dome_flipbook.png` | 1024², 2×4 cells | 8 pre-rendered churn frames of a whole limb-darkened dome (render offline with the same fBm + N·V law) | idea #12 far impostor |

**Why textures over in-shader 3D value noise (the verdict).** The wall can fill the entire
screen at near range; 3–4 octaves of 3D value noise per fragment is 50–100 ALU × ~2M fragments
× 3 shells of overdraw — and today the wall runs on *vanilla* shaders, so shader noise
requires the custom-pipeline step (idea #15) *first*, with its Iris-fallback duplication cost.
Precomputed textures cost 1 fetch, are art-directable offline (iterate in Python, view the
PNG), tile perfectly, mip cleanly, and work with the vanilla shader today. In-shader noise
only wins for *animated parallax* noise (domain-warped 3D), which idea #15 scopes as the
optional endgame. `eclipse_common.glsl`'s `efxNoise` stays the tool for *post* passes only.

**Cost.** Offline; ~1.3 MB of PNGs. **Feasibility.** High — `tools/art` precedent exists;
numpy fBm/curl is ~150 lines. **Risk.** None at runtime.

### 4. Interleaved noise-displaced shells with per-shell flow (parallax between shells)

**What.** Make the three concentric shells *interpenetrate*: displace every ring vertex
radially by a smooth low-frequency noise `Δr(shell, bearing, lat, t)` with amplitude
1.0–1.6 blocks and per-shell flow speeds/directions (outer slow prograde, body counter, inner
fast prograde — extend `SPHERE_BAND_LEAD`). Because the shells sit only 2 blocks apart,
displaced bulges of the inner additive shell locally push *through* the alpha body — as the
camera orbits, the crossings shift = true motion parallax, the strongest monocular depth cue
the current fixed-offset stack lacks.

**How, concretely.** In `emitSphereShell`, `radius → radius + amp·noise` where the noise is
`Mth.lerp` between two `hash3` anchors on a coarse (every-4-columns × per-ring) lattice with a
*continuous* time phase (not the stepped `noiseT`) so displacement never pops. Clamp so the
alpha body never crosses the occluder (`r − Δmax > occluderR + 0.5`) and so shell order can
only swap between additive/alpha pairs (additive is order-independent, so blending stays
correct; never displace two *alpha* shells past each other — there is only one alpha shell, so
this is free).

**Cost.** ~2 extra hash + lerp per vertex; zero new quads.
**Feasibility.** High — same loops, pure CPU.
**Risk.** Silhouette wobble against the opaque occluder rim: keep displacement amplitude
`< OCCLUDER_INSET − 2` and fade `Δr → 0` at the skirt latitudes so the terrain seam stays sealed.

### 5. Fog-grade wall-band coupling: `WallBand` uniform in `storm_interior` (the crossing IS the thickness)

**What.** The moment of crossing the wall is where "volume" is cheapest to sell: a post-grade
term that darkens/thickens the frame as a function of camera distance to the wall band,
peaking mid-band. Inside → out and outside → in both read as pushing through meters of mass.

**How, concretely.** `StormInteriorFx.interiorTargetAt` already computes signed wall distance
(`inset`, `wallProxTarget`); add a symmetric band scalar
`WallBand = 1 − clamp(|centerDist − (r − OCCLUDER_INSET/2)| / halfBand, 0, 1)` (halfBand ≈ 6),
smoothed like `smoothedWallProx`, fed in the *existing* registered `storm_interior` row (no
new pipeline — the ≤3-pass budget is untouched). In `storm_interior.fsh`: extra
`efxCrush(color, WallBand·0.5)`, mist push toward the sphere palette with depth window pulled
to ~4–18 blocks, +30% shimmer amplitude, and a vignette clamp — all ≤10 lines. Note the grade
currently activates on `stormInterior() > 0.01`, which is 0 outside: widen the predicate to
`interior > 0.01 || wallBand > 0.01` so the outside half of the crossing is graded too.

**Cost.** ~0 GPU (lines in an already-running fragment pass), 1 uniform.
**Feasibility.** Trivial — exact `WallProx` precedent.
**Risk.** Iris: post is gated off, so mirror a weaker fallback by boosting shell alpha for
cameras inside the band (2 lines in `emitSphereShell`). Keep total crush ≤ the frozen
`Interior` look so the interior grade still owns the deep-inside read.

### 6. CPU strike-glow injection into shells (lightning lights the mass from within)

**What.** When a bolt/arc fires, the wall around the strike point should *bloom from inside
the mass* — brightness injected into the shells near the strike with radial falloff, 3–4 tick
decay. Sells the shells as a participating medium, not wallpaper.

**How, concretely.** No uniforms needed — shell colors are per-vertex CPU already. Per frame,
for each storm collect live strikes (≤ `MAX_BOLTS` 8 + arcs 6, from `StormFxClient.bolts()/
arcs()`, age < 6t) that lie within the wall band; inside `emitSphereShell`, per *column* (not
per vertex): `glow = Σ intensity·decay(age)·exp(−dBearing²/σθ²)·exp(−dLat²/σφ²)` with early-out
by bearing delta (>2σ skip — typically ≥90 % of columns skip in one compare). Add `glow` to
the additive shell color toward white-violet and lerp the vein head brighter when a strike is
near its longitude (couples with the existing vein system). Also flash the *inner* additive
shell (index 2) hardest — light from within.

**Cost.** Worst case ~50 visible columns × 10 rings × ≤4 nearby strikes ≈ 2k exp() per frame
*only while strikes are live*; typical ≈ 0. No new geometry.
**Feasibility.** Trivial-high — data is all client-local, loops exist.
**Risk.** Palette blow-out when several arcs cluster: clamp per-column glow, and respect
`DAY_ADDITIVE_BOOST` so the day/night tuning holds.

### 7. Billboard cloud clumps BETWEEN shells, distance-band sorted (the "real cloud" filler)

**What.** 120–200 camera-facing textured puffs (atlas from idea #3) seeded in the radial gap
r−3.5 … r+2.5, near tier only — the interstitial cloudlets that break the "concentric
onion" tell when the camera is close enough to see between shells.

**How, concretely.** Deterministic seeding (hash of storm id × slot) on the sphere: bearing,
latitude, radial offset, size 2–6 blocks, per-slot orbit speed matching its band lead — no
per-frame allocation, positions are pure functions of `time` like everything else in this
renderer. Emit as camera-facing quads (the `emitCrossFlash`/`emitRibbon` math) with atlas UVs.
**Cheap sorting vs shells — distance bands:** don't sort per-quad. Bucket slots into 6–8
*radial* bands (band = quantized `|slotDist − camDist|`); emit alpha-blended puffs far-band →
near-band into the alpha pass buffer *between* shell emissions ordered the same way (outer
shell → outer bands → body shell → inner bands), i.e. the shells themselves act as the band
separators — the painter's order is correct by construction against the geometry that
matters. Within a band, disorder is hidden by low alpha (≤0.35) and soft atlas edges;
additive glow puffs need no sorting at all. Bands re-bucket only when the camera crosses a
band boundary (int compare per slot per frame).

**Cost.** +200 quads near tier (~13 % over current), 1 texture (shared with idea #2), ~free
CPU. Cull with the same tangent-arc window (skip slots outside `camAngle ± halfArc`).
**Feasibility.** High — all existing patterns.
**Risk.** Puffs intersecting the occluder read as flat cutouts: keep inner radial limit ≥
occluderR + 1.5. Sodium translucency order at `AFTER_PARTICLES` — same §7 risk 2 escape hatch
(switch stage constant) already documented in the class header.

### 8. GPU-instanced photon clump belt: 800–1200 orbiting mesh/billboard particles

**What.** The premium version of #7 for photon-equipped clients: one looping `.fx` per sphere
storm — a belt system of 800–1200 GPU-instanced puff particles orbiting in 3 latitude bands
(counter-rotating, band leads matching the shells), living just outside the outer shell so
they never fight the alpha ordering.

**How, concretely (feasibility per FX_FORMAT).** Author with `tools/photon/fxlib.py`:
an `empty` parent + 3 `particle_emitter` children (one per band). Each: `looping:1b`,
`prewarm` ≈ lifetime (no cold start), `maxParticles` 400, `simulationSpace: Local` (orbits
track the anchor), shape `cylinder{radius:1.02, radiusThickness:0.06, arc:360,
shapeArc{arcMode: Random}}` at band height, `velocityOverLifetime{orbitalMode:
AngularVelocity, orbital:[0, ±ω, 0]}` + `noise{quality: Noise2D, position:~0.15}` turbulence,
`renderMode: Billboard`, material `sprite/texture` = `storm_puff_atlas` with
`uvAnimation{tiles:[4,4], startFrame: random_constant}`, blend = alpha
(`SRC_ALPHA/ONE_MINUS_SRC_ALPHA`) with `vertexSortingMode: NONE` *because* the belt sits
outside every alpha shell (nearest-wins errors are hidden by design) — DISTANCE sort on 1200
particles is the thing to avoid. **Key flags:** `useGPUInstance:1b, parallelUpdate:1b,
parallelRendering:1b` (FX_FORMAT §7: 10⁴–10⁵ budgets — 1200 is comfortable),
`renderer.cull.cullBox` = unit AABB (auto-scaled), `shade:0b`.
Runtime wiring = the `STORM_CROWN_HALO` pattern verbatim: per-`ClientStorm`
`PhotonBridge.spawnLoop` at the storm center with `SpawnOptions.withScale(r, r·0.9, r)`
(executor scale fits any radius — no per-radius assets), windowed on
`shellDist < ARC_RANGE` with the `CROWN_RELEASE_RANGE` hysteresis and 40t budget-refusal
backoff, released with the storm / on `STATE_EXPLODE` (graceful destroy → clumps drift apart
through the shockwave for free).

**LOD/cull strategy.** (a) window the loop on shell distance (above); (b) photon's own
cull box kills rendering when off-screen; (c) `reducedFx` already disables the whole bridge —
the belt is a tier-2-only garnish and the geometry shells remain the baseline; (d) author a
`storm_clump_belt_far.fx` variant (300 particles, bigger sizes) and swap by distance band if
profiling demands it — the bridge can hold one handle per storm either way.

**Cost.** GPU: 1200 instanced quads ≈ noise; CPU: parallel update off-thread; 1 of 24
executors per storm (2–3 storms max concurrently → fine).
**Feasibility.** High per FX_FORMAT; medium confidence on `useGPUInstance` × `uvAnimation`
interplay — validate in `/photon_editor` first (the doc flags the GPU path as the
big-count path but flipbook-on-instanced needs an editor smoke test).
**Risk.** Photon absent → silent no-op (by bridge design); belt visible only outside the
outer shell so the never-see-inside and alpha-order invariants are untouched.

### 9. Photon HDR mass-bolt beam + REVERSE_SUB dark flash (lightning-in-mass, part 2)

**What.** Pair idea #6's shell glow with an actual luminous *core*: on qualifying strikes, a
one-shot photon `beam_emitter` chord buried inside the wall band — start/end sampled inside
r−4 … r−1 within ±25° bearing, `raycast: NONE`, width 0.6–1.2, life ~6t, material `texture`
with `hdr:[2.5,1.8,3.5]` → the photon bloom chain (bright-pass → mip blur →
`unreal_composite`) makes the wall *bleed light through its own alpha layers* — the one
thing CPU vertex color cannot do (LDR clamps at 1.0). Occasionally (1 in 5) fire the identity
variant instead: `blendFunc: REVERSE_SUB` — a *darkness bolt* that subtracts light from the
mass (GL blend equations are per-material, FX_FORMAT §3.2/§5).

**How, concretely.** `StormFxClient.scheduleArc`-side: when an arc rolls on a sphere storm at
near tier and `PhotonBridge.available()`, `PhotonBridge.spawn(STORM_MASS_BOLT, midPoint,
options.withRotationDeg(...))` with the beam's local `end` vector baked in the `.fx` and the
executor rotation aiming the chord; ≤1 per storm per 20t (own countdown — the bridge's 24 cap
is shared with everything else). Author both variants in `fxlib.py`.

**Cost.** 1 executor per strike for ~6t; bloom pipeline already running when photon is on.
**Feasibility.** High — beams + hdr + blend equations are all first-class per FX_FORMAT §4.1/§5.
**Risk.** Bloom threshold is global photon config (`bloom_threshold` 1.0) — tune hdr values,
don't touch user config. Dark-flash variant under Iris-compatible-mode needs a visual check.

### 10. Polar crown spiral (the top-down identity read)

**What.** From above (elytra, cliffs — and the impostor lid today is the *weakest* angle),
the dome should read as a hurricane: spiral banding converging on a polar eye, not concentric
UV-sphere rings.

**How, concretely.** Two changes inside `emitSphereShell`, zero new draw structure: (a) make
the per-ring pattern lead *superlinear* toward the pole — replace `(1 + ring·0.12)` with
`(1 + ring·0.12 + 0.9·pow(latFrac, 3))` so churn cells shear into log-spiral arms exactly
where rings shrink; (b) add a geometric twist term to high-latitude rings (`a0 + twist·latFrac²`
per ring pair, the cylinder shells' `VORTEX_TWIST` trick applied to latitude) so column edges
themselves wind. Cap the top ring at lat ~80° and fill the last 10° with a small counter-
rotating "eye collar" disc (8 columns, additive, darker center = the eye) — also neatly hides
the pole pinch of the UV sphere. The existing `STORM_CROWN_HALO` photon loop orbits above
this eye already — alignment is free.

**Cost.** ~0 (constants + one pow per ring) + ~16 quads for the eye collar.
**Feasibility.** High.
**Risk.** The banded-rotation law (EVAL-POL-F #1: geometry window stays camera-centered, only
pattern indices rotate) must be preserved — both changes act on pattern index/twist, not on
the arc window, so the law holds.

### 11. Ground dust inflow torus (the storm is *feeding*)

**What.** Upgrade the existing static ground-skirt dust band into an inflow system: dust
visibly dragged *toward and up into* the wall at the base — the classic supercell inflow
band, and the strongest "this thing is alive" cue at ground level.

**How, concretely.** (a) Geometry: a second flared skirt band (existing `emitColumn` dust
call, radius r+6 → r+1) whose churn pattern index scrolls *radially inward* over time
(index on quantized distance-to-wall instead of bearing) — reads as material flowing in;
(b) motion: one looping photon emitter per storm (or Quasar within STORM budget as the
photon-less path): `circle` shape at r+5, `shapeArc{arcMode: Loop}` sweeping the ring,
`velocityOverLifetime{radial: −0.25, orbital: [0, 0.4, 0], linear +Y ramp via curve}` —
spiraling inward then up the wall face; `colorBySpeed` brightens the fast final approach.
Attach to the same per-storm loop window as idea #8 (one `empty`-parented `.fx` can carry
belt + inflow + anvil together = still ONE executor per storm).

**Cost.** +~50 quads near tier; particles inside existing budgets.
**Feasibility.** High.
**Risk.** Terrain irregularity: keep the band's lower edge at the existing skirt depth so
slopes never open gaps.

### 12. Anvil outflow collar at the dome apex

**What.** Real storm tops flatten and vent outward (the anvil). Give the dome an outward-
flowing flared collar just below the crown: latitude band ~62–72° whose radius flares
*outward* ×1.15–1.25, additive, with pattern flow scrolling radially *outward* — opposite the
base inflow, closing the convection-cell story (in at the bottom, out at the top) and giving
mid-distance silhouettes a distinctive two-tier profile instead of a plain ball.

**How, concretely.** One extra ring pair in `emitSphereShell` (near tier, outer additive
shell only): flare radius, alpha fading to 0 at the outer lip, churn index keyed on quantized
radial distance with negative time scroll. Optional photon garnish rides the idea-#8/#11
combined per-storm `.fx`: a slow `circle`-shape emitter at apex height with `radial: +0.15`
drift and long-lived stretched billboards.

**Cost.** +~100 quads near tier.
**Feasibility.** High.
**Risk.** The flare must stay below the crown-spiral eye (idea #10) and outside the occluder
apex — both are latitude-band disjoint by construction.

### 13. Far-LOD flipbook impostor card (volumetric at 4 quads)

**What.** Beyond `FAR_LOD_END` the current impostor is an 8-column tinted ring + lid —
correctly cheap, visibly a cylinder. Replace (sphere storms only) with 1–2 camera-facing
quads sampling `storm_dome_flipbook.png` (idea #3): 8 pre-rendered churn frames of a
limb-darkened dome, crossfaded pairs at ~2 fps with the same slate/green palette and the
existing `impW` fade. Distant site storms then read *volumetric* — limb darkening baked into
the bake — for less than today's impostor cost.

**How, concretely.** `emitImpostor` gains a sphere branch: one camera-facing quad of size
2r × 2r·heightScale (the `emitCrossFlash` billboard math), UVs picking
`frame = (time/10) % 8` and `frame+1` on a second quad with complementary alpha (crossfade).
Needs the `POSITION_TEX_COLOR` switch from idea #2 (same pass infrastructure). Keep the
opaque occluder dome — the guarantee never rests on the impostor.

**Cost.** −~250 quads at far range (net win), 1 shared texture.
**Feasibility.** High after idea #2.
**Risk.** Billboard rotation parallax at the 320-block boundary — the ±16 crossfade already
covers the swap; bake frame 0 to match the geometric dome's average silhouette.

### 14. Interior strike backlight streak (post, `StrikeScreen` uniform)

**What.** While *inside* a sphere storm, an interior arc/flash should smear a bright radial
streak across the fog from the strike's screen position — the mass around the bolt lights up
directionally, not just uniformly (the current `flash()` only lifts fog far-plane + color).

**How, concretely.** Exact `ShockCenter` precedent (`shockwave.fsh` + `SunTracker.worldToNdc`,
parked at (10,10) when unprojectable): `StormInteriorFx` records the last flash's world pos
(arcs already have positions in `StormFxClient`), projects per frame, feeds `StrikeScreen`
(vec2) + reuses `flashAmount()` as strength in the existing `storm_interior` row. In the
shader: 6–8 tap radial smear of the *bright-pass* of the scene toward `StrikeScreen`, added
with the flash tint, gated `if (flashStrength > 0.01)` so quiet frames pay one branch.

**Cost.** 8 taps × flash frames only (≤6t per flicker); 1 uniform; no new pass.
**Feasibility.** High — every ingredient has a shipped precedent.
**Risk.** Double-exposure with the fog-color blow: scale the smear down by the existing
color-lift amount so the two flash channels sum ≤ current peak.

### 15. Custom Veil world-space shell shader (the endgame tier: per-fragment 3D noise + depth soft-clip)

**What.** The only idea that changes pipeline: promote the sphere shell passes to a small
custom world-space shader (Veil-managed program; NOT a post pass) to unlock the three things
CPU vertices cannot do: (a) per-fragment domain-warped 3D value noise / curl-advected flow
(`storm_curl_flow` sampled per fragment — true volumetric churn), (b) soft depth
intersection: sample scene depth, fade shell alpha over ~2 blocks where it cuts terrain
("soft particles" — kills the hard wall/ground line everywhere), (c) real uniforms: strike
positions array, storm center/radius → analytic per-fragment N·V and band density instead of
per-vertex approximations.

**How, concretely.** Keep the exact 3-pass structure and vertex generation; only the shader
and vertex format change (`POSITION_TEX_COLOR` + a params tex-coord channel). Veil provides
shader management + depth texture access on the world pipeline; the renderer already
branches per storm type, so cylinders/vanilla path stay untouched. **Hard rule from §7 risk
1:** under Iris this must degrade to the idea-#2 vanilla textured path — i.e. maintain both
paths behind one emit API. That duplication is the real cost, and why this ranks last
despite the highest ceiling.

**Cost.** Medium-high engineering (two render paths forever); GPU ~30–60 ALU/fragment on
wall pixels (with texture-based noise, not pure ALU noise).
**Feasibility.** Medium — Veil supports it; nothing in the repo does it yet for world
geometry (first-mover cost, new failure surface under shaderpacks/Sodium).
**Risk.** Iris/Sodium compatibility matrix; only attempt after ideas #1–#7 have banked the
cheap 80 %.

---

## Summary table

| # | Idea | Layer | Cost | Feasibility |
|---|---|---|---|---|
| 1 | N·V limb opacity law | CPU vertex math | ~0 | trivial |
| 2 | Textured shells (`POSITION_TEX_COLOR`) | vanilla pipeline | 1 fetch/frag | high |
| 3 | Python texture set (cloud tile, curl flow, puff atlas, LUTs, flipbook) | offline | 0 runtime | high |
| 4 | Noise-displaced interleaved shells + per-shell flow | CPU vertex math | ~0 | high |
| 5 | `WallBand` fog-grade coupling | existing post row | ~0 | trivial |
| 6 | CPU strike-glow injection | CPU vertex math | ~0 (burst) | trivial |
| 7 | Billboard clumps between shells, distance-band sorted | geometry | +200 quads | high |
| 8 | GPU-instanced photon clump belt (800–1200) | photon loop | 1 executor | high (editor-verify GPU path) |
| 9 | Photon HDR mass beam + REVERSE_SUB dark flash | photon one-shot | 1 executor/strike | high |
| 10 | Polar crown spiral + eye collar | CPU vertex math | ~0 | high |
| 11 | Ground dust inflow torus | geometry + loop FX | +50 quads | high |
| 12 | Anvil outflow collar | geometry (+FX) | +100 quads | high |
| 13 | Far-LOD flipbook impostor | geometry + texture | net −quads | high (after #2) |
| 14 | Interior strike backlight streak | existing post row | 8 taps (flash only) | high |
| 15 | Custom Veil world shader (3D noise, depth soft-clip) | new pipeline | med-high eng. | medium |

**Suggested batching:** #1+#4+#6+#10 are one CPU-math PR (no assets); #3 then #2+#7+#13 are
the texture PR; #5+#14 are one post PR; #8+#9+#11+#12 share one per-storm `.fx` + bridge PR.
Every idea preserves the frozen invariants: opaque occluder never-see-inside, camera-centered
arc windows (EVAL-POL-F #1), Iris fallback = world geometry, `FxBudget`/`PhotonBridge` caps,
reducedFx ladders.
