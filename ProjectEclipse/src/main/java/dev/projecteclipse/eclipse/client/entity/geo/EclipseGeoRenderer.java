package dev.projecteclipse.eclipse.client.entity.geo;

import javax.annotation.Nullable;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.LivingEntity;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.animatable.GeoEntity;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.model.DefaultedEntityGeoModel;
import software.bernie.geckolib.renderer.GeoEntityRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * FROZEN base renderer for every P6 GeckoLib mob ({@code docs/plans_v3/
 * P6_mobs_models_builds.md} §2.1). Wraps {@link DefaultedEntityGeoModel} on the
 * {@code eclipse} namespace, so one string id resolves the whole asset triple:
 * {@code geo/entity/<id>.geo.json} + {@code animations/entity/<id>.animation.json} +
 * {@code textures/entity/<id>.png} (verified 4.9.2 paths — the OLD-style layout, not the
 * GeckoLib-5 wiki's {@code geckolib/models}).
 *
 * <p>Opt-ins, chainable from the subclass constructor:</p>
 * <ul>
 *   <li>{@link #withGlowmask()} — adds {@link AutoGlowingGeoLayer}; ship a
 *       {@code textures/entity/<id>_glowmask.png} at the SAME canvas size (enforced),
 *       emissive pixels only, transparent elsewhere.</li>
 *   <li>{@link #withUprightDeath()} — zeroes the vanilla 20t death tip-over for scripted
 *       {@code death} animations (pair with a {@code tickDeath()} override).</li>
 *   <li>{@link #withTranslucency()} — renders with
 *       {@link RenderType#entityTranslucent} instead of the cutout default; REQUIRED
 *       whenever the albedo uses partial alpha (e.g. glass at 40%), which cutout would
 *       otherwise show fully opaque.</li>
 * </ul>
 *
 * <p>Pass {@code turnsHead = true} only if the geo has a bone named {@code head}
 * (GeckoLib's automatic head tracking targets exactly that bone).</p>
 */
@OnlyIn(Dist.CLIENT)
public class EclipseGeoRenderer<T extends LivingEntity & GeoEntity> extends GeoEntityRenderer<T> {
    private boolean uprightDeath;
    private boolean translucent;

    /** Non-head-tracking variant (most ambient mobs). */
    public EclipseGeoRenderer(EntityRendererProvider.Context context, String geoId) {
        this(context, geoId, false);
    }

    /** @param geoId entity path under {@code eclipse} (must equal the entity's geoId()) */
    public EclipseGeoRenderer(EntityRendererProvider.Context context, String geoId, boolean turnsHead) {
        super(context, new DefaultedEntityGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, geoId), turnsHead));
    }

    /** Adds the {@code _glowmask.png} emissive layer (eyes-style, fullbright). */
    public EclipseGeoRenderer<T> withGlowmask() {
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
        return this;
    }

    /** Suppresses the vanilla sideways death flip (for scripted upright collapses). */
    public EclipseGeoRenderer<T> withUprightDeath() {
        this.uprightDeath = true;
        return this;
    }

    /** Renders the model translucent (needed for partial-alpha albedo pixels). */
    public EclipseGeoRenderer<T> withTranslucency() {
        this.translucent = true;
        return this;
    }

    @Override
    protected float getDeathMaxRotation(T animatable) {
        return this.uprightDeath ? 0.0F : super.getDeathMaxRotation(animatable);
    }

    /**
     * Universal hit feedback (W4-FEEL, IDEA-02 #1): every Eclipse custom mob pops one
     * BURST-budgeted {@code eclipse:rift_spark} crackle on the first {@code hurtTime}
     * frame — {@link HurtSparks} dedupes per entity, so this per-frame call is cheap.
     * Subclasses overriding {@code preRender} keep the behavior via their
     * {@code super.preRender} call.
     */
    @Override
    public void preRender(PoseStack poseStack, T entity, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender, float partialTick,
            int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, entity, model, bufferSource, buffer, isReRender, partialTick,
                packedLight, packedOverlay, colour);
        if (!isReRender && entity.isAlive() && entity.hurtTime > 0) {
            HurtSparks.onHurtFrame(entity);
        }
    }

    @Override
    public RenderType getRenderType(T animatable, ResourceLocation texture,
            @Nullable MultiBufferSource bufferSource, float partialTick) {
        if (this.translucent) {
            return RenderType.entityTranslucent(texture);
        }
        return super.getRenderType(animatable, texture, bufferSource, partialTick);
    }
}
