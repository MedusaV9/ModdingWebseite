package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.SunmoteEntity;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.MobRenderer;
import net.minecraft.client.renderer.entity.RenderLayerParent;
import net.minecraft.client.renderer.entity.layers.RenderLayer;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Sunmote renderer: fullbright (block light forced to 15) plus a whole-model
 * {@code RenderType.eyes} glow pass — the wisp reads as a light source at any time of day.
 */
@OnlyIn(Dist.CLIENT)
public class SunmoteRenderer extends MobRenderer<SunmoteEntity, SunmoteModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/sunmote.png");

    public SunmoteRenderer(EntityRendererProvider.Context context) {
        super(context, new SunmoteModel(context.bakeLayer(EclipseEntityRenderers.SUNMOTE_LAYER)), 0.15F);
        this.addLayer(new GlowLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(SunmoteEntity entity) {
        return TEXTURE;
    }

    @Override
    protected int getBlockLightLevel(SunmoteEntity entity, BlockPos pos) {
        return 15; // Fullbright per spec §1.5.
    }

    /** Additive whole-model glow pass. */
    @OnlyIn(Dist.CLIENT)
    static class GlowLayer extends RenderLayer<SunmoteEntity, SunmoteModel> {
        private static final RenderType EYES = RenderType.eyes(TEXTURE);

        GlowLayer(RenderLayerParent<SunmoteEntity, SunmoteModel> parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight, SunmoteEntity entity,
                float limbSwing, float limbSwingAmount, float partialTick, float ageInTicks,
                float netHeadYaw, float headPitch) {
            VertexConsumer buffer = bufferSource.getBuffer(EYES);
            this.getParentModel().root().render(poseStack, buffer,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
        }
    }
}
