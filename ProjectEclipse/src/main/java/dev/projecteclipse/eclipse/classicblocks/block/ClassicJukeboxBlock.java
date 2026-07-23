package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;

/**
 * Jukebox lookalike: vanilla {@code has_record} property for palette parity, but no block
 * entity — discs cannot be inserted (mined vanilla discs from event chests stay playable
 * in real jukeboxes).
 */
public class ClassicJukeboxBlock extends Block {

    public static final BooleanProperty HAS_RECORD = BlockStateProperties.HAS_RECORD;

    public ClassicJukeboxBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(HAS_RECORD, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(HAS_RECORD);
    }
}
