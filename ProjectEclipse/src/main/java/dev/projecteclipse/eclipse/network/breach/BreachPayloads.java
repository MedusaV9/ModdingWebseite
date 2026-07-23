package dev.projecteclipse.eclipse.network.breach;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CBreachPayload;
import net.minecraft.server.level.ServerLevel;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering network seam for D10's breach phases. It deliberately uses its own
 * MOD-bus registrar, so neither {@code EclipseMod} nor the shared payload hub needs an
 * edit. P2 installs the optional client consumer during client setup.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class BreachPayloads {
    private static final String VERSION = "breach1";

    private static volatile Consumer<S2CBreachPayload> clientPhaseHandler;

    private BreachPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CBreachPayload.TYPE, S2CBreachPayload.STREAM_CODEC,
                BreachPayloads::handlePhase);
    }

    /** Sends one lifecycle boundary to every player currently in the overworld. */
    public static void sendPhase(ServerLevel level, S2CBreachPayload payload) {
        PacketDistributor.sendToPlayersInDimension(level, payload);
    }

    /** P2 client setup hook; phases received before installation are safely dropped. */
    public static void setClientPhaseHandler(Consumer<S2CBreachPayload> handler) {
        clientPhaseHandler = handler;
    }

    private static void handlePhase(S2CBreachPayload payload, IPayloadContext context) {
        Consumer<S2CBreachPayload> handler = clientPhaseHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Nether breach phase {} at {} (r={}); no client FX handler installed",
                    payload.phase(), payload.center().toShortString(), payload.radius());
        }
    }
}
