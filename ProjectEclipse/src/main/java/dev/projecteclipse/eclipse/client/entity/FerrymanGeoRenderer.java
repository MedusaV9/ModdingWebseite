package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.client.entity.geo.EclipseGeoRenderer;
import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.cache.object.BakedGeoModel;

/**
 * Ferryman renderer — GeckoLib conversion (MA4). The asset triple resolves off the id
 * {@code ferryman} (geo/animations/textures); head tracking targets the {@code head}
 * bone (the skull follows the hunted fighter). On the frozen {@link EclipseGeoRenderer}
 * base this opts into:
 *
 * <ul>
 *   <li>{@code withGlowmask()} — the painter's {@code ferryman_glowmask.png}: eye slit,
 *       soul flame, lantern glass shine-through, socket embers, robe sheen.</li>
 *   <li>{@code withUprightDeath()} — the scripted 100t collapse ({@code tickDeath} +
 *       the held {@code death} sheet) replaces the vanilla sideways tip-over.</li>
 *   <li>{@code withTranslucency()} — the {@code glow_gaze} soul-shell is painted at
 *       alpha&lt;255 (cutout would render it opaque).</li>
 * </ul>
 *
 * <p>Per-frame bone visibility (server-synced state → glow bones):</p>
 * <ul>
 *   <li>{@code glow_gaze} — the translucent soul-shell around the lantern shows ONLY
 *       while the P3 Lantern Gaze is marking a player ({@code isGazing()}).</li>
 *   <li>{@code glow_flame} + {@code glow_robe} — follow
 *       {@link FerrymanEntity#isLanternFlameLit()}: the death collapse gutters the flame
 *       with a 4t sputter over the first 30t, and the robe's cast sheen dies with its
 *       light source.</li>
 * </ul>
 *
 * <p>Registration lives in {@link FerrymanRenderers} (own subscriber, NOT in the shared
 * {@code EclipseEntityRenderers} — census §5 G2).</p>
 */
@OnlyIn(Dist.CLIENT)
public class FerrymanGeoRenderer extends EclipseGeoRenderer<FerrymanEntity> {
    public FerrymanGeoRenderer(EntityRendererProvider.Context context) {
        super(context, "ferryman", true);
        withGlowmask();
        withUprightDeath();
        withTranslucency();
        this.shadowRadius = 0.9F; // Old FerrymanRenderer footprint.
    }

    @Override
    public void preRender(PoseStack poseStack, FerrymanEntity entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        if (isReRender) {
            return;
        }
        // Gaze shell: only while the P3 mark hunts someone (fires alongside the target's
        // private vignette — the lantern visibly "opens" toward the marked player).
        getGeoModel().getBone("glow_gaze")
                .ifPresent(gaze -> gaze.setHidden(!entity.isGazing()));
        // Death gutter: the flame sputters (4t on/off) through the first 30t of the
        // collapse and then dies; the robe's cast sheen is the same light, so it dies too.
        boolean flameLit = entity.isLanternFlameLit();
        getGeoModel().getBone("glow_flame").ifPresent(flame -> flame.setHidden(!flameLit));
        getGeoModel().getBone("glow_robe").ifPresent(sheen -> sheen.setHidden(!flameLit));
    }
}
