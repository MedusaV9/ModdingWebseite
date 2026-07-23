package dev.projecteclipse.eclipse.network.growth;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CGrowthWavePayload;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the ring-growth wave payload (P1 W1.5, design D11) —
 * same pattern as {@code network.fx.FxPayloads}: registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION},
 * so {@code EclipsePayloads.register(...)} and {@code EclipseMod} stay untouched
 * (NeoForge allows any number of payload registrars). The payload id is prefixed
 * {@code eclipse:growth/} and must NOT additionally be registered in
 * {@code EclipsePayloads} (duplicate registration throws at startup).
 *
 * <p>The client visual is P2's (rise/dissolve shaders against the wavefront). Until P2
 * lands, the handler is a no-op hook: P2 installs its consumer via
 * {@link #setClientWaveHandler} from client setup — no edit to this file needed. The hook
 * type is a plain {@link Consumer}, so this class stays loadable on dedicated servers.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class GrowthPayloads {
    private static final String VERSION = "growth1";

    /** Client-side wave consumer installed by P2 (runs on the client main thread). */
    private static volatile Consumer<S2CGrowthWavePayload> clientWaveHandler;

    private GrowthPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CGrowthWavePayload.TYPE, S2CGrowthWavePayload.STREAM_CODEC,
                GrowthPayloads::handleGrowthWave);
    }

    // ------------------------------------------------------------------ server send helper

    /**
     * Broadcasts one wavefront pulse to every player in the growing dimension. Called by
     * {@code worldgen.stage.RingGrowthService} every 5 ticks during animated sweeps.
     */
    public static void sendWave(ServerLevel level, S2CGrowthWavePayload payload) {
        PacketDistributor.sendToPlayersInDimension(level, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /**
     * Installs the client-side wave consumer (P2 seam). Call once from client setup;
     * pulses received while no handler is installed are dropped (debug-logged).
     */
    public static void setClientWaveHandler(Consumer<S2CGrowthWavePayload> handler) {
        clientWaveHandler = handler;
    }

    /** Runs on the client main thread only; no client classes are referenced eagerly. */
    private static void handleGrowthWave(S2CGrowthWavePayload payload, IPayloadContext context) {
        Consumer<S2CGrowthWavePayload> handler = clientWaveHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Growth wave pulse {} ({} stage {}->{}, waveR {}) — no client handler installed",
                    payload.pulseIndex(), payload.dim(), payload.fromStage(), payload.toStage(), payload.waveR());
        }
    }
}
