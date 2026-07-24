package dev.projecteclipse.eclipse.anonymity;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.ServerChatEvent;

/**
 * Prevents player-authored text chat from being broadcast by the server.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChatBlocker {
    private ChatBlocker() {}

    @SubscribeEvent
    public static void onServerChat(ServerChatEvent event) {
        event.setCanceled(true);
    }
}
