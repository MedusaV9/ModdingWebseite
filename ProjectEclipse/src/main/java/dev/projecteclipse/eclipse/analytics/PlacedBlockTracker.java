package dev.projecteclipse.eclipse.analytics;

import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.chunk.LevelChunk;

/**
 * O(1) player-placed block tracker over the {@code eclipse:placed_blocks} chunk attachment
 * (P4 §2.4 — THE anti-abuse primitive; consumed by skills T2/T6, the double-ore buff, goal
 * {@code naturalOnly} triggers and the awards mining categories via analytics).
 *
 * <p>Semantics: {@link #markPlaced} on player placement, {@link #clear} on player break
 * (after the natural check, so re-placing the same spot re-marks), {@link #isPlaced} = bit
 * set. Explosions, pistons and fluid washes do NOT update bits — a stale bit can only
 * mis-flag a later block at that exact position as "player-placed", which UNDER-credits
 * (never mints XP): fails safe by design (plans_v3 P4 §5 risk 4). Worldgen and ring-growth
 * writes never mark (they write {@code LevelChunkSection}s directly and fire no
 * {@code EntityPlaceEvent}).</p>
 *
 * <p>Memory: one lazily-allocated {@code long[64]} (512 bytes) per 16×16×16 section that has
 * ever seen a player placement; untouched sections cost nothing.</p>
 */
public final class PlacedBlockTracker {
    private PlacedBlockTracker() {}

    /** Sets the placed bit for {@code pos} (any dimension) and marks the chunk for saving. */
    public static void markPlaced(ServerLevel level, BlockPos pos) {
        LevelChunk chunk = level.getChunkAt(pos);
        PlacedBlockData data = chunk.getData(EclipseAttachments.PLACED_BLOCKS);
        long[] bits = data.sectionBits(sectionIndex(pos), true);
        int bit = bitIndex(pos);
        bits[bit >>> 6] |= 1L << (bit & 63);
        chunk.setUnsaved(true);
    }

    /** Whether {@code pos} holds a player-placed block. O(1); never allocates attachment data. */
    public static boolean isPlaced(ServerLevel level, BlockPos pos) {
        LevelChunk chunk = level.getChunkAt(pos);
        PlacedBlockData data = chunk.getExistingDataOrNull(EclipseAttachments.PLACED_BLOCKS.get());
        if (data == null) {
            return false;
        }
        long[] bits = data.sectionBits(sectionIndex(pos), false);
        if (bits == null) {
            return false;
        }
        int bit = bitIndex(pos);
        return (bits[bit >>> 6] & (1L << (bit & 63))) != 0L;
    }

    /**
     * Clears the placed bit for {@code pos}; returns whether it was set (the break-event
     * natural check uses the return value so mark + verdict is a single chunk lookup).
     */
    public static boolean clear(ServerLevel level, BlockPos pos) {
        LevelChunk chunk = level.getChunkAt(pos);
        PlacedBlockData data = chunk.getExistingDataOrNull(EclipseAttachments.PLACED_BLOCKS.get());
        if (data == null) {
            return false;
        }
        long[] bits = data.sectionBits(sectionIndex(pos), false);
        if (bits == null) {
            return false;
        }
        int bit = bitIndex(pos);
        long mask = 1L << (bit & 63);
        if ((bits[bit >>> 6] & mask) == 0L) {
            return false;
        }
        bits[bit >>> 6] &= ~mask;
        chunk.setUnsaved(true);
        return true;
    }

    /** Section Y index of the position (arithmetic shift handles negative Y). */
    static int sectionIndex(BlockPos pos) {
        return pos.getY() >> 4;
    }

    /** Bit index of the position inside its section bitset: {@code (y&15)<<8 | (z&15)<<4 | (x&15)}. */
    static int bitIndex(BlockPos pos) {
        return ((pos.getY() & 15) << 8) | ((pos.getZ() & 15) << 4) | (pos.getX() & 15);
    }
}
