package dev.projecteclipse.eclipse.ritual;

import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;

/**
 * The revive sigil. Non-sneak right-clicks on the altar are handled by
 * {@link AltarBlock#useItemOn} (cycle the selected banned player); this item's
 * {@link #useOn} only fires while sneaking, because vanilla skips block
 * interaction when the player is sneaking with an item in hand — that click
 * confirms the selection and starts the {@link ReviveRitual}.
 */
public class ReviveSigilItem extends Item {
    public ReviveSigilItem(Properties properties) {
        super(properties);
    }

    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        if (!(level.getBlockEntity(context.getClickedPos()) instanceof AltarBlockEntity altar)) {
            return InteractionResult.PASS;
        }
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(context.getPlayer() instanceof ServerPlayer serverPlayer)) {
            return InteractionResult.PASS;
        }
        if (context.isSecondaryUseActive()) {
            altar.handleSigilConfirm(serverPlayer);
        } else {
            // Unreachable through vanilla flow (AltarBlock consumes non-sneak clicks); kept for safety.
            altar.handleSigilCycle(serverPlayer);
        }
        return InteractionResult.CONSUME;
    }
}
