package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.hearts.client.HeartBurstOverlay;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/** Registers Eclipse GUI layers on the client mod bus. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseGuiLayers {
    private EclipseGuiLayers() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAbove(VanillaGuiLayers.PLAYER_HEALTH,
                HeartBurstOverlay.LAYER_ID, HeartBurstOverlay::render);
        event.registerAboveAll(WaveOverlay.LAYER_ID, WaveOverlay::render);
    }
}
