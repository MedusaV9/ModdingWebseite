package dev.projecteclipse.eclipse.client.entity.herald;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
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
 * Herald GeckoLib renderer (MA3 conversion): defaulted asset triple for
 * {@code herald} (128x128 canvas), head tracking ON (the godhead's {@code head} bone —
 * horns, eye and vein plates ride along — follows the gaze/volley focus), the
 * {@code _glowmask.png} layer (the Herald's first: gold core fissures, eye, floating
 * veins, horn/crown tips, shield crests, shard tips, halo) and upright death for the
 * scripted {@link HeraldEntity#DEATH_DURATION_TICKS}-tick collapse — the held
 * {@code death} anim poses the wreck, vanilla's sideways flip would fight it.
 *
 * <p>Fight-state hooks, both driven by synced entity data (renderer-side only, the
 * hitbox never changes):</p>
 * <ul>
 *   <li><b>Shard detach</b> ({@link HeraldEntity#getShardsLeft}): P3 tears the corona
 *       shards off one by one (and the death collapse sheds the rest) — bones
 *       {@code shard1..8} are hidden once their slot detaches, exactly like the old
 *       model's {@code visible} flags.</li>
 *   <li><b>Telegraph surge</b> ({@link HeraldEntity#isTelegraphing}): while a volley
 *       winds up the whole glowmask throbs (the shard tips are painted dim at rest so
 *       the surge reads); through the death collapse the glow instead gutters out — the
 *       light leaves the godhead as the wreck settles.</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
public class HeraldGeoRenderer extends EclipseGeoRenderer<HeraldEntity> {
    public HeraldGeoRenderer(EntityRendererProvider.Context context) {
        super(context, HeraldEntity.GEO_ID, true);
        addRenderLayer(new TelegraphGlowLayer(this));
        withUprightDeath();
        this.shadowRadius = 1.1F; // Parity with the old MobRenderer registration.
    }

    /**
     * Synced shard-detach visibility. Runs every frame (bones are shared per-model
     * state, and another Herald — or a re-render pass — may have set them differently),
     * matching the Deckhand oar-hide pattern.
     */
    @Override
    public void preRender(PoseStack poseStack, HeraldEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        int shardsLeft = entity.getShardsLeft();
        for (int i = 1; i <= HeraldEntity.CORONA_SHARDS; i++) {
            boolean hidden = i > shardsLeft;
            getGeoModel().getBone("shard" + i).ifPresent(bone -> bone.setHidden(hidden));
        }
    }

    /**
     * The stock glowmask pass with two fight-state colour envelopes: a fast throb while
     * a volley telegraph winds up ("the shards glow", spec §2.1 — flattened to a steady
     * three-quarter burn under {@code reducedFx}, no strobing), and a gutter-out fade
     * across the scripted death collapse. Steady full-bright otherwise.
     */
    @OnlyIn(Dist.CLIENT)
    static final class TelegraphGlowLayer extends AutoGlowingGeoLayer<HeraldEntity> {
        /** Sky-15/block-0, the same packed light the stock glowmask pass re-renders with. */
        private static final int EMISSIVE_PACKED_LIGHT = 0xF00000;

        TelegraphGlowLayer(GeoRenderer<HeraldEntity> renderer) {
            super(renderer);
        }

        @Override
        public void render(PoseStack poseStack, HeraldEntity animatable, BakedGeoModel bakedModel,
                RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
                float partialTick, int packedLight, int packedOverlay) {
            boolean dying = animatable.deathTime > 0;
            if (!dying && !animatable.isTelegraphing()) {
                super.render(poseStack, animatable, bakedModel, renderType, bufferSource, buffer,
                        partialTick, packedLight, packedOverlay);
                return;
            }
            RenderType emissive = getRenderType(animatable, bufferSource);
            if (emissive == null) {
                return; // Invisible edge case — mirror the stock layer's bail.
            }
            float brightness;
            if (dying) {
                // The light leaves the wreck across the 70t collapse (floor 0.1 so the
                // last frame still has embers under the shatter FX).
                float fade = (animatable.deathTime + partialTick) / HeraldEntity.DEATH_DURATION_TICKS;
                brightness = Math.max(0.1F, 1.0F - fade * 0.9F);
            } else if (EclipseClientConfig.reducedFx()) {
                brightness = 0.75F; // Steady surge, no strobing.
            } else {
                float time = animatable.tickCount + partialTick;
                brightness = 0.7F + 0.3F * Mth.sin(time * 0.9F); // ~3.5Hz throb.
            }
            int colour = Color.ofARGB(1.0F, brightness, brightness, brightness).argbInt();
            getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                    bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                    packedOverlay, colour);
        }
    }
}
