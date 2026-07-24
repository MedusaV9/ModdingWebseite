package dev.projecteclipse.eclipse.economy;

import dev.projecteclipse.eclipse.ritual.AltarBlockEntity;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;

/**
 * The umbral shard (W10's night-mob drop, W13's shop currency). Sneak-right-clicking the
 * altar with a stack deposits ALL of it into the shard bank ({@link ShardEconomy#deposit}):
 * personal balance + team pool.
 *
 * <p>Same routing trick as {@code ritual.HeraldsLureItem}: vanilla skips block interaction
 * entirely while sneaking with an item in hand, so this {@link #useOn} IS the sneak path.
 * Non-sneak clicks land in {@code AltarBlock#useItemOn} → milestone deposit, which
 * special-cases the shard into a "sneak to bank" hint when no milestone wants it.</p>
 */
public class UmbralShardItem extends Item {
    public UmbralShardItem(Properties properties) {
        super(properties);
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
