package dev.projecteclipse.eclipse.client.entity;

import java.util.List;

import com.mojang.blaze3d.vertex.PoseStack;
import com.mojang.blaze3d.vertex.VertexConsumer;

import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
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
 * Herald model — 26 cubes on a 128×128 texture ({@code docs/uv/herald.md}), all procedural
 * per spec §2.1: core 12×12×12 floating at pivot (0,40,0), emissive innerEye 6×6×6
 * (protrudes 1px from the core's front face; re-rendered fullbright by
 * {@code HeraldRenderer.EmissiveLayer}), 8 corona shard wedges 2×6×2 on a rotating ring
 * bone at r=14px, and 4 tentacle chains × 4 segments (2×6×2, chained pivots) hanging from
 * the core's underside corners.
 *
 * <p>Anim (age = the entity's smooth clock, ×2 speed in P3): ring {@code yRot = age*0.05};
 * shard i {@code y = sin(age*0.1 + i*π/4)*2px} plus the P3 tilt-out
 * ({@code zRot} lerped to 0.6 — each shard's local X points radially outward, so zRot tips
 * its top away from the ring); tentacle segment k {@code xRot = sin(age*0.09 + k*0.6)*0.25};
 * core bob {@code sin(age*0.06)*1.2px} (ring slightly out of phase). Detached corona shards
 * (P3, {@code getShardsLeft()}) are hidden.</p>
 */
@OnlyIn(Dist.CLIENT)
public class HeraldModel extends HierarchicalModel<HeraldEntity> {
    /** Ring bone radius in pixels (spec: r=14px). */
    private static final float RING_RADIUS = 14.0F;
    private static final float CORE_PIVOT_Y = -40.0F; // 40px above ground (root at y=24).

    private final ModelPart root;
    private final ModelPart core;
    private final ModelPart innerEye;
    private final ModelPart ring;
    private final ModelPart[] shards = new ModelPart[HeraldEntity.CORONA_SHARDS];
    private final ModelPart[][] tentacles = new ModelPart[4][4];
    private final List<ModelPart> allParts;

    public HeraldModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the herald_root bone.
        ModelPart bone = root.getChild("herald_root");
        this.core = bone.getChild("core");
        this.innerEye = this.core.getChild("inner_eye");
        this.ring = bone.getChild("ring");
        for (int i = 0; i < shards.length; i++) {
            this.shards[i] = this.ring.getChild("shard" + i);
        }
        for (int t = 0; t < 4; t++) {
            ModelPart parent = this.core;
            for (int k = 0; k < 4; k++) {
                parent = parent.getChild("tentacle" + t + "_seg" + k);
                this.tentacles[t][k] = parent;
            }
        }
        this.allParts = root.getAllParts().toList();
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("herald_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 24.0F, 0.0F));
        // Core 12x12x12 centered on the floating pivot (0,40,0) above ground.
        PartDefinition core = root.addOrReplaceChild("core", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-6.0F, -6.0F, -6.0F, 12.0F, 12.0F, 12.0F),
                PartPose.offset(0.0F, CORE_PIVOT_Y, 0.0F));
        // Inner eye 6x6x6: seated in the core, front face protruding 1px (z -7..-1).
        core.addOrReplaceChild("inner_eye", CubeListBuilder.create()
                .texOffs(48, 0).addBox(-3.0F, -3.0F, -7.0F, 6.0F, 6.0F, 6.0F),
                PartPose.ZERO);
        // Corona ring bone (no cube) carrying the 8 shard wedges at r=14px every 45°.
        PartDefinition ring = root.addOrReplaceChild("ring", CubeListBuilder.create(),
                PartPose.offset(0.0F, CORE_PIVOT_Y, 0.0F));
        for (int i = 0; i < HeraldEntity.CORONA_SHARDS; i++) {
            float angle = i * Mth.PI / 4.0F;
            // yRot = -angle points each shard's local +X radially outward, so the P3
            // tilt-out is a plain zRot on every shard.
            ring.addOrReplaceChild("shard" + i, CubeListBuilder.create()
                    .texOffs(i * 8, 32).addBox(-1.0F, -3.0F, -1.0F, 2.0F, 6.0F, 2.0F),
                    PartPose.offsetAndRotation(
                            Mth.cos(angle) * RING_RADIUS, 0.0F, Mth.sin(angle) * RING_RADIUS,
                            0.0F, -angle, 0.0F));
        }
        // 4 tentacle chains x 4 segments, hanging from the core's underside corners.
        float[][] anchors = {{-3.5F, -3.5F}, {3.5F, -3.5F}, {3.5F, 3.5F}, {-3.5F, 3.5F}};
        for (int t = 0; t < 4; t++) {
            PartDefinition parent = core;
            for (int k = 0; k < 4; k++) {
                parent = parent.addOrReplaceChild("tentacle" + t + "_seg" + k, CubeListBuilder.create()
                        .texOffs((t * 4 + k) * 8, 44).addBox(-1.0F, 0.0F, -1.0F, 2.0F, 6.0F, 2.0F),
                        k == 0 ? PartPose.offset(anchors[t][0], 6.0F, anchors[t][1])
                               : PartPose.offset(0.0F, 6.0F, 0.0F));
            }
        }
        return LayerDefinition.create(mesh, 128, 128);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(HeraldEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        // ageInTicks = tickCount + partialTick; recover the fraction for the smooth clock.
        float partialTick = ageInTicks - entity.tickCount;
        float age = entity.animAge(partialTick);
        float tilt = entity.shardTilt(partialTick);

        // Core bob + subtle look-tracking of the current target.
        this.core.y = CORE_PIVOT_Y + Mth.sin(age * 0.06F) * 1.2F;
        this.core.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.core.xRot = headPitch * Mth.DEG_TO_RAD * 0.5F;

        // Corona: ring spin, per-shard bob, P3 tilt-out, detached shards hidden.
        this.ring.yRot = age * 0.05F;
        this.ring.y = CORE_PIVOT_Y + Mth.sin(age * 0.06F + 0.8F) * 1.0F;
        int shardsLeft = entity.getShardsLeft();
        for (int i = 0; i < shards.length; i++) {
            this.shards[i].visible = i < shardsLeft;
            this.shards[i].y = Mth.sin(age * 0.1F + i * Mth.PI / 4.0F) * 2.0F;
            this.shards[i].zRot = tilt;
        }

        // Tentacles: whip-lag down the chain (phase shifts by segment index).
        for (int t = 0; t < 4; t++) {
            for (int k = 0; k < 4; k++) {
                this.tentacles[t][k].xRot = Mth.sin(age * 0.09F + k * 0.6F) * 0.25F;
            }
        }

        // Scripted death collapse (deathTime > 0; the renderer suppresses the vanilla
        // sideways flip): the core keels forward and sinks toward the dais, the corona
        // ring sags below it while the surviving shards tip outward, and the tentacle
        // whip dies to a limp hang. The server detaches shards as it plays the crashes,
        // so the synced shardsLeft already blanks them out one by one.
        float death = entity.deathProgress(partialTick);
        if (death > 0.0F) {
            float sag = death * death; // Ease-in: the wreck accelerates as it gives up.
            this.core.y += sag * 30.0F;
            this.core.xRot += sag * 0.25F;
            this.ring.y += sag * 34.0F;
            for (ModelPart shard : shards) {
                shard.zRot += sag * 0.8F;
            }
            for (int t = 0; t < 4; t++) {
                for (int k = 0; k < 4; k++) {
                    this.tentacles[t][k].xRot *= 1.0F - death;
                }
            }
        }
    }

    /**
     * Renders ONLY the emissive parts (fullbright {@code RenderType.eyes}) while keeping
     * every ancestor transform: everything else gets {@code skipDraw} for one draw of the
     * tree (Gazer pattern). The corona shards join the pass while a volley telegraph is
     * running ("shards glow"), otherwise only the inner eye burns.
     */
    public void renderEmissive(PoseStack poseStack, VertexConsumer buffer, int packedLight, int packedOverlay,
            boolean includeShards) {
        for (ModelPart part : allParts) {
            part.skipDraw = true;
        }
        this.innerEye.skipDraw = false;
        if (includeShards) {
            for (ModelPart shard : shards) {
                shard.skipDraw = false;
            }
        }
        this.root.render(poseStack, buffer, packedLight, packedOverlay);
        for (ModelPart part : allParts) {
            part.skipDraw = false;
        }
    }
}
