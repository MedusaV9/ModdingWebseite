package dev.projecteclipse.eclipse.ritual;

import com.mojang.serialization.MapCodec;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.network.altar.AltarPayloads;
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
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;

/**
 * The ritual altar. Admin-placed only (no recipe, no loot table).
 *
 * <p><b>ALTARFIX2 #3 — the interaction contract is now exactly two lanes:</b></p>
 * <ul>
 *   <li><b>Right-click (no sneak), hand empty or not</b> — opens the altar panel screen
 *       and NOTHING else: one {@code S2CAltarPanelPayload} with {@code openScreen=true}
 *       carrying the CURRENT milestone's live requirements, the shop and the boss
 *       instructions ({@code network.altar.AltarPayloads}). It never consumes an item and
 *       never hands one out. The single exception is the revive sigil, which keeps its
 *       target-cycling click — that is a selection, not a withdrawal, and the revive
 *       ritual has no other way to pick a target.</li>
 *   <li><b>Sneak-right-click WITH an item</b> — pays it in: an outstanding cost of the
 *       hungering milestone goes to {@link AltarBlockEntity#handleMilestoneDeposit},
 *       umbral shards go to the team pool ({@code ShardEconomy.deposit}), anything else
 *       becomes the daily offering ({@link AltarBlockEntity#handleOffering}).</li>
 * </ul>
 *
 * <p>Sneak-right-click with an EMPTY hand has nothing to pay in and only prints a hint.
 * The old heart-sacrifice lane (two sneak-clicks → −1 life, +1 heart fragment on the
 * ground) is gone: the altar must never hand an item out. Heart fragments come from the
 * craftable {@link HeartExtractorItem} (2 hearts → 4 fragments) instead.</p>
 *
 * <p>Every deliberate interaction fires {@code EclipseSignals.fireAltarTouched} — the
 * source of the day-1 {@code touch_altar} goal (ALTARFIX2 #1).</p>
 *
 * <p>All feedback is action bar + sounds; nothing is ever printed to chat.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
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

    /**
     * The DEPOSIT lane. Vanilla invokes {@code Item#useOn} instead of {@link #useItemOn}
     * while secondary-use is active, so ordinary items need this event lane. LOWEST lets
     * the day-14 dragon-egg finale consume/cancel first; the lure and revive sigil keep
     * their own item handlers. Shards are handled here so their bank signal fires exactly
     * once without editing the economy-owned item class.
     *
     * <p>ALTARFIX2 #3: the milestone deposit moved here from the plain right-click, so
     * "sneak-right-click = pay in" holds for every payment kind. A held item that the
     * hungering milestone still wants goes to the ladder; everything else keeps the old
     * bank/offering routing.</p>
     */
    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onSneakRightClick(PlayerInteractEvent.RightClickBlock event) {
        if (!(event.getEntity() instanceof ServerPlayer player)
                || !player.isShiftKeyDown()
                || event.getItemStack().isEmpty()
                || !(event.getLevel().getBlockEntity(event.getPos()) instanceof AltarBlockEntity altar)) {
            return;
        }
        ItemStack stack = event.getItemStack();
        if (stack.is(EclipseItems.REVIVE_SIGIL.get()) || stack.is(EclipseItems.HERALDS_LURE.get())) {
            return;
        }
        event.setCanceled(true);
        event.setCancellationResult(InteractionResult.CONSUME);
        touched(player, event.getPos());
        if (altar.wantsForMilestone(player.server, stack)) {
            altar.handleMilestoneDeposit(player, stack);
            return;
        }
        if (stack.is(EclipseItems.UMBRAL_SHARD.get())) {
            int amount = stack.getCount();
            ShardEconomy.deposit(player, stack);
            if (amount > 0) {
                EclipseSignals.fireAltarDeposit(player,
                        net.minecraft.core.registries.BuiltInRegistries.ITEM.getKey(EclipseItems.UMBRAL_SHARD.get()),
                        amount, EclipseSignals.AltarDepositPurpose.SHARD_BANK);
            }
            return;
        }
        altar.handleOffering(player, stack);
    }

    /**
     * Plain right-click WITH an item. ALTARFIX2 #3: this no longer deposits anything — it
     * opens the panel exactly like the empty-hand click, so a stray click can never eat a
     * stack. The revive sigil is the one exception (target cycling; the sneak-confirm in
     * {@link ReviveSigilItem#useOn} needs a selection to confirm).
     */
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
        touched(serverPlayer, pos);
        if (stack.is(EclipseItems.REVIVE_SIGIL.get())) {
            // Only reached without sneaking; sneak + item skips block interaction (ReviveSigilItem#useOn confirms).
            altar.handleSigilCycle(serverPlayer);
        } else {
            AltarPayloads.sendPanel(serverPlayer, pos, true);
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
        touched(serverPlayer, pos);
        if (serverPlayer.isShiftKeyDown()) {
            // ALTARFIX2 #3: the heart sacrifice used to live here and dropped a heart
            // fragment on the stone. The altar hands nothing out any more — sneaking with
            // an empty hand simply has nothing to pay in.
            altar.handleEmptyHandDeposit(serverPlayer);
        } else {
            // ALTARUI task 1: the panel screen replaced the old action-bar status hint.
            AltarPayloads.sendPanel(serverPlayer, pos, true);
        }
        return InteractionResult.CONSUME;
    }

    /** ALTARFIX2 #1: one choke point for the {@code touch_altar} quest signal. */
    private static void touched(ServerPlayer player, BlockPos pos) {
        EclipseSignals.fireAltarTouched(player, pos);
    }
}
