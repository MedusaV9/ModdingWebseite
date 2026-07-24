package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Enchanting-table lookalike: vanilla shape and glow, but no block entity, no floating
 * book, no enchanting GUI — obsidian-and-diamond shelf decoration.
 */
public class ClassicEnchantingTableBlock extends Block {

    private static final VoxelShape SHAPE = box(0, 0, 0, 16, 12, 16);

    public ClassicEnchantingTableBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected boolean useShapeForLightOcclusion(BlockState state) {
        return true;
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return SHAPE;
    }
}
