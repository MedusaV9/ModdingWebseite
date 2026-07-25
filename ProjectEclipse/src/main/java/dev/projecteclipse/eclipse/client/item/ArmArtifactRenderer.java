package dev.projecteclipse.eclipse.client.item;

import com.mojang.blaze3d.vertex.PoseStack;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.artifact.ArmArtifactItem;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.core.component.DataComponents;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.ItemDisplayContext;
import net.minecraft.world.item.ItemStack;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the arm artifact (PLAN-ITEMS A2; registered through
 * {@code ItemsAClientExtensions}). Severed-forearm geo with the ledger-light mote —
 * the {@link AutoGlowingGeoLayer} lights the painted
 * {@code textures/item/artifact/arm_artifact_glowmask.png} (mote, stump ring, palm
 * light-spill).
 *
 * <p><b>Glint discipline (plan §2.3):</b> geo items drop the enchant glint — the geo
 * glow replaces it. {@code GeoItemRenderer} reads foil straight off
 * {@code ItemStack#hasFoil}, and the registration-side
 * {@code ENCHANTMENT_GLINT_OVERRIDE} drop lands with ITEMS-B (sole owner of
 * {@code EclipseItems.java}), so until that merges {@link #renderByItem} defensively
 * renders a foil-stripped copy. Zero-cost once the component is gone, and it also
 * satisfies the §2.3 "no double-shimmer with AutoGlowingGeoLayer" acceptance check
 * regardless of merge order.</p>
 */
public final class ArmArtifactRenderer extends GeoItemRenderer<ArmArtifactItem> {
    public ArmArtifactRenderer() {
        // Defaulted item triple: geo/item/arm_artifact.geo.json +
        // animations/item/arm_artifact.animation.json (texture is overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, ArmArtifactItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(ArmArtifactItem animatable) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/artifact/arm_artifact.png");
    }

    @Override
    public void renderByItem(ItemStack stack, ItemDisplayContext transformType, PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight, int packedOverlay) {
        if (stack.hasFoil()) {
            stack = stack.copy();
            stack.set(DataComponents.ENCHANTMENT_GLINT_OVERRIDE, Boolean.FALSE);
        }
        super.renderByItem(stack, transformType, poseStack, bufferSource, packedLight, packedOverlay);
    }
}
