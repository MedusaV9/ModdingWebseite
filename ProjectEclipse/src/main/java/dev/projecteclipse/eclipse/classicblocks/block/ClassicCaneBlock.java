package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Static sugar cane: vanilla {@code age} 0–15 property for palette parity, no growth and
 * no water-adjacency requirement (classic water is a solid block, so vanilla's fluid
 * check would pop baked cane). Stacks survive on their own kind or any sturdy block.
 */
public class ClassicCaneBlock extends ClassicPlantBlock {

    public static final IntegerProperty AGE = BlockStateProperties.AGE_15;

    private static final VoxelShape SHAPE = Block.box(2.0, 0.0, 2.0, 14.0, 16.0, 14.0);

    public ClassicCaneBlock(Properties properties) {
        super(PlantShape.BUSH, true, properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(AGE, 0));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(AGE);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return SHAPE;
    }

    @Override
    protected boolean mayPlaceOn(LevelReader level, BlockPos below) {
        BlockState state = level.getBlockState(below);
        return state.is(this) || state.isFaceSturdy(level, below, Direction.UP);
    }
}
