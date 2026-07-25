package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.SunmoteEntity;
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
 * Sunmote model — 3 cubes on a 32x32 texture ({@code docs/uv/sunmote.md}): a 2x2x2 core,
 * a 1.4x1.4x1.4 {@code core_inner} kernel nested inside it, and a 4x1x4 halo plate mounted
 * at 45°. The whole model renders fullbright plus an additive {@code RenderType.eyes} pass
 * ({@code SunmoteRenderer}); the halo spins in place while the orbit itself is
 * entity-position-driven ({@code SunmoteEntity#tick}).
 *
 * <p>Pulse rhythm (MOB-AMBIENT): the kernel scale-breathes on a slow beat with a faster
 * shimmer harmonic — at each beat's peak it breaches the core's faces, so the mote reads
 * as a heart of daylight flaring through its shell. The core takes a subtle sympathetic
 * breath and the halo counter-bobs against the same beat.</p>
 */
@OnlyIn(Dist.CLIENT)
public class SunmoteModel extends HierarchicalModel<SunmoteEntity> {
    private static final float HALO_BASE_Y_ROT = (float) (Math.PI / 4.0D);

    private final ModelPart root;
    private final ModelPart core;
    private final ModelPart coreInner;
    private final ModelPart halo;

    public SunmoteModel(ModelPart root) {
        this.root = root;
        // bakeLayer() hands over the layer root, whose single child is the sunmote_root bone.
        ModelPart bone = root.getChild("sunmote_root");
        this.core = bone.getChild("core");
        this.coreInner = this.core.getChild("core_inner");
        this.halo = bone.getChild("halo");
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("sunmote_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 21.0F, 0.0F));
        PartDefinition core = root.addOrReplaceChild("core", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
                PartPose.ZERO);
        // Inner-core kernel: hidden inside the shell at rest, breaches it at pulse peaks.
        core.addOrReplaceChild("core_inner", CubeListBuilder.create()
                .texOffs(16, 0).addBox(-0.7F, -0.7F, -0.7F, 1.4F, 1.4F, 1.4F),
                PartPose.ZERO);
        root.addOrReplaceChild("halo", CubeListBuilder.create()
                .texOffs(0, 4).addBox(-2.0F, -0.5F, -2.0F, 4.0F, 1.0F, 4.0F),
                PartPose.rotation(0.0F, HALO_BASE_Y_ROT, 0.0F));
        return LayerDefinition.create(mesh, 32, 32);
    }

    @Override
    public ModelPart root() {
        return this.root;
    }

    @Override
    public void setupAnim(SunmoteEntity entity, float limbSwing, float limbSwingAmount, float ageInTicks,
            float netHeadYaw, float headPitch) {
        this.halo.yRot = HALO_BASE_Y_ROT + ageInTicks * 0.1F;
        // Heartbeat of daylight: slow beat + fast shimmer on the kernel (0.8..1.75x —
        // peaks breach the 2px shell), a sympathetic core breath, a halo counter-bob.
        float pulse = Mth.sin(ageInTicks * 0.18F) * 0.5F + 0.5F;
        float shimmer = Mth.sin(ageInTicks * 0.45F) * 0.5F + 0.5F;
        float inner = 0.8F + pulse * 0.75F + shimmer * 0.2F;
        this.coreInner.xScale = inner;
        this.coreInner.yScale = inner;
        this.coreInner.zScale = inner;
        float breath = 1.0F + pulse * 0.08F;
        this.core.xScale = breath;
        this.core.yScale = breath;
        this.core.zScale = breath;
        this.halo.y = Mth.sin(ageInTicks * 0.18F + (float) Math.PI) * 0.3F;
    }
}
