package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.GazerEntity;
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
 * Gazer renderer: the 6-cube cloak model plus an emissive pass that re-renders ONLY the
 * 6x6x1 face inset with {@code RenderType.eyes} at full brightness — the pale violet face
 * glows out of the pitch-black hood interior regardless of ambient light.
 */
@OnlyIn(Dist.CLIENT)
public class GazerRenderer extends MobRenderer<GazerEntity, GazerModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/gazer.png");

    public GazerRenderer(EntityRendererProvider.Context context) {
        super(context, new GazerModel(context.bakeLayer(EclipseEntityRenderers.GAZER_LAYER)), 0.4F);
        this.addLayer(new FaceEyesLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(GazerEntity entity) {
        return TEXTURE;
    }

    /** Emissive face pass ({@code RenderType.eyes}, fullbright, face cube only). */
    @OnlyIn(Dist.CLIENT)
    static class FaceEyesLayer extends RenderLayer<GazerEntity, GazerModel> {
        private static final RenderType EYES = RenderType.eyes(TEXTURE);

        FaceEyesLayer(RenderLayerParent<GazerEntity, GazerModel> parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight, GazerEntity entity,
                float limbSwing, float limbSwingAmount, float partialTick, float ageInTicks,
                float netHeadYaw, float headPitch) {
            VertexConsumer buffer = bufferSource.getBuffer(EYES);
            this.getParentModel().renderFaceEmissive(poseStack, buffer,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
        }
    }
}
