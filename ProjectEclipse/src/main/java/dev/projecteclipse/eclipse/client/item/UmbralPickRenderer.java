package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.UmbralPickItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the umbral pick (POLISH3; registered through
 * {@code ItemsCClientExtensions}). Twin-prong pick geo — the
 * {@link AutoGlowingGeoLayer} lights
 * {@code textures/item/umbral/umbral_pick_glowmask.png} (prong seams, moon gem, haft
 * vein). Hand contexts only — see {@code UmbralBladeRenderer} for the
 * separate-transforms routing note.
 */
public final class UmbralPickRenderer extends GeoItemRenderer<UmbralPickItem> {
    public UmbralPickRenderer() {
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, UmbralPickItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(UmbralPickItem animatable) {
        // NOT the defaulted textures/item/umbral_pick.png — that is the FINAL 2D icon.
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/umbral/umbral_pick.png");
    }
}
