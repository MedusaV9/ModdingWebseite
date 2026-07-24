package dev.projecteclipse.eclipse.minigames;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Tick-budgeted course block IO on top of {@link BudgetedBlockWriter} (W14's shared bulk
 * writer). Course layouts are pure {@code seed → List<Placement>} functions, so building
 * is "clear the OLD layout's positions, then write the NEW layout" — both jobs are plain
 * {@code setBlock} loops sliced by the writer's shared per-tick budget, idempotent and
 * safe to re-run after a crash (the seeds are persisted in {@link MinigameState}).
 */
public final class CourseBlocks {

    /** One deterministic course block. */
    public record Placement(BlockPos pos, BlockState state) {}

    private CourseBlocks() {}

    /** Enqueues writing every placement (chunks are sync-loaded under writer tickets). */
    static void enqueueBuild(ServerLevel level, List<Placement> placements, Runnable onComplete) {
        enqueue(level, placements, false, onComplete);
    }

    /** Enqueues writing AIR at every placement position (skips already-air positions). */
    static void enqueueClear(ServerLevel level, List<Placement> placements, Runnable onComplete) {
        enqueue(level, placements, true, onComplete);
    }

    private static void enqueue(ServerLevel level, List<Placement> placements, boolean clear,
            Runnable onComplete) {
        BudgetedBlockWriter.enqueue(level, new BudgetedBlockWriter.BudgetedWork() {
            private int cursor;

            @Override
            public boolean run(int operationBudget) {
                int end = Math.min(placements.size(), cursor + operationBudget);
                while (cursor < end) {
                    Placement placement = placements.get(cursor++);
                    BlockPos pos = placement.pos();
                    if (level.getChunkSource().getChunkNow(pos.getX() >> 4, pos.getZ() >> 4) == null) {
                        BudgetedBlockWriter.loadWithTicket(level, pos.getX() >> 4, pos.getZ() >> 4);
                    }
                    if (clear) {
                        if (!level.getBlockState(pos).isAir()) {
                            level.setBlock(pos, Blocks.AIR.defaultBlockState(), 3);
                        }
                    } else {
                        level.setBlock(pos, placement.state(), 3);
                    }
                }
                return cursor >= placements.size();
            }
        }, onComplete, failure -> EclipseMod.LOGGER.error(
                "Minigame course {} failed in {}", clear ? "clear" : "build",
                level.dimension().location(), failure));
    }
}
