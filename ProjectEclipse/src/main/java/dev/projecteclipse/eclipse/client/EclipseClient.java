package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;

/**
 * Client-side entry point shell for Project: Eclipse.
 * Static methods annotated with {@link SubscribeEvent} are auto-registered on the client only.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseClient {
    private EclipseClient() {}

    @SubscribeEvent
    static void onClientSetup(FMLClientSetupEvent event) {
        EclipseMod.LOGGER.info("Project: Eclipse client setup");
    }
}
