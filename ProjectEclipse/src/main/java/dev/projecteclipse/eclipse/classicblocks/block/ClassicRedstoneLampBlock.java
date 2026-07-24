package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;

/**
 * Redstone-lamp lookalike: vanilla {@code lit} property (baked lamps stay exactly as lit
 * as the bake recorded them — light level 15 when lit), but no redstone response ever.
 */
public class ClassicRedstoneLampBlock extends Block {

    public static final BooleanProperty LIT = BlockStateProperties.LIT;

    public ClassicRedstoneLampBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(LIT, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(LIT);
    }
}
