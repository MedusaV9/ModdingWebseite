package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.UmbralStalkerEntity;
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
 * Umbral Stalker renderer: the 11-cube quadruped plus an emissive pass ({@code
 * RenderType.eyes}, fullbright — Gazer skipDraw pattern) that re-renders the head (violet
 * eye pinpricks), the jaw shards and the crystal spine shards at full brightness. The
 * night hunter hunts at light 0, where the plain albedo glow was invisible — the emissive
 * pass keeps its silhouette readable in total darkness.
 */
@OnlyIn(Dist.CLIENT)
public class UmbralStalkerRenderer extends MobRenderer<UmbralStalkerEntity, UmbralStalkerModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/umbral_stalker.png");

    public UmbralStalkerRenderer(EntityRendererProvider.Context context) {
        super(context, new UmbralStalkerModel(context.bakeLayer(EclipseEntityRenderers.UMBRAL_STALKER_LAYER)), 0.6F);
        this.addLayer(new ShardEyesLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(UmbralStalkerEntity entity) {
        return TEXTURE;
    }

    /** Emissive shard pass ({@code RenderType.eyes}, fullbright: eyes + jaws + spine). */
    @OnlyIn(Dist.CLIENT)
    static class ShardEyesLayer extends RenderLayer<UmbralStalkerEntity, UmbralStalkerModel> {
        private static final RenderType EYES = RenderType.eyes(TEXTURE);

        ShardEyesLayer(RenderLayerParent<UmbralStalkerEntity, UmbralStalkerModel> parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
                UmbralStalkerEntity entity, float limbSwing, float limbSwingAmount, float partialTick,
                float ageInTicks, float netHeadYaw, float headPitch) {
            VertexConsumer buffer = bufferSource.getBuffer(EYES);
            this.getParentModel().renderEmissive(poseStack, buffer,
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
        }
    }
}
