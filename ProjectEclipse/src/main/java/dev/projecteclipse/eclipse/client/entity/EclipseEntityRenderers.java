package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import net.minecraft.client.model.HumanoidModel;
import net.minecraft.client.model.geom.ModelLayerLocation;
import net.minecraft.client.model.geom.builders.CubeDeformation;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.renderer.entity.ThrownItemRenderer;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Registers the layer definitions (mob cube models authored as code) and renderers for the
 * v2 custom mobs. The Other reuses vanilla humanoid geometry at 64x64 (player-skin UV
 * layout) so the doppelganger matches the uniform-skin players exactly; every other mob has
 * a bespoke model class in this package.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EclipseEntityRenderers {
    public static final ModelLayerLocation THE_OTHER_LAYER = layer("the_other");
    public static final ModelLayerLocation GAZER_LAYER = layer("gazer");
    public static final ModelLayerLocation UMBRAL_STALKER_LAYER = layer("umbral_stalker");
    public static final ModelLayerLocation SUNMOTE_LAYER = layer("sunmote");
    public static final ModelLayerLocation HERALD_LAYER = layer("herald");
    public static final ModelLayerLocation FERRYMAN_LAYER = layer("ferryman");

    private EclipseEntityRenderers() {}

    private static ModelLayerLocation layer(String name) {
        return new ModelLayerLocation(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name), "main");
    }

    @SubscribeEvent
    static void onRegisterLayerDefinitions(EntityRenderersEvent.RegisterLayerDefinitions event) {
        // Vanilla humanoid mesh (head 8x8x8, body 8x12x4, limbs 4x12x4) on the 64x64
        // player-skin layout — zero new geometry per spec §1.1.
        event.registerLayerDefinition(THE_OTHER_LAYER,
                () -> LayerDefinition.create(HumanoidModel.createMesh(CubeDeformation.NONE, 0.0F), 64, 64));
        event.registerLayerDefinition(GAZER_LAYER, GazerModel::createBodyLayer);
        event.registerLayerDefinition(UMBRAL_STALKER_LAYER, UmbralStalkerModel::createBodyLayer);
        event.registerLayerDefinition(SUNMOTE_LAYER, SunmoteModel::createBodyLayer);
        event.registerLayerDefinition(HERALD_LAYER, HeraldModel::createBodyLayer);
        event.registerLayerDefinition(FERRYMAN_LAYER, FerrymanModel::createBodyLayer);
    }

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(EclipseEntities.THE_OTHER.get(), TheOtherRenderer::new);
        event.registerEntityRenderer(EclipseEntities.GAZER.get(), GazerRenderer::new);
        event.registerEntityRenderer(EclipseEntities.UMBRAL_STALKER.get(), UmbralStalkerRenderer::new);
        // Deckhand: GeckoLib renderer self-registers in DeckhandRenderer.Registration (P6-W2).
        event.registerEntityRenderer(EclipseEntities.SUNMOTE.get(), SunmoteRenderer::new);
        event.registerEntityRenderer(EclipseEntities.HERALD.get(), HeraldRenderer::new);
        event.registerEntityRenderer(EclipseEntities.FERRYMAN.get(), FerrymanRenderer::new);
        // The corona shard renders as the umbral-shard item sprite (ItemSupplier), scaled
        // up and fullbright so it reads as a glowing ember in the night fight.
        event.registerEntityRenderer(EclipseEntities.HERALD_SHARD.get(),
                context -> new ThrownItemRenderer<>(context, 1.5F, true));
    }
}
