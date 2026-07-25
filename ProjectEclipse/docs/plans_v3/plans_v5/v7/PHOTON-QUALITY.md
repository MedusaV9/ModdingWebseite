# PHOTON-QUALITY — v7 quality audit of the 68 shipped `.fx` assets

Worker: PHOTON-DEEP-3 (of 3), 2026-07. Read-only pass; no gradle, no git.

**Method.** All 68 `src/main/resources/assets/eclipse/fx/**/*.fx` (58 top-level + 10
`boss/`) were parsed with `tools/photon/fxlib.py` (`read_fx_file`, same NBT reader as
`fxlib.py dump`) and every emitter's main block, emission, shape, renderer/materials,
toggle modules and every NumberFunction was extracted and graded against
`photon/FX_FORMAT.md` (§3 schema, §9 perf, §10 golden rules) and the five spec docs
(`photon/IDEAS-{boss,player,mobs,events,world}.md`). "Lazy linear" curve detection:
a `curve`/`random_curve` is flagged when **all** Bézier segments have control points
collinear with their endpoints (tolerance 0.02 — this catches the `fxlib`
`SEG_LINEAR_UP`/`SEG_LINEAR_DOWN` presets verbatim). Cross-references: the 65 Quasar
emitters (`assets/eclipse/quasar/emitters/`), the shipped registry rows
(`veilfx/PhotonFxRegistry` + `BossPhotonFxRows` / `HeraldFerrymanFxRows` /
`MobPhotonFxRows` / `PlayerFxPhotonRows` / `AltarPhotonFxRows` / `GlideTrailFx`), and
the v7 palette tokens (`v7/FX-STYLE-GUIDE.md` §1).

---

## §1 Aggregate scorecard (the good news first)

| Metric | Value | Verdict |
|---|---|---|
| Files / emitters | 68 files, 148 emitters (avg 2.18/file) | healthy |
| Cull boxes on loops | **48 of 49** looping emitters have `renderer.cull` | excellent — 1 violation (`ghost_wisp` "core") |
| `maxParticles` hygiene | zero emitters at the 2000 default; range 1–1200, all deliberate (1200 = `end_void_wisps`, GPU-instanced by spec) | excellent |
| Duration/lifetime coherence | zero one-shots with bursts past `duration`; zero loops with `prewarm > duration` (`altar_corona_idle` is exactly `prewarm == duration`, per spec) | excellent |
| Blend/sort discipline | additive⇒`NONE`, alpha⇒`DISTANCE` respected in 146/148; 2 violations (§2 rows 14–15) | good |
| HDR placement | 100/150 materials carry `hdr > 0`; dust/fog/petal/static materials correctly at 0; deliberate no-HDR reads (gazer thread, dread aura, lantern models) honored | good |
| Capability showcases | REVERSE_SUB/MAX passes, Model+mesh renderers, `function` shapes, GPU-instancing flags, ara physics — all present and faithful where specced | good |
| **Eased curves** | **70 of 157 curves (45 %) are lazy piecewise-linear** — the `SEG_LINEAR_UP/DOWN` presets shipped verbatim where the specs authored ease-out/overshoot segments | **the systemic weakness** |
| Single-emitter files | 21 of 68 (most are spec'd sub-emitter children or bare ribbons; ~5 are under-delivered compositions) | mixed |
| `.fxproj` sources | **zero** committed (binary-diff law, FX_FORMAT.md §7 / INTEGRATION.md §6) | violation, repo-wide |

The fleet is **structurally excellent and parametrically lazy**: implementers nailed the
hard things (cull boxes, budgets, blend equations, sub-emitter chains, GPU flags) and
skimped on the easy-but-visible thing — curve easing. 45 % linear is the single biggest
quality lever for v7.

---

## §2 The weakest 15

Grades: composition (vs spec'd object list), curves (eased vs linear), fidelity
(spec'd hero features delivered), hygiene (cull/sort/blend/budget). Ordered weakest
first. "spec" cites the IDEAS doc + concept #.

| # | `.fx` | em | Grade | What's wrong | Spec (concept) |
|---|---|---|---|---|---|
| 1 | `portal_loop_xbox` | 2 | **D** | ZERO curves in the file. Spec's hero features missing: `crt_flicker` was spec'd as `random_curve` irregular brightness + 2×2 `uvAnimation` frame jitter — shipped as a plain constant-alpha glow quad. `era_pixels` uses `circle.png`+pixelArt (round dot pixelated) instead of chunky squares (`square_4x4.png` exists!). The era read is gone. | events #5b |
| 2 | `wand_idle_stern` | 1 | **D+** | Identity loop reads generic: spec'd 4-point-star sprite + 2×2 `uvAnimation` flipbook twinkle — shipped `circle.png`, no flipbook. Constellation-line trails present but `ratio 0.3` hairlines off round dots ≠ star map. | player #6 |
| 3 | `portal_loop_backrooms` | 3 | **C−** | The concept's signature — `random_curve` alpha with long dark gaps + double-blink clusters ("dying fluorescent") on `tube_flicker` — is absent (no curve at all on the tube; only a linear size curve on `haze`). Composition (tube+haze+moth_motes) ✓. | events #5c |
| 4 | `ghost_wisp` | 2 | **C−** | The repo's **only loop without a cull box** (`core`, looping, no `renderer.cull`). Spec'd optional 20 % hairline trails dropped. Otherwise fine. | player #9 |
| 5 | `structure_slam_mushroom` | 3 | **C−** | **8/8 curves linear** — the decelerating-column and cap-bloom easing IS the mushroom read; shipped as straight ramps, so the column rises and grows mechanically. Composition (column/cap_roll/Model dirt clods + collision sub→`slam_dust_puff`) ✓. | events #3 |
| 6 | `boss_intro_shockwave` | 6 | **C** | Best composition in the fleet (ring + dust + 4 raycast beams under a pivot) but **6/6 curves linear**, including the ring `sizeOverLifetime` that spec authored as ease-out crest. The flagship celebration pops like a metronome. | mobs #1 |
| 7 | `boss/ferry_kneel_corona` | 2 | **C** | `invuln_shell`'s spec'd 2-segment slow alpha-pulse curve missing (no curve in file); spec'd `dome_faint.png` never authored → smoke.png stand-in. The "inert dome" reads as a static smoke blob. | boss #9 |
| 8 | `wand_idle_riss` | 2 | **C** | `squares` emitter uses `circle.png`+pixelArt instead of hard squares (`square_4x4.png` shipped for exactly this); spec'd scanline-ribbon `thicknessOverTime` flicker curve absent (1 curve total). Glitch identity diluted. | player #6 |
| 9 | `riss_glitch_pop` | 1 | **C** | Sub-emitter child: spec'd "hard additive squares, pixelArt bits 4" — shipped `circle.png`+pixelArt, zero curves. Single emitter is per-spec; the texture choice isn't. | player #4 |
| 10 | `expansion_rift_glow` | 2 | **C** | Flagship "Event-Horizon Ring": **4/4 curves linear** (ribbon `thicknessOverLength` taper + infall `sizeOverLifetime`). Orbiters+ara+streaks composition ✓; the accretion disc just tapers like a ruler. | world #2 |
| 11 | `rift_piece_flash` | 3 | **C** | 3/3 linear where the spec literally wrote the eased pop segments out (`[0,0.55, 0.1,1, 0.6,0.8, 1,0.2]`). The muzzle flash fires 6×/delivery window — the mechanical pop is very visible. | world #3 |
| 12 | `end_void_wisps` | 1 | **C** | GPU-instancing showcase flags ✓ (`useGPUInstance`, both parallel paths, cull ±110, maxParticles 1200) but all 3 envelope curves linear — 1200 wisps breathing on straight ramps. Single emitter is per-spec. | world #6b |
| 13 | `award_star_glint` | 1 | **C** | Collision-child spark: 3/3 linear, `circle.png`. 8 particles, so small blast radius — but it spawns on every star bounce, and the linear shrink reads as popping out of existence. | mobs #3 |
| 14 | `award_star_shower` | 2 | **C** | `star_fall`: alpha-blended `block_atlas` Model stars with `vertexSortingMode: NONE` **and** `depthMask: 0b` — translucent models with no ordering (z-shimmer when stars overlap). Bursts/physics/sub-chain otherwise exactly per spec. | mobs #3 |
| 15 | `boss/fog_debris_puff` | 1 | **C** | Sub-emitter child: 3/3 linear (spec'd growing `sizeOverLifetime` to 2×), alpha fog ✓ no-HDR ✓. Minor alone, but it stamps on every debris bounce of the tyrant death implosion. | boss #2 |

**Runner-ups** (fix opportunistically): `sentinel_alert` (3/3 linear),
`stern_komet_fall` (the descent's spec'd ease-in Y curve is linear — the comet falls at
constant speed), `glide_trail` + `hound_dash_trail` + `sky_launch_contrail` +
`supply_drop_contrail` (linear ribbon tapers), `credits_strike_beam` (linear beam-width
collapse), `intro_burst_ring` / `boss/tyrant_blind_burst` / `wand_soulbind_flash` /
`glut_sprung_crater` / `stern_komet_impact` (3 linear each, mixed with eased),
`boss/warden_eye_laser` (beam width flicker→commit curve shipped linear).

**Exemplary files** (steal from these): `credits_confetti_burst` (15/15 eased curves, 5
Model shard emitters + glint, parallelRendering), `boss/tyrant_death_implosion` (7/7
eased, radial in-suck curve, collision sub-chain), `theft_soul_arrive` (6/6 eased),
`glut_sprung_crater` composition, `warden_glitch_orbit` (REVERSE_SUB + ADD dual-pass +
MAX-blend veil, exactly per spec), `glitch_pop` (REVERSE_SUB `square_4x4` + ADD
`static_4x4` shared-flipbook trick), `altar_levelup` (Model amethyst shards +
TRAIL sparks + beam spear), `offering_swallow_soul` / `sky_launch_charge` (function-
shape helixes + ara trails), `wanderer_static_shroud` (shade-1b lightmap-sync concept
delivered faithfully).

---

## §3 Gap backlog — spec'd concepts never implemented (= the v7 new-effects queue)

The 5 IDEAS docs rank 50 concepts (+1 below-cut). 38 shipped at least their primary
asset (68 files incl. children/variants). **13 assets across 12 concepts never landed:**

| Missing asset | Doc / rank | What it was | Why it likely stalled | v7 priority |
|---|---|---|---|---|
| `boss/tyrant_fog_arms` | boss #10 | mesh-shape fog tendrils precessing around the Fog Tyrant P3 | needs `eclipse:item/fog_tendril` model + entity executor; ranked last by its own doc | LOW |
| `riss_maw_snap` | player #4 (sub-piece) | the snap-shut beat: white-cyan HDR slice + 8 `removedWhenCollided` shards, `setDelay(openTicks)` | the maw shipped without its punchline | **HIGH** — cheap, completes an L3 power |
| `revenant_fog_ribbons` | mobs #4c | Fog Revenant hem-wisp loop with tear-off TRAIL streamers | loop-tier attach manager scope | MED |
| `glitch_drip` | mobs #5b | sparse pixelArt corruption drip loop for glitched family | loop-tier | MED |
| `shadow_bolt_impact` | mobs #6b | REVERSE_SUB dark flash + violet shards + 4-beam micro-cross on bolt hit | one-shot, seam exists (`onHit*`) — easy win | **HIGH** |
| `deckhand_soul_flame` | mobs below-cut | 8 hooded rowers' soul-candle hats + hostile flare | deliberately below the cut | LOW |
| `intro_storm_wall` | events #7 | looping vortex-wall arcs (3 sputtering raycast beams + orbiting embers), destroyed on BURST | needs `spawnLooping`/`stop` handle | MED |
| `intro_sunrise_rays` | events #8 | 4 staggered god-ray ara ribbons + rim motes over the SUNRISE beat | plain one-shot, **no new machinery** — unexplained gap | **HIGH** — once-per-world flagship |
| `credits_contrail` | events #9b | thin gold-violet contrails on 8 nearest credits flyers | entity-attach heuristic | LOW-MED |
| `era_dust_motes` | events #10 | GPU-instanced pixelArt ambient in xbox tutorial dims | explicitly law-flagged; needs sign-off | HOLD |
| `end_crack_bleed` | world #6a | splayed HDR beam fan + seam embers per crack-race step (Option B) | shipped Option A (crack race reuses `expansion_rift_glow`) — thematically off per its own spec | MED |
| `storm_wall_veins` | world #8a | 4-beam jagged lightning vein chains on the fog-storm shell (5t, `random_curve` flicker widths) | `storm_crown_halo` half shipped; veins didn't | **HIGH** — the readable half of the pair |
| `wizard_hearth` | world #10 | chimney sparks + standalone `trail_emitter` smoke wisp + window motes | loop window; also the fleet's only planned `trail_emitter` use — capability still unexercised | LOW-MED |
| *(textures)* `dome_faint.png`, `fog_puff.png` | boss cross-cutting | shell-dome + soft fog puff textures | never authored; `smoke.png` stood in (§2 row 7) | with riss/ferry fixes |

Suggested backlog order: `riss_maw_snap` → `shadow_bolt_impact` → `intro_sunrise_rays`
→ `storm_wall_veins` (all one-shots on existing seams, zero new bridge machinery) →
`end_crack_bleed` → loop-tier trio (`revenant_fog_ribbons`, `glitch_drip`,
`intro_storm_wall`) → the rest.

---

## §4 Texture audit — the worker-generated particle PNGs

Photon workers generated **7** textures programmatically (stdlib PNG writers embedded in
the generator scripts); all are white-RGB alpha-mask sheets (correct — tint comes from
`startColor`/gradients at runtime). The three from `tools/photon/mobs_fx.py`
(`static_4x4` et al.) plus the four from the boss generators:

| Texture | Size (px) | Generator | Used by | Verdict |
|---|---|---|---|---|
| `static_4x4.png` | 64×64 (4×4 grid → 16px frames) | `mobs_fx.py` | `glitch_pop` pass 2, `wanderer_static_shroud` (shared, per spec) | ✓ right size for ≤0.3-block flecks; 16 genuinely distinct noise frames (4.9 KB, high entropy) |
| `square_4x4.png` | 64×64 (16 identical soft squares) | `mobs_fx.py` | `glitch_pop` REVERSE_SUB pass | ✓ clever: identical frames let both passes share one `uvAnimation` module without divergence; 100 % alpha coverage is intentional (whole quad subtracts) |
| `petal_soft.png` | 32×32 single petal | `mobs_fx.py` | `sentinel_alert`, `sentinel_petal_orbit` | ✓ adequate for 0.1–0.3-block petals; 36 % alpha coverage, soft edge |
| `beam_core.png` | 64×256 (4-frame `[1,4]` strip) | `boss_b_fx.py` | `warden_eye_laser`, `gazer_gaze_beam`, `boss_intro_shockwave` beams | ✓ per spec (4-frame scroll) |
| `glitch_shard.png` | 128×128 (2×2 → 64px frames) | `boss_b_fx.py` | `warden_glitch_orbit` dual-pass | ✓ hard-edged shards, biggest frames in the set — right call for the rim-discard trick |
| `noise_strip.png` | 64×64 | `boss_b_fx.py` | `warden_glitch_orbit` MAX-blend veil | ✓ |
| `ring_soft.png` | 64×64 | `fx_boss_herald_ferryman.py` | `roar_shockwave` ground ring | ⚠ **undersized**: the roar ring scales to r≈30 blocks — 64 px stretched across 60 blocks will band/blur up close. Regenerate at 256×256 (one-line change in the generator). Same review for photon-bundled `ring.png` uses on big rings (`intro_burst_ring` at 2×VORTEX_RADIUS). |

(`purple_wisp.png` / `wisp_white.png` are 8×8 pre-photon art from
`tools/art/gen_wisp_white.py` — out of scope.) Gaps: `dome_faint.png`, `fog_puff.png`
spec'd but never generated (§3).

---

## §5 The v7 QUALITY BAR for `.fx`

### 5.1 Author checklist (gate for every new/revised hero asset)

1. **≥ 2 emitters per hero effect.** Layered reads (core + support + accent) are the
   house style; single-emitter files are legal ONLY for sub-emitter children
   (`*_puff`, `*_glint`, `*_sparkle`, `*_pop`) and bare entity-attached ribbons where
   the spec says one object.
2. **Eased curves, always.** Every `curve`/`random_curve` on a size/alpha/width/velocity
   envelope must contain at least one genuinely curved segment (control points off the
   chord). The `SEG_LINEAR_UP`/`SEG_LINEAR_DOWN` presets are for prototyping, not
   shipping. Sanctioned exceptions: `uvAnimation.frameOverTime` linear scans and
   arc-sweep inputs where the spec says linear. House segments to reuse:
   `SEG_POP_SHRINK` `[0,0.66, 0.1,1, 0.9,0.2, 1,0]`, ease-out crest
   `[0,0.04, 0.15,0.9, 0.6,1, 1,1]`, overshoot-settle (iris)
   `[0,0.2, 0.1,1.15, 0.5,0.95, 1,1]`, flicker→commit `[0,0.15, 0.55,0.35, 0.9,1, 1,1]`.
3. **Cull box on every loop** (golden rule, FX_FORMAT §10) and on any one-shot that
   lives > 20t or spans > 8 blocks. Box must actually contain the effect's travel.
4. **LOD-consciousness.** Explicit `maxParticles` ≤ 512 (above that, `useGPUInstance:
   1b` + `parallelUpdate/parallelRendering: 1b` and no physics/level access); collision
   physics on ≤ 80 particles per file and never on loops that outlive a window; additive
   ⇒ `vertexSortingMode: NONE`; alpha ⇒ `DISTANCE`; translucent Model particles need
   `depthMask: 1b` or `DISTANCE`; `prewarm ≤ duration`; sub-emitter child files ≤ 8
   particles (each collision stamp deep-copies a full runtime, FX_FORMAT §9).
5. **Palette tokens.** `startColor`/gradients pull from `v7/FX-STYLE-GUIDE.md` §1
   families (`SAC_*`, `COR_*`, `GLI_*`, `ERA_*`, `STM_*`), with the token table's HDR
   column as the `hdr` baseline. Corruption never gets gold; dust/fog/occluders never
   get HDR; ≤ 4.0 HDR ceiling pending the Iris pair test.
6. **Texture intent.** Use the authored identity textures (`square_4x4`, `static_4x4`,
   `glitch_shard`, `petal_soft`, `ring_soft`, `beam_core`) where the read is identity;
   `photon:textures/particle/circle.png` is for generic sparks/motes only. New textures:
   white-RGB alpha-mask, frame ≥ 32 px at expected on-screen size (≥ 256 px for
   ground rings that scale past r=10).
7. **Coherence.** `looping: 0b` + burst = one-shot; `looping: 1b` + rate = ambient
   (WINDOWED rows only); particle lifetimes and burst times inside the duration window
   for one-shots; `simulationSpace` World for debris, Local for followers.
8. **Ship the `.fxproj` beside the `.fx`** (binary-diff law) — currently 0/68 comply.

### 5.2 Lint rule set for `fxlib validate` (implementable now)

`validate_file` today returns structural errors only; add a warnings channel
(`validate <f.fx> --lint`) with these rules — all verified implementable against the
data `read_fx_file` already exposes (this audit implemented every check below):

| Rule id | Severity | Check |
|---|---|---|
| `LINT-CULL-LOOP` | error | `looping: 1b` particle/trail emitter without `renderer.cull._enable: 1b` |
| `LINT-LINEAR-CURVE` | warn | `curve`/`random_curve` whose segments are ALL chord-collinear (tol 0.02); suppress for `uvAnimation.frameOverTime` and `shape.*` paths |
| `LINT-MAXP-DEFAULT` | error | `maxParticles` absent or == 2000 (the unset default) |
| `LINT-MAXP-CPU` | warn | `maxParticles > 512` without `useGPUInstance: 1b` |
| `LINT-GPU-PHYSICS` | error | `parallelUpdate: 1b` or `useGPUInstance` together with enabled `physics` (collision needs level access) |
| `LINT-ALPHA-NOSORT` | warn | any material with `dstColorFactor: ONE_MINUS_SRC_ALPHA` while `vertexSortingMode: NONE` and `depthMask: 0b` |
| `LINT-HDR-DUST` | warn | `hdr > 0` on an alpha-blended material with `shade: 1b` (world-lit dust must not bloom) |
| `LINT-HDR-CEILING` | warn | any `hdr` channel > 4.0 |
| `LINT-PREWARM` | error | `prewarm > duration` |
| `LINT-BURST-WINDOW` | warn | one-shot (`looping: 0b`) with `burst.time + (cycles−1)·interval ≥ duration` |
| `LINT-SUBEM-RESOLVE` | error | `subEmitters.emitters[].fxLocation` (or trails child refs) not resolvable to a file under `FX_ASSETS_DIR` (fail-soft at runtime = silent no-op, so catch at commit time) |
| `LINT-SUBEM-FAT` | warn | a file referenced as a sub-emitter child whose burst count sum > 8 |
| `LINT-SINGLE-EMITTER` | info | 1 renderable object and the name doesn't match the child-suffix allowlist (`_puff/_glint/_sparkle/_pop/_trail/_ribbon`) |
| `LINT-PALETTE` | info | `startColor`/gradient RGB stops further than a set distance from every FX-STYLE-GUIDE §1 token (advisory only — gradients legitimately pass through off-token mids) |
| `LINT-FXPROJ` | warn | no sibling `.fxproj` next to the `.fx` |

Wire `selfcheck` to run the lint set over `FX_ASSETS_DIR` with a committed baseline
(current violations grandfathered, count may only go down).

---

## §6 Photon-vs-Quasar overlaps — retirement list

`PhotonFxRegistry.dispatch` already implements safe retirement: a `Mode.REPLACE` row
spawns the Quasar leg **only when the Photon leg did not play** (photon-less clients,
missing asset, `reducedFx`). "Retire" below = flip the row LAYER→REPLACE (or add the
row), keeping the Quasar emitter as automatic fallback. All shipped rows today are
LAYER.

**Retire (photon strictly supersedes; running both = double-vision):**

| Quasar emitter | Superior Photon asset | Why photon wins | Note |
|---|---|---|---|
| `glide_trail` | `glide_trail` (2 ara wingtip ribbons + sparkles) | physics ribbons vs point trail; IDEAS-player #10 itself says "two trails = mud … honest recommendation is REPLACE" | fix the linear tapers (§2 runner-up) when flipping |
| `wand_soulbind_flash` | `wand_soulbind_flash` (4-emitter HDR flash) | same beat, same tick, same shape — the double flash reads as stutter; photon adds bloom + afterglow | keep the Quasar orbit emitters (`wand_soulbind_orbit`) — different beat |
| `ferry_kneel_corona` | `boss/ferry_kneel_corona` | 1:1 name/read overlap; photon adds the invuln dome | fix §2 row 7 first |
| `ferry_lantern_swarm` | `boss/ferry_lantern_swarm` | actual soul-lantern Model particles supersede the mote swarm; the photon file's `soul_leak` emitter already duplicates the quasar mote read | |
| `stern_komet_core` | `stern_komet_fall` | the quasar leg is the teleport-fake descent (2 re-spawns); the photon head + ara ribbon is the real fall — both at once shows two comet heads | keep `stern_funke_fall` (LAYER — ground sparkle is complementary); ease the descent curve first |
| `riss_schlag_maw` (emitter only) | `riss_schlag_maw` | both draw the inhale; photon adds the Death-chain pops | keep `riss_maw_shimmer` + `riss_seam_scar` as LAYER dressing; ship `riss_maw_snap` (§3) with the flip |

**Evaluate after quality fixes (overlap real, photon not yet clearly superior):**

| Quasar | Photon | Blocker |
|---|---|---|
| `glut_sprung_crater` | `glut_sprung_crater` | photon version is strong (bounce physics + 2 sub-chains) but the launch/landing double-anchor choreography needs an in-game pass before dropping the quasar crater |
| `structure_slam_dust` | `structure_slam_mushroom` + `slam_dust_puff` | mushroom is weakest-15 row 5 — retire only after its curves are eased |
| `offering_swallow` | `offering_swallow_soul` | partial overlap (item trail vs inhale helix); MAX_FLIGHTS=4 stacking must be verified with `allowMulti(true)` first |

**Considered and kept LAYER (deliberate double per D12 "Photon is garnish" law):**
`altar_levelup_ring` under `altar_levelup`; `boss_slam` under `boss/roar_shockwave` and
`boss/tyrant_blind_burst`; `growth_dust_wall` pulse curtains under
`growth_front_ribbon` (spec: curtains read as reinforcements of the wall);
`map_expand_materialize` under `rift_piece_flash`; `heart_burst` under the
`theft_soul_*` arc (burst vs transfer — complementary); `limbo_motes` family under the
kneel/lantern boss rows (fallback-only shapes).

---

## §7 Fix order (one sentence)

Ease the 70 linear curves starting with the weakest-15 (a `fxlib` batch pass over the
generator scripts, since every file is programmatically authored), add the `ghost_wisp`
cull box + the two sort/depth fixes, regenerate `ring_soft.png` at 256², land the lint
rules with a grandfathered baseline, then burn the HIGH-priority gap backlog
(`riss_maw_snap`, `shadow_bolt_impact`, `intro_sunrise_rays`, `storm_wall_veins`)
before flipping the six retirement rows to REPLACE.
