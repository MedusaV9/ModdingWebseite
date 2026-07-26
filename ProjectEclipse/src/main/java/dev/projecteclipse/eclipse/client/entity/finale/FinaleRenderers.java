package dev.projecteclipse.eclipse.client.entity.finale;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ferryman.finale.FinaleEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the FERRYMAN2 finale family (portal gate, portal key, soul
 * wisp) — auto-subscribed, no {@code EclipseMod} wiring needed (the
 * {@code AmbientRenderers} house §1.6 pattern). Guarded on
 * {@code DeferredHolder.isBound()} so the client boots green while the
 * {@code FinaleEntities.register(modEventBus)} wiring line has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FinaleRenderers {
    private FinaleRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!FinaleEntities.PORTAL_GATE.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(FinaleEntities.PORTAL_GATE.get(), PortalGateRenderer::new);
        event.registerEntityRenderer(FinaleEntities.PORTAL_KEY.get(), PortalKeyRenderer::new);
        event.registerEntityRenderer(FinaleEntities.SOUL_WISP.get(), SoulWispRenderer::new);
    }
}
