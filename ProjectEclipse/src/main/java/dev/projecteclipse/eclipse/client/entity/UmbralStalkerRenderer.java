package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.UmbralStalkerEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.MobRenderer;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/** Umbral Stalker renderer — the 11-cube quadruped; shard glow lives in the texture. */
@OnlyIn(Dist.CLIENT)
public class UmbralStalkerRenderer extends MobRenderer<UmbralStalkerEntity, UmbralStalkerModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/umbral_stalker.png");

    public UmbralStalkerRenderer(EntityRendererProvider.Context context) {
        super(context, new UmbralStalkerModel(context.bakeLayer(EclipseEntityRenderers.UMBRAL_STALKER_LAYER)), 0.6F);
    }

    @Override
    public ResourceLocation getTextureLocation(UmbralStalkerEntity entity) {
        return TEXTURE;
    }
}
