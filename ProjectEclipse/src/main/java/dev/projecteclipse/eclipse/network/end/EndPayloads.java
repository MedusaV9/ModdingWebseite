package dev.projecteclipse.eclipse.network.end;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering network seam for D12's overworld End crash. P2 may install an
 * optional client consumer without touching the shared payload registrar.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class EndPayloads {
    private static final String VERSION = "end1";

    private static volatile Consumer<S2CEndCrashPayload> clientCrashHandler;

    private EndPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(
                S2CEndCrashPayload.TYPE,
                S2CEndCrashPayload.STREAM_CODEC,
                EndPayloads::handleCrash);
    }

    /** Sends the arrival cue to every player currently in the overworld. */
    public static void sendCrash(ServerLevel level, S2CEndCrashPayload payload) {
        PacketDistributor.sendToPlayersInDimension(level, payload);
    }

    /** Client-setup seam owned by P2. */
    public static void setClientCrashHandler(Consumer<S2CEndCrashPayload> handler) {
        clientCrashHandler = handler;
    }

    private static void handleCrash(S2CEndCrashPayload payload, IPayloadContext context) {
        Consumer<S2CEndCrashPayload> handler = clientCrashHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug(
                    "End crash at {} (r={}, {}t, shake={}); no client FX handler installed",
                    payload.center().toShortString(), payload.radius(),
                    payload.timelineTicks(), payload.shakeStrength());
        }
    }
}
