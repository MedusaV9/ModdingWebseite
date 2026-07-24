package dev.projecteclipse.eclipse.client.entity.dungeon;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.dungeon.EclipseCultistEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Eclipse Cultist renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3):
 * defaulted asset triple for {@code eclipse_cultist}, head tracking ON (the deep hood
 * turning to watch you is the mob's menace), and the {@code _glowmask.png} layer for the
 * orbiting rune pages + the trim sigils. Death stays upright for the scripted
 * {@link EclipseCultistEntity#DEATH_ANIM_TICKS}-tick kneel-forward collapse.
 */
@OnlyIn(Dist.CLIENT)
public class EclipseCultistRenderer extends EclipseGeoRenderer<EclipseCultistEntity> {
    public EclipseCultistRenderer(EntityRendererProvider.Context context) {
        super(context, EclipseCultistEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.4F;
    }
}
