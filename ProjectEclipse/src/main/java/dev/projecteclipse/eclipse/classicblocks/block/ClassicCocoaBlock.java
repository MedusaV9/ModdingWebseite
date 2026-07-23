package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Cocoa-pod lookalike: vanilla {@code age}/{@code facing} properties and shapes, but no
 * growth ticks and no support requirement — pods survive on classic jungle logs (and
 * anywhere else) instead of popping off like the vanilla block would.
 */
public class ClassicCocoaBlock extends ClassicHorizontalBlock {

    public static final IntegerProperty AGE = BlockStateProperties.AGE_2;

    private static final VoxelShape[] EAST_AABB = {
            box(11, 7, 6, 15, 12, 10), box(9, 5, 5, 15, 12, 11), box(7, 3, 4, 15, 12, 12)};
    private static final VoxelShape[] WEST_AABB = {
            box(1, 7, 6, 5, 12, 10), box(1, 5, 5, 7, 12, 11), box(1, 3, 4, 9, 12, 12)};
    private static final VoxelShape[] NORTH_AABB = {
            box(6, 7, 1, 10, 12, 5), box(5, 5, 1, 11, 12, 7), box(4, 3, 1, 12, 12, 9)};
    private static final VoxelShape[] SOUTH_AABB = {
            box(6, 7, 11, 10, 12, 15), box(5, 5, 9, 11, 12, 15), box(4, 3, 7, 12, 12, 15)};

    public ClassicCocoaBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.NORTH)
                .setValue(AGE, 0));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        super.createBlockStateDefinition(builder);
        builder.add(AGE);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        Direction face = context.getClickedFace();
        // pods hang off the clicked (log) face and point back at it, like vanilla
        Direction facing = face.getAxis().isHorizontal()
                ? face.getOpposite() : context.getHorizontalDirection();
        return this.defaultBlockState().setValue(FACING, facing);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        int age = state.getValue(AGE);
        return switch (state.getValue(FACING)) {
            case SOUTH -> SOUTH_AABB[age];
            case EAST -> EAST_AABB[age];
            case WEST -> WEST_AABB[age];
            default -> NORTH_AABB[age];
        };
    }
}
