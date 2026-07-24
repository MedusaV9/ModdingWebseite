package dev.projecteclipse.eclipse.client.backrooms;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsEntities;
import dev.projecteclipse.eclipse.backrooms.GlitchedWandererEntity;
import dev.projecteclipse.eclipse.client.entity.glitch.GlitchedGeoRenderer;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the Backrooms event mobs — this package's OWN
 * {@code @EventBusSubscriber} per the P6 no-shared-file rule ({@code GlitchRenderers}
 * precedent). Annotation-discovered; no {@code EclipseMod} wiring needed; no-ops via
 * {@code isBound()} until the {@code BackroomsEntities} registrar line lands.
 *
 * <p>The Wanderer reuses the full GLITCHED datamosh presentation
 * ({@link GlitchedGeoRenderer}: hash-scheduled {@code _alt} texture bursts, lockstep
 * glowmask, pose pop, upright scripted death) over the {@code glitched_wanderer} asset
 * triple — geo/anim are byte-copies of the husk's shape with renamed identifiers, the
 * four texture sheets are the python mono-yellow "wet paint" regrades (IDEAS §A3.1).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BackroomsRenderers {
    private BackroomsRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!BackroomsEntities.GLITCHED_WANDERER.isBound()) {
            return; // Registrar not wired yet (server half already logged the warning).
        }
        event.registerEntityRenderer(BackroomsEntities.GLITCHED_WANDERER.get(),
                GlitchedWandererRenderer::new);
    }

    /** Husk-shaped renderer over the {@code glitched_wanderer} triple (head-tracked). */
    @OnlyIn(Dist.CLIENT)
    static class GlitchedWandererRenderer extends GlitchedGeoRenderer<GlitchedWandererEntity> {
        GlitchedWandererRenderer(EntityRendererProvider.Context context) {
            super(context, GlitchedWandererEntity.GEO_ID, true);
            this.shadowRadius = 0.5F;
        }
    }
}
