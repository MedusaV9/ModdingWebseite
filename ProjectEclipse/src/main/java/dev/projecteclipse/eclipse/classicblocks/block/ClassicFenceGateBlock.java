package dev.projecteclipse.eclipse.classicblocks.block;

import javax.annotation.Nullable;

import net.minecraft.core.BlockPos;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.FenceGateBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.WoodType;

/**
 * Classic fence gate: opens/closes by hand like doors (plan §2.14 allows it) but ignores
 * redstone entirely; the baked {@code powered} value never changes.
 */
public class ClassicFenceGateBlock extends FenceGateBlock {

    public ClassicFenceGateBlock(Properties properties) {
        super(WoodType.OAK, properties);
    }

    @Override
    @Nullable
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        BlockState state = super.getStateForPlacement(context);
        // never inherit a neighbor signal on placement
        return state == null ? null : state.setValue(POWERED, false).setValue(OPEN, false);
    }

    @Override
    protected void neighborChanged(BlockState state, Level level, BlockPos pos, Block block,
                                   BlockPos fromPos, boolean isMoving) {
        // no redstone response
    }
}
