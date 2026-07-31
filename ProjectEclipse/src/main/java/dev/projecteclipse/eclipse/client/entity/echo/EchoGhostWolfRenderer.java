package dev.projecteclipse.eclipse.client.entity.echo;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.woah.echogrove.EchoActor;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGhostWolfEntity;
import net.minecraft.client.model.WolfModel;
import net.minecraft.client.model.geom.ModelLayers;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.MobRenderer;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FastColor;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * WOAH-05 echo-wolf renderer (plan §4.3): the vanilla {@link WolfModel} (baked
 * from {@code ModelLayers.WOLF} — the reason {@code EchoGhostWolfEntity} extends
 * {@code Wolf}) drawn with the {@code EchoGhostRenderer} translucent-alpha
 * technique over the pale {@code echo_ghost_wolf.png}. Sitting pose falls out of
 * the entity's {@code isInSittingPose()} → ACTION mapping; trot/tail animation
 * falls out of the position deltas the scene player produces. No shadow, no
 * nameplate, no wolf-variant plumbing — one fixed spectral texture.
 */
@OnlyIn(Dist.CLIENT)
public final class EchoGhostWolfRenderer
        extends MobRenderer<EchoGhostWolfEntity, WolfModel<EchoGhostWolfEntity>> {
    public static final ResourceLocation TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/entity/echo_ghost_wolf.png");

    private static final float BODY_ALPHA = 0.35F;

    public EchoGhostWolfRenderer(EntityRendererProvider.Context context) {
        super(context, new EchoWolfModel(context.bakeLayer(ModelLayers.WOLF)), 0.0F);
    }

    @Override
    public ResourceLocation getTextureLocation(EchoGhostWolfEntity entity) {
        return TEXTURE;
    }

    @Override
    protected RenderType getRenderType(EchoGhostWolfEntity entity, boolean bodyVisible,
            boolean translucent, boolean glowing) {
        return entity.isInvisible() ? null : RenderType.entityTranslucent(TEXTURE);
    }

    @Override
    protected boolean shouldShowName(EchoGhostWolfEntity entity) {
        return false;
    }

    @Override
    public void render(EchoGhostWolfEntity entity, float entityYaw, float partialTick,
            PoseStack poseStack, MultiBufferSource bufferSource, int packedLight) {
        // MC4: shared family alpha curve (EchoGhostRenderer.echoAlpha) — same glow×fade
        // fix as the humanoid echoes, and the wolf now shimmers on the family's hashed
        // phase clock instead of its own ad-hoc multiply.
        ((EchoWolfModel) this.model).alpha = EchoGhostRenderer.echoAlpha(
                entity.echoFade() / (float) EchoActor.FADE_TICKS, entity.echoGlow(),
                entity.getId(), entity.tickCount + partialTick,
                EclipseClientConfig.reducedFx());
        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
    }

    /** {@link WolfModel} with renderer-driven whole-model alpha (the GhostModel technique). */
    @OnlyIn(Dist.CLIENT)
    static final class EchoWolfModel extends WolfModel<EchoGhostWolfEntity> {
        private float alpha = BODY_ALPHA;

        EchoWolfModel(ModelPart root) {
            super(root);
        }

        @Override
        public void renderToBuffer(PoseStack poseStack, VertexConsumer buffer, int packedLight,
                int packedOverlay, int color) {
            super.renderToBuffer(poseStack, buffer, packedLight, packedOverlay,
                    FastColor.ARGB32.multiply(color,
                            FastColor.ARGB32.colorFromFloat(this.alpha, 1.0F, 1.0F, 1.0F)));
        }
    }
}
