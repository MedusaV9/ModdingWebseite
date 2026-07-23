package dev.projecteclipse.eclipse.client.entity.glitch;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.glitch.GlitchEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the GLITCHED family — this family's OWN
 * {@code @EventBusSubscriber} per the P6 no-shared-file rule (the shared
 * {@code EclipseEntityRenderers} stays frozen). Annotation-discovered; no
 * {@code EclipseMod} wiring needed. No-ops via {@code isBound()} until the
 * {@code GlitchEntities} registrar line lands
 * ({@code docs/plans_v3/wiring/P6-W8_wiring.md}).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class GlitchRenderers {
    private GlitchRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!GlitchEntities.GLITCHED_HUSK.isBound() || !GlitchEntities.GLITCHED_HOUND.isBound()
                || !GlitchEntities.GLITCHED_TICK.isBound()) {
            return; // Registrar not wired yet (server half already logged the warning).
        }
        event.registerEntityRenderer(GlitchEntities.GLITCHED_HUSK.get(), GlitchedHuskRenderer::new);
        event.registerEntityRenderer(GlitchEntities.GLITCHED_HOUND.get(), GlitchedHoundRenderer::new);
        event.registerEntityRenderer(GlitchEntities.GLITCHED_TICK.get(), GlitchedTickRenderer::new);
    }
}
