package dev.projecteclipse.eclipse.client.entity.player;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.Minecraft;
import net.minecraft.client.model.PlayerModel;
import net.minecraft.client.player.AbstractClientPlayer;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.RenderLayerParent;
import net.minecraft.client.renderer.entity.layers.RenderLayer;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Emissive pass for the uniform "Purple Mythic" player skin (plans_v3 P6 §2.7): re-renders
 * the whole player model with {@code RenderType.eyes} (Ferryman/Herald skipDraw-family
 * pattern — vanilla render type, Veil-compatible, self-disabling under nothing) over a
 * dedicated glow texture that carries ONLY the heart, energy veins and eyes. Everything
 * else in that texture is transparent, so just those pixels draw — fullbright at any light
 * level, alpha-graded so forks glow softer than the heart core.
 *
 * <p>OFF-safe by design (no config): if {@code eclipsed_player_glow.png} is missing from
 * resources the layer no-ops forever after one warning, and the albedo skin still carries
 * bright heart/vein pixels (Iris-shaderpack fallback per plan §5). Skips invisible players
 * so the glow can never betray a potion-invisible teammate.</p>
 */
@OnlyIn(Dist.CLIENT)
public class EclipsedPlayerGlowLayer extends RenderLayer<AbstractClientPlayer, PlayerModel<AbstractClientPlayer>> {
    public static final ResourceLocation GLOW_TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/entity/eclipsed_player_glow.png");
    private static final RenderType GLOW_RENDER_TYPE = RenderType.eyes(GLOW_TEXTURE);

    /** Lazily resolved once; {@code null} = not checked yet (resources not ready at ctor). */
    private static volatile Boolean glowTexturePresent;

    public EclipsedPlayerGlowLayer(RenderLayerParent<AbstractClientPlayer, PlayerModel<AbstractClientPlayer>> parent) {
        super(parent);
    }

    private static boolean glowTextureAvailable() {
        Boolean present = glowTexturePresent;
        if (present == null) {
            present = Minecraft.getInstance().getResourceManager().getResource(GLOW_TEXTURE).isPresent();
            if (!present) {
                EclipseMod.LOGGER.warn("[skin v2] {} missing — player glow layer disabled (albedo fallback only)",
                        GLOW_TEXTURE);
            }
            glowTexturePresent = present;
        }
        return present;
    }

    @Override
    public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
            AbstractClientPlayer player, float limbSwing, float limbSwingAmount, float partialTick,
            float ageInTicks, float netHeadYaw, float headPitch) {
        if (player.isInvisible() || !glowTextureAvailable()) {
            return;
        }
        VertexConsumer buffer = bufferSource.getBuffer(GLOW_RENDER_TYPE);
        this.getParentModel().renderToBuffer(poseStack, buffer,
                LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
    }
}
