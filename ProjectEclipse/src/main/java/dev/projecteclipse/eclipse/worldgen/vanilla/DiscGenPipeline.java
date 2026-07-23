package dev.projecteclipse.eclipse.worldgen.vanilla;

import java.util.EnumSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

import com.mojang.logging.LogUtils;

import org.slf4j.Logger;

import net.minecraft.core.Holder;
import net.minecraft.core.RegistryAccess;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.NaturalSpawner;
import net.minecraft.world.level.ServerLevelAccessor;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.biome.Biome;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.LegacyRandomSource;
import net.minecraft.world.level.levelgen.WorldgenRandom;

import dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;

/**
 * The unified vanilla-integration sequence of the disc world (design D1.5): the same
 * <b>carve &rarr; decorate &rarr; seed mobs</b> pipeline callable from both worlds the disc
 * lives in —
 *
 * <ol>
 *   <li><b>Chunk generation</b> (ProtoChunk path): {@link DiscChunkGenerator} delegates its
 *       {@code applyCarvers} / {@code applyBiomeDecoration} / {@code spawnOriginalMobs}
 *       overrides to the phase entries here, in vanilla status order.</li>
 *   <li><b>Ring growth</b> (live-chunk path): after a GROW sweep rewrites a chunk's base
 *       terrain, {@link #runOnLiveChunk} replays the exact same phases on the live
 *       {@code LevelChunk} — same fixed seed, same phase order, same hull guards — so grown
 *       chunks are block-identical to what fresh generation at the new stage would produce
 *       (design D3; W1.5 calls this before its heightmap re-prime and relight/resend, W1.6
 *       may call it for site-prep regeneration).</li>
 * </ol>
 *
 * <p>Every phase seeds itself from {@link #fixedSeed()} (the frozen map seed, design D9),
 * never from the per-save world seed. Decoration is wrapped in {@link FixedSeedGenRegion}
 * by the generator's {@code applyBiomeDecoration} override — the single canonical
 * decoration sequence for both paths — and is followed by {@link HullRepair#afterDecoration}
 * plus the registered {@link ExtraDecor}s (in that order: hull repair must never wipe
 * intentional hanging dressing).</p>
 *
 * <p>{@link #runOnLiveChunk} must run on the server thread: decoration writes through
 * {@code ServerLevel.setBlock} and mob seeding adds entities. Carving writes only through
 * {@code ChunkAccess.setBlockState} (no neighbour updates); the caller owns the follow-up
 * heightmap re-prime, relight and resend (existing sweep machinery).</p>
 */
public final class DiscGenPipeline {
    private static final Logger LOGGER = LogUtils.getLogger();

    /**
     * Heightmaps primed immediately before decoration — the same set vanilla's FEATURES
     * status task primes, so live-chunk replays hand {@code applyBiomeDecoration} inputs
     * that are byte-identical to the chunk-generation path.
     */
    private static final Set<Heightmap.Types> DECORATION_HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR, Heightmap.Types.WORLD_SURFACE);

    /**
     * A post-decoration stamp of the disc pipeline (compile seam §3.10): runs after vanilla
     * decoration AND after {@link HullRepair#afterDecoration} on both the chunk-generation
     * and live-chunk paths (W1.7 registers its nether underside dressing here). The level
     * handed in reports {@link #fixedSeed()} from {@code getSeed()}, so implementations
     * seeded from it are save-independent; {@code chunk} is the decorated center chunk.
     */
    @FunctionalInterface
    public interface ExtraDecor {
        void decorate(WorldGenLevel level, ChunkAccess chunk);
    }

    /** Registered extra decors per profile; iterated in registration order. */
    private static final Map<DiscProfile, List<ExtraDecor>> EXTRA_DECOR = new ConcurrentHashMap<>();

    private DiscGenPipeline() {}

    /**
     * Registers a post-decoration stamp for every chunk of the given profile's disc, on
     * both generation paths (compile seam §3.10). Call once at mod setup — registration is
     * thread-safe, but a decor registered after the first chunk decorated will only cover
     * chunks from then on (earlier chunks replay it only through a sweep).
     */
    public static void registerExtraDecor(DiscProfile profile, ExtraDecor decor) {
        EXTRA_DECOR.computeIfAbsent(profile, key -> new CopyOnWriteArrayList<>()).add(decor);
    }

    /**
     * The frozen map seed (design D9) every pipeline phase seeds itself from — never the
     * per-save world seed, so carving, decoration and replay are identical in every save
     * with the same frozen params.
     */
    public static long fixedSeed() {
        return FrozenParams.mapSeed();
    }

    /**
     * Carve phase: vanilla carvers via {@link DiscCarverEngine}, then
     * {@link HullRepair#afterCarving} re-seals the hull. Called by the generator's
     * {@code applyCarvers} override (chunk generation) and {@link #runOnLiveChunk}.
     * Safe on worldgen worker threads.
     */
    public static void carve(DiscChunkGenerator generator, RegistryAccess registryAccess, ChunkAccess chunk,
            GenerationStep.Carving step) {
        DiscCarverEngine.carve(generator, registryAccess, chunk, step);
        HullRepair.afterCarving(generator.profile(), chunk);
    }

    /**
     * Post-decoration phase: {@link HullRepair#afterDecoration} (feature-leak cleanup +
     * hull re-seal), then the registered {@link ExtraDecor}s in registration order. Called
     * by the generator's {@code applyBiomeDecoration} override right after
     * {@code super.applyBiomeDecoration} on both paths — {@code level} is the
     * {@link FixedSeedGenRegion}-wrapped level the vanilla features decorated through.
     */
    public static void afterDecoration(DiscProfile profile, WorldGenLevel level, ChunkAccess chunk) {
        HullRepair.afterDecoration(profile, chunk);
        List<ExtraDecor> decors = EXTRA_DECOR.get(profile);
        if (decors != null) {
            for (ExtraDecor decor : decors) {
                decor.decorate(level, chunk);
            }
        }
    }

    /**
     * Mob-seeding phase (design D1.4): the vanilla chunk-generation animal seeding
     * ({@link NaturalSpawner#spawnMobsForChunkGeneration}) with the decoration random
     * seeded from {@link #fixedSeed()}. Works on both {@code WorldGenRegion} (called by the
     * generator's {@code spawnOriginalMobs}) and {@code ServerLevel} (live replay).
     */
    public static void seedMobs(ServerLevelAccessor level, ChunkPos center) {
        Holder<Biome> biome = level.getBiome(center.getWorldPosition().atY(level.getMaxBuildHeight() - 1));
        long seed = fixedSeed();
        WorldgenRandom random = new WorldgenRandom(new LegacyRandomSource(seed));
        random.setDecorationSeed(seed, center.getMinBlockX(), center.getMinBlockZ());
        NaturalSpawner.spawnMobsForChunkGeneration(level, biome, center, random);
    }

    /**
     * Replays the full pipeline — carve (AIR step, like the vanilla status pipeline),
     * heightmap re-prime, decorate (fixed-seed wrap + hull repair + extra decors via the
     * generator override), seed animals — on an already-generated live chunk (compile seam
     * §3.10; design D3). Call on the server thread after the sweep rewrote the chunk's
     * base terrain; the caller re-primes heightmaps/light and resends afterwards.
     *
     * <p>Chunks with no solid sections are skipped: the vanilla phases are provable no-ops
     * on fully-void chunks (features ground-probe, carvers early-out), so skipping cannot
     * diverge from chunk generation — and it protects against replaying a chunk whose base
     * rewrite has not happened yet.</p>
     */
    public static void runOnLiveChunk(ServerLevel level, LevelChunk chunk) {
        if (!(level.getChunkSource().getGenerator() instanceof DiscChunkGenerator generator)) {
            LOGGER.warn("eclipse: DiscGenPipeline.runOnLiveChunk called for {} at {}, which is not a disc dimension",
                    level.dimension().location(), chunk.getPos());
            return;
        }
        if (!hasAnySolidSection(chunk)) {
            return;
        }
        carve(generator, level.registryAccess(), chunk, GenerationStep.Carving.AIR);
        Heightmap.primeHeightmaps(chunk, DECORATION_HEIGHTMAPS);
        generator.applyBiomeDecoration(level, chunk, level.structureManager());
        seedMobs(level, chunk.getPos());
    }

    private static boolean hasAnySolidSection(LevelChunk chunk) {
        for (LevelChunkSection section : chunk.getSections()) {
            if (!section.hasOnlyAir()) {
                return true;
            }
        }
        return false;
    }
}
