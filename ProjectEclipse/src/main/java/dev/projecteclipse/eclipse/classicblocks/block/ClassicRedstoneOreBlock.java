package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;

/**
 * Redstone ore lookalike: vanilla {@code lit} property for palette parity (glows at the
 * vanilla level 9 when a baked state is lit) but never toggles on touch.
 */
public class ClassicRedstoneOreBlock extends Block {

    public static final BooleanProperty LIT = BlockStateProperties.LIT;

    public ClassicRedstoneOreBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(LIT, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(LIT);
    }
}
