package dev.projecteclipse.eclipse.client.entity;

import java.util.List;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.entity.boss.FerrymanEntity;
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
 * Ferryman model — 17 cubes on a 128×128 texture ({@code docs/uv/ferryman.md}), all
 * procedural per spec §2.2: floating robe 10×26×8 with 4 hanging strips 2×6×1, skull 7×7×7
 * under a 9×9×9 hood (open front — the hood's north face is transparent in the skin),
 * emissive eye slit 5×2×1, arms 3×20×3, two-handed oar 2×2×36 (+ a 1×6×5 blade), and a
 * 4×5×4 lantern with a 2×2×2 emissive flame swinging off the left shoulder on a 3-segment
 * 1×4×1 chain.
 *
 * <p>Anim (age = the entity's smooth clock, ×1.4 in P3): float bob
 * {@code sin(age*0.05)*1.5px}; chain segment k drag-lag swing
 * {@code zRot = sin(age*0.07 - k*0.45)*0.3}; rowing-idle oar
 * {@code xRot = -0.7 + sin(age*0.08)*0.35}. Pose blends from the entity: telegraph raises
 * the oar overhead ({@code raiseAmount}), P2 kneels the whole body ({@code kneelAmount}),
 * P3 plants the oar vertically beside him ({@code plantAmount}; a running telegraph still
 * lifts it — plant is applied first, raise last).</p>
 */
@OnlyIn(Dist.CLIENT)
public class FerrymanModel extends HierarchicalModel<FerrymanEntity> {
    /** Robe pivot height in px above ground (root sits at y=24 = ground). */
    private static final float BODY_PIVOT_Y = -27.0F;
    private static final float OAR_BONE_X = 0.0F;
    private static final float OAR_BONE_Y = -6.0F;
    private static final float OAR_BONE_Z = -7.0F;

    private final ModelPart root;
    private final ModelPart body;
    private final ModelPart head;
    private final ModelPart eyes;
    private final ModelPart armRight;
    private final ModelPart armLeft;
    private final ModelPart oar;
    private final ModelPart[] strips = new ModelPart[4];
    private final ModelPart[] chain = new ModelPart[3];
    private final ModelPart lantern;
    private final ModelPart flame;
    private final List<ModelPart> allParts;

    public FerrymanModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the ferryman_root bone.
        ModelPart bone = root.getChild("ferryman_root");
        this.body = bone.getChild("body");
        this.head = this.body.getChild("head");
        this.eyes = this.head.getChild("eyes");
        this.armRight = this.body.getChild("arm_right");
        this.armLeft = this.body.getChild("arm_left");
        this.oar = this.body.getChild("oar");
        for (int i = 0; i < strips.length; i++) {
            this.strips[i] = this.body.getChild("strip" + i);
        }
        ModelPart parent = this.body;
        for (int k = 0; k < chain.length; k++) {
            parent = parent.getChild("chain" + k);
            this.chain[k] = parent;
        }
        this.lantern = this.chain[2].getChild("lantern");
        this.flame = this.lantern.getChild("flame");
        this.allParts = root.getAllParts().toList();
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("ferryman_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 24.0F, 0.0F));
        // Robe 10x26x8, floating: bottom hem 14px above the ground.
        PartDefinition body = root.addOrReplaceChild("body", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-5.0F, -13.0F, -4.0F, 10.0F, 26.0F, 8.0F),
                PartPose.offset(0.0F, BODY_PIVOT_Y, 0.0F));
        // 4 hanging robe strips 2x6x1 off the bottom hem (front + back pairs).
        float[][] stripAt = {{-2.5F, -3.5F}, {2.5F, -3.5F}, {-2.5F, 3.5F}, {2.5F, 3.5F}};
        for (int i = 0; i < 4; i++) {
            body.addOrReplaceChild("strip" + i, CubeListBuilder.create()
                    .texOffs(32 + i * 8, 36).addBox(-1.0F, 0.0F, -0.5F, 2.0F, 6.0F, 1.0F),
                    PartPose.offset(stripAt[i][0], 13.0F, stripAt[i][1]));
        }
        // Skull 7x7x7 on the robe top, hood 9x9x9 around it (open front in the skin).
        PartDefinition head = body.addOrReplaceChild("head", CubeListBuilder.create()
                .texOffs(80, 0).addBox(-3.5F, -7.0F, -3.5F, 7.0F, 7.0F, 7.0F),
                PartPose.offset(0.0F, -13.0F, 0.0F));
        head.addOrReplaceChild("hood", CubeListBuilder.create()
                .texOffs(40, 0).addBox(-4.5F, -8.5F, -4.0F, 9.0F, 9.0F, 9.0F),
                PartPose.ZERO);
        // Emissive eye slit 5x2x1 poking out of the skull's brow (HeraldRenderer eyes pass).
        head.addOrReplaceChild("eyes", CubeListBuilder.create()
                .texOffs(108, 0).addBox(-2.5F, -5.5F, -4.25F, 5.0F, 2.0F, 1.0F),
                PartPose.ZERO);
        // Arms 3x20x3 off the robe shoulders.
        body.addOrReplaceChild("arm_right", CubeListBuilder.create()
                .texOffs(0, 36).addBox(-1.5F, 0.0F, -1.5F, 3.0F, 20.0F, 3.0F),
                PartPose.offset(-6.5F, -11.0F, 0.0F));
        body.addOrReplaceChild("arm_left", CubeListBuilder.create()
                .texOffs(16, 36).addBox(-1.5F, 0.0F, -1.5F, 3.0F, 20.0F, 3.0F),
                PartPose.offset(6.5F, -11.0F, 0.0F));
        // Two-handed oar 2x2x36 (pivot mid-shaft, chest height, in front) + 1x6x5 blade.
        PartDefinition oar = body.addOrReplaceChild("oar", CubeListBuilder.create()
                .texOffs(64, 36).addBox(-1.0F, -18.0F, -1.0F, 2.0F, 36.0F, 2.0F),
                PartPose.offset(OAR_BONE_X, OAR_BONE_Y, OAR_BONE_Z));
        oar.addOrReplaceChild("blade", CubeListBuilder.create()
                .texOffs(76, 36).addBox(-0.5F, 12.0F, -2.5F, 1.0F, 6.0F, 5.0F),
                PartPose.ZERO);
        // Lantern chain off the LEFT shoulder: 3 chained 1x4x1 segments + 4x5x4 lantern.
        PartDefinition parent = body;
        for (int k = 0; k < 3; k++) {
            parent = parent.addOrReplaceChild("chain" + k, CubeListBuilder.create()
                    .texOffs(92 + k * 6, 36).addBox(-0.5F, 0.0F, -0.5F, 1.0F, 4.0F, 1.0F),
                    k == 0 ? PartPose.offset(6.5F, -11.0F, 1.5F) : PartPose.offset(0.0F, 4.0F, 0.0F));
        }
        PartDefinition lantern = parent.addOrReplaceChild("lantern", CubeListBuilder.create()
                .texOffs(92, 44).addBox(-2.0F, 0.0F, -2.0F, 4.0F, 5.0F, 4.0F),
                PartPose.offset(0.0F, 4.0F, 0.0F));
        // Emissive flame cube inside the lantern.
        lantern.addOrReplaceChild("flame", CubeListBuilder.create()
                .texOffs(110, 36).addBox(-1.0F, 1.5F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.ZERO);
        return LayerDefinition.create(mesh, 128, 128);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(FerrymanEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        // ageInTicks = tickCount + partialTick; recover the fraction for the smooth clock.
        float partialTick = ageInTicks - entity.tickCount;
        float age = entity.animAge(partialTick);
        float raise = entity.raiseAmount(partialTick);
        float kneel = entity.kneelAmount(partialTick);
        float plant = entity.plantAmount(partialTick);

        // Float bob; kneeling drops the whole body toward the deck and hunches it forward.
        this.body.y = BODY_PIVOT_Y + Mth.sin(age * 0.05F) * 1.5F * (1.0F - kneel) + kneel * 11.0F;
        this.body.xRot = kneel * 0.3F;
        this.head.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.head.xRot = headPitch * Mth.DEG_TO_RAD * 0.6F;

        // Hanging robe strips sway on the float clock.
        for (int i = 0; i < strips.length; i++) {
            this.strips[i].xRot = Mth.sin(age * 0.06F + i * 1.3F) * 0.18F;
        }

        // Lantern chain: drag-lag swing (each segment lags the one above it).
        for (int k = 0; k < chain.length; k++) {
            this.chain[k].zRot = Mth.sin(age * 0.07F - k * 0.45F) * 0.3F;
            this.chain[k].xRot = Mth.sin(age * 0.055F - k * 0.4F) * 0.12F;
        }
        this.lantern.zRot = Mth.sin(age * 0.07F - 3.0F * 0.45F) * 0.12F;

        // --- oar + arm poses ---
        // Rowing idle: the oar pulls in the same slow cadence as the Deckhand crew.
        float row = Mth.sin(age * 0.08F);
        float oarXRot = -0.7F + row * 0.35F;
        float oarZRot = 0.15F;
        float oarX = OAR_BONE_X;
        float oarY = OAR_BONE_Y;
        float armRightXRot = -1.0F + row * 0.3F;
        float armLeftXRot = -0.8F + row * 0.3F;
        float armZ = 0.0F;

        // P3 planted: vertical beside him, blade to the deck (bottom of the 36px shaft at
        // ground: pivot must sit 18px up → body-space y = 9 with the kneel-free pivot).
        oarXRot = Mth.lerp(plant, oarXRot, 0.0F);
        oarZRot = Mth.lerp(plant, oarZRot, 0.0F);
        oarX = Mth.lerp(plant, oarX, 9.0F);
        oarY = Mth.lerp(plant, oarY, 9.0F);
        armRightXRot = Mth.lerp(plant, armRightXRot, -0.4F);
        armLeftXRot = Mth.lerp(plant, armLeftXRot, -0.5F);
        armZ = Mth.lerp(plant, armZ, -0.25F);

        // Telegraph: raise the oar overhead for the 25t windup (applied last — wins).
        oarXRot = Mth.lerp(raise, oarXRot, -2.5F);
        oarZRot = Mth.lerp(raise, oarZRot, 0.0F);
        oarX = Mth.lerp(raise, oarX, OAR_BONE_X);
        oarY = Mth.lerp(raise, oarY, OAR_BONE_Y - 4.0F);
        armRightXRot = Mth.lerp(raise, armRightXRot, -2.6F);
        armLeftXRot = Mth.lerp(raise, armLeftXRot, -2.6F);

        // Kneeling folds the arms down over the planted-or-idle pose.
        armRightXRot = Mth.lerp(kneel, armRightXRot, -0.25F);
        armLeftXRot = Mth.lerp(kneel, armLeftXRot, -0.25F);
        oarXRot = Mth.lerp(kneel, oarXRot, -1.45F);
        oarY = Mth.lerp(kneel, oarY, OAR_BONE_Y + 7.0F);

        // Scripted death collapse (deathTime > 0; the renderer suppresses the vanilla
        // sideways flip): he sinks upright with the oar planted — forced here off the
        // death clock too, in case the synced plant flag was lost to a mid-death reload —
        // while the skull bows onto the chest and the arms slip off the shaft.
        float death = entity.deathProgress(partialTick);
        if (death > 0.0F) {
            float sag = death * death; // Ease-in: the body settles as the sea takes it.
            float plantOut = Math.max(plant, death);
            oarXRot = Mth.lerp(plantOut, oarXRot, 0.0F);
            oarZRot = Mth.lerp(plantOut, oarZRot, 0.0F);
            oarX = Mth.lerp(plantOut, oarX, 9.0F);
            oarY = Mth.lerp(plantOut, oarY, 9.0F);
            this.head.xRot += sag * 0.7F;
            this.body.xRot += sag * 0.12F;
            armRightXRot = Mth.lerp(sag, armRightXRot, 0.15F);
            armLeftXRot = Mth.lerp(sag, armLeftXRot, 0.1F);
            armZ = Mth.lerp(sag, armZ, -0.05F);
        }

        this.oar.xRot = oarXRot;
        this.oar.zRot = oarZRot;
        this.oar.x = oarX;
        this.oar.y = oarY;
        this.armRight.xRot = armRightXRot;
        this.armLeft.xRot = armLeftXRot;
        this.armRight.zRot = armZ;
        this.armLeft.zRot = -armZ;
    }

    /**
     * Renders ONLY the emissive parts (fullbright {@code RenderType.eyes}) while keeping
     * every ancestor transform: everything else gets {@code skipDraw} for one draw of the
     * tree (Gazer/Herald pattern). The eye slit always burns; the lantern flame burns
     * while {@code flameLit} (it gutters out during the death collapse); the lantern
     * housing joins the pass while the Lantern Gaze mark is active.
     */
    public void renderEmissive(PoseStack poseStack, VertexConsumer buffer, int packedLight, int packedOverlay,
            boolean includeLantern, boolean flameLit) {
        for (ModelPart part : allParts) {
            part.skipDraw = true;
        }
        this.eyes.skipDraw = false;
        if (flameLit) {
            this.flame.skipDraw = false;
        }
        if (includeLantern) {
            this.lantern.skipDraw = false;
        }
        this.root.render(poseStack, buffer, packedLight, packedOverlay);
        for (ModelPart part : allParts) {
            part.skipDraw = false;
        }
    }
}
