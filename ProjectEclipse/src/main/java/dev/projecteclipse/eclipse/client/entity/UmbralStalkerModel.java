package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.UmbralStalkerEntity;
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
 * Umbral Stalker model — 11 cubes on a 64x64 texture ({@code docs/uv/umbral_stalker.md}),
 * exactly the spec sizes/pivots (§1.3): body 8x7x14 (pivot 10px up, xRot 0.05), head 7x6x8
 * (pivot 12px up, 8px forward) with two hanging 1x3x1 jaw shards, four 3x8x3 legs, and
 * three spine shards (2x4x2 / 2x5x2 / 2x4x2 at z −4/0/4, zRot ±0.2) riding the back.
 *
 * <p>Anim: quadruped legs {@code cos(limbSwing*0.66 + phase)*1.2*limbSwingAmount}
 * (diagonal pairs), spine shards pulse-breathe (lift + rock), head lowers 0.3 rad while
 * hunting ({@code entity.headLower}).</p>
 */
@OnlyIn(Dist.CLIENT)
public class UmbralStalkerModel extends HierarchicalModel<UmbralStalkerEntity> {
    private static final float BODY_X_ROT = 0.05F;
    private static final float SPINE_Z_ROT = 0.2F;

    private final ModelPart root;
    private final ModelPart body;
    private final ModelPart head;
    private final ModelPart[] legs;
    private final ModelPart[] spines;

    public UmbralStalkerModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the stalker_root bone.
        ModelPart bone = root.getChild("stalker_root");
        this.body = bone.getChild("body");
        this.head = bone.getChild("head");
        this.legs = new ModelPart[] {
                bone.getChild("leg_front_left"), bone.getChild("leg_front_right"),
                bone.getChild("leg_hind_left"), bone.getChild("leg_hind_right")};
        this.spines = new ModelPart[] {
                this.body.getChild("spine_front"), this.body.getChild("spine_mid"),
                this.body.getChild("spine_back")};
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("stalker_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 24.0F, 0.0F));
        PartDefinition body = root.addOrReplaceChild("body", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-4.0F, -3.5F, -7.0F, 8.0F, 7.0F, 14.0F),
                PartPose.offsetAndRotation(0.0F, -10.0F, 0.0F, BODY_X_ROT, 0.0F, 0.0F));
        PartDefinition head = root.addOrReplaceChild("head", CubeListBuilder.create()
                .texOffs(0, 21).addBox(-3.5F, -3.0F, -8.0F, 7.0F, 6.0F, 8.0F),
                PartPose.offset(0.0F, -12.0F, -8.0F));
        head.addOrReplaceChild("jaw_left", CubeListBuilder.create()
                .texOffs(30, 21).addBox(-0.5F, 0.0F, -0.5F, 1.0F, 3.0F, 1.0F),
                PartPose.offset(-1.5F, 3.0F, -7.5F));
        head.addOrReplaceChild("jaw_right", CubeListBuilder.create()
                .texOffs(36, 21).addBox(-0.5F, 0.0F, -0.5F, 1.0F, 3.0F, 1.0F),
                PartPose.offset(1.5F, 3.0F, -7.5F));
        int[] legU = {0, 12, 24, 36};
        String[] legNames = {"leg_front_left", "leg_front_right", "leg_hind_left", "leg_hind_right"};
        float[][] legPos = {{-2.5F, -5.0F}, {2.5F, -5.0F}, {-2.5F, 5.0F}, {2.5F, 5.0F}};
        for (int i = 0; i < 4; i++) {
            root.addOrReplaceChild(legNames[i], CubeListBuilder.create()
                    .texOffs(legU[i], 35).addBox(-1.5F, 0.0F, -1.5F, 3.0F, 8.0F, 3.0F),
                    PartPose.offset(legPos[i][0], -8.0F, legPos[i][1]));
        }
        body.addOrReplaceChild("spine_front", CubeListBuilder.create()
                .texOffs(44, 0).addBox(-1.0F, -4.0F, -1.0F, 2.0F, 4.0F, 2.0F),
                PartPose.offsetAndRotation(0.0F, -3.5F, -4.0F, 0.0F, 0.0F, SPINE_Z_ROT));
        body.addOrReplaceChild("spine_mid", CubeListBuilder.create()
                .texOffs(44, 6).addBox(-1.0F, -5.0F, -1.0F, 2.0F, 5.0F, 2.0F),
                PartPose.offsetAndRotation(0.0F, -3.5F, 0.0F, 0.0F, 0.0F, -SPINE_Z_ROT));
        body.addOrReplaceChild("spine_back", CubeListBuilder.create()
                .texOffs(44, 13).addBox(-1.0F, -4.0F, -1.0F, 2.0F, 4.0F, 2.0F),
                PartPose.offsetAndRotation(0.0F, -3.5F, 4.0F, 0.0F, 0.0F, SPINE_Z_ROT));
        return LayerDefinition.create(mesh, 64, 64);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(UmbralStalkerEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        // Quadruped gait: diagonal pairs in phase (FL+HR vs FR+HL).
        float[] phases = {0.0F, (float) Math.PI, (float) Math.PI, 0.0F};
        for (int i = 0; i < 4; i++) {
            this.legs[i].xRot = Mth.cos(limbSwing * 0.66F + phases[i]) * 1.2F * limbSwingAmount;
        }
        this.head.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.head.xRot = headPitch * Mth.DEG_TO_RAD + entity.headLower(0.0F);
        this.body.xRot = BODY_X_ROT;
        for (int i = 0; i < 3; i++) {
            float pulse = entity.shardPulse(ageInTicks, i);
            this.spines[i].y = -3.5F - (pulse * 0.5F + 0.5F) * 0.6F;
            float base = i == 1 ? -SPINE_Z_ROT : SPINE_Z_ROT;
            this.spines[i].zRot = base + pulse * 0.05F;
        }
    }
}
