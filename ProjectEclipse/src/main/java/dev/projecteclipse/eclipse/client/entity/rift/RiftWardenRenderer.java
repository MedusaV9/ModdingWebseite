package dev.projecteclipse.eclipse.client.entity.rift;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.boss.rift.RiftWardenEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Rift Warden renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4): defaulted
 * asset triple for {@code rift_warden} (the 128×128 canvas), head tracking ON (the horned
 * helm follows its mark between attacks), the {@code _glowmask.png} layer for the boiling
 * void-tear half + blade edges + helm slit, and upright death for the scripted
 * {@link RiftWardenEntity#DEATH_DURATION_TICKS}-tick implosion — the rift swallowing the
 * body reads wrong if vanilla tips the knight sideways first.
 */
@OnlyIn(Dist.CLIENT)
public class RiftWardenRenderer extends EclipseGeoRenderer<RiftWardenEntity> {
    public RiftWardenRenderer(EntityRendererProvider.Context context) {
        super(context, RiftWardenEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.8F;
    }
}
