package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.StormHeartItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the Storm Heart (registered through
 * {@code ItemsBClientExtensions}; item model {@code models/item/storm_heart.json} is
 * {@code builtin/entity}). Textures live in {@code textures/item/stormheart/}
 * (PLAN-ITEMS §6); the {@link AutoGlowingGeoLayer} lights the rotating core and the
 * lightning-arc planes the idle anim flickers — the item keeps NO enchant glint
 * (registry drops the override; the glow layer is the shimmer now).
 */
public final class StormHeartRenderer extends GeoItemRenderer<StormHeartItem> {
    private static final ResourceLocation TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/item/stormheart/storm_heart.png");

    public StormHeartRenderer() {
        // Defaulted item triple: geo/item/storm_heart.geo.json +
        // animations/item/storm_heart.animation.json (texture overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, StormHeartItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(StormHeartItem animatable) {
        return TEXTURE;
    }
}
