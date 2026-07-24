package dev.projecteclipse.eclipse.client.entity.glitch;

import dev.projecteclipse.eclipse.entity.glitch.GlitchedTickEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Glitched Tick renderer (P6-W8) — asset triple off {@code glitched_tick}. No head
 * tracking: the mite reads as a scuttling object, not a gazer (and the mandible
 * {@code head} bone is animation-driven). Flicker/glowmask/pose-pop come from
 * {@link GlitchedGeoRenderer}; the magenta core glow does the aiming for it.
 */
@OnlyIn(Dist.CLIENT)
public class GlitchedTickRenderer extends GlitchedGeoRenderer<GlitchedTickEntity> {
    public GlitchedTickRenderer(EntityRendererProvider.Context context) {
        super(context, GlitchedTickEntity.GEO_ID, false);
        this.shadowRadius = 0.3F;
    }
}
