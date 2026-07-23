package dev.projecteclipse.eclipse.client.entity.door;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.limbo.door.RespawnDoorBlockEntity;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.AABB;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import software.bernie.geckolib.model.DefaultedBlockGeoModel;
import software.bernie.geckolib.renderer.GeoBlockRenderer;
import software.bernie.geckolib.renderer.layer.AutoGlowingGeoLayer;

/**
 * GeckoLib renderer for the Respawn Door (plans_v3 §2.5). One {@code eclipse}-namespace
 * id resolves the whole asset triple via {@link DefaultedBlockGeoModel}:
 * {@code geo/block/respawn_door.geo.json} +
 * {@code animations/block/respawn_door.animation.json} +
 * {@code textures/block/respawn_door.png} (128×128, with
 * {@code respawn_door_glowmask.png} feeding the {@link AutoGlowingGeoLayer} — the
 * {@code #B98CFF} seam/glyph/disc blaze).
 *
 * <p>The geo is authored front-facing NORTH (Blockbench default);
 * {@link GeoBlockRenderer} yaws it by the blockstate's {@code HORIZONTAL_FACING} (EAST
 * on the ship), and per-viewer pose logic lives in
 * {@link RespawnDoorBlockEntity#clientPoseAnimation()}. The render box is widened to the
 * full 3×6×3 multiblock volume so the door never frustum-pops while its controller cell
 * (bottom-center) is off screen.</p>
 */
@OnlyIn(Dist.CLIENT)
public class RespawnDoorRenderer extends GeoBlockRenderer<RespawnDoorBlockEntity> {
    public RespawnDoorRenderer() {
        super(new DefaultedBlockGeoModel<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, RespawnDoorBlockEntity.GEO_ID)));
        addRenderLayer(new AutoGlowingGeoLayer<>(this));
    }

    @Override
    public AABB getRenderBoundingBox(RespawnDoorBlockEntity blockEntity) {
        BlockPos pos = blockEntity.getBlockPos();
        // Controller = bottom-center cell; cover the whole aperture for any facing
        // (leaves swing one block past the wall plane while opening).
        return new AABB(pos.getX() - 2, pos.getY(), pos.getZ() - 2,
                pos.getX() + 3, pos.getY() + 6, pos.getZ() + 3);
    }
}
