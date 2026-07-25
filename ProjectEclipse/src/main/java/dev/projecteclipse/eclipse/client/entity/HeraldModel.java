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
 * Herald model — 33 cubes on a 128×128 UV sheet painted at 2× (256×256 png,
 * {@code docs/uv/herald.md}), all procedural per spec §2.1: core 12×12×12 floating at
 * pivot (0,40,0), emissive innerEye 6×6×6 (protrudes 1px from the core's front face;
 * re-rendered fullbright by {@code HeraldRenderer.EmissiveLayer}), 4 crown spikes 1×5×1
 * jutting from the core's top corners, 8 corona shard wedges 2×6×2 on a rotating ring
 * bone at r=14px, 3 small floating shards 1×3×1 on a counter-rotating inner {@code halo}
 * bone at r=9px, and 4 tentacle chains × 4 segments (2×6×2, chained pivots) hanging from
 * the core's underside corners.
 *
 * <p>Anim (age = the entity's smooth clock, ×2 speed in P3): ring {@code yRot = age*0.05}
 * (+ the accumulated telegraph spin-up / volley recoil kick); shard i
 * {@code y = sin(age*0.1 + i*π/4)*2px} with a breathing amplitude, plus the P3 tilt-out
 * ({@code zRot} lerped to 0.6 — each shard's local X points radially outward, so zRot tips
 * its top away from the ring); the halo counter-spins and its shards gather inward during
 * a volley telegraph (summon gesture) and get flung back out by the recoil; tentacle
 * segment k whips {@code xRot = sin(age*0.09 + k*0.6)*0.25} with a per-chain phase offset
 * and curls up into the telegraph claw; the core bob breathes via a subtle scale pulse;
 * a phase-break ROAR ({@code roarAmount}) rears the core back, flares the crown (which
 * joins the emissive pass) and splays every tentacle. Detached corona shards (P3,
 * {@code getShardsLeft()}) are hidden; the death collapse staggers — tentacles die
 * chain-by-chain, crown spikes keel over one by one, halo shards drop away and the core
 * sinks in three lurches.</p>
 */
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

    @Override
    public void setupAnim(HeraldEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        // ageInTicks = tickCount + partialTick; recover the fraction for the smooth clock.
        float partialTick = ageInTicks - entity.tickCount;
        float age = entity.animAge(partialTick);
        float tilt = entity.shardTilt(partialTick);
        float gesture = entity.telegraphAmount(partialTick);
        float kick = entity.volleyKick(partialTick);
        float roar = entity.roarAmount(partialTick);
        float death = entity.deathProgress(partialTick);

        // Core bob + a subtle glass "breathing" scale pulse + look-tracking; the summon
        // gesture leans the core toward its target, the volley recoil flinches it back,
        // the phase-break roar rears it up and swells it.
        this.core.y = CORE_PIVOT_Y + Mth.sin(age * 0.06F) * 1.2F - roar * 4.0F;
        float breathe = 1.0F + Mth.sin(age * 0.023F) * 0.012F + roar * 0.05F;
        this.core.xScale = breathe;
        this.core.yScale = breathe;
        this.core.zScale = breathe;
        this.core.yRot = netHeadYaw * Mth.DEG_TO_RAD;
        this.core.xRot = headPitch * Mth.DEG_TO_RAD * 0.5F
                + gesture * 0.12F - kick * 0.3F - roar * 0.5F;

        // Crown spikes: independent slow shimmer on the base outward lean; the summon
        // gesture focuses them slightly inward, the roar + recoil flare them out and up.
        // Personality micro-beat (REPASS-MOB): every ~16 s the shards briefly RE-ORDER —
        // a staggered pop-and-settle wave runs around the crown (each spike hops in turn,
        // momentarily swapping height ranks), gated out by the roar and the summon.
        float shuffleClock = age % 320.0F;
        for (int i = 0; i < crown.length; i++) {
            float shufflePhase = shuffleClock - i * 6.0F;
            float pulse = 0.0F;
            if (shufflePhase > 0.0F && shufflePhase < 18.0F) {
                pulse = Mth.sin(shufflePhase / 18.0F * Mth.PI)
                        * (1.0F - roar) * (1.0F - gesture) * (1.0F - death);
            }
            float flare = 0.28F + roar * 0.55F + kick * 0.25F - gesture * 0.1F
                    + Mth.sin(age * 0.05F + i * 1.57F) * 0.04F
                    + pulse * 0.16F;
            boolean east = i == 1 || i == 2;  // crown anchors with x > 0
            boolean south = i == 2 || i == 3; // crown anchors with z > 0
            this.crown[i].zRot = east ? flare : -flare;
            this.crown[i].xRot = south ? -flare : flare;
            this.crown[i].y = -6.0F - roar * 1.5F - pulse * 2.2F;
        }

        // Corona: ring spin (+ the accumulated telegraph spin-up / recoil snap), per-shard
        // bob with a slow breathing amplitude, P3 tilt-out, detached shards hidden.
        float spinExtra = entity.ringSpinExtra(partialTick);
        this.ring.yRot = age * 0.05F + spinExtra;
        this.ring.y = CORE_PIVOT_Y + Mth.sin(age * 0.06F + 0.8F) * 1.0F;
        int shardsLeft = entity.getShardsLeft();
        float bobAmp = 2.0F + Mth.sin(age * 0.021F) * 0.5F;
        for (int i = 0; i < shards.length; i++) {
            this.shards[i].visible = i < shardsLeft;
            this.shards[i].y = Mth.sin(age * 0.1F + i * Mth.PI / 4.0F) * bobAmp;
            // The gesture tips the corona IN toward the core (gathering), the recoil
            // flares it back out; both ride on top of the P3 tilt-out.
            this.shards[i].zRot = tilt - gesture * 0.12F + kick * 0.25F;
        }

        // Halo: counter-spins under the corona; the summon gesture GATHERS the small
        // floating shards inward toward the core (the volley's "ammo") and the recoil
        // flings them back out with an overshoot.
        this.halo.yRot = -age * 0.085F - spinExtra * 0.6F;
        this.halo.y = CORE_PIVOT_Y + Mth.sin(age * 0.07F + 2.1F) * 1.4F;
        float haloRadius = HALO_RADIUS - gesture * 3.5F + kick * 2.5F;
        for (int i = 0; i < haloShards.length; i++) {
            float angle = i * Mth.PI * 2.0F / 3.0F;
            this.haloShards[i].visible = true;
            this.haloShards[i].x = Mth.cos(angle) * haloRadius;
            this.haloShards[i].z = Mth.sin(angle) * haloRadius;
            this.haloShards[i].y = Mth.sin(age * 0.13F + i * 2.09F) * 1.5F;
            this.haloShards[i].zRot = gesture * 0.4F;
        }

        // Tentacles: whip-lag down the chain, now with a per-chain phase offset (the four
        // chains no longer metronome in sync) and a secondary cross-sway; the summon
        // gesture curls them up into a claw, the roar splays them symmetrically outward.
        for (int t = 0; t < 4; t++) {
            float chainPhase = t * 1.57F;
            float outX = (t == 1 || t == 2) ? 1.0F : -1.0F; // anchor x sign
            float outZ = (t >= 2) ? 1.0F : -1.0F;           // anchor z sign
            for (int k = 0; k < 4; k++) {
                float splay = roar * Math.max(0.0F, 0.38F - k * 0.07F);
                this.tentacles[t][k].xRot = Mth.sin(age * 0.09F + k * 0.6F + chainPhase) * 0.25F
                        + gesture * (-0.22F - 0.13F * k)
                        + outZ * splay * 0.7F;
                this.tentacles[t][k].zRot = Mth.cos(age * 0.067F + k * 0.45F + chainPhase * 1.3F) * 0.07F
                        + outX * splay;
            }
        }

        // Scripted death collapse (deathTime > 0; the renderer suppresses the vanilla
        // sideways flip), STAGGERED so the wreck gives way joint by joint: the core sinks
        // in three eased lurches while it keels forward, the corona ring sags below it
        // with the surviving shards tipping outward, the crown spikes keel over one by
        // one, the halo shards drop away and vanish, and the tentacle whip dies
        // chain-by-chain to a limp hang. The server detaches corona shards as it plays
        // the crashes, so the synced shardsLeft already blanks those out one by one.
        if (death > 0.0F) {
            float seg = death * 3.0F;
            int step = (int) seg;
            float f = seg - step;
            float lurch = Math.min(1.0F, (step + f * f * (3.0F - 2.0F * f)) / 3.0F);
            float sag = death * death; // Ease-in: the wreck accelerates as it gives up.
            this.core.y += lurch * lurch * 30.0F;
            this.core.xRot += sag * 0.25F;
            this.ring.y += sag * 34.0F;
            for (ModelPart shard : shards) {
                shard.zRot += sag * 0.8F;
            }
            for (int i = 0; i < crown.length; i++) {
                float die = Mth.clamp((death - (0.1F + i * 0.12F)) / 0.25F, 0.0F, 1.0F);
                float keel = die * die * 1.1F;
                this.crown[i].zRot += (i == 1 || i == 2) ? keel : -keel;
            }
            for (int i = 0; i < haloShards.length; i++) {
                float die = Mth.clamp((death - (0.05F + i * 0.15F)) / 0.2F, 0.0F, 1.0F);
                this.haloShards[i].y += die * die * 26.0F;
                if (die >= 1.0F) {
                    this.haloShards[i].visible = false;
                }
            }
            for (int t = 0; t < 4; t++) {
                float die = Mth.clamp((death - t * 0.13F) / 0.3F, 0.0F, 1.0F);
                for (int k = 0; k < 4; k++) {
                    this.tentacles[t][k].xRot *= 1.0F - die;
                    this.tentacles[t][k].zRot *= 1.0F - die;
                }
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
