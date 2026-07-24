package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
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
 * Herald renderer: the 26-cube godhead plus an emissive pass ({@code RenderType.eyes},
 * fullbright — Gazer skipDraw pattern) that keeps the inner eye burning out of the black
 * glass at any light level, and pulls the 8 corona shards into the same glow pass while a
 * volley telegraph is winding up (the server syncs {@code isTelegraphing()}).
 */
@OnlyIn(Dist.CLIENT)
public class HeraldRenderer extends MobRenderer<HeraldEntity, HeraldModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/herald.png");

    public HeraldRenderer(EntityRendererProvider.Context context) {
        super(context, new HeraldModel(context.bakeLayer(EclipseEntityRenderers.HERALD_LAYER)), 1.1F);
        this.addLayer(new EmissiveLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(HeraldEntity entity) {
        return TEXTURE;
    }

    /**
     * While the scripted death collapse runs ({@code deathTime > 0},
     * {@code HeraldEntity.tickDeath}), the model poses the wreck itself — suppress the
     * vanilla 20t sideways death flip and keep only the body yaw.
     */
    @Override
    protected void setupRotations(HeraldEntity entity, PoseStack poseStack, float bob, float yBodyRot,
            float partialTick, float scale) {
        if (entity.deathTime > 0) {
            poseStack.mulPose(Axis.YP.rotationDegrees(180.0F - yBodyRot));
            return;
        }
        super.setupRotations(entity, poseStack, bob, yBodyRot, partialTick, scale);
    }

    /** Emissive pass: inner eye always; corona shards only during a volley telegraph. */
    @OnlyIn(Dist.CLIENT)
    static class EmissiveLayer extends RenderLayer<HeraldEntity, HeraldModel> {
        private static final RenderType EYES = RenderType.eyes(TEXTURE);

        EmissiveLayer(RenderLayerParent<HeraldEntity, HeraldModel> parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
                HeraldEntity entity, float limbSwing, float limbSwingAmount, float partialTick,
                float ageInTicks, float netHeadYaw, float headPitch) {
            VertexConsumer buffer = bufferSource.getBuffer(EYES);
            this.getParentModel().renderEmissive(poseStack, buffer,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY, entity.isTelegraphing());
        }
    }
}
