package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.Direction;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;

/**
 * Furnace lookalike: vanilla {@code facing/lit} properties for palette parity, but no
 * block entity, no smelting GUI and no fuel intake — a stone box with a face.
 */
public class ClassicFurnaceBlock extends ClassicHorizontalBlock {

    public static final BooleanProperty LIT = BlockStateProperties.LIT;

    public ClassicFurnaceBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.NORTH)
                .setValue(LIT, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        super.createBlockStateDefinition(builder);
        builder.add(LIT);
    }
}
