package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Networking base for Project: Eclipse. Registers all custom payloads (registrar version "1")
 * and syncs lives + day state to a player when they log in.
 */
public final class EclipsePayloads {
    private EclipsePayloads() {}

    /** Wires the mod-bus payload registration and the game-bus login sync. Call once from the mod constructor. */
    public static void register(IEventBus modEventBus) {
        modEventBus.addListener(EclipsePayloads::onRegisterPayloadHandlers);
        NeoForge.EVENT_BUS.addListener(EclipsePayloads::onPlayerLoggedIn);
    }

    private static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar("1");
        registrar.playToClient(S2CLivesPayload.TYPE, S2CLivesPayload.STREAM_CODEC, EclipsePayloads::handleLives);
        registrar.playToClient(S2CDayStatePayload.TYPE, S2CDayStatePayload.STREAM_CODEC, EclipsePayloads::handleDayState);
    }

    private static void handleLives(S2CLivesPayload payload, IPayloadContext context) {
        ClientStateCache.lives = payload.lives();
    }

    private static void handleDayState(S2CDayStatePayload payload, IPayloadContext context) {
        ClientStateCache.day = payload.day();
        ClientStateCache.altarLevel = payload.altarLevel();
    }

    private static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            EclipseWorldState state = EclipseWorldState.get(player.server);
            PacketDistributor.sendToPlayer(player,
                    new S2CLivesPayload(LivesApi.get(player)),
                    new S2CDayStatePayload(state.getDay(), state.getAltarLevel()));
        }
    }
}
