package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.TheOtherEntity;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.HumanoidMobRenderer;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The Other renders as a plain uniform-skinned humanoid — deliberately identical to how the
 * anonymized players look at a glance. This is a separate entity renderer with its OWN
 * texture copy ({@code textures/entity/the_other.png}: uniform skin + pure-black eyes +
 * faint purple face seam), so the {@code AbstractClientPlayerMixin} uniform-skin pipeline
 * stays completely untouched (regression guard, W10 task 4).
 */
@OnlyIn(Dist.CLIENT)
public class TheOtherRenderer extends HumanoidMobRenderer<TheOtherEntity, HumanoidModel<TheOtherEntity>> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/the_other.png");

    public TheOtherRenderer(EntityRendererProvider.Context context) {
        super(context, new HumanoidModel<>(context.bakeLayer(EclipseEntityRenderers.THE_OTHER_LAYER)), 0.5F);
    }

    @Override
    public ResourceLocation getTextureLocation(TheOtherEntity entity) {
        return TEXTURE;
    }
}
