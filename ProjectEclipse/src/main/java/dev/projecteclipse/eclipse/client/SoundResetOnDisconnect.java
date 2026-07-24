package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Stops every active sound instance when the local player disconnects. Third-party
 * entity-attached tickable sounds (e.g. Supplementaries' rope-slide instance) survive a
 * disconnect inside the sound engine and then NPE on the next join while
 * {@code Minecraft.getConnection()} is still null — hard-crashing the client. Flushing the
 * engine between sessions removes the whole failure class; music restarts naturally.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SoundResetOnDisconnect {
    private SoundResetOnDisconnect() {}

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        Minecraft minecraft = Minecraft.getInstance();
        minecraft.getSoundManager().stop();
    }
}
