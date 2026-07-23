package dev.projecteclipse.eclipse.classicblocks.block;

import java.util.function.Function;

import net.minecraft.core.Direction;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Mirror;
import net.minecraft.world.level.block.PipeBlock;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;

/**
 * Huge-mushroom cap/stem lookalike: vanilla six per-face cap properties (the baked
 * palettes distinguish trimmed faces), no neighbor-trimming behaviour — placed blocks
 * simply keep whatever faces their state says.
 */
public class ClassicMushroomBlock extends Block {

    public ClassicMushroomBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(BlockStateProperties.NORTH, true)
                .setValue(BlockStateProperties.EAST, true)
                .setValue(BlockStateProperties.SOUTH, true)
                .setValue(BlockStateProperties.WEST, true)
                .setValue(BlockStateProperties.UP, true)
                .setValue(BlockStateProperties.DOWN, true));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(BlockStateProperties.NORTH, BlockStateProperties.EAST,
                BlockStateProperties.SOUTH, BlockStateProperties.WEST,
                BlockStateProperties.UP, BlockStateProperties.DOWN);
    }

    private static BlockState mapDirections(BlockState state, Function<Direction, Direction> mapper) {
        BlockState out = state;
        for (Direction direction : Direction.values()) {
            out = out.setValue(PipeBlock.PROPERTY_BY_DIRECTION.get(mapper.apply(direction)),
                    state.getValue(PipeBlock.PROPERTY_BY_DIRECTION.get(direction)));
        }
        return out;
    }

    @Override
    protected BlockState rotate(BlockState state, Rotation rotation) {
        return mapDirections(state, rotation::rotate);
    }

    @Override
    protected BlockState mirror(BlockState state, Mirror mirror) {
        return mapDirections(state, mirror::mirror);
    }
}
