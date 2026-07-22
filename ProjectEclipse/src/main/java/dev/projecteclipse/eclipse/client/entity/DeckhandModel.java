package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import net.minecraft.client.model.HierarchicalModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.PartPose;
import net.minecraft.client.model.geom.builders.CubeDeformation;
import net.minecraft.client.model.geom.builders.CubeListBuilder;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.geom.builders.MeshDefinition;
import net.minecraft.client.model.geom.builders.PartDefinition;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Deckhand model — 7 cubes on a 64x64 texture ({@code docs/uv/deckhand.md}): legless robe
 * base 8x8x6 on the deck, hunched torso 8x10x4 (xRot 0.15), head 8x8x8 under a 0.25-inflated
 * hood, two 3x10x3 arms extended forward (base xRot −1.2) and a 1x22x1 oar shaft gripped by
 * the right arm.
 *
 * <p>Anim (§1.4): rowing {@code arm.xRot = −1.2 + sin(age*0.08)*0.35} — the same slow pull
 * cadence the block-display oars follow — plus a small torso zRot sway on the same clock.
 * The head only moves when the occasional {@code LookAtPlayerGoal} tracks a ghost.</p>
 */
@OnlyIn(Dist.CLIENT)
public class DeckhandModel extends HierarchicalModel<DeckhandEntity> {
    private static final float ARM_BASE_X_ROT = -1.2F;
    private static final float TORSO_HUNCH = 0.15F;

    private final ModelPart root;
    private final ModelPart torso;
    private final ModelPart head;
    private final ModelPart armLeft;
    private final ModelPart armRight;

    public DeckhandModel(ModelPart root) {
        this.root = root;
        this.torso = root.getChild("torso");
        this.head = this.torso.getChild("head");
        this.armLeft = this.torso.getChild("arm_left");
        this.armRight = this.torso.getChild("arm_right");
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("deckhand_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 24.0F, 0.0F));
        root.addOrReplaceChild("robe", CubeListBuilder.create()
                .texOffs(24, 16).addBox(-4.0F, -8.0F, -3.0F, 8.0F, 8.0F, 6.0F),
                PartPose.ZERO);
        PartDefinition torso = root.addOrReplaceChild("torso", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-4.0F, -10.0F, -2.0F, 8.0F, 10.0F, 4.0F),
                PartPose.offsetAndRotation(0.0F, -8.0F, 0.0F, TORSO_HUNCH, 0.0F, 0.0F));
        PartDefinition head = torso.addOrReplaceChild("head", CubeListBuilder.create()
                .texOffs(24, 0).addBox(-4.0F, -8.0F, -4.0F, 8.0F, 8.0F, 8.0F),
                PartPose.offset(0.0F, -10.0F, 0.0F));
        head.addOrReplaceChild("hood", CubeListBuilder.create()
                .texOffs(0, 27).addBox(-4.0F, -8.0F, -4.0F, 8.0F, 8.0F, 8.0F, new CubeDeformation(0.25F)),
                PartPose.ZERO);
        PartDefinition armRight = torso.addOrReplaceChild("arm_right", CubeListBuilder.create()
                .texOffs(0, 14).addBox(-1.5F, 0.0F, -1.5F, 3.0F, 10.0F, 3.0F),
                PartPose.offsetAndRotation(-5.5F, -9.0F, 0.0F, ARM_BASE_X_ROT, 0.0F, 0.0F));
        torso.addOrReplaceChild("arm_left", CubeListBuilder.create()
                .texOffs(12, 14).addBox(-1.5F, 0.0F, -1.5F, 3.0F, 10.0F, 3.0F),
                PartPose.offsetAndRotation(5.5F, -9.0F, 0.0F, ARM_BASE_X_ROT, 0.0F, 0.0F));
        // Oar shaft crosses the right hand, slanting down toward the water.
        armRight.addOrReplaceChild("oar", CubeListBuilder.create()
                .texOffs(56, 16).addBox(-0.5F, -14.0F, -0.5F, 1.0F, 22.0F, 1.0F),
                PartPose.offsetAndRotation(0.0F, 9.0F, 0.0F, 0.4F, 0.0F, 0.0F));
        return LayerDefinition.create(mesh, 64, 64);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(DeckhandEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        float pull = ARM_BASE_X_ROT + Mth.sin(ageInTicks * 0.08F) * 0.35F; // Spec formula.
        this.armLeft.xRot = pull;
        this.armRight.xRot = pull;
        this.torso.zRot = Mth.sin(ageInTicks * 0.08F) * 0.05F;
        this.torso.xRot = TORSO_HUNCH;
        this.head.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.head.xRot = headPitch * Mth.DEG_TO_RAD;
    }
}
