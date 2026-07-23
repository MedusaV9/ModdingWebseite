package dev.projecteclipse.eclipse.analytics;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import it.unimi.dsi.fastutil.longs.LongOpenHashSet;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.biome.Biome;

/**
 * The 1 Hz analytics sampler (P4 §2.4): playtime, distance, depth, new-chunk and new-biome
 * accumulation for every online tracked player. Driven by {@link AnalyticsService}'s tick
 * subscriber every 20 ticks — O(online players), no allocation on the steady-state path
 * (scratch {@link BlockPos.MutableBlockPos}, non-capturing factory lambdas, primitive sets).
 *
 * <p>Teleport hardening: each distance sample is capped at
 * {@code analytics.json distanceSampleCapCm} (default 100 m) and a dimension change resets
 * the anchor, so warps and portal hops never mint distance. Per-day chunk sets are capped
 * ({@code chunkSetCap}) — beyond the cap new chunks stop counting (fail-safe under-credit).</p>
 */
public final class AnalyticsSampler {
    private static final class Anchor {
        ResourceKey<Level> dimension;
        double x;
        double y;
        double z;
    }

    // statics reset on ServerStopped (via AnalyticsService.onServerStopped -> reset())
    private static final Map<UUID, Anchor> ANCHORS = new HashMap<>();
    // statics reset on ServerStopped; also cleared per day on rollover PRE (via clearDayScratch)
    private static final Map<UUID, LongOpenHashSet> CHUNKS_TODAY = new HashMap<>();
    /** Scratch position — server-thread only, reused to keep the hot path allocation-free. */
    private static final BlockPos.MutableBlockPos SCRATCH_POS = new BlockPos.MutableBlockPos();

    private AnalyticsSampler() {}

    /** One full sampler pass over all online players. Called every 20 ticks by the service. */
    public static void samplePass(MinecraftServer server) {
        AnalyticsConfig.Data cfg = AnalyticsConfig.get();
        if (!cfg.samplerEnabled()) {
            return;
        }
        samplePlayers(server, server.getPlayerList().getPlayers(), cfg);
    }

    /**
     * Sampler core over an explicit player list — public so the perf gametest can drive
     * mock players that are not registered in the {@code PlayerList}.
     */
    public static void samplePlayers(MinecraftServer server, List<ServerPlayer> players,
            AnalyticsConfig.Data cfg) {
        int day = AnalyticsService.currentDay(server);
        AnalyticsState state = AnalyticsState.get(server);
        for (int i = 0; i < players.size(); i++) {
            ServerPlayer player = players.get(i);
            if (AnalyticsService.isTracked(player)) {
                samplePlayer(state, day, player, cfg);
            }
        }
    }

    private static void samplePlayer(AnalyticsState state, int day, ServerPlayer player,
            AnalyticsConfig.Data cfg) {
        UUID id = player.getUUID();

        // Playtime: one second per 20-tick sample while online.
        state.add(day, id, AnalyticsKeys.PLAYTIME_S, 1L);

        // Depth: stored as 4096 - y so "max" aggregation finds the deepest dive.
        int blockY = player.getBlockY();
        state.max(day, id, AnalyticsKeys.DEPTH_MIN_Y, 4096L - blockY);

        // Distance: capped 3D delta since the previous sample in the same dimension.
        Anchor anchor = ANCHORS.computeIfAbsent(id, key -> new Anchor());
        ResourceKey<Level> dimension = player.level().dimension();
        double px = player.getX();
        double py = player.getY();
        double pz = player.getZ();
        if (anchor.dimension == dimension) {
            long deltaCm = sampleDeltaCm(anchor.x, anchor.y, anchor.z, px, py, pz,
                    cfg.distanceSampleCapCm());
            if (deltaCm > 0L) {
                state.add(day, id, AnalyticsKeys.DIST_CM, deltaCm);
            }
        }
        anchor.dimension = dimension;
        anchor.x = px;
        anchor.y = py;
        anchor.z = pz;

        // New chunks (per-day-distinct, capped set).
        int chunkX = player.getBlockX() >> 4;
        int chunkZ = player.getBlockZ() >> 4;
        long chunkKey = ChunkPos.asLong(chunkX, chunkZ);
        LongOpenHashSet chunks = CHUNKS_TODAY.computeIfAbsent(id, key -> new LongOpenHashSet());
        if (!chunks.contains(chunkKey) && chunks.size() < cfg.chunkSetCap()) {
            chunks.add(chunkKey);
            state.add(day, id, AnalyticsKeys.CHUNKS_NEW, 1L);
            EclipseSignals.fireChunkExplored(player, new ChunkPos(chunkX, chunkZ));
        }

        // New biomes (lifetime-distinct set persisted in AnalyticsState; per-day count).
        SCRATCH_POS.set(player.getBlockX(), blockY, player.getBlockZ());
        Optional<ResourceKey<Biome>> biomeKey = player.level().getBiome(SCRATCH_POS).unwrapKey();
        if (biomeKey.isPresent()) {
            ResourceLocation biomeId = biomeKey.get().location();
            if (state.markBiomeVisited(id, biomeId.toString())) {
                state.add(day, id, AnalyticsKeys.BIOMES, 1L);
                EclipseSignals.fireBiomeVisited(player, biomeId);
            }
        }
    }

    /**
     * Pure sample-delta math: euclidean 3D distance in whole centimetres, clamped to
     * {@code capCm} so a teleport contributes at most one capped sample (§3.6 acceptance).
     */
    public static long sampleDeltaCm(double x0, double y0, double z0,
            double x1, double y1, double z1, long capCm) {
        double dx = x1 - x0;
        double dy = y1 - y0;
        double dz = z1 - z0;
        long cm = (long) Math.floor(Math.sqrt(dx * dx + dy * dy + dz * dz) * 100.0D);
        return Math.min(Math.max(0L, cm), capCm);
    }

    /** Clears the per-day chunk scratch (rollover PRE — day N+1 counts chunks fresh). */
    static void clearDayScratch() {
        CHUNKS_TODAY.clear();
    }

    /** Drops every anchor and scratch set. Called from the service's ServerStopped reset. */
    static void reset() {
        ANCHORS.clear();
        CHUNKS_TODAY.clear();
    }
}
