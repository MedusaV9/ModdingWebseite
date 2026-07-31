package dev.projecteclipse.eclipse.client.entity.gazer;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.GazerEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Gazer GeckoLib renderer (MC1 conversion): defaulted asset triple for {@code gazer}
 * (64x64 canvas), head tracking ON (the {@code head} bone carries the hood, mask, iris
 * rig and lids — the whole face follows the look target like the old code model's hood
 * yaw), the {@code _glowmask.png} layer (the Gazer's first: the pale mask front burns
 * with dark eye slits, the violet iris pips burn whole — replaces the old
 * {@code RenderType.eyes} face re-render, and the cloth lids occlude it when they blink
 * shut because they sit proud of the mask in z) and upright death for the scripted
 * {@link GazerEntity#DEATH_ANIM_TICKS}-tick gutter-out (bypass-kills only) — the held
 * {@code death} anim closes the lids forever, vanilla's sideways flip would fight it.
 */
@OnlyIn(Dist.CLIENT)
public class GazerGeoRenderer extends EclipseGeoRenderer<GazerEntity> {
    public GazerGeoRenderer(EntityRendererProvider.Context context) {
        super(context, GazerEntity.GEO_ID, true);
        withGlowmask();
        withUprightDeath();
        this.shadowRadius = 0.4F; // Parity with the old MobRenderer registration.
    }
}
