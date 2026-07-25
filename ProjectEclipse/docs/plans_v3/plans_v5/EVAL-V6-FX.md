# EVAL-V6-FX — v6 Veil-effect precision audit

## Verdict

**Overall precision: 7.3 / 10** (equal-weight mean of the eight clusters).

The wave is substantially implemented: every cluster has at least four claimed changes
present in source, the touched emitter corpus is syntactically valid, claimed Java/shader
uniform names match, and the hand-audited effect loads remain well below the documented
particle/geometry envelopes. Precision is nevertheless below ship quality because three
fullscreen shaders use reverse-edge `smoothstep` (undefined by GLSL), `rift_glitch` has an
exact-center `atan(0,0)` NaN path, and ALTAR's flagship anticipation emitter repeats a
previously documented fatal point-attractor schema error.

| Cluster | Score |
|---|---:|
| GRADE | 7.0 / 10 |
| GLITCH | 8.0 / 10 |
| LIMBO | 6.0 / 10 |
| STORM | 7.0 / 10 |
| RIFT | 8.5 / 10 |
| ALTAR | 6.5 / 10 |
| WAND | 7.0 / 10 |
| UIFEEL | 8.5 / 10 |

## Audit method and cross-cutting results

- Read-only source audit; no Gradle or git commands were run.
- Parsed all 65 files under `assets/eclipse/quasar/emitters/` with Python JSON decoding:
  **65/65 syntax-valid**. Syntax validity does not validate Veil codecs; ALTAR has one
  codec-level failure detailed below.
- Uniform parity: no name/type mismatch found in the ten audited post shaders. Samplers
  remain Veil-bound; every non-sampler declaration has a matching Java write.
- No explicit `dFdx`, `dFdy`, `fwidth`, `textureGrad`, or `textureProj` use was found.
  Texture samples inside conditionals are controlled by uniforms; no fragment-varying
  implicit-derivative hazard was found.
- Expected wave workloads remain below 1,500 live Quasar particles, the per-channel
  spawn caps, 16 lights, and RIFT's 400-triangle cap. Examples: LIMBO near motes cap at
  2×12, STORM god-fingers at 2×8, and RIFT recounts at 374 triangles.
- The “1,500 live particles” guard is not a hard cap: `FxBudget.liveParticles()` caches
  Veil's count once per 20-tick window and never reserves the particles of accepted
  emitters (`src/main/java/dev/projecteclipse/eclipse/veilfx/FxBudget.java:50-52`,
  `:158-167`). Many large emitters accepted in one window can therefore overshoot 1,500.
  The audited wave's realistic stacks do not independently reach that boundary, but team
  claims that the cap is strictly enforced are too strong.

---

## GRADE — 7.0 / 10

### Claim verification

1. `world_grade` contains the true-horizon band, explicit `bandH * bandH`, wrapped
   18 Hz grain clock, split tone, double-sine vignette, sky seethe, and output dither
   (`world_grade.fsh:57-119`).
2. `VeilPostController` feeds the claimed `Time`, `HorizonY`, and reduced `Detail`, in
   addition to all frozen grade uniforms
   (`VeilPostController.java:195-203`).
3. `ghost_grade` contains violet-memory retention, dark-side edge shimmer, void sky,
   explicit-square heartbeat, and dither (`ghost_grade.fsh:52-105`); `GhostGradeFx`
   feeds `Ghost/Time/Detail` and flattens CPU breath under reduced FX
   (`GhostGradeFx.java:81-99`).
4. `sun_halo` has the five depth probes, three spectral rings, eased CPU occlusion input,
   chromatic radii, anamorphic streak, shimmer, breath, and local dither
   (`sun_halo.fsh:69-136`; `VeilPostController.java:255-270`).
5. `altar_aberration` has the centroid-retuned two-tap split, resonance rings, clamped
   glyph echo, and dither (`altar_aberration.fsh:54-102`); the binder gates the flash,
   freezes its drain while paused, and feeds all four uniforms
   (`AltarAberration.java:118-133`, `:191-197`).

### Defects

- **HIGH — undefined reverse `smoothstep`:**
  `src/main/resources/assets/eclipse/pinwheel/shaders/program/sun_halo.fsh:83-84`
  calls `smoothstep` with radius expressions ordered high→low twice, and `:122` calls
  `smoothstep(1.0, 0.92, x)`. GLSL specifies undefined results when `edge0 >= edge1`.
  These expressions drive the core rim and streak edge fade, so the pass can disappear,
  invert, or become driver-dependent. Use `1.0 - smoothstep(low, high, x)`.

Uniform parity and reduced-FX feeds otherwise check out. Craft is strong in the other
three passes, but one undefined core halo mask materially lowers the cluster score.

---

## GLITCH — 8.0 / 10

### Claim verification

1. `border_glitch` contains quantized directional pull, kick desync, proximity-scaled
   chroma, AV-law grain, and dither (`border_glitch.fsh:46-124`);
   `BorderFxRenderer` feeds all five uniforms and suppresses kick triggering under
   reduced FX (`BorderFxRenderer.java:256-275`, `:283-319`).
2. `rift_glitch` contains voxel-sort lanes, mirror shards, jitter echo, black-hold-safe
   dither, and the two additive ambient uniforms (`rift_glitch.fsh:61-129`);
   `TransitionFx` feeds `RiftAmount/RiftCenter` (`TransitionFx.java:260-284`) and
   `RiftFx.publishAmbient` forces the source to zero under reduced FX
   (`RiftFx.java:292-313`).
3. `shockwave` has the crisp `ringTerms` helper, pressure dimple, gated echo pulse,
   travel attenuation, and activity-local dither (`shockwave.fsh:46-114`);
   `WaveOverlay` applies the claimed 0.6 reduced strength to both feed paths
   (`WaveOverlay.java:293-303`).
4. `xbox_era` contains the four-tap resolve/bloom, post-gamma three-zone grade, warm
   vignette, and static dither (`xbox_era.fsh:38-90`); `XboxEraFx` drives `Amount` to
   zero under reduced FX (`XboxEraFx.java:70-81`).

### Defects

- **HIGH — exact-center NaN path:**
  `src/main/resources/assets/eclipse/pinwheel/shaders/program/rift_glitch.fsh:77-85`
  enters the mirror-shard branch at maximum strength when `lensDist == 0`, then evaluates
  `atan(fromLens.y, fromLens.x)` as `atan(0,0)`. The log's claim that the degeneracy is
  “bounded by the shard-zone radius” is backwards: the zone includes and peaks at the
  center. NaN can propagate through `floor`, `cos/sin`, `mirrorUv`, and the sampled UV.
  Apply an epsilon or explicitly bypass/refine the center.

No other uniform, budget, or reduced-FX precision failure was found in this cluster.

---

## LIMBO — 6.0 / 10

### Claim verification

1. The shader contains near micro-ripples, far swells, sparse soul-green glints,
   wave-broken reflection, and the azimuthal storm glow
   (`limbo.fsh:169-218`, `:227-240`).
2. `LimboAmbience` feeds all eleven non-sampler uniforms, gates storm glow on valid frame
   matrices/reduced FX, and zeroes curvature under reduced FX
   (`LimboAmbience.java:433-477`, `:491-512`).
3. Its rolling windows implement per-emitter sway and a garnish flag that clears/skips
   near motes when reduced FX is toggled (`LimboAmbience.java:184-234`, `:310-314`).
4. `LimboSpecialEffects` skips coronal wisps under reduced FX and uses nullable
   `BufferBuilder.build()` for the dash reflection (`LimboSpecialEffects.java:360-379`,
   `:411-513`).
5. `LimboHorizonShips` skips the passing lantern under reduced FX
   (`LimboHorizonShips.java:233-238`).
6. Emitter numbers match the log: near motes rate 8/count 1/cap 12, fog 8/2/20,
   fogbank 20/1/8, and godray 10/1/10
   (`limbo_motes_near.json:4-6`, `limbo_fog.json:4-6`,
   `limbo_fogbank.json:4-6`, `limbo_godray.json:4-6`).

### Defects

- **HIGH — undefined curvature edge fade:**
  `src/main/resources/assets/eclipse/pinwheel/shaders/program/limbo.fsh:118-119`
  uses `smoothstep(1.0, 0.94, uv.y)` and `smoothstep(1.0, 0.96, uv.x)`. Both are
  reverse-edge undefined behavior in the full-quality horizon warp.
- **MEDIUM — unguarded homogeneous divide:**
  `src/main/resources/assets/eclipse/pinwheel/shaders/program/limbo.fsh:76-78`
  divides by `clip.w` without a finite/epsilon guard. It is called for far-plane ray
  reconstruction (`:98-100`) and every sampled depth (`:123-129`); singular or near-zero
  `w` can inject Inf/NaN into UV warp, distance, water masks, and noise coordinates.
- **MEDIUM — reduced-FX gap in the new water motion:**
  the v4 swells, micro-ripples, blinking glints, and reflection ripple all remain
  time-animated at full amplitude (`limbo.fsh:173-218`). The CPU only zeroes
  `CurveAmount`/`LightningGlow`; there is no detail gate for these additions
  (`LimboAmbience.java:472-477`). “Cheap ALU” addresses performance, not the reduced-motion
  contract.

---

## STORM — 7.0 / 10

### Claim verification

1. `StormWallRenderer` contains distinct shell churn clocks, raw-cell lightning veins,
   explosion radius staging, 22/12 shards, clear-sky ring, and the deep-interior Tyrant
   silhouette call before the early return (`StormWallRenderer.java:171-181`,
   `:403-446`, `:647-754`, `:797-924`).
2. `StormInteriorFx` implements the shared gust clock, rotating/gust cadence rain,
   tiered managed god-fingers, ash devils, bloom tail, and the `WallProx` feeder
   (`StormInteriorFx.java:249-256`, `:456-552`, `:590-644`, `:725-726`).
3. `StormFxClient.tickExplosionDebris` has explicit implosion/quiet/expansion stages,
   reduced particle counts, eased ring radius, and tiered border-glitch bursts
   (`StormFxClient.java:339-398`); the wisp rise and roar volume consume the same gust
   (`:545-546`, `:954`).
4. The post shader has same-UV color/depth shimmer sampling and the 0.995→0.9998
   depth/height mist (`storm_interior.fsh:43-78`); all five uniforms are fed.
5. `storm_arc` is count 5/life 4/stretch 1.7, rain has stretch 2.2 plus wind, and
   god-fingers have rate 8/count 1/cap 8 (`storm_arc.json:4-5`, `:26`, `:45`;
   `storm_rain_sheet.json:45`, `:68-75`; `storm_godfinger.json:4-6`).

### Defects

- **HIGH — undefined rain envelope:**
  `src/main/resources/assets/eclipse/pinwheel/shaders/program/storm_interior.fsh:36`
  uses `smoothstep(1.0, 0.55, y)`. This is undefined, not a portable descending ramp,
  and it controls every procedural rain streak.
- **MEDIUM — reduced-FX gap in new heat shimmer:**
  `storm_interior.fsh:47-52` animates two noise fields at full amplitude whenever
  `WallProx` is nonzero. `StormInteriorFx.java:249-256` feeds the same proximity value
  regardless of reduced FX. Other new storm layers degrade, but this fullscreen
  refraction does not.

No claimed STORM-channel or geometry budget overage was found.

---

## RIFT — 8.5 / 10

### Claim verification

1. `RiftRenderer` has two guarded void-well fans, counter-scrolling lensing, two forkable
   arcs, and reduced mode collapsing to the center shell
   (`RiftRenderer.java:331-425`, `:441-503`, `:552-631`, `:687-732`).
2. The class recount is present and internally consistent at STRUCTURE 374 and
   PORTAL/BACKROOMS ≤374, below the 400-triangle cap
   (`RiftRenderer.java:60-64`).
3. `RiftFx.tickSurge` runs the 20-tick inhale, 6-tick materialize cadence, teardown,
   no-inhale reduced path, and 12-tick reduced bursts
   (`RiftFx.java:614-650`).
4. Backrooms style 2 is mapped as portal-like with the wax-gold palette
   (`RiftFx.java:104-106`, `:482-497`); portal discs share the seeded breath and the
   renderer contains ping/entry geometry (`RiftRenderer.java:364-429`, `:734-827`).
5. Emitter claims exist: spark trails, stronger motes vortex/attractor, camelCase
   point-attractor fields on materialize, size-Molang bloom on impact, and the retuned
   dust/debris/lightning physics (`rift_spark.json:54-72`,
   `portal_surface_motes.json:73-106`, `map_expand_materialize.json:51-65`,
   `impact_light.json:52-56`).

### Defects

- **MEDIUM — reduced entry path contradicts “iris fan only”:**
  reduced rendering correctly removes streamers/ping (`RiftRenderer.java:496-503`), but
  `RiftFx.tickEntryWatch` unconditionally spawns `rift_spark` and applies the local
  transition glitch pulse (`RiftFx.java:661-687`). There is no reduced-FX check, so the
  log's claimed fan-only reduced entry is false.
- **LOW — self-check particle arithmetic is stale/conservative:**
  the report claims materialize 36 and impact 9 live (`RIFT.md:330-332`), while the
  documented spawn formula and current JSON yield 5 waves×6 = 30 for
  `map_expand_materialize` (`map_expand_materialize.json:2-5`) and 2 waves×3 = 6 for
  `impact_light` (`impact_light.json:2-5`). This does not create an over-budget runtime;
  it does show that the claimed validator totals were not generated from the landed data.

---

## ALTAR — 6.5 / 10

### Claim verification

1. `AltarVeilSky` implements level write-in, two-axis glyph permutation, offering glow,
   synchronized beam spin, and tiered crown flare/echo
   (`AltarVeilSky.java:150-235`, `:267-291`, `:356-448`).
2. `AltarCeremonyFx` implements the 40-tick tiered lead, rising hum/indraw, shifted beats,
   two afterglows, and offering sky envelope (`AltarCeremonyFx.java:128-220`,
   `:267-284`).
3. `AltarIdleMotes` implements two helix placements per three spawns and separate L4
   sweeping halo-patch cadence, all behind its reduced/distance gate
   (`AltarIdleMotes.java:128-152`, `:179-198`, `:229-246`).
4. `OfferingSwallowFx` exits to fallback before reading visual tier under reduced FX,
   stores sampled glow color, notifies the sky on arrival, and renders a separate additive
   fan mesh (`OfferingSwallowFx.java:191-218`, `:301`, `:376-442`).
5. `SanctumOrbitals` applies the ±0.22/640-tick radius breath only to large rings
   (`SanctumOrbitals.java:118-125`, `:377-392`).

### Defects

- **CRITICAL — `altar_indraw` fails Veil's point-attractor codec:**
  `src/main/resources/assets/eclipse/quasar/emitters/altar_indraw.json:70-80` uses
  `local_position`, `strength_by_distance`, and `invert_distance_modifier`.
  Veil 4.3.0 requires `localPosition`, required `strengthByDistance`, and
  `invertDistanceModifier` for `veil:point_attractor`
  (`docs/plans_v3/eval/VFXPOLISH-2_emitters.md:15-20`). The same audit documents this
  exact key set as an emitter-decode failure (`:68`). Proven current siblings use the
  camelCase fields (`portal_surface_motes.json:89-99`,
  `map_expand_materialize.json:51-61`). Consequently the flagship 2-second anticipation
  spiral requested by the PLAN does not load.

The remaining ALTAR features are carefully implemented and under budget, but a dead
ceremony opener is a release-blocking precision miss.

---

## WAND — 7.0 / 10

### Claim verification

1. Blink sends the doubled departure tear, two delayed seam scars, and settle chirp
   (`WandPowers.java:411-447`); Phasenwelle schedules two post-band seams
   (`WandPhaseService.java:145-155`).
2. Rissschlag schedules the pre-snap shimmer and post-close seam from one `openTicks`
   source (`WandPowers.java:495-516`).
3. GLUT adds alpha-blended ash at midpoint/impact, launch and landing heat columns at
   corrected +1.4 Y, vanilla flamelets, and delayed smoke
   (`WandPowers.java:577-585`, `:662`; `WandTickService.java:281-294`, `:432-439`).
4. STERN adds delayed constellation residue and three pre-impact ground rings without
   moving damage timing (`WandPowers.java:694`, `:830-875`).
5. Heavy-cost cast flourish scaling exists at cost ≥30 (`WandPowers.java:335-366`).
6. Soulbind is staged at t0/t7/t18 with flash, cast hand, celebration, beacon, and
   `wand_awakening` on the flash tick (`WandPowers.java:215-242`).
7. All seven new emitter files are `loop:false`; their one-shot particle totals are small
   relative to 1,500 (for example, one seam is 2 waves×7 = 14 and one soulbind orbit is
   3 waves×9 = 27).

### Defects

- **HIGH — reduced-FX claim is false and the D11 layers generally do not degrade:**
  all server-dispatched Quasar cues reach the client through the default BURST path
  (`EclipsePayloads.java:149-157`). The reduced cap admits the first seven spawns
  (`FxBudget.java:67-83`). Blink has exactly seven Quasar spawns including its cast hand
  (`WandPowers.java:424-444`, `:346`), so “exactly at cap” means none is shed; if the cast
  straddles a fixed 20-tick budget window, even more headroom exists. This directly
  contradicts `WAND.md:35-37`, which says the two scars are dropped under reduced FX.
  Other under-cap D11 additions (soulbind orbits/flash, maw shimmer, ash, heat, and
  constellation) likewise run at full emitter count and animation under reduced FX;
  lowering the number of *allowed emitter starts* is not per-effect degradation.

Budget totals are otherwise within the documented spawn/live envelopes.

---

## UIFEEL — 8.5 / 10

### Claim verification

1. Bottom toasts have piecewise spring/settle/exit offsets and shared icon bounce, with
   all motion zeroed under reduced FX (`BottomToastQueue.java:168-229`);
   shard/tier icons consume the helper (`ShardGainToast.java:56`,
   `CollectionTierToast.java:69`).
2. `LevelUpOverlay` computes the four-step roll, fires impact at the resolve tick, and
   suppresses both roll and burst under reduced FX (`LevelUpOverlay.java:145-155`,
   `:188-190`, `:226-236`).
3. Awards instantiate zero-duration strips under reduced FX and explicitly gate needle
   motion, ring, confetti, flare, and podium burst
   (`AwardsOverlay.java:277-306`, `:408-420`, `:575-584`, `:619-632`);
   `RouletteStrip.speedFraction` is the quart derivative (`RouletteStrip.java:196-207`).
4. Reward materialization applies the 5-tick press/pop only to the live non-calm variant
   (`RewardMaterializeOverlay.java:237-266`).
5. The twelve emitter retunes are present: two-tone unlock/roulette, two-spike danger,
   long soft follow/glide trails, vortex updraft, and drifting randomized cutscene veil
   (for example `unlock_burst.json:62-105`, `glyph_danger.json:58-105`,
   `glyph_follow.json:54-124`, `cutscene_veil.json:34-99`).

### Defects

- **MEDIUM — danger-glyph reduced-FX/photosensitivity gap:**
  the new two-spike `glyph_danger` envelope remains a full-rate `loop:true` emitter
  (`glyph_danger.json:2-5`, `:78-105`). `GestureGlyphFx` only documents tier-0 dropping
  and continuously calls `ensureAttached` with no reduced guard
  (`GestureGlyphFx.java:20-28`, `:82-110`). `ensureAttached` charges only creation and
  treats an existing loop as free (`QuasarSpawner.java:149-166`), so toggling reduced FX
  at tier 1 neither stops nor thins the live loop. The UI motion is carefully gated; this
  newly sharpened world-space repeated flash behavior is not.

No UIFEEL JSON schema, expected-particle-budget, or Java precision defect was otherwise
found.

---

## Three weakest effects versus their own ambition

1. **RIFT structure-slam “ground shock-ring decal”.** The PLAN asks for a ground decal,
   but the team explicitly defers the renderer and leaves only particles plus the
   screen-space shockwave (`RIFT.md:249-265`, `:336-341`). A dust hemisphere cannot create
   the crisp ground-contact graphic promised by “decal”.
2. **STERN `stern_constellation`.** It emits five independently drifting points and gives
   each point its own trail (`stern_constellation.json:2-27`, `:52-74`). Trails record each
   particle's history; they do not connect different stars. The result can read as five
   tiny comets, not a stable connect-the-dots star map.
3. **ALTAR L4 halo ground patch.** `altar_halo_patch` uses camera-facing billboards with
   random initial directions/rotations (`altar_halo_patch.json:21-45`), spawned at a fixed
   hover Y (`AltarIdleMotes.java:179-198`). That is a faint mote cluster near the ground,
   not a ground-projected light pool aligned to the sweeping sky beam; it is the weakest
   translation of a team's own spatial ambition.

## Release recommendation

Block the wave on the ALTAR codec keys and the four GLSL undefined-behavior sites
(GRADE sun rim/edge, GLITCH center angle, LIMBO warp fade, STORM rain envelope). Then
close the explicit reduced-FX gaps in LIMBO, STORM, RIFT entry, WAND D11, and UIFEEL
danger glyph before calling the polish wave precision-complete.
