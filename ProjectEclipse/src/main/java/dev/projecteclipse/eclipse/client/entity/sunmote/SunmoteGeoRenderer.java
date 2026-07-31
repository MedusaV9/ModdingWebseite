package dev.projecteclipse.eclipse.client.entity.sunmote;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.SunmoteEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.core.BlockPos;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Sunmote renderer (MC3 conversion) on the frozen {@link EclipseGeoRenderer} base:
 * defaulted asset triple for {@code sunmote}, no head tracking (the whole mote turns as
 * one — the geo has no {@code head} bone), the mob's first glowmask layer, and the
 * upright scripted death from {@code SunmoteEntity#tickDeath}.
 *
 * <p>Fullbright is kept from the old {@code SunmoteRenderer} (spec §1.5: the mote reads
 * as a light source at any time of day) — but the old whole-model additive
 * {@code RenderType.eyes} pass is gone: emission is now DIFFERENTIATED by the glowmask
 * (core, kernel and the ray wreath burn; the halo ring only catches the light on its
 * inner edge). No ground shadow: a mote of daylight hovering 1.5 blocks over the altar
 * must not paint a dark blob on the sanctum floor.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SunmoteGeoRenderer extends EclipseGeoRenderer<SunmoteEntity> {
    public SunmoteGeoRenderer(EntityRendererProvider.Context context) {
        super(context, SunmoteEntity.GEO_ID);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.0F;
    }

    @Override
    protected int getBlockLightLevel(SunmoteEntity entity, BlockPos pos) {
        return 15; // Fullbright per spec §1.5.
    }
}
