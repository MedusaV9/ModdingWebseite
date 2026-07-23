package dev.projecteclipse.eclipse.classicblocks.block;

import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.IntegerProperty;

/**
 * Decorative sapling: never grows into a tree. Keeps the vanilla {@code stage} property
 * purely for blockstate parity with the baked region palettes.
 */
public class ClassicSaplingBlock extends ClassicPlantBlock {

    public static final IntegerProperty STAGE = BlockStateProperties.STAGE;

    public ClassicSaplingBlock(Properties properties) {
        super(PlantShape.SAPLING, true, properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(STAGE, 0));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(STAGE);
    }
}
