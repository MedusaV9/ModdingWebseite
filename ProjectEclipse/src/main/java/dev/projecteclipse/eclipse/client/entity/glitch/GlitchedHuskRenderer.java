package dev.projecteclipse.eclipse.client.entity.glitch;

import dev.projecteclipse.eclipse.entity.glitch.GlitchedHuskEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Glitched Husk renderer (P6-W8) — asset triple off {@code glitched_husk}; the tilted
 * {@code head} bone is head-tracked (the displaced half-face follows as a rigid
 * cluster). Flicker/glowmask/pose-pop come from {@link GlitchedGeoRenderer}.
 */
@OnlyIn(Dist.CLIENT)
public class GlitchedHuskRenderer extends GlitchedGeoRenderer<GlitchedHuskEntity> {
    public GlitchedHuskRenderer(EntityRendererProvider.Context context) {
        super(context, GlitchedHuskEntity.GEO_ID, true);
        this.shadowRadius = 0.5F;
    }
}
