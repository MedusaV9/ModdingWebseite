package dev.projecteclipse.eclipse.anonymity;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.item.Items;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.AnvilUpdateEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import net.neoforged.neoforge.event.level.BlockEvent;

/**
 * Blocks vanilla text-entry surfaces that could reveal player-authored text.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class TextInputBlocker {
    private TextInputBlocker() {}

    @SubscribeEvent
    public static void onAnvilUpdate(AnvilUpdateEvent event) {
        if (!(event.getPlayer() instanceof ServerPlayer)) {
            return;
        }

        String requestedName = event.getName();
        if (requestedName != null
                && !requestedName.isEmpty()
                && !requestedName.equals(event.getLeft().getHoverName().getString())) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onSignPlaced(BlockEvent.EntityPlaceEvent event) {
        if (event.getEntity() instanceof ServerPlayer && event.getPlacedBlock().is(BlockTags.ALL_SIGNS)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onSignUsed(PlayerInteractEvent.RightClickBlock event) {
        if (event.getEntity() instanceof ServerPlayer player
                && player.level().getBlockState(event.getPos()).is(BlockTags.ALL_SIGNS)) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onBookUsed(PlayerInteractEvent.RightClickItem event) {
        if (event.getEntity() instanceof ServerPlayer
                && (event.getItemStack().is(Items.WRITABLE_BOOK)
                        || event.getItemStack().is(Items.WRITTEN_BOOK))) {
            event.setCanceled(true);
        }
    }
}
