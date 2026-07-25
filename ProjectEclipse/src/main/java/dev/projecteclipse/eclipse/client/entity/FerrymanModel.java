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
 * Ferryman model — 24 cubes on a 128×128 UV sheet painted at 2× (256×256 png,
 * {@code docs/uv/ferryman.md}), all procedural per spec §2.2: floating robe 10×26×8 with
 * 4 hanging strips 2×6×1 plus 3 longer tatters 2×8×1, skull 7×7×7 under a 9×9×9 hood
 * (open front — the hood's north face is transparent in the skin), emissive eye slit
 * 5×2×1, arms 3×20×3, two-handed oar 2×2×36 (+ a 1×6×5 blade), and a 4×5×4 lantern
 * (crowned by a 3×1×3 cap) with a 2×2×2 emissive flame swinging off the left shoulder on
 * a 3-segment 1×4×1 chain whose joints carry alternating 2×2×1 link crosspieces.
 *
 * <p>Anim (age = the entity's smooth clock, ×1.4 in P3): float bob
 * {@code sin(age*0.05)*1.5px} under a slow two-layer breathing roll; chain segment k
 * drag-lag pendulum swing (amplitude grows down the chain and with deck drift speed,
 * {@code FerrymanEntity.swayBoost}); rowing-idle oar {@code xRot = -0.7 + sin(age*0.08)*0.35}.
 * Pose blends from the entity: telegraph raises the oar overhead with a coiled wind-up
 * ({@code raiseAmount} + a late-windup quiver), the sweep CONTACT whips the oar through a
 * one-shot arc with follow-through and eased recovery ({@code sweepSwing}), P2 kneels the
 * whole body ({@code kneelAmount}) with a heavy breathing loop, P3 plants the oar
 * vertically beside him ({@code plantAmount}; a running telegraph still lifts it — plant
 * is applied first, raise last). The death collapse folds the body toward the lantern
 * while the chain stills so the last light hangs plumb.</p>
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
    private final ModelPart[] tatters = new ModelPart[3];
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
        for (int i = 0; i < tatters.length; i++) {
            this.tatters[i] = this.body.getChild("tatter" + i);
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
        // 3 longer cloak tatters 2x8x1 (west/east flank + back center) — separate bones so
        // the lower cloak drags on its own slower, deeper cadence than the hem strips.
        float[][] tatterAt = {{-4.2F, 0.0F}, {4.2F, 0.0F}, {0.0F, 3.9F}};
        for (int i = 0; i < 3; i++) {
            body.addOrReplaceChild("tatter" + i, CubeListBuilder.create()
                    .texOffs(24 + i * 8, 76).addBox(-1.0F, 0.0F, -0.5F, 2.0F, 8.0F, 1.0F),
                    PartPose.offset(tatterAt[i][0], 13.0F, tatterAt[i][1]));
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
        // Each segment's lower joint carries a flat 2x2x1 link crosspiece, alternating
        // orientation 90° per segment so the chain reads as interlocked iron links.
        PartDefinition parent = body;
        for (int k = 0; k < 3; k++) {
            parent = parent.addOrReplaceChild("chain" + k, CubeListBuilder.create()
                    .texOffs(92 + k * 6, 36).addBox(-0.5F, 0.0F, -0.5F, 1.0F, 4.0F, 1.0F),
                    k == 0 ? PartPose.offset(6.5F, -11.0F, 1.5F) : PartPose.offset(0.0F, 4.0F, 0.0F));
            parent.addOrReplaceChild("link" + k, CubeListBuilder.create()
                    .texOffs(k * 8, 76).addBox(-1.0F, -1.0F, -0.5F, 2.0F, 2.0F, 1.0F),
                    PartPose.offsetAndRotation(0.0F, 3.5F, 0.0F,
                            0.0F, (k % 2 == 0) ? 0.0F : Mth.HALF_PI, 0.0F));
        }
        PartDefinition lantern = parent.addOrReplaceChild("lantern", CubeListBuilder.create()
                .texOffs(92, 44).addBox(-2.0F, 0.0F, -2.0F, 4.0F, 5.0F, 4.0F),
                PartPose.offset(0.0F, 4.0F, 0.0F));
        // Iron cap crown over the housing (the chain visually seats into it).
        lantern.addOrReplaceChild("cap", CubeListBuilder.create()
                .texOffs(48, 76).addBox(-1.5F, -1.0F, -1.5F, 3.0F, 1.0F, 3.0F),
                PartPose.ZERO);
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
        float boost = entity.swayBoost(partialTick);

        // Float bob under a two-layer breathing roll (slow list + slower counter-roll so
        // no two cycles repeat); kneeling drops the whole body toward the deck, hunches
        // it forward and swaps the idle bob for a heavier, slower breath.
        this.body.y = BODY_PIVOT_Y + Mth.sin(age * 0.05F) * 1.5F * (1.0F - kneel) + kneel * 11.0F;
        this.body.xRot = kneel * (0.3F + Mth.sin(age * 0.045F) * 0.045F);
        this.body.zRot = Mth.sin(age * 0.031F) * 0.02F + Mth.sin(age * 0.013F) * 0.008F;
        this.body.yRot = 0.0F;
        this.head.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        // Slow idle nod rides the breath; the kneel bows the skull (penitent read).
        this.head.xRot = headPitch * Mth.DEG_TO_RAD * 0.6F + Mth.sin(age * 0.043F) * 0.03F
                + kneel * 0.4F;

        // Hanging robe strips sway on the float clock; the longer tatters drag on a
        // slower, deeper cadence with a light flutter harmonic — both amplified while he
        // drifts across the deck (swayBoost).
        for (int i = 0; i < strips.length; i++) {
            this.strips[i].xRot = Mth.sin(age * 0.06F + i * 1.3F) * 0.18F * (1.0F + 0.6F * boost);
            this.strips[i].zRot = Mth.cos(age * 0.047F + i * 0.9F) * 0.06F;
        }
        for (int i = 0; i < tatters.length; i++) {
            this.tatters[i].xRot = Mth.sin(age * 0.042F + i * 2.1F) * 0.22F * (1.0F + 0.8F * boost)
                    + Mth.sin(age * 0.19F + i * 1.1F) * 0.035F;
            this.tatters[i].zRot = Mth.cos(age * 0.037F + i * 1.7F) * 0.1F;
        }

        // Lantern chain: pendulum drag-lag — amplitude GROWS down the chain (the bob
        // leads its pivot) and with drift speed, under a slow breathing modulation so the
        // swing never metronomes; the housing counter-swings against the last link
        // (inertia read).
        float breathe = 1.0F + 0.12F * Mth.sin(age * 0.013F);
        float speedAmp = (1.0F + 0.85F * boost) * breathe;
        for (int k = 0; k < chain.length; k++) {
            this.chain[k].zRot = Mth.sin(age * 0.07F - k * 0.45F) * (0.22F + 0.08F * k) * speedAmp;
            this.chain[k].xRot = Mth.sin(age * 0.055F - k * 0.4F) * (0.09F + 0.03F * k) * speedAmp;
        }
        this.lantern.zRot = -Mth.sin(age * 0.07F - 3.0F * 0.45F) * 0.14F * speedAmp;

        // --- oar + arm poses ---
        // Rowing idle: the oar pulls in the same slow cadence as the Deckhand crew.
        float row = Mth.sin(age * 0.08F);
        float oarXRot = -0.7F + row * 0.35F;
        float oarZRot = 0.15F;
        float oarX = OAR_BONE_X;
        float oarY = OAR_BONE_Y;
        float armRightXRot = -1.0F + row * 0.3F;
        float armLeftXRot = -0.8F + row * 0.3F;
        float armZ = Mth.sin(age * 0.05F) * 0.02F; // Breathing shoulder drift.

        // P3 planted: vertical beside him, blade to the deck (bottom of the 36px shaft at
        // ground: pivot must sit 18px up → body-space y = 9 with the kneel-free pivot).
        oarXRot = Mth.lerp(plant, oarXRot, 0.0F);
        oarZRot = Mth.lerp(plant, oarZRot, 0.0F);
        oarX = Mth.lerp(plant, oarX, 9.0F);
        oarY = Mth.lerp(plant, oarY, 9.0F);
        armRightXRot = Mth.lerp(plant, armRightXRot, -0.4F);
        armLeftXRot = Mth.lerp(plant, armLeftXRot, -0.5F);
        armZ = Mth.lerp(plant, armZ, -0.25F);

        // Telegraph ANTICIPATION: raise the oar overhead for the 25t windup (applied
        // last — wins) while the body screws down into the coil, the skull tips up at the
        // blade, and the held windup quivers just before release.
        oarXRot = Mth.lerp(raise, oarXRot, -2.5F);
        oarZRot = Mth.lerp(raise, oarZRot, 0.0F);
        oarX = Mth.lerp(raise, oarX, OAR_BONE_X);
        oarY = Mth.lerp(raise, oarY, OAR_BONE_Y - 4.0F);
        armRightXRot = Mth.lerp(raise, armRightXRot, -2.6F);
        armLeftXRot = Mth.lerp(raise, armLeftXRot, -2.6F);
        this.body.yRot -= raise * 0.28F;
        this.body.xRot += raise * 0.07F;
        this.head.xRot -= raise * 0.3F;
        float quiver = Math.max(0.0F, (raise - 0.85F) / 0.15F);
        oarZRot += quiver * Mth.sin(age * 1.5F) * 0.035F;

        // Kneeling folds the arms down over the planted-or-idle pose.
        armRightXRot = Mth.lerp(kneel, armRightXRot, -0.25F);
        armLeftXRot = Mth.lerp(kneel, armLeftXRot, -0.25F);
        oarXRot = Mth.lerp(kneel, oarXRot, -1.45F);
        oarY = Mth.lerp(kneel, oarY, OAR_BONE_Y + 7.0F);

        // Sweep CONTACT + RECOVERY: a one-shot whip on the telegraph's falling edge
        // (FerrymanEntity.sweepSwing) — the raised oar snaps down-and-across with the
        // body twisting into the follow-through (ease-out cubic, ~4t), then the whole
        // pose eases back to whatever the base blend wants (smoothstep, ~10t).
        float swing = entity.sweepSwing(partialTick);
        if (swing >= 0.0F) {
            float w;
            if (swing < 0.22F) {
                float c = swing / 0.22F;
                w = 1.0F - (1.0F - c) * (1.0F - c) * (1.0F - c);
            } else {
                float r = (swing - 0.22F) / 0.78F;
                w = 1.0F - r * r * (3.0F - 2.0F * r);
            }
            oarXRot = Mth.lerp(w, oarXRot, -0.1F); // Past horizontal: a full swing-through.
            oarZRot = Mth.lerp(w, oarZRot, -0.55F);
            armRightXRot = Mth.lerp(w, armRightXRot, -0.9F);
            armLeftXRot = Mth.lerp(w, armLeftXRot, -0.95F);
            this.body.yRot = Mth.lerp(w, this.body.yRot, 0.6F); // Follow-through twist.
            this.body.xRot += w * 0.1F;
        }

        // Scripted death collapse (deathTime > 0; the renderer suppresses the vanilla
        // sideways flip): the oar stays planted (forced off the death clock too, in case
        // the synced flag was lost to a mid-death reload) and the body folds INTO the
        // lantern — listing toward the chain shoulder, the skull turning to the last
        // light, the left arm reaching for it — while the chain swing stills and
        // counter-rotates the body's list so the lantern keeps hanging plumb.
        float death = entity.deathProgress(partialTick);
        if (death > 0.0F) {
            float sag = death * death; // Ease-in: the body settles as the sea takes it.
            float plantOut = Math.max(plant, death);
            oarXRot = Mth.lerp(plantOut, oarXRot, 0.0F);
            oarZRot = Mth.lerp(plantOut, oarZRot, 0.0F);
            oarX = Mth.lerp(plantOut, oarX, 9.0F);
            oarY = Mth.lerp(plantOut, oarY, 9.0F);
            this.head.xRot += sag * 0.7F;
            this.head.yRot = Mth.lerp(sag, this.head.yRot, 0.9F);
            this.body.xRot += sag * 0.12F;
            this.body.zRot += sag * 0.18F;
            armRightXRot = Mth.lerp(sag, armRightXRot, 0.15F);
            armLeftXRot = Mth.lerp(sag, armLeftXRot, -0.35F);
            armZ = Mth.lerp(sag, armZ, -0.05F);
            for (int k = 0; k < chain.length; k++) {
                this.chain[k].zRot *= 1.0F - death;
                this.chain[k].xRot *= 1.0F - death;
            }
            this.chain[0].zRot -= sag * 0.18F; // Cancels the body list: the light stays plumb.
            this.lantern.zRot *= 1.0F - death;
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
