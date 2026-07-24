package dev.projecteclipse.eclipse.network.bestiary;

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
 * Self-registering registrar for the W4-BESTIARY payload ({@code GrowthPayloads} /
 * {@code GatePayloads} pattern): own MOD-bus {@link RegisterPayloadHandlersEvent}
 * subscriber under version group {@value #VERSION}, so {@code EclipsePayloads} and
 * {@code EclipseMod} stay untouched. The payload id is prefixed {@code eclipse:bestiary/}
 * and must NOT additionally be registered elsewhere (duplicate registration throws at
 * startup).
 *
 * <p>Client dispatch uses an installable {@link Consumer} hook so this class stays
 * loadable on dedicated servers (no eager client-class references):
 * {@code client.progression.ClientBestiaryCache} installs its consumer from its own
 * static initializer. Payloads received while no handler is installed are dropped
 * (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class BestiaryPayloads {
    private static final String VERSION = "bestiary1";

    /** Client-side snapshot consumer installed by {@code ClientBestiaryCache}. */
    private static volatile Consumer<S2CBestiaryPayload> clientHandler;

    private BestiaryPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CBestiaryPayload.TYPE, S2CBestiaryPayload.STREAM_CODEC,
                BestiaryPayloads::handleBestiary);
    }

    // ------------------------------------------------------------------ server send helper

    /** Sends one player their snapshot ({@code BestiaryService} owns the send policy). */
    public static void sendTo(ServerPlayer player, S2CBestiaryPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installed by {@code client.progression.ClientBestiaryCache} on client class-load. */
    public static void setClientHandler(Consumer<S2CBestiaryPayload> handler) {
        clientHandler = handler;
    }

    /** Runs on the client main thread only; no client classes referenced eagerly. */
    private static void handleBestiary(S2CBestiaryPayload payload, IPayloadContext context) {
        Consumer<S2CBestiaryPayload> handler = clientHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Bestiary snapshot ({} entries) — no client handler installed",
                    payload.entries().size());
        }
    }
}
