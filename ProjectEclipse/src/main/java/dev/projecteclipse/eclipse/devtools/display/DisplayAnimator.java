package dev.projecteclipse.eclipse.devtools.display;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/** Two-tick server animation driver; interpolation duration matches the update interval. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DisplayAnimator {
    public static final int TICK_INTERVAL = 2;

    private DisplayAnimator() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (event.getServer().getTickCount() % TICK_INTERVAL == 0) {
            DisplayPlacerService.get(event.getServer()).tick(event.getServer());
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        DisplayPlacerService.clearTransientSelections();
    }
}
