package dev.projecteclipse.eclipse.economy;

import java.util.List;

import dev.projecteclipse.eclipse.ritual.AltarBlockEntity;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;

/**
 * The umbral shard (W10's night-mob drop, W13's shop currency). Sneak-right-clicking the
 * altar with a stack deposits ALL of it into the shard bank ({@link ShardEconomy#deposit}):
 * team pool only (FINAL-DOPA-SOL §3 — banking no longer also credits the personal balance).
 *
 * <p>Same routing trick as {@code ritual.HeraldsLureItem}: vanilla skips block interaction
 * entirely while sneaking with an item in hand, so this {@link #useOn} IS the sneak path.
 * Non-sneak clicks land in {@code AltarBlock#useItemOn} → milestone deposit, which
 * special-cases the shard into a "sneak to bank" hint when no milestone wants it.</p>
 */
public class UmbralShardItem extends Item {
    /** Tooltip tint — the Quiet-Eclipse accent purple ({@code EclipseUiTheme.ACCENT}). */
    private static final int TOOLTIP_ACCENT = 0xB98CFF;

    public UmbralShardItem(Properties properties) {
        super(properties);
    }

    /** ALTARUI task 5: the shard advertises its altar-trade purpose right on the item. */
    @Override
    public void appendHoverText(ItemStack stack, Item.TooltipContext context,
            List<Component> tooltipComponents, TooltipFlag tooltipFlag) {
        tooltipComponents.add(Component.translatable("item.eclipse.umbral_shard.tooltip")
                .withColor(TOOLTIP_ACCENT));
    }

    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        if (!(level.getBlockEntity(context.getClickedPos()) instanceof AltarBlockEntity)) {
            return InteractionResult.PASS;
        }
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(context.getPlayer() instanceof ServerPlayer player) || !context.isSecondaryUseActive()) {
            return InteractionResult.PASS;
        }
        ShardEconomy.deposit(player, context.getItemInHand());
        return InteractionResult.CONSUME;
    }
}
