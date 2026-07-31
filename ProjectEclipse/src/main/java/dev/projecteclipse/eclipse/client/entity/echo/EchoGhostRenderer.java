package dev.projecteclipse.eclipse.client.entity.echo;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.woah.echogrove.EchoActor;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGhostEntity;
import net.minecraft.client.Minecraft;
import net.minecraft.client.model.PlayerModel;
import net.minecraft.client.model.geom.ModelLayers;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.LightTexture;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.LivingEntityRenderer;
import net.minecraft.client.renderer.entity.layers.RenderLayer;
import net.minecraft.client.renderer.texture.OverlayTexture;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FastColor;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * WOAH-05 echo-ghost renderer (plan §4.3) — the {@code GhostPlayerRenderer}
 * bauart copy-and-stripped (that class is welded to the logout-ghost reveal
 * logic): vanilla WIDE player model over the pale {@code echo_ghost.png},
 * translucent pass, no shadow, no nameplate. What is NEW against the original:
 *
 * <ul>
 *   <li><b>Alpha</b> = {@value #BODY_ALPHA} × fade({@code DATA_FADE}) +
 *       {@value #GLOW_ALPHA} × {@code DATA_GLOW} — actors ease in/out through the
 *       scene player's fade window and brighten during floods (plan §3.5);
 *       the original's shimmer/drift sines ride on top (hash-per-entity phases,
 *       ghosts never in lockstep); constant alpha under {@code reducedFx}.</li>
 *   <li><b>{@code DATA_CHILD}</b> → whole-model scale {@value #CHILD_SCALE}.</li>
 *   <li><b>{@code ACTION_SIT}</b> → the model's riding pose + a −0.45 body drop
 *       (the bench couple sits ON the prop bench, not in the air).</li>
 *   <li><b>{@code ACTION_WAVE}</b> → raised, gently swaying left arm (posed in
 *       {@link EchoModel#setupAnim} — we own the model).</li>
 *   <li>No purple heart: instead {@link MoonGlowLayer} re-renders the body over
 *       {@code echo_ghost_glow.png} with {@code RenderType.eyes} at a faint
 *       {@value MoonGlowLayer#GLOW_BASE} — a moonlit silhouette, night-readable
 *       without reading "undead".</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
public final class EchoGhostRenderer extends LivingEntityRenderer<EchoGhostEntity, EchoGhostRenderer.EchoModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/echo_ghost.png");

    /** Base body alpha at full fade (plan §4.3: 0.35). */
    private static final float BODY_ALPHA = 0.35F;
    /** Flood/finale brightness boost per DATA_GLOW unit (plan §4.3: 0.20). */
    private static final float GLOW_ALPHA = 0.20F;
    private static final float CHILD_SCALE = 0.72F;
    private static final float SIT_DROP = 0.45F;
    /** Hover + drift (the GhostPlayerRenderer set, slightly calmer — these walk). */
    private static final float HOVER_BLOCKS = 1.0F / 16.0F;
    private static final float DRIFT_BLOCKS = 0.03F;
    private static final float DRIFT_SPEED = 0.021F;
    private static final float SHIMMER_ALPHA = 0.04F;
    private static final float SHIMMER_SPEED = 0.09F;

    public EchoGhostRenderer(EntityRendererProvider.Context context) {
        // Shadow radius 0 — a memory casts no shadow.
        super(context, new EchoModel(context.bakeLayer(ModelLayers.PLAYER)), 0.0F);
        this.addLayer(new MoonGlowLayer(this));
    }

    @Override
    public ResourceLocation getTextureLocation(EchoGhostEntity entity) {
        return TEXTURE;
    }

    /** Always the translucent pass; honors true invisibility. */
    @Override
    protected RenderType getRenderType(EchoGhostEntity entity, boolean bodyVisible,
            boolean translucent, boolean glowing) {
        return entity.isInvisible() ? null : RenderType.entityTranslucent(TEXTURE);
    }

    @Override
    protected boolean shouldShowName(EchoGhostEntity entity) {
        return false;
    }

    @Override
    protected void scale(EchoGhostEntity entity, PoseStack poseStack, float partialTick) {
        if (entity.isChildEcho()) {
            poseStack.scale(CHILD_SCALE, CHILD_SCALE, CHILD_SCALE);
        }
    }

    @Override
    public void render(EchoGhostEntity entity, float entityYaw, float partialTick,
            PoseStack poseStack, MultiBufferSource bufferSource, int packedLight) {
        float time = entity.tickCount + partialTick;
        float driftPhase = hash(entity.getId(), 0xD21F7) & 0xFF;
        float bob = HOVER_BLOCKS + Mth.sin((time + driftPhase) * DRIFT_SPEED) * DRIFT_BLOCKS;
        boolean sitting = entity.echoAction() == EchoActor.ACTION_SIT;

        this.model.alpha = computeAlpha(entity, time);

        poseStack.pushPose();
        poseStack.translate(0.0F, sitting ? -SIT_DROP : bob, 0.0F);
        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
        poseStack.popPose();
    }

    /** fade-scaled base + glow boost + idle shimmer (constant under reducedFx). */
    private static float computeAlpha(EchoGhostEntity entity, float time) {
        return echoAlpha(entity.echoFade() / (float) EchoActor.FADE_TICKS,
                entity.echoGlow(), entity.getId(), time, EclipseClientConfig.reducedFx());
    }

    /**
     * Shared echo-family alpha curve (the wolf renderer reuses it): {@code (base +
     * glow·boost) × fade + shimmer × fade}. MC4 alpha-curve fix: the flood/finale glow
     * boost now rides INSIDE the fade envelope — previously it was added un-faded, so an
     * actor materializing or releasing DURING a flood popped in/out at {@code 0.20 ×
     * glow} instead of easing from/to zero (the {@code MoonGlowLayer} always faded
     * correctly, which made the body pop stand out even more). At full fade the value is
     * unchanged. Package-visible + primitive args for the MC4 offline harness (report §5).
     */
    static float echoAlpha(float fade, float glow, int entityId, float time, boolean reducedFx) {
        float alpha = (BODY_ALPHA + GLOW_ALPHA * glow) * fade;
        if (reducedFx) {
            return Mth.clamp(alpha, 0.0F, 0.8F);
        }
        float shimmerPhase = hash(entityId, 0x5A11E) & 0xFF;
        return Mth.clamp(alpha + Mth.sin((time + shimmerPhase) * SHIMMER_SPEED)
                * SHIMMER_ALPHA * fade, 0.0F, 0.8F);
    }

    /** Small deterministic mix (the skin-generator family) — stable per-entity phases. */
    private static int hash(int a, int b) {
        int h = (a * 0x27D4EB2D) ^ (b * 0x9E3779B9) ^ 0x0EC15C1E;
        h ^= h >>> 15;
        h *= 0x2C1B3C6D;
        h ^= h >>> 12;
        return h;
    }

    /**
     * {@link PlayerModel} with renderer-driven whole-model alpha (the GhostModel
     * technique) plus scene-ACTION pose access: SIT folds through the vanilla riding
     * pose, WAVE raises and sways the left arm.
     */
    @OnlyIn(Dist.CLIENT)
    public static final class EchoModel extends PlayerModel<EchoGhostEntity> {
        private float alpha = BODY_ALPHA;

        EchoModel(ModelPart root) {
            super(root, false); // WIDE arms — matches the generated skin layout
        }

        @Override
        public void setupAnim(EchoGhostEntity entity, float limbSwing, float limbSwingAmount,
                float ageInTicks, float netHeadYaw, float headPitch) {
            this.riding = entity.echoAction() == EchoActor.ACTION_SIT;
            super.setupAnim(entity, limbSwing, limbSwingAmount, ageInTicks, netHeadYaw, headPitch);
            if (entity.echoAction() == EchoActor.ACTION_WAVE) {
                // Raised left arm with a gentle wave sway (a greeting, not a flail).
                this.leftArm.xRot = (float) Math.PI * 0.95F;
                this.leftArm.zRot = 0.35F + Mth.sin(ageInTicks * 0.35F) * 0.25F;
                this.leftSleeve.copyFrom(this.leftArm);
                // MC4: the head leans gently toward the raised arm, counter-phased to
                // the sway — a greeting with warmth, not a mannequin with a flag.
                this.head.zRot = 0.06F + Mth.sin(ageInTicks * 0.35F + (float) Math.PI) * 0.04F;
            } else {
                // Vanilla never writes head.zRot — reset absolutely (shared model
                // instance; a stale wave tilt would leak onto every other echo).
                this.head.zRot = 0.0F;
            }
            this.hat.copyFrom(this.head); // re-sync: super copied before the tilt
        }

        @Override
        public void renderToBuffer(PoseStack poseStack, VertexConsumer buffer, int packedLight,
                int packedOverlay, int color) {
            super.renderToBuffer(poseStack, buffer, packedLight, packedOverlay,
                    FastColor.ARGB32.multiply(color,
                            FastColor.ARGB32.colorFromFloat(this.alpha, 1.0F, 1.0F, 1.0F)));
        }
    }

    /**
     * Moonlit silhouette pass (plan §4.3): the posed model re-rendered over
     * {@code echo_ghost_glow.png} with {@code RenderType.eyes} at a faint base
     * alpha (+ a little during floods) — fullbright THROUGH the body translucency,
     * so echoes stay readable at night without a horror heart. No-ops forever if
     * the glow texture is missing (one shared warning).
     */
    @OnlyIn(Dist.CLIENT)
    static final class MoonGlowLayer extends RenderLayer<EchoGhostEntity, EchoModel> {
        static final ResourceLocation GLOW_TEXTURE = ResourceLocation.fromNamespaceAndPath(
                EclipseMod.MOD_ID, "textures/entity/echo_ghost_glow.png");
        private static final RenderType GLOW_RENDER_TYPE = RenderType.eyes(GLOW_TEXTURE);
        /** Faint by design — a silhouette hint, not a lantern. */
        static final float GLOW_BASE = 0.10F;
        private static final float GLOW_FLOOD_BOOST = 0.12F;

        private static boolean checked;
        private static boolean present;

        MoonGlowLayer(EchoGhostRenderer parent) {
            super(parent);
        }

        static boolean glowTextureAvailable() {
            if (!checked) {
                present = Minecraft.getInstance().getResourceManager()
                        .getResource(GLOW_TEXTURE).isPresent();
                checked = true;
                if (!present) {
                    EclipseMod.LOGGER.warn("EchoGhostRenderer: {} missing — moon-glow pass disabled",
                            GLOW_TEXTURE);
                }
            }
            return present;
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
                EchoGhostEntity entity, float limbSwing, float limbSwingAmount, float partialTick,
                float ageInTicks, float netHeadYaw, float headPitch) {
            if (entity.isInvisible() || !glowTextureAvailable()) {
                return;
            }
            float fade = entity.echoFade() / (float) EchoActor.FADE_TICKS;
            float glowAlpha = (GLOW_BASE + GLOW_FLOOD_BOOST * entity.echoGlow()) * fade;
            if (glowAlpha <= 0.01F) {
                return;
            }
            EchoModel model = this.getParentModel();
            float bodyAlpha = model.alpha;
            model.alpha = glowAlpha;
            model.renderToBuffer(poseStack, bufferSource.getBuffer(GLOW_RENDER_TYPE),
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
            model.alpha = bodyAlpha;
        }
    }
}
