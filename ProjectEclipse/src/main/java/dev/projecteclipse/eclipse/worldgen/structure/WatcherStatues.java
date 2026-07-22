package dev.projecteclipse.eclipse.worldgen.structure;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * §F flavor landmark: obsidian "watcher statues" at the former team-disc centers, appearing
 * once the intro fusion (stage 1) has swallowed the eight player discs into the main disc.
 * Each statue faces the altar at the origin — a silent audience around the sanctum.
 * Deterministic (positions from {@link DiscGeometry#playerDiscCenter}, heights from the
 * terrain function), so a stage revert + regrow reproduces them exactly.
 */
final class WatcherStatues {
    private WatcherStatues() {}

    /** Builds one statue per former player disc (stage-1 completion hook). */
    static void placeAll(ServerLevel level) {
        StringBuilder placed = new StringBuilder();
        for (int i = 0; i < DiscGeometry.PLAYER_DISC_COUNT; i++) {
            BlockPos center = DiscGeometry.playerDiscCenter(i);
            int ground = build(level, center.getX(), center.getZ());
            placed.append(placed.isEmpty() ? "" : ", ")
                    .append('(').append(center.getX()).append(", ").append(ground)
                    .append(", ").append(center.getZ()).append(')');
        }
        EclipseMod.LOGGER.info("PROCEDURAL: {} watcher statues placed at the former team-disc centers: {}",
                DiscGeometry.PLAYER_DISC_COUNT, placed);
    }

    /**
     * One ~7-block obsidian watcher on a 3×3 polished-blackstone plinth: two legs, a
     * 2-wide torso, shoulders, and a crying-obsidian head weeping towards the altar.
     * Returns the plinth ground Y (for the placement log).
     */
    private static int build(ServerLevel level, int x, int z) {
        level.getChunk(x >> 4, z >> 4);
        int ground = DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z);
        Direction facing = Direction.getNearest(-x, 0, -z);
        Direction width = facing.getClockWise();
        BlockState obsidian = Blocks.OBSIDIAN.defaultBlockState();
        BlockState plinth = Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        BlockPos base = new BlockPos(x, ground, z);

        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                FallbackBuilders.set(level, x + dx, ground, z + dz, plinth);
                for (int y = ground + 1; y <= ground + 8; y++) {
                    FallbackBuilders.set(level, x + dx, y, z + dz, Blocks.AIR.defaultBlockState());
                }
            }
        }
        // Legs (2 high) on the width axis, then the 2-wide torso (3 high).
        BlockPos legA = base.relative(width, 1);
        BlockPos legB = base.relative(width.getOpposite(), 0);
        for (int dy = 1; dy <= 2; dy++) {
            set(level, legA.offset(0, dy, 0), obsidian);
            set(level, legB.offset(0, dy, 0), obsidian);
        }
        for (int dy = 3; dy <= 5; dy++) {
            set(level, legA.offset(0, dy, 0), obsidian);
            set(level, legB.offset(0, dy, 0), obsidian);
        }
        // Shoulders flare one block outward at torso top.
        set(level, legA.relative(width, 1).offset(0, 5, 0), obsidian);
        set(level, legB.relative(width.getOpposite(), 1).offset(0, 5, 0), obsidian);
        // Crying-obsidian head centered over the torso, weeping towards the altar.
        set(level, legB.offset(0, 6, 0), Blocks.CRYING_OBSIDIAN.defaultBlockState());
        set(level, legA.offset(0, 6, 0), Blocks.CRYING_OBSIDIAN.defaultBlockState());
        return ground;
    }

    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        FallbackBuilders.set(level, pos.getX(), pos.getY(), pos.getZ(), state);
    }
}
