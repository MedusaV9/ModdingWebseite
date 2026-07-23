package dev.projecteclipse.eclipse.client.entity.pale;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.pale.PaleSentinelEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Pale Sentinel renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3): defaulted
 * asset triple for {@code pale_sentinel}, head tracking ON (the geo has a {@code head}
 * bone — while frozen the server re-asserts the yaw/pitch snapshot every tick, so the
 * statue's head genuinely stays put and tracking only shows while it creeps), the
 * {@code _glowmask.png} layer for the two faint hollow-socket eye embers, and upright
 * death for the scripted {@link PaleSentinelEntity#DEATH_ANIM_TICKS}-tick crumble (the
 * vanilla sideways tip-over would wreck the rooted-tree silhouette).
 */
@OnlyIn(Dist.CLIENT)
public class PaleSentinelRenderer extends EclipseGeoRenderer<PaleSentinelEntity> {
    public PaleSentinelRenderer(EntityRendererProvider.Context context) {
        super(context, PaleSentinelEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.55F;
    }
}
