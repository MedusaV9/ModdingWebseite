package dev.projecteclipse.eclipse.client.entity.fog;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.fog.FogRevenantEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Fog Revenant renderer — defaulted asset triple for {@code fog_revenant}, head tracking
 * ON (the hooded skull follows its prey — the geo's {@code head} bone), glowmask layer
 * (cyan eye slits under the hood + the three orbiting {@code glow_wisp_*} cubes) and an
 * upright scripted death: the 40 t {@code death} anim disperses the wraith UPWARD into
 * its wisps, so the vanilla sideways tip-over must never fire. Faint shadow — it barely
 * touches the world.
 */
@OnlyIn(Dist.CLIENT)
public class FogRevenantRenderer extends EclipseGeoRenderer<FogRevenantEntity> {
    public FogRevenantRenderer(EntityRendererProvider.Context context) {
        super(context, FogRevenantEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.4F;
    }
}
