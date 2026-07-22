package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.DeckhandEntity;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import net.minecraft.client.renderer.entity.MobRenderer;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/** Deckhand renderer — the 7-cube hunched rower on the ghost ship benches. */
@OnlyIn(Dist.CLIENT)
public class DeckhandRenderer extends MobRenderer<DeckhandEntity, DeckhandModel> {
    public static final ResourceLocation TEXTURE =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/entity/deckhand.png");

    public DeckhandRenderer(EntityRendererProvider.Context context) {
        super(context, new DeckhandModel(context.bakeLayer(EclipseEntityRenderers.DECKHAND_LAYER)), 0.4F);
    }

    @Override
    public ResourceLocation getTextureLocation(DeckhandEntity entity) {
        return TEXTURE;
    }
}
