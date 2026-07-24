package dev.projecteclipse.eclipse.client.entity.fogboss;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import org.joml.Matrix4f;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.entity.boss.fog.FogTyrantEntity;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.renderer.GeoRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;
import software.bernie.geckolib.renderer.layer.GeoRenderLayer;
import software.bernie.geckolib.util.Color;

/**
 * Fog Tyrant renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4): defaulted
 * asset triple for {@code fog_tyrant} (the 128×128 canvas), head tracking ON (the hooded
 * monarch stares its mark down between volleys), the {@code _glowmask.png} emissive layer
 * for the floating shard-crown + eye slit + storm-core chest cavity + lance edges, and
 * upright death for the scripted {@link FogTyrantEntity#DEATH_DURATION_TICKS}-tick
 * collapse — the crown-falls-first finale reads wrong if vanilla tips the monarch
 * sideways underneath it.
 *
 * <p>W4 IDEA-16 flourish (the synced-but-unused {@code DATA_ENRAGE_STACKS} find): the
 * glowmask layer gains a pulsing overdrive pass whose brightness and tempo climb with the
 * enrage stacks, and faint additive speed lines rise around the monarch — the P2+ cooldown
 * creep is now readable at a glance. Purely visual; both degrade under
 * {@link EclipseClientConfig#reducedFx()} and stand down for the death collapse.</p>
 */
@OnlyIn(Dist.CLIENT)
public class FogTyrantRenderer extends EclipseGeoRenderer<FogTyrantEntity> {
    public FogTyrantRenderer(EntityRendererProvider.Context context) {
        super(context, FogTyrantEntity.GEO_ID, true);
        // Crown shards, eye slit, chest core, lance edges — plus the enrage overdrive pass.
        addRenderLayer(new EnrageGlowLayer(this));
        addRenderLayer(new EnrageSpeedLines(this));
        withUprightDeath();  // Scripted crown-fall collapse; no vanilla tip-over.
        this.shadowRadius = 1.1F;
    }

    /**
     * The stock glowmask pass plus, while enraged, a second translucent-emissive re-render
     * whose alpha pulses harder and faster per stack — the crown and storm-core visibly
     * overcharge as the cooldowns tighten. Under {@code reducedFx} the pulse flattens to a
     * steady mid-intensity lift (no strobing).
     */
    @OnlyIn(Dist.CLIENT)
    static final class EnrageGlowLayer extends AutoGlowingGeoLayer<FogTyrantEntity> {
        /** Sky-15/block-0, the same packed light the stock glowmask pass re-renders with. */
        private static final int EMISSIVE_PACKED_LIGHT = 0xF00000;

        EnrageGlowLayer(GeoRenderer<FogTyrantEntity> renderer) {
            super(renderer);
        }

        @Override
        public void render(PoseStack poseStack, FogTyrantEntity animatable, BakedGeoModel bakedModel,
                RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
                float partialTick, int packedLight, int packedOverlay) {
            super.render(poseStack, animatable, bakedModel, renderType, bufferSource, buffer,
                    partialTick, packedLight, packedOverlay);
            int stacks = animatable.getEnrageStacks();
            if (stacks <= 0 || animatable.deathTime > 0) {
                return; // The death collapse owns the stage (core gutters out instead).
            }
            RenderType emissive = getRenderType(animatable, bufferSource);
            if (emissive == null) {
                return; // Invisible edge case — mirror the stock layer's bail.
            }
            float time = animatable.tickCount + partialTick;
            // Pulse quickens AND deepens per stack; reducedFx flattens it to a steady lift.
            float pulse = EclipseClientConfig.reducedFx() ? 0.5F
                    : 0.5F + 0.5F * Mth.sin(time * (0.16F + 0.05F * stacks));
            float alpha = (0.10F + 0.11F * stacks) * (0.35F + 0.65F * pulse);
            int colour = Color.ofARGB(alpha, 1.0F, 0.62F, 0.55F).argbInt(); // Hot overdrive tint.
            getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                    bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                    packedOverlay, colour);
        }
    }

    /**
     * Faint additive streaks rising around the monarch while enraged — count and alpha
     * scale with the stacks (2 lines per stack, ≤ {@value #MAX_ALPHA_STACKS} alpha steps).
     * Layers run OUTSIDE the body-yaw rotation in GeckoLib 4.9, so the aura is
     * world-aligned and doesn't spin with the model. Skipped entirely under
     * {@code reducedFx}, while dying, or while invisible.
     */
    @OnlyIn(Dist.CLIENT)
    static final class EnrageSpeedLines extends GeoRenderLayer<FogTyrantEntity> {
        private static final int MAX_ALPHA_STACKS = 5;
        /** Golden-angle spread keeps the streak columns from clumping. */
        private static final float GOLDEN_ANGLE = 2.39996F;
        private static final float BAND_BOTTOM = 0.4F;
        /** Hitbox is 4.2 tall; the band covers robe hem to crown. */
        private static final float BAND_HEIGHT = 3.2F;
        private static final float STREAK_LENGTH = 0.85F;
        private static final float HALF_WIDTH = 0.03F;

        EnrageSpeedLines(GeoRenderer<FogTyrantEntity> renderer) {
            super(renderer);
        }

        @Override
        public void render(PoseStack poseStack, FogTyrantEntity animatable, BakedGeoModel bakedModel,
                RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
                float partialTick, int packedLight, int packedOverlay) {
            int stacks = Math.min(animatable.getEnrageStacks(), MAX_ALPHA_STACKS);
            if (stacks <= 0 || animatable.deathTime > 0 || animatable.isInvisible()
                    || EclipseClientConfig.reducedFx()) {
                return;
            }
            float time = animatable.tickCount + partialTick;
            float baseAlpha = 0.05F + 0.022F * stacks; // "Faint" is the brief — ≤ ~0.16.
            VertexConsumer lines = bufferSource.getBuffer(RenderType.lightning());
            Matrix4f pose = poseStack.last().pose();
            int count = 2 * stacks + 2;
            for (int i = 0; i < count; i++) {
                // Deterministic per-index params (no per-streak state to track).
                float angle = i * GOLDEN_ANGLE + (animatable.getId() & 15) * 0.41F;
                float radius = 1.45F + 0.35F * fract(i * 0.618F);
                float speed = 0.028F + 0.018F * fract(i * 0.377F);
                float cycle = fract(time * speed + i * 0.173F);
                float x = radius * Mth.cos(angle);
                float z = radius * Mth.sin(angle);
                float y0 = BAND_BOTTOM + cycle * BAND_HEIGHT;
                float y1 = y0 + STREAK_LENGTH;
                // Tent fade so streaks materialize/dissolve at the band ends.
                float alpha = baseAlpha * Mth.clamp(Math.min(cycle, 1.0F - cycle) * 4.0F, 0.0F, 1.0F);
                if (alpha < 0.01F) {
                    continue;
                }
                streak(lines, pose, x, y0, y1, z, alpha);
            }
        }

        /** Two crossed thin quads (each double-sided) — visible from every camera angle. */
        private static void streak(VertexConsumer lines, Matrix4f pose, float x, float y0, float y1,
                float z, float alpha) {
            quad(lines, pose, x - HALF_WIDTH, y0, z, x + HALF_WIDTH, y0, z, alpha, y1 - y0);
            quad(lines, pose, x, y0, z - HALF_WIDTH, x, y0, z + HALF_WIDTH, alpha, y1 - y0);
        }

        /** One vertical quad between two base corners, emitted in both windings. */
        private static void quad(VertexConsumer lines, Matrix4f pose, float ax, float ay, float az,
                float bx, float by, float bz, float alpha, float height) {
            // Pale storm-cyan, additive (RenderType.lightning) so it stays a whisper.
            float r = 0.72F;
            float g = 0.84F;
            float b = 0.95F;
            lines.addVertex(pose, ax, ay, az).setColor(r, g, b, alpha);
            lines.addVertex(pose, bx, by, bz).setColor(r, g, b, alpha);
            lines.addVertex(pose, bx, by + height, bz).setColor(r, g, b, alpha);
            lines.addVertex(pose, ax, ay + height, az).setColor(r, g, b, alpha);
            // Reverse winding — the lightning render type culls back faces.
            lines.addVertex(pose, ax, ay + height, az).setColor(r, g, b, alpha);
            lines.addVertex(pose, bx, by + height, bz).setColor(r, g, b, alpha);
            lines.addVertex(pose, bx, by, bz).setColor(r, g, b, alpha);
            lines.addVertex(pose, ax, ay, az).setColor(r, g, b, alpha);
        }

        private static float fract(float value) {
            return value - Mth.floor(value);
        }
    }
}
