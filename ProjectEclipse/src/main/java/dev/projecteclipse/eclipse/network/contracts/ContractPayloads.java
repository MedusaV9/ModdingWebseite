package dev.projecteclipse.eclipse.network.contracts;

import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.UUIDUtil;
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
 * Self-registering S2C transport for the kill-contract system (IDEA-20) — the
 * {@code network.growth.GrowthPayloads} / {@code music.MusicPayloads} pattern: own MOD-bus
 * registrar under version group {@value #VERSION}, payload ids prefixed
 * {@code eclipse:contracts/}, and NO edit to {@code EclipsePayloads}/{@code EclipseMod}.
 *
 * <p><b>Anonymity contract:</b> {@link S2CContractRevealPayload} carries the target's UUID
 * ONLY toward the hunter ({@link #ROLE_HUNTER}); the target-role payload always carries the
 * nil UUID. No name ever crosses the wire — the client resolves UUID → face texture itself
 * (the deliberate, hunter-only breach; see the wiring doc's design notes). PRANK rounds
 * send the identical target-role payload to everyone, so "you are hunted" carries zero
 * information by construction.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class ContractPayloads {
    private static final String VERSION = "contracts1";

    /** Reveal roles. */
    public static final byte ROLE_HUNTER = 1;
    public static final byte ROLE_TARGET = 2;

    /** Resolve kinds ({@link S2CContractResolvePayload}). */
    public static final byte RESOLVE_FULFILLED = 1;
    public static final byte RESOLVE_LAPSED = 2;
    public static final byte RESOLVE_SURVIVED = 3;
    public static final byte RESOLVE_PRANK_REVEAL = 4;
    public static final byte RESOLVE_WITHDRAWN = 5;

    private static final UUID NIL_UUID = new UUID(0L, 0L);

    private ContractPayloads() {}

    // ------------------------------------------------------------------ payloads

    /**
     * Reveal ceremony trigger. {@code role} = {@link #ROLE_HUNTER} (roulette → real face →
     * red X; {@code targetUuid} set) or {@link #ROLE_TARGET} ("DU WIRST GEJAGT";
     * {@code targetUuid} is nil). {@code windowTicks} is the remaining window length;
     * {@code replay} = mid-window relog resync (mini-marker only, no full ceremony).
     */
    public record S2CContractRevealPayload(byte role, UUID targetUuid, int windowTicks, boolean replay)
            implements CustomPacketPayload {
        public static final Type<S2CContractRevealPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "contracts/reveal"));
        public static final StreamCodec<ByteBuf, S2CContractRevealPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BYTE, S2CContractRevealPayload::role,
                        UUIDUtil.STREAM_CODEC, S2CContractRevealPayload::targetUuid,
                        ByteBufCodecs.VAR_INT, S2CContractRevealPayload::windowTicks,
                        ByteBufCodecs.BOOL, S2CContractRevealPayload::replay,
                        S2CContractRevealPayload::new);

        @Override
        public Type<S2CContractRevealPayload> type() {
            return TYPE;
        }
    }

    /**
     * Window flag broadcast to EVERY player (start, end, login resync): drives the
     * client-side armor blackout, the mini-marker countdown and the subtle window vignette.
     * Carries no pair information — safe to broadcast.
     */
    public record S2CContractStatePayload(boolean windowActive, long endsAtEpochMillis,
            long serverNowMillis) implements CustomPacketPayload {
        public static final Type<S2CContractStatePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "contracts/state"));
        public static final StreamCodec<ByteBuf, S2CContractStatePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BOOL, S2CContractStatePayload::windowActive,
                        ByteBufCodecs.VAR_LONG, S2CContractStatePayload::endsAtEpochMillis,
                        ByteBufCodecs.VAR_LONG, S2CContractStatePayload::serverNowMillis,
                        S2CContractStatePayload::new);

        @Override
        public Type<S2CContractStatePayload> type() {
            return TYPE;
        }
    }

    /** Private resolution beat (per-receiver): solid-X stamp, crumble, survived, prank exhale. */
    public record S2CContractResolvePayload(byte kind) implements CustomPacketPayload {
        public static final Type<S2CContractResolvePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "contracts/resolve"));
        public static final StreamCodec<ByteBuf, S2CContractResolvePayload> STREAM_CODEC =
                ByteBufCodecs.BYTE.map(S2CContractResolvePayload::new, S2CContractResolvePayload::kind);

        @Override
        public Type<S2CContractResolvePayload> type() {
            return TYPE;
        }
    }

    // ------------------------------------------------------------------ registration

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CContractRevealPayload.TYPE, S2CContractRevealPayload.STREAM_CODEC,
                ContractPayloads::handleReveal);
        registrar.playToClient(S2CContractStatePayload.TYPE, S2CContractStatePayload.STREAM_CODEC,
                ContractPayloads::handleState);
        registrar.playToClient(S2CContractResolvePayload.TYPE, S2CContractResolvePayload.STREAM_CODEC,
                ContractPayloads::handleResolve);
    }

    // ------------------------------------------------------------------ server send helpers

    /** Hunter reveal: the only payload that ever carries the target UUID. */
    public static void sendHunterReveal(ServerPlayer hunter, UUID targetUuid, int windowTicks,
            boolean replay) {
        PacketDistributor.sendToPlayer(hunter, new S2CContractRevealPayload(
                ROLE_HUNTER, targetUuid, windowTicks, replay));
    }

    /** Target reveal ("DU WIRST GEJAGT") — identical for REAL targets and PRANK rounds. */
    public static void sendTargetReveal(ServerPlayer player, int windowTicks, boolean replay) {
        PacketDistributor.sendToPlayer(player, new S2CContractRevealPayload(
                ROLE_TARGET, NIL_UUID, windowTicks, replay));
    }

    public static void sendStateToAll(net.minecraft.server.MinecraftServer server,
            boolean windowActive, long endsAtEpochMillis, long serverNowMillis) {
        PacketDistributor.sendToAllPlayers(new S2CContractStatePayload(
                windowActive, endsAtEpochMillis, serverNowMillis));
    }

    public static void sendState(ServerPlayer player, boolean windowActive,
            long endsAtEpochMillis, long serverNowMillis) {
        PacketDistributor.sendToPlayer(player, new S2CContractStatePayload(
                windowActive, endsAtEpochMillis, serverNowMillis));
    }

    public static void sendResolve(ServerPlayer player, byte kind) {
        PacketDistributor.sendToPlayer(player, new S2CContractResolvePayload(kind));
    }

    // ------------------------------------------------------------------ client dispatch

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleReveal(S2CContractRevealPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.contracts.ContractRevealOverlay.handleReveal(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleState(S2CContractStatePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.contracts.ContractClientState.handleState(payload);
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleResolve(S2CContractResolvePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.contracts.ContractRevealOverlay.handleResolve(payload);
    }
}
