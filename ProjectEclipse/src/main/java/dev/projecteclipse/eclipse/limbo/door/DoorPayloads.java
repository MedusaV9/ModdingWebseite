package dev.projecteclipse.eclipse.limbo.door;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the P6-W3 door payload group, version {@value #VERSION}
 * (plans_v3 §2.5 — "registrar {@code p6w3}"). Registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber (auto-routed by event type) so
 * {@code EclipsePayloads.register} and {@code EclipseMod} stay untouched (NeoForge
 * allows any number of payload registrars; {@code FxPayloads} pattern).
 *
 * <p>The handler is thin and dispatches to the client entry point fully-qualified inside
 * the method body, so client classes resolve lazily and never load on a dedicated
 * server (repo pattern).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DoorPayloads {
    private static final String VERSION = "p6w3";

    private DoorPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CDoorCuePayload.TYPE, S2CDoorCuePayload.STREAM_CODEC, DoorPayloads::handleDoorCue);
    }

    /** Sends a personal door pose cue ({@code S2CDoorCuePayload.POSE_*}) to one player. */
    public static void sendCue(ServerPlayer player, S2CDoorCuePayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleDoorCue(S2CDoorCuePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.entity.door.DoorRenderers.handleCue(payload);
    }
}
