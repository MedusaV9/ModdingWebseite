package dev.projecteclipse.eclipse.network.hearts;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * Self-registering registrar for the W4-HEARTS payloads (the
 * {@code network.death.DeathFlowPayloads} pattern): registers on its own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under version group {@value #VERSION},
 * so {@code EclipsePayloads.register(...)} stays untouched. Payload ids are prefixed
 * {@code eclipse:hearts/} and must NOT additionally be registered in
 * {@code EclipsePayloads} (duplicate registration throws at startup).
 *
 * <p>The pre-existing {@code S2CHeartBurstPayload} ({@code eclipse:heart_burst})
 * deliberately stays in {@code EclipsePayloads} version group "2" — only NEW payloads
 * live here.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HeartsPayloads {
    /** Bumped w4hearts1 → w4hearts2 when {@link S2CHeartBurstFxPayload} joined the group (R5). */
    private static final String VERSION = "w4hearts2";

    private HeartsPayloads() {}

    // ------------------------------------------------------------------ payload records

    /**
     * Server → the ritual's ghost target (W4-HEARTS R4): revive-ritual vigil sync, sent
     * every 20 ticks while a {@code ReviveRitual} runs for that player. {@code progress}
     * is 0..1 of the 3-minute ritual; {@code active=false} means the ritual failed or
     * was aborted — the client drains the violet fill and the cracks return. Carries no
     * names or positions (anonymity law).
     */
    public record S2CRitualVigilPayload(float progress, boolean active) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CRitualVigilPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "hearts/ritual_vigil"));

        public static final StreamCodec<ByteBuf, S2CRitualVigilPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.FLOAT, S2CRitualVigilPayload::progress,
                        ByteBufCodecs.BOOL, S2CRitualVigilPayload::active,
                        S2CRitualVigilPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CRitualVigilPayload> type() {
            return TYPE;
        }
    }

    /**
     * Server → one client (W4-HEARTS R5): play a heart-burst timeline over heart slot
     * {@code heartIndex}. {@code gained=true} is the kill-transfer reverse burst — the
     * shatter plays BACKWARDS (shards converge, sparks fold in, the heart materializes
     * violet and settles) over the killer's newly filled slot. {@code gained=false} plays
     * the normal loss shatter, a superset of the legacy {@code eclipse:heart_burst} lane
     * (which stays registered in {@code EclipsePayloads} version group "2", untouched —
     * duplicate-id rule). Carries no names or positions (anonymity law).
     */
    public record S2CHeartBurstFxPayload(int heartIndex, boolean gained) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CHeartBurstFxPayload> TYPE =
                new CustomPacketPayload.Type<>(
                        ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "hearts/burst_fx"));

        public static final StreamCodec<ByteBuf, S2CHeartBurstFxPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.VAR_INT, S2CHeartBurstFxPayload::heartIndex,
                        ByteBufCodecs.BOOL, S2CHeartBurstFxPayload::gained,
                        S2CHeartBurstFxPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CHeartBurstFxPayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CRitualVigilPayload.TYPE, S2CRitualVigilPayload.STREAM_CODEC,
                HeartsPayloads::handleRitualVigil);
        registrar.playToClient(S2CHeartBurstFxPayload.TYPE, S2CHeartBurstFxPayload.STREAM_CODEC,
                HeartsPayloads::handleHeartBurstFx);
    }

    // ------------------------------------------------------------------ server send helpers

    /** Sends the current vigil state to exactly one (online) ghost target. */
    public static void sendRitualVigil(ServerPlayer target, float progress, boolean active) {
        PacketDistributor.sendToPlayer(target, new S2CRitualVigilPayload(progress, active));
    }

    /** Sends one heart-burst timeline (forward loss or reversed gain) to exactly one player. */
    public static void sendHeartBurstFx(ServerPlayer target, int heartIndex, boolean gained) {
        PacketDistributor.sendToPlayer(target, new S2CHeartBurstFxPayload(heartIndex, gained));
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleRitualVigil(S2CRitualVigilPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.death.GhostHeartsLayer
                .setRitualVigil(payload.progress(), payload.active());
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleHeartBurstFx(S2CHeartBurstFxPayload payload, IPayloadContext context) {
        if (payload.gained()) {
            dev.projecteclipse.eclipse.hearts.client.HeartBurstOverlay.triggerGained(payload.heartIndex());
        } else {
            dev.projecteclipse.eclipse.hearts.client.HeartBurstOverlay.trigger(payload.heartIndex());
        }
    }
}
