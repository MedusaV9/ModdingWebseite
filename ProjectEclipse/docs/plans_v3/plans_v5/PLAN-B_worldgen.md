# PLAN-B — Worldgen (plans_v5)

PLANNER-B worker packages. Scope: WORLDGEN items from the v5 playtest feedback round.
Every package was root-caused against the actual code (files + symbols cited per
package). Ownership is disjoint: **no two packages edit the same file**; cross-package
and cross-planner seams are called out explicitly. Package numbers match the user's
item numbers 1:1 (B11 is folded into B6 because both own `DiscTerrainFunction.java`).

Conventions (same as PLAN-D):

- **Effort** — S (≤ 3 files / < 1 focused session), M (4–10 files), L (> 10 files or
  new package + client payloads + gametests).
- All paths are relative to `src/main/java/dev/projecteclipse/eclipse/` unless noted.
- All new `/dev` commands MUST register `DevCommandDoc` entries in
  `devtools/dev/DevCommandRegistry` (static initializer, see `DevContractCommands`).
- Every worldgen change MUST stay a pure function of frozen per-save data
  (`FrozenParams.mapSeed()`, `DiscMapData`) — never the world seed or live stage —
  so chunkgen and the `RingGrowthService` sweep replay stay byte-identical.

---

## B1 — Mountain snowline: high-altitude snow/ice must persist (item 1)

**Root cause.** `worldgen/DiscBiomeSource.java`: the only altitude-aware biome rule on
the mountain is `jaggedCore && by > JAGGED_PEAKS_MIN_Y` (y > 200, and only inside the
core disc `r < mountain.radius() * 0.45`). Everything else on the mountain keeps its
2-D biome at ALL altitudes: the flank ring (`0.45R..0.8R`) resolves via
`DiscMapDefaults.flankBiome` to meadow / cherry-grove thirds, and terraces beyond
`0.8R` read the warm wedge biome. Meadow/cherry grove have vanilla temperature 0.5:
`freeze_top_layer` (which the mod deliberately relies on for snow layers/ice — see the
`DiscTerrainFunction` header, "snow LAYERS now come from vanilla's freeze_top_layer")
only freezes where `Biome#coldEnoughToSnow` is true, weather drops RAIN instead of
snow up there, and gen-time ice on high river/pool columns sits in a warm biome and
reverts to flowing water when disturbed — the observed "melting snow + water running
down the mountain". The hand-placed `snowCap`/`iceCascade` blocks in
`DiscTerrainFunction` are snow BLOCKS / packed ice (non-melting) and are not the
problem; the biome-driven layer around them is.

**Fix.**

1. `DiscBiomeSource`: add an altitude snowline overlay for the whole mountain
   footprint (not just the core). In `resolveColumn`, when the column is inside
   `mountain.radius()` compute `surfaceY` (already available) and classify:
   - `surfaceY ≥ 200` (or `by > 200` in `getNoiseBiome`) → `minecraft:jagged_peaks`
     (existing rule, keep);
   - `surfaceY` in `[SNOWLINE_Y .. 200)` → `minecraft:snowy_slopes` (temp −0.3,
     freeze_top_layer covers everything, rain falls as snow);
   - `SNOWLINE_Y` recommended 152 — just above the terrace-quantization start
     (y 150 in `DiscTerrainFunction.computeSurfaceY`), so the stepped cliff bands read
     snowy. Resolve the two new holders in the constructor next to `jaggedHolder`
     (they are already in `DiscMapDefaults.allBiomeIds` or must be added there).
2. Make the overlay **y-aware, not just column-aware** (mirror the jagged rule): a
   sample at `by ≥ SNOWLINE_Y` inside the mountain radius reads the snowy biome, so
   vertical cliff faces and the frozen cascade sides freeze consistently.
3. `DiscMapDefaults`: add `minecraft:snowy_slopes` (and `minecraft:grove` if used) to
   `allBiomeIds`, and lower the flank-third table so `flankBiome` can never return a
   warm biome above the snowline (belt + braces; the overlay in (1) already outranks).

**Why this is safe:** biomes are baked at chunkgen and the lookup stays a pure
function of frozen map data + deterministic `surfaceY`, honoring the class contract.

**Files:** `worldgen/DiscBiomeSource.java`, `worldgen/DiscMapDefaults.java`.
**Effort:** S.

---

## B2 — Ores: vanilla-shaped VEINS instead of blobs (item 2)

**Root cause.** `worldgen/ore/OreField.java` `tryOre`: membership test
`dx*dx + dy*dy*1.6 + dz*dz <= radius*radius` — a squashed ellipsoid per 16³ cell =
the "blob" the user sees. Vanilla `OreFeature.doPlace` instead walks a short line
segment with sine-modulated ellipsoid bulges along it (the classic snake vein).
`worldgen/ore/VeinTracker.java` mirrors the exact same formula ("keep in lockstep")
for mining feedback. Vanilla ore features can't fire because
`worldgen/vanilla/BiomeFeatureFilter.java` deny-lists them (`VANILLA_ORE_DENY`).

**Fix (primary — keeps the per-block pure-function architecture).** Reimplement
vanilla's vein SHAPE deterministically inside `OreField`:

1. Per cell, derive from the existing cell hash (salt `17 + ore.salt()`): a segment —
   two endpoints around the cell center (`length ≈ size/8 * 2` blocks, random pitch ≤
   ~±30°) — plus per-step sine bulge radii exactly like `OreFeature.doPlace` computes
   (`d0..d7` endpoints, per-i ellipsoid centers `(d0 + (d3-d0) * i/size, ...)` with
   radius `(sin(π·i/size)+1) * rand * size/16 + 0.5) / 2`).
2. `oreAt` membership: test the block against the precomputed ellipsoid chain
   (≤ `size` spheres; cache the chain per cell in a small per-thread direct-mapped
   cache like `DiscBiomeSource.ColumnCache` — the chain is reused for all ~4096
   lookups of a cell).
3. Take vein `size`/count/Y-distribution per ore from vanilla's `OreConfiguration`
   values (coal 17, iron 9, gold 9, redstone 8, diamond 4/8, copper 10/20, lapis 7 —
   read them into `OreConfig` defaults) so density and vein caliber match vanilla 1:1.
4. Rewrite `VeinTracker` to the same chain derivation (it stays in lockstep by
   construction — extract the shared chain math into a package-private
   `OreVeinShape` helper INSIDE `worldgen/ore/` so both files call one function).
5. `OreGateApi` stays untouched — the progression gate keeps operating on the same
   ids; only the shape generator under it changes.

**Alternative (rejected for now):** un-deny vanilla ore features in
`BiomeFeatureFilter` and delete the `OreField.oreAt` call — true 1:1, but the call
site is `DiscTerrainFunction.stateInColumn` (line ~653), which package B6 owns, and
runtime ring-sweep replay would double-place ores on regrown chunks unless the
decoration replay is made ore-aware. Only pick this if the primary shape port fails
review; the one-line `DiscTerrainFunction` deletion then goes through B6's owner.

**Files:** `worldgen/ore/OreField.java`, `worldgen/ore/VeinTracker.java`,
`worldgen/ore/OreConfig.java`, new `worldgen/ore/OreVeinShape.java`.
**Effort:** M.

---

## B3 — Structures: no more giant AIR bubble (cavity carve must hug pieces) (item 3)

**Root cause.** `worldgen/structure/SitePrep.java` `prepareCavity` carves the
**entire union bounding box** of all pieces (`boundsMin/Max ± CAVITY_PAD = 3`) to
cave air before placement. Trial Chambers / Ancient City piece sets fill only a
fraction of their union box (sprawling jigsaw arms), so the rest of the box remains a
huge open-air cavern around the structure — exactly the user's "open-air structures".

**Fix.**

1. Add `prepareCavity(level, profile, List<BoundingBox> pieceBoxes, BlockPos anchor)`
   overload: carve the UNION OF PER-PIECE ENVELOPES (each piece box + `CAVITY_PAD`)
   instead of the outer union box. Implementation: keep the same resumable
   `CavityWork` slice walker over the outer box, but test each (x,y,z) against the
   padded piece boxes (sort boxes into a per-chunk-column index first — ≤ a few
   hundred boxes, cheap) and skip blocks outside every envelope.
2. Keep the floor pad + the collared access shaft exactly as today (they anchor to
   the anchor column, not the union box).
3. Keep the legacy whole-box signature delegating to a single-box list so existing
   callers compile; **B4's owner** switches `VanillaLandmarks.placeVanillaAsync` to
   pass `start.getPieces()` boxes (one-line seam, called out in B4).
4. `StructureStamper.placeCavity` sites (mountain Ancient City) get the same
   treatment through the same overload — but `StructureStamper.java` is owned by
   B15; the call-site swap there is a one-line seam executed by B15's worker.

**Files:** `worldgen/structure/SitePrep.java` (sole owner).
**Effort:** M.

---

## B4 — Villages in the air: surface snap vs. plateau ordering (item 4)

**Root cause.** `worldgen/structure/VanillaLandmarks.placeVanillaAsync` runs
`Structure.generate` (which Y-snaps the jigsaw start + roads against the LIVE
heightmaps of the *natural, pre-plateau* terrain) **before**
`SitePrep.preparePlateau` terraforms the footprint flat at `anchor.getY()`. Modern
jigsaw villages get no per-piece ground snap at placement (that only applies to
`ScatteredFeaturePiece`; vanilla villages rely on noise-gen "beard/bury" terrain
adaptation, which this runtime placement path has none of). Result: pieces keep Y
values from the old slope; wherever the plateau ends up lower than the pre-plateau
heightmap, houses float in the air (`PLATEAU` comment "they ground-snap against the
heightmaps SitePrep just re-primed" is wrong for jigsaw pieces).

**Fix (in `VanillaLandmarks.placeVanillaAsync`, PLATEAU branch):**

1. Compute the deterministic plateau height FIRST:
   `plateauY = DiscTerrainFunction.surfaceY(profile, anchor.getX(), anchor.getZ())`
   (this is what `preparePlateau` will build — it targets `anchor.getY()`, and the
   stamper's `surfaceAnchor` already sets anchor Y from the same function).
2. After `Structure.generate`, measure the start's generated ground reference:
   `groundY = bounds.minY()` for the start piece (or the piece-union min of
   ground-level pieces), and vertically translate ALL pieces by
   `dy = plateauY - groundY` — the same `piece.move(...)` loop the CAVITY branch
   already uses, vertical-only.
3. Optionally per-piece refinement: after prep, re-snap each ground-level piece to
   `prepared.groundY(pieceCenterX, pieceCenterZ)` (the smoothstep skirt height), so
   pieces on the skirt don't hover over the blend. Cap per-piece delta at ±3 to
   avoid tearing streets apart.
4. Execute B3's seam: pass per-piece boxes into the new `SitePrep.prepareCavity`
   overload in the CAVITY branch.
5. Execute B15's seam: delete the
   `stronghold → eclipse:stronghold_emergence` row from `LOCATE_SITES`.

**Files:** `worldgen/structure/VanillaLandmarks.java` (sole owner).
**Effort:** S–M.

---

## B5 — Normal mobs don't spawn enough on the disc (item 5)

**Root cause (multi-factor; instrument first, then fix).** Verified in code:

- Chunk-gen animal seeding IS wired: `DiscChunkGenerator.spawnOriginalMobs` →
  `DiscGenPipeline.seedMobs` → `NaturalSpawner.spawnMobsForChunkGeneration` (fixed
  seed), same biome sampling as vanilla. Not the bug.
- Dimension jsons use the vanilla dimension types (`minecraft:overworld` /
  `minecraft:the_nether` in `data/minecraft/dimension/*.json`), so
  `monster_spawn_light_level` etc. are vanilla. Not the bug.
- **Y-dilution (main suspect):** vanilla's runtime spawn cycle picks a random Y in
  `[minBuildHeight, WORLD_SURFACE_top]` per attempt (`NaturalSpawner
  .getRandomPosWithin`). On the floating disc a large share of that band is
  under-disc VOID (below `undersideY`), and in the nether the roof shell reaches the
  world top so the band includes the sealed roof mass — far more dead attempts per
  cycle than vanilla terrain, i.e. systematically fewer successful spawns.
- **Cap competition:** `entity/spawn/EventSpawnRules` and `entity/EclipseSpawner`
  spawn custom mobs with `MobSpawnType.NATURAL`; if their `EntityType`s are
  registered `MobCategory.MONSTER` they count against the per-player MONSTER budget
  (`LocalMobCapCalculator`), shrinking vanilla spawns near storms/fresh rings.
- `SanctumProtection.onFinalizeSpawn` only suppresses r=18 — negligible.

**Fix.**

1. New mixin `mixin/NaturalSpawnerMixin` (or wrap in an event if NeoForge exposes
   one): in disc dimensions clamp/re-roll the random spawn Y into the column band
   `[col.undersideY(), col.surfaceY() + 1]` (query `DiscTerrainFunction.column` —
   cheap, cached). Overworld: also allow the cave band. Nether: band
   `[floor surfaceY − 8, ceilingBottomY − 1]`. This restores vanilla per-cycle hit
   rates.
2. Audit `registry/EclipseEntities` categories: move ambient event mobs
   (drift lantern, fog/glitched families, sunmote…) to `MobCategory.MISC` (they are
   self-capped by their spawners — see `EventSpawnRules` caps) so they stop eating
   the MONSTER cap. Keep genuine hostiles that should count (or accept them, but
   then raise nothing — measure first).
3. Add `/dev spawn census` (extend `devtools/dev/DevSpawnCommands.java`, which B5
   owns) printing per-category mob-cap usage + last-cycle attempt/success counters
   from (1)'s instrumentation, so the fix is verifiable in-game.

**Files:** new `mixin/NaturalSpawnerMixin.java` (+ mixins json entry),
`registry/EclipseEntities.java`, `devtools/dev/DevSpawnCommands.java`,
`entity/spawn/EventSpawnRules.java` / `entity/EclipseSpawner.java` (only if census
shows their NATURAL spawns must switch to `MobSpawnType.EVENT`).
**Effort:** M.

---

## B6 — Nether floor interest + outer-terrain cliffs/hills (items 6 + 11 merged — single owner of `DiscTerrainFunction.java`)

**Root cause.** `worldgen/DiscTerrainFunction.computeSurfaceY`:

- NETHER branch: floor = `138 + large*5*relief + medium*3 + detail*2`, clamped
  100..150 — ±7-ish gentle swell, no landforms. The praised ceiling got the
  stalactite forests + lava-fall curtains; the floor only has the moat lip, sector
  top-block palettes (`SectorStyle.SOUL/BASALT/CRIMSON/WARPED`) and flat wastes.
- OVERWORLD branch: outside the mountain, relief is `large*9 + medium*4.5 + detail`
  scaled by the sector's `relief[0]` — the badlands/terracotta ring reads as low
  rolling ground; only THE mountain has drama.

**Fix (all inside the terrain function + one new decor file; stays a pure function
of frozen data as the header demands — reuse existing hash-salt discipline, next
free salt 31+).**

1. **Nether floor relief:** in the NETHER branch add sector-keyed landforms:
   - `SOUL` sectors: broad sunken valleys (−6..−10 with soft edges) — "soul valleys";
   - `BASALT` sectors: columnar terracing — quantize `s` to 3-block steps modulated
     by a cell hash, giving basalt-delta benches;
   - `WASTES`: occasional lava spring pits — small (r 3–5) depressions to y ≤ 118
     whose bottom block is LAVA + magma lip (reuse the moat-lip pattern);
   - widen the clamp to 96..156 so the forms survive.
2. **Nether floor dressing:** new `worldgen/nether/NetherFloorDecor.java` registered
   via the existing `DiscGenPipeline.registerExtraDecor` seam (exact
   `NetherCeilingDecor` pattern — no `DiscGenPipeline` edit): glowstone growth
   clusters on wastes, scattered basalt pillars 3–8 high in basalt sectors, wart-bulb
   patches + bone-block ribs in crimson/warped, fire/soul-fire sprinkles on soul
   sand. All keyed to cell hashes of `FrozenParams.mapSeed()`.
3. **Overworld outer relief (item 11):** add a `cliffiness` factor per
   `SectorStyle` (BADLANDS/terracotta high, savanna medium): where cliffiness > 0,
   blend `s` towards `floor(s / 8) * 8` weighted by a mid-frequency mask (reuse the
   mountain terrace trick at ~y150 — same code shape, lower threshold) and add a
   ridge-noise lift of up to +18 in mask cores — mesas/cuestas, deliberately below
   mountain scale. Respect landmark clearances (`nearNetherLandmark` analogue exists;
   add `nearOverworldLandmark` guard so plateaus under villages stay calm).
4. NOTE: this package is the sole owner of `DiscTerrainFunction.java` and executes
   B2's alternative one-liner ONLY if B2 escalates.

**Compat:** changing `computeSurfaceY` changes terrain for NEW saves only (frozen
saves keep their generated chunks; the ring sweep would rewrite regrown annuli —
acceptable per the stage contract, flag in the changelog).

**Files:** `worldgen/DiscTerrainFunction.java`, new
`worldgen/nether/NetherFloorDecor.java`.
**Effort:** M–L.

---

## B7 — Nether arrival: shaft spawn, fall damage, fog, lightning, pre-protection (item 7)

**Root cause.**

- **Spawned in the updraft:** `worldgen/nether/BreachBuilder.arrivalCenter()` sits
  only ~3 blocks from `updraftCenter()` (updraft is offset 3 towards the disc
  center); the arrival pad overlaps the updraft column, and
  `BreachTransferService.tickNether`'s legacy updraft boost is applied to survival
  players on drift cooldown too — fresh arrivals get shoved straight out.
- **Fall damage:** the drift applies `MobEffects.SLOW_FALLING` for
  `DRIFT_SAFETY_SLOW_FALL_TICKS = 600`; long descents outlive it, and the legacy
  (cooldown/creative) path skips the drift entirely — free fall from the breach
  mouth. `player.fallDistance = 0` is only reset at capture, not at landing.
- **No storm moment:** `BreachBuilder.openNow` only plays
  `SoundEvents.LIGHTNING_BOLT_THUNDER` — no bolt, no weather.
- **No fog at the hole**, and **no build protection** around breach or observatory
  (the only build protection in the mod is the altar cylinder in
  `SanctumProtection`; `WizardObservatory` and the breach have none).

**Fix.**

1. `BreachBuilder`: move `arrivalCenter()` to ≥ 8 blocks from `updraftCenter()`
   (outside the shaft column + 2 safety), on the disc-center side; keep the pad build.
2. `BreachTransferService`: gate the legacy updraft boost to creative/spectator only;
   during any drift, refresh SLOW_FALLING every 100t while airborne and re-zero
   `fallDistance` on the landing tick (listen for `onGround` transition within the
   drift window); extend the drift timeout so slow-fall can never expire mid-drift.
3. **Lightning on open:** in `BreachBuilder.openNow`, spawn a real
   `LightningBolt` (visual-only: `setVisualOnly(true)`) at the breach mouth + start
   a short thunder weather burst (`ServerLevel.setWeatherParameters(0, 600, true,
   true)`) — the storm moment the user asked for.
4. **Fog veil:** server-side particle curtain at the overworld hole (CAMPFIRE_COSY
   /large smoke ring, budgeted, only while players are within 64) driven from
   `BreachTransferService.tickOverworld`; optionally a client fog payload later via
   the `stormfx`/`veilfx` P2 seam (out of B7 scope, noted for P2).
5. **Pre-protection zones:** new `protection/LandmarkProtection.java` (event
   subscriber, `SanctumProtection` pattern but multi-zone, data from
   `DiscMapData.get()` landmarks): cylinder zones for `eclipse:nether_breach`
   (overworld hole + nether crater, r = landmark radius + 12) and the mountain
   summit / `eclipse:wizard_observatory` (r 24 around the summit anchor). Cancels
   break/place for non-ops from server start — i.e. BEFORE players ever reach them.
   Deliberately a NEW file so B10's `SanctumProtection` ownership stays disjoint.

**Files:** `worldgen/nether/BreachBuilder.java`,
`worldgen/nether/BreachTransferService.java`, new
`protection/LandmarkProtection.java`.
**Effort:** M.

---

## B8 — "Betrete den Nether" quest trigger (item 8)

**Root cause.** `progression/goals/GoalConfig` defines `d02_burning_door` as
`count(TriggerType.VISIT_BIOMES, "#minecraft:is_nether", 1)`. VISIT_BIOMES rides
`EclipseSignals.fireBiomeVisited`, which `analytics/AnalyticsSampler` fires **only on
the first-ever visit of each biome per player** (`AnalyticsState.markBiomeVisited`
lifetime set). Any player whose first nether-biome visit happened before the quest
was active/eligible (breach opens on day 2; scouting, deaths, or quest-window skew)
has consumed the signal forever — the quest can never complete. The signal is also
biome-based, so entering the nether into an already-visited biome id fires nothing.

**Fix.**

1. Add `TriggerType.VISIT_DIMENSION` (polling=false): fired from a new
   `QuestDetectors` subscriber on `PlayerEvent.PlayerChangedDimensionEvent`
   (target = dimension id, e.g. `minecraft:the_nether`). Fires EVERY entry, not
   lifetime-once; `QuestEngine`'s per-goal done-latch dedupes.
2. Switch `d02_burning_door` to
   `count(TriggerType.VISIT_DIMENSION, "minecraft:the_nether", 1)`.
3. Retro-heal: when the quest becomes eligible (or on login), check
   `player.level().dimension()` and complete immediately if the player is already
   in the nether (cover players standing there during the day-2 rollover).
4. Execute B15's seam here (single GoalConfig owner): replace the day-12 stronghold
   quests (`d12_stronghold`, `d12_breach`, `d12_purge` — they target the removed
   stronghold) with End-disc equivalents (locate the End disc / open the rift /
   purge endermites), keeping reward parity.

**Files:** `progression/goals/TriggerType.java`,
`progression/goals/QuestDetectors.java`, `progression/goals/GoalConfig.java`,
`progression/goals/QuestEngine.java` (retro-check helper).
**Effort:** S–M.

---

## B9 — Border: kick earlier + 5 s slow falling (item 9)

**Root cause.** `border/SoftBorder.java`: the impulse band pushes back first;
the hard teleport only engages at `dist > radius + TELEPORT_BAND` with
`TELEPORT_BAND = 3.0` — with sprint-jump/elytra momentum players visibly overshoot
("kicked too late / too close"). On teleport, `FALLBACK_SLOW_FALLING_TICKS = 60`
(3 s) is applied; the user wants 5 s.

**Fix.**

1. `FALLBACK_SLOW_FALLING_TICKS` 60 → **100** (5 s) — both application sites
   (ground-found branch and spawn-fallback branch) already share the constant.
2. `TELEPORT_BAND` 3.0 → **1.5**, and scale the pushback impulse up earlier:
   raise `IMPULSE_SCALE` so the escalation saturates within the band (target: a
   sprinting player is turned around ≤ 2 blocks past R).
3. Add a pre-band warning at `dist > radius − 4`: the existing glitch sound throttle
   (`LAST_SOUND`) + an action-bar hint, so the kick never feels sudden.
4. Verify the vehicle path (`VEHICLE_VIOLATIONS_TO_EJECT`) uses the same tightened
   band.

**Files:** `border/SoftBorder.java` (sole owner).
**Effort:** S.

---

## B10 — Spawn/altar area: block ALL mining/building (item 10)

**Root cause.** `worldgen/structure/SanctumProtection` has TWO zones:
`isProtected` — the r=18 cylinder (±26/24 vertical) — and `isSpawnProtected` — the
broad `protection.json` spawn zone (default r=96, absolute vertical band). The
break/place/explosion handlers (`onBlockBreak`, `onBlockPlace`,
`onExplosionDetonate`) test **only `isProtected` (r=18)**. The broad r=96 zone is
consulted solely by `protection/SpawnProtectionRules` for PvP/fluid/vehicle/grief
flags — so everything from r=19 to r=96 around the altar is freely minable, which is
exactly what the user observed ("Ich will das man im Spawn/Altar Bereich nichts
abbauen kann"). Additional edge: `altarPos == null` before the sanctum is built (or
after a failed `refresh`) silently disables ALL protection.

**Fix.**

1. `protection/ProtectionConfig.SpawnRules`: add `noBuild` (default true) +
   optional `buildRadius` (default 0 = use `radius()`), so servers can tune the
   no-build ring independently of the PvP ring.
2. `SanctumProtection.onBlockBreak` / `onBlockPlace` / `onExplosionDetonate`: when
   `ProtectionConfig.current().spawn().noBuild()`, test
   `isProtected(pos) || isSpawnProtected(pos)` instead of `isProtected` alone
   (keep ops exempt; keep the action-bar hint).
3. Also cancel `PlayerInteractEvent.RightClickBlock` bucket/fire placements inside
   the broad zone (bucket griefing bypasses `EntityPlaceEvent`) — but note
   `SpawnProtectionRules` (separate file, PLANNER-D territory) already covers
   fluids; only add what it provably misses.
4. Fallback center: if `altarPos` is null, fall back to the authored disc center
   (`BlockPos.ZERO.atY(70)` — the flat spawn pad in `computeSurfaceY`) so the spawn
   zone is protected from tick 0, before the sanctum builds.

**Files:** `worldgen/structure/SanctumProtection.java`,
`protection/ProtectionConfig.java`.
**Effort:** S.

---

## B11 — Outer-terrain cliffs/hills (item 11)

**Merged into B6** (single owner of `DiscTerrainFunction.java`); see B6 step 3.

---

## B12 — Caves: richer features, occasional GIANT caves, more dungeons (item 12)

**Root cause / current state.** `worldgen/CaveDensity` gives worms
(`WORM_THRESHOLD 0.11`) + depth-boosted cheese rooms (`CHEESE_BASE_THRESHOLD 0.62`,
max relief 0.10) — no giant caverns by design. Cave biome variety exists
(`CaveBiomeMap` dripstone/lush/deep-dark → vanilla cave decoration fires), but rooms
stay modest. Dungeons: `worldgen/structure/UndergroundSites` rolls 1–3 mineshafts +
≤ 4 monster rooms per stage annulus and exactly TWO custom dungeons, both hard-wired
to stage 3 (`DUNGEON_STAGE = 3`) — Collapsed Vault + Umbral Warrens.

**Fix.**

1. **Giant caves:** add a third carver layer in `CaveDensity` — sparse "cathedral"
   cells: hash 1-in-N 64³ cells (salt from the 31+ free family), inside a chosen cell
   evaluate a large-scale simplex ellipsoid (r up to ~28, vertical ~18) with the same
   floor-guard/rim-fade rules; expose `cathedralAt(...)` and OR it into `carvedAt`.
   Depth-gate to y < 20 so they never daylight.
2. **Richer features:** extend `CaveBiomeMap` region table with 1–2 more regions
   (e.g. `minecraft:deep_dark` satellites → skulk pockets, and a crystal region
   mapped to lush/amethyst-heavy decoration); giant-cave cells register their own
   `DiscGenPipeline.ExtraDecor` (new `worldgen/CaveDressings.java`, ceiling-decor
   pattern) for glow-lichen falls, pointed-dripstone clusters and spring lakelets on
   cathedral floors.
3. **More dungeons:** `UndergroundSites` — make `DUNGEON_STAGE` a per-row field and
   add rows: a second Collapsed Vault at stage 4, 1–2 new compact dungeon types
   (new builders in `worldgen/structure/dungeon/`, e.g. `FloodedCryptBuilder`,
   `GlitchReliquaryBuilder`) with **custom loot**: new loot tables under
   `data/eclipse/loot_table/dungeon/` wired the way `StormLootData.chestTable`
   wires chest tables, and `DungeonSpawners` rows for their spawners.
4. Keep every roll keyed to `FrozenParams.mapSeed()` + stage radii (same
   `hash01(SALT, …)` discipline; new salts from the free family, document in the
   seed registry).

**Files:** `worldgen/CaveDensity.java`, `worldgen/CaveBiomeMap.java`, new
`worldgen/CaveDressings.java`, `worldgen/structure/UndergroundSites.java`, new
builders in `worldgen/structure/dungeon/`, `worldgen/structure/dungeon/
DungeonSpawners.java`, new loot jsons under `src/main/resources/data/eclipse/`.
**Effort:** L.

---

## B13 — Snow-storm site: snow never comes back after the storm (item 13)

**Root cause.** The "snow storm site" is `eclipse:fog_storm_2` at (0, −250) in the
snowy grove ring (`DiscMapDefaults`). `worldgen/fog/FogStormSites.materializeSite`
→ `SitePrep.preparePlateau` strips ALL snow layers/powder snow (they are
"vegetation" per `SitePrep.isVegetation`) over the footprint + skirt, then
`carveGrove` paints a biome-blind MUD/PODZOL/GRASS palette. Nothing re-places snow
when the site retires (`retireSessionSite` only clears markers/FX), and runtime
re-freezing can't happen: vanilla only lays snow during active snowfall weather
ticks (`ServerLevel.tickPrecipitation`), which the event's scripted weather rarely
provides — so the grove stays a brown scar in a snow biome forever.

**Fix (all inside `FogStormSites` — SitePrep stays B3's).**

1. `carveGrove`: make the ground palette biome-aware — sample
   `level.getBiome(pos)`; in cold biomes (`coldEnoughToSnow` at the surface) use
   SNOW_BLOCK / powder-snow accents for the outer scar rings instead of
   mud/podzol, keep the scorched center.
2. Add `recoverSite(level, site)` called from the retire path (stage rollback in
   `onStageTerrainComplete` AND a new "storm ended" hook where
   `StormRegistry.handleFogSite(..., false)` is invoked): for every column in the
   radius whose biome is cold at its surface, place a `Blocks.SNOW` layer on
   motion-blocking, snow-supporting tops (skip chests/campfire), i.e. a manual
   `freeze_top_layer` sweep. Budget it through `BudgetedBlockWriter` like all site
   work.
3. Persist a `recovered` flag next to the placed/active flags in
   `EclipseWorldgenState.setFogSiteState` so restarts don't re-run the sweep.

**Files:** `worldgen/fog/FogStormSites.java`
(+ a flag field in `core/state/EclipseWorldgenState.java`).
**Effort:** S–M.

---

## B14 — Umbral shards never "received" (item 14)

**Root cause.** The economy is deliberately split
(`economy/ShardEconomy` header, FINAL-DOPA-SOL §3):

- **Personal balance** (`eclipse:shards` attachment, shown on the sidebar via
  `hud/SidebarSyncService` → `S2CSidebarStatePayload.shards`) is credited ONLY by
  direct `addShards` callers: quest rewards (`QuestEngine.grantRewardContents`),
  minigames, awards, contracts, admin command.
- **Physical shard items** — the sources players actually SEE (boss payouts:
  `HeraldEntity`, `RiftWardenEntity`, `FogTyrantEntity` death drops;
  `skills/SkillPerks` `bonus_shard_on_night_kill` ground pop) — drop as
  `ItemStack(UMBRAL_SHARD)` on the ground and, when banked at the altar, credit the
  **TEAM POOL only** (`ShardEconomy` bank path). They NEVER touch the personal
  balance by design.

So "players never actually receive" is real from the player's POV: ground drops
despawn in 5 min / burn in boss arenas, picked-up shards don't move the visible
balance, and depositing moves them into the pool silently. There is no bug in
`addShards` itself — it's a delivery/feedback gap.

**Fix (keep the double-spend rule: one physical shard = pool value only).**

1. **Reliable delivery:** boss death payouts → replace ground drops with direct
   inventory insert per credited participant (`player.getInventory().add`, drop at
   the player on overflow) + `RewardPayloads.sendRewardGrant(...,
   SOURCE_AWARD-style)` so the materialize overlay plays. Same for
   `SkillPerks.bonus_shard_on_night_kill` (insert, don't pop).
2. **Visible pickup:** on umbral-shard pickup/insert, action-bar cue "X Umbral
   Splitter erhalten — am Altar einzahlen" (reuse the `hint` action-bar pattern) so
   holding ≠ banked is understood.
3. **Bank feedback:** deposit path already messages; also fire the sidebar resync
   immediately after `addShards`/deposit (call the `SidebarSyncService` dirty hook)
   so the HUD number moves in the same second — audit: `setShards` currently
   updates the attachment only; sync rides the next periodic push.
4. Add `/dev shards trace on|off` (extend `devtools/dev/DevStatusCommands` or the
   package B14 file `admin/EclipseCommands` already has `shards add`) logging every
   addShards/deposit/drop with source — playtest verification tool.

**Files:** `entity/boss/HeraldEntity.java`,
`entity/boss/rift/RiftWardenEntity.java`, `entity/boss/fog/FogTyrantEntity.java`,
`skills/SkillPerks.java`, `economy/ShardEconomy.java`,
`hud/SidebarSyncService.java`.
**Effort:** M.

---

## B15 — Stronghold must no longer spawn (item 15)

**Root cause / current wiring.** The finale pair triggers in
`worldgen/structure/StructureStamper.onStageComplete`: stage table row
`new StageEntry(5, 440, "final_day", List.of("eclipse:stronghold_emergence"), …)` in
`core/config/EclipseConfig` enqueues the emergence (→ `StrongholdEmergence.begin`
rips the mountain open and stamps `minecraft:stronghold` into the core cavity), and
the hardcoded `if (stage == FINALE_STAGE) enqueueStrongholdVault(...)` adds the
surface vault + gauntlet. The landmark row `eclipse:stronghold_emergence (0, −400)`
lives in `DiscMapDefaults` (harmless if never enqueued). The handbook map lists it
(`client/handbook/tabs/MapTab.java` landmark 5), and `/locate` maps
`minecraft:stronghold` to it (`VanillaLandmarks.LOCATE_SITES` — removal executed by
B4, the file's owner).

**Fix.**

1. `EclipseConfig`: remove `"eclipse:stronghold_emergence"` from the stage-5
   `StageEntry` default (leave the list empty or substitute the End-disc finale id
   if PLANNER-D's finale needs one); update the day-12 `DayPlan` strings
   ("Locate the stronghold" → End-disc wording).
2. `StructureStamper`: delete `enqueueStrongholdVault` + the `FINALE_STAGE` branch
   and the `STRONGHOLD_VAULT_ID` placer registration (keep
   `StrongholdEmergence`/`CollapsedVaultBuilder.buildStrongholdGauntlet` compiled —
   dead code kept for history per repo convention, mark `@Deprecated` with a
   pointer to this plan). Also drop the emergence self-check re-run if it lives
   here.
3. `MapTab`: remove/replace landmark 5 ("stronghold", 330).
4. Seams executed elsewhere: `GoalConfig` day-12 quest swap → **B8**;
   `VanillaLandmarks.LOCATE_SITES` row removal → **B4**. Frozen saves that already
   committed stage 5 keep their stronghold (acceptable; new saves never get one).

**Files:** `core/config/EclipseConfig.java`,
`worldgen/structure/StructureStamper.java`, `client/handbook/tabs/MapTab.java`.
**Effort:** S.

---

## B16 — `/dev chunk regen` (item 16)

**Root cause / current state.** No such command. All machinery exists: the ring
sweep (`worldgen/stage/RingGrowthService`) already rewrites live chunks
column-by-column from `DiscTerrainFunction` and replays the vanilla pipeline via
`DiscGenPipeline.runOnLiveChunk` (carve → heightmap prime → decorate → seed
animals), then `Heightmap.primeHeightmaps` + budgeted relight/resend — but its
rewrite internals are private inner classes.

**Fix.**

1. New `worldgen/stage/ChunkRegen.java`: public
   `regen(ServerLevel level, ChunkPos pos)` —
   - guard: disc dimension only (`WorldStageService.profileOf`), chunk loaded;
   - clear block entities in the chunk, then for every column with
     `DiscTerrainFunction.column(profile, x, z, committedStage).inside()`, rewrite
     y from `bottomY..topY` with `stateInColumn` via direct
     `LevelChunkSection.setBlockState` (the `EndDiscService.finishChunk` /
     `BreachBuilder` write pattern), air above;
   - replay: `DiscGenPipeline.runOnLiveChunk(level, chunk)`;
   - finish: `Heightmap.primeHeightmaps(chunk, …)` +
     `BudgetedBlockWriter.relightAndResend` (the `SitePrep.finishBounds` pattern);
   - refuse (with message) chunks intersecting a pending/registered structure
     protection box (`StructurePendingRegistry` / registered starts) unless a
     `force` flag is passed — same protection rule the sweep honours.
2. New `devtools/dev/DevChunkCommands.java`: `/dev chunk regen [<chunkX> <chunkZ>]
   [force]` (defaults to the caller's chunk; permission ≥ 3, `Danger.DESTRUCTIVE`),
   registering `DevCommandDoc` entries in `DevCommandRegistry` per the P5
   convention; success prints rewritten column/block counts.
3. Deliberately does NOT touch `RingGrowthService` (no shared-file conflict); the
   small amount of duplicated write-loop code cites the sweep as its reference.

**Files:** new `worldgen/stage/ChunkRegen.java`, new
`devtools/dev/DevChunkCommands.java`.
**Effort:** M.

---

## B17 — `/give` with player names for OPs (item 17)

**Root cause.** Two layers block name targeting, one of them for OPS too:

- Server: `anonymity/mixin/ServerGamePacketListenerImplMixin
  .eclipse$blockNameSuggestions` cancels `ask_server` suggestions only below
  permission 2 — ops are fine here. NOT the bug for ops.
- Client: `client/mixin/ClientSuggestionProviderMixin` empties
  `ClientSuggestionProvider.getOnlinePlayerNames()` **unconditionally**. Vanilla's
  `EntityArgument.listSuggestions` computes player-name suggestions CLIENT-side from
  exactly this method — so `/give <tab>` offers nothing, for everyone, ops
  included. Typing an exact name still resolves server-side, but ops can't KNOW
  names: the tab list is hidden (anonymity `TabListHider`) and `/list` is only
  op-allowed via `CommandBlocker` — so in practice targeting by name is
  "impossible" for ops as reported.

**Fix.**

1. Gate the client mixin on the local player's permission:
   `Minecraft.getInstance().player != null &&
   Minecraft.getInstance().player.hasPermissions(2)` → do NOT empty the list (ops
   get full client-side name completion back); everyone else stays masked. Mirrors
   the server mixin's permission gate exactly.
2. Ops discovery aid: add `/dev player names` to
   `devtools/dev/DevPlayerCommands.java` (permission ≥ 2) printing the real
   name ↔ anonymous-alias roster, with `DevCommandDoc` registration.
3. Verify `/give` end-to-end as OP on a dedicated server (client completion +
   `ask_server` path + execution) and as non-OP (still sealed).

**Files:** `client/mixin/ClientSuggestionProviderMixin.java`,
`devtools/dev/DevPlayerCommands.java`.
**Effort:** S.

---

## Ownership matrix (disjointness proof)

| File | Sole owner |
|---|---|
| `worldgen/DiscBiomeSource.java`, `worldgen/DiscMapDefaults.java` | B1 |
| `worldgen/ore/*` (incl. new `OreVeinShape`) | B2 |
| `worldgen/structure/SitePrep.java` | B3 |
| `worldgen/structure/VanillaLandmarks.java` | B4 (executes B3+B15 one-line seams) |
| `mixin/NaturalSpawnerMixin.java` (new), `registry/EclipseEntities.java`, `devtools/dev/DevSpawnCommands.java`, `entity/spawn/EventSpawnRules.java`, `entity/EclipseSpawner.java` | B5 |
| `worldgen/DiscTerrainFunction.java`, `worldgen/nether/NetherFloorDecor.java` (new) | B6 (items 6+11) |
| `worldgen/nether/BreachBuilder.java`, `worldgen/nether/BreachTransferService.java`, `protection/LandmarkProtection.java` (new) | B7 |
| `progression/goals/{TriggerType,QuestDetectors,GoalConfig,QuestEngine}.java` | B8 (executes B15's quest seam) |
| `border/SoftBorder.java` | B9 |
| `worldgen/structure/SanctumProtection.java`, `protection/ProtectionConfig.java` | B10 |
| `worldgen/{CaveDensity,CaveBiomeMap}.java`, `worldgen/CaveDressings.java` (new), `worldgen/structure/UndergroundSites.java`, `worldgen/structure/dungeon/*` | B12 |
| `worldgen/fog/FogStormSites.java`, `core/state/EclipseWorldgenState.java` | B13 |
| `entity/boss/*` payout files, `skills/SkillPerks.java`, `economy/ShardEconomy.java`, `hud/SidebarSyncService.java` | B14 |
| `core/config/EclipseConfig.java`, `worldgen/structure/StructureStamper.java`, `client/handbook/tabs/MapTab.java` | B15 |
| `worldgen/stage/ChunkRegen.java` (new), `devtools/dev/DevChunkCommands.java` (new) | B16 |
| `client/mixin/ClientSuggestionProviderMixin.java`, `devtools/dev/DevPlayerCommands.java` | B17 |
