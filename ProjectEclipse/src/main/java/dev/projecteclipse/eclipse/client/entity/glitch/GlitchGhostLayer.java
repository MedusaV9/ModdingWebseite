package dev.projecteclipse.eclipse.client.entity.glitch;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.entity.glitch.GlitchedMonster;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.renderer.layer.GeoRenderLayer;

/**
 * Chromatic ghost for the GLITCHED pose pop (MOB-GLITCH renderer pass): on the 1–2
 * frames a {@link GlitchedGeoRenderer#popOffset pop} is live, the full baked model is
 * re-rendered twice as translucent tinted copies — magenta pushed FURTHER along the
 * shear vector, cyan mirrored behind the popped anchor — so the blink reads as an
 * RGB-split tear (two color planes failing to land on the same vertices) instead of a
 * plain position hitch.
 *
 * <p>Runs inside the same {@code PoseStack} state as the popped main model (the
 * {@code preRender} shear is still applied), so both ghosts are positioned relative to
 * the popped anchor. Re-renders use {@code isReRender = true}, which skips layers —
 * no recursion, and the glowmask layer stays exclusive to the primary pass. When no
 * pop is live this layer is a single null-check per frame.</p>
 */
@OnlyIn(Dist.CLIENT)
final class GlitchGhostLayer<T extends GlitchedMonster> extends GeoRenderLayer<T> {
    /** Ghost separation as a multiple of the pop shear (magenta +, cyan −1−this). */
    private static final float GHOST_SPREAD = 0.8F;
    /** ~38% alpha family magenta/cyan — visible tear, silhouette stays readable. */
    private static final int GHOST_MAGENTA_ARGB = 0x60FF3B6B;
    private static final int GHOST_CYAN_ARGB = 0x6037F2E5;

    GlitchGhostLayer(GlitchedGeoRenderer<T> renderer) {
        super(renderer);
    }

    @Override
    public void render(PoseStack poseStack, T animatable, BakedGeoModel bakedModel,
            RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
            float partialTick, int packedLight, int packedOverlay) {
        float[] pop = GlitchedGeoRenderer.popOffset(animatable, partialTick);
        if (pop == null) {
            return;
        }
        RenderType ghostType = RenderType.entityTranslucent(getTextureResource(animatable));
        // Magenta plane: overshoots the shear (the "late" color channel).
        renderGhost(poseStack, animatable, bakedModel, ghostType, bufferSource, partialTick,
                packedLight, pop, GHOST_SPREAD, GHOST_MAGENTA_ARGB);
        // Cyan plane: mirrored back past the true anchor (the "stale" channel).
        renderGhost(poseStack, animatable, bakedModel, ghostType, bufferSource, partialTick,
                packedLight, pop, -1.0F - GHOST_SPREAD, GHOST_CYAN_ARGB);
    }

    private void renderGhost(PoseStack poseStack, T animatable, BakedGeoModel bakedModel,
            RenderType ghostType, MultiBufferSource bufferSource, float partialTick,
            int packedLight, float[] pop, float along, int argb) {
        poseStack.pushPose();
        poseStack.translate(pop[0] * along, pop[1] * along, pop[2] * along);
        getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, ghostType,
                bufferSource.getBuffer(ghostType), partialTick, packedLight,
                OverlayTexture.NO_OVERLAY, argb);
        poseStack.popPose();
    }
}
