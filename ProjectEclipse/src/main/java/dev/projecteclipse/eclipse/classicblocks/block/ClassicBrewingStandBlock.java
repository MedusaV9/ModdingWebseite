package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
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
 * Brewing stand lookalike: vanilla {@code has_bottle_0..2} properties and shape, but no
 * block entity, no brewing GUI, no bubbling particles.
 */
public class ClassicBrewingStandBlock extends Block {

    public static final BooleanProperty[] HAS_BOTTLE = {
            BlockStateProperties.HAS_BOTTLE_0, BlockStateProperties.HAS_BOTTLE_1,
            BlockStateProperties.HAS_BOTTLE_2};
    private static final VoxelShape SHAPE = Shapes.or(
            box(1, 0, 1, 15, 2, 15), box(7, 0, 7, 9, 14, 9));

    public ClassicBrewingStandBlock(Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any()
                .setValue(HAS_BOTTLE[0], false)
                .setValue(HAS_BOTTLE[1], false)
                .setValue(HAS_BOTTLE[2], false));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(HAS_BOTTLE[0], HAS_BOTTLE[1], HAS_BOTTLE[2]);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return SHAPE;
    }
}
