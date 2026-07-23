package dev.projecteclipse.eclipse.client.entity.ghost;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import net.minecraft.Util;
import net.minecraft.client.model.PlayerModel;
import net.minecraft.client.model.geom.ModelLayers;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.LivingEntityRenderer;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.MutableComponent;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FastColor;
import net.minecraft.util.Mth;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Logout-ghost renderer (plans_v3 P6 §2.7 / P4 §2.12): the vanilla player model (baked from
 * {@code ModelLayers.PLAYER}, WIDE — matching the forced uniform skin) wearing the v2
 * eclipsed skin, drawn with {@code RenderType.entityTranslucent} at ~40% alpha, hovering
 * +2px with a slow bob and twitching a sub-pixel "vertex jitter" every few ticks. No
 * shadow, no vanilla nameplate.
 *
 * <p><strong>Name reveal:</strong> while a {@code S2CGhostRevealPayload} window is active
 * for this ghost ({@link GhostRenderers#activeReveal(int)}), a glitchy nametag renders
 * above the head: fully scrambled at first ({@code GlitchText}, P3 file — read-only use),
 * resolving left-to-right into the owner name, with brief re-scramble flickers and a body
 * alpha flicker. P2 layers particle FX on top separately (§4.2).</p>
 *
 * <p>Typed against {@link LivingEntity} on purpose: the concrete {@code LogoutGhostEntity}
 * class is P4-B9's and may not exist at this worker's compile time — the frozen contract
 * (humanoid-sized LivingEntity) is all this renderer needs. Registered by lookup in
 * {@link GhostRenderers}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class GhostPlayerRenderer extends LivingEntityRenderer<LivingEntity, GhostPlayerRenderer.GhostModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/eclipsed_player.png");

    /** ~40% body alpha per the design sheet (plan §2.7 quotes ~0.45 — both approximate). */
    private static final float BASE_ALPHA = 0.40F;
    /** Baseline hover: +2px in model units. */
    private static final float HOVER_BLOCKS = 2.0F / 16.0F;
    private static final int NAME_RESOLVED_COLOR = 0xE7D6FF;
    private static final int NAME_SCRAMBLE_COLOR = 0x8367A8;

    public GhostPlayerRenderer(EntityRendererProvider.Context context) {
        // Shadow radius 0: a translucent spectre casting a hard blob shadow reads wrong.
        super(context, new GhostModel(context.bakeLayer(ModelLayers.PLAYER)), 0.0F);
    }

    @Override
    public ResourceLocation getTextureLocation(LivingEntity entity) {
        return TEXTURE;
    }

    /** Always the translucent pass (never the opaque skin pipeline); honors true invisibility. */
    @Override
    protected RenderType getRenderType(LivingEntity entity, boolean bodyVisible, boolean translucent,
            boolean glowing) {
        return entity.isInvisible() ? null : RenderType.entityTranslucent(TEXTURE);
    }

    /** Vanilla nameplate suppressed — the reveal tag below is the only name that ever shows. */
    @Override
    protected boolean shouldShowName(LivingEntity entity) {
        return false;
    }

    @Override
    public void render(LivingEntity entity, float entityYaw, float partialTick, PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight) {
        GhostRenderers.Reveal reveal = GhostRenderers.activeReveal(entity.getId());
        long now = Util.getMillis();

        float time = entity.tickCount + partialTick;
        float bob = HOVER_BLOCKS + Mth.sin(time * 0.05F) * 0.035F;

        // Whole-model micro-jitter: a new deterministic offset every 3-tick window, active
        // ~19% of windows normally and every window while the reveal glitch is running.
        float jitterX = 0.0F;
        float jitterZ = 0.0F;
        int window = hash(entity.getId(), entity.tickCount / 3);
        if (reveal != null || (window & 15) < 3) {
            float amplitude = reveal != null ? 0.045F : 0.02F;
            jitterX = ((window >> 8 & 7) - 3.5F) / 3.5F * amplitude;
            jitterZ = ((window >> 16 & 7) - 3.5F) / 3.5F * amplitude;
        }

        this.model.alpha = computeAlpha(entity.getId(), reveal, now);

        poseStack.pushPose();
        poseStack.translate(jitterX, bob, jitterZ);
        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
        poseStack.popPose();

        if (reveal != null) {
            this.renderNameTag(entity, buildRevealName(reveal, entity.getId(), now),
                    poseStack, bufferSource, packedLight, partialTick);
        }
    }

    /** Steady ~40%; while revealing, a 100 ms-bucket flicker between ~0.2 and ~0.62. */
    private static float computeAlpha(int entityId, GhostRenderers.Reveal reveal, long nowMillis) {
        if (reveal == null) {
            return BASE_ALPHA;
        }
        int bucket = hash(entityId, (int) (nowMillis / 100L));
        return Mth.clamp(BASE_ALPHA + ((bucket & 0xFF) / 255.0F - 0.5F) * 0.45F, 0.18F, 0.65F);
    }

    /**
     * The glitch reveal text: scrambled → resolves left-to-right across the middle 60% of
     * the window → holds the plain owner name; ~12% of 150 ms buckets re-scramble fully
     * while unresolved (the datamosh "pop"). GlitchText already re-rolls its glyphs every
     * 3 ticks and self-calms under reducedFx.
     */
    private static Component buildRevealName(GhostRenderers.Reveal reveal, int entityId, long nowMillis) {
        String ownerName = reveal.ownerName();
        int length = ownerName.length();
        float progress = reveal.progress(nowMillis);

        float resolveT = Mth.clamp((progress - 0.2F) / 0.6F, 0.0F, 1.0F);
        int resolved = Math.round(resolveT * length);
        if (progress < 0.85F && (hash(entityId, (int) (nowMillis / 150L)) & 31) < 4) {
            resolved = 0; // brief full re-scramble flicker
        }

        MutableComponent name = Component.literal(ownerName.substring(0, resolved))
                .withColor(NAME_RESOLVED_COLOR);
        if (resolved < length) {
            name.append(Component.literal(GlitchText.scramble(length - resolved, entityId))
                    .withColor(NAME_SCRAMBLE_COLOR));
        }
        return name;
    }

    /** Small deterministic mix (skin-generator family) — stable jitter/flicker per entity. */
    private static int hash(int a, int b) {
        int h = (a * 0x27D4EB2D) ^ (b * 0x9E3779B9) ^ 0x0EC15C1E;
        h ^= h >>> 15;
        h *= 0x2C1B3C6D;
        h ^= h >>> 12;
        return h;
    }

    /** {@link PlayerModel} with a renderer-driven whole-model alpha (translucent ghost pass). */
    @OnlyIn(Dist.CLIENT)
    public static final class GhostModel extends PlayerModel<LivingEntity> {
        private float alpha = BASE_ALPHA;

        GhostModel(ModelPart root) {
            super(root, false); // WIDE arms — matches the forced uniform skin layout
        }

        @Override
        public void renderToBuffer(PoseStack poseStack, VertexConsumer buffer, int packedLight,
                int packedOverlay, int color) {
            super.renderToBuffer(poseStack, buffer, packedLight, packedOverlay,
                    FastColor.ARGB32.multiply(color, FastColor.ARGB32.colorFromFloat(this.alpha, 1.0F, 1.0F, 1.0F)));
        }
    }
}
