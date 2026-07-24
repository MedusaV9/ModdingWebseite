package dev.projecteclipse.eclipse.client.entity.fog;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.fog.StormHoundEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Storm Hound renderer — defaulted asset triple for {@code storm_hound}, head tracking
 * ON ({@code head} bone), glowmask layer (the three {@code glow_spine} shards +
 * {@code glow_horn} antenna, the electric flank veins, eye dots and the charged tail
 * tip — the windup anim scales the spine bones, so the glow visibly ramps before a
 * lunge). {@code withUprightDeath()} is deliberate even though the hound dies sideways:
 * the 30 t {@code death} anim rolls the root itself, and the vanilla tip-over would
 * double-rotate the corpse.
 */
@OnlyIn(Dist.CLIENT)
public class StormHoundRenderer extends EclipseGeoRenderer<StormHoundEntity> {
    public StormHoundRenderer(EntityRendererProvider.Context context) {
        super(context, StormHoundEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.5F;
    }
}
