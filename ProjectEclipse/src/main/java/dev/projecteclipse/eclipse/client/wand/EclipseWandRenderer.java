package dev.projecteclipse.eclipse.client.wand;

import java.util.EnumMap;
import java.util.Locale;
import java.util.Map;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.wand.EclipseWandItem;
import dev.projecteclipse.eclipse.wand.WandPath;
import dev.projecteclipse.eclipse.wand.WandSoulbind;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.ItemStack;
import software.bernie.geckolib.cache.object.BakedGeoModel;
import software.bernie.geckolib.model.DefaultedItemGeoModel;
import software.bernie.geckolib.renderer.GeoItemRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the Zauberstab (registered through {@code WandClientExtensions}'
 * {@code IClientItemExtensions#getCustomRenderer}; the item model is
 * {@code builtin/entity} so vanilla routes here in every perspective, GUI included).
 *
 * <p><b>Model evolution</b> (IDEA-19 §"the wand grows with you") uses the SINGLE geo file
 * {@code geo/item/eclipse_wand.geo.json}: one shared branch base plus per-path ornament
 * bone groups named {@code p_<path>_s<stage>} (riss: floating shard crown that multiplies;
 * glut: ember core + flame fins; stern: constellation disc + orbiting star points). This
 * renderer toggles bone visibility per frame from the synced {@code wand_path} /
 * {@code wand_level} data components — {@code GeoBone#setHidden} propagates to children,
 * so hiding the three group roots per foreign path is the whole job. Chosen over
 * per-path geo files because one file keeps the shared-base animations (idle float, use
 * flick, levelup surge) authored exactly once.</p>
 *
 * <p><b>Texture</b> swaps per path ({@code textures/item/wand/eclipse_wand[_<path>].png},
 * painter-generated) and the {@link AutoGlowingGeoLayer} lights each variant's painted
 * {@code _glowmask} (rune line + path ornaments) — glow rides the SAME
 * {@link #getTextureLocation} override, so it follows the swap automatically.</p>
 */
public final class EclipseWandRenderer extends GeoItemRenderer<EclipseWandItem> {
    private static final Map<WandPath, ResourceLocation> TEXTURES = new EnumMap<>(WandPath.class);
    /** Paths whose ornament groups exist in the geo (everything but NONE). */
    private static final WandPath[] ORNAMENT_PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    private static final int MAX_STAGE = 3;

    static {
        TEXTURES.put(WandPath.NONE, texture("eclipse_wand"));
        for (WandPath path : ORNAMENT_PATHS) {
            TEXTURES.put(path, texture("eclipse_wand_" + path.name().toLowerCase(Locale.ROOT)));
        }
    }

    private static ResourceLocation texture(String name) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID,
                "textures/item/wand/" + name + ".png");
    }

    public EclipseWandRenderer() {
        // Defaulted item triple: geo/item/eclipse_wand.geo.json +
        // animations/item/eclipse_wand.animation.json (texture is overridden below).
        super(new DefaultedItemGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, EclipseWandItem.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public ResourceLocation getTextureLocation(EclipseWandItem animatable) {
        ItemStack stack = getCurrentItemStack();
        WandPath path = stack == null ? WandPath.NONE : WandSoulbind.pathOf(stack);
        return TEXTURES.get(path);
    }

    @Override
    public void preRender(PoseStack poseStack, EclipseWandItem animatable, BakedGeoModel model,
            MultiBufferSource bufferSource, VertexConsumer buffer, boolean isReRender,
            float partialTick, int packedLight, int packedOverlay, int colour) {
        super.preRender(poseStack, animatable, model, bufferSource, buffer, isReRender,
                partialTick, packedLight, packedOverlay, colour);
        ItemStack stack = getCurrentItemStack();
        WandPath current = stack == null ? WandPath.NONE : WandSoulbind.pathOf(stack);
        int stage = current == WandPath.NONE ? 0
                : WandPath.stageForLevel(stack == null ? 1 : WandSoulbind.levelOf(stack));
        for (WandPath path : ORNAMENT_PATHS) {
            String prefix = "p_" + path.name().toLowerCase(Locale.ROOT) + "_s";
            for (int s = 1; s <= MAX_STAGE; s++) {
                boolean hidden = path != current || s > stage;
                model.getBone(prefix + s).ifPresent(bone -> bone.setHidden(hidden));
            }
        }
    }
}
