package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.ReviveSigilItem;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the revive sigil (registered through
 * {@code ItemsBClientExtensions}; the item model {@code models/item/revive_sigil.json}
 * is {@code builtin/entity} so vanilla routes every perspective here). Textures live in
 * the per-item folder {@code textures/item/sigil/} (PLAN-ITEMS §6), so
 * {@link #getTextureLocation} overrides the {@link DefaultedItemGeoModel} default —
 * the {@link AutoGlowingGeoLayer} rides the same override for the painted
 * {@code _glowmask} (the ACCENT glyph the idle anim pulses).
 */
public final class ReviveSigilRenderer extends GeoItemRenderer<ReviveSigilItem> {
    private static final ResourceLocation TEXTURE = ResourceLocation.fromNamespaceAndPath(
            EclipseMod.MOD_ID, "textures/item/sigil/revive_sigil.png");

    public ReviveSigilRenderer() {
        // Defaulted item triple: geo/item/revive_sigil.geo.json +
        // animations/item/revive_sigil.animation.json (texture overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, ReviveSigilItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(ReviveSigilItem animatable) {
        return TEXTURE;
    }
}
