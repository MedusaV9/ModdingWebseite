package dev.projecteclipse.eclipse.client.entity.fog;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.fog.FogColossusEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Fog Colossus renderer (P6-W8) — the asset triple resolves off {@code fog_colossus}
 * (128×128 canvas, plan §6). Head tracking targets the tiny sunken {@code head} bone;
 * the glowmask layer carries the fissure light and eye embers
 * ({@code fog_colossus_glowmask.png}); the scripted 50 t forward-collapse death keeps
 * the body upright ({@code withUprightDeath()} — {@code tickDeath} owns the timing).
 */
@OnlyIn(Dist.CLIENT)
public class FogColossusRenderer extends EclipseGeoRenderer<FogColossusEntity> {
    public FogColossusRenderer(EntityRendererProvider.Context context) {
        super(context, FogColossusEntity.GEO_ID, true);
        withGlowmask();      // Glowing fissures + eye embers.
        withUprightDeath();  // Scripted forward collapse; no vanilla tip-over.
        this.shadowRadius = 1.3F;
    }
}
