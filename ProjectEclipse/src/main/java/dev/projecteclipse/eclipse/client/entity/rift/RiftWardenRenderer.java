package dev.projecteclipse.eclipse.client.entity.rift;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.math.Axis;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.entity.boss.rift.RiftWardenEntity;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.renderer.GeoRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;
import software.bernie.geckolib.util.Color;

/**
 * Rift Warden renderer ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.4): defaulted
 * asset triple for {@code rift_warden} (the 128×128 canvas), head tracking ON (the horned
 * helm follows its mark between attacks), the {@code _glowmask.png} layer for the boiling
 * void-tear half + blade edges + helm slit, and upright death for the scripted
 * {@link RiftWardenEntity#DEATH_DURATION_TICKS}-tick implosion — the rift swallowing the
 * body reads wrong if vanilla tips the knight sideways first.
 *
 * <p>W4 IDEA-16 flourish (the synced-but-unused {@code DATA_STAGGERED} find): while the
 * post-volley weakpoint window is open the void-tear glow gutters (irregular flicker) and
 * the knight visibly slumps — sink + forward sag with a slow sway — so the punish opening
 * reads without a single UI element. Renderer-side only (the hitbox never moves), eased by
 * {@link RiftWardenEntity#staggerSlump} and calmed under
 * {@link EclipseClientConfig#reducedFx()}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class RiftWardenRenderer extends EclipseGeoRenderer<RiftWardenEntity> {
    /** Max slump lean, degrees (scaled by the eased 0..1 slump amount). */
    private static final float SLUMP_LEAN_DEG = 8.0F;
    /** Max slump sink, blocks. */
    private static final float SLUMP_SINK = 0.10F;

    public RiftWardenRenderer(EntityRendererProvider.Context context) {
        super(context, RiftWardenEntity.GEO_ID, true);
        // Void-tear half, blade edges, helm slit — guttering while staggered.
        addRenderLayer(new StaggerGlowLayer(this));
        withUprightDeath();
        this.shadowRadius = 0.8F;
    }

    /**
     * Slumped weakpoint pose: sink + lean forward with a slow sway while staggered.
     * {@code applyRotations} re-runs identically inside the glow layer's re-render pass
     * (GeckoLib 4.9 {@code reRender} contract), so base and emissive passes stay aligned.
     */
    @Override
    protected void applyRotations(RiftWardenEntity animatable, PoseStack poseStack, float ageInTicks,
            float rotationYaw, float partialTick, float nativeScale) {
        super.applyRotations(animatable, poseStack, ageInTicks, rotationYaw, partialTick, nativeScale);
        float slump = animatable.staggerSlump(partialTick);
        if (slump <= 0.02F) {
            return;
        }
        poseStack.translate(0.0F, -SLUMP_SINK * slump, 0.0F);
        // Negative X pitch = lean toward the facing direction (vanilla swim/fall-fly sign).
        float sway = EclipseClientConfig.reducedFx() ? 0.0F : 1.5F * Mth.sin(ageInTicks * 0.35F);
        poseStack.mulPose(Axis.XP.rotationDegrees(-(SLUMP_LEAN_DEG + sway) * slump));
    }

    /**
     * The stock glowmask pass, except while the stagger slump is live the emissive colour
     * gutters — two incommensurate sines give an irregular candle-flutter, eased in/out by
     * the same slump amount as the pose. Under {@code reducedFx} the flicker flattens to a
     * steady dim (no strobing).
     */
    @OnlyIn(Dist.CLIENT)
    static final class StaggerGlowLayer extends AutoGlowingGeoLayer<RiftWardenEntity> {
        /** Sky-15/block-0, the same packed light the stock glowmask pass re-renders with. */
        private static final int EMISSIVE_PACKED_LIGHT = 0xF00000;

        StaggerGlowLayer(GeoRenderer<RiftWardenEntity> renderer) {
            super(renderer);
        }

        @Override
        public void render(PoseStack poseStack, RiftWardenEntity animatable, BakedGeoModel bakedModel,
                RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
                float partialTick, int packedLight, int packedOverlay) {
            float slump = animatable.staggerSlump(partialTick);
            if (slump <= 0.02F || animatable.deathTime > 0) {
                // Steady core (or the death implosion, which owns its own glow language).
                super.render(poseStack, animatable, bakedModel, renderType, bufferSource, buffer,
                        partialTick, packedLight, packedOverlay);
                return;
            }
            RenderType emissive = getRenderType(animatable, bufferSource);
            if (emissive == null) {
                return; // Invisible edge case — mirror the stock layer's bail.
            }
            float time = animatable.tickCount + partialTick;
            // Guttering candle: mostly lit, with irregular dips (never a clean strobe).
            float flick = 0.5F + 0.5F * Mth.sin(time * 1.1F) * Mth.sin(time * 2.63F + 1.7F);
            float brightness = EclipseClientConfig.reducedFx()
                    ? 1.0F - 0.35F * slump
                    : 1.0F - slump * (0.25F + 0.45F * flick);
            int colour = Color.ofARGB(1.0F, brightness, brightness, brightness).argbInt();
            getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                    bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                    packedOverlay, colour);
        }
    }
}
