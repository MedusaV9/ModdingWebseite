# Collector #1 — World & Terrain (Disc World)

## Recommended architecture (decision up front)

**One deterministic terrain function, two consumers.** A hand-authored `DiscMapData` (painted PNG control maps + JSON landmark list, fixed seed constant) is sampled by a pure function `DiscTerrainFunction.stateAt(dim, x, y, z, stage)`. Consumer 1 is a custom `DiscChunkGenerator` (registered codec, referenced from `data/minecraft/dimension/overworld.json` and `the_nether.json`) that generates any chunk *up to the currently committed stage radius*. Consumer 2 is a runtime `RingGrowthService` that animates fusion/expansion by writing the *same* function's output into already-generated chunks, batched per tick. Rejected alternative: pre-generate the full disc and hide locked rings behind barrier/structure-void swaps — doubles block writes, leaks map info, and still needs mass live writes for the "watch it grow" animation. One function, one code path, idempotent by construction — which is what the dev stage-load/revert tooling needs.

Disc geometry (radii in blocks from origin 0,0 = spawn + altar):

| Stage | Overworld radius | Content |
|---|---|---|
| 0 (pre-intro) | main disc r=96 + per-team discs r=24 on ring r=170 | spawn, altar, player starts |
| 1 (intro fusion) | fused disc r=225 (450 diameter) | gap annulus fills live |
| 2 | r=300 | desert sector + desert temple |
| 3 | r=360 | jungle sector + jungle temple |
| 4 | r=420 | plains village |
| 5 (final day) | r=480 | stronghold materializes under the mountain |

Thickness: lens profile, 200 at center tapering to 150 at rim ("fat coin"), bedrock cap on the bottom 3 layers, underside hangs at ~y −130, surface ~y 65–90 (mountain to 280).

## A) Research findings

- **Custom ChunkGenerator NeoForge 1.21.1** [MUST, 3]: subclass `net.minecraft.world.level.chunk.ChunkGenerator`, `MapCodec<DiscChunkGenerator>` via `codec()`, register with `DeferredRegister` on `Registries.CHUNK_GENERATOR` (id `eclipse:disc`). Reference as `"generator": {"type": "eclipse:disc", ...}` in `data/minecraft/dimension/overworld.json`. Dimension JSONs re-read from datapacks each server start → overrides overworld generator for new AND existing worlds (existing chunks kept — exploited). Hardcoded `ECLIPSE_SEED` constant = hand-prepared guarantee (do NOT use `neoforge:use_server_seed`).
- **Dimension height** [MUST, 1]: override `data/minecraft/dimension_type/overworld.json`: `min_y: -176, height: 512` → build range −176…336 (mountain 280, disc underside). min_y change corrupts existing worlds → event world must start fresh (fine, curated map).
- **Noise/density JSON vs programmatic**: programmatic `fillFromNoise` writing `LevelChunkSection`s directly wins for curated stage-aware map. Implement `getBaseHeight`/`getBaseColumn` from same function so structure placement + spawn selection work.
- **Prior art — Chunk By Chunk**: batching model = ~8 y-layers of one chunk per tick writing sections directly, one chunk in flight, then relight + resend. Confirms live mass placement viable.

## B) Disc generator design

**`DiscChunkGenerator` [MUST, 4]** — package `dev.projecteclipse.eclipse.worldgen`. `fillFromNoise`: per column compute `r = sqrt(x²+z²)`; outside `stageRadius(stage)` (+ stage-0 per-disc shapes) → air. Else fill from `DiscTerrainFunction`:

1. **Radius falloff**: rim `edgeNoise = simplex(angle*6) * 8` + smoothstep over last 12 blocks → crumbling rim with overhangs.
2. **Thickness**: `bottomY(r) = centerBottom + (rimBottom − centerBottom) * (r/R)²` (lens). Bottom 3 layers bedrock [MUST]. Underside deepslate "stalactite fringe" via 2D noise.
3. **Surface**: `surfaceY(x,z)` bilinear from authored 1024×1024 heightmap PNG (1px=1block, covers r=480 + margin) + fixed-seed simplex detail (±3).
4. **Biomes per angular sector** [MUST, 3]: custom `DiscBiomeSource extends BiomeSource` (codec on `Registries.BIOME_SOURCE`) reading authored indexed-palette biome PNG. Layout: center alpine/meadow (mountain), pie sectors — forest (spawn approach), desert (SE), jungle (SW), savanna, snowy slopes (N mountain face), swamp, dark forest.
5. **Rivers** [SHOULD, 2]: painted as reserved palette index; carve to `surfaceY−4`, water fill, run off rim (void waterfalls).
6. **Caves** [MUST, 3]: deterministic Perlin-worm carving in `applyCarvers` (fixed seed) + 3–4 authored set-piece caverns from landmark JSON. Clamp ≥4 blocks from underside.
7. **Ores** [MUST, 2]: ring-budgeted deterministic veins — each stage annulus has explicit ore budget in `stages.json` (e.g. stage-1: 400 iron, 90 gold, 40 diamond deep-central), hashed-position veins. Diamonds only below y −40, biased to center → contested.
8. **Giant mountain** [SHOULD, 3]: painted on heightmap, peak y≈280 off-center; hollow lava-lit core chamber reserved for stronghold finale.

**Generation vs runtime — decision**: chunkgen handles never-generated chunks (consults `EclipseWorldState.getStage(dim)`); **animated path is runtime placement** (chunks near players already generated). Volume: stage 1→2 annulus ≈ 21M blocks ≈ 780 chunk-columns. **Batching [MUST, 4]**: `RingGrowthService` one chunk-column per tick — write into `LevelChunkSection.setBlockState(..., false)`, `Heightmap.primeHeightmaps`, `ThreadedLevelLightEngine.relight(Set.of(chunkPos))`, resend `ClientboundLevelChunkWithLightPacket`. ~780 ticks ≈ 40s per expansion; order columns as **angular ring sweep** (radius then angle) → wave of land racing around circumference. Adaptive throttle: skip when MSPT > 40. Garnish leading edge with rising BlockDisplays + purple_wisp particles.

## C) Stage system

**`config/eclipse/stages.json` [MUST, 2]** (separate timeline from days):

```json
{ "overworld": [
  { "stage": 1, "radius": 225, "trigger": "intro_fusion", "structures": [] },
  { "stage": 2, "radius": 300, "trigger": "milestone", "structures": ["eclipse:desert_temple"], "oreBudget": {"iron": 400, "diamond": 40} },
  { "stage": 5, "radius": 480, "trigger": "final_day", "structures": ["eclipse:stronghold_emergence"] } ],
  "nether": [ { "stage": 1, "radius": 80, "trigger": "day:2", "structures": ["eclipse:fortress_core"] } ] }
```

**State [MUST, 1]**: `worldStageOverworld` / `worldStageNether` + `growthCursor` (resume mid-animation after restart) in `EclipseWorldState`. `WorldStageService.setStage(server, dim, n, animate)` single entry point.

**Intro fusion [MUST, 3]**: `FusionSequence` = special stage-1 sweep. Precompute void columns within r=225; order by *distance to nearest existing disc edge* → land grows outward from main disc and inward from player discs simultaneously, meeting in middle. Runs after `StartEventCutscene` teleport, ~60–90s, rumble + shake via `S2CCutscenePayload`.

**Dev stage tooling [MUST, 3]**: `/eclipse stage get`, `/eclipse stage set <dim> <n> [instant|animate]` (lower → `RingGrowthService` erase mode: air beyond new radius — idempotent revert), `/eclipse stage rebuild <dim> <n>` (re-stamp annulus). **Pristine snapshots [SHOULD, 3]**: `/eclipse stage snapshot save|restore <name>` — flush chunks (`ServerChunkCache.save(true)`), copy `region/ entities/ poi/` to `<world>/eclipse/stage_snapshots/<name>/`; restore = marker file applied at `ServerAboutToStartEvent` (requires restart, fine for dev).

## D) Nether disc (Day 2)

Same `DiscChunkGenerator`, nether `DiscProfile` via `data/minecraft/dimension/the_nether.json` [MUST, 2]. Disc center y 32–160, thickness ~120, netherrack/blackstone palette, soul-sand + basalt sectors, **lava moat ring** at r=50 with two natural bridges, glowstone stalactite fringe. Stages: N1 r=80 at `day:2` (DayScheduler hook applies `"day:N"` triggers), N2 r=120 (bastion-style treasury), N3 r=160 (quartz ring + warped forest). **Fortress core** [MUST]: curated fortress at N1, central bridge spans moat — blazes gated behind crossing. Portal: coordinate_scale 8 maps r=480 → r=60 (inside N1) — no special handling.

## E) Structure placement

**`StructureStamper` [MUST, 3]**: (1) *Template stamping* for compact set-pieces: `.nbt` in `data/eclipse/structure/`, `StructureTemplateManager.getOrCreate` + `placeInWorld` — desert temple (curated loot), jungle temple, landmarks. (2) *Programmatic generation* for sprawling: replicate `/place structure` internals — `Structure.generate(...)` then place `StructureStart` pieces — `minecraft:village_plains` (flat painted plaza needed), `minecraft:stronghold` (guarantees portal room). Structures run after ring terrain sweep.

**Stronghold finale [MUST, 4]**: pre-carve sealed cavity in mountain core at chunkgen. Final day: quake sounds, fissure trench opens down mountainside (scripted column edits), purple beam, stronghold generates into cavity, portal room aligned under altar axis — frames WITHOUT eyes.

**Custom landmarks**: Eclipse Observatory on mountain shoulder (telescope at purple sun); toppled bell tower half-buried at desert boundary; obsidian "watcher statues" at former player-disc centers appearing after fusion.

## F) Creative ideas

1. **Rim waterfalls into void** [SHOULD, 2] — painted rivers end at rim.
2. **Ring scars** [SHOULD, 1] — each expansion boundary = 1-block tinted deepslate seam + sparse amethyst; map growth readable like tree rings.
3. **Buried titan skeleton** [SHOULD, 2] — bone ribcage in desert; heart cavity hides a heart_fragment.
4. **Whisper wells** [SHOULD, 2] — 3 deep shafts to underside; at bottom: ambient cave sounds + anonymous paranoia chat messages styled like another player's whisper (never names).
5. **Underside barnacle vault** [NICE, 3] — dungeon hanging under disc above bedrock; only Notch apple.
6. **Ghost-ship figurehead on beach** [NICE, 1] — foreshadows Limbo.
7. **Sundial plaza at spawn** [SHOULD, 2] — 24-block dial around altar; basalt shadow line moves each day (~40 blocks rewritten by DayScheduler).
8. **Abandoned research camp** [NICE, 1] — tents, shattered "worldborder projector", lore lecterns.
9. **The Drowned Bell** [NICE, 2] — submerged bell; ringing plays global day-change bell to all (psyops).
10. **Watcher statues** [SHOULD, 2] — post-fusion obsidian statues at team disc centers facing altar.
11. **Stronghold emergence quake** [MUST, 3] — finale set-piece.
12. **Nether moat duel bridge** [SHOULD, 2] — 3-wide no-rail bridges = PvP chokepoint.
13. **Hollow-core rumors** [NICE, 1] — sealed cavity + faint ambient.cave loops from day 1.

**MUST backbone**: DiscChunkGenerator + DiscBiomeSource + DiscMapData (PNG+JSON), DiscTerrainFunction, RingGrowthService (sweep + erase), WorldStageService + stages.json + EclipseWorldState fields, StructureStamper, dimension JSONs (overworld, the_nether, raised dimension_type), /eclipse stage commands, fusion sequence, nether N1 + fortress, stronghold finale.
