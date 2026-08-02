package dev.projecteclipse.eclipse.client.entity.herald;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
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
 * <p>The MA3 deletion snippet is applied (WAVE9-C): the legacy vanilla-model
 * registration ({@code HeraldModel}/{@code HeraldRenderer}) is gone from the shared
 * {@code EclipseEntityRenderers}, so this listener is the ONLY Herald renderer
 * registration and runs at default priority — the transitional
 * {@code EventPriority.LOWEST} last-write-wins crutch is gone.</p>
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class HeraldRenderers {
    private HeraldRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!(EclipseEntities.HERALD instanceof DeferredHolder<?, ?> holder) || !holder.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(EclipseEntities.HERALD.get(), HeraldGeoRenderer::new);
    }
}
