package dev.projecteclipse.eclipse.worldgen;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import javax.annotation.Nullable;

import com.mojang.datafixers.util.Pair;
import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.structure.VanillaLandmarks;
import dev.projecteclipse.eclipse.worldgen.vanilla.BiomeFeatureFilter;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import dev.projecteclipse.eclipse.worldgen.vanilla.FixedSeedGenRegion;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Holder;
import net.minecraft.core.HolderGetter;
import net.minecraft.core.HolderSet;
import net.minecraft.core.RegistryAccess;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.RegistryOps;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.WorldGenRegion;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.LevelHeightAccessor;
import net.minecraft.world.level.NoiseColumn;
import net.minecraft.world.level.StructureManager;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.biome.Biome;
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
import net.minecraft.world.level.levelgen.structure.Structure;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructureTemplateManager;

/**
 * Chunk generator of the disc world ({@code eclipse:disc}). The BASE terrain — silhouette,
 * rim, underside, strata, rivers, sealed hull — comes from {@link DiscTerrainFunction}
 * evaluated at the CURRENT COMMITTED STAGE (read through the {@link WorldStageAccess} seam,
 * safe on worldgen worker threads, default stage 0) — so a chunk generated for the first
 * time after a stage grows already contains the wider disc, while the runtime ring sweep
 * rewrites chunks that generated earlier.
 *
 * <p>On top of that base the vanilla pipeline runs for real (design D1, the
 * {@code worldgen/vanilla} engine): {@link #applyCarvers} runs vanilla cave/canyon carvers,
 * {@link #applyBiomeDecoration} places each biome's real placed features (minus the
 * {@link BiomeFeatureFilter} ore deny-list) under the frozen map seed via
 * {@link FixedSeedGenRegion}, and {@link #spawnOriginalMobs} seeds animals — all phases
 * hull-guarded and byte-deterministic per save (see {@link DiscGenPipeline}). Structure
 * starts stay disabled (structures are stamped at fixed landmark sites) and surface rules
 * stay off (sector palettes are strata in the terrain function). {@code fillFromNoise}
 * writes {@link LevelChunkSection}s directly, bounded by each column's
 * {@code bottomY..topY} span.</p>
 */
public final class DiscChunkGenerator extends ChunkGenerator {
    public static final MapCodec<DiscChunkGenerator> CODEC = RecordCodecBuilder.mapCodec(
            instance -> instance.group(
                    DiscProfile.CODEC.fieldOf("profile").forGetter(DiscChunkGenerator::profile),
                    RegistryOps.retrieveGetter(Registries.BIOME))
            .apply(instance, instance.stable(DiscChunkGenerator::new)));

    private final DiscProfile profile;

    public DiscChunkGenerator(DiscProfile profile, HolderGetter<Biome> biomes) {
        // Real per-biome generation settings minus the ore deny-list: vanilla vegetation,
        // springs, geodes and monster rooms decorate the disc, while the OreField engine
        // owns every mineral ore (design D1.1/D5).
        super(new DiscBiomeSource(profile, biomes), BiomeFeatureFilter::settingsFor);
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
        // One map snapshot per chunk: a disc_map.json reload mid-generation must never
        // mix old and new map data inside the same chunk (worker-thread volatile swap).
        DiscMapData map = DiscMapData.get();
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
                DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, stage, map);
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

    /**
     * Resolves {@code /locate structure} against the deterministic landmark table instead of
     * vanilla structure placements (there are none — {@link #createStructures} is disabled).
     * The vanilla-structure-id → landmark-id table is owned by
     * {@link VanillaLandmarks#locateSites} (W1.6 seam, §3.10). A site only resolves once its
     * landmark stage is committed, i.e. once the {@code StructureStamper} has actually
     * stamped it. {@code skipKnownStructures} is ignored: sites are fixed, there is exactly
     * one instance of each.
     */
    @Nullable
    @Override
    public Pair<BlockPos, Holder<Structure>> findNearestMapStructure(ServerLevel level,
            HolderSet<Structure> structures, BlockPos pos, int searchRadius, boolean skipKnownStructures) {
        int committedStage = WorldStageAccess.stage(this.profile);
        Map<ResourceLocation, String> locateSites = VanillaLandmarks.locateSites();
        Pair<BlockPos, Holder<Structure>> nearest = null;
        double nearestDistSq = Double.MAX_VALUE;
        for (Holder<Structure> holder : structures) {
            ResourceLocation structureId = holder.unwrapKey().map(key -> key.location()).orElse(null);
            if (structureId == null) {
                continue;
            }
            String landmarkId = locateSites.get(structureId);
            if (landmarkId == null) {
                continue;
            }
            for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(this.profile)) {
                if (!landmark.id().equals(landmarkId) || landmark.stage() > committedStage) {
                    continue;
                }
                BlockPos site = new BlockPos(landmark.x(),
                        DiscTerrainFunction.surfaceY(this.profile, landmark.x(), landmark.z()), landmark.z());
                double distSq = site.distSqr(pos);
                if (distSq < nearestDistSq) {
                    nearestDistSq = distSq;
                    nearest = Pair.of(site, holder);
                }
            }
        }
        return nearest;
    }

    /**
     * Vanilla cave/canyon carvers on the disc base (design D1.3). The world-derived
     * arguments ({@code seed}, {@code random}, {@code biomeManager}) are deliberately
     * ignored: the engine builds every input from the frozen map seed so carved caves are
     * identical in every save and every ring-growth replay, and {@code HullRepair} re-seals
     * the hull afterwards (inside {@link DiscGenPipeline#carve}).
     */
    @Override
    public void applyCarvers(WorldGenRegion level, long seed, RandomState random, BiomeManager biomeManager,
            StructureManager structureManager, ChunkAccess chunk, GenerationStep.Carving step) {
        DiscGenPipeline.carve(this, level.registryAccess(), chunk, step);
    }

    /**
     * Vanilla biome decoration under the frozen map seed (design D1.2): the level is
     * wrapped in {@link FixedSeedGenRegion} so the per-chunk population seed — and with it
     * every placed feature — is identical in every save and every ring-growth replay; the
     * shared post-pass ({@code HullRepair} + registered {@code ExtraDecor}s) runs through
     * {@link DiscGenPipeline#afterDecoration}. Both generation paths land here:
     * chunk generation passes the {@code WorldGenRegion}, and
     * {@link DiscGenPipeline#runOnLiveChunk} passes the {@code ServerLevel}.
     */
    @Override
    public void applyBiomeDecoration(WorldGenLevel level, ChunkAccess chunk, StructureManager structureManager) {
        WorldGenLevel fixed = level instanceof FixedSeedGenRegion wrapped ? wrapped
                : new FixedSeedGenRegion(level, DiscGenPipeline.fixedSeed());
        super.applyBiomeDecoration(fixed, chunk, structureManager);
        DiscGenPipeline.afterDecoration(this.profile, fixed, chunk);
    }

    /** Surface blocks are part of {@link DiscTerrainFunction} (sector palettes). */
    @Override
    public void buildSurface(WorldGenRegion level, StructureManager structureManager, RandomState random,
            ChunkAccess chunk) {
    }

    /** Chunk-generation animal seeding, the vanilla behavior (design D1.4 — req 4). */
    @Override
    public void spawnOriginalMobs(WorldGenRegion level) {
        DiscGenPipeline.seedMobs(level, level.getCenter());
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
