package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.FarmBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Static pumpkin/melon stem: vanilla {@code age} 0–7 property for palette parity, fixed
 * visual, no growth and no fruit search. Technical block — no item.
 */
public class ClassicStemBlock extends ClassicPlantBlock {

    public static final IntegerProperty AGE = BlockStateProperties.AGE_7;

    private static final VoxelShape[] SHAPE_BY_AGE = new VoxelShape[]{
            Block.box(7.0, 0.0, 7.0, 9.0, 2.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 4.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 6.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 8.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 10.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 12.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 14.0, 9.0),
            Block.box(7.0, 0.0, 7.0, 9.0, 16.0, 9.0)
    };

    public ClassicStemBlock(Properties properties) {
        super(PlantShape.BUSH, true, properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(AGE, 0));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(AGE);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return SHAPE_BY_AGE[state.getValue(AGE)];
    }

    @Override
    protected boolean mayPlaceOn(LevelReader level, BlockPos below) {
        BlockState state = level.getBlockState(below);
        return state.getBlock() instanceof ClassicFarmlandBlock
                || state.getBlock() instanceof FarmBlock
                || state.isFaceSturdy(level, below, Direction.UP);
    }
}
