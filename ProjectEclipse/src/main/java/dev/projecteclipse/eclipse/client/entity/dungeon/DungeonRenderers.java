package dev.projecteclipse.eclipse.client.entity.dungeon;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.entity.dungeon.DungeonEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * Renderer registration for the dungeon family — auto-subscribed, no {@code EclipseMod}
 * wiring needed (house §1.6 pattern). Guarded on {@code DeferredHolder.isBound()} so the
 * client boots green while the {@code DungeonEntities.register(modEventBus)} wiring line
 * ({@code docs/plans_v3/wiring/P6-W910_wiring.md}) has not been applied yet.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DungeonRenderers {
    private DungeonRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        if (!DungeonEntities.ECLIPSE_CULTIST.isBound()) {
            return; // Registrar not wired yet — nothing to render.
        }
        event.registerEntityRenderer(DungeonEntities.ECLIPSE_CULTIST.get(), EclipseCultistRenderer::new);
        event.registerEntityRenderer(DungeonEntities.SHADOW_BOLT.get(), ShadowBoltRenderer::new);
    }
}
