package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterGuiLayersEvent;

/** Registers Eclipse GUI layers (mod bus, client only): the cutscene {@link WaveOverlay} above the HUD. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseGuiLayers {
    private EclipseGuiLayers() {}

    @SubscribeEvent
    static void onRegisterGuiLayers(RegisterGuiLayersEvent event) {
        event.registerAboveAll(WaveOverlay.LAYER_ID, WaveOverlay::render);
    }
}
