package dev.projecteclipse.eclipse.client.entity.pale;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.pale.PaleEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the pale-garden family — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern). Guarded on
 * {@code DeferredHolder.isBound()} so the client boots green while the
 * {@code PaleEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/P6-W910_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class PaleRenderers {
    private PaleRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!PaleEntities.PALE_SENTINEL.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(PaleEntities.PALE_SENTINEL.get(), PaleSentinelRenderer::new);
    }
}
