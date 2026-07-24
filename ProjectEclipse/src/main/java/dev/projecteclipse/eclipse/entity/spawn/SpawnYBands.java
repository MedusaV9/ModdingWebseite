package dev.projecteclipse.eclipse.entity.spawn;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.MobCategory;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.level.Level;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.FinalizeSpawnEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;

/**
 * PLAN-B B5 (plans_v5): natural-spawn Y-band support for the floating discs.
 *
 * <p><b>Why:</b> vanilla's runtime spawn cycle rolls a random Y in
 * {@code [minBuildHeight, WORLD_SURFACE_top]} per attempt
 * ({@code NaturalSpawner.getRandomPosWithin}). On the overworld disc most of that band is
 * under-disc VOID (below {@code DiscColumn.undersideY()}), and in the nether the sealed
 * roof shell reaches the world top — so the overwhelming majority of attempts land in
 * dead space and the per-cycle spawn hit rate collapses far below vanilla terrain.
 * {@code mixin/NaturalSpawnerMixin} calls {@link #adjust} on every rolled position to
 * re-band the Y into the column's actually-populated range.</p>
 *
 * <p><b>Bands</b> (per plan B5 fix 1):</p>
 * <ul>
 *   <li>Overworld disc column: {@code [undersideY, surfaceY + 1]} — spans the cave band
 *       (caves live between underside and surface) plus the stand-on-surface block.</li>
 *   <li>End disc footprint (once materialized): {@code [EndDiscGeometry.MIN_Y,
 *       lens surface + 1]} — weighted alongside the main band so endermen keep spawning
 *       on the in-sky lens.</li>
 *   <li>Nether column: {@code [floor surfaceY − 8, ceilingBottomY − 1]} — the open
 *       cavern between floor and roof shell, plus a little floor-cave headroom.</li>
 *   <li>Non-disc dimensions and off-disc (void) columns are left untouched.</li>
 * </ul>
 *
 * <p>Everything is instrumented: per-dimension attempt/band counters plus NATURAL
 * {@link FinalizeSpawnEvent} successes by {@link MobCategory}, surfaced in-game via
 * {@code /dev spawn census} ({@code DevSpawnCommands}) so the fix is verifiable live.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SpawnYBands {
    /** Floor-cave headroom below the nether floor surface included in the band. */
    private static final int NETHER_FLOOR_HEADROOM = 8;
    /** Fallback band height above the nether floor when a column carries no roof data. */
    private static final int NETHER_NO_ROOF_SPAN = 48;

    /** Mutable per-dimension counters (server thread; snapshot via {@link #census}). */
    public static final class DimCensus {
        private long attempts;
        private long inBand;
        private long rebanded;
        private long offDisc;
        private final long[] naturalByCategory = new long[MobCategory.values().length];

        public long attempts() {
            return attempts;
        }

        /** Rolled Y already inside a populated band (left untouched). */
        public long inBand() {
            return inBand;
        }

        /** Rolled Y re-banded out of dead space into a populated band. */
        public long rebanded() {
            return rebanded;
        }

        /** Attempts on void/off-disc columns (left untouched; vanilla discards them). */
        public long offDisc() {
            return offDisc;
        }

        /** NATURAL finalizeSpawn count of the given category since the last reset. */
        public long naturalSpawns(MobCategory category) {
            return naturalByCategory[category.ordinal()];
        }

        public long naturalSpawnsTotal() {
            long sum = 0L;
            for (long count : naturalByCategory) {
                sum += count;
            }
            return sum;
        }
    }

    // statics reset on ServerStopped
    private static final Map<ResourceKey<Level>, DimCensus> CENSUS = new ConcurrentHashMap<>();
    // statics reset on ServerStopped
    private static volatile long resetAtMillis = System.currentTimeMillis();

    private SpawnYBands() {}

    /**
     * Re-bands one rolled spawn position (mixin seam — see class doc). Returns the input
     * instance unchanged when no adjustment applies, so the caller can identity-compare.
     */
    public static BlockPos adjust(Level level, BlockPos pos) {
        if (!(level instanceof ServerLevel serverLevel)) {
            return pos;
        }
        DiscProfile profile = WorldStageService.profileOf(serverLevel.dimension());
        if (profile == null) {
            return pos; // limbo & friends: vanilla behavior
        }
        DimCensus census = census(serverLevel.dimension());
        census.attempts++;

        int x = pos.getX();
        int z = pos.getZ();
        int minY = level.getMinBuildHeight() + 1;
        int maxY = level.getMaxBuildHeight() - 1;

        // Main disc band of this column (pure frozen-data function; cheap).
        int discLo = Integer.MIN_VALUE;
        int discHi = Integer.MIN_VALUE;
        DiscTerrainFunction.DiscColumn col =
                DiscTerrainFunction.column(profile, x, z, WorldStageAccess.stage(profile));
        if (col.inside()) {
            if (profile == DiscProfile.NETHER) {
                int roof = col.ceilingBottomY() != Integer.MAX_VALUE
                        ? col.ceilingBottomY() - 1
                        : col.surfaceY() + NETHER_NO_ROOF_SPAN;
                discLo = Math.max(minY, col.surfaceY() - NETHER_FLOOR_HEADROOM);
                discHi = Math.min(maxY, Math.max(discLo, roof));
            } else {
                discLo = Math.max(minY, col.undersideY());
                discHi = Math.min(maxY, Math.max(discLo, col.surfaceY() + 1));
            }
        }

        // End-disc band (overworld only, once the lens has materialized).
        int endLo = Integer.MIN_VALUE;
        int endHi = Integer.MIN_VALUE;
        if (profile == DiscProfile.OVERWORLD && FrozenParams.endDiscMaterialized()
                && EndDiscGeometry.footprintContains(x, z)) {
            endLo = EndDiscGeometry.MIN_Y;
            endHi = Math.min(maxY, Math.max(endLo, EndDiscGeometry.surfaceYAt(x, z) + 1));
        }

        boolean hasDisc = discLo != Integer.MIN_VALUE;
        boolean hasEnd = endLo != Integer.MIN_VALUE;
        if (!hasDisc && !hasEnd) {
            census.offDisc++;
            return pos; // void column; vanilla's min-height check discards the attempt
        }
        int y = pos.getY();
        if ((hasDisc && y >= discLo && y <= discHi) || (hasEnd && y >= endLo && y <= endHi)) {
            census.inBand++;
            return pos;
        }
        // Re-roll the Y uniformly across the populated band(s), weighted by band height —
        // same uniform-per-block distribution vanilla uses, minus the dead space.
        int discSpan = hasDisc ? discHi - discLo + 1 : 0;
        int endSpan = hasEnd ? endHi - endLo + 1 : 0;
        int roll = level.random.nextInt(discSpan + endSpan);
        int bandedY = roll < discSpan ? discLo + roll : endLo + (roll - discSpan);
        census.rebanded++;
        return new BlockPos(x, bandedY, z);
    }

    // --- census surface (read by DevSpawnCommands) ---

    /** Live counter object of the dimension (created on demand; do not mutate). */
    public static DimCensus census(ResourceKey<Level> dimension) {
        return CENSUS.computeIfAbsent(dimension, key -> new DimCensus());
    }

    /** Milliseconds since the counters were last reset (boot or {@code /dev spawn census reset}). */
    public static long millisSinceReset() {
        return System.currentTimeMillis() - resetAtMillis;
    }

    /** Clears all counters ({@code /dev spawn census reset}). */
    public static void reset() {
        CENSUS.clear();
        resetAtMillis = System.currentTimeMillis();
    }

    // --- success instrumentation ---

    @SubscribeEvent
    static void onFinalizeSpawn(FinalizeSpawnEvent event) {
        if (event.getSpawnType() != MobSpawnType.NATURAL) {
            return;
        }
        ServerLevel level = event.getLevel().getLevel();
        DimCensus census = census(level.dimension());
        census.naturalByCategory[event.getEntity().getType().getCategory().ordinal()]++;
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        reset();
    }
}
