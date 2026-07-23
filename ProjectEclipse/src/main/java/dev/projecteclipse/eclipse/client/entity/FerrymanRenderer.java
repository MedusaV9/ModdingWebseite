package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.MobRenderer;
import net.minecraft.client.renderer.entity.RenderLayerParent;
import net.minecraft.client.renderer.entity.layers.RenderLayer;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Ferryman renderer: the 17-cube robed rower plus an emissive pass ({@code RenderType.eyes},
 * fullbright — Herald skipDraw pattern) that keeps the eye slit and the lantern flame
 * burning inside the hood at any light level, and pulls the whole lantern housing into the
 * glow pass while the P3 Lantern Gaze is marking a player (the server syncs
 * {@code isGazing()}).
 */
@OnlyIn(Dist.CLIENT)
public class FerrymanRenderer extends MobRenderer<FerrymanEntity, FerrymanModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/ferryman.png");

    public FerrymanRenderer(EntityRendererProvider.Context context) {
        super(context, new FerrymanModel(context.bakeLayer(EclipseEntityRenderers.FERRYMAN_LAYER)), 0.9F);
        this.addLayer(new EmissiveLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(FerrymanEntity entity) {
        return TEXTURE;
    }

    /**
     * While the scripted death collapse runs ({@code deathTime > 0},
     * {@code FerrymanEntity.tickDeath}), the model sinks the body upright itself —
     * suppress the vanilla 20t sideways death flip and keep only the body yaw.
     */
    @Override
    protected void setupRotations(FerrymanEntity entity, PoseStack poseStack, float bob, float yBodyRot,
            float partialTick, float scale) {
        if (entity.deathTime > 0) {
            poseStack.mulPose(Axis.YP.rotationDegrees(180.0F - yBodyRot));
            return;
        }
        super.setupRotations(entity, poseStack, bob, yBodyRot, partialTick, scale);
    }

    /**
     * Emissive pass: eye slit always; the lantern flame until it gutters out during the
     * death collapse; the whole lantern housing while the Gaze is marking.
     */
    @OnlyIn(Dist.CLIENT)
    static class EmissiveLayer extends RenderLayer<FerrymanEntity, FerrymanModel> {
        private static final RenderType EYES = RenderType.eyes(TEXTURE);

        EmissiveLayer(RenderLayerParent<FerrymanEntity, FerrymanModel> parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
                FerrymanEntity entity, float limbSwing, float limbSwingAmount, float partialTick,
                float ageInTicks, float netHeadYaw, float headPitch) {
            VertexConsumer buffer = bufferSource.getBuffer(EYES);
            this.getParentModel().renderEmissive(poseStack, buffer,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY,
                    entity.isGazing(), entity.isLanternFlameLit());
        }
    }
}
