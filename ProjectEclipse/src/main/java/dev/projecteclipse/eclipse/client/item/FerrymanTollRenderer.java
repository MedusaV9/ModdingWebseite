package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.FerrymanTollItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the Ferryman's Toll (POLISH3; registered through
 * {@code ItemsCClientExtensions}). Spectral coin geo — the
 * {@link AutoGlowingGeoLayer} lights
 * {@code textures/item/toll/ferryman_toll_glowmask.png} (rim ring, barge/lantern
 * engravings, obol orbiters). Hand contexts only — see {@code UmbralBladeRenderer}
 * for the separate-transforms routing note.
 */
public final class FerrymanTollRenderer extends GeoItemRenderer<FerrymanTollItem> {
    public FerrymanTollRenderer() {
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, FerrymanTollItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(FerrymanTollItem animatable) {
        // NOT the defaulted textures/item/ferryman_toll.png — that is the FINAL 2D icon.
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/toll/ferryman_toll.png");
    }
}
