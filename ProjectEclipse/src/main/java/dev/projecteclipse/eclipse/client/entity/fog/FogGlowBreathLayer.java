package dev.projecteclipse.eclipse.client.entity.fog;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.stormfx.StormInteriorFx;
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
 * WAVE5 (F-105 B) B4 — fog-mob glowmask "Atmung" (IDEA-15 §8): the emissive pass of the
 * fog family (Storm Hound, Fog Colossus, Fog Revenant) breathes with the storm around the
 * VIEWER — alpha ×{@code (0.6 + 0.8·interior)} off {@link StormInteriorFx#interiorAmount()}.
 * Outside a storm the glow sits at a dimmed 0.6 (embers seen in clear air); deep inside the
 * fog the factor reaches 1.4 — the base pass clamps at 1.0 and the excess re-renders as a
 * second translucent-emissive overdrive pass (the {@code FogTyrantRenderer.EnrageGlowLayer}
 * two-pass precedent), so the mobs visibly burn THROUGH the fog exactly where the fog is
 * thickest. Purely a client-side alpha multiplier: replaces the stock
 * {@code withGlowmask()} {@link AutoGlowingGeoLayer} 1:1, keeps the renderer's own
 * {@code getRenderColor} fades (death/invisibility) intact, and the overdrive pass stands
 * down under {@link EclipseClientConfig#reducedFx()} and during scripted deaths.
 */
@OnlyIn(Dist.CLIENT)
final class FogGlowBreathLayer<T extends LivingEntity & GeoEntity> extends AutoGlowingGeoLayer<T> {
    /** Sky-15/block-0 — the same packed light the stock glowmask pass re-renders with. */
    private static final int EMISSIVE_PACKED_LIGHT = 0xF00000;
    /** IDEA-15 §8 curve: {@code 0.6 + 0.8·interior} (0.6 in clear air → 1.4 deep in fog). */
    private static final float BREATH_BASE = 0.6F;
    private static final float BREATH_SPAN = 0.8F;

    FogGlowBreathLayer(GeoRenderer<T> renderer) {
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
        float breath = BREATH_BASE + BREATH_SPAN * StormInteriorFx.interiorAmount();
        // Base pass = the stock glowmask re-render with the alpha scaled (respecting the
        // renderer's own render color, so death/hurt fades keep working underneath).
        Color base = getRenderer().getRenderColor(animatable, partialTick, packedLight);
        int colour = Color.ofARGB(Math.min(1.0F, breath) * base.getAlphaFloat(),
                base.getRedFloat(), base.getGreenFloat(), base.getBlueFloat()).argbInt();
        getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                packedOverlay, colour);
        // Overdrive pass: only the >1.0 excess (≤0.4 deep inside). reducedFx keeps the
        // single stock-strength pass; scripted deaths own their own gutter-out.
        float excess = breath - 1.0F;
        if (excess > 0.01F && animatable.deathTime <= 0 && !EclipseClientConfig.reducedFx()) {
            int over = Color.ofARGB(excess * base.getAlphaFloat(), base.getRedFloat(),
                    base.getGreenFloat(), base.getBlueFloat()).argbInt();
            getRenderer().reRender(bakedModel, poseStack, bufferSource, animatable, emissive,
                    bufferSource.getBuffer(emissive), partialTick, EMISSIVE_PACKED_LIGHT,
                    packedOverlay, over);
        }
    }
}
