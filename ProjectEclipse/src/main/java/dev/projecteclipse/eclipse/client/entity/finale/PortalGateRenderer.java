package dev.projecteclipse.eclipse.client.entity.finale;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.ferryman.finale.PortalGateEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * F-045 portal-gate renderer: defaulted asset triple for {@code portal_gate}, no head
 * tracking (a monument does not look around), glowmask layer (the violet rune bands,
 * keystone sigil and door keyhole). No ground shadow — the arch's feet stand in water
 * and a 12-block prop with a vanilla blob shadow reads absurd.
 */
@OnlyIn(Dist.CLIENT)
public class PortalGateRenderer extends EclipseGeoRenderer<PortalGateEntity> {
    public PortalGateRenderer(EntityRendererProvider.Context context) {
        super(context, "portal_gate");
        withGlowmask();
        this.shadowRadius = 0.0F;
    }
}
