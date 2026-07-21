package dev.projecteclipse.eclipse.ritual;

import com.mojang.serialization.MapCodec;

import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.ItemInteractionResult;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.BlockHitResult;

/**
 * The ritual altar. Admin-placed only (no recipe, no loot table). Interactions:
 * <ul>
 *   <li><b>Right-click with a cost item</b> — deposits it toward the next altar
 *       milestone (see {@link AltarBlockEntity#handleMilestoneDeposit}).</li>
 *   <li><b>Right-click with a revive sigil</b> — cycles the selected banned player
 *       (sneak-confirm is handled by {@link ReviveSigilItem#useOn}, because vanilla
 *       skips block interaction entirely while sneaking with an item in hand).</li>
 *   <li><b>Sneak-right-click with an empty hand</b> — heart sacrifice (two clicks
 *       within 5 s; see {@link AltarBlockEntity#handleHeartSacrifice}).</li>
 *   <li><b>Right-click with an empty hand</b> — action-bar status of the current milestone.</li>
 * </ul>
 * All feedback is action bar + sounds; nothing is ever printed to chat.
 */
public class AltarBlock extends BaseEntityBlock {
    public static final MapCodec<AltarBlock> CODEC = simpleCodec(AltarBlock::new);

    public AltarBlock(Properties properties) {
        super(properties);
    }

    @Override
    protected MapCodec<AltarBlock> codec() {
        return CODEC;
    }

    @Override
    protected RenderShape getRenderShape(BlockState state) {
        return RenderShape.MODEL;
    }

    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new AltarBlockEntity(pos, state);
    }

    @Override
    protected ItemInteractionResult useItemOn(ItemStack stack, BlockState state, Level level, BlockPos pos,
            Player player, InteractionHand hand, BlockHitResult hitResult) {
        if (stack.isEmpty()) {
            return ItemInteractionResult.PASS_TO_DEFAULT_BLOCK_INTERACTION;
        }
        if (level.isClientSide) {
            return ItemInteractionResult.SUCCESS;
        }
        if (!(player instanceof ServerPlayer serverPlayer)
                || !(level.getBlockEntity(pos) instanceof AltarBlockEntity altar)) {
            return ItemInteractionResult.PASS_TO_DEFAULT_BLOCK_INTERACTION;
        }
        if (stack.is(EclipseItems.REVIVE_SIGIL.get())) {
            // Only reached without sneaking; sneak + item skips block interaction (ReviveSigilItem#useOn confirms).
            altar.handleSigilCycle(serverPlayer);
        } else {
            altar.handleMilestoneDeposit(serverPlayer, stack);
        }
        return ItemInteractionResult.CONSUME;
    }

    @Override
    protected InteractionResult useWithoutItem(BlockState state, Level level, BlockPos pos, Player player,
            BlockHitResult hitResult) {
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(player instanceof ServerPlayer serverPlayer)
                || !(level.getBlockEntity(pos) instanceof AltarBlockEntity altar)) {
            return InteractionResult.PASS;
        }
        if (serverPlayer.isShiftKeyDown()) {
            altar.handleHeartSacrifice(serverPlayer);
        } else {
            altar.handleStatusHint(serverPlayer);
        }
        return InteractionResult.CONSUME;
    }
}
