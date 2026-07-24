# W4-NETHER wiring — 1:1 nether disc, roof shell, glitch-drift transfer (IDEA-17)

Implements IDEA-17 top ideas **1 (1:1 disc + roof shell), 2 (glitch-drift transfer),
3 (ceiling stalactite forests)** plus two more terrain-interest ideas:
**4 (glowstone chandelier fields)** and **5 (lava-fall curtains at sector seams)**.

## Files touched

| File | Change |
|---|---|
| `worldgen/FrozenParams.java` | `DEFAULT_NETHER_RADII` → `{0, 150, 280, 440}` (was `{0, 64, 110, 150}`) |
| `core/config/EclipseConfig.java` | `defaultStages()` nether entries → radii 150/280/440 (must stay in lockstep with the FrozenParams constant — the freeze file is built from stages.json) |
| `worldgen/DiscProfile.java` | `NETHER.lensNormRadius` 160 → **480** (mirrors the overworld lens constant) |
| `data/minecraft/dimension_type/the_nether.json` | `coordinate_scale` 8.0 → **1.0** (vanilla map/compass/F3 parity with the 1:1 disc) |
| `worldgen/DiscMapDefaults.java` | `netherDefaults()` rescale: moat r=190 hw=6 (bridges 0°/180°, hw 4), `breach_arrival` → **(85, 85)** r=4 (same x/z as the overworld `eclipse:nether_breach` landmark — the 1:1 rule), `bastion_remnant` → (−70, −214) r=24, `hanging_court` → (194, −141) r=20 |
| `worldgen/DiscTerrainFunction.java` | nether roof shell + stalactite forests + seam-curtain flag; new `DiscColumn` fields `ceilingBottomY/ceilingBodyY/ceilingTopY/seamCurtain`; hash salts 29/30 |
| `worldgen/nether/BreachBuilder.java` | ceiling bore in `chimneyWrites()` (air d²≤12 from chimney top to world top + blackstone collar ring d²≤18); fallback arrival 85/85 |
| `worldgen/nether/BreachTransferService.java` | glitch-drift rewrite (capture, drift physics, 1:1 handoff — the 8:1 divide is deleted, tractor ascent, ceiling pull-through, aborts); legacy paths kept for creative |
| `worldgen/nether/NetherCeilingDecor.java` | **new** — chandelier fields via the `DiscGenPipeline.ExtraDecor` seam |
| `network/S2CBreachPayload.java` | append-only `Phase` additions: `DRIFT_DOWN`, `DRIFT_UP`, `DRIFT_END` (the read-side ordinal clamp is dynamic — `phases.length − 1` — so appends are wire-safe) |
| `network/breach/BreachClientFx.java` | drift FX: `EclipseFxState.startTransitionGlitch` PULSES (12 t) at capture/seams, shake, `SOUL_ESCAPE` whoosh, `RESPAWN_ANCHOR_DEPLETE` arrival thud on `DRIFT_END` |

## Constants chosen (all deterministic, mapSeed-keyed)

### Roof shell + terrain (DiscTerrainFunction)
- `CEILING_CENTER_BOTTOM_Y = 232`, `CEILING_RIM_BOTTOM_Y = 200`: mirrored lens — the
  cavern is tallest over the center; the roof thins with the SAME `edge` rim taper as
  the floor, then crumbles inside the rim band. Top 3 layers of the shell are bedrock
  (nobody escapes over the roof); body is the existing strata palette (blackstone).
- Stalactite forests: floor fringe formula on the offset domain
  (`x/22 + 1024, z/22 + 1024`, high-freq at `±1536`), needle cap
  `CEILING_NEEDLE_MAX = 16`, forest cell mask `hash01(H_CEILING, x>>4, z>>4) < 0.35`
  (`CEILING_FOREST_CELL_CHANCE`). Fringe palette gives glowing tips for free.
- Seam curtains: `sectorBlendAt` gate `t > 0.42` (`SEAM_CURTAIN_MIN_T`), core bowl at
  `t > 0.47` (`SEAM_CORE_MIN_T`), per-24-block-run segment gate
  `hash01(H_SEAM, seamIndex, r/24) < 0.5`, ONE ceiling lava source per 5 radial blocks
  (`seamCurtain == 3`), suppressed near the moat (±4 blocks / ±4° bridges) and inside
  landmark clearance + 24.
- Salts: hash **29** (`H_CEILING`), hash **30** (`H_SEAM`) — registered in
  `P1-W1.2_wiring.md` (noise 29–32 are W1.4's; families key differently).

### Glitch-drift (BreachTransferService)
- Descent: `DRIFT_SPEED = −0.10`/t in shaft + bore, `DRIFT_CAVERN_SPEED = −0.34`
  eased across the open cavern (`DRIFT_EASE = 0.02`), `DRIFT_LANDING_SPEED = −0.15`
  final approach → whole ride ≈ 35–40 s without a boring minute-long float.
- Stutter-skips: per-7-tick window (`DRIFT_STUTTER_WINDOW`), chance 0.25, one-tick
  Y-hold + `±0.12` lateral jolt; hash = `mapSeed ^ playerUUID ^ window` (deterministic,
  per conventions).
- Capture at `lipY − 4`; dimension seam at `lipY − 36` → nether world-top + 2 (through
  the bore); ascent tractor `+0.18`/t (user constant) from the soul chimney to
  `ceilingBottomY − 2` (deliberately the NEEDLE-TIP height, not the lens base — a
  stalactite over the updraft column must not block the rise) → overworld chimney at
  `lipY − 36` → rim arc onto the return pad.
- Aborts: escape radius 10 (descent) / 6 (ascent), timeout 900 t → release with 30 s
  Slow Falling or return-pad fallback. Players only (dismounted at capture); creative
  keeps the legacy instant paths. `DRIFTING` map lifecycle mirrors `TRANSFER_COOLDOWN`
  (logout + server stop cleanup).

### Chandeliers (NetherCeilingDecor)
- Cell 24, chance 0.30, wastes-wedge full density / 50% elsewhere; 2–5 chain links,
  glowstone diamond tier + diagonal drops, 1-in-8 shroomlight core; `setIfAir` only;
  class-local salts `0x4E43`/`0x4E44` (NetherUndersideDecor convention). Column-local
  writes — chandeliers crossing chunk borders assemble without cross-chunk access.

## Border confirmation (asked in the brief)

`border/SoftBorder` needs **no change**: the nether ring radius derives per-dimension
from the frozen `StageRadii` table (`stageOuterRadius` → `StageRadii.radius(NETHER,
stage)`); there was never an 8x mapping in the border. With the 1:1 radii the nether
ring simply becomes 150/280/440 + borderOffset. The only 8:1 divide in the codebase was
in `BreachTransferService.descend()` — deleted. The breach-local hard clamp
(`clampNetherBorder`, stage radius + 16) reads the same table and also just works.

## Per-save freeze awareness (IMPORTANT for dev worlds)

`DEFAULT_NETHER_RADII`/`stages.json` defaults freeze into `world/<save>/eclipse/
worldgen.json` at save creation — **existing saves keep the old 150-block nether**.
The lens constant (480) and the roof shell are code, so a pre-change save would get a
mismatched rim. **Reset dev worlds** (or `/eclipse-worldgen refreeze stages` + a nether
sweep) after pulling this change.

## Idempotence

`BreachBuilder.openNow` replays the full write set including the ceiling bore — repair
replays re-carve the bore through any regenerated roof. All bore/collar writes are
absolute block states (no read-modify-write), so replay order is irrelevant.

## Integrator asks

1. **Sound**: the arrival thud currently reuses `RESPAWN_ANCHOR_DEPLETE` (client) +
   `SOUL_ESCAPE` (server). If the sound wave has budget, a dedicated
   `eclipse:breach.drift_thud` event with more sub-bass would land better — drop-in
   replacement in `BreachClientFx.handle(DRIFT_END)`.
2. **P2 FX**: `DRIFT_*` payloads carry the pulse hold in `radius`; if P2 wants longer
   cinematic pulses, tune `DRIFT_PULSE_HOLD_TICKS` (server) — the client honors whatever
   arrives.
3. W1.4's wiring table still lists the OLD nether landmark positions (breach_arrival
   48/35 etc.) — superseded by `DiscMapDefaults.netherDefaults()` (85/85 etc. above).

## Risks

- **Ring-growth × roof shell (the big one)**: stage sweeps now rewrite full 0–255
  columns instead of ~0–150 — the per-column write count roughly doubles (roof body +
  bedrock cap + stalactites). The sweep is budgeted (`BudgetedBlockWriter`), so this
  costs sweep TIME, not tick health; the stage-2/3 nether sweeps will take visibly
  longer. Interior roof output is keyed to the FINAL `lensNormRadius` only (mirrors the
  floor-lens rule), and the taper is `edge`-gated inside the same rim band the sweep
  already rewrites — so ring replay reproduces the roof byte-identically. Verified
  stage-independent for the interior by construction; watch sweep duration on real
  saves.
- **Seam-curtain flow updates**: only ONE lava source per curtain column and one pour
  per 5 radial blocks bounds vanilla flow spread, but a stage sweep materializing a
  whole seam at once will trigger a burst of flow updates on the seam chunks. If a
  sweep hitches, halve the `H_SEAM` gate (0.5 → 0.25) first.
- **Old clients** (wire compat): `DRIFT_*` ordinals clamp to `SETTLED` on a client
  running the pre-change enum — harmless (no crash, no FX). Append-only rule is now
  documented on the payload.
- **F3/maps**: `coordinate_scale 1.0` changes vanilla nether/overworld coordinate
  conversion for any external tooling that assumed 8:1.

## Verification performed (no gradle, per rules)

- `javac --release 21` (sandbox args-file pattern, moddev merged jar + veil/geckolib/
  voicechat classpath): all 10 touched files compile clean from source (0 errors; the
  only warnings are the pre-existing deprecated `getSoundType()`/`Bus.MOD` conventions).
- **Standalone geometry harness** (real `DiscTerrainFunction` against the merged jar,
  registry-bootstrapped, default map installed): 1:1 radii + lens mirror confirmed;
  roof present on every non-shard interior column with `ceilingTopY = 255`, min
  interior floor→roof clearance **65** blocks; needles ≤ 16 (cap respected), clustered;
  arrival (85, 85): surface 136 / roof bottom 229 (93-block cavern, bore clearance
  ample); world-top = bedrock, roof body solid, cavern air; 146 curtain columns across
  three test rings with 35 pour sources (sparse, gated); no curtain on the moat
  causeways; overworld columns carry only sentinel roof fields (surgical); `column()`
  deterministic across calls; stage-1 roof sealed to the rim.
- SoftBorder clamp reasoning re-read and confirmed (section above) — no code change.
