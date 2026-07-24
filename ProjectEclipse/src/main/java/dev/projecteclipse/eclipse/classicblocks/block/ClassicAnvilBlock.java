package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Anvil lookalike: vanilla shape and {@code facing} property, but a normal static block —
 * it never falls, damages nothing and opens no repair GUI.
 */
public class ClassicAnvilBlock extends ClassicHorizontalBlock {

    private static final VoxelShape BASE = box(2, 0, 2, 14, 4, 14);
    private static final VoxelShape X_AABB = Shapes.or(BASE,
            box(3, 4, 4, 13, 5, 12), box(4, 5, 6, 12, 10, 10), box(0, 10, 3, 16, 16, 13));
    private static final VoxelShape Z_AABB = Shapes.or(BASE,
            box(4, 4, 3, 12, 5, 13), box(6, 5, 4, 10, 10, 12), box(3, 10, 0, 13, 16, 16));

    public ClassicAnvilBlock(Properties properties) {
        super(properties);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        // vanilla anvils face sideways-on to the placer
        return this.defaultBlockState().setValue(FACING, context.getHorizontalDirection().getClockWise());
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return state.getValue(FACING).getAxis() == Direction.Axis.X ? X_AABB : Z_AABB;
    }
}
