package dev.projecteclipse.eclipse.limbo.door;

import com.mojang.serialization.MapCodec;

import dev.projecteclipse.eclipse.lives.BanService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Mirror;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.BooleanProperty;
import net.minecraft.world.level.block.state.properties.DirectionProperty;
import net.minecraft.world.phys.BlockHitResult;

/**
 * Controller block of the Respawn Door multiblock (plans_v3 §2.5): the BOTTOM-CENTER
 * cell of the 3-wide × 5-tall aperture. Renders nothing itself ({@code BaseEntityBlock}
 * = {@code RenderShape.INVISIBLE}) — the GeckoLib model on
 * {@link RespawnDoorBlockEntity} draws the whole door from this cell; the other 14 cells
 * are {@link RespawnDoorFillerBlock}s that only provide collision (solid to everyone,
 * always — the "ghosts can't pass" rule is physical, plan §2.5 documented limitation:
 * P4 teleports revived players through via {@link RespawnDoorApi}).
 *
 * <p>{@link #FACING} points OUT of the door's front face (EAST on the ship — toward the
 * bow); {@link #LIT} mirrors the global {@link DoorState} (dark only while SEALED) so
 * the purple spill is real block light. Unbreakable in survival, piston-proof; removing
 * any cell in creative cascades the whole multiblock away (the next boot's
 * {@code RespawnDoorApi.ensureDoor} repairs it).</p>
 */
public class RespawnDoorBlock extends BaseEntityBlock {
    public static final MapCodec<RespawnDoorBlock> CODEC = simpleCodec(RespawnDoorBlock::new);

    /** Direction of the door's FRONT face (the side the light spills toward). */
    public static final DirectionProperty FACING = BlockStateProperties.HORIZONTAL_FACING;
    /** Purple block-light emission; false only while the door is {@link DoorState#SEALED}. */
    public static final BooleanProperty LIT = BlockStateProperties.LIT;

    /** Aperture cells across (columns 0..2 along {@code facing.getClockWise()}). */
    public static final int WIDTH = 3;
    /** Aperture cells up (rows 0..4 from the controller's row). */
    public static final int HEIGHT = 5;

    public RespawnDoorBlock(Properties properties) {
        super(properties);
        registerDefaultState(this.stateDefinition.any()
                .setValue(FACING, Direction.EAST)
                .setValue(LIT, true));
    }

    /**
     * World position of multiblock cell ({@code col}, {@code row}) for a controller at
     * {@code controllerPos}: columns run along {@code facing.getClockWise()} with the
     * controller in column 1, rows straight up from the controller's row 0.
     */
    public static BlockPos cellPos(BlockPos controllerPos, Direction facing, int col, int row) {
        return controllerPos.relative(facing.getClockWise(), col - 1).above(row);
    }

    /**
     * Places/repairs the 14 filler cells around an already-placed controller (used by
     * creative item placement and {@code RespawnDoorApi.ensureDoor}); returns how many
     * cells actually changed.
     */
    public static int placeFillers(Level level, BlockPos controllerPos, Direction facing, boolean lit) {
        if (!DoorRegistry.isBound()) {
            return 0;
        }
        int changed = 0;
        for (int col = 0; col < WIDTH; col++) {
            for (int row = 0; row < HEIGHT; row++) {
                if (col == 1 && row == 0) {
                    continue; // the controller cell itself
                }
                BlockState wanted = DoorRegistry.RESPAWN_DOOR_FILLER.get().defaultBlockState()
                        .setValue(RespawnDoorFillerBlock.FACING, facing)
                        .setValue(RespawnDoorFillerBlock.COL, col)
                        .setValue(RespawnDoorFillerBlock.ROW, row)
                        .setValue(RespawnDoorFillerBlock.LIT, lit);
                BlockPos cell = cellPos(controllerPos, facing, col, row);
                if (!level.getBlockState(cell).equals(wanted)) {
                    level.setBlock(cell, wanted, Block.UPDATE_ALL);
                    changed++;
                }
            }
        }
        return changed;
    }

    /**
     * Shared right-click handling for every multiblock cell: the door is a stage prop —
     * it never opens by hand. Ghosts get the locked shudder + a whisper (the P3/P4 flow
     * is the only way through); the living get a hint. Feedback throttles itself by
     * being action-bar only.
     */
    static InteractionResult handleUse(Level level, BlockPos controllerPos, Player player) {
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (player instanceof ServerPlayer serverPlayer) {
            if (BanService.isBanned(serverPlayer)) {
                if (level.getBlockEntity(controllerPos) instanceof RespawnDoorBlockEntity door) {
                    door.triggerAnim(RespawnDoorBlockEntity.CONTROLLER_STATE,
                            RespawnDoorBlockEntity.ANIM_LOCKED_SHUDDER);
                }
                level.playSound(null, controllerPos, SoundEvents.IRON_DOOR_CLOSE, SoundSource.BLOCKS, 0.7F, 0.45F);
                serverPlayer.displayClientMessage(Component.translatable("message.eclipse.door.locked"), true);
            } else {
                serverPlayer.displayClientMessage(Component.translatable("message.eclipse.door.closed"), true);
            }
        }
        return InteractionResult.CONSUME;
    }

    @Override
    protected MapCodec<? extends BaseEntityBlock> codec() {
        return CODEC;
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(FACING, LIT);
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new RespawnDoorBlockEntity(pos, state);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        return defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite());
    }

    /** Creative/admin item placement builds the full multiblock around the controller. */
    @Override
    public void setPlacedBy(Level level, BlockPos pos, BlockState state, LivingEntity placer, ItemStack stack) {
        super.setPlacedBy(level, pos, state, placer, stack);
        if (!level.isClientSide) {
            placeFillers(level, pos, state.getValue(FACING), state.getValue(LIT));
        }
    }

    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos,
            Player player, BlockHitResult hitResult) {
        return handleUse(level, pos, player);
    }

    /** Controller gone (creative break / admin edit) → the whole multiblock goes. */
    @Override
    protected void onRemove(BlockState state, Level level, BlockPos pos, BlockState newState, boolean movedByPiston) {
        if (!state.is(newState.getBlock())) { // LIT/FACING swaps keep the door standing
            Direction facing = state.getValue(FACING);
            for (int col = 0; col < WIDTH; col++) {
                for (int row = 0; row < HEIGHT; row++) {
                    if (col == 1 && row == 0) {
                        continue;
                    }
                    BlockPos cell = cellPos(pos, facing, col, row);
                    if (level.getBlockState(cell).getBlock() instanceof RespawnDoorFillerBlock) {
                        level.setBlock(cell, net.minecraft.world.level.block.Blocks.AIR.defaultBlockState(),
                                Block.UPDATE_ALL);
                    }
                }
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
