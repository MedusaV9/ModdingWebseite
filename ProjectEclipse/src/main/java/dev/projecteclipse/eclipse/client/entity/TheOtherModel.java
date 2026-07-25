package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.TheOtherEntity;
import net.minecraft.client.model.HumanoidModel;
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
 * The Other's humanoid model (MOB-GLITCH): the EXACT vanilla mesh — the doppelganger
 * must stay silhouette-identical to the uniform-skinned players at a glance (spec §1.1
 * regression guard) — plus three tiny FLOATING FRAGMENT cubes parented to the head and
 * body. The fragments sample the uniform skin's own texture regions (torn-off chunks,
 * not new art) and stay {@code visible = false} while the mannequin is passive, so the
 * disguise holds until the REVEAL:
 *
 * <ul>
 *   <li><b>Looming idle</b> (passive + standing): the vanilla idle arm-bob is zeroed —
 *       arms dead-straight, mannequin-still — with a slight whole-torso lean-in and the
 *       stare tipped a few degrees down THROUGH the player. A person who breathes
 *       wrong.</li>
 *   <li><b>Reveal</b> (aggro — {@code isAggressive()} syncs with the melee goal, the
 *       same beat as the 180° head snap): the fragments detach and hover on slow
 *       phase-offset sine drifts with a lazy tumble, and the head cocks 7° off plumb.
 *       The silhouette stays; the personhood does not.</li>
 * </ul>
 */
@OnlyIn(Dist.CLIENT)
public class TheOtherModel extends HumanoidModel<TheOtherEntity> {
    /**
     * Rest offsets of the fragments (model space, y-down; vanilla right = −x), chosen
     * to CLEAR the limb volumes (arms occupy |x| 4–8 for y 2–14): crown floats above
     * the head's right corner, shoulder hangs outboard of the right arm, hip hovers
     * behind the left hip.
     */
    private static final float CROWN_X = -5.5F, CROWN_Y = -11.5F;
    private static final float SHOULDER_X = -10.0F, SHOULDER_Y = 1.0F;
    private static final float HIP_X = 5.8F, HIP_Y = 9.5F, HIP_Z = 4.5F;
    /** Suspension drift: ~0.28 Hz bob + lazy tumble — suspended, not bolted on. */
    private static final float DRIFT_SPEED = 0.09F;
    /** Reveal head cant, radians (~7°) — human angle, wrong execution. */
    private static final float REVEAL_HEAD_CANT = 0.12F;
    /** Looming lean-in / stare-down, radians. */
    private static final float LOOM_LEAN = 0.05F;
    private static final float LOOM_STARE_DOWN = 0.09F;

    private final ModelPart fragCrown;
    private final ModelPart fragShoulder;
    private final ModelPart fragHip;

    public TheOtherModel(ModelPart root) {
        super(root);
        this.fragCrown = this.head.getChild("frag_crown");
        this.fragShoulder = this.body.getChild("frag_shoulder");
        this.fragHip = this.body.getChild("frag_hip");
    }

    /**
     * Vanilla humanoid mesh (identical silhouette) + the three fragment cubes. The
     * texOffs sample existing uniform-skin regions on the 64x64 player layout — head
     * strip, jacket top, arm strip — so the shards read as chunks OF the body.
     */
    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = HumanoidModel.createMesh(CubeDeformation.NONE, 0.0F);
        PartDefinition root = mesh.getRoot();
        root.getChild("head").addOrReplaceChild("frag_crown",
                CubeListBuilder.create().texOffs(0, 0)
                        .addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.offset(CROWN_X, CROWN_Y, 0.0F));
        PartDefinition body = root.getChild("body");
        body.addOrReplaceChild("frag_shoulder",
                CubeListBuilder.create().texOffs(16, 16)
                        .addBox(-1.5F, -1.5F, -1.5F, 3.0F, 3.0F, 3.0F),
                PartPose.offset(SHOULDER_X, SHOULDER_Y, 0.5F));
        body.addOrReplaceChild("frag_hip",
                CubeListBuilder.create().texOffs(40, 16)
                        .addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.offset(HIP_X, HIP_Y, HIP_Z));
        return LayerDefinition.create(mesh, 64, 64);
    }

    @Override
    public void setupAnim(TheOtherEntity entity, float limbSwing, float limbSwingAmount,
            float ageInTicks, float netHeadYaw, float headPitch) {
        super.setupAnim(entity, limbSwing, limbSwingAmount, ageInTicks, netHeadYaw, headPitch);
        boolean revealed = entity.isAggressive();
        this.fragCrown.visible = revealed;
        this.fragShoulder.visible = revealed;
        this.fragHip.visible = revealed;
        if (revealed) {
            float drift = ageInTicks * DRIFT_SPEED;
            this.fragCrown.y = CROWN_Y + Mth.sin(drift) * 0.6F;
            this.fragCrown.yRot = drift * 0.35F;
            this.fragShoulder.x = SHOULDER_X + Mth.cos(drift * 0.7F) * 0.4F;
            this.fragShoulder.y = SHOULDER_Y + Mth.sin(drift + 2.1F) * 0.7F;
            this.fragShoulder.zRot = drift * 0.25F;
            this.fragHip.y = HIP_Y + Mth.sin(drift + 4.2F) * 0.5F;
            this.fragHip.xRot = drift * 0.3F;
            this.head.zRot += REVEAL_HEAD_CANT;
        } else if (limbSwingAmount < 0.05F) {
            // Looming idle: mannequin-still arms (the vanilla bob is the tell that a
            // body is alive — remove it), slight lean-in, stare tipped down at you.
            this.rightArm.xRot = 0.0F;
            this.rightArm.zRot = 0.02F;
            this.leftArm.xRot = 0.0F;
            this.leftArm.zRot = -0.02F;
            this.body.xRot = LOOM_LEAN;
            this.head.xRot += LOOM_STARE_DOWN;
        }
        this.hat.copyFrom(this.head); // Re-sync: super copied before our head tweaks.
    }
}
