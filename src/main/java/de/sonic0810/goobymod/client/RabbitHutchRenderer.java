package de.sonic0810.goobymod.client;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.math.Axis;
import de.sonic0810.goobymod.block.entity.RabbitHutchBlockEntity;
import net.minecraft.client.gui.Font;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.blockentity.BlockEntityRendererProvider;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import org.joml.Matrix4f;

/** Renders the explicitly bound resident as compact sign-style nameplate text. */
public final class RabbitHutchRenderer implements BlockEntityRenderer<RabbitHutchBlockEntity> {
    private static final int NAME_COLOR = 0xFF3A2418;
    private static final int MAX_TEXT_WIDTH = 66;
    private final Font font;

    public RabbitHutchRenderer(BlockEntityRendererProvider.Context context) {
        this.font = context.getFont();
    }

    @Override
    public void render(RabbitHutchBlockEntity hutch, float partialTick, PoseStack poseStack,
            MultiBufferSource bufferSource, int packedLight, int packedOverlay) {
        if (hutch.getResidentName().isBlank()) {
            return;
        }
        String name = this.font.plainSubstrByWidth(hutch.getResidentName(), MAX_TEXT_WIDTH);
        Direction facing = hutch.getBlockState().getValue(HorizontalDirectionalBlock.FACING);

        poseStack.pushPose();
        poseStack.translate(0.5, 0.61, 0.5);
        poseStack.mulPose(Axis.YP.rotationDegrees(-facing.toYRot()));
        poseStack.translate(0.0, 0.0, -0.506);
        poseStack.scale(-0.0104F, -0.0104F, 0.0104F);
        Matrix4f pose = poseStack.last().pose();
        this.font.drawInBatch(name, -this.font.width(name) / 2.0F, -4.0F,
                NAME_COLOR, false, pose, bufferSource, Font.DisplayMode.POLYGON_OFFSET,
                0, packedLight);
        poseStack.popPose();
    }
}
