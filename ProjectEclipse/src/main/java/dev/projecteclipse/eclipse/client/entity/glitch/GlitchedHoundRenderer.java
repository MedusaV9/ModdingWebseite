package dev.projecteclipse.eclipse.client.entity.glitch;

import dev.projecteclipse.eclipse.entity.glitch.GlitchedHoundEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Glitched Hound renderer (P6-W8) — asset triple off {@code glitched_hound}; the
 * detached {@code head} bone inside the floating neck shard is head-tracked (the skull
 * swivels while the fragments lag). Flicker/glowmask/pose-pop come from
 * {@link GlitchedGeoRenderer}.
 */
@OnlyIn(Dist.CLIENT)
public class GlitchedHoundRenderer extends GlitchedGeoRenderer<GlitchedHoundEntity> {
    public GlitchedHoundRenderer(EntityRendererProvider.Context context) {
        super(context, GlitchedHoundEntity.GEO_ID, true);
        this.shadowRadius = 0.6F;
    }
}
