package dev.projecteclipse.eclipse.client.entity.echo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.woah.echogrove.EchoGroveEntities;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.EntityRenderersEvent;

/**
 * WOAH-05 renderer registration (plan §4.3) — the {@code GhostRenderers}
 * pattern, minus the lookup guard: {@code EchoGroveEntities} lives in this
 * feature's own compile unit, so the holders are always present and typed
 * registration is safe (the guard existed for cross-worker registration races
 * that cannot happen here). MC4: dropped the deprecated explicit {@code bus =}
 * attribute — NeoForge picks the mod bus from the event type, exactly like the
 * GhostRenderers original this file mirrors.
 */
@OnlyIn(Dist.CLIENT)
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class EchoRenderers {
    private EchoRenderers() {}

    @SubscribeEvent
    static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(EchoGroveEntities.ECHO_GHOST.get(), EchoGhostRenderer::new);
        event.registerEntityRenderer(EchoGroveEntities.ECHO_GHOST_WOLF.get(), EchoGhostWolfRenderer::new);
        event.registerEntityRenderer(EchoGroveEntities.MEMORY_ORB.get(), MemoryOrbRenderer::new);
    }
}
