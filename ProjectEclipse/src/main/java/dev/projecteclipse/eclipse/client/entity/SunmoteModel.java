package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.entity.SunmoteEntity;
import net.minecraft.client.model.HierarchicalModel;
import net.minecraft.client.model.geom.ModelPart;
import net.minecraft.client.model.geom.PartPose;
import net.minecraft.client.model.geom.builders.CubeListBuilder;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.geom.builders.MeshDefinition;
import net.minecraft.client.model.geom.builders.PartDefinition;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Sunmote model — 2 cubes on a 32x32 texture ({@code docs/uv/sunmote.md}): a 2x2x2 core and
 * a 4x1x4 halo plate mounted at 45°. The whole model renders fullbright plus an additive
 * {@code RenderType.eyes} pass ({@code SunmoteRenderer}); the halo spins in place while the
 * orbit itself is entity-position-driven ({@code SunmoteEntity#tick}).
 */
@OnlyIn(Dist.CLIENT)
public class SunmoteModel extends HierarchicalModel<SunmoteEntity> {
    private static final float HALO_BASE_Y_ROT = (float) (Math.PI / 4.0D);

    private final ModelPart root;
    private final ModelPart halo;

    public SunmoteModel(ModelPart root) {
        this.root = root;
        this.halo = root.getChild("halo");
    }

    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot().addOrReplaceChild("sunmote_root", CubeListBuilder.create(),
                PartPose.offset(0.0F, 21.0F, 0.0F));
        root.addOrReplaceChild("core", CubeListBuilder.create()
                .texOffs(0, 0).addBox(-1.0F, -1.0F, -1.0F, 2.0F, 2.0F, 2.0F),
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
    }
}
