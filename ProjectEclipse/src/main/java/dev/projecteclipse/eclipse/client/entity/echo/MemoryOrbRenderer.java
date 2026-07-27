package dev.projecteclipse.eclipse.client.entity.echo;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.echo.EchoGroveFx;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.woah.echogrove.MemoryOrbEntity;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRenderer;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * WOAH-05 memory-orb renderer (plan §4.3): one camera-facing translucent-emissive
 * quad (the {@code ExperienceOrbRenderer} vertex school) breathing on a slow
 * per-entity sine — the guaranteed photon-less read of every orb (baseline law;
 * the Photon attach-loop in {@code EchoOrbGlowFx} only adds sparks on top).
 *
 * <p>Two looks off the synced data: cold blue-white for waiting orbs,
 * {@code DATA_LIT} → warmer gold tint + {@value #LIT_SCALE}× size. The flood
 * warmth ({@link EchoGroveFx#warmth}) leans even the cold orbs golden while the
 * past is showing — the whole hollow agrees on one palette.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class MemoryOrbRenderer extends EntityRenderer<MemoryOrbEntity> {
    public static final ResourceLocation TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/entity/memory_orb.png");
    private static final RenderType RENDER_TYPE = RenderType.entityTranslucentEmissive(TEXTURE);

    /** Quad half-extent in blocks (entity box is 0.5×0.5). */
    private static final float HALF_SIZE = 0.30F;
    private static final float LIT_SCALE = 1.3F;
    /** Slow breath: ±12% size, ~3 s period (calm — a memory, not an alarm). */
    private static final float PULSE_AMPLITUDE = 0.12F;
    private static final float PULSE_SPEED = 0.105F;

    public MemoryOrbRenderer(EntityRendererProvider.Context context) {
        super(context);
        this.shadowRadius = 0.0F;
    }

    @Override
    public ResourceLocation getTextureLocation(MemoryOrbEntity entity) {
        return TEXTURE;
    }

    @Override
    public void render(MemoryOrbEntity entity, float entityYaw, float partialTick,
            PoseStack poseStack, MultiBufferSource bufferSource, int packedLight) {
        float time = entity.tickCount + partialTick;
        float phase = (entity.getId() * 0x9E3779B9) & 0xFF;
        float pulse = EclipseClientConfig.reducedFx() ? 1.0F
                : 1.0F + Mth.sin((time + phase) * PULSE_SPEED) * PULSE_AMPLITUDE;
        float scale = pulse * (entity.isLit() ? LIT_SCALE : 1.0F);

        // Palette: cold #A8C8E8 ↔ lit/warm #F0D090; flood warmth leans cold orbs gold.
        float warm = entity.isLit() ? 1.0F : EchoGroveFx.warmth(partialTick) * 0.6F;
        float red = Mth.lerp(warm, 0.66F, 0.94F);
        float green = Mth.lerp(warm, 0.78F, 0.82F);
        float blue = Mth.lerp(warm, 0.91F, 0.56F);
        float alpha = entity.isLit() ? 0.95F : 0.80F;

        poseStack.pushPose();
        poseStack.translate(0.0D, 0.25D, 0.0D); // quad at the 0.5-box center
        poseStack.mulPose(this.entityRenderDispatcher.cameraOrientation());
        poseStack.scale(scale, scale, scale);

        PoseStack.Pose pose = poseStack.last();
        VertexConsumer buffer = bufferSource.getBuffer(RENDER_TYPE);
        vertex(buffer, pose, -HALF_SIZE, -HALF_SIZE, 0.0F, 1.0F, red, green, blue, alpha);
        vertex(buffer, pose, HALF_SIZE, -HALF_SIZE, 1.0F, 1.0F, red, green, blue, alpha);
        vertex(buffer, pose, HALF_SIZE, HALF_SIZE, 1.0F, 0.0F, red, green, blue, alpha);
        vertex(buffer, pose, -HALF_SIZE, HALF_SIZE, 0.0F, 0.0F, red, green, blue, alpha);
        poseStack.popPose();

        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
    }

    private static void vertex(VertexConsumer buffer, PoseStack.Pose pose, float x, float y,
            float u, float v, float red, float green, float blue, float alpha) {
        buffer.addVertex(pose, x, y, 0.0F)
                .setColor(red, green, blue, alpha)
                .setUv(u, v)
                .setOverlay(OverlayTexture.NO_OVERLAY)
                .setLight(LightTexture.FULL_BRIGHT)
                .setNormal(pose, 0.0F, 1.0F, 0.0F);
    }
}
