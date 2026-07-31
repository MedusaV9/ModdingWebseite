package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import net.neoforged.neoforge.registries.DeferredHolder;

/**
 * Ferryman GeckoLib renderer registration (MA4) — auto-subscribed, own class per the
 * census §5 conflict law (G2: {@code EclipseEntityRenderers} is SHARED; this file is
 * MA4-owned instead). Two guards:
 *
 * <ul>
 *   <li>{@code isBound()} — the client boots green even if the {@code EclipseEntities}
 *       registrar wiring is ever absent (AmbientRenderers pattern).</li>
 *   <li>{@link EventPriority#LOW} — {@code EclipseEntityRenderers} still registers the
 *       legacy vanilla {@code FerrymanRenderer} at NORMAL priority; renderer providers
 *       land in a map where the LAST registration wins, so running after it makes the
 *       GeckoLib renderer the deterministic winner until the integrator applies the
 *       removal patch ({@code docs/plans_v3/session_0730/MA4_FERRYMAN_REPORT.md}).</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FerrymanRenderers {
    private FerrymanRenderers() {}

    @SubscribeEvent(priority = EventPriority.LOW)
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (EclipseEntities.FERRYMAN instanceof DeferredHolder<?, ?> holder && !holder.isBound()) {
            return; // Registrar not wired — nothing to render.
        }
        event.registerEntityRenderer(EclipseEntities.FERRYMAN.get(), FerrymanGeoRenderer::new);
    }
}
