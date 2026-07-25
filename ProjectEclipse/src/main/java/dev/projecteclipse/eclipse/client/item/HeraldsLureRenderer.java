package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.HeraldsLureItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the Herald's Lure (registered through
 * {@code ItemsBClientExtensions}; item model {@code models/item/heralds_lure.json} is
 * {@code builtin/entity}). Textures live in {@code textures/item/lure/} (PLAN-ITEMS §6);
 * the {@link AutoGlowingGeoLayer} lights the CRIMSON→GOLD heart-fragment core glowmask
 * that the idle anim pulses and the {@code offering} trigger surges.
 */
public final class HeraldsLureRenderer extends GeoItemRenderer<HeraldsLureItem> {
    private static final ResourceLocation TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/item/lure/heralds_lure.png");

    public HeraldsLureRenderer() {
        // Defaulted item triple: geo/item/heralds_lure.geo.json +
        // animations/item/heralds_lure.animation.json (texture overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, HeraldsLureItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(HeraldsLureItem animatable) {
        return TEXTURE;
    }
}
