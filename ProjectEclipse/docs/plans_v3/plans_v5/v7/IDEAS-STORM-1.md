# IDEAS-STORM-1 — Visual-reference-driven ideas for the volumetric sphere storms

User brief: the site sphere storms should read as **balls of wind and weather** — thick
mass, many layers, depth and height. This report mines real-world storm structure and
game storm walls for stealable visual elements and maps each one onto our tech.

## Tech inventory (what "our tech" means below)

- **`StormWallRenderer`** — per-vertex procedural world-space geometry: 3 passes
  (opaque occluder dome → alpha shells → additive shells), sphere storms are UV-dome
  latitude bands × longitude columns (near tier: 96 segments × 10 rings × 3 shells at
  r+2/r/r−2), camera-centered tangent-arc windows (EVAL-POL-F #1: geometry never
  rotates; all motion lives in the churn-pattern noise index), `hash3` noise, zero
  textures, zero per-frame heap. Existing hooks reused heavily below: churn clocks
  (`SPHERE_CHURN_TICKS`), band leads (`SPHERE_BAND_LEAD`), rim factor, lightning-vein
  color crawl, dust skirt, day-carve (`DAY_*`), `daylight`, `bolts()`/`arcs()` lists.
- **`StormInteriorFx`** — interior fog/grade/uniform feeder (`Interior`, `RainAmount`,
  `Time`, `Sphere`, `WallProx` — frozen set, additive-only growth), gust clock
  (`gustAmount()`, 160 t bar), flash beats, managed quasar loop emitters (rain sheets,
  god-fingers), budgeted point lights, `approachAmount()` exterior pre-tint.
- **`StormFxClient`** — orchestration, `ClientStorm` (center/radius/height/type/state,
  visibility + explode ramps), bolt/arc scheduling, `StormLoopSound`.
- **Quasar emitters** (`assets/eclipse/quasar/emitters/*.json`) — hand-writable Veil
  particle loops/bursts through `QuasarSpawner` + `FxBudget` (STORM channel: 12
  spawns/window full, 6 reduced; ≤ 1500 live particles; ≤ 16 lights).
- **Photon `.fx`** via `PhotonBridge` — editor-authored NBT effects, client-side
  executor spawn. Available, but the storm cluster is quasar-native; ideas below
  default to quasar/renderer and flag photon only where authored layering would win.
- **`storm_interior.fsh`** — screen-space post (interior only, Iris-gated off).

## Frozen constraints every idea respects

1. **Never-see-inside occluder** (geometry, not post) — no idea opens the dome; all
   radial modulations keep every shell outside `r − OCCLUDER_INSET` (5 blocks).
2. **Wire format** `S2CStormStatePayload` untouched — everything is client-derived.
3. **Camera-centered tangent-arc windows** — new patterns index the RAW world angle
   (the vein-gate precedent) so features are world-stable and never drift with camera.
4. Zero textures / zero per-frame heap in the renderer; FxBudget + reducedFx ladder.
5. Prior STORM.md rejections navigated, not repeated: per-column sun-side
   *self-shadowing* (rejected) ≠ idea 5 (silhouette *rim scatter*, additive-only);
   exterior *silhouette god-rays* (rejected — implies the dome leaks) ≠ idea 15
   (day-sky *transmission carve* between bands); parallax far-side dome stays rejected.

## Reference index

| Reference | What it teaches | Ideas |
|---|---|---|
| Hurricane satellite view (eye, eyewall, spiral rainbands, outflow) | log-spiral band organization, eye/eyewall, layered rotation | 1, 2, 4, 8, 9 |
| Tornado supercell (wall cloud, beaver-tail inflow, dust ring, "stacked plates" striations) | vertical stratification, asymmetric base drama, ground coupling | 3, 7, 13 |
| Night hurricanes from the ISS / anvil-crawler lightning | diffuse in-cloud glow, horizontal spider lightning | 6, 16, 17 |
| Backlit cumulonimbus ("silver lining"), green severe-hail sky | sun-side rim scatter, sick-green storm light | 5, 20 |
| Fortnite storm wall | layered multi-frequency translucency, readable curved wall | 11 |
| Zelda TotK gloom | boiling viscous blob mass, slow pulse | 12, 10 |
| Diablo 4 sandstorm walls | torn top-edge streamers, scrolling sheets | 14 |
| WoW Maelstrom | spiral throat, banded vortex ceiling | 19 |

---

## The 20 ideas, ranked

### 1. Log-spiral rainbands wrapping the dome — **the** hurricane read
- **Reference:** any satellite hurricane photo — cloud mass organizes into 2–4 arms
  spiraling from the outer edge into the eyewall. This single feature makes a blob of
  cloud read as a *rotating weather system* instead of a fog dome.
- **Steal:** log-spiral band density: clumpy, bright, thick ON the arms; thinner,
  darker, slightly transparent between them.
- **How:** `StormWallRenderer.emitSphereShell` — pure per-column color/alpha math on
  existing quads. Spiral phase `p = fract(ARMS · a0/2π + SPIRAL_WRAP · latFrac +
  time · ARM_DRIFT)` with `ARMS = 3`, `SPIRAL_WRAP ≈ 1.4` (each arm wraps ~½ turn
  base→apex), indexed off the RAW angle (vein-gate precedent) so arms hold together
  vertically and stay world-stable. Band weight `w = smoothstep`-bump around the arm
  center: on-arm → churn ×1.3, alpha +0.15, additive band hue brightened; off-arm →
  alpha −0.12 (day-carve style, never below the occluder guarantee's needs since the
  occluder is separate geometry). Arms drift with the existing band-lead rotation so
  the shear ladder (idea 4) twists them naturally.
- **Cost:** zero quads; ~6 flops/column of color math. All LOD tiers (impostor skips).
- **Tiering:** tier-independent (cheaper than the veins we already gate).

### 2. Cauliflower clump billboards riding the arm lanes — mass and chunkiness
- **Reference:** cumulus congestus towers embedded in hurricane rainbands; Fortnite's
  wall reads "thick" because discrete lumps break the smooth surface.
- **Steal:** big soft cloud lumps protruding from the shell, with faked shading:
  2-tone vertical gradient (lit violet-gray top → dark slate base) + bright rim.
- **How:** `StormWallRenderer`, near tier only. N ≈ 30 blob anchors hashed onto
  (arm, k) positions along idea 1's spiral paths, radius `r + 1..3`, size 6–14
  blocks. Each blob = a 4-petal diamond fan in QUADS mode (the cone-lid degenerate
  trick: quad = edge0, edge1, center, center → 4 quads/blob) with center vertex
  bright/opaque and edge vertices alpha 0 — a soft radial sprite with zero textures.
  Top petals get the lit tone, bottom petals the dark tone ("normal-ish" 2-tone
  shading); the existing rim factor multiplies edge-petal alpha for silhouette pop.
  Blobs drift along their arm with the band lead; each swells/shrinks ±10% on a slow
  hash phase so the surface boils.
- **Cost:** ~120 quads near tier, alpha + additive split; zero allocations (fixed
  slot array indexed by hash — same pattern as explosion shards).
- **Tiering:** 30 full / 14 reduced / 0 at tier 0; culled beyond near LOD.

### 3. Stacked cloud decks with ledge lips — vertical structure, "many layers"
- **Reference:** supercell "stacked plates" striations and lenticular stacks — the
  storm reads TALL because horizontal strata interrupt the vertical smear.
- **Steal:** 3–4 distinct horizontal decks: a dark heavy base deck, a mid deck, a
  bright upper deck, each separated by a visible seam/ledge.
- **How:** `StormWallRenderer.emitSphereShell` — map ring → deck (rings 0–3 / 4–6 /
  7–8 / 9-cap). Per deck: gray-range offset (base darkest), small alternating radius
  offset (±0.4, ledges), and a darkened seam color on the shared boundary ring edge
  (free — it's an existing vertex). Near tier adds one thin "ledge lip" ring of
  columns at the 2 main seams (torn-crown reuse: short outward flare, alpha fading
  out) so the decks cast a readable break in silhouette.
- **Cost:** color math + ≤ 192 lip quads near tier (2 seams × 96); occluder-safe
  (offsets ≪ 5-block inset).
- **Tiering:** lips near tier only; deck coloring everywhere including far tier.

### 4. Differential-rotation shear ladder with reversed outflow deck — motion language
- **Reference:** real hurricanes: low-level inflow spirals in cyclonically, upper
  outflow rotates the *opposite* way. Today's linear "+12% per ring" reads as one
  rigid body slightly smeared.
- **Steal:** height-banded rotation: slow heavy base, fast mid-deck, top deck slowly
  counter-rotating — instantly "layered atmosphere", not "spinning ball".
- **How:** `StormWallRenderer` — replace the linear per-ring lead with a per-deck
  curve on the pattern clock only (geometry stays camera-centered): base deck 0.7×,
  mid 1.5×, upper 1.0×, top 2 rings −0.5× (reversed). Idea 1's arms inherit the
  shear, so arm tops visibly lag/oppose their bases — free depth cue.
- **Cost:** zero quads, zero flops added (constant table swap).
- **Tiering:** all tiers.

### 5. Sun-side rim scatter ("silver lining") — light behavior, day identity
- **Reference:** backlit cumulonimbus: the silhouette edge facing the sun burns with
  a thin bright fringe while the mass stays dark.
- **Steal:** the dome's tangent rim on the sun side gets a pale bright fringe; the
  anti-sun rim stays the current violet.
- **How:** `StormWallRenderer` — we already compute a rim factor per column; multiply
  it by `sunFacing = 0.5 + 0.5 · dot(columnBearingXZ, sunAzimuthXZ)` (sun azimuth
  from `SunTracker`, fetched once per frame like `daylight`). On the additive outer
  shell, lerp the band hue toward desaturated bone-white (NOT warm gold — warm is
  reserved for the loot-camp beacon) by `sunFacing · daylight · rim`, alpha +30% at
  the fringe. Night: moon-silver at 25% strength. This is additive rim *scatter* on
  the silhouette, not the rejected per-column self-shadowing (no darkening pass).
- **Cost:** zero quads; 1 dot product per column.
- **Tiering:** all tiers (it's the long-distance read that profits most).

### 6. Diffuse in-cloud lightning glow cells — light behavior, night identity
- **Reference:** night hurricanes filmed from the ISS: lightning rarely shows as
  bolts — it shows as soft patches of the cloud mass glowing from within, pulsing
  irregularly across the storm.
- **Steal:** random interior glow patches that light a local region of the wall
  through the cloud, with soft falloff — "there is weather INSIDE this thing".
- **How:** `StormWallRenderer` — hash-scheduled glow cells: per 60-tick window and
  per (deck, longitude supercell), a gate (`hash > 0.86`) opens a 6–10-tick
  smoothstep envelope; columns within the cell lerp additive alpha up to +0.35 and
  hue toward violet-white with radial falloff from the cell center. 1-in-3 cells also
  request one budgeted `FxBudget` point light (≤ 1 concurrent per storm) just inside
  the shell, so nearby terrain answers the pulse. Pairs with idea 16.
- **Cost:** zero quads; ≤ 1 light; color math behind a cheap gate.
- **Tiering:** glow cells all tiers ≥ 1; the point light tier 2 only.

### 7. Gust-front ripple + dust-ring surge — the wall breathes wind
- **Reference:** haboob/outflow-boundary footage and the tornado base dust ring: the
  leading edge of a gust visibly bulges and drags a ring of dust with it.
- **Steal:** a slow traveling bulge that runs around the sphere's base, with the
  existing dust skirt surging where the bulge passes — wind you can SEE.
- **How:** `StormWallRenderer` — for the lowest 3 rings, radius += `sin(3·a −
  time·ω) · 0.6 · (0.4 + 0.6 · gust)` tapered to zero by `latFrac` (amplitude 0.6 ≪
  the 3-block margin above the occluder — guarantee intact). The dust-skirt band
  (already emitted at the equator) reads the same wave: alpha ×(1 + 0.8·wavefront),
  outer radius +1 at the crest. Drive the envelope from
  `StormInteriorFx.gustAmount()` so wall, rain, roar and updraft all gust together.
- **Cost:** zero quads (vertex math on existing columns).
- **Tiering:** near + far tier; skirt part near tier (where the skirt exists).

### 8. Apex eyewall collar + eye dimple — hurricane crown
- **Reference:** the hurricane eye: a tight, steep, fast-rotating eyewall ring around
  a calm depression — the crown feature that stamps "cyclone" on the top-down and
  distant silhouette read.
- **Steal:** the dome apex dimples slightly inward and is ringed by a brighter,
  faster, counter-shifted collar band.
- **How:** `StormWallRenderer` — top 2 latitude rings pull radius inward by up to
  3.5 blocks absolute (capped ≪ the 5-block occluder inset — the occluder dome stays
  closed and covered; never-see-inside untouched), forming a shallow crater. Add one
  48-column collar torus band at the dimple rim (crown-swirl-collar reuse from the
  vortex): additive, 1.6× band speed on the pattern clock, rim-boosted. From inside,
  the existing god-fingers already stream through this "eye" — the exterior and
  interior stories now agree.
- **Cost:** vertex math + 48 collar quads near tier.
- **Tiering:** dimple all tiers; collar near tier.

### 9. Anvil outflow wisps — overshooting top and cirrus streamers
- **Reference:** overshooting tops venting thin cirrus streamers off the storm summit,
  smeared downwind — the classic "this thing is exhaling" summit signature.
- **Steal:** thin, fast, translucent wisps streaming tangentially off the apex collar
  and dissolving a few blocks out.
- **How:** new quasar loop emitter `storm_anvil_wisp.json` (clone `vortex_wisp` DNA:
  additive slate-violet, low alpha ≤ 0.14, `velocity_stretch_factor 2.4`, life ~50,
  `veil:wind` outward drift), ≤ 2 managed loops parked on the apex ring at 0.35r
  offsets, spawn-managed by `StormFxClient` next to the god-finger manager, STORM
  channel, released on state change/reset. Renderer fallback if budget is tight:
  10–12 tangential ribbon quads reusing the bolt-ribbon emitter.
- **Cost:** ≤ 2 loop emitters ≈ 2 spawns + retries; ≤ ~20 live particles.
- **Tiering:** 2 loops full / 1 reduced / 0 tier 0 (god-finger ladder pattern).

### 10. Breathing pulsation synced to the interior drone — the storm is alive
- **Reference:** TotK gloom pulse / fantasy storm-sphere idiom: a slow whole-body
  inhale-exhale reads as *contained pressure*, exactly the "ball of weather" fantasy.
- **Steal:** ±1% radius swell at ~0.15 Hz with counter-phase alpha (denser when
  contracted, wispier when expanded), phase-locked to the interior sub-bass pulses.
- **How:** `StormWallRenderer` — global scale `1 + 0.012 · sin(2π · time/140)`
  applied to shell radii only (max ±1.2 blocks at r=100, occluder-safe; occluder
  dome does NOT breathe, preserving the guarantee margin); alpha ×(1 ∓ 0.08). Reuse
  the same 140 t clock in `StormInteriorFx` for the heartbeat-adjacent pulses so
  sound and mass breathe together (one shared constant, the
  `EXPLODE_IMPLODE_FRAC` cross-class precedent). Suppressed during spawn/dissipate
  ramps and EXPLODE.
- **Cost:** zero quads; one sin per frame.
- **Tiering:** all tiers.

### 11. Two-octave fine churn on the inner fast sheet — Fortnite wall translucency
- **Reference:** Fortnite's storm wall: a coarse slow pattern PLUS a fine fast layer
  visible through it — the overlap is what sells "deep translucent volume".
- **Steal:** close-up fine detail living inside the coarse billow instead of one
  noise frequency per shell.
- **How:** `StormWallRenderer.emitSphereShell` — on the inner sheet shell only
  (shellIndex 2), multiply churn by a second octave: `hash3(shellIndex+70, noiseSeg
  (fine, un-coarsened), noiseT·2)` weighted 0.3. The outer billow already coarsens
  its cells; this widens the frequency spread between layers, which is the actual
  Fortnite trick.
- **Cost:** zero quads; one extra hash per inner-shell column, near tier only.
- **Tiering:** near tier, quality ≥ 1.

### 12. Boiling base blobs — TotK gloom mass at ground level
- **Reference:** TotK gloom: viscous dark bubbles swelling out of the mass and
  subsiding. The base of the dome is what players stand next to — thickness there
  pays the most.
- **Steal:** slow dark blobs that swell out of the wall base and pop.
- **How:** `StormWallRenderer`, near tier: 14 anchors hashed around the equator ring
  (camera-arc-windowed like everything else); lifecycle 60–100 t (70% swell, 30%
  collapse) on hash phase; each is a 4-quad diamond fan (idea 2 geometry), alpha
  pass, colored slightly darker than the wall base with a faint additive rim pop at
  maximum swell. Radius bulge ≤ 2.5 blocks (occluder-safe). Alternative: quasar
  emitter with big soft dark particles — rejected here because dark alpha particles
  sort badly against the shells; renderer quads draw in-pass.
- **Cost:** ~56 quads near tier.
- **Tiering:** 14 full / 7 reduced / 0 tier 0.

### 13. Wall-cloud bulge + beaver-tail inflow lane — supercell asymmetry
- **Reference:** tornado supercells: a lowered dark rotating wall cloud on one flank,
  with a smooth "beaver tail" band of cloud visibly feeding INTO it. Asymmetry +
  inflow = "this storm is eating the sky".
- **Steal:** one slowly migrating bearing of the dome base is lower, darker and
  bulged; a lane of cloud clumps streams toward and merges into it.
- **How:** `StormWallRenderer` — a wall-cloud anchor bearing drifting 0.0006 rad/t;
  columns within ±0.5 rad of it get: −15% gray, +2.5 radius bulge tapering over the
  lowest 2 rings, +0.1 alpha. The beaver tail reuses idea 2's blob slots: 8 of the
  30 blobs are re-anchored each cycle onto a quadratic lane from (bearing + 0.9 rad,
  r + 30 blocks, low altitude) descending into the bulge, drifting inward ~0.05
  blocks/t and dissolving at the wall. Outside-the-shell geometry is fine — it is
  additive/alpha decoration, the occluder is untouched.
- **Cost:** color/vertex math + 0 net new quads (borrows blob budget).
- **Tiering:** near tier, quality ≥ 1.

### 14. Torn rim streamers — Diablo 4 sandstorm top edge
- **Reference:** D4's Kehjistan sandstorm walls: the top edge constantly tears off
  into ragged streamers that dissolve downwind — the edge is never a clean line.
- **Steal:** short-lived ragged ribbons shredding off the upper rings, blown along
  the rotation direction.
- **How:** `StormWallRenderer`, additive pass, near tier: 12 fixed streamer slots;
  each seeds at a hashed (upper-ring, angle) point, lives 40 t, translates with the
  local band-lead velocity + 0.05/t outward, rendered as a 2-quad tapered ribbon
  (bolt-ribbon emitter reuse), dissolving via the hash-strobe dropout already used
  by explosion shards (house glitch style).
- **Cost:** ≤ 24 quads near tier, fixed slots, zero allocation.
- **Tiering:** 12 full / 6 reduced / 0 tier 0.

### 15. God-ray gaps between rainbands — day-sky transmission
- **Reference:** satellite + ground shots: between rainbands the sky reads THROUGH,
  and low sun pushes visible bright lanes into the gaps.
- **Steal:** inter-arm gaps are genuinely more transparent, and on the sun-facing
  quadrant they carry a faint bright lane — layered depth for free during day.
- **How:** `StormWallRenderer` — extends idea 1: in gap centers (band weight ≈ 0),
  carve alpha a further −0.10 · `daylight` on the alpha shell (bright sky reads
  through — the day-carve precedent, occluder unaffected as ever), and on the outer
  additive shell add +0.12 · `daylight` · `sunFacing` pale lift in the same gap
  longitudes. **Navigates the prior rejection:** no shafts stream OFF the silhouette
  and nothing implies interior light — this is exterior skylight transmitted through
  thin cloud, day-only, and lives entirely on existing quads.
- **Cost:** zero quads; piggybacks idea 1 + idea 5 terms.
- **Tiering:** all tiers where arms render; needs `daylight > 0.3`.

### 16. Anvil-crawler spider veins — horizontal lightning crawl
- **Reference:** anvil crawlers: lightning that spiders HORIZONTALLY along cloud
  decks for kilometers, distinctly different from vertical strikes.
- **Steal:** occasional bright heads racing sideways along a deck seam, complementing
  the existing vertical veins.
- **How:** `StormWallRenderer` — transpose the existing vein math: gate per (deck
  seam, 80-tick window); head angle = `fract(time · 0.02 + hash) · 2π` clamped to
  the visible arc; columns within ±0.12 rad of the head, on the 2 rings adjacent to
  the seam latitude, lerp toward white with the vein's quadratic falloff. Same
  color-only, zero-quad approach; day-boost rule inherited.
- **Cost:** zero quads; vein-family math, near tier, quality ≥ 1.
- **Tiering:** as veins (tier ≥ 1); mutually rate-limited with idea 6 cells so light
  events never stack (shared window hash).

### 17. Bolt-reactive bearing flash — the wall answers its own lightning
- **Reference:** any storm video: when a bolt fires, the surrounding cloud face
  lights up for 2–3 frames. Our sky bolts currently leave the wall unmoved.
- **Steal:** wall columns near a live bolt's bearing flare briefly.
- **How:** `StormWallRenderer` — it already iterates `StormFxClient.bolts()`: for
  bolts with age < 4 t belonging to this storm, boost additive alpha of columns
  within ±0.35 rad of the bolt bearing by `0.3 · (1 − age/4)`, with idea 6's radial
  falloff. Pure read of existing state, no new lists.
- **Cost:** zero quads; a bearing compare per column only while a bolt is live.
- **Tiering:** all tiers ≥ 1.

### 18. Virga rain curtains under the outer arms — weather falling out of the ball
- **Reference:** rainband cross-sections: dark translucent shafts of rain hang from
  band bases to the ground ("virga" when they evaporate mid-air).
- **Steal:** hazy vertical curtains connecting the lowest cloud deck to the terrain
  under each spiral arm — the storm doesn't just sit on the ground, it RAINS onto it.
- **How:** `StormWallRenderer`, near tier, alpha pass: at each arm's current
  longitude (from idea 1's phase), emit 3–4 tall `emitColumn` bands at radius
  r + 1.5, from the deck-0 base down to `cy − 2`, blue-gray slate, alpha 0.20 at top
  → 0 at ground, sheared 0.3 rad in the rotation direction (wind-driven rain).
  Exterior complement of the interior rain sheets.
- **Cost:** ~30 quads near tier (3 arms × ~10 columns).
- **Tiering:** near tier, quality ≥ 1; suppressed during EXPLODE.

### 19. Maelstrom throat ceiling — interior apex spiral
- **Reference:** WoW's Maelstrom: a banded spiral throat overhead. Inside our storm
  the apex is currently undifferentiated fog.
- **Steal:** looking up from inside, a slowly rotating spiral ceiling with the
  god-fingers falling out of its center — interior height and structure.
- **How:** `StormWallRenderer`, inside the deep-interior early-out branch (the
  Tyrant-silhouette precedent — drawn against the occluder, guarantee untouched):
  3 concentric rings (0.55r / 0.35r / 0.18r) under the apex, each 12 columns with
  idea 1's spiral alpha gates and staggered rotation clocks, green-violet additive,
  engaged only while `interiorAmount > 0.6`. The center hole is where god-fingers
  already originate — the eye read completes.
- **Cost:** 36 quads, interior-only (they replace the storm's exterior cost — when
  deep inside, the shells early-out anyway).
- **Tiering:** tier ≥ 1; skipped while `flashAmount()` is live (flash owns the eye).

### 20. Green storm-light approach tint — severe-weather dread
- **Reference:** the notorious green sky before severe hail/tornado weather —
  instantly legible as "that is not normal weather" even to players who can't name it.
- **Steal:** the last 60 blocks of approach to a sphere storm tint the world faintly
  sick-green before the wall dominates the screen.
- **How:** `StormInteriorFx` — the exterior `approachAmount()` pre-tint already
  drains daylight up to 15%; for `TYPE_SPHERE` sites, additionally pull the fog
  color toward the fog-green cast (≤ 0.12 blend, feathered by the same approach
  band). No shader change (fog color is fed per-frame already), no uniform growth.
- **Cost:** color-only, a few flops per tick.
- **Tiering:** all tiers; respects the existing teleport-snap hygiene.

---

## Budget roll-up (near tier, steady state, if EVERYTHING ships)

| Bucket | Ideas | Added cost |
|---|---|---|
| Pure color/vertex math | 1, 4, 5, 6, 7, 10, 11, 13, 15, 16, 17, 20 | ~0 quads, O(columns) flops |
| Renderer quads | 2 (~120), 3 (~192), 8 (48), 12 (~56), 14 (~24), 18 (~30), 19 (36 interior) | ≈ +470 exterior worst case |
| Emitters/lights | 9 (≤ 2 loops), 6 (≤ 1 light) | inside STORM channel + light caps |

Recommendation if a quad envelope of ~+300 near tier is the ceiling: ship all
color-math ideas + 2, 8, 12 first (the mass/structure core), then 3's lips, 14, 18
as the second wave. Ideas 1 + 4 + 5 together transform the read for literally zero
quads and should land first in any ordering.

## Top 8

1. Log-spiral rainbands (color-gated arm density on existing dome columns — zero quads).
2. Cauliflower clump billboards riding the arms (diamond-fan soft blobs, 2-tone + rim).
3. Stacked cloud decks with ledge lips (per-ring deck grays/offsets + 2 seam lip rings).
4. Differential-rotation shear ladder with reversed top deck (pattern-clock table swap).
5. Sun-side rim scatter via `SunTracker` (bone-white silhouette fringe, additive-only).
6. Diffuse in-cloud lightning glow cells (+ ≤ 1 budgeted point light).
7. Gust-front ripple + dust-ring surge driven by `gustAmount()`.
8. Apex eyewall collar + eye dimple (occluder-safe crater + counter-shifted collar).
