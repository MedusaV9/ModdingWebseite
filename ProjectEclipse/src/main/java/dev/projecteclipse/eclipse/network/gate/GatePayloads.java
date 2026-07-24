package dev.projecteclipse.eclipse.network.gate;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the P3-W11 gate payloads ({@code GrowthPayloads} /
 * {@code XboxPayloads} pattern): own MOD-bus {@link RegisterPayloadHandlersEvent} subscriber
 * on the shared P3 registrar version {@code "2"} (§7.3) — {@code EclipsePayloads} and
 * {@code EclipseMod} stay untouched. Payload ids are prefixed {@code eclipse:gate/} and must
 * NOT additionally be registered elsewhere (duplicate registration throws at startup).
 *
 * <p>Client dispatch uses installable {@link Consumer} hooks so this class stays loadable on
 * dedicated servers (no eager client-class references). The client owners install their
 * consumers from their own class initialization:
 * {@code client.loading.PortalTransitionController} for {@link S2CPortalFxPayload} and
 * {@code client.progression.ClientUnlockCache} for {@link S2CUnlockedKeysPayload}. Payloads
 * received while no handler is installed are dropped (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class GatePayloads {
    /** Shared P3 payload registrar version (§7.3). */
    private static final String VERSION = "2";

    private static volatile Consumer<S2CPortalFxPayload> clientPortalFxHandler;
    private static volatile Consumer<S2CUnlockedKeysPayload> clientUnlocksHandler;

    private GatePayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CPortalFxPayload.TYPE, S2CPortalFxPayload.STREAM_CODEC,
                GatePayloads::handlePortalFx);
        registrar.playToClient(S2CUnlockedKeysPayload.TYPE, S2CUnlockedKeysPayload.STREAM_CODEC,
                GatePayloads::handleUnlockedKeys);
    }

    // ------------------------------------------------------------------ server send helpers

    /** Sends the portal transition trigger to one player (call right BEFORE the teleport). */
    public static void sendPortalFx(ServerPlayer player, S2CPortalFxPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    /** Sends the unlock snapshot to one player ({@code UnlockSync} owns the send policy). */
    public static void sendUnlockedKeys(ServerPlayer player, S2CUnlockedKeysPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installed by {@code client.loading.PortalTransitionController} (client main thread). */
    public static void setClientPortalFxHandler(Consumer<S2CPortalFxPayload> handler) {
        clientPortalFxHandler = handler;
    }

    /** Installed by {@code client.progression.ClientUnlockCache} (client main thread). */
    public static void setClientUnlocksHandler(Consumer<S2CUnlockedKeysPayload> handler) {
        clientUnlocksHandler = handler;
    }

    private static void handlePortalFx(S2CPortalFxPayload payload, IPayloadContext context) {
        Consumer<S2CPortalFxPayload> handler = clientPortalFxHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Portal FX payload ({} style {}) — no client handler installed",
                    payload.phase(), payload.styleId());
        }
    }

    private static void handleUnlockedKeys(S2CUnlockedKeysPayload payload, IPayloadContext context) {
        Consumer<S2CUnlockedKeysPayload> handler = clientUnlocksHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Unlock-keys payload ({} keys) — no client handler installed",
                    payload.keys().size());
        }
    }
}
