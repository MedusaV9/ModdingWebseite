package dev.projecteclipse.eclipse.limbo.door;

import com.mojang.serialization.MapCodec;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Mirror;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.level.block.state.properties.DirectionProperty;
import net.minecraft.world.level.block.state.properties.IntegerProperty;
import net.minecraft.world.phys.BlockHitResult;

/**
 * Invisible, collidable filler for the 14 non-controller cells of the Respawn Door
 * multiblock (plans_v3 §2.5). {@link #COL}/{@link #ROW} + {@link #FACING} encode the
 * cell's place in the 3×5 aperture, so the owning {@link RespawnDoorBlock} controller is
 * a pure coordinate computation ({@link #controllerPos}) — no scanning. Interactions
 * route to the controller; removing a filler removes the controller (which cascades the
 * rest); {@link #LIT} carries the shared purple block light.
 */
public class RespawnDoorFillerBlock extends Block {
    public static final MapCodec<RespawnDoorFillerBlock> CODEC = simpleCodec(RespawnDoorFillerBlock::new);

    /** Same orientation as the controller's front face. */
    public static final DirectionProperty FACING = BlockStateProperties.HORIZONTAL_FACING;
    /** Column 0..2 along {@code facing.getClockWise()} (controller sits at column 1). */
    public static final IntegerProperty COL = IntegerProperty.create("col", 0, RespawnDoorBlock.WIDTH - 1);
    /** Row 0..4 above the controller's row (controller sits at row 0). */
    public static final IntegerProperty ROW = IntegerProperty.create("row", 0, RespawnDoorBlock.HEIGHT - 1);
    /** Purple block-light emission; false only while the door is {@link DoorState#SEALED}. */
    public static final BooleanProperty LIT = BlockStateProperties.LIT;

    public RespawnDoorFillerBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.EAST)
                .setValue(COL, 0)
                .setValue(ROW, 1)
                .setValue(LIT, true));
    }

    /** The controller cell this filler belongs to (inverse of {@code RespawnDoorBlock.cellPos}). */
    public static BlockPos controllerPos(BlockPos fillerPos, BlockState fillerState) {
        Direction facing = fillerState.getValue(FACING);
        return fillerPos
                .relative(facing.getClockWise(), 1 - fillerState.getValue(COL))
                .below(fillerState.getValue(ROW));
    }

    @Override
    protected MapCodec<? extends Block> codec() {
        return CODEC;
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(FACING, COL, ROW, LIT);
    }

    @Override
    protected RenderShape getRenderShape(BlockState state) {
        return RenderShape.INVISIBLE; // the controller's BER draws the whole door
    }

    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos,
            Player player, BlockHitResult hitResult) {
        return RespawnDoorBlock.handleUse(level, controllerPos(pos, state), player);
    }

    /** Any filler gone → drop the controller too; its removal cascades the rest away. */
    @Override
    protected void onRemove(BlockState state, Level level, BlockPos pos, BlockState newState, boolean movedByPiston) {
        if (!state.is(newState.getBlock())) { // LIT swaps keep the door standing
            BlockPos controller = controllerPos(pos, state);
            if (level.getBlockState(controller).getBlock() instanceof RespawnDoorBlock) {
                level.setBlock(controller, net.minecraft.world.level.block.Blocks.AIR.defaultBlockState(),
                        Block.UPDATE_ALL);
            }
        }
        super.onRemove(state, level, pos, newState, movedByPiston);
    }

    @Override
    protected BlockState rotate(BlockState state, Rotation rotation) {
        return state.setValue(FACING, rotation.rotate(state.getValue(FACING)));
    }

    @Override
    protected BlockState mirror(BlockState state, Mirror mirror) {
        return state.rotate(mirror.getRotation(state.getValue(FACING)));
    }
}
