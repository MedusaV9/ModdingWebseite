package dev.projecteclipse.eclipse.core.util;

import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;

/**
 * Ground resolution for "return to world spawn" teleports (finale victory, credits
 * home/hold/end_event, arena exits).
 *
 * <p>The naive global {@code MOTION_BLOCKING_NO_LEAVES} heightmap is a trap on this map:
 * from day 12 the End disc hangs at y≈360 over the sanctum, the heightmap resolves to
 * the DISC, and every "home" teleport parks players 270 blocks above the island —
 * reproduced live when the credits HOLD returned the fighter "home behind the black"
 * onto the disc, where he died to ambient magic without ever seeing ground. Same trap
 * family as F-089's structure evacuation; same cure — resolve the ground in a local
 * band around the spawn's OWN Y instead of asking the global heightmap.</p>
 */
public final class SpawnReturns {
    /** Band reach above/below the reference Y ({@code PlacementSafety} scan doctrine). */
    private static final int SCAN_UP = 24;
    private static final int SCAN_DOWN = 16;

    private SpawnReturns() {}

    /**
     * One above the topmost colliding block in the band {@code [refY-16, refY+24]} at
     * (x, z) — can never resolve to the sky disc. Fully open column (void seam next to
     * the island edge): {@code refY} itself, the spawn's own height.
     */
    public static int groundY(ServerLevel level, int x, int z, int refY) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int top = Math.min(refY + SCAN_UP, level.getMaxBuildHeight() - 2);
        int bottom = Math.max(refY - SCAN_DOWN, level.getMinBuildHeight());
        for (int y = top; y >= bottom; y--) {
            cursor.set(x, y, z);
            if (!level.getBlockState(cursor).getCollisionShape(level, cursor).isEmpty()) {
                return y + 1;
            }
        }
        return refY;
    }

    /** {@link #groundY} for a home-spread column, anchored at the shared spawn's own Y. */
    public static int homeY(ServerLevel overworld, BlockPos column) {
        return groundY(overworld, column.getX(), column.getZ(),
                overworld.getSharedSpawnPos().getY());
    }
}
