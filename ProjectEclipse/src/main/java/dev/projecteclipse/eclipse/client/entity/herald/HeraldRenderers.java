package dev.projecteclipse.eclipse.client.entity.herald;

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
 * Renderer registration for the Herald's GeckoLib conversion — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern, {@code AmbientRenderers}
 * template with the {@code isBound()} guard; {@code EclipseEntities.HERALD} is typed
 * as a plain {@code Supplier}, hence the instanceof-cast to reach it).
 *
 * <p>LOWEST priority on purpose: the legacy vanilla-model registration in the SHARED
 * {@code EclipseEntityRenderers} (conflict law G2 — MA3 must not edit it) still runs at
 * default priority, and {@code registerEntityRenderer} is last-write-wins. This listener
 * therefore always lands AFTER it and deterministically installs
 * {@link HeraldGeoRenderer}, whether or not the integrator has applied the deletion
 * snippet from {@code MA3_HERALD_REPORT.md} yet. Once those two legacy lines (layer
 * definition + renderer) are gone, the priority is redundant but harmless.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class HeraldRenderers {
    private HeraldRenderers() {}

    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!(EclipseEntities.HERALD instanceof DeferredHolder<?, ?> holder) || !holder.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(EclipseEntities.HERALD.get(), HeraldGeoRenderer::new);
    }
}
