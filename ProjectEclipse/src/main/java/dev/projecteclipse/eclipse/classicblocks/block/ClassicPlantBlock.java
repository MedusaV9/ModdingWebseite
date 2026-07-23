package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.LevelAccessor;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Fixed-pose cross plant (flowers, mushrooms, grass tufts, dead bush, cobweb): never
 * grows, spreads or gets eaten. Unlike vanilla {@code BushBlock} it uses a purely
 * geometric support rule (sturdy top face below) so plants survive on classic AND vanilla
 * ground blocks — vanilla's {@code mayPlaceOn} tag checks would pop baked plants off
 * {@code eclipse:classic_grass_block} on the first neighbor update.
 */
public class ClassicPlantBlock extends Block {

    /** Vanilla twin outline shapes. */
    public enum PlantShape {
        FLOWER(Block.box(5.0, 0.0, 5.0, 11.0, 10.0, 11.0)),
        MUSHROOM(Block.box(5.0, 0.0, 5.0, 11.0, 6.0, 11.0)),
        BUSH(Block.box(2.0, 0.0, 2.0, 14.0, 13.0, 14.0)),
        SAPLING(Block.box(2.0, 0.0, 2.0, 14.0, 12.0, 14.0)),
        FULL(Shapes.block());

        private final VoxelShape shape;

        PlantShape(VoxelShape shape) {
            this.shape = shape;
        }
    }

    private final PlantShape plantShape;
    private final boolean requiresSupport;

    public ClassicPlantBlock(PlantShape plantShape, boolean requiresSupport, Properties properties) {
        super(properties);
        this.plantShape = plantShape;
        this.requiresSupport = requiresSupport;
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        return this.plantShape.shape;
    }

    @Override
    protected boolean canSurvive(BlockState state, LevelReader level, BlockPos pos) {
        return !this.requiresSupport || this.mayPlaceOn(level, pos.below());
    }

    /** Geometric support rule; subclasses widen it (farmland for crops, self for cane). */
    protected boolean mayPlaceOn(LevelReader level, BlockPos below) {
        return level.getBlockState(below).isFaceSturdy(level, below, Direction.UP);
    }

    @Override
    protected BlockState updateShape(BlockState state, Direction direction, BlockState neighborState,
                                     LevelAccessor level, BlockPos pos, BlockPos neighborPos) {
        return !state.canSurvive(level, pos)
                ? Blocks.AIR.defaultBlockState()
                : super.updateShape(state, direction, neighborState, level, pos, neighborPos);
    }
}
