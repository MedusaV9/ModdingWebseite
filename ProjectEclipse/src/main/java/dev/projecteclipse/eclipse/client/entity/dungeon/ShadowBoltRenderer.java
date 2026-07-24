package dev.projecteclipse.eclipse.client.entity.dungeon;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.dungeon.ShadowBoltProjectile;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.model.DefaultedEntityGeoModel;
import software.bernie.geckolib.renderer.GeoEntityRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * Shadow Bolt renderer — a tiny GeckoLib spike-orb ({@code shadow_bolt.geo.json} spinning
 * on its {@code idle} loop) instead of an item sprite: the task's no-custom-items rule
 * rules out the Herald shard's {@code ThrownItemRenderer} pattern. Extends
 * {@link GeoEntityRenderer} directly (not {@code EclipseGeoRenderer}, whose bound is
 * {@code LivingEntity} — a projectile isn't one) with the same defaulted asset triple.
 * Fullbright + glowmask core: a shadow bolt must read in a pitch-black vault corridor.
 */
@OnlyIn(Dist.CLIENT)
public class ShadowBoltRenderer extends GeoEntityRenderer<ShadowBoltProjectile> {
    public ShadowBoltRenderer(EntityRendererProvider.Context context) {
        super(context, new DefaultedEntityGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, ShadowBoltProjectile.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
        this.shadowRadius = 0.0F;
    }

    @Override
    protected int getBlockLightLevel(ShadowBoltProjectile entity, BlockPos pos) {
        return 15; // Fullbright: glowing ember even in an unlit dungeon (fireball pattern).
    }
}
