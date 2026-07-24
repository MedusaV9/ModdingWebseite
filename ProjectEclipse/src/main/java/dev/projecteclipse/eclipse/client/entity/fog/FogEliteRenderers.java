package dev.projecteclipse.eclipse.client.entity.fog;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.fog.FogEliteEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the W8 half of the fog family (the storm elite tier) —
 * this family's OWN {@code @EventBusSubscriber} per the P6 no-shared-file rule: W7's
 * {@code FogRenderers} is a sibling file and is never touched. Annotation-discovered;
 * no {@code EclipseMod} wiring needed. No-ops via {@code isBound()} until the
 * {@code FogEliteEntities} registrar line lands
 * ({@code docs/plans_v3/wiring/P6-W8_wiring.md}).
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class FogEliteRenderers {
    private FogEliteRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!FogEliteEntities.FOG_COLOSSUS.isBound()) {
            return; // Registrar not wired yet (server half already logged the warning).
        }
        event.registerEntityRenderer(FogEliteEntities.FOG_COLOSSUS.get(), FogColossusRenderer::new);
    }
}
