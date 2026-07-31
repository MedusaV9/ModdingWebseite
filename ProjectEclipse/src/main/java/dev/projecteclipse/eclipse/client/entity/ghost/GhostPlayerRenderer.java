package dev.projecteclipse.eclipse.client.entity.ghost;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.entity.player.EclipsedPlayerGlowLayer;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
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
 *
 * <p><strong>WB-GHOSTFX refinements:</strong> a second, much slower vertical drift sine
 * (~15 s period) under the bob plus a faint idle alpha shimmer (±{@value #SHIMMER_ALPHA})
 * make the figure read as suspended rather than parked; and {@link HeartGlowLayer}
 * re-renders the model over {@code eclipsed_player_glow.png} with {@code RenderType.eyes}
 * so the purple heart (plus dim veins/eyes) stays fullbright THROUGH the 40% body
 * translucency — the ghost is unmistakably a ghost <em>of the uniform skin</em>, readable
 * at night. Both are allocation-free and deterministic per entity id.</p>
 *
 * <p><strong>MC4 reveal polish (F-098):</strong> the reveal glitch now runs on a
 * smoothstep ease-in/out envelope ({@link #revealEnvelope}) — alpha flicker, jitter duty
 * cycle/amplitude and the heart flare all ramp with it instead of snapping at the window
 * edges; full-name re-scramble pops decay as the name resolves; and a short client-side
 * materialize fade-in covers both spawning and walking into tracking range.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class GhostPlayerRenderer extends LivingEntityRenderer<LivingEntity, GhostPlayerRenderer.GhostModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/eclipsed_player.png");

    /** ~40% body alpha per the design sheet (plan §2.7 quotes ~0.45 — both approximate). */
    private static final float BASE_ALPHA = 0.40F;
    /** Baseline hover: +2px in model units. */
    private static final float HOVER_BLOCKS = 2.0F / 16.0F;
    /** Slow whole-body drift under the bob: ±0.05 blocks over a ~15 s sine. */
    private static final float DRIFT_BLOCKS = 0.05F;
    private static final float DRIFT_SPEED = 0.021F;
    /** Idle body-alpha shimmer amplitude (0.40 ± 0.04 — night readability preserved). */
    private static final float SHIMMER_ALPHA = 0.04F;
    private static final float SHIMMER_SPEED = 0.09F;
    /**
     * MC4 reveal polish: the glitch treatment eases in/out over this fraction of the
     * reveal window (smoothstepped, {@link #revealEnvelope}) instead of snapping between
     * calm-idle and full-flicker at the window edges.
     */
    private static final float REVEAL_EASE_FRACTION = 0.12F;
    /**
     * Client-side materialize fade (ticks over the entity's client {@code tickCount}) —
     * softens BOTH the spawn moment and walking into tracking range; without it the
     * spectre pops in at full 40%.
     */
    private static final float MATERIALIZE_TICKS = 12.0F;
    private static final int NAME_RESOLVED_COLOR = 0xE7D6FF;
    private static final int NAME_SCRAMBLE_COLOR = 0x8367A8;

    public GhostPlayerRenderer(EntityRendererProvider.Context context) {
        // Shadow radius 0: a translucent spectre casting a hard blob shadow reads wrong.
        super(context, new GhostModel(context.bakeLayer(ModelLayers.PLAYER)), 0.0F);
        // Heart glow through the translucency (same glow texture the living skin uses).
        this.addLayer(new HeartGlowLayer(this));
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
        // Ease-in/out envelope of the reveal glitch (0 = calm idle, 1 = full glitch).
        float envelope = reveal != null ? revealEnvelope(reveal.progress(now)) : 0.0F;
        // Bob (fast, small) layered over a much slower whole-body drift (WB-GHOSTFX);
        // phases hashed per entity so two ghosts never float in lockstep.
        float driftPhase = hash(entity.getId(), 0xD21F7) & 0xFF;
        float bob = HOVER_BLOCKS + Mth.sin(time * 0.05F) * 0.035F
                + Mth.sin((time + driftPhase) * DRIFT_SPEED) * DRIFT_BLOCKS;

        // Whole-model micro-jitter: a new deterministic offset every 3-tick window,
        // active ~19% of windows normally; the reveal envelope ramps BOTH the window
        // duty cycle (up to every window) and the amplitude — no binary snap.
        float jitterX = 0.0F;
        float jitterZ = 0.0F;
        int window = hash(entity.getId(), entity.tickCount / 3);
        if ((window & 15) < 3 + Math.round(envelope * 13.0F)) {
            float amplitude = Mth.lerp(envelope, 0.02F, 0.045F);
            jitterX = ((window >> 8 & 7) - 3.5F) / 3.5F * amplitude;
            jitterZ = ((window >> 16 & 7) - 3.5F) / 3.5F * amplitude;
        }

        this.model.alpha = computeAlpha(entity.getId(), envelope, now, time,
                EclipseClientConfig.reducedFx());

        poseStack.pushPose();
        poseStack.translate(jitterX, bob, jitterZ);
        super.render(entity, entityYaw, partialTick, poseStack, bufferSource, packedLight);
        poseStack.popPose();

        if (reveal != null) {
            this.renderNameTag(entity, buildRevealName(reveal, entity.getId(), now),
                    poseStack, bufferSource, packedLight, partialTick);
        }
    }

    /**
     * The reveal-glitch envelope: smoothstep from 0 → 1 over the first
     * {@value #REVEAL_EASE_FRACTION} of the window and back down over the last — the
     * ghost slides INTO the glitch and settles back OUT of it instead of snapping.
     * Package-visible for the MC4 offline harness (report §5).
     */
    static float revealEnvelope(float progress) {
        float edge = Math.min(Mth.clamp(progress / REVEAL_EASE_FRACTION, 0.0F, 1.0F),
                Mth.clamp((1.0F - progress) / REVEAL_EASE_FRACTION, 0.0F, 1.0F));
        return edge * edge * (3.0F - 2.0F * edge);
    }

    /**
     * Idle: ~40% with a slow ±{@value #SHIMMER_ALPHA} sine shimmer (calm under
     * {@code reducedFx}); the reveal blends toward a 100 ms-bucket flicker between ~0.2
     * and ~0.62 by the envelope. A {@value #MATERIALIZE_TICKS}-tick fade-in over the
     * client tickCount softens spawn/tracking-range pops. Package-visible + primitive
     * args for the MC4 offline harness.
     */
    static float computeAlpha(int entityId, float envelope, long nowMillis, float time,
            boolean reducedFx) {
        float idle = BASE_ALPHA;
        if (!reducedFx) {
            float shimmerPhase = hash(entityId, 0x5A11E) & 0xFF;
            idle += Mth.sin((time + shimmerPhase) * SHIMMER_SPEED) * SHIMMER_ALPHA;
        }
        float alpha = idle;
        if (envelope > 0.0F) {
            int bucket = hash(entityId, (int) (nowMillis / 100L));
            float flicker = Mth.clamp(
                    BASE_ALPHA + ((bucket & 0xFF) / 255.0F - 0.5F) * 0.45F, 0.18F, 0.65F);
            alpha = Mth.lerp(envelope, idle, flicker);
        }
        return alpha * Math.min(1.0F, time / MATERIALIZE_TICKS);
    }

    /**
     * The glitch reveal text: scrambled → resolves left-to-right across the middle 60% of
     * the window → holds the plain owner name; full re-scramble "pops" start at ~16% of
     * 150 ms buckets and DECAY with the resolve progress (down to none once resolved) —
     * the name fights its way out. GlitchText already re-rolls its glyphs every 3 ticks
     * and self-calms under reducedFx.
     */
    private static Component buildRevealName(GhostRenderers.Reveal reveal, int entityId, long nowMillis) {
        String ownerName = reveal.ownerName();
        int length = ownerName.length();
        float progress = reveal.progress(nowMillis);

        float resolveT = Mth.clamp((progress - 0.2F) / 0.6F, 0.0F, 1.0F);
        int resolved = Math.round(resolveT * length);
        int rescrambleChance = Mth.ceil(5.0F * (1.0F - resolveT));
        if (rescrambleChance > 0 && (hash(entityId, (int) (nowMillis / 150L)) & 31) < rescrambleChance) {
            resolved = 0; // brief full re-scramble flicker (thins out as the name resolves)
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

    /**
     * Heart-through-the-mist pass (WB-GHOSTFX): re-renders the posed ghost model over the
     * skin family's shared glow texture ({@code eclipsed_player_glow.png} — heart, dim
     * veins, eyes; transparent elsewhere) with {@code RenderType.eyes} at fullbright, so
     * the purple heart stays visible through the 40% body translucency at any light level.
     * Breathes {@value #GLOW_MIN}–{@value #GLOW_MAX} on the same ~2 s heartbeat as the
     * living skin ({@link EclipsedPlayerGlowLayer#heartbeatAlpha}); steady mid-value under
     * {@code reducedFx}. While a name reveal runs, the heart FLARES toward
     * {@value #GLOW_REVEAL} on the reveal envelope (the identity leaking out burns), and
     * the materialize fade-in from the body pass applies here too (no fullbright heart on
     * a not-yet-faded-in body). Skips invisible entities (mirrors the body pass) and
     * no-ops forever if the glow texture is missing (one shared warning). Allocation-free.
     */
    @OnlyIn(Dist.CLIENT)
    static final class HeartGlowLayer extends RenderLayer<LivingEntity, GhostModel> {
        private static final RenderType GLOW_RENDER_TYPE =
                RenderType.eyes(EclipsedPlayerGlowLayer.GLOW_TEXTURE);
        /** Dimmer than the living skin's 0.75–1.0 pulse — spectral, but night-readable. */
        private static final float GLOW_MIN = 0.60F;
        private static final float GLOW_MAX = 0.82F;
        /** Reveal flare ceiling — near-living intensity while the name is leaking. */
        private static final float GLOW_REVEAL = 0.95F;

        HeartGlowLayer(GhostPlayerRenderer parent) {
            super(parent);
        }

        @Override
        public void render(PoseStack poseStack, MultiBufferSource bufferSource, int packedLight,
                LivingEntity entity, float limbSwing, float limbSwingAmount, float partialTick,
                float ageInTicks, float netHeadYaw, float headPitch) {
            if (entity.isInvisible() || !EclipsedPlayerGlowLayer.glowTextureAvailable()) {
                return;
            }
            float glowAlpha = EclipseClientConfig.reducedFx()
                    ? (GLOW_MIN + GLOW_MAX) * 0.5F
                    : EclipsedPlayerGlowLayer.heartbeatAlpha(entity.getId(),
                            entity.tickCount + partialTick, GLOW_MIN, GLOW_MAX);
            GhostRenderers.Reveal reveal = GhostRenderers.activeReveal(entity.getId());
            if (reveal != null) {
                glowAlpha = Mth.lerp(revealEnvelope(reveal.progress(Util.getMillis())),
                        glowAlpha, GLOW_REVEAL);
            }
            glowAlpha *= Math.min(1.0F, (entity.tickCount + partialTick) / MATERIALIZE_TICKS);
            GhostModel model = this.getParentModel();
            float bodyAlpha = model.alpha;
            model.alpha = glowAlpha;
            model.renderToBuffer(poseStack, bufferSource.getBuffer(GLOW_RENDER_TYPE),
                    LightTexture.FULL_BRIGHT, OverlayTexture.NO_OVERLAY);
            model.alpha = bodyAlpha;
        }
    }
}
