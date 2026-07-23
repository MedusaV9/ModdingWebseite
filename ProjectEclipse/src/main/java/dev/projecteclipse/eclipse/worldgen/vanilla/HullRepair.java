package dev.projecteclipse.eclipse.worldgen.vanilla;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.LevelChunkSection;

import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;

/**
 * Hull guard of the vanilla pipeline (design D1.2/D1.3): after carvers and after
 * decoration it re-asserts, column by column against the pure
 * {@link DiscTerrainFunction}, the parts of the disc that must never be punctured or
 * littered — while leaving everything above/inside the playable body exactly as the
 * vanilla pipeline shaped it (carvers MAY breach the top surface; that is where natural
 * cave entrances come from).
 *
 * <p>Per column (all bounds from the column snapshot, so this is deterministic and
 * replay-safe):</p>
 * <ul>
 *   <li><b>Seal band</b> — {@code bottomY … undersideY+3}: bedrock seal
 *       ({@code y ≤ groundBottomY+2}), stalactite fringe ({@code y < undersideY+4}) and
 *       hanging rim decor are restored to the terrain function's exact states
 *       (both passes).</li>
 *   <li><b>Rim knife edge</b> — columns whose remaining thickness says the smoothstep
 *       edge factor is below ~0.25 (the last ~6 blocks of the taper) get their whole
 *       ground span {@code bottomY … surfaceY} re-asserted, so no carver or lake can
 *       cut the silhouette (both passes).</li>
 *   <li><b>Void cleanup</b> — decoration pass only: any block a feature leaked below
 *       the column bottom, or into a fully-void column (beyond the rim, crumble holes),
 *       is deleted. Trees at the very rim get canopy overhang clipped — accepted; the
 *       alternative is floating debris over the void.</li>
 * </ul>
 *
 * <p>Writes go through {@code ChunkAccess.setBlockState(pos, state, false)} and only
 * where the actual state differs, so a clean chunk costs a read-only scan of the edge/
 * underside bands. Runs on worldgen worker threads (generation) and on the server
 * thread (live replay); {@code W1.7}'s underside {@code ExtraDecor} stamps run AFTER
 * {@link #afterDecoration}, so intentional hanging dressing is never wiped.</p>
 */
public final class HullRepair {
    /**
     * Column-thickness ratio equivalent of {@code edgeFactor < 0.25}: thickness scales
     * as {@code 0.08 + 0.92 · edge} of the full lens thickness in
     * {@link DiscTerrainFunction#column}, so edge 0.25 keeps ~31 % — with a hair of
     * margin for integer rounding. Keep in sync with the terrain function's taper.
     */
    private static final double RIM_SEAL_THICKNESS_RATIO = 0.32D;
    /** Seal band top offset above {@code undersideY} (the fringe band is {@code y < undersideY+4}). */
    private static final int SEAL_BAND_ABOVE_UNDERSIDE = 3;

    private static final BlockState AIR = Blocks.AIR.defaultBlockState();

    private HullRepair() {}

    /** Re-asserts the seal band and rim knife-edge columns after carving. */
    public static void afterCarving(DiscProfile profile, ChunkAccess chunk) {
        repair(profile, chunk, false);
    }

    /**
     * {@link #afterCarving} plus feature-leak deletion below the hull and in void
     * columns, after vanilla decoration (and before registered {@code ExtraDecor}s).
     */
    public static void afterDecoration(DiscProfile profile, ChunkAccess chunk) {
        repair(profile, chunk, true);
    }

    private static void repair(DiscProfile profile, ChunkAccess chunk, boolean decorationPass) {
        int stage = WorldStageAccess.stage(profile);
        DiscMapData map = DiscMapData.get();
        ChunkPos pos = chunk.getPos();
        int minBuild = chunk.getMinBuildHeight();
        int maxY = chunk.getMaxBuildHeight() - 1;

        // Emptiness snapshot BEFORE any writes: sections empty now cannot contain
        // feature leakage, so deletion scans may skip them wholesale. Repair writes
        // only re-add terrain, never deletable content, so the snapshot stays valid.
        LevelChunkSection[] sections = chunk.getSections();
        boolean[] mayHaveBlocks = new boolean[sections.length];
        for (int i = 0; i < sections.length; i++) {
            mayHaveBlocks[i] = !sections[i].hasOnlyAir();
        }

        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int lx = 0; lx < 16; lx++) {
            int x = pos.getMinBlockX() + lx;
            for (int lz = 0; lz < 16; lz++) {
                int z = pos.getMinBlockZ() + lz;
                DiscColumn column = DiscTerrainFunction.column(profile, x, z, stage, map);
                if (!column.inside()) {
                    if (decorationPass) {
                        deleteLeaks(chunk, cursor, x, z, minBuild, maxY, mayHaveBlocks);
                    }
                    continue;
                }
                int sealBottom = Math.max(column.bottomY(), minBuild);
                int sealTop = Math.min(column.undersideY() + SEAL_BAND_ABOVE_UNDERSIDE, maxY);
                int assertTop = isRimColumn(profile, column)
                        ? Math.min(column.surfaceY(), maxY)
                        : sealTop;
                for (int y = sealBottom; y <= assertTop; y++) {
                    BlockState expected = DiscTerrainFunction.stateInColumn(column, y);
                    if (chunk.getBlockState(cursor.set(x, y, z)) != expected) {
                        chunk.setBlockState(cursor, expected, false);
                    }
                }
                if (decorationPass && sealBottom > minBuild) {
                    deleteLeaks(chunk, cursor, x, z, minBuild, sealBottom - 1, mayHaveBlocks);
                }
            }
        }
    }

    /**
     * Whether the column sits in the outermost few blocks of the rim taper
     * ({@code edgeFactor < ~0.25}), reconstructed from the thickness the taper left:
     * these columns get a full-span re-seal so the knife edge survives carving.
     * Detached floating shards are excluded — their thickness is unrelated to the taper
     * (the seal band already covers their whole 2-4 block body).
     */
    private static boolean isRimColumn(DiscProfile profile, DiscColumn column) {
        if (column.shard()) {
            return false;
        }
        int thickness = column.surfaceY() - column.undersideY();
        int lensBottom = (int) Math.floor(profile.lensBottomY(column.radial()));
        int fullThickness = Math.max(4, column.surfaceY() - lensBottom);
        return thickness <= fullThickness * RIM_SEAL_THICKNESS_RATIO;
    }

    /** Deletes every non-air block in {@code minY..maxY} of the column, skipping empty sections. */
    private static void deleteLeaks(ChunkAccess chunk, BlockPos.MutableBlockPos cursor, int x, int z,
            int minY, int maxY, boolean[] mayHaveBlocks) {
        int y = minY;
        while (y <= maxY) {
            int sectionIndex = chunk.getSectionIndex(y);
            if (sectionIndex >= 0 && sectionIndex < mayHaveBlocks.length && !mayHaveBlocks[sectionIndex]) {
                y = (((y >> 4) + 1) << 4); // skip to the next section floor
                continue;
            }
            if (!chunk.getBlockState(cursor.set(x, y, z)).isAir()) {
                chunk.setBlockState(cursor, AIR, false);
            }
            y++;
        }
    }
}
