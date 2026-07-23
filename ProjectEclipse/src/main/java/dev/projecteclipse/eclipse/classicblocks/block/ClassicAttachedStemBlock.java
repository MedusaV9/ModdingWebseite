package dev.projecteclipse.eclipse.classicblocks.block;

import java.util.Map;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.FarmBlock;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.Mirror;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.DirectionProperty;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Static attached pumpkin/melon stem: keeps the vanilla horizontal {@code facing} for
 * palette parity, never reverts to a growing stem. Technical block — no item.
 */
public class ClassicAttachedStemBlock extends ClassicPlantBlock {

    public static final DirectionProperty FACING = HorizontalDirectionalBlock.FACING;

    private static final Map<Direction, VoxelShape> AABBS = Map.of(
            Direction.SOUTH, Block.box(6.0, 0.0, 6.0, 10.0, 10.0, 16.0),
            Direction.WEST, Block.box(0.0, 0.0, 6.0, 10.0, 10.0, 10.0),
            Direction.NORTH, Block.box(6.0, 0.0, 0.0, 10.0, 10.0, 10.0),
            Direction.EAST, Block.box(6.0, 0.0, 6.0, 16.0, 10.0, 10.0));

    public ClassicAttachedStemBlock(Properties properties) {
        super(PlantShape.BUSH, true, properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(FACING, Direction.NORTH));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(FACING);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return AABBS.get(state.getValue(FACING));
    }

    @Override
    protected boolean mayPlaceOn(LevelReader level, BlockPos below) {
        BlockState state = level.getBlockState(below);
        return state.getBlock() instanceof ClassicFarmlandBlock
                || state.getBlock() instanceof FarmBlock
                || state.isFaceSturdy(level, below, Direction.UP);
    }

    @Override
    protected BlockState rotate(BlockState state, Rotation rotation) {
        return state.setValue(FACING, rotation.rotate(state.getValue(FACING)));
    }

    @Override
    protected BlockState mirror(BlockState state, Mirror mirror) {
        return state.setValue(FACING, mirror.mirror(state.getValue(FACING)));
    }
}
