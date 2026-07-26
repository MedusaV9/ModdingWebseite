package dev.projecteclipse.eclipse.backrooms;

import java.util.List;
import java.util.concurrent.CompletableFuture;

import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderGetter;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.RegistryOps;
import net.minecraft.server.level.WorldGenRegion;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.LevelHeightAccessor;
import net.minecraft.world.level.NoiseColumn;
import net.minecraft.world.level.StructureManager;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeManager;
import net.minecraft.world.level.biome.Biomes;
import net.minecraft.world.level.biome.FixedBiomeSource;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.RandomState;
import net.minecraft.world.level.levelgen.blending.Blender;

/**
 * Chunk generator of the Backrooms dimension ({@code eclipse:backrooms}) — the
 * {@code DiscChunkGenerator} architecture applied to the layer stack: every block comes
 * from the pure {@link BackroomsLayers} terrain function (one {@link BackroomsLayers.Column}
 * context per column, then {@code stateInColumn} per Y), so the five levels — Yellow
 * Rooms, Poolrooms, Warehouse, Flooded Halls, The Hollow — are REAL terrain generation:
 * infinite in X/Z, produced
 * as chunks load, byte-deterministic per world seed, with no stamp phase and no global
 * solver. Carvers, surface rules, vanilla features, structures and worldgen mob seeding
 * are all disabled — the maze IS the terrain. Water (pool basins, drain waterfalls,
 * landing basins) is marked for fluid post-processing so drains spill naturally.
 */
public final class BackroomsChunkGenerator extends ChunkGenerator {
    public static final MapCodec<BackroomsChunkGenerator> CODEC = RecordCodecBuilder.mapCodec(
            instance -> instance.group(
                    RegistryOps.retrieveGetter(Registries.BIOME))
            .apply(instance, instance.stable(BackroomsChunkGenerator::new)));

    public BackroomsChunkGenerator(HolderGetter<Biome> biomes) {
        super(new FixedBiomeSource(biomes.getOrThrow(Biomes.THE_VOID)));
    }

    @Override
    protected MapCodec<? extends ChunkGenerator> codec() {
        return CODEC;
    }

    @Override
    public CompletableFuture<ChunkAccess> fillFromNoise(Blender blender, RandomState randomState,
            StructureManager structureManager, ChunkAccess chunk) {
        long seed = BackroomsMaze.worldSeed();
        ChunkPos pos = chunk.getPos();
        int minBuild = chunk.getMinBuildHeight();
        int maxY = Math.min(BackroomsLayers.TOP_Y, chunk.getMaxBuildHeight() - 1);
        Heightmap oceanFloor = chunk.getOrCreateHeightmapUnprimed(Heightmap.Types.OCEAN_FLOOR_WG);
        Heightmap worldSurface = chunk.getOrCreateHeightmapUnprimed(Heightmap.Types.WORLD_SURFACE_WG);
        BlockPos.MutableBlockPos fluidPos = new BlockPos.MutableBlockPos();
        for (int lx = 0; lx < 16; lx++) {
            int x = pos.getMinBlockX() + lx;
            for (int lz = 0; lz < 16; lz++) {
                int z = pos.getMinBlockZ() + lz;
                BackroomsLayers.Column column = BackroomsLayers.column(seed, x, z);
                for (int y = Math.max(0, minBuild); y <= maxY; y++) {
                    BlockState state = BackroomsLayers.stateInColumn(column, y);
                    if (state.isAir()) {
                        continue;
                    }
                    LevelChunkSection section = chunk.getSection(chunk.getSectionIndex(y));
                    section.setBlockState(lx, y & 15, lz, state, false);
                    oceanFloor.update(lx, y, lz, state);
                    worldSurface.update(lx, y, lz, state);
                    if (!state.getFluidState().isEmpty()) {
                        chunk.markPosForPostprocessing(fluidPos.set(x, y, z));
                    }
                }
            }
        }
        return CompletableFuture.completedFuture(chunk);
    }

    @Override
    public int getBaseHeight(int x, int z, Heightmap.Types type, LevelHeightAccessor level,
            RandomState random) {
        BackroomsLayers.Column column = BackroomsLayers.column(BackroomsMaze.worldSeed(), x, z);
        int top = Math.min(BackroomsLayers.TOP_Y, level.getMaxBuildHeight() - 1);
        for (int y = top; y >= level.getMinBuildHeight(); y--) {
            if (type.isOpaque().test(BackroomsLayers.stateInColumn(column, y))) {
                return y + 1;
            }
        }
        return level.getMinBuildHeight();
    }

    @Override
    public NoiseColumn getBaseColumn(int x, int z, LevelHeightAccessor level, RandomState random) {
        BackroomsLayers.Column column = BackroomsLayers.column(BackroomsMaze.worldSeed(), x, z);
        BlockState[] states = new BlockState[level.getHeight()];
        for (int i = 0; i < states.length; i++) {
            states[i] = BackroomsLayers.stateInColumn(column, level.getMinBuildHeight() + i);
        }
        return new NoiseColumn(level.getMinBuildHeight(), states);
    }

    /** No carvers — the maze IS the terrain. */
    @Override
    public void applyCarvers(WorldGenRegion level, long seed, RandomState random,
            BiomeManager biomeManager, StructureManager structureManager, ChunkAccess chunk,
            GenerationStep.Carving step) {
    }

    /** No surface rules — palettes are part of the layer function. */
    @Override
    public void buildSurface(WorldGenRegion level, StructureManager structureManager,
            RandomState random, ChunkAccess chunk) {
    }

    /** No worldgen mob seeding — the event service owns the mob budget. */
    @Override
    public void spawnOriginalMobs(WorldGenRegion level) {
    }

    @Override
    public int getSpawnHeight(LevelHeightAccessor level) {
        return BackroomsLayers.Y_WALK_Y;
    }

    @Override
    public int getMinY() {
        return 0;
    }

    /** Must equal {@code dimension_type/backrooms.json}'s {@code height}. */
    @Override
    public int getGenDepth() {
        return BackroomsLayers.DIM_HEIGHT;
    }

    @Override
    public int getSeaLevel() {
        return 0;
    }

    @Override
    public void addDebugScreenInfo(List<String> info, RandomState random, BlockPos pos) {
        info.add("Eclipse backrooms: layer=" + BackroomsLayers.layerOf(pos.getY())
                + " cell=" + Math.floorDiv(pos.getX(), BackroomsMaze.CELL)
                + "," + Math.floorDiv(pos.getZ(), BackroomsMaze.CELL));
    }
}
