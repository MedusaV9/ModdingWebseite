package dev.projecteclipse.eclipse.buffs;

import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.chunk.LevelChunk;

/**
 * Minimal placed-block lookup for ore-drop buffs until P4-B5's {@code PlacedBlockTracker} lands.
 * Reads the chunk attachment directly (O(1) bit test).
 */
public final class PlacedBlockCheck {
    private PlacedBlockCheck() {}

    /** {@code true} when the block at {@code pos} was player-placed. */
    public static boolean isPlaced(ServerLevel level, BlockPos pos) {
        if (!(level.getChunkAt(pos) instanceof LevelChunk chunk)) {
            return false;
        }
        PlacedBlockData data = chunk.getData(EclipseAttachments.PLACED_BLOCKS);
        if (data == null) {
            return false;
        }
        int sectionIndex = level.getSectionIndex(pos.getY());
        long[] bits = data.sectionBits(sectionIndex, false);
        if (bits == null) {
            return false;
        }
        int localX = pos.getX() & 15;
        int localY = pos.getY() & 15;
        int localZ = pos.getZ() & 15;
        int blockIndex = (localY << 8) | (localZ << 4) | localX;
        int longIndex = blockIndex >> 6;
        int bitIndex = blockIndex & 63;
        if (longIndex >= bits.length) {
            return false;
        }
        return ((bits[longIndex] >> bitIndex) & 1L) != 0L;
    }

    /** {@code true} when the block is natural (not player-placed). */
    public static boolean isNatural(ServerLevel level, BlockPos pos) {
        return !isPlaced(level, pos);
    }
}
