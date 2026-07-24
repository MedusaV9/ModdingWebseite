package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.block.LeavesBlock;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Classic leaves: vanilla {@code distance/persistent/waterlogged} properties (palette
 * parity) but never decay — baked canopies stay intact regardless of distance values.
 */
public class ClassicLeavesBlock extends LeavesBlock {

    public ClassicLeavesBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected boolean isRandomlyTicking(BlockState state) {
        return false;
    }

    @Override
    protected void randomTick(BlockState state, ServerLevel level, BlockPos pos, RandomSource random) {
        // no decay
    }
}
