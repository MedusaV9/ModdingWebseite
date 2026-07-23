package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.TrapDoorBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockSetType;

/**
 * Classic trapdoor: opens/closes by hand (allowed interaction, plan §2.14) but ignores
 * redstone entirely; the baked {@code powered} value never changes.
 */
public class ClassicTrapdoorBlock extends TrapDoorBlock {

    public ClassicTrapdoorBlock(BlockSetType type, Properties properties) {
        super(type, properties);
    }

    @Override
    protected void neighborChanged(BlockState state, Level level, BlockPos pos, Block block,
                                   BlockPos fromPos, boolean isMoving) {
        // no redstone response
    }
}
