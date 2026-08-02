package dev.projecteclipse.eclipse.client.entity.stalker;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.drama.NightDreadFx;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.animatable.GeoEntity;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.renderer.GeoRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;
import software.bernie.geckolib.util.Color;

/**
 * WAVE6 (F-106 A) A7 (stretch) — the Umbral Stalker's glowmask burns hotter on Umbral
 * Nights: emissive alpha ×(1 + {@value #UMBRAL_BOOST_EXCESS}) while
 * {@link NightDreadFx#isUmbral()} (the A1-synced client state). The base pass below is
 * byte-equivalent to the stock {@code withGlowmask()} {@link AutoGlowingGeoLayer}
 * re-render; because colour ints clamp at 1.0, the 0.6 excess re-renders as a second
 * translucent-emissive overdrive pass — the {@code FogGlowBreathLayer} /
 * {@code FogTyrantRenderer.EnrageGlowLayer} W5-B4 two-pass precedent. {@code reducedFx}
 * leaves the base look untouched (only the boost pass stands down), as do scripted
 * deaths (the collapse owns its own fade).
 *
 * <p>Probe {@code [w6a-stalkerglow] umbral=<b>} — one line per boost-state flip
 * (class-static dedup), the llvmpipe-friendly proof the boost pass is live.</p>
 */
@OnlyIn(Dist.CLIENT)
final class UmbralNightGlowLayer<T extends LivingEntity & GeoEntity> extends AutoGlowingGeoLayer<T> {
    /** Sky-15/block-0 — the same packed light the stock glowmask pass re-renders with. */
    private static final int EMISSIVE_PACKED_LIGHT = 0xF00000;
    /** Plan §3 A7: emissive ×1.6 total = base 1.0 + this overdrive excess. */
    private static final float UMBRAL_BOOST_EXCESS = 0.6F;

    /** {@code [w6a-stalkerglow]} probe dedup: last logged boost state (null = never). */
    private static Boolean lastLoggedBoost;

    UmbralNightGlowLayer(GeoRenderer<T> renderer) {
        super(renderer);
    }

    @Override
    public void render(PoseStack poseStack, T animatable, BakedGeoModel bakedModel,
            RenderType renderType, MultiBufferSource bufferSource, VertexConsumer buffer,
            float partialTick, int packedLight, int packedOverlay) {
        RenderType emissive = getRenderType(animatable, bufferSource);
        if (emissive == null) {
            return; // Invisible edge case — mirror the stock layer's bail.
        }
        boolean boosted = NightDreadFx.isUmbral() && !EclipseClientConfig.reducedFx()
                && animatable.deathTime <= 0;
        if (lastLoggedBoost == null || lastLoggedBoost != boosted) {
            EclipseMod.LOGGER.debug("[w6a-stalkerglow] umbral={}", boosted);
            lastLoggedBoost = boosted;
        }
        // Base pass = the stock glowmask re-render (respecting the renderer's own render
        // color, so death/hurt fades keep working underneath) — the reducedFx baseline.
        Color base = getRenderer().getRenderColor(animatable, partialTick, packedLight);
        getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                packedOverlay, base.argbInt());
        // Overdrive pass: only the excess the clamped colour ints cannot carry.
        if (boosted) {
            int over = Color.ofARGB(UMBRAL_BOOST_EXCESS * base.getAlphaFloat(),
                    base.getRedFloat(), base.getGreenFloat(), base.getBlueFloat()).argbInt();
            getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                    bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                    packedOverlay, over);
        }
    }
}
