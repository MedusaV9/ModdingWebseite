package dev.projecteclipse.eclipse.client.entity.ambient;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.ambient.DriftLanternEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Drift Lantern renderer — the pilot use of the frozen GeckoLib base
 * ({@code docs/plans_v3/handoff/P6_geckolib_conventions.md}): defaulted asset triple for
 * {@code drift_lantern}, no head tracking (the whole lantern bobs as one), glowmask layer
 * (soul flame + the shine-through blob painted on the cage faces), upright scripted
 * death, and a translucent render type for the 40%-alpha glass panes. No ground shadow:
 * it is a floating spirit light.
 */
@OnlyIn(Dist.CLIENT)
public class DriftLanternRenderer extends EclipseGeoRenderer<DriftLanternEntity> {
    public DriftLanternRenderer(EntityRendererProvider.Context context) {
        super(context, DriftLanternEntity.GEO_ID);
        withGlowmask().withUprightDeath().withTranslucency();
        this.shadowRadius = 0.0F;
    }
}
