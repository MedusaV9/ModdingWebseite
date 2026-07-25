package dev.projecteclipse.eclipse.client.item;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the heart extractor (PLAN-ITEMS A3; registered through
 * {@code ItemsAClientExtensions}). Brass-and-glass heart-tap geo — the
 * {@link AutoGlowingGeoLayer} lights the painted
 * {@code textures/item/extractor/heart_extractor_glowmask.png} (vitae fill + the
 * shine-through painted into the chamber's glowmask pixels), and
 * {@link #getRenderType} returns a translucent type because the chamber's glass albedo
 * uses partial alpha (the cutout default would render it fully opaque —
 * P6 conventions §6).
 */
public final class HeartExtractorRenderer extends GeoItemRenderer<HeartExtractorItem> {
    public HeartExtractorRenderer() {
        // Defaulted item triple: geo/item/heart_extractor.geo.json +
        // animations/item/heart_extractor.animation.json (texture is overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, HeartExtractorItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(HeartExtractorItem animatable) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/extractor/heart_extractor.png");
    }

    @Override
    public RenderType getRenderType(HeartExtractorItem animatable, ResourceLocation texture,
            MultiBufferSource bufferSource, float partialTick) {
        return RenderType.entityTranslucent(texture);
    }

    /**
     * Whether {@code stack} is being channeled by a player in the client level right now
     * — drives the {@code base} controller's idle↔channel swap
     * ({@code HeartExtractorItem#registerControllers} references this fully-qualified so
     * the class never loads on a dedicated server). Identity comparison is correct: the
     * rendered stack IS the inventory stack on the client, for the local player and
     * remote holders alike.
     */
    public static boolean isClientChanneling(ItemStack stack) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.level == null) {
            return false;
        }
        for (Player player : minecraft.level.players()) {
            if (player.isUsingItem() && player.getUseItem() == stack) {
                return true;
            }
        }
        return false;
    }
}
