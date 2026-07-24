package dev.projecteclipse.eclipse.client.entity.fogboss;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.fog.FogBossEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the Fog Tyrant family — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern). Guarded on
 * {@code DeferredHolder.isBound()} so the client boots green while the
 * {@code FogBossEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/WB-TYRANT_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FogBossRenderers {
    private FogBossRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!FogBossEntities.FOG_TYRANT.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(FogBossEntities.FOG_TYRANT.get(), FogTyrantRenderer::new);
    }
}
