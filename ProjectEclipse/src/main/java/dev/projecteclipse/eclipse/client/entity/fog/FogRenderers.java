package dev.projecteclipse.eclipse.client.entity.fog;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.fog.FogEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the W7 fog-storm mobs — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern; W8's Fog Colossus registers in
 * its own {@code FogEliteRenderers}). Guarded on {@code DeferredHolder.isBound()} so the
 * client boots green while the {@code FogEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/P6-W7_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FogRenderers {
    private FogRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!FogEntities.FOG_REVENANT.isBound() || !FogEntities.STORM_HOUND.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(FogEntities.FOG_REVENANT.get(), FogRevenantRenderer::new);
        event.registerEntityRenderer(FogEntities.STORM_HOUND.get(), StormHoundRenderer::new);
    }
}
