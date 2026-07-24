package dev.projecteclipse.eclipse.network.invlock;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.S2CInvLockPayload;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the inventory slot-lock payload (WB-SLOTLOCK) — same
 * pattern as {@code network.growth.GrowthPayloads}: registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION},
 * so {@code EclipsePayloads.register(...)} and {@code EclipseMod} stay untouched
 * (NeoForge allows any number of payload registrars). The payload id is prefixed
 * {@code eclipse:invlock/} and must NOT additionally be registered in
 * {@code EclipsePayloads} (duplicate registration throws at startup).
 *
 * <p>The client side is dispatched to the frozen entry point
 * {@code client.invlock.InvLockClientState.handle} — referenced fully-qualified inside
 * the handler body so it resolves lazily and never loads on a dedicated server (repo
 * pattern from {@code network.fx.FxPayloads}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class InvLockPayloads {
    private static final String VERSION = "invlock1";

    private InvLockPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CInvLockPayload.TYPE, S2CInvLockPayload.STREAM_CODEC,
                InvLockPayloads::handleState);
    }

    // ------------------------------------------------------------------ server send helper

    /** Sends one player their current slot-lock state ({@code progression.InvLockSync}). */
    public static void send(ServerPlayer player, S2CInvLockPayload payload) {
        PacketDistributor.sendToPlayer(player, payload);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleState(S2CInvLockPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.invlock.InvLockClientState.handle(payload);
    }
}
