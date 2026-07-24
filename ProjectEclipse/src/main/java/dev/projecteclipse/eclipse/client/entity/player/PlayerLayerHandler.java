package dev.projecteclipse.eclipse.client.entity.player;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.renderer.entity.player.PlayerRenderer;
import net.minecraft.client.resources.PlayerSkin;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Attaches {@link EclipsedPlayerGlowLayer} to both vanilla player renderers via the
 * supported {@code EntityRenderersEvent.AddLayers} hook (plan §2.7). Both skin-model keys
 * are covered even though {@code AbstractClientPlayerMixin} forces WIDE — belt and braces
 * in case the forced model ever changes. Guarded with {@code instanceof PlayerRenderer}
 * per the plan's risk table so a foreign replacement renderer can't crash the hook.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PlayerLayerHandler {
    private PlayerLayerHandler() {}

    @SubscribeEvent
    static void onAddLayers(EntityRenderersEvent.AddLayers event) {
        int attached = 0;
        for (PlayerSkin.Model skinModel : event.getSkins()) {
            if (event.getSkin(skinModel) instanceof PlayerRenderer playerRenderer) {
                playerRenderer.addLayer(new EclipsedPlayerGlowLayer(playerRenderer));
                attached++;
            }
        }
        EclipseMod.LOGGER.info("[skin v2] eclipsed player glow layer attached to {} player renderer(s)", attached);
    }
}
