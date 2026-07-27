package dev.projecteclipse.eclipse.client.altarmodel;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.ritual.AltarBlockEntity;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.AABB;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.model.DefaultedBlockGeoModel;
import software.bernie.geckolib.renderer.GeoBlockRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the ritual altar (F-076). One {@code eclipse}-namespace id
 * resolves the whole asset triple via {@link DefaultedBlockGeoModel}:
 * {@code geo/block/altar.geo.json} + {@code animations/block/altar.animation.json} +
 * {@code textures/block/altar.png} (256×128, with {@code altar_glowmask.png} feeding
 * the {@link AutoGlowingGeoLayer} — rune plates, the eclipse heart, crown inlay, ring
 * ticks and horn tips blaze in the dark).
 *
 * <p>The model is a monument, not a cube: a two-step deepslate plinth wearing four
 * floating rune plates, a crown plate with corner horns, the floating eclipse core
 * ~1.6 blocks above the plate, three slowly counter-rotating rune rings and four
 * orbiting debris chips. The geometry extends ~1 block past the block column on every
 * side and up to ~3 blocks high (the erupt one-shot lifts the core ~1 more), so the
 * render box is widened accordingly — the altar must never frustum-pop while its
 * block-pos cell is off screen. The altar has no FACING property; the geo renders
 * unrotated (it is 4-fold symmetric anyway).</p>
 */
@OnlyIn(Dist.CLIENT)
public class AltarModelRenderer extends GeoBlockRenderer<AltarBlockEntity> {
    public AltarModelRenderer() {
        super(new DefaultedBlockGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, AltarBlockEntity.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public AABB getRenderBoundingBox(AltarBlockEntity blockEntity) {
        BlockPos pos = blockEntity.getBlockPos();
        // Rings reach ~1 block past the cell; erupt lifts the core to ~+3.9 blocks.
        return new AABB(pos.getX() - 2, pos.getY(), pos.getZ() - 2,
                pos.getX() + 3, pos.getY() + 5, pos.getZ() + 3);
    }
}
