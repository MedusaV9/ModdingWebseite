package dev.projecteclipse.eclipse.client;

import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.hud.SidebarPanel;
import dev.projecteclipse.eclipse.cutscene.client.LetterboxLayer;
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
        // W8 sidebar panel: renders from ClientStateCache, suppresses the vanilla sidebar
        // while on (see SidebarPanel). Deliberately NOT whitelisted below — cutscene HUD
        // suppression is supposed to hide it.
        event.registerAbove(VanillaGuiLayers.SCOREBOARD_SIDEBAR,
                SidebarPanel.LAYER_ID, SidebarPanel::render);
        event.registerAboveAll(WaveOverlay.LAYER_ID, WaveOverlay::render);
        event.registerAboveAll(LetterboxLayer.LAYER_ID, LetterboxLayer::render);
        // Cutscene HUD suppression must never cancel these: the letterbox itself, W2's
        // mid-death heart burst, and the v1 wave overlay (renders through the intro flight).
        LetterboxLayer.setHudWhitelist(Set.of(
                LetterboxLayer.LAYER_ID, HeartBurstOverlay.LAYER_ID, WaveOverlay.LAYER_ID));
    }
}
