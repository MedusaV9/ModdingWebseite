package dev.projecteclipse.eclipse.network.nether;

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
 * Self-registering network seam for the day-2 nether-opening beats (the
 * {@code network.breach.BreachPayloads} precedent): its OWN mod-bus registrar under its own
 * version group, so neither {@code EclipsePayloads} nor {@code FxPayloads} needs an edit.
 * The client installs its consumer during client setup
 * ({@code client.nether.NetherOpenClientFx}); beats received before installation — or on a
 * dedicated server — are dropped harmlessly.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class NetherOpenPayloads {
    private static final String VERSION = "netheropen1";

    private static volatile Consumer<S2CNetherOpenPayload> clientHandler;

    private NetherOpenPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CNetherOpenPayload.TYPE, S2CNetherOpenPayload.STREAM_CODEC,
                NetherOpenPayloads::handle);
    }

    /** Broadcasts one beat to every player currently in {@code level} (the overworld). */
    public static void send(ServerLevel level, S2CNetherOpenPayload payload) {
        PacketDistributor.sendToPlayersInDimension(level, payload);
    }

    /** Client-setup hook; beats arriving before installation are safely dropped. */
    public static void setClientHandler(Consumer<S2CNetherOpenPayload> handler) {
        clientHandler = handler;
    }

    private static void handle(S2CNetherOpenPayload payload, IPayloadContext context) {
        Consumer<S2CNetherOpenPayload> handler = clientHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Nether opening beat {} at {} (i={}); no client FX handler installed",
                    payload.phase(), payload.center().toShortString(), payload.intensity());
        }
    }
}
