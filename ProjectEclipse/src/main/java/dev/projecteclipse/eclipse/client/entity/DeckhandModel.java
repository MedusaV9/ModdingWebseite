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
 *
 * <p><b>Hostile pose</b> (Ferryman P2 "Crew", blended via {@code entity.hostileAmount}):
 * the oar cube is hidden, the arms lerp up into a reaching claw, a limbSwing shamble sway
 * rocks the torso while it chases, and {@code attackTime} drives a zombie-style lunge
 * (arms sweep down, torso pitches in) so melee swings read. Calming blends straight back
 * to the seated rowing pull.</p>
 */
@OnlyIn(Dist.CLIENT)
public class DeckhandModel extends HierarchicalModel<DeckhandEntity> {
    private static final float ARM_BASE_X_ROT = -1.2F;
    private static final float TORSO_HUNCH = 0.15F;
    /** Hostile reach: arms up just past horizontal, clawing at chest height. */
    private static final float ARM_REACH_X_ROT = -1.7F;

    private final ModelPart root;
    private final ModelPart torso;
    private final ModelPart head;
    private final ModelPart armLeft;
    private final ModelPart armRight;
    private final ModelPart oar;

    public DeckhandModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the deckhand_root bone.
        this.torso = root.getChild("deckhand_root").getChild("torso");
        this.head = this.torso.getChild("head");
        this.armLeft = this.torso.getChild("arm_left");
        this.armRight = this.torso.getChild("arm_right");
        this.oar = this.armRight.getChild("oar");
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
        // ageInTicks = tickCount + partialTick; recover the fraction for the pose blend.
        float partialTick = ageInTicks - entity.tickCount;
        float hostile = entity.hostileAmount(partialTick);

        // Seated rower (default): both arms on the slow oar pull, torso swaying with it.
        float pull = ARM_BASE_X_ROT + Mth.sin(ageInTicks * 0.08F) * 0.35F; // Spec formula.
        float rowSway = Mth.sin(ageInTicks * 0.08F) * 0.05F;

        // Risen fighter: reaching claw + limbSwing shamble + attackTime lunge. The lunge
        // sweeps the raised arms down onto the target (zombie-style two-beat swing).
        float shamble = Mth.cos(limbSwing * 0.6F) * 0.25F * limbSwingAmount;
        float lunge = Mth.sin(this.attackTime * Mth.PI);
        float lungeEase = Mth.sin((1.0F - (1.0F - this.attackTime) * (1.0F - this.attackTime)) * Mth.PI);
        float reach = ARM_REACH_X_ROT + lunge * 1.1F - lungeEase * 0.35F;

        this.armRight.xRot = Mth.lerp(hostile, pull, reach + shamble);
        this.armLeft.xRot = Mth.lerp(hostile, pull, reach - shamble);
        // Claws spread slightly apart; the rowing pose keeps the arms parallel.
        this.armRight.zRot = hostile * -0.12F;
        this.armLeft.zRot = hostile * 0.12F;
        this.torso.zRot = Mth.lerp(hostile, rowSway, shamble * 0.4F);
        this.torso.xRot = TORSO_HUNCH + hostile * lunge * 0.25F; // Pitch into the swing.
        this.head.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.head.xRot = headPitch * Mth.DEG_TO_RAD;
        // A risen deckhand drops its oar at the bench; the cube pops back when it calms.
        this.oar.visible = hostile < 0.5F;
    }
}
