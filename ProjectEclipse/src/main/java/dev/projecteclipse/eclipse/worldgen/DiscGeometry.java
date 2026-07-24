package dev.projecteclipse.eclipse.worldgen;

import net.minecraft.core.BlockPos;

/**
 * Fixed stage-0 disc layout and geometry helpers for later workers
 * (W4 ring growth / fusion ordering, W5 watcher statues, W6 intro shots).
 *
 * <p>Stage 0 (pre-intro): one main disc of radius {@link #MAIN_DISC_RADIUS} centered on
 * the origin (spawn + altar), plus {@link #PLAYER_DISC_COUNT} player discs of radius
 * {@link #PLAYER_DISC_RADIUS} spaced every 45° on the ring of radius
 * {@link #PLAYER_DISC_RING_RADIUS}. From stage 1 the world is a single fused disc whose
 * radius comes from {@link StageRadii}.</p>
 */
public final class DiscGeometry {
    /** Radius of the stage-0 main disc around the origin. */
    public static final int MAIN_DISC_RADIUS = 96;
    /** Radius of each stage-0 player disc. */
    public static final int PLAYER_DISC_RADIUS = 24;
    /** Radius of the ring the player-disc centers sit on. */
    public static final int PLAYER_DISC_RING_RADIUS = 170;
    /** Deterministic number of player discs, angularly spaced every 45°. */
    public static final int PLAYER_DISC_COUNT = 8;

    private DiscGeometry() {}

    /**
     * Center (y = 0) of player disc {@code index} (wrapped modulo
     * {@link #PLAYER_DISC_COUNT}): on the r=170 ring at angle {@code index · 45°}
     * measured from +X towards +Z. Index 0 = (170, 0), index 2 = (0, 170), …
     */
    public static BlockPos playerDiscCenter(int index) {
        int i = Math.floorMod(index, PLAYER_DISC_COUNT);
        double angle = Math.toRadians(i * (360.0D / PLAYER_DISC_COUNT));
        int x = (int) Math.round(PLAYER_DISC_RING_RADIUS * Math.cos(angle));
        int z = (int) Math.round(PLAYER_DISC_RING_RADIUS * Math.sin(angle));
        return new BlockPos(x, 0, z);
    }

    /** Index of the player disc whose center is nearest to (x, z). */
    public static int nearestPlayerDiscIndex(double x, double z) {
        int best = 0;
        double bestDistSq = Double.MAX_VALUE;
        for (int i = 0; i < PLAYER_DISC_COUNT; i++) {
            BlockPos center = playerDiscCenter(i);
            double dx = x - center.getX();
            double dz = z - center.getZ();
            double distSq = dx * dx + dz * dz;
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                best = i;
            }
        }
        return best;
    }

    /**
     * Radius of the (main) overworld disc at the given stage: {@link #MAIN_DISC_RADIUS}
     * at stage 0, otherwise the fused-disc radius from {@link StageRadii}.
     */
    public static int mainDiscRadius(int stage) {
        return stage <= 0 ? MAIN_DISC_RADIUS : StageRadii.radius(DiscProfile.OVERWORLD, stage);
    }

    /**
     * Whether the column (x, z) is within the nominal stage-0 overworld footprint
     * (main disc or any player disc), IGNORING rim noise — use
     * {@link DiscTerrainFunction#column} for the exact shape.
     */
    public static boolean isInStageZeroFootprint(double x, double z) {
        if (x * x + z * z <= (double) MAIN_DISC_RADIUS * MAIN_DISC_RADIUS) {
            return true;
        }
        for (int i = 0; i < PLAYER_DISC_COUNT; i++) {
            BlockPos center = playerDiscCenter(i);
            double dx = x - center.getX();
            double dz = z - center.getZ();
            if (dx * dx + dz * dz <= (double) PLAYER_DISC_RADIUS * PLAYER_DISC_RADIUS) {
                return true;
            }
        }
        return false;
    }
}
