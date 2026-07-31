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
 * Old handcrafted Herald model (33 cubes, vanilla {@code HierarchicalModel}).
 *
 * @deprecated MA3 GeckoLib conversion: the live Herald renders through
 *             {@code HeraldGeoRenderer} + {@code geo/entity/herald.geo.json} /
 *             {@code animations/entity/herald.animation.json}, registered by
 *             {@code HeraldRenderers} at LOWEST priority (it overwrites the legacy
 *             {@code EclipseEntityRenderers} registration — the shared file's Herald
 *             lines are removed by the integrator, see MA3_HERALD_REPORT.md). This
 *             class only survives so the shared registration keeps compiling until
 *             then; the per-phase entity clock hooks it animated from are gone, so
 *             {@link #setupAnim} is a plain decoupled idle. NOTE:
 *             {@code textures/entity/herald.png} now holds the NEW 128x128 GeckoLib
 *             sheet — this fallback samples it with the old UV map and will smear if
 *             it ever draws.
 */
@Deprecated
@OnlyIn(Dist.CLIENT)
public class HeraldModel extends HierarchicalModel<HeraldEntity> {
    /** Ring bone radius in pixels (spec: r=14px). */
    private static final float RING_RADIUS = 14.0F;
    /** Inner floating-shard halo radius in pixels (counter-rotates under the corona). */
    private static final float HALO_RADIUS = 9.0F;
    private static final float CORE_PIVOT_Y = -40.0F; // 40px above ground (root at y=24).

    private final ModelPart root;
    private final ModelPart core;
    private final ModelPart innerEye;
    private final ModelPart ring;
    private final ModelPart[] shards = new ModelPart[HeraldEntity.CORONA_SHARDS];
    private final ModelPart[] crown = new ModelPart[4];
    private final ModelPart halo;
    private final ModelPart[] haloShards = new ModelPart[3];
    private final ModelPart[][] tentacles = new ModelPart[4][4];
    private final List<ModelPart> allParts;

    public HeraldModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the herald_root bone.
        ModelPart bone = root.getChild("herald_root");
        this.core = bone.getChild("core");
        this.innerEye = this.core.getChild("inner_eye");
        for (int i = 0; i < crown.length; i++) {
            this.crown[i] = this.core.getChild("crown" + i);
        }
        this.ring = bone.getChild("ring");
        for (int i = 0; i < shards.length; i++) {
            this.shards[i] = this.ring.getChild("shard" + i);
        }
        this.halo = bone.getChild("halo");
        for (int i = 0; i < haloShards.length; i++) {
            this.haloShards[i] = this.halo.getChild("halo" + i);
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
        // 4 crown spikes 1x5x1 on the core's top corners, tipped outward — children of
        // the core so they track its look; separate bones so the roar can flare them.
        float[][] crownAt = {{-4.0F, -4.0F}, {4.0F, -4.0F}, {4.0F, 4.0F}, {-4.0F, 4.0F}};
        for (int i = 0; i < 4; i++) {
            float lean = 0.28F;
            core.addOrReplaceChild("crown" + i, CubeListBuilder.create()
                    .texOffs(72 + i * 4, 0).addBox(-0.5F, -5.0F, -0.5F, 1.0F, 5.0F, 1.0F),
                    PartPose.offsetAndRotation(crownAt[i][0], -6.0F, crownAt[i][1],
                            crownAt[i][1] > 0.0F ? -lean : lean,
                            0.0F,
                            crownAt[i][0] > 0.0F ? lean : -lean));
        }
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
        // Inner halo bone (no cube): 3 small floating shards 1x3x1 at r=9px every 120°,
        // counter-rotating under the corona — the "ammo" the volley telegraph gathers.
        PartDefinition halo = root.addOrReplaceChild("halo", CubeListBuilder.create(),
                PartPose.offset(0.0F, CORE_PIVOT_Y, 0.0F));
        for (int i = 0; i < 3; i++) {
            float angle = i * Mth.PI * 2.0F / 3.0F;
            halo.addOrReplaceChild("halo" + i, CubeListBuilder.create()
                    .texOffs(72 + i * 4, 8).addBox(-0.5F, -1.5F, -0.5F, 1.0F, 3.0F, 1.0F),
                    PartPose.offsetAndRotation(
                            Mth.cos(angle) * HALO_RADIUS, 0.0F, Mth.sin(angle) * HALO_RADIUS,
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

    /**
     * Decoupled fallback idle: the per-phase smooth clock, telegraph gesture, roar and
     * death-collapse hooks this used to read moved into GeckoLib
     * ({@code herald.animation.json}) — only plain tick-time bob/spin and the synced
     * shard visibility remain, so the class compiles without the removed entity API.
     */
    @Override
    public void setupAnim(HeraldEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        this.core.y = CORE_PIVOT_Y + Mth.sin(ageInTicks * 0.06F) * 1.2F;
        this.core.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.core.xRot = headPitch * Mth.DEG_TO_RAD * 0.5F;
        this.ring.yRot = ageInTicks * 0.05F;
        int shardsLeft = entity.getShardsLeft();
        for (int i = 0; i < shards.length; i++) {
            this.shards[i].visible = i < shardsLeft;
            this.shards[i].y = Mth.sin(ageInTicks * 0.1F + i * Mth.PI / 4.0F) * 2.0F;
        }
        this.halo.yRot = -ageInTicks * 0.085F;
        for (int t = 0; t < 4; t++) {
            for (int k = 0; k < 4; k++) {
                this.tentacles[t][k].xRot = Mth.sin(ageInTicks * 0.09F + k * 0.6F + t * 1.57F) * 0.25F;
            }
        }
    }

    /**
     * Renders ONLY the emissive parts (fullbright {@code RenderType.eyes}) while keeping
     * every ancestor transform: everything else gets {@code skipDraw} for one draw of the
     * tree (Gazer pattern). The corona + halo shards join the pass while a volley
     * telegraph is running ("shards glow"), the crown spikes flare fullbright through the
     * phase-break roar, otherwise only the inner eye burns.
     */
    public void renderEmissive(PoseStack poseStack, VertexConsumer buffer, int packedLight, int packedOverlay,
            boolean includeShards, boolean includeCrown) {
        for (ModelPart part : allParts) {
            part.skipDraw = true;
        }
        this.innerEye.skipDraw = false;
        if (includeShards) {
            for (ModelPart shard : shards) {
                shard.skipDraw = false;
            }
            for (ModelPart shard : haloShards) {
                shard.skipDraw = false;
            }
        }
        if (includeCrown) {
            for (ModelPart spike : crown) {
                spike.skipDraw = false;
            }
        }
        this.root.render(poseStack, buffer, packedLight, packedOverlay);
        for (ModelPart part : allParts) {
            part.skipDraw = false;
        }
    }
}
