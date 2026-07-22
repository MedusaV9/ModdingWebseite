package dev.projecteclipse.eclipse.client.entity;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.entity.GazerEntity;
import net.minecraft.client.model.HierarchicalModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.PartPose;
import net.minecraft.client.model.geom.builders.CubeListBuilder;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.geom.builders.MeshDefinition;
import net.minecraft.client.model.geom.builders.PartDefinition;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Gazer model — 6 cubes on a 64x64 texture ({@code docs/uv/gazer.md}): cloak 10x18x6
 * floating 6px above the ground, shoulder mantle 12x3x8, hood 8x8x8 (pivot 18px up),
 * emissive face inset 6x6x1 (re-rendered by {@code GazerRenderer.EyesLayer} with
 * {@code RenderType.eyes}), and two 3x8x1 hem tatters.
 *
 * <p>Anim: whole-body bob {@code sin(age*0.06)*0.8px}, tatter sway
 * {@code xRot = sin(age*0.1 + phase)*0.15}, hood (and the face with it) yaw-tracking the
 * look target via {@code netHeadYaw}.</p>
 */
@OnlyIn(Dist.CLIENT)
public class GazerModel extends HierarchicalModel<GazerEntity> {
    private final ModelPart root;
    private final ModelPart cloak;
    private final ModelPart mantle;
    private final ModelPart hood;
    private final ModelPart face;
    private final ModelPart tatterLeft;
    private final ModelPart tatterRight;

    public GazerModel(ModelPart root) {
        this.root = root;
        this.cloak = root.getChild("cloak");
        this.mantle = root.getChild("mantle");
        this.hood = root.getChild("hood");
        this.face = this.hood.getChild("face");
        this.tatterLeft = this.cloak.getChild("tatter_left");
        this.tatterRight = this.cloak.getChild("tatter_right");
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("gazer_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 24.0F, 0.0F));
        // Cloak bottom hem floats 6px above ground; body spans ground-Y 6..24.
        PartDefinition cloak = root.addOrReplaceChild("cloak", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-5.0F, -18.0F, -3.0F, 10.0F, 18.0F, 6.0F),
                PartPose.offset(0.0F, -6.0F, 0.0F));
        root.addOrReplaceChild("mantle", CubeListBuilder.create()
                .texOffs(0, 40).addBox(-6.0F, -1.5F, -4.0F, 12.0F, 3.0F, 8.0F),
                PartPose.offset(0.0F, -22.0F, 0.0F));
        PartDefinition hood = root.addOrReplaceChild("hood", CubeListBuilder.create()
                .texOffs(32, 0).addBox(-4.0F, -8.0F, -4.0F, 8.0F, 8.0F, 8.0F),
                PartPose.offset(0.0F, -18.0F, 0.0F)); // Spec pivot (0,18,0) above ground.
        hood.addOrReplaceChild("face", CubeListBuilder.create()
                .texOffs(32, 16).addBox(-3.0F, -7.0F, -4.25F, 6.0F, 6.0F, 1.0F),
                PartPose.ZERO);
        cloak.addOrReplaceChild("tatter_left", CubeListBuilder.create()
                .texOffs(0, 24).addBox(-1.5F, 0.0F, -0.5F, 3.0F, 8.0F, 1.0F),
                PartPose.offset(-2.5F, 0.0F, 1.0F));
        cloak.addOrReplaceChild("tatter_right", CubeListBuilder.create()
                .texOffs(10, 24).addBox(-1.5F, 0.0F, -0.5F, 3.0F, 8.0F, 1.0F),
                PartPose.offset(2.5F, 0.0F, 1.0F));
        return LayerDefinition.create(mesh, 64, 64);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(GazerEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        this.root.y = 24.0F - Mth.sin(ageInTicks * 0.06F) * 0.8F;
        this.hood.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.tatterLeft.xRot = Mth.sin(ageInTicks * 0.1F) * 0.15F;
        this.tatterRight.xRot = Mth.sin(ageInTicks * 0.1F + (float) Math.PI) * 0.15F;
    }

    /**
     * Renders ONLY the face cube (fullbright, {@code RenderType.eyes}) while keeping every
     * ancestor transform: all other parts get {@code skipDraw} for one draw of the tree.
     */
    public void renderFaceEmissive(PoseStack poseStack, VertexConsumer buffer, int packedLight, int packedOverlay) {
        this.cloak.skipDraw = true;
        this.mantle.skipDraw = true;
        this.hood.skipDraw = true;
        this.tatterLeft.skipDraw = true;
        this.tatterRight.skipDraw = true;
        this.root.render(poseStack, buffer, packedLight, packedOverlay);
        this.cloak.skipDraw = false;
        this.mantle.skipDraw = false;
        this.hood.skipDraw = false;
        this.tatterLeft.skipDraw = false;
        this.tatterRight.skipDraw = false;
    }
}
