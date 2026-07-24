package dev.projecteclipse.eclipse.client.entity.wizard;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.wizard.WizardOrinEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Orin the Sun-Reader renderer (W4-WIZARD): defaulted asset triple for
 * {@code wizard_orin} (64×64 canvas), head tracking ON (the hermit watches visitors —
 * the geo's {@code head} bone carries the hat + beard along), the
 * {@code _glowmask.png} layer for the constellation stitches embroidered into the robe,
 * the hat-tip star and the staff tip, and upright death for the scripted
 * {@link WizardOrinEntity#DEATH_DURATION_TICKS}-tick sit-down-fade — an astronomer
 * settling down one last time reads wrong if vanilla tips him sideways.
 */
@OnlyIn(Dist.CLIENT)
public class WizardOrinRenderer extends EclipseGeoRenderer<WizardOrinEntity> {
    public WizardOrinRenderer(EntityRendererProvider.Context context) {
        super(context, WizardOrinEntity.GEO_ID, true);
        withGlowmask().withUprightDeath();
        this.shadowRadius = 0.5F;
    }
}
