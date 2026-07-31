package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.economy.UmbralBladeItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the umbral blade (POLISH3; registered through
 * {@code ItemsCClientExtensions}). Curved umbral shortsword geo — the
 * {@link AutoGlowingGeoLayer} lights the painted
 * {@code textures/item/umbral/umbral_blade_glowmask.png} (vein inlay on the blade
 * flats, edge-aura planes, pommel eye). Default cutout render type: the albedo has no
 * partial alpha, the wisps' raggedness is real cutout holes.
 *
 * <p>This renderer only ever runs for HAND (and head) contexts — the item model is a
 * {@code neoforge:separate_transforms} model whose gui/ground/fixed perspectives bake
 * to the 2D sprite, so vanilla never routes those contexts to the BEWLR
 * ({@code ItemRenderer#render} re-resolves {@code isCustomRenderer()} AFTER
 * {@code applyTransform} picked the per-context child model).</p>
 */
public final class UmbralBladeRenderer extends GeoItemRenderer<UmbralBladeItem> {
    public UmbralBladeRenderer() {
        // Defaulted item triple: geo/item/umbral_blade.geo.json +
        // animations/item/umbral_blade.animation.json (texture is overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, UmbralBladeItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(UmbralBladeItem animatable) {
        // NOT the defaulted textures/item/umbral_blade.png — that path is the FINAL 2D
        // icon the gui/ground/fixed perspectives keep using.
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/umbral/umbral_blade.png");
    }
}
