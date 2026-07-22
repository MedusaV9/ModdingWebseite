package dev.projecteclipse.eclipse.worldgen;

import java.util.List;
import java.util.concurrent.CompletableFuture;

import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderGetter;
import net.minecraft.core.RegistryAccess;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.RegistryOps;
import net.minecraft.server.level.WorldGenRegion;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.LevelHeightAccessor;
import net.minecraft.world.level.NoiseColumn;
import net.minecraft.world.level.StructureManager;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeGenerationSettings;
import net.minecraft.world.level.biome.BiomeManager;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.ChunkGenerator;
import net.minecraft.world.level.chunk.ChunkGeneratorStructureState;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.RandomState;
import net.minecraft.world.level.levelgen.blending.Blender;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructureTemplateManager;

/**
 * Chunk generator of the disc world ({@code eclipse:disc}). All terrain comes from
 * {@link DiscTerrainFunction} evaluated at the CURRENT COMMITTED STAGE (read through the
 * {@link WorldStageAccess} seam, safe on worldgen worker threads, default stage 0) — so a
 * chunk generated for the first time after a stage grows already contains the wider disc,
 * while worker 4's runtime ring sweep rewrites chunks that generated earlier.
 *
 * <p>Everything vanilla that would break determinism is disabled: no structure starts
 * (worker 5 stamps structures itself), no biome decoration features (vegetation is part of
 * the terrain function), no carvers (caves are part of the terrain function) and no
 * surface rules. {@code fillFromNoise} writes {@link LevelChunkSection}s directly, bounded
 * by each column's {@code bottomY..topY} span.</p>
 */
public final class DiscChunkGenerator extends ChunkGenerator {
    public static final MapCodec<DiscChunkGenerator> CODEC = RecordCodecBuilder.mapCodec(
            instance -> instance.group(
                    DiscProfile.CODEC.fieldOf("profile").forGetter(DiscChunkGenerator::profile),
                    RegistryOps.retrieveGetter(Registries.BIOME))
            .apply(instance, instance.stable(DiscChunkGenerator::new)));

    private final DiscProfile profile;

    public DiscChunkGenerator(DiscProfile profile, HolderGetter<Biome> biomes) {
        // Empty per-biome generation settings: vanilla placed features must never
        // decorate the disc, or chunkgen output would diverge from the terrain function.
        super(new DiscBiomeSource(profile, biomes), holder -> BiomeGenerationSettings.EMPTY);
        this.profile = profile;
    }

    public DiscProfile profile() {
        return this.profile;
    }

    @Override
    protected MapCodec<? extends ChunkGenerator> codec() {
        return CODEC;
    }

    @Override
    public CompletableFuture<ChunkAccess> fillFromNoise(Blender blender, RandomState randomState,
            StructureManager structureManager, ChunkAccess chunk) {
        int stage = WorldStageAccess.stage(this.profile);
        ChunkPos pos = chunk.getPos();
        int minBuild = chunk.getMinBuildHeight();
        int maxY = chunk.getMaxBuildHeight() - 1;
        Heightmap oceanFloor = chunk.getOrCreateHeightmapUnprimed(Heightmap.Types.OCEAN_FLOOR_WG);
        Heightmap worldSurface = chunk.getOrCreateHeightmapUnprimed(Heightmap.Types.WORLD_SURFACE_WG);
        BlockPos.MutableBlockPos fluidPos = new BlockPos.MutableBlockPos();
        for (int lx = 0; lx < 16; lx++) {
            int x = pos.getMinBlockX() + lx;
            for (int lz = 0; lz < 16; lz++) {
                int z = pos.getMinBlockZ() + lz;
                DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, stage);
                if (!column.inside()) {
                    continue;
                }
                int yMin = Math.max(column.bottomY(), minBuild);
                int yMax = Math.min(column.topY(), maxY);
                for (int y = yMin; y <= yMax; y++) {
                    BlockState state = DiscTerrainFunction.stateInColumn(column, y);
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
    public int getBaseHeight(int x, int z, Heightmap.Types type, LevelHeightAccessor level, RandomState random) {
        DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, WorldStageAccess.stage(this.profile));
        if (!column.inside()) {
            return level.getMinBuildHeight();
        }
        int top = Math.min(column.topY(), level.getMaxBuildHeight() - 1);
        int bottom = Math.max(column.bottomY(), level.getMinBuildHeight());
        for (int y = top; y >= bottom; y--) {
            if (type.isOpaque().test(DiscTerrainFunction.stateInColumn(column, y))) {
                return y + 1;
            }
        }
        return level.getMinBuildHeight();
    }

    @Override
    public NoiseColumn getBaseColumn(int x, int z, LevelHeightAccessor level, RandomState random) {
        DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, WorldStageAccess.stage(this.profile));
        BlockState[] states = new BlockState[level.getHeight()];
        for (int i = 0; i < states.length; i++) {
            states[i] = DiscTerrainFunction.stateInColumn(column, level.getMinBuildHeight() + i);
        }
        return new NoiseColumn(level.getMinBuildHeight(), states);
    }

    /** Vanilla structure starts are disabled; worker 5 stamps structures deterministically. */
    @Override
    public void createStructures(RegistryAccess registryAccess, ChunkGeneratorStructureState structureState,
            StructureManager structureManager, ChunkAccess chunk, StructureTemplateManager structureTemplateManager) {
    }

    /** Carving is part of {@link DiscTerrainFunction} (deterministic Perlin-worm caves). */
    @Override
    public void applyCarvers(WorldGenRegion level, long seed, RandomState random, BiomeManager biomeManager,
            StructureManager structureManager, ChunkAccess chunk, GenerationStep.Carving step) {
    }

    /** Surface blocks are part of {@link DiscTerrainFunction} (sector palettes). */
    @Override
    public void buildSurface(WorldGenRegion level, StructureManager structureManager, RandomState random,
            ChunkAccess chunk) {
    }

    @Override
    public void spawnOriginalMobs(WorldGenRegion level) {
    }

    @Override
    public int getSpawnHeight(LevelHeightAccessor level) {
        return DiscTerrainFunction.surfaceY(this.profile, 0, 0) + 1;
    }

    @Override
    public int getMinY() {
        return this.profile.minY();
    }

    @Override
    public int getGenDepth() {
        return this.profile.height();
    }

    @Override
    public int getSeaLevel() {
        return this.profile.seaLevel();
    }

    @Override
    public void addDebugScreenInfo(List<String> info, RandomState random, BlockPos pos) {
        info.add("Eclipse disc: profile=" + this.profile.name()
                + " stage=" + WorldStageAccess.stage(this.profile));
    }
}
