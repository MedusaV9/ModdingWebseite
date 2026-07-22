package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.levelgen.structure.BoundingBox;
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.StructurePiece;
import net.minecraft.world.level.levelgen.structure.StructureStart;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Worker 5's structure placement entry point. Subscribes to
 * {@link WorldStageService#addListener}: when a stage's terrain sweep completes (grown, not
 * erased), every {@code structures[]} id listed in {@code stages.json} for the crossed
 * stages {@code fromStage+1..toStage} is stamped at its {@link DiscMapData.Landmark}
 * position — deterministic, so a stage revert + regrow (or {@code /eclipse stage rebuild})
 * reproduces identical structures.
 *
 * <p>Two mechanisms (docs/ideas/01_world_terrain.md §E):</p>
 * <ol>
 *   <li><b>Programmatic vanilla generation</b> ({@link #generateVanilla}/{@link #placeStart}):
 *       replicates {@code /place structure} internals — resolve the {@link Structure} from
 *       {@code Registries.STRUCTURE}, {@code Structure.generate(...)} with the fixed
 *       {@link DiscMapData#ECLIPSE_SEED}, then place the {@link StructureStart} pieces chunk
 *       by chunk. Used for {@code minecraft:desert_pyramid}, {@code minecraft:jungle_pyramid},
 *       {@code minecraft:village_plains} and {@code minecraft:stronghold}.</li>
 *   <li><b>Procedural set-piece builders</b> (GhostShipBuilder pattern) for custom landmarks
 *       ({@link FortressCoreBuilder}, {@link WatcherStatues}, {@link AltarSanctumBuilder})
 *       and as the guaranteed {@link FallbackBuilders fallback} whenever a vanilla structure
 *       refuses to generate in the disc context after 2 attempts — a listed structure NEVER
 *       silently misses.</li>
 * </ol>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StructureStamper {
    /** How often a vanilla {@code Structure.generate} is retried before falling back. */
    static final int VANILLA_ATTEMPTS = 2;

    private static final AtomicBoolean LISTENER_REGISTERED = new AtomicBoolean();

    private StructureStamper() {}

    /** Registers the stage listener once per JVM ({@code LISTENERS} is a static list). */
    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        if (LISTENER_REGISTERED.compareAndSet(false, true)) {
            WorldStageService.addListener(StructureStamper::onStageTerrainComplete);
            EclipseMod.LOGGER.info("StructureStamper registered as world-stage listener");
        }
    }

    /**
     * Stage listener: stamps the {@code structures[]} of every newly reached stage. Erase
     * sweeps ({@code toStage <= fromStage}) place nothing — the terrain function already
     * removed the annulus (and any structure in it); regrowing re-stamps deterministically.
     */
    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile, int fromStage, int toStage) {
        if (toStage <= fromStage) {
            return;
        }
        for (int stage = fromStage + 1; stage <= toStage; stage++) {
            if (profile == DiscProfile.OVERWORLD && stage == 1) {
                // §F flavor landmark: watcher statues appear at the former team-disc
                // centers once the intro fusion (stage 1) swallows the player discs.
                runSafely("eclipse:watcher_statues", () -> WatcherStatues.placeAll(level));
            }
            EclipseConfig.StageEntry entry = EclipseConfig.stage(profile.name(), stage);
            if (entry == null) {
                continue;
            }
            for (String structureId : entry.structures()) {
                final int stageFinal = stage;
                runSafely(structureId, () -> place(level, profile, stageFinal, structureId));
            }
        }
    }

    /** One structure must never break the others (or the sweep-completion path). */
    private static void runSafely(String what, Runnable placement) {
        try {
            placement.run();
        } catch (Exception e) {
            EclipseMod.LOGGER.error("Structure placement of {} failed", what, e);
        }
    }

    /** Dispatches one {@code stages.json} structure id to its placement mechanism. */
    private static void place(ServerLevel level, DiscProfile profile, int stage, String structureId) {
        DiscMapData.Landmark landmark = findLandmark(profile, structureId);
        if (landmark == null) {
            EclipseMod.LOGGER.warn("No disc_map.json landmark for structure {} (stage {} of {}); skipping",
                    structureId, stage, profile.name());
            return;
        }
        switch (structureId) {
            case "eclipse:desert_temple" -> stampPyramid(level, profile, landmark,
                    ResourceLocation.withDefaultNamespace("desert_pyramid"),
                    () -> FallbackBuilders.desertTemple(level, surfaceAnchor(profile, landmark)));
            case "eclipse:jungle_temple" -> stampPyramid(level, profile, landmark,
                    ResourceLocation.withDefaultNamespace("jungle_pyramid"),
                    () -> FallbackBuilders.jungleTemple(level, surfaceAnchor(profile, landmark)));
            case "eclipse:village_plains" -> stampVillage(level, profile, landmark);
            case "eclipse:stronghold_emergence" -> StrongholdEmergence.begin(level);
            case "eclipse:fortress_core" -> FortressCoreBuilder.build(level, landmark);
            default -> EclipseMod.LOGGER.warn("Unknown structure id {} in stages.json (stage {} of {})",
                    structureId, stage, profile.name());
        }
    }

    /** The landmark entry for a structure id, or {@code null} when the map has none. */
    @Nullable
    static DiscMapData.Landmark findLandmark(DiscProfile profile, String structureId) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(profile)) {
            if (landmark.id().equals(structureId)) {
                return landmark;
            }
        }
        return null;
    }

    /** Deterministic surface anchor of a landmark (terrain function, not world heightmap). */
    static BlockPos surfaceAnchor(DiscProfile profile, DiscMapData.Landmark landmark) {
        return new BlockPos(landmark.x(),
                DiscTerrainFunction.surfaceY(profile, landmark.x(), landmark.z()), landmark.z());
    }

    // --- vanilla-generate structures ---

    /**
     * Desert/jungle pyramid: vanilla {@code Structure.generate} at the landmark chunk. The
     * pyramid pieces self-anchor to the real ground at placement time
     * ({@code ScatteredFeaturePiece} samples MOTION_BLOCKING_NO_LEAVES), so no piece moves
     * are needed. Falls back to a compact procedural temple after {@value #VANILLA_ATTEMPTS}
     * failed attempts.
     */
    private static void stampPyramid(ServerLevel level, DiscProfile profile,
            DiscMapData.Landmark landmark, ResourceLocation vanillaId, Runnable fallback) {
        BlockPos anchor = surfaceAnchor(profile, landmark);
        StructureStart start = generateVanilla(level, vanillaId, anchor);
        if (start == null) {
            EclipseMod.LOGGER.warn("PROCEDURAL FALLBACK: {} failed to generate at {}; building fallback temple",
                    vanillaId, anchor.toShortString());
            fallback.run();
            return;
        }
        BoundingBox placed = placeStart(level, start, placementRandom(anchor));
        registerStart(level, start, placed);
        EclipseMod.LOGGER.info("VANILLA GENERATE: placed {} for {} at {} (bounds {})",
                vanillaId, landmark.id(), anchor.toShortString(), placed);
    }

    /**
     * Village: flatten a coarse-dirt plaza around the landmark first (§E — vanilla village
     * start expects workable flat ground), then vanilla-generate
     * {@code minecraft:village_plains}. Outer street/house pieces terrain-match against the
     * real (procedural) plains surface at placement time.
     */
    private static void stampVillage(ServerLevel level, DiscProfile profile, DiscMapData.Landmark landmark) {
        BlockPos anchor = surfaceAnchor(profile, landmark);
        flattenPlaza(level, profile, landmark.x(), landmark.z(), 12);
        StructureStart start = generateVanilla(level,
                ResourceLocation.withDefaultNamespace("village_plains"), anchor);
        if (start == null) {
            EclipseMod.LOGGER.warn("PROCEDURAL FALLBACK: minecraft:village_plains failed at {}; building fallback hamlet",
                    anchor.toShortString());
            FallbackBuilders.village(level, anchor);
            return;
        }
        BoundingBox placed = placeStart(level, start, placementRandom(anchor));
        registerStart(level, start, placed);
        EclipseMod.LOGGER.info("VANILLA GENERATE: placed minecraft:village_plains for {} at {} (bounds {})",
                landmark.id(), anchor.toShortString(), placed);
    }

    /**
     * Replicates the {@code /place structure} generate step with the fixed
     * {@link DiscMapData#ECLIPSE_SEED} (attempt index nudges the seed). Returns {@code null}
     * after {@value #VANILLA_ATTEMPTS} invalid/failed attempts — callers must fall back.
     */
    @Nullable
    static StructureStart generateVanilla(ServerLevel level, ResourceLocation structureId, BlockPos anchor) {
        Structure structure = level.registryAccess().registryOrThrow(Registries.STRUCTURE).get(structureId);
        if (structure == null) {
            EclipseMod.LOGGER.error("Structure {} missing from registry", structureId);
            return null;
        }
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        for (int attempt = 0; attempt < VANILLA_ATTEMPTS; attempt++) {
            try {
                StructureStart start = structure.generate(level.registryAccess(), generator,
                        generator.getBiomeSource(), level.getChunkSource().randomState(),
                        level.getStructureManager(), DiscMapData.ECLIPSE_SEED + attempt,
                        new ChunkPos(anchor), 0, level, biome -> true);
                if (start != null && start.isValid()) {
                    return start;
                }
                EclipseMod.LOGGER.warn("Structure.generate attempt {}/{} for {} at {} produced no pieces",
                        attempt + 1, VANILLA_ATTEMPTS, structureId, anchor.toShortString());
            } catch (Exception e) {
                EclipseMod.LOGGER.warn("Structure.generate attempt {}/{} for {} at {} threw",
                        attempt + 1, VANILLA_ATTEMPTS, structureId, anchor.toShortString(), e);
            }
        }
        return null;
    }

    /**
     * Places every piece of a generated start, chunk by chunk like {@code /place structure}.
     * Bounds come from the piece union (NOT {@link StructureStart#getBoundingBox()}, whose
     * lazy cache would be stale after {@link StructurePiece#move} repositioning). Chunks are
     * force-materialised first — the ring sweep only rewrites already-generated chunks, so
     * a landmark area may still be ungenerated when its stage completes.
     */
    static BoundingBox placeStart(ServerLevel level, StructureStart start, RandomSource random) {
        BoundingBox bounds = pieceUnion(start);
        ChunkPos minChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos maxChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> level.getChunk(chunkPos.x, chunkPos.z));
        ChunkGenerator generator = level.getChunkSource().getGenerator();
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos -> start.placeInChunk(level,
                level.structureManager(), generator, random,
                new BoundingBox(chunkPos.getMinBlockX(), level.getMinBuildHeight(), chunkPos.getMinBlockZ(),
                        chunkPos.getMaxBlockX(), level.getMaxBuildHeight(), chunkPos.getMaxBlockZ()),
                chunkPos));
        return pieceUnion(start); // recompute: scattered pieces may have self-moved vertically
    }

    /** Union of the current piece bounding boxes (move-safe, unlike the start's cache). */
    static BoundingBox pieceUnion(StructureStart start) {
        return BoundingBox.encapsulatingBoxes(
                start.getPieces().stream().map(StructurePiece::getBoundingBox).toList()).orElseThrow();
    }

    /**
     * Books the placed start into the chunk structure data (start + references), the same
     * bookkeeping natural generation performs — structure-aware features like
     * {@code /locate structure} can then resolve it from the chunk.
     */
    static void registerStart(ServerLevel level, StructureStart start, BoundingBox bounds) {
        Structure structure = start.getStructure();
        ChunkAccess startChunk = level.getChunk(start.getChunkPos().x, start.getChunkPos().z);
        startChunk.setStartForStructure(structure, start);
        ChunkPos minChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.minX()),
                SectionPos.blockToSectionCoord(bounds.minZ()));
        ChunkPos maxChunk = new ChunkPos(SectionPos.blockToSectionCoord(bounds.maxX()),
                SectionPos.blockToSectionCoord(bounds.maxZ()));
        ChunkPos.rangeClosed(minChunk, maxChunk).forEach(chunkPos ->
                level.getChunk(chunkPos.x, chunkPos.z).addReferenceForStructure(structure, start.getChunkPos().toLong()));
    }

    /** Deterministic placement random (chest loot, decoration rolls) per landmark. */
    static RandomSource placementRandom(BlockPos anchor) {
        return RandomSource.create(DiscMapData.ECLIPSE_SEED ^ anchor.asLong());
    }

    /**
     * Flattens a circular coarse-dirt plaza to the landmark's deterministic surface height:
     * vegetation and terrain above are cleared, dips are filled, and the top layer becomes a
     * hashed grass/coarse-dirt/path mix.
     */
    static void flattenPlaza(ServerLevel level, DiscProfile profile, int centerX, int centerZ, int radius) {
        int plazaY = DiscTerrainFunction.surfaceY(profile, centerX, centerZ);
        BlockState dirt = Blocks.DIRT.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = -radius; dx <= radius; dx++) {
            for (int dz = -radius; dz <= radius; dz++) {
                if (dx * dx + dz * dz > radius * radius) {
                    continue;
                }
                int x = centerX + dx;
                int z = centerZ + dz;
                level.getChunk(x >> 4, z >> 4);
                for (int y = plazaY + 1; y <= plazaY + 24; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isAir()) {
                        level.setBlock(cursor, Blocks.AIR.defaultBlockState(), 2);
                    }
                }
                for (int y = plazaY - 3; y < plazaY; y++) {
                    cursor.set(x, y, z);
                    if (!level.getBlockState(cursor).isSolidRender(level, cursor)) {
                        level.setBlock(cursor, dirt, 2);
                    }
                }
                cursor.set(x, plazaY, z);
                level.setBlock(cursor, plazaTopBlock(x, z), 2);
            }
        }
        EclipseMod.LOGGER.info("Flattened village plaza r={} at ({}, {}, {})", radius, centerX, plazaY, centerZ);
    }

    /** Hashed plaza surface mix: mostly grass with coarse-dirt patches and dirt-path scars. */
    private static BlockState plazaTopBlock(int x, int z) {
        long h = (x * 341873128712L + z * 132897987541L) ^ DiscMapData.ECLIPSE_SEED;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        double roll = ((h >>> 11) & 0xFFFFF) / (double) 0x100000;
        if (roll < 0.25D) {
            return Blocks.COARSE_DIRT.defaultBlockState();
        }
        if (roll < 0.32D) {
            return Blocks.DIRT_PATH.defaultBlockState();
        }
        return Blocks.GRASS_BLOCK.defaultBlockState();
    }
}
