package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * End-portal-frame lookalike: vanilla {@code eye}/{@code facing} properties and shapes,
 * but no eye insertion and no portal formation — the stronghold room stays a museum.
 */
public class ClassicEndPortalFrameBlock extends ClassicHorizontalBlock {

    public static final BooleanProperty EYE = BlockStateProperties.EYE;
    private static final VoxelShape BASE = box(0, 0, 0, 16, 13, 16);
    private static final VoxelShape WITH_EYE = Shapes.or(BASE, box(4, 13, 4, 12, 16, 12));

    public ClassicEndPortalFrameBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.NORTH)
                .setValue(EYE, false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        super.createBlockStateDefinition(builder);
        builder.add(EYE);
    }

    @Override
    protected boolean useShapeForLightOcclusion(BlockState state) {
        return true;
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return state.getValue(EYE) ? WITH_EYE : BASE;
    }
}
