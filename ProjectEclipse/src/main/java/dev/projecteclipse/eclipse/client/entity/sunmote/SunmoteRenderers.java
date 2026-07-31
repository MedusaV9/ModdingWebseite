package dev.projecteclipse.eclipse.client.entity.sunmote;

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
 * Renderer registration for the Sunmote's GeckoLib conversion — auto-subscribed, no
 * {@code EclipseMod} wiring needed (house §1.6 pattern, {@code AmbientRenderers}
 * template with the {@code isBound()} guard; {@code EclipseEntities.SUNMOTE} is typed as
 * a plain {@code Supplier}, hence the instanceof-cast to reach the holder).
 *
 * <p>LOWEST priority on purpose (MA3 precedent): the legacy vanilla-model registration
 * in the SHARED {@code EclipseEntityRenderers} (conflict law G2 — MC3 must not edit it)
 * still runs at default priority and {@code registerEntityRenderer} is last-write-wins,
 * so this listener always lands after it and deterministically installs
 * {@link SunmoteGeoRenderer}, whether or not the integrator has applied the deletion
 * snippet from {@code MC3_AMBIENT_REPORT.md} yet. Once those three legacy lines are
 * gone the priority is redundant but harmless.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class SunmoteRenderers {
    private SunmoteRenderers() {}

    @SubscribeEvent(priority = EventPriority.LOWEST)
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!(EclipseEntities.SUNMOTE instanceof DeferredHolder<?, ?> holder) || !holder.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(EclipseEntities.SUNMOTE.get(), SunmoteGeoRenderer::new);
    }
}
