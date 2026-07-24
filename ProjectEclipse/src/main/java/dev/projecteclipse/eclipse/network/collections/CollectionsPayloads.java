package dev.projecteclipse.eclipse.network.collections;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the D1 collections payloads ({@code BestiaryPayloads}
 * pattern): own MOD-bus {@link RegisterPayloadHandlersEvent} subscriber under version
 * group {@value #VERSION}, so {@code EclipsePayloads} and {@code EclipseMod} stay
 * untouched. Payload ids are prefixed {@code eclipse:collections/} and must NOT
 * additionally be registered elsewhere (duplicate registration throws at startup).
 *
 * <p>Client dispatch uses installable {@link Consumer} hooks so this class stays
 * loadable on dedicated servers (no eager client-class references):
 * {@code client.collections.ClientCollectionsCache} installs its consumers from its own
 * static initializer. Payloads received while no handler is installed are dropped
 * (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class CollectionsPayloads {
    private static final String VERSION = "collections1";

    private static volatile Consumer<S2CCollectionsPayload> snapshotHandler;
    private static volatile Consumer<S2CCollectionDeltaPayload> deltaHandler;
    private static volatile Consumer<S2CCollectionTierPayload> tierHandler;

    private CollectionsPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CCollectionsPayload.TYPE, S2CCollectionsPayload.STREAM_CODEC,
                CollectionsPayloads::handleSnapshot);
        registrar.playToClient(S2CCollectionDeltaPayload.TYPE, S2CCollectionDeltaPayload.STREAM_CODEC,
                CollectionsPayloads::handleDelta);
        registrar.playToClient(S2CCollectionTierPayload.TYPE, S2CCollectionTierPayload.STREAM_CODEC,
                CollectionsPayloads::handleTier);
    }

    // ------------------------------------------------------------------ server send helper

    /** Sends one player a payload ({@code CollectionsService} owns the send policy). */
    public static void sendTo(ServerPlayer player, CustomPacketPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installed by {@code client.collections.ClientCollectionsCache} on client class-load. */
    public static void setSnapshotHandler(Consumer<S2CCollectionsPayload> handler) {
        snapshotHandler = handler;
    }

    public static void setDeltaHandler(Consumer<S2CCollectionDeltaPayload> handler) {
        deltaHandler = handler;
    }

    public static void setTierHandler(Consumer<S2CCollectionTierPayload> handler) {
        tierHandler = handler;
    }

    /** Runs on the client main thread only; no client classes referenced eagerly. */
    private static void handleSnapshot(S2CCollectionsPayload payload, IPayloadContext context) {
        Consumer<S2CCollectionsPayload> handler = snapshotHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Collections snapshot ({} entries) — no client handler installed",
                    payload.entries().size());
        }
    }

    private static void handleDelta(S2CCollectionDeltaPayload payload, IPayloadContext context) {
        Consumer<S2CCollectionDeltaPayload> handler = deltaHandler;
        if (handler != null) {
            handler.accept(payload);
        }
    }

    private static void handleTier(S2CCollectionTierPayload payload, IPayloadContext context) {
        Consumer<S2CCollectionTierPayload> handler = tierHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Collection tier-up {} T{} — no client handler installed",
                    payload.collectionId(), payload.tier());
        }
    }
}
