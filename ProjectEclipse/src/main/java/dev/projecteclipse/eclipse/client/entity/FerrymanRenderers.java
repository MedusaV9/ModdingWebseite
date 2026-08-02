package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;
import net.neoforged.neoforge.registries.DeferredHolder;

/**
 * Ferryman GeckoLib renderer registration (MA4) — auto-subscribed, own class per the
 * census §5 conflict law (G2: {@code EclipseEntityRenderers} is SHARED; this file is
 * MA4-owned instead). The {@code isBound()} guard keeps the client booting green even
 * if the {@code EclipseEntities} registrar wiring is ever absent (AmbientRenderers
 * pattern). The MA4 removal patch is applied (WAVE9-C): the legacy vanilla
 * {@code FerrymanRenderer}/{@code FerrymanModel} pair is deleted and the shared
 * registrar no longer registers anything for the Ferryman, so this listener runs at
 * default priority — the transitional {@code EventPriority.LOW} last-write-wins
 * crutch is gone.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FerrymanRenderers {
    private FerrymanRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (EclipseEntities.FERRYMAN instanceof DeferredHolder<?, ?> holder && !holder.isBound()) {
            return; // Registrar not wired — nothing to render.
        }
        event.registerEntityRenderer(EclipseEntities.FERRYMAN.get(), FerrymanGeoRenderer::new);
    }
}
