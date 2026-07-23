package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.DoorBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockSetType;

/**
 * Classic door: opens/closes by hand (the one allowed interaction, plan §2.14 — the
 * classic "iron" set type is hand-openable since classic redstone is inert) but ignores
 * redstone entirely; the baked {@code powered} value never changes.
 */
public class ClassicDoorBlock extends DoorBlock {

    public ClassicDoorBlock(BlockSetType type, Properties properties) {
        super(type, properties);
    }

    @Override
    protected void neighborChanged(BlockState state, Level level, BlockPos pos, Block block,
                                   BlockPos fromPos, boolean isMoving) {
        // no redstone response
    }
}
