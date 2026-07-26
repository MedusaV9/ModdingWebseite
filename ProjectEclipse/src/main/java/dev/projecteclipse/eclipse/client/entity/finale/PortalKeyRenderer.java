package dev.projecteclipse.eclipse.client.entity.finale;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.ferryman.finale.PortalKeyEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * F-045b portal-key renderer: defaulted asset triple for {@code portal_key}, glowmask
 * layer (the violet gem + filigree seams). Shadowless — it hovers over the altar and
 * later flies; a blob shadow racing across the island would break the read.
 */
@OnlyIn(Dist.CLIENT)
public class PortalKeyRenderer extends EclipseGeoRenderer<PortalKeyEntity> {
    public PortalKeyRenderer(EntityRendererProvider.Context context) {
        super(context, "portal_key");
        withGlowmask();
        this.shadowRadius = 0.0F;
    }
}
