package dev.projecteclipse.eclipse.client.entity.finale;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.ferryman.finale.SoulWispEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * F-045b soul-wisp renderer: defaulted asset triple for {@code soul_wisp}, glowmask
 * (inner soul core + eye slit), translucent render type (the shroud albedo carries
 * partial alpha — cutout would render the ghost solid), upright scripted death (the
 * shrink-and-spin {@code death} anim replaces the vanilla tip-over). Shadowless.
 */
@OnlyIn(Dist.CLIENT)
public class SoulWispRenderer extends EclipseGeoRenderer<SoulWispEntity> {
    public SoulWispRenderer(EntityRendererProvider.Context context) {
        super(context, "soul_wisp");
        withGlowmask().withTranslucency().withUprightDeath();
        this.shadowRadius = 0.0F;
    }
}
