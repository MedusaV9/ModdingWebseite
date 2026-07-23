# P1 — World Generation & Dimensions Overhaul (Plan v3)

Planner: P1. Scope: disc terrain, vanilla worldgen integration (caves/features/mobs), ore gating,
structures & terraforming, nether breach, end disc + dragon fight, stage radii rebalance, per-save
state, fog-storm sites, new-ring flags, growth pacing hooks.
Mod: `eclipse`, NeoForge 21.1.238, MC 1.21.1, Java 21, package root `dev.projecteclipse.eclipse`.
All paths below are relative to `ProjectEclipse/` and `src/main/java/dev/projecteclipse/eclipse/`
for Java files unless stated otherwise.

---

## 1. CURRENT-STATE AUDIT

### 1.1 Architecture as it exists

**Chunk generator** — `worldgen/DiscChunkGenerator` (`eclipse:disc`), registered in
`registry/EclipseWorldgen`, bound to `minecraft:overworld` and `minecraft:the_nether` via
`data/minecraft/dimension/overworld.json` / `the_nether.json` (`profile: "overworld"|"nether"`).
Every vanilla worldgen stage is deliberately disabled:

| Hook | Current state | Consequence |
|---|---|---|
| `super(...)` ctor | `BiomeGenerationSettings.EMPTY` for every biome | **Zero vanilla features**: no trees, grass patches, springs, geodes, monster rooms, stone blobs, desert wells, fossils, glow lichen … |
| `fillFromNoise` | writes sections directly from `DiscTerrainFunction.column()`; primes `OCEAN_FLOOR_WG`/`WORLD_SURFACE_WG` | base terrain fine; **everything else must be hand-rolled** |
| `createStructures` | empty | no vanilla structures, no `StructurePlacement`s; `/locate` re-routed through a hardcoded `LOCATE_SITES` table (5 entries) |
| `applyCarvers` | empty | no vanilla caves/ravines |
| `buildSurface` | empty | surface = hand-rolled strata in the terrain function |
| `spawnOriginalMobs` | **empty** | no chunk-gen animal seeding (root cause of "world feels empty", see 1.4) |

**Terrain function** — `worldgen/DiscTerrainFunction` (~1300 lines) is a pure function
`(profile, x, z, stage, DiscMapData) → DiscColumn` with **fixed seed** (`ECLIPSE_SEED`, salted
SimplexNoise + hashes). It hand-rolls: rim taper + fringe stalactites, surface height (mountain
y≈280, base y≈71), rivers, nether moat, strata palettes per `SectorStyle`, ring scars at
**hardcoded** `SCAR_RADII = {225, 300, 360, 420}`, sealed mountain cavity, ice cascade, hanging
rim decor, snow caps, **trees** (one candidate per 8×8 grid cell, canopy radius ≤ 2, clamped
cell-local), **ground cover** (grass/flowers/dead bush/cactus/roots hashes), and **ores**
(`oreAt`, see 1.5).

**Biome source** — `worldgen/DiscBiomeSource` (`eclipse:disc_sectors`): strictly **2-D angular
pie wedges** from `DiscMapData.biomeAt` (8 overworld sectors: plains, desert, forest, jungle,
savanna, swamp, snowy_slopes, dark_forest + mountain core/flank + center cap; 5 nether sectors).
`getNoiseBiome(x,y,z)` ignores `y` entirely → **cave biomes are impossible today**. Only ~11 of
~60 vanilla overworld biomes exist anywhere.

**Stages** — `worldgen/stage/`:
- `WorldStageService`: commit entry point (`setStage`), day/milestone triggers from
  `stages.json`, `StageListener.onStageTerrainComplete` (used by `StructureStamper`),
  `GrowthStartListener` (used by cutscenes), `S2CStagePayload {dim, stage, radius, animating}`
  broadcast, per-save persistence into `EclipseWorldState` (`worldStageOverworld/Nether`,
  `growthCursor` etc.).
- `RingGrowthService`: tick-budgeted annulus sweep. Orderings: GROW = radius-then-angle,
  ERASE = outer-first, FUSION = distance-to-disc-edge. `ANIMATE_TARGET_TICKS = 1500`,
  `INSTANT_BUDGET_MS = 25`, ≤ 4 chunk finishes/tick, cursor persisted every 100 columns,
  protected XZ boxes around stamped structures, players rescued upward. When a chunk's last
  band column is written it re-primes 4 heightmap types (`Heightmap.primeHeightmaps`, line
  ~866) and hands it to `BudgetedBlockWriter.relightAndResend` (whole-chunk relight + resend).
- `BudgetedBlockWriter`: ticketed chunk loads + relight/resend queues.
- `FusionSequence`: intro fusion trigger + rumble broadcast.

**Structures** — `worldgen/structure/StructureStamper` listens on stage-complete and stamps the
`structures[]` array of the committed stage entries: `generateVanilla()` builds a real
`StructureStart` (desert temple, jungle temple, plains village) at a `DiscMapData.Landmark`
anchor and `placeStart()` places its pieces; `flattenPlaza()` flattens village centers;
`FortressCoreBuilder`, `AltarSanctumBuilder`, `WatcherStatues`, `SundialPlaza`,
`StrongholdEmergence` (finale: quake → fissure → stronghold stamped into mountain cavity),
`FallbackBuilders`, `SanctumProtection` are procedural.

**Config/state**:
- Global (per **installation**, `config/eclipse/`): `general.json`, `days.json`,
  `milestones.json`, `modgate.json`, `anticheat.json`, `stages.json`
  (O: 225/300/360/420/480, N: 80/120/160), `disc_map.json` (+ optional heightmap PNG). Loaded by
  static `EclipseConfig.reload()` → `applyStageRadii()` → static `StageRadii`.
- Per-save (`SavedData`): `core/state/EclipseWorldState` — day, altar level, world stages,
  growth cursor, night events, borders, graves … (correct per-save keying already).
- Statics that mirror per-save state: `WorldStageAccess` (volatile stages, set on level load /
  server start, reset on server stop), `StageRadii`, `DiscMapData.instance` (lazy singleton from
  the **global** config file).
- Dev tools: `devtools/StageIO` (per-world snapshots at `world/<name>/eclipse/stages/`),
  `PristineSnapshots` (region backups), `PhaseScheduler`.

**Dimension overrides** — `data/minecraft/dimension_type/overworld.json`: min_y −176,
height 512 (build range −176…336), `monster_spawn_light_level` 0–7, effects `eclipse:overworld`.
`the_nether.json`: 0…256, `coordinate_scale` 8, monster light 7. `DiscProfile.OVERWORLD =
(−176, 512, sea 63, surface 71, lens −130/−80, norm 480)`; `NETHER = (0, 256, sea 32,
surface 138, lens 32/56, norm 160)`. The End dimension is untouched vanilla (reachable only in
theory; no disc content). `eclipse:limbo` is custom (out of P1 scope).

**Mob spawning today** — biome JSONs are vanilla registry entries, so `MobSpawnSettings` are
intact and vanilla's runtime `NaturalSpawner` does run. But: (a) `spawnOriginalMobs` is empty →
**no chunk-generation animal seeding**, and vanilla only trickles CREATURE spawns every 400
ticks against a global cap → the disc is effectively animal-free; (b) newly grown rings never
get seeded either; (c) custom mobs come from `entity/EclipseSpawner` (gazer/stalker/other/
sunmote), which is unrelated to vanilla biome mobs.

### 1.2 Root cause per user complaint

| # | Complaint | Root cause found in code |
|---|---|---|
| 1 | chunk pop-in instead of build-up animation | sweep writes sections silently, then `relightAndResend` sends the **whole chunk at once** (≤4 chunks/tick). No wavefront data is sent to clients; no per-column timing exists. Client has nothing to animate against. |
| 2 | caves featureless/weird | caves are 2 simplex "worm" bands (`|a|<0.085 && |b|<0.085`, band `undersideY+4 … surfaceY−7`) → uniform spaghetti tubes, no rooms, no ravines; `BiomeGenerationSettings.EMPTY` → no dripstone/lush/glow-lichen features; 2-D biome source → no cave biomes; `caveMaxY = surfaceY−7` → **caves can never breach the surface** (no natural entrances). |
| 3 | desert looks weird | desert = sand top + 7 sandstone + hash cactus (0.4 %)/dead bush (1.6 %) only. No dunes (same surface noise as every sector), no desert wells/fossils/pyramid ambience, sharp wedge borders. |
| 4 | world feels empty | `spawnOriginalMobs` empty (no animal seeding at chunkgen or ring growth); everything else (light rules, heightmaps after sweep, caps) is actually fine. |
| 5 | no ravines/springs/stone variety/dungeons | all of those are vanilla **carvers** (canyon) and **underground placed features** (`spring_water`, `spring_lava`, `monster_room`, `amethyst_geode`, `ore_granite/diorite/andesite/tuff`, glow lichen) or structures (mineshaft) — all disabled. |
| 6 | structures on trees | stamping happens at **runtime after trees exist**; village/temple pieces snap to `WORLD_SURFACE`-style heightmaps which count logs/leaves → pieces sit on canopies. Vanilla never has this problem because structures generate before features. No terraforming besides `flattenPlaza`. |
| 7 | ore gating per day | none exists: `oreAt` bands are hardcoded (`annulusBand` uses hardcoded final radii; `stages.json` "oreBudget" is parsed-but-ignored). No mod-ore support. |
| 8 | ore clusters on top of terrain | `oreAt` is evaluated **before** `strataBlock` for every ground y; coal band is −32…**200**, iron to 96 → blobs overwrite the grass/top layers on hills → exposed ore boulders sitting on the surface. |
| 9 | all vanilla biomes + pale garden + set-piece structures | 2-D sector source with 8 fixed wedges; no Mansion/Outpost/Trial Chambers/Ancient City anywhere; stronghold exists only as `StrongholdEmergence` finale in the mountain. Pale Garden is 1.21.4 content, absent in 1.21.1. |
| 10 | nether hole | nether is a plain separate dimension today (own disc profile, day-2 stage trigger). No breach, no visual/physical connection. |
| 11 | end | nothing exists (vanilla End dimension is default-generated but unused). |
| 12 | first phases too big | `stages.json` defaults O:225/300/360/420/480. Stage-0 geometry: main disc r=96 + 8 player discs r=24 on ring r=170 (`DiscGeometry`). Stage 1 jumps to 225 immediately. |
| 13 | same map/stage in a brand-new save | `EclipseWorldState` is per-save and stage statics are reset on stop — the **map itself** is identical in every save by design (fixed `ECLIPSE_SEED`) and, more importantly, **all configs are global**: `disc_map.json`, `stages.json`, `days.json` live in `config/eclipse/` shared by every world in the instance; `SCAR_RADII`/`annulusBand` are hardcoded to one radii set. Editing stage radii for a test world silently changes every world. Also `DiscMapData.instance` is a JVM-global singleton keyed to nothing. |
| 14 | fog storm areas | nothing exists. |
| 15 | glitched mobs in new areas | nothing flags freshly grown rings; `EclipseWorldState.growthCursor` is transient per-sweep. |
| 16 | two-phase terrain → structures | `StructureStamper` fires **immediately** inside `onStageTerrainComplete`; no pending registry, no animation window. |
| 17 | authentic vanilla vegetation | all vegetation is hand-rolled in the terrain function (8×8 tree grid, tiny canopies, 4 flower types, no sugar cane/pumpkins/berries/etc.). |

### 1.3 What must NOT be broken

- Determinism per save: base terrain must remain a pure function so `RingGrowthService`
  rewrite-sweeps, `StageIO` snapshot load, and chunk-gen of not-yet-generated chunks all agree.
- `RingGrowthService` protections (structure no-write boxes, player rescue, cursor resume),
  budget discipline (`ringBlocksBudgetMs`, `INSTANT_BUDGET_MS`).
- `StrongholdEmergence`, sanctum, watcher statues, sundial, limbo — untouched by P1 workers
  except where listed.
- `/locate` table behavior (extend, don't regress).
- `StageIO` dev workflow (P5 owns the tooling; P1 keeps block-level determinism guarantees).

---

## 2. DESIGN

### D1. Vanilla integration pipeline — "disc base + real vanilla decoration" (req 2, 5, 17)

**Decision**: keep `DiscTerrainFunction` as the sole authority for the disc **shape and strata**
(silhouette, rim, underside, mountain, rivers, sealed hull), and re-enable the three vanilla
pipeline stages on top of it, in vanilla order: **carve → (surface stays custom) → decorate →
seed mobs**. No `NoiseRouter`/`NoiseBasedChunkGenerator` terrain delegation — the disc shape,
staged radii and hand-authored map make vanilla's density-function terrain a poor fit; carvers +
placed features + 3-D biomes deliver ~90 % of the "authentic Minecraft" feel for ~20 % of the
risk. (Noise *caves* specifically are approximated with an added cheese layer in the terrain
function, D4 — vanilla noise caves live inside the NoiseRouter and can't run standalone.)

Mechanics, all inside `DiscChunkGenerator` + new `worldgen/vanilla/` engine classes:

1. **Real biome generation settings**: ctor changes from `holder ->
   BiomeGenerationSettings.EMPTY` to a cached **filter**: `BiomeFeatureFilter.settingsFor(holder)`
   returns the biome's real `BiomeGenerationSettings` minus a deny-list (all `minecraft:ore_*`
   iron/gold/diamond/etc. placed features — replaced by the OreField engine D5 — plus a config
   deny/allow list in `worldgen_tuning.json`). Filtering by placed-feature registry id; cache
   one filtered `BiomeGenerationSettings` per biome holder.
2. **Decoration**: override `applyBiomeDecoration(WorldGenLevel, ChunkAccess, StructureManager)`
   → wrap the level in `FixedSeedGenRegion` (delegating `WorldGenLevel` whose `getSeed()`
   returns the frozen map seed, D9) and call `super.applyBiomeDecoration(wrapped, …)`. Vanilla
   then computes the usual per-chunk population seed from our fixed seed → features are
   **identical in every save and every re-run** (needed for sweep replay, D3/D11). Features
   ground-probe via heightmaps, so void columns outside the disc are naturally skipped; a
   post-pass (`HullRepair.afterDecoration`) deletes any feature block that leaked below the
   underside or outside the disc radius (cheap scan of the chunk's edge/underside band only).
3. **Carvers**: implement `applyCarvers` with `DiscCarverEngine`: iterate the 8-chunk
   neighborhood exactly like vanilla `NoiseBasedChunkGenerator.applyCarvers`, using the biome's
   `getCarvers(GenerationStep.Carving.AIR)`, `WorldgenRandom` seeded from the frozen seed +
   chunk coords, a fresh `CarvingMask` per chunk (we are not dependent on ProtoChunk state),
   `Aquifer.createDisabled(fluidPicker)` (fluid = lava below `profile.minY()+12`, else air — dry
   caves; springs come from features), and a `CarvingContext` built against a lazily-created
   private vanilla `NoiseBasedChunkGenerator` (overworld noise settings from registry) purely
   for `topMaterial` surface repair. **Hull guard**: after carving, `HullRepair.afterCarving`
   re-asserts, for every column, all blocks at `y ≤ groundBottomY+2` (bedrock seal) and the
   stalactite fringe band `y < undersideY+4`, and re-seals columns within 6 blocks of the rim
   edge (`edgeFactor < 0.25`) — carvers may otherwise puncture the floating hull. Carvers ARE
   allowed to breach the top surface (that's where free cave entrances come from).
4. **Chunk-gen mob seeding**: `spawnOriginalMobs` = vanilla one-liner
   (`NaturalSpawner.spawnMobsForChunkGeneration(region, biome, center chunkpos, random)`), which
   fixes animals for all newly generated chunks (req 4).
5. **Unified pipeline object**: `DiscGenPipeline.run(levelOrRegion, chunk, phases…)` — the same
   carve/decorate/seed sequence callable (a) from chunk generation (ProtoChunk path) and (b)
   from the ring-growth sweep on live `LevelChunk`s (D3). This is the load-bearing piece that
   keeps "grown" terrain identical to "generated" terrain.

**Trade-offs**: carving on live chunks at runtime is nonstandard but safe — we construct every
argument ourselves (mask, random, aquifer, context) and write through `ChunkAccess.setBlockState`
with no neighbor updates, then relight/resend via the existing writer. Decoration on live chunks
is exactly what `/place feature` does; falling-block/water physics after resend are acceptable
and vanilla-authentic.

### D2. Desert & per-sector surface identity (req 3)

- `DiscTerrainFunction.computeSurfaceY` gains per-style modifiers: DESERT adds directional
  long-wavelength dune ridges (new salted noise, amplitude ~6, wavelength ~48, oriented by
  sector mid-angle) and suppresses small-scale jitter; BADLANDS (new outer sub-ring, D6) gets
  terracotta strata bands; SWAMP lowers toward sea level with shallow water pools.
- Desert strata: sand top ×3, sandstone band to `surfaceY−10`, sprinkle `smooth_sandstone`/
  `cut_sandstone` accents via hash; red-sand transition patches near the badlands ring.
- Everything decorative (cacti with proper heights, dead bushes, desert wells 1/1000-ish,
  fossils, sus-sand-free pyramids ambience) arrives **for free** from D1's vanilla
  `minecraft:desert` placed features once the hand-rolled cactus/dead-bush hashes are deleted.

### D3. Ring growth v2 — full-chunk regeneration + decoration replay (req 1, 4, 17 in grown rings)

Sweeps currently write only band columns and leave old columns untouched. With vegetation moving
to features, grown annuli must be decorated too:

- **Chunk-complete rewrite**: when a GROW sweep touches a chunk, it rewrites **all** disc columns
  of that chunk from the terrain function (not just band columns), then replays
  `DiscGenPipeline` (carve → decorate → seed animals) on the live chunk, then re-primes
  heightmaps and relight/resends (existing machinery). Guarantees: grown chunks are
  block-identical to what fresh generation at the new stage would produce (same fixed seeds);
  no duplicated trees at the band boundary (old decoration inside the chunk is wiped by the base
  rewrite because base fill now includes air for non-terrain space — the rewrite loop must
  explicitly clear `bottomY..maxY` outside the column solid span, which the sweep already does
  for ERASE; extend to GROW).
- Structure protection boxes, player rescue, cursor resume, budget discipline all unchanged;
  decoration/carve replay runs inside the same per-tick budget accounting (they are bounded per
  chunk and only run at chunk-finish, ≤ 4/tick).
- `StageIO` snapshots (P5) still capture final blocks; a loaded snapshot skips pipeline replay
  (blocks already decorated). Guarded by the existing `RingGrowthService.isRunning` checks.

### D4. Cave system (req 2, 5, 8)

Layered underground, all deterministic:

1. **Cheese layer** (terrain function): new 3-D noise `CAVE_CHEESE` opens rooms where
   `noise > 0.62 − depthBoost`, only below `surfaceY − 12`, radius-faded near rim/underside.
   Combined with the existing worm tubes (kept, widened threshold 0.085 → 0.11 and
   `caveMaxY` raised to `surfaceY` so tunnels may daylight naturally).
2. **Vanilla carvers** (D1): `minecraft:cave`, `cave_extra_underground`, `canyon` → ravines and
   organic entrances.
3. **Cave biomes** (3-D biome source): `DiscBiomeSource.getNoiseBiome` becomes y-aware — below
   `surfaceY(x,z) − 14` (call into the pure terrain function; quart-resolution, BiomeManager
   caches): regions of `minecraft:dripstone_caves` and `minecraft:lush_caves` from a low-freq
   2-D noise; `minecraft:deep_dark` for y < −96 within r < 120 of the mountain (ancient-city
   tie-in D6). Cave features (dripstone clusters, pointed dripstone, glow berries, moss,
   sculk via deep dark) then come from D1 decoration automatically.
4. **Authored cave entrances** (req 8): `oreAt` surface exposure is eliminated (D5 moves ores
   fully below `min(surfaceY−8, 60)`); in its place `CaveEntrances` (terrain-function module)
   opens 1 hashed walk-in entrance per ~96×96 cell where slope is low: a cone/helix void mask
   from `surfaceY+1` down to the worm band, rimmed with exposed stone + `minecraft:glow_lichen`
   patches by decoration. Deterministic → sweeps and chunk-gen agree.
5. **Underground features from vanilla biome settings** (free with D1): water/lava springs,
   amethyst geodes, monster rooms (vanilla dungeons), granite/diorite/andesite/tuff/dirt/gravel
   blobs, glow lichen. **Mineshafts + 2 custom dungeons** are structures → D6.

### D5. Ore gating engine (req 7, 8)

**Space-based gating** (not time-based): each stage annulus carries an ore whitelist; the day
gates map to stages via the existing `stages.json` triggers (day 1 = stages ≤ 1 area, day 2 =
stage-2 annulus + nether, day 3 = stage-3+). Mining deeper in old rings never yields new-tier
ore — progression pushes players outward, and terrain stays a pure function of (pos, stage).

- New `worldgen/ore/` engine, config-driven: `config/eclipse/ores.json` (auto-written default,
  reloadable, **frozen per save** by D9):
  ```json5
  { "overworld": [
      { "id": "coal",    "block": "minecraft:coal_ore", "deepslate": "minecraft:deepslate_coal_ore",
        "minY": -32, "maxY": 52, "cellP": 0.30, "radius": 3.2, "unlockStage": 0,
        "bandFactor": [1,1,1,1,1,1] },
      { "id": "iron",    "…": "…", "unlockStage": 2 },
      { "id": "diamond", "…": "…", "unlockStage": 3, "centerBias": false },
      { "id": "zinc",    "block": "create:zinc_ore", "deepslate": "create:deepslate_zinc_ore",
        "requiredMod": "create", "unlockStage": 3 } ],
    "nether": [ { "id": "quartz", "unlockStage": 0 }, { "id": "netherite", "block":
      "minecraft:ancient_debris", "unlockStage": 2 } ] }
  ```
- `OreField.oreAt(profile, x, y, z, deepslate?)` replaces `DiscTerrainFunction.oreAt`: same
  hashed one-blob-per-16³-cell algorithm, but (a) table from config snapshot, (b) **hard cap
  `maxY ≤ min(configured maxY, 52)`** so no blob ever reaches typical surfaces (req 8 exposure
  fix; entrances replace them per D4), (c) band = stage annulus of the **frozen radii**
  (D9) whose whitelist decides availability, (d) `requiredMod` entries resolve via
  `ModList.get().isLoaded` and only in annuli with `unlockStage` satisfied (ties into P4's
  ModGate day mapping).
- Vanilla ore placed features are deny-listed in D1's `BiomeFeatureFilter` (coal/iron/…/emerald
  and `ore_ancient_debris_*`); stone-variety blobs (granite/tuff/…) stay allowed.
- Dev: reload via `/eclipse-worldgen ores reload` (new command class, D12 wiring); already
  generated chunks keep old blocks (documented; use StageIO rebuild to re-roll).

### D6. Biome map v2 + full vanilla coverage + Pale Garden (req 9)

`disc_map.json` v2 (defaults authored in code, overridable per save):

- **Sub-ring sectors**: each pie wedge splits into inner/mid/outer rings so the expanded map
  carries many more biomes. Default layout (overworld, 8 wedges × up to 3 rings — final radius
  440, D8-rebalance):
  plains→sunflower_plains→**pale_garden(eclipse)**, desert→badlands→wooded_badlands,
  forest→birch_forest→old_growth_birch_forest, jungle→sparse_jungle→bamboo_jungle,
  savanna→savanna_plateau→windswept_savanna, swamp→mangrove_swamp→(swamp),
  snowy_slopes→grove→snowy_taiga+ice_spikes, dark_forest→taiga→old_growth_pine_taiga; plus
  cherry_grove + meadow on the mountain flank ring, mushroom_fields as a small detached shard
  ring off the rim (stage 4+), `minecraft:river` along authored rivers, cave biomes 3-D (D4).
  Every biome id in the table is data-driven; unknown ids fall back gracefully (existing
  behavior).
- **Pale Garden port** (1.21.1 custom): new `eclipse:pale_garden` biome JSON (fog/greyish grass
  colors, `minecraft:dark_forest` temperature class), custom **pale oak wood set blocks**
  (log/stripped/wood/planks/leaves/sapling-less; slabs/stairs/fence optional S2 stretch) in a
  new registry class, custom configured/placed features `eclipse:pale_oak_tree` (dark-oak-shaped
  2×2 canopy w/ pale palette) + hanging pale moss carpet feature. Creaking-like mob is **P6**;
  the biome JSON leaves a documented `"spawners"` hook (P6 adds via biome modifier or JSON edit;
  interface in §4).
- **Set-piece structures** (all placed via the two-phase stamper D7, real vanilla starts via
  `generateVanilla` + SitePrep):
  - `minecraft:mansion` — dark-forest/taiga outer ring landmark, stage 4.
  - `minecraft:pillager_outpost` — savanna mid ring, stage 2.
  - `minecraft:trial_chambers` — underground landmark under the badlands ring, stage 3
    (anchor y ≈ −20; carved room envelope via SitePrep cavity mode).
  - `minecraft:ancient_city` — **inside the mountain**: y ≈ −40 under the mountain cavity,
    deep-dark biome region (D4) ties visuals; carved envelope + connection tunnel to the
    stronghold fissure (flavor).
  - Stronghold finale stays `StrongholdEmergence`, but its surface gets a **big surface
    structure + custom gauntlet dungeon** (Collapsed Vault, D7) between the surface entrance and
    the portal room; landmark moves to the far rim (stage 5, r ≈ 400) per user request — the
    mountain keeps the Ancient City instead. `LOCATE_SITES` table extended accordingly.
- 2-D wedge borders get a ±6-block hash wobble (already partially wobbled) plus 8-block
  surface-block blend bands so borders read naturally.

### D7. Structure system v2 — terraforming + two-phase + underground sites (req 5, 6, 16)

- **`SitePrep`** (fixes on-trees): before any `placeStart`, for footprint = start bounding box
  + 6-block margin: (1) delete vegetation column-wise (logs/leaves/plants/snow above ground),
  (2) terraform: target plateau = anchor surface Y, smoothstep skirt over 8–14 blocks (raise
  with sector filler, cut with air), (3) re-prime heightmaps, (4) place pieces, (5) relight/
  resend via `BudgetedBlockWriter`. Cavity mode for underground starts (trial chambers, ancient
  city): carve an interior envelope box + entrance shaft instead of a plateau. All budgeted
  (existing writer), so big mansions don't spike the tick.
- **Two-phase apply** (req 16): `StructurePendingRegistry` (persisted in the new
  `EclipseWorldgenState` SavedData): on `onStageTerrainComplete`, `StructureStamper` **enqueues**
  `{siteId, structureId, anchor, stage, status=PENDING}` and fires
  `StructurePhaseEvents.PENDING` (server event bus custom event + S2C payload for P2's rift
  animation). Placement happens on `StructurePendingRegistry.trigger(siteId)` (called by P2's
  sequence when the rift finishes) or automatically after `structure_phase.auto_delay_ticks`
  (default 100, config) — never lost across restarts (registry is SavedData; auto-trigger
  resumes).
- **Underground sites**: `UndergroundSites` deterministic table (hash per annulus, min-spacing,
  slope/depth checks): N `minecraft:mineshaft` per annulus (generateVanilla at y ≈ −20…10),
  extra monster-room clusters near entrances, and **2 custom dungeons**:
  - *Collapsed Vault* (stronghold gauntlet + 1 standalone instance): procedural rooms/corridors
    (FallbackBuilders style), trap corridors, vanilla spawner blocks with **config-driven mob
    ids** (`dungeons.json`: P6 supplies `eclipse:*` mob ids later; defaults zombie/skeleton),
    loot tables `eclipse:dungeon/collapsed_vault`.
  - *Umbral Warrens* (cave-web dungeon in the deep dark region): tunnel maze + nest rooms,
    spawners from config, loot `eclipse:dungeon/umbral_warrens`.
- Village/temple stamping switches to SitePrep too (replaces `flattenPlaza`).

### D8. Stage radii rebalance (req 12)

New `stages.json` defaults (smaller early game; final 440 < old 480 keeps sweep cost down):

| Overworld stage | old r | new r | trigger (unchanged) | structures (new additions bold) |
|---|---|---|---|---|
| 0 (geometry) | 96+discs | 96+discs | — | — |
| 1 | 225 | **150** | intro_fusion | — |
| 2 | 300 | **210** | milestone:2 | desert_temple, **pillager_outpost** |
| 3 | 360 | **280** | milestone:3 | jungle_temple, **trial_chambers**, **fog storms ×2** |
| 4 | 420 | **360** | milestone:4 | village_plains, **mansion**, **ancient_city** |
| 5 | 480 | **440** | final_day | stronghold_emergence, **stronghold_surface+vault** |

Nether: 80/120/160 → **64/110/150** (day:2/10/12 unchanged). End disc appears via its own
trigger (D10). Scar radii and ore bands derive from the **frozen** radii (D9), never from
hardcoded constants again. Mountain (center 140, radius 75) fully inside from stage 3; at stages
1–2 its outer flank is rim-tapered (accepted, reads as "the mountain grows in"; landmark
structures on it are stage ≥ 3).

### D9. Per-save worldgen state (req 13)

- **Freeze-on-create**: new `worldgen/FrozenParams` — plain JSON at
  `world/<save>/eclipse/worldgen.json` (NOT SavedData: must be readable in
  `ServerAboutToStartEvent`, before dimensions deserialize). First boot of a save copies from
  global config: map seed (default `ECLIPSE_SEED`, optionally randomized via
  `general.json:randomizeMapSeed`), stage radii arrays (→ scar radii + ore bands), disc-map
  JSON snapshot, ores.json snapshot, end/breach/fogstorm params. Every consumer
  (`DiscMapData`, `StageRadii`, `DiscTerrainFunction` scar/band lookups, `OreField`,
  `DiscBiomeSource`) reads through `FrozenParams.current()` — a volatile context set on
  `ServerAboutToStartEvent`, cleared on `ServerStoppedEvent`.
- Global `config/eclipse/*` remains the **template for new saves** + live-reloadable *runtime*
  knobs (budgets, pacing); anything that shapes terrain comes only from the frozen copy.
  `/eclipse-worldgen refreeze [section]` (dev, P5-facing) re-copies global → save explicitly.
- Statics audit (fix while here): `DiscMapData.instance`, `StageRadii`, `WorldStageAccess` all
  keyed under `FrozenParams` lifecycle; verified reset on server stop (WorldStageAccess/Service
  already do; DiscMapData currently survives → bug, fixed).
- `EclipseWorldgenState` (new SavedData, overworld): pending structures (D7), new-ring registry
  (D11), end/breach materialization flags, fog-storm chest index. (Distinct from
  `EclipseWorldState` to avoid file-ownership collision with other planners.)

### D10. Nether breach + nether disc upgrade (req 10)

**Decision: keep the real nether dimension** (option b — seamless transfer), because ultrawarm
(lava flow speed), bed explosions, fog/ambience, piglin/zombification behavior, ghast/spawn
logic and the 0…256 height budget are all per-dimension and irreplaceable in-overworld without
a mixin swamp. The "hole" is a **physical breach set-piece in the overworld disc** plus a
matching **return chimney on the nether disc**, glued by a transfer service:

- **Breach site**: `disc_map.json` landmark `eclipse:nether_breach` (badlands/desert ring edge,
  r ≈ 130, opens with nether stage 1 / day 2). Terrain-function support (`BreachGeometry`): a
  32-block-wide funnel crater through the full lens (surface → below underside), walls layered
  netherrack/blackstone/magma with crimson-creep ring (nylium patches, weeping vines, fire) in a
  12-block halo. Deterministic: new chunks generate it; the day-2 event materializes it on live
  chunks via a budgeted `BreachBuilder` sweep (same writer) with quake/smoke hooks for P2
  (S2C payload with crater geometry).
- **Transfer**: `BreachTransferService` (server tick): players (and non-player entities,
  config) falling below `undersideY − 16` within the breach column → teleport to
  `minecraft:the_nether` at the fixed nether-entry chimney (landmark `eclipse:breach_arrival`,
  near nether disc rim), preserving fall vector, +8 s slow-falling (config) so arrival onto the
  netherrack funnel is survivable. **Return**: the arrival chimney is a climbable basalt spiral
  + a "soul updraft" column (levitation zone, config strength) rising into an overworld return
  pad at the breach rim (reverse teleport at chimney top). No vanilla portals: portal ignition
  stays blocked (existing behavior kept; clamp any `ChangeDimensionEvent` outside the breach).
- **Nether disc**: all 5 biomes already exist as sectors; D1 gives them real vegetation features
  (crimson/warped fungi & vines, glowstone blobs, basalt pillars) and mobs. **Bottom surface**:
  underside band gets hanging decor (glowstone clusters, weeping-vine curtains, shroomlight
  pockets) via terrain-function underside module + inverted feature stamps; a small
  **inverted bastion ruin** ("Hanging Court") is stamped under the disc as a set-piece
  (procedural, blackstone), reachable via ladder shafts — satisfies "structures on TOP and
  BOTTOM". Top: existing `FortressCoreBuilder` (stage 1) + vanilla `minecraft:bastion_remnant`
  via generateVanilla (stage 2).
- **Soft border**: nether soft border already exists (`softBorderRadiusNether`); breach-only
  access means no portal-scale escape; still clamp teleports/ender pearls beyond
  `radius + 16` (listener in the transfer service).

### D11. Growth animation pacing + new-ring flags (req 1, 15)

Server-side hooks P2 builds visuals on (P1 owns pacing/order/data):

- **Ordering guarantee** (already true, now contractual): GROW = radius-then-angle wave;
  FUSION = edge-distance. Documented + kept stable.
- **`S2CGrowthWavePayload`** `{dim, fromStage, toStage, innerR, outerR, waveR, waveAngleStart,
  waveAngleEnd, columnRiseTicks, pulseIndex}` broadcast every 5 ticks during animated sweeps —
  the exact wavefront the sweep just wrote. P2 renders rise/dissolve shaders against it.
- **Resend-after-wavefront**: chunk relight/resend is delayed until the wavefront payload
  covering that chunk's columns has been out for ≥ `growth.revealDelayTicks` (default 10) — the
  client never sees raw chunks pop before the animation front reaches them.
- **Pacing config** `worldgen_tuning.json → growth {targetTicks, revealDelayTicks,
  ringsPerPulse, shakeEveryRings}`; reload-supported. Shake pulses reuse existing
  `S2CShakePayload`.
- **`NewRingRegistry`** (in `EclipseWorldgenState`): rows `{dim, innerR, outerR, stage,
  committedGameTime}`; API `isFreshRing(level, pos)`, `freshness(level, pos) → 0..1` (decays
  over `glitch.freshTicks`, default 3 in-game days), `sampleFreshPositions(level, n)` for P4/P6
  glitched-mob spawners. Rebuilds/StageIO loads do NOT re-flag (only genuine commits).

### D12. The End disc + dragon fight (req 11)

- **In-sky disc in the overworld** (user preference): end-stone lens, radius 96, surface
  y ≈ 360, thickness ~14, centered above the map center. Requires headroom → dimension_type
  overworld `height 512 → 640` (build −176…464) + `DiscProfile.OVERWORLD.height = 640`.
  Officially supported on fresh saves (event worlds are fresh); existing dev saves keep working
  (new sections appear empty) but are not a support target. Mountain peak 280 stays well below
  the disc (80-block clearance).
- Terrain-function module `EndDiscGeometry`: lens + 8 obsidian pillars (heights 24–44, iron-bar
  cages on the tallest 2), central bedrock exit-portal podium (portal blocks lit only after the
  dragon dies; stepping in teleports to the sanctum — no vanilla End credits), chorus fields on
  the outer third, `minecraft:the_end` biome via the 3-D biome source for y > 320 within the
  disc radius (end mobs/ambience; sky/fog visuals are P2 via Veil).
- **Materialization**: hidden until its trigger (`end.json`: `{trigger: "day:9", radius, y}`),
  then `EndDiscService.materialize(server)` builds it via the budgeted writer while P2 plays the
  crash-in sequence (payload hook with disc params + timeline). After materialization the
  terrain function includes it for new chunks (flag in `EclipseWorldgenState` + FrozenParams
  geometry, mirroring how stages work).
- **Dragon**: real `EnderDragon` in the overworld with `setFightOrigin(discCenter)` (1.21.1 API
  exists for non-End fights) driven by `EclipseDragonFight` (custom controller, NOT vanilla
  `EndDragonFight`): spawns crystals on pillars, boss bar (`ServerBossEvent`), phase watchdog —
  if a vanilla phase misbehaves outside the End (known risk: some phases path against
  `fightOrigin` heightmap; podium provided), the watchdog forces circling/strafe phases only
  (config `end.simpleDragonAi=true` fallback). Death: XP rain, egg on podium, portal lights,
  `EclipseWorldState`-adjacent flag in `EclipseWorldgenState`, event fired for P2/P4 (unlocks).
  Crystal respawn ritual disabled (one-shot fight, config).
- **End cities**: 2 small `minecraft:end_city` starts via generateVanilla + SitePrep plateau on
  the outer third (loot: elytra kept? default **no elytra** — config `end.allowElytra=false`
  strips it from placed loot; flight would trivialize the disc world).

---

## 3. WORKER PACKAGES

Rules for all packages: never modify `admin/EclipseCommands.java`, `EclipseMod.java`, or lang
JSONs (drop keys to `docs/plans_v3/langdrop/<worker>.json`, en_us + de_de). All thresholds/knobs
via config with `/eclipse reload` support where stated. Respect tick budgets — heavy writes only
through `BudgetedBlockWriter`/sweep machinery. No two packages touch the same file; cross-package
calls use the exact signatures specified in §3.10 (compile seam contracts).

### W1.1 — Vanilla pipeline core (carvers, features, chunk-gen mob seeding)
- **Goal**: D1 — real biome features + carvers + `spawnOriginalMobs` inside the disc generator,
  with hull protection and fixed-seed determinism.
- **Files (create)**: `worldgen/vanilla/DiscGenPipeline.java`, `worldgen/vanilla/DiscCarverEngine.java`,
  `worldgen/vanilla/BiomeFeatureFilter.java`, `worldgen/vanilla/FixedSeedGenRegion.java`,
  `worldgen/vanilla/HullRepair.java`, `worldgen/vanilla/package-info.java`.
- **Files (modify)**: `worldgen/DiscChunkGenerator.java`.
- **Outline**: ctor generation-settings getter → `BiomeFeatureFilter.settingsFor` (cache
  per-holder; deny-list from `worldgen_tuning.json → features.deny[]` + hardcoded vanilla ore
  feature ids); override `applyBiomeDecoration` (wrap in `FixedSeedGenRegion(getSeed()=
  FrozenParams.mapSeed())`, call super, then `HullRepair.afterDecoration`); implement
  `applyCarvers` per D1.3 (8-neighborhood, `WorldgenRandom(seed=mapSeed)`, own `CarvingMask`,
  disabled aquifer, `CarvingContext` against a lazy private `NoiseBasedChunkGenerator`
  from `NoiseGeneratorSettings.OVERWORLD` registry holder, then `HullRepair.afterCarving`);
  implement `spawnOriginalMobs` via `NaturalSpawner.spawnMobsForChunkGeneration`;
  `DiscGenPipeline.runOnLiveChunk(ServerLevel, LevelChunk)` public entry (used by W1.5/W1.6).
  Keep `findNearestMapStructure` but read the table from `VanillaLandmarks.locateSites()`
  (W1.6 seam, §3.10) instead of the local constant.
- **Acceptance**: fresh world: trees/grass/flowers per biome, springs, geodes, monster rooms,
  granite/diorite/andesite/tuff blobs, glow lichen present; ravines + surface cave mouths
  exist; underside/bedrock hull intact everywhere (scan test around rim); animals present in
  new chunks; same seed → identical chunks across two saves with same frozen params;
  `runOnLiveChunk` decorates a stripped chunk identically to chunkgen (compare snapshot).
- **Model**: FABLE. **Size**: L.

### W1.2 — Terrain function v2 (strata-only base, cheese caves, entrances, dunes, breach/end geometry)
- **Goal**: D2 + D4.1/4.4 + geometry support for D10/D12; delete hand-rolled vegetation/ores.
- **Files (modify)**: `worldgen/DiscTerrainFunction.java`, `worldgen/DiscProfile.java`
  (OVERWORLD height 512→640; add `endDisc` accessor constants).
- **Files (create)**: `worldgen/CaveDensity.java` (worms+cheese), `worldgen/CaveEntrances.java`,
  `worldgen/BreachGeometry.java`, `worldgen/EndDiscGeometry.java`.
- **Outline**: strip `treeAt`/cover/pillar/`oreAt`+`OreType` tables (ore calls redirect to
  `OreField.oreAt`, §3.10; NO vegetation left except snow caps + scar amethyst accents which are
  strata); keep rivers/scars/cascade/moat/hang decor; scar radii + annulus bands read
  `FrozenParams.stageRadii()` (§3.10) instead of `SCAR_RADII`; cave band via `CaveDensity`
  (worms widened, cheese rooms, `caveMaxY = surfaceY`); `CaveEntrances.mask(x,y,z)` cone/helix
  per D4.4; desert dunes + badlands terracotta strata + swamp lowering per D2; breach funnel via
  `BreachGeometry.carve(profile, x, y, z)` active when `FrozenParams.breachOpen()`; end lens via
  `EndDiscGeometry.stateAt(x,y,z)` active when `FrozenParams.endDiscMaterialized()` (both also
  always-on for chunks generated after the flags set). Column record fields adjusted; keep the
  public static pure API (`column`, `stateInColumn`, `surfaceY`) signature-stable.
- **Acceptance**: no grass/flower/tree/ore blocks emitted by the terrain function itself
  (assert via unit-style scan of sample columns); dunes visible in desert; entrance craters
  reach the worm band; breach/end geometry off by default and deterministic when on; build
  passes with height 640.
- **Model**: FABLE. **Size**: L.

### W1.3 — Ore gate engine + config
- **Goal**: D5.
- **Files (create)**: `worldgen/ore/OreField.java`, `worldgen/ore/OreConfig.java`,
  `worldgen/ore/OreGateApi.java`, `worldgen/ore/package-info.java`,
  `docs/plans_v3/langdrop/W1.3.json`.
- **Outline**: `OreConfig.reload(Path configDir)` loads/writes-default `ores.json` (schema D5)
  into an immutable volatile snapshot (`OreConfig.Snapshot current()`), validating blocks exist
  (skip + warn unknown/mod-absent); `OreField.oreAt(DiscProfile, int x, int y, int z, boolean
  deepslate)` — hashed cell blobs, band from `FrozenParams.annulusBand(r)`, whitelist by
  `unlockStage`, `requiredMod` via `ModList`; global `maxY` clamp 52; `OreGateApi` (P4-facing):
  `List<OreId> unlockedInBand(int band)`, `int unlockStageOf(String oreId)`,
  `int bandAt(DiscProfile, BlockPos)`. Localized log/warn strings to langdrop.
- **Acceptance**: default gates: coal/copper everywhere; iron/gold absent inside stage-1 radius,
  present in stage-2 annulus; diamond only stage-3+ annuli; ancient debris only nether stage-2+;
  with Create absent, zinc entries skipped silently; reload swaps snapshot without touching
  generated chunks; deterministic across saves with equal frozen params.
- **Model**: SOL. **Size**: M.

### W1.4 — Biome map v2, 3-D biome source, Pale Garden port
- **Goal**: D6 (layout + cave/end biome lookup + pale garden content); D4.3.
- **Files (modify)**: `worldgen/DiscBiomeSource.java`.
- **Files (create)**: `worldgen/DiscMapDefaults.java` (authored v2 defaults incl. sub-rings,
  new landmarks table incl. mansion/outpost/trial_chambers/ancient_city/nether_breach/
  breach_arrival/fog storms/stronghold-at-rim), `worldgen/CaveBiomeMap.java`,
  `registry/PaleGardenBlocks.java` (own `DeferredRegister<Block>`+items),
  `data/eclipse/worldgen/biome/pale_garden.json`,
  `data/eclipse/worldgen/configured_feature/pale_oak_tree.json` (+ `pale_moss_patch.json`),
  `data/eclipse/worldgen/placed_feature/pale_oak_trees.json` (+ moss),
  blockstates/models/item-model JSONs + textures under `assets/eclipse/` (placeholder-quality
  textures acceptable; list in `docs/ASSET_MANIFEST_V2.md` addendum comment),
  `docs/plans_v3/langdrop/W1.4.json`.
- **Outline**: `DiscBiomeSource.getNoiseBiome` becomes y-aware: below `surfaceY−14` →
  `CaveBiomeMap.at(x,y,z)` (dripstone/lush regions noise, deep_dark near mountain per D4.3);
  above 320 within end radius → `minecraft:the_end` (via `FrozenParams.endDiscMaterialized()`
  OR always when inside geometry — biome may pre-exist harmlessly); sub-ring resolution in
  `biomeAt` path via `DiscMapDefaults` ring tables (sector entries gain optional
  `rings: [{maxR, biome}]`); `collectPossibleBiomes` updated (must include every referenced
  biome + eclipse:pale_garden + cave biomes + the_end, or features/spawns break). Pale garden
  biome JSON: greyish `grass_color`/`foliage_color`, fog, ambience, features referencing the new
  configured features; `"spawners"` left vanilla-monster-only with a `_p6_hook` comment.
- **Acceptance**: `/locate biome` finds every table biome on a stage-5 world (spot-check 10);
  cave biomes appear underground (F3), lush/dripstone features generate there via W1.1;
  pale garden renders grey-ish with pale oak trees; no missing-model/purple blocks;
  datapack loads with zero registry errors.
- **Model**: FABLE. **Size**: L.

### W1.5 — Growth v2: chunk-complete rewrite, pipeline replay, wave payloads, new-ring registry
- **Goal**: D3 + D11.
- **Files (modify)**: `worldgen/stage/RingGrowthService.java`,
  `worldgen/stage/BudgetedBlockWriter.java`, `worldgen/stage/WorldStageService.java`,
  `worldgen/stage/FusionSequence.java`.
- **Files (create)**: `network/S2CGrowthWavePayload.java`, `worldgen/stage/GrowthPacing.java`,
  `worldgen/stage/NewRingRegistry.java`, `core/state/EclipseWorldgenState.java`,
  `docs/plans_v3/langdrop/W1.5.json`.
- **Outline**: GROW sweeps enumerate all disc columns of touched chunks (band membership by
  chunk, not column), clear+rewrite full span, then at chunk-finish call
  `DiscGenPipeline.runOnLiveChunk` (W1.1 seam) before heightmap re-prime and relight/resend;
  delay resend per D11 (`revealDelayTicks` after covering wavefront); emit
  `S2CGrowthWavePayload` every 5 ticks (animated sweeps only) + shake pulses per config;
  `GrowthPacing` reads `worldgen_tuning.json → growth` (create file loader here; file also
  carries `features.deny[]` for W1.1 and `glitch.freshTicks` — single loader class here,
  accessors public); on sweep completion register the annulus in `NewRingRegistry`
  (SavedData-backed via `EclipseWorldgenState`), API per D11; rebuilds (`startRebuild`) skip
  registry + skip animal seeding. `EclipseWorldgenState`: pending-structure list storage (used
  by W1.6), new-ring rows, `breachOpen`/`endDiscMaterialized` booleans + fog-chest index (used
  by W1.7/W1.8/W1.9) — pure storage with typed accessors, no logic.
- **Acceptance**: animated stage grow shows no chunk visible before its wavefront (verify with
  logging + a client test); grown annulus contains trees/features/animals identical to a
  freshly generated world at that stage (block-compare 3 sample chunks); cursor resume across
  restart still works; instant (non-animated) grows skip wave payloads; `isFreshRing` true in
  new annulus, false after decay/rebuild; budget respected (no tick > 60 ms in test sweep on
  16 GB VM defaults).
- **Model**: FABLE. **Size**: L.

### W1.6 — Structure system v2: SitePrep, two-phase pending registry, underground sites, custom dungeons
- **Goal**: D7 (+ landmark/locate table ownership).
- **Files (modify)**: `worldgen/structure/StructureStamper.java`.
- **Files (create)**: `worldgen/structure/SitePrep.java`,
  `worldgen/structure/StructurePendingRegistry.java`, `worldgen/structure/UndergroundSites.java`,
  `worldgen/structure/VanillaLandmarks.java` (structure-id ↔ landmark table + `locateSites()`),
  `worldgen/structure/dungeon/CollapsedVaultBuilder.java`,
  `worldgen/structure/dungeon/UmbralWarrensBuilder.java`,
  `worldgen/structure/dungeon/DungeonSpawners.java` (`dungeons.json` loader: mob ids per
  dungeon, P6 seam), `network/S2CStructureRiftPayload.java`,
  `data/eclipse/loot_table/dungeon/collapsed_vault.json`,
  `data/eclipse/loot_table/dungeon/umbral_warrens.json`,
  `docs/plans_v3/langdrop/W1.6.json`.
- **Outline**: stamper listener enqueues into `StructurePendingRegistry` (persist via
  `EclipseWorldgenState` accessors, W1.5 seam) + broadcasts `S2CStructureRiftPayload {siteId,
  structureId, anchor, footprint}`; `trigger(siteId)`/auto-delay places via SitePrep→
  `generateVanilla`→`placeStart` (existing methods refactored to take a prepared ground grid);
  SitePrep per D7 (vegetation clear, plateau/cavity terraform, budgeted, heightmap re-prime);
  `UndergroundSites` deterministic tables (mineshafts, monster-room clusters, both dungeons)
  registered as pending sites on their stage; dungeon builders with config-driven spawners +
  loot; mansion/outpost/trial_chambers/ancient_city/end_city/bastion placement helpers (used
  by W1.7/W1.8 through `VanillaLandmarks` — single owner of `generateVanilla` wrappers);
  extend locate table (mansion, outpost, trial_chambers, ancient_city, mineshaft → nearest
  site). Protected-zone registration for all placed sites (existing RingGrowth mechanism —
  register via the existing measured-extent path, no RingGrowthService file edits needed).
- **Acceptance**: village/temple/mansion never intersect a tree (place on forest test spot:
  vegetation cleared, plateau smooth); trial chambers + ancient city carve clean envelopes,
  reachable; two-phase: pending → rift payload → trigger places; restart mid-pending resumes;
  both custom dungeons generate with working config spawners + loot; `/locate structure
  minecraft:mansion` resolves post-stamp.
- **Model**: FABLE. **Size**: L.

### W1.7 — Nether breach + transfer + nether disc dressing
- **Goal**: D10.
- **Files (create)**: `worldgen/nether/BreachBuilder.java`,
  `worldgen/nether/BreachTransferService.java`, `worldgen/nether/HangingCourtBuilder.java`
  (underside bastion ruin), `worldgen/nether/NetherUndersideDecor.java` (hanging
  glowstone/vine/shroomlight stamps, invoked from `DiscGenPipeline` nether path via seam),
  `network/S2CBreachPayload.java`, `docs/plans_v3/langdrop/W1.7.json`.
- **Outline**: `BreachBuilder.open(server)` (called from nether stage-1 commit via a
  `StageListener` it registers itself): budgeted sweep materializing `BreachGeometry` columns on
  live overworld chunks, sets `EclipseWorldgenState.breachOpen`, broadcasts `S2CBreachPayload
  {center, radius, phase}` (P2 smoke/quake); `BreachTransferService` tick handler per D10
  (fall-through teleport both directions, slow-fall grace, updraft levitation zone at arrival
  chimney, pearl/teleport clamp beyond nether soft border + 16); `HangingCourtBuilder` stamped
  under the disc at stage 2 (pending-registry site via W1.6 API); bastion_remnant top-side site
  registration (uses `VanillaLandmarks` helpers); arrival chimney build (basalt spiral +
  return pad) part of `BreachBuilder` nether-side pass.
- **Acceptance**: day-2 commit opens the crater with nether creep ring; falling in lands you in
  the nether at the chimney, alive, with matching visual continuity (netherrack funnel);
  updraft returns you to the overworld rim pad; no vanilla portal can be lit anywhere; pearls
  can't cross the nether soft border; fortress (existing) + bastion + hanging court all present
  by stage 2.
- **Model**: FABLE. **Size**: L.

### W1.8 — End disc materialization + dragon fight + end cities
- **Goal**: D12.
- **Files (create)**: `worldgen/end/EndDiscService.java`, `worldgen/end/EndSpires.java`
  (pillars/crystal placement/podium build), `worldgen/end/EclipseDragonFight.java`,
  `worldgen/end/EndConfig.java` (`end.json` loader: trigger day, radius, y, simpleDragonAi,
  allowElytra, crystalRespawn), `network/S2CEndCrashPayload.java`,
  `docs/plans_v3/langdrop/W1.8.json`.
- **Files (modify)**: `data/minecraft/dimension_type/overworld.json` (height 512→640,
  logical_height 640).
- **Outline**: `EndDiscService` registers a day listener (via `WorldStageService.applyDayTriggers`
  pattern — its own `DayScheduler` hook, no shared-file edit): on trigger broadcast
  `S2CEndCrashPayload` (P2 sequence), then budgeted materialization of `EndDiscGeometry`
  columns + `EndSpires` (pillars, cages, crystals as real `EndCrystal` entities, podium);
  set `endDiscMaterialized`; spawn dragon via `EclipseDragonFight.begin(server)`
  (`EnderDragon` + `setFightOrigin`, ServerBossEvent, crystal-tracking, phase watchdog +
  `simpleDragonAi` fallback per D12); on death: egg, portal blocks in podium (portal tick
  handler teleports to sanctum), fire `EclipseDragonFight.Listener` (P2/P4 seam), persist flag;
  2 end cities via pending-site registration (`VanillaLandmarks` helper) with elytra stripped
  from loot when `allowElytra=false` (post-place chest scan).
- **Acceptance**: trigger day → disc appears above center with pillars/crystals/chorus; dragon
  circles the disc, perches on podium, takes crystal heals, is killable; boss bar correct; egg
  + portal appear; portal teleports to sanctum; end cities present, loot elytra-free by
  default; fight state survives restart (re-attach or respawn per saved phase); world height
  464 confirmed.
- **Model**: FABLE. **Size**: L.

### W1.9 — Per-save freeze, config plumbing, fog storms, radii rebalance
- **Goal**: D8 + D9 + fog-storm placement/loot (req 14) + DiscMapData per-save load.
- **Files (modify)**: `worldgen/DiscMapData.java`, `core/config/EclipseConfig.java`,
  `worldgen/StageRadii.java`, `worldgen/WorldStageAccess.java`.
- **Files (create)**: `worldgen/FrozenParams.java`, `worldgen/fog/FogStormSites.java`,
  `worldgen/fog/StormLootData.java`, `network/S2CFogStormPayload.java`,
  `data/eclipse/loot_table/fog_storm/storm_cache.json`,
  `docs/plans_v3/langdrop/W1.9.json`.
- **Outline**: `FrozenParams` per D9 (`ServerAboutToStartEvent` load/freeze from
  `world/eclipse/worldgen.json`, volatile context, `mapSeed()`, `stageRadii(profile)`,
  `annulusBand(r)`, `breachOpen()/endDiscMaterialized()` mirrors of `EclipseWorldgenState`
  flags cached for worker threads, `refreeze(section)`); `DiscMapData` load order: frozen copy
  → global file → `DiscMapDefaults` (W1.4 seam), instance reset on server stop (bug fix);
  `StageRadii`/`WorldStageAccess` initialized from FrozenParams; `EclipseConfig`: new default
  stage radii per D8 table, `randomizeMapSeed` general flag, calls `OreConfig.reload`,
  `EndConfig.reload`, `GrowthPacing.reload` from `reload()` (seam signatures §3.10);
  fog storms: `fogstorms.json` frozen config (2–3 sites: default auto-picked stage-3 annulus
  positions w/ spacing, editable), `FogStormSites` registers pending sites (W1.6 registry) that
  SitePrep-place a storm-scarred grove (mud/podzol accents, lightning rods, ruined camp) with
  3 loot chests from `StormLootData` (chest index persisted in `EclipseWorldgenState`;
  API `setChestLoot(siteId, idx, lootTable)`, `reload()` — P5 command seam), broadcasts
  `S2CFogStormPayload {siteId, center, radius, active}` for P2 fog/lightning visuals; loot
  table includes Mending book + `eclipse:replant` enchanted book placeholder id (enchantment
  registered by P4; loot entry uses raw id + `_p4_hook` comment, validated-if-present).
- **Acceptance**: two saves with `randomizeMapSeed=true` differ; editing global stages.json
  does NOT change an existing save (frozen), `/eclipse-worldgen refreeze stages` does;
  new radii defaults active on fresh saves incl. scar/ore bands; fog sites materialize at
  stage 3 with chests + payload; `StormLootData.setChestLoot` swaps loot live; all existing
  `/eclipse reload` behavior intact.
- **Model**: FABLE (freeze semantics are subtle). **Size**: L.

### 3.10 Compile seam contracts (all workers code against these exact signatures)

```java
// W1.1 exposes:
dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline.runOnLiveChunk(ServerLevel level, LevelChunk chunk)
DiscGenPipeline.registerExtraDecor(DiscProfile profile, ExtraDecor decor)
//   interface ExtraDecor { void decorate(WorldGenLevel level, ChunkAccess chunk); }
//   runs after vanilla decoration on both chunkgen and live-chunk paths (W1.7 registers
//   NetherUndersideDecor here at @EventBusSubscriber setup time)
// W1.2 exposes (unchanged pure API + new):
DiscTerrainFunction.column(DiscProfile, int x, int z, int stage, DiscMapData)  // stable
DiscTerrainFunction.surfaceY(DiscProfile, int x, int z)                        // stable
worldgen.EndDiscGeometry.contains(int x, int y, int z) / stateAt(...)
worldgen.BreachGeometry.contains(int x, int z) / carveAt(int x, int y, int z)
// W1.3 exposes:
worldgen.ore.OreField.oreAt(DiscProfile p, int x, int y, int z, boolean deepslate) -> BlockState|null
worldgen.ore.OreConfig.reload(java.nio.file.Path configDir)
worldgen.ore.OreGateApi.{unlockedInBand(int), unlockStageOf(String), bandAt(DiscProfile, BlockPos)}
// W1.4 exposes:
worldgen.DiscMapDefaults.{overworldDefaults(), netherDefaults()} -> DiscMapData.MapProfile
worldgen.CaveBiomeMap.at(int x, int y, int z) -> ResourceLocation
// W1.5 exposes:
core.state.EclipseWorldgenState.get(MinecraftServer)  // typed accessors: pendingStructures(),
//   newRings(), breachOpen()/setBreachOpen(), endDiscMaterialized()/set..., fogChests()
worldgen.stage.NewRingRegistry.{isFreshRing(ServerLevel, BlockPos), freshness(...), sampleFreshPositions(ServerLevel, int)}
worldgen.stage.GrowthPacing.reload(Path configDir)   // owns worldgen_tuning.json incl. features.deny
// W1.6 exposes:
worldgen.structure.StructurePendingRegistry.{enqueue(PendingSite), trigger(String siteId), addListener(...)}
worldgen.structure.VanillaLandmarks.{locateSites(), placeVanilla(ServerLevel, ResourceLocation, BlockPos, SitePrep.Mode)}
worldgen.structure.SitePrep.Mode { PLATEAU, CAVITY }
// W1.8 exposes:
worldgen.end.EndConfig.reload(Path configDir)
// W1.9 exposes:
worldgen.FrozenParams.{current(), mapSeed(), stageRadii(DiscProfile), annulusBand(double r),
  breachOpen(), endDiscMaterialized(), refreeze(String section)}
worldgen.fog.StormLootData.{setChestLoot(String siteId, int idx, ResourceLocation table), reload()}
```

### Orchestrator wiring (P1 does NOT edit these; integrate at merge)
- `EclipseMod.java`: `PaleGardenBlocks.register(modEventBus);` (W1.4). All new services use
  `@EventBusSubscriber` — no further mod-class lines.
- `network/EclipsePayloads.java`: register `S2CGrowthWavePayload`, `S2CStructureRiftPayload`,
  `S2CBreachPayload`, `S2CEndCrashPayload`, `S2CFogStormPayload` (client handlers are P2's).
- New command class (single file, any worker slot may host it if orchestrator prefers, else
  P5): `/eclipse-worldgen {ores reload | refreeze <section> | seedmobs <radius> | structures
  trigger <siteId> | endspawn | breachopen}` — thin calls into the seams above.
- Lang merge from `docs/plans_v3/langdrop/W1.*.json`.

---

## 4. INTERFACES TO OTHER PLANNERS

**P2 (visuals/sequences)**
- `S2CGrowthWavePayload` (fields in D11) every 5 ticks during animated sweeps + guarantee:
  chunk resend only ≥ `revealDelayTicks` after its wavefront. Shake via existing
  `S2CShakePayload` pulses (`growth.shakeEveryRings`).
- `S2CStructureRiftPayload {siteId, structureId, anchor, footprint}` on pending;
  P2 calls `StructurePendingRegistry.trigger(siteId)` when the rift animation lands (auto
  fallback after `structure_phase.auto_delay_ticks`).
- `S2CBreachPayload {center, radius, phase∈{QUAKE,OPEN,SETTLED}}`; smoke/ember columns are P2.
- `S2CEndCrashPayload {center, radius, y, timelineTicks}` before materialization; end-sky/fog
  shader bounds via the same payload (disc geometry constants included).
- `S2CFogStormPayload {siteId, center, radius, active}`; fog wall + lightning visuals P2.
- Existing `S2CStagePayload`/`S2CQuasarPayload` unchanged.

**P4 (progression/mechanics)**
- `OreGateApi` (W1.3): day↔stage mapping stays in `stages.json` triggers; P4 reads
  `unlockStageOf(oreId)` for goal/UI text and ModGate coupling (mod ores: `requiredMod` +
  `unlockStage` — P4's modgate unlock day should match; single source = `ores.json`).
- `NewRingRegistry` (W1.5): `isFreshRing`/`freshness`/`sampleFreshPositions` for glitched-mob
  spawn rules; freshness decay knob `glitch.freshTicks` in `worldgen_tuning.json`.
- `eclipse:replant` enchantment registration is P4's; W1.9's storm loot references the id and
  degrades gracefully if absent.
- `EclipseDragonFight.Listener` (dragon death → unlocks/credits).

**P5 (devtools/commands)**
- Per-save layout: `world/<save>/eclipse/worldgen.json` (frozen params), stage snapshots
  unchanged. `FrozenParams.refreeze(section)` is the API your commands call; sections:
  `map|stages|ores|end|fogstorms|all`.
- `StormLootData.setChestLoot/reload` for loot-editing commands; chest index in
  `EclipseWorldgenState.fogChests()`.
- StageIO compatibility notes: sweeps now rewrite whole chunks + replay decoration — snapshot
  SAVE format unchanged (blocks are blocks); snapshot LOAD must keep skipping pipeline replay
  (blocks already final) and must not register new-ring flags. `startRebuild` already bypasses
  both (W1.5 acceptance).
- `/eclipse-worldgen` command surface listed in §3 wiring — thin, safe to own/extend.

**P6 (mobs/content)**
- `dungeons.json` (W1.6 `DungeonSpawners`): `{"collapsed_vault": {"spawners": ["eclipse:<mob>",
  …]}, "umbral_warrens": {…}}` — drop your mob ids; spawner blocks re-read on reload.
- `fogstorms.json` sites carry `"mobSet": ["eclipse:<mob>", …]` — P6's storm-mob spawner reads
  via `FogStormSites.sites()` (public accessor, includes center/radius/active).
- Pale Garden: biome JSON `"spawners"` hook for the creaking-like mob (biome modifier
  recommended so W1.4's file stays untouched); pale wood **blocks** are provided by W1.4
  (`registry/PaleGardenBlocks`) — P6 only brings the mob.
- Glitched mobs: use P4's rules on top of `NewRingRegistry` (same API as above).

---

## 5. RISKS & FALLBACKS

| Risk | Likelihood | Fallback |
|---|---|---|
| `CarvingContext` internals resist standalone construction (needs `NoiseChunk`) | medium | `DiscCarverEngine` ships its own worm+canyon carver port (same configs, own math) — API identical to W1.1's engine entry, rest of plan unaffected |
| Decoration replay on live chunks triggers physics cascades (gravel, water) | low | place with update-flag discipline (2\|16) + post-pass fluid tick scheduling like `fillFromNoise` already does; worst case restrict replay to section-buffered writes then swap |
| Vanilla dragon phases misbehave outside the End | medium | `end.simpleDragonAi=true` watchdog forces circle/strafe/perch-scripted loop (still a real EnderDragon; fight stays playable) |
| Dimension height bump breaks existing dev saves | accepted | event targets fresh saves; document; old saves load (empty new sections), no corruption expected |
| Full-chunk rewrite + replay blows the sweep tick budget | medium | replay work is chunk-finish-bounded (≤4/tick) and measured; knobs: lower chunk finishes/tick, raise `targetTicks`; worst case decoration replay deferred to a follow-up budgeted queue after the sweep |
| Mineshaft/mansion runtime generation cost spikes | low | pending-registry places ≤1 site per N ticks (config), SitePrep is budgeted |
| 3-D biome lookups (surfaceY calls) slow chunkgen | low | per-quart memoization inside `CaveBiomeMap`; BiomeManager already caches; profile in W1.4 acceptance |
| Feature seed wrapping misses a code path (`getSeed()` used elsewhere) | low | acceptance test compares two saves; if variance found, extend `FixedSeedGenRegion` delegation |
| Breach fall transfer feels janky (chunk load latency on arrival) | medium | pre-ticket arrival chunks when a player enters the crater radius; slow-fall grace covers hitches |
| Cross-worker merge conflicts on shared concepts | — | file ownership matrix is disjoint (§3); all cross-calls via §3.10 signatures; orchestrator wiring list is exhaustive |
| `annulusBand` freeze vs. old saves created pre-overhaul | low | `FrozenParams` falls back to legacy constants when `worldgen.json` absent AND world has committed stages (detected via `EclipseWorldState`), preserving old dev worlds |

---

## Appendix A — biome→wedge/ring default table (W1.4 authoring reference)

wedge 0 plains: r<150 plains · 150–280 sunflower_plains · >280 **eclipse:pale_garden**
wedge 1 desert: desert · badlands · wooded_badlands (+ trial_chambers under mid ring)
wedge 2 forest: forest · birch_forest · old_growth_birch_forest
wedge 3 jungle: jungle · sparse_jungle · bamboo_jungle
wedge 4 savanna: savanna · savanna_plateau · windswept_savanna (outpost mid ring)
wedge 5 swamp: swamp · mangrove_swamp · swamp
wedge 6 snowy: snowy_slopes · grove · snowy_taiga + ice_spikes patch
wedge 7 dark_forest: dark_forest · taiga · old_growth_pine_taiga (mansion outer ring)
mountain: core snowy_slopes/jagged_peaks(>y200) · flank grove + cherry_grove + meadow ring
center cap: plains (sanctum). rivers: minecraft:river ribbon. detached shards (stage 4+):
mushroom_fields. underground: dripstone_caves/lush_caves noise regions; deep_dark r<120 @ y<−96.
nether wedges (5): unchanged ids; features/mobs via D1.

## Appendix B — new/changed config & data files

| File | Owner | Notes |
|---|---|---|
| `config/eclipse/ores.json` | W1.3 | frozen per save |
| `config/eclipse/worldgen_tuning.json` | W1.5 | growth pacing, features.deny, glitch.freshTicks — live-reloadable |
| `config/eclipse/end.json` | W1.8 | frozen per save |
| `config/eclipse/fogstorms.json` | W1.9 | frozen per save |
| `config/eclipse/dungeons.json` | W1.6 | live-reloadable (P6 mob ids) |
| `config/eclipse/stages.json` | W1.9 (defaults) | new radii D8; frozen per save |
| `world/<save>/eclipse/worldgen.json` | W1.9 | the freeze |
| `data/minecraft/dimension_type/overworld.json` | W1.8 | height 640 |
