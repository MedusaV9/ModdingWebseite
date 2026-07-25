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
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Gazer model — 6 cubes on a 64x64 texture ({@code docs/uv/gazer.md}): cloak 10x18x6
 * floating 6px above the ground, shoulder mantle 12x3x8, hood 8x8x8 (pivot 18px up),
 * emissive face inset 6x6x1 (re-rendered by {@code GazerRenderer.EyesLayer} with
 * {@code RenderType.eyes}), and two 3x8x1 hem tatters.
 *
 * <p>MOB-AMBIENT face rig: two 1x2 iris pips ({@code iris_left/right}, children of the
 * face — they join the emissive pass) sit proud inside the mask's hollow eye slits, and
 * two cloth eyelids ({@code lid_top/bottom}, children of the hood — skipped from the
 * emissive pass) rest as slivers at the face rim and y-scale shut over it.</p>
 *
 * <p>Anim: whole-body bob {@code sin(age*0.06)*0.8px}, tatter sway
 * {@code xRot = sin(age*0.1 + phase)*0.15}, hood (and the face with it) yaw-tracking the
 * look target via {@code netHeadYaw}. Iris pips dilate (scale up to ~1.9x) as the nearest
 * player's view vector locks onto the gazer — the same dot math the server's
 * {@code VanishWhenSeenGoal} uses — with a faint whisper-rhythm pulse otherwise; the lids
 * blink shut every ~5.5s (phase-salted per entity id) but never while being stared at:
 * the watched gazer refuses to blink.</p>
 */
@OnlyIn(Dist.CLIENT)
public class GazerModel extends HierarchicalModel<GazerEntity> {
    /** View-dot span mapped to iris dilation 0..1 (SEEN_DOT 0.985 = fully dilated). */
    private static final double DILATE_DOT_MIN = 0.90D;
    private static final double DILATE_DOT_MAX = 0.985D;
    private static final float BLINK_PERIOD_TICKS = 110.0F;
    private static final float BLINK_CLOSE_TICKS = 7.0F;
    /** Resting lid sliver (a hint of cloth at the mask rim, not a visible lid). */
    private static final float LID_REST_SCALE = 0.08F;

    private final ModelPart root;
    private final ModelPart bone;
    private final ModelPart cloak;
    private final ModelPart mantle;
    private final ModelPart hood;
    private final ModelPart face;
    private final ModelPart irisLeft;
    private final ModelPart irisRight;
    private final ModelPart lidTop;
    private final ModelPart lidBottom;
    private final ModelPart tatterLeft;
    private final ModelPart tatterRight;

    public GazerModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the gazer_root bone.
        this.bone = root.getChild("gazer_root");
        ModelPart bone = this.bone;
        this.cloak = bone.getChild("cloak");
        this.mantle = bone.getChild("mantle");
        this.hood = bone.getChild("hood");
        this.face = this.hood.getChild("face");
        this.irisLeft = this.face.getChild("iris_left");
        this.irisRight = this.face.getChild("iris_right");
        this.lidTop = this.hood.getChild("lid_top");
        this.lidBottom = this.hood.getChild("lid_bottom");
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
        PartDefinition face = hood.addOrReplaceChild("face", CubeListBuilder.create()
                .texOffs(32, 16).addBox(-3.0F, -7.0F, -4.25F, 6.0F, 6.0F, 1.0F),
                PartPose.ZERO);
        // Iris pips: 1x2 violet-hot pupils proud inside the mask's hollow eye slits
        // (slit centers x ±1.5, y -4). Pivoted at their own centers so scale = dilation.
        face.addOrReplaceChild("iris_left", CubeListBuilder.create()
                .texOffs(46, 16).addBox(-0.5F, -1.0F, -4.5F, 1.0F, 2.0F, 1.0F),
                PartPose.offset(1.5F, -4.0F, 0.0F));
        face.addOrReplaceChild("iris_right", CubeListBuilder.create()
                .texOffs(46, 16).addBox(-0.5F, -1.0F, -4.5F, 1.0F, 2.0F, 1.0F),
                PartPose.offset(-1.5F, -4.0F, 0.0F));
        // Eyelids: hood-cloth shutters pivoted at the face rim; yScale 0.08 rest sliver,
        // 1.0 = blink shut (they sit proud of the iris pips, so a blink occludes the glow).
        hood.addOrReplaceChild("lid_top", CubeListBuilder.create()
                .texOffs(44, 24).addBox(-3.5F, 0.0F, -4.75F, 7.0F, 3.0F, 1.0F),
                PartPose.offset(0.0F, -7.2F, 0.0F));
        hood.addOrReplaceChild("lid_bottom", CubeListBuilder.create()
                .texOffs(44, 28).addBox(-3.5F, -3.0F, -4.75F, 7.0F, 3.0F, 1.0F),
                PartPose.offset(0.0F, -0.8F, 0.0F));
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
        // Bob the gazer_root bone (baked pivot y=24 = ground) — NOT the layer root, whose
        // extra +24px used to sink the whole model 1.5 blocks into the ground.
        this.bone.y = 24.0F - Mth.sin(ageInTicks * 0.06F) * 0.8F;
        this.hood.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.tatterLeft.xRot = Mth.sin(ageInTicks * 0.1F) * 0.15F;
        this.tatterRight.xRot = Mth.sin(ageInTicks * 0.1F + (float) Math.PI) * 0.15F;

        // Iris dilation: same view-dot math as the server's VanishWhenSeenGoal — the pips
        // swell as the nearest player's gaze locks on (0 at dot 0.90 -> full at 0.985).
        float dilate = 0.0F;
        Player nearest = entity.level().getNearestPlayer(entity, 64.0D);
        if (nearest != null) {
            Vec3 look = nearest.getViewVector(1.0F).normalize();
            Vec3 toGazer = new Vec3(entity.getX() - nearest.getX(),
                    entity.getEyeY() - nearest.getEyeY(),
                    entity.getZ() - nearest.getZ()).normalize();
            dilate = (float) Mth.clamp(
                    (look.dot(toGazer) - DILATE_DOT_MIN) / (DILATE_DOT_MAX - DILATE_DOT_MIN), 0.0D, 1.0D);
        }
        // Blink cycle (phase-salted per entity id so a pair never blinks in sync) —
        // suppressed while stared at: the watched gazer refuses to blink.
        float blinkTime = (ageInTicks + (entity.getId() % 89) * 4.7F) % BLINK_PERIOD_TICKS;
        float blink = blinkTime >= 0.0F && blinkTime < BLINK_CLOSE_TICKS
                ? Mth.sin((float) Math.PI * blinkTime / BLINK_CLOSE_TICKS)
                : 0.0F;
        blink *= 1.0F - dilate;

        float pulse = Mth.sin(ageInTicks * 0.11F) * 0.08F; // whisper-rhythm micro pulse
        float irisScale = 1.0F + pulse + dilate * 0.9F - blink * 0.4F;
        this.irisLeft.xScale = irisScale;
        this.irisLeft.yScale = irisScale;
        this.irisRight.xScale = irisScale;
        this.irisRight.yScale = irisScale;
        float lidScale = LID_REST_SCALE + (1.0F - LID_REST_SCALE) * blink;
        this.lidTop.yScale = lidScale;
        this.lidBottom.yScale = lidScale;
    }

    /**
     * Renders ONLY the face cube + iris pips (fullbright, {@code RenderType.eyes}) while
     * keeping every ancestor transform: all other parts get {@code skipDraw} for one draw
     * of the tree. The cloth lids are cloth, not glow — they stay in the albedo pass and
     * occlude the face when blinking (they sit proud of it in z).
     */
    public void renderFaceEmissive(PoseStack poseStack, VertexConsumer buffer, int packedLight, int packedOverlay) {
        this.cloak.skipDraw = true;
        this.mantle.skipDraw = true;
        this.hood.skipDraw = true;
        this.lidTop.skipDraw = true;
        this.lidBottom.skipDraw = true;
        this.tatterLeft.skipDraw = true;
        this.tatterRight.skipDraw = true;
        this.root.render(poseStack, buffer, packedLight, packedOverlay);
        this.cloak.skipDraw = false;
        this.mantle.skipDraw = false;
        this.hood.skipDraw = false;
        this.lidTop.skipDraw = false;
        this.lidBottom.skipDraw = false;
        this.tatterLeft.skipDraw = false;
        this.tatterRight.skipDraw = false;
    }
}
