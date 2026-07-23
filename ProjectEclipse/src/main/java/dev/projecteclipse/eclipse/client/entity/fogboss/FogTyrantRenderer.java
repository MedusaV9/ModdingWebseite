package dev.projecteclipse.eclipse.client.entity.fogboss;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Fog Tyrant renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4): defaulted
 * asset triple for {@code fog_tyrant} (the 128×128 canvas), head tracking ON (the hooded
 * monarch stares its mark down between volleys), the {@code _glowmask.png} emissive layer
 * for the floating shard-crown + eye slit + storm-core chest cavity + lance edges, and
 * upright death for the scripted {@link FogTyrantEntity#DEATH_DURATION_TICKS}-tick
 * collapse — the crown-falls-first finale reads wrong if vanilla tips the monarch
 * sideways underneath it.
 */
@OnlyIn(Dist.CLIENT)
public class FogTyrantRenderer extends EclipseGeoRenderer<FogTyrantEntity> {
    public FogTyrantRenderer(EntityRendererProvider.Context context) {
        super(context, FogTyrantEntity.GEO_ID, true);
        withGlowmask();      // Crown shards, eye slit, chest core, lance edges.
        withUprightDeath();  // Scripted crown-fall collapse; no vanilla tip-over.
        this.shadowRadius = 1.1F;
    }
}
