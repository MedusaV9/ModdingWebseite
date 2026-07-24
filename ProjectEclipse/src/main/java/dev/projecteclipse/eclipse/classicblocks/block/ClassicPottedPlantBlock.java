package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Potted-plant lookalike (pot + plant in one JSON model): no plant swapping on click —
 * breaking it drops the matching classic plant (the pot itself has no classic twin).
 */
public class ClassicPottedPlantBlock extends Block {

    private static final VoxelShape SHAPE = box(5, 0, 5, 11, 6, 11);

    public ClassicPottedPlantBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return SHAPE;
    }
}
