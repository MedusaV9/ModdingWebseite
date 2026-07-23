package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Fire lookalike: vanilla {@code age} + side properties for palette parity, but a fully
 * inert museum flame — it never spreads, never burns out, never damages anything and
 * needs no support (the netherrack pits in the tutorial worlds keep their eternal fire).
 */
public class ClassicFireBlock extends Block {

    public static final IntegerProperty AGE = BlockStateProperties.AGE_15;
    public static final BooleanProperty NORTH = BlockStateProperties.NORTH;
    public static final BooleanProperty EAST = BlockStateProperties.EAST;
    public static final BooleanProperty SOUTH = BlockStateProperties.SOUTH;
    public static final BooleanProperty WEST = BlockStateProperties.WEST;
    public static final BooleanProperty UP = BlockStateProperties.UP;

    private static final VoxelShape DOWN_AABB = box(0, 0, 0, 16, 1, 16);
    private static final VoxelShape NORTH_AABB = box(0, 0, 0, 16, 16, 1);
    private static final VoxelShape SOUTH_AABB = box(0, 0, 15, 16, 16, 16);
    private static final VoxelShape WEST_AABB = box(0, 0, 0, 1, 16, 16);
    private static final VoxelShape EAST_AABB = box(15, 0, 0, 16, 16, 16);
    private static final VoxelShape UP_AABB = box(0, 15, 0, 16, 16, 16);

    public ClassicFireBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(AGE, 0)
                .setValue(NORTH, false).setValue(EAST, false)
                .setValue(SOUTH, false).setValue(WEST, false)
                .setValue(UP, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(AGE, NORTH, EAST, SOUTH, WEST, UP);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        VoxelShape shape = Shapes.empty();
        if (state.getValue(NORTH)) {
            shape = Shapes.or(shape, NORTH_AABB);
        }
        if (state.getValue(EAST)) {
            shape = Shapes.or(shape, EAST_AABB);
        }
        if (state.getValue(SOUTH)) {
            shape = Shapes.or(shape, SOUTH_AABB);
        }
        if (state.getValue(WEST)) {
            shape = Shapes.or(shape, WEST_AABB);
        }
        if (state.getValue(UP)) {
            shape = Shapes.or(shape, UP_AABB);
        }
        return shape.isEmpty() ? DOWN_AABB : shape;
    }
}
