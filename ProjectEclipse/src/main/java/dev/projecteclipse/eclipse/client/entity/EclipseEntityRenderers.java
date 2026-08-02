package dev.projecteclipse.eclipse.client.entity;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.EclipseEntities;
import net.minecraft.client.model.geom.ModelLayerLocation;
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

    private EclipseEntityRenderers() {}

    private static ModelLayerLocation layer(String name) {
        return new ModelLayerLocation(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, name), "main");
    }

    @SubscribeEvent
    static void onRegisterLayerDefinitions(EntityRenderersEvent.RegisterLayerDefinitions event) {
        // Vanilla humanoid mesh (head 8x8x8, body 8x12x4, limbs 4x12x4) on the 64x64
        // player-skin layout per spec §1.1 — plus TheOtherModel's hidden-until-aggro
        // floating fragment cubes (MOB-GLITCH; silhouette unchanged while passive).
        event.registerLayerDefinition(THE_OTHER_LAYER, TheOtherModel::createBodyLayer);
        // Gazer/Umbral Stalker/Sunmote: converted to GeckoLib (MC1/MC2/MC3) — their geo
        // renderers self-register in client/entity/{gazer,stalker,sunmote}/*Renderers.
        // Herald/Ferryman: converted to GeckoLib too (MA3/MA4) — no layer bake needed.
    }

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(EclipseEntities.THE_OTHER.get(), TheOtherRenderer::new);
        // Deckhand: GeckoLib renderer self-registers in DeckhandRenderer.Registration (P6-W2).
        // Gazer/Umbral Stalker/Sunmote: GeckoLib registrars in their own subpackages (MC1/MC2/MC3).
        // Herald: GeckoLib renderer self-registers in client.entity.herald.HeraldRenderers (MA3).
        // Ferryman: GeckoLib renderer self-registers in client.entity.FerrymanRenderers (MA4).
        // The corona shard renders as the umbral-shard item sprite (ItemSupplier), scaled
        // up and fullbright so it reads as a glowing ember in the night fight.
        event.registerEntityRenderer(EclipseEntities.HERALD_SHARD.get(),
                context -> new ThrownItemRenderer<>(context, 1.5F, true));
    }
}
