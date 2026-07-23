package dev.projecteclipse.eclipse.client.entity.rift;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.rift.RiftEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the Rift Warden family — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern). Guarded on
 * {@code DeferredHolder.isBound()} so the client boots green while the
 * {@code RiftEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/P6-W910_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class RiftRenderers {
    private RiftRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!RiftEntities.RIFT_WARDEN.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(RiftEntities.RIFT_WARDEN.get(), RiftWardenRenderer::new);
    }
}
