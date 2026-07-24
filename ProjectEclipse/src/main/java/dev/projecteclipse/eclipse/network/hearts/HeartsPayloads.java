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
    private static final String VERSION = "w4hearts1";

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

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CRitualVigilPayload.TYPE, S2CRitualVigilPayload.STREAM_CODEC,
                HeartsPayloads::handleRitualVigil);
    }

    // ------------------------------------------------------------------ server send helper

    /** Sends the current vigil state to exactly one (online) ghost target. */
    public static void sendRitualVigil(ServerPlayer target, float progress, boolean active) {
        PacketDistributor.sendToPlayer(target, new S2CRitualVigilPayload(progress, active));
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleRitualVigil(S2CRitualVigilPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.death.GhostHeartsLayer
                .setRitualVigil(payload.progress(), payload.active());
    }
}
