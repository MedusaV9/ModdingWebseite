package dev.projecteclipse.eclipse.worldgen.vanilla;

import java.util.List;
import java.util.Optional;
import java.util.function.Predicate;
import java.util.function.Supplier;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.Holder;
import net.minecraft.core.RegistryAccess;
import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.Difficulty;
import net.minecraft.world.DifficultyInstance;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.flag.FeatureFlagSet;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.ColorResolver;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.biome.BiomeManager;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.border.WorldBorder;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.ChunkSource;
import net.minecraft.world.level.chunk.status.ChunkStatus;
import net.minecraft.world.level.dimension.DimensionType;
import net.minecraft.world.level.entity.EntityTypeTest;
import net.minecraft.world.level.gameevent.GameEvent;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.lighting.LevelLightEngine;
import net.minecraft.world.level.material.Fluid;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.level.storage.LevelData;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.phys.shapes.VoxelShape;
import net.minecraft.world.ticks.LevelTickAccess;
import net.minecraft.util.RandomSource;

/**
 * A delegating {@link WorldGenLevel} that reports a FIXED seed instead of the world seed
 * (design D1.2/D9): vanilla decoration derives its per-chunk population seed from
 * {@code level.getSeed()}, so wrapping the generation region in this class makes every
 * placed feature — and therefore the whole decorated disc — identical in every save and
 * every ring-growth re-run with the same frozen params.
 *
 * <p>Biome lookups are wrapped too: {@link #getBiomeManager()} returns a manager whose
 * zoom (the ±2-3 block biome-border jitter) is seeded from the same fixed seed, because
 * {@code BiomeFilter} placement checks query {@code level.getBiome(pos)} and vanilla's
 * region manager zooms with the per-save world seed — which would shift feature outcomes
 * along sector borders between saves. Everything else delegates verbatim, including
 * {@link #ensureCanWrite} (the ±1-chunk write discipline of {@code WorldGenRegion}) and
 * {@link #setCurrentlyGenerating} (crash-report context).</p>
 *
 * <p>Wraps both {@code WorldGenRegion} (chunk generation) and {@code ServerLevel}
 * (live-chunk decoration replay, {@link DiscGenPipeline#runOnLiveChunk}).</p>
 */
public final class FixedSeedGenRegion implements WorldGenLevel {
    private final WorldGenLevel delegate;
    private final long seed;
    private final BiomeManager fixedBiomeManager;

    public FixedSeedGenRegion(WorldGenLevel delegate, long seed) {
        this.delegate = delegate;
        this.seed = seed;
        this.fixedBiomeManager = new BiomeManager(delegate::getNoiseBiome, BiomeManager.obfuscateSeed(seed));
    }

    /** The wrapped level (the real region / server level). */
    public WorldGenLevel delegate() {
        return this.delegate;
    }

    // --- the point of this class ---

    @Override
    public long getSeed() {
        return this.seed;
    }

    @Override
    public BiomeManager getBiomeManager() {
        return this.fixedBiomeManager;
    }

    // --- WorldGenLevel / ServerLevelAccessor ---

    @Override
    public boolean ensureCanWrite(BlockPos pos) {
        return this.delegate.ensureCanWrite(pos);
    }

    @Override
    public void setCurrentlyGenerating(@Nullable Supplier<String> currentlyGenerating) {
        this.delegate.setCurrentlyGenerating(currentlyGenerating);
    }

    @Override
    public ServerLevel getLevel() {
        return this.delegate.getLevel();
    }

    // --- LevelAccessor ---

    @Override
    public long nextSubTickCount() {
        return this.delegate.nextSubTickCount();
    }

    @Override
    public LevelTickAccess<Block> getBlockTicks() {
        return this.delegate.getBlockTicks();
    }

    @Override
    public LevelTickAccess<Fluid> getFluidTicks() {
        return this.delegate.getFluidTicks();
    }

    @Override
    public LevelData getLevelData() {
        return this.delegate.getLevelData();
    }

    @Override
    public DifficultyInstance getCurrentDifficultyAt(BlockPos pos) {
        return this.delegate.getCurrentDifficultyAt(pos);
    }

    @Nullable
    @Override
    public MinecraftServer getServer() {
        return this.delegate.getServer();
    }

    @Override
    public Difficulty getDifficulty() {
        return this.delegate.getDifficulty();
    }

    @Override
    public ChunkSource getChunkSource() {
        return this.delegate.getChunkSource();
    }

    @Override
    public RandomSource getRandom() {
        return this.delegate.getRandom();
    }

    @Override
    public void playSound(@Nullable Player player, BlockPos pos, SoundEvent sound, SoundSource source,
            float volume, float pitch) {
        this.delegate.playSound(player, pos, sound, source, volume, pitch);
    }

    @Override
    public void addParticle(ParticleOptions particleData, double x, double y, double z,
            double xSpeed, double ySpeed, double zSpeed) {
        this.delegate.addParticle(particleData, x, y, z, xSpeed, ySpeed, zSpeed);
    }

    @Override
    public void levelEvent(@Nullable Player player, int type, BlockPos pos, int data) {
        this.delegate.levelEvent(player, type, pos, data);
    }

    @Override
    public void gameEvent(Holder<GameEvent> gameEvent, Vec3 pos, GameEvent.Context context) {
        this.delegate.gameEvent(gameEvent, pos, context);
    }

    // --- LevelReader ---

    @Nullable
    @Override
    public ChunkAccess getChunk(int x, int z, ChunkStatus chunkStatus, boolean requireChunk) {
        return this.delegate.getChunk(x, z, chunkStatus, requireChunk);
    }

    /** Deprecated in {@code LevelReader} but abstract — pure delegation, no policy here. */
    @Deprecated
    @Override
    public boolean hasChunk(int chunkX, int chunkZ) {
        return this.delegate.hasChunk(chunkX, chunkZ);
    }

    @Override
    public int getHeight(Heightmap.Types heightmapType, int x, int z) {
        return this.delegate.getHeight(heightmapType, x, z);
    }

    @Override
    public int getSkyDarken() {
        return this.delegate.getSkyDarken();
    }

    @Override
    public Holder<Biome> getUncachedNoiseBiome(int x, int y, int z) {
        return this.delegate.getUncachedNoiseBiome(x, y, z);
    }

    @Override
    public boolean isClientSide() {
        return this.delegate.isClientSide();
    }

    /** Deprecated in {@code LevelReader} but abstract — pure delegation, no policy here. */
    @Deprecated
    @Override
    public int getSeaLevel() {
        return this.delegate.getSeaLevel();
    }

    @Override
    public DimensionType dimensionType() {
        return this.delegate.dimensionType();
    }

    @Override
    public RegistryAccess registryAccess() {
        return this.delegate.registryAccess();
    }

    @Override
    public FeatureFlagSet enabledFeatures() {
        return this.delegate.enabledFeatures();
    }

    // --- LevelHeightAccessor ---

    @Override
    public int getHeight() {
        return this.delegate.getHeight();
    }

    @Override
    public int getMinBuildHeight() {
        return this.delegate.getMinBuildHeight();
    }

    // --- BlockGetter / BlockAndTintGetter ---

    @Nullable
    @Override
    public BlockEntity getBlockEntity(BlockPos pos) {
        return this.delegate.getBlockEntity(pos);
    }

    @Override
    public BlockState getBlockState(BlockPos pos) {
        return this.delegate.getBlockState(pos);
    }

    @Override
    public FluidState getFluidState(BlockPos pos) {
        return this.delegate.getFluidState(pos);
    }

    @Override
    public float getShade(Direction direction, boolean shade) {
        return this.delegate.getShade(direction, shade);
    }

    @Override
    public LevelLightEngine getLightEngine() {
        return this.delegate.getLightEngine();
    }

    @Override
    public int getBlockTint(BlockPos blockPos, ColorResolver colorResolver) {
        return this.delegate.getBlockTint(blockPos, colorResolver);
    }

    // --- CollisionGetter ---

    @Override
    public WorldBorder getWorldBorder() {
        return this.delegate.getWorldBorder();
    }

    @Nullable
    @Override
    public BlockGetter getChunkForCollisions(int chunkX, int chunkZ) {
        return this.delegate.getChunkForCollisions(chunkX, chunkZ);
    }

    @Override
    public List<VoxelShape> getEntityCollisions(@Nullable Entity entity, AABB collisionBox) {
        return this.delegate.getEntityCollisions(entity, collisionBox);
    }

    // --- EntityGetter ---

    @Override
    public List<Entity> getEntities(@Nullable Entity entity, AABB area, Predicate<? super Entity> predicate) {
        return this.delegate.getEntities(entity, area, predicate);
    }

    @Override
    public <T extends Entity> List<T> getEntities(EntityTypeTest<Entity, T> entityTypeTest, AABB bounds,
            Predicate<? super T> predicate) {
        return this.delegate.getEntities(entityTypeTest, bounds, predicate);
    }

    @Override
    public List<? extends Player> players() {
        return this.delegate.players();
    }

    // --- LevelSimulatedReader ---

    @Override
    public boolean isStateAtPosition(BlockPos pos, Predicate<BlockState> state) {
        return this.delegate.isStateAtPosition(pos, state);
    }

    @Override
    public boolean isFluidAtPosition(BlockPos pos, Predicate<FluidState> predicate) {
        return this.delegate.isFluidAtPosition(pos, predicate);
    }

    @Override
    public <T extends BlockEntity> Optional<T> getBlockEntity(BlockPos pos, BlockEntityType<T> blockEntityType) {
        return this.delegate.getBlockEntity(pos, blockEntityType);
    }

    @Override
    public BlockPos getHeightmapPos(Heightmap.Types heightmapType, BlockPos pos) {
        return this.delegate.getHeightmapPos(heightmapType, pos);
    }

    // --- LevelWriter ---

    @Override
    public boolean setBlock(BlockPos pos, BlockState state, int flags, int recursionLeft) {
        return this.delegate.setBlock(pos, state, flags, recursionLeft);
    }

    @Override
    public boolean removeBlock(BlockPos pos, boolean isMoving) {
        return this.delegate.removeBlock(pos, isMoving);
    }

    @Override
    public boolean destroyBlock(BlockPos pos, boolean dropBlock, @Nullable Entity entity, int recursionLeft) {
        return this.delegate.destroyBlock(pos, dropBlock, entity, recursionLeft);
    }

    @Override
    public boolean addFreshEntity(Entity entity) {
        return this.delegate.addFreshEntity(entity);
    }
}
