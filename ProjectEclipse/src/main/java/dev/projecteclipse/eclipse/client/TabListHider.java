package dev.projecteclipse.eclipse.client;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.gui.screens.social.SocialInteractionsScreen;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiLayerEvent;
import net.neoforged.neoforge.client.event.ScreenEvent;
import net.neoforged.neoforge.client.gui.VanillaGuiLayers;

/**
 * Hides the vanilla player-roster UIs without removing player-info packets:
 * the tab-list overlay, and the social interactions screen (bound to P by
 * default) which would list every online player's name and face.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class TabListHider {
    private TabListHider() {}

    @SubscribeEvent
    public static void onRenderGuiLayer(RenderGuiLayerEvent.Pre event) {
        if (VanillaGuiLayers.TAB_LIST.equals(event.getName())) {
            event.setCanceled(true);
        }
    }

    @SubscribeEvent
    public static void onScreenOpening(ScreenEvent.Opening event) {
        if (event.getNewScreen() instanceof SocialInteractionsScreen) {
            event.setCanceled(true);
        }
    }
}
