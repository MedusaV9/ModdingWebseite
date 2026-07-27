package dev.projecteclipse.eclipse.woah.mansiondome;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * WOAH-01 self-registering payload registrar (plan §3.6) — the sanctioned
 * {@code EchoGrovePayloads}/{@code FxPayloads} pattern: own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under its own version group, so the
 * shared {@code network.EclipsePayloads} hub stays untouched. The single payload mirrors
 * the dome snapshot to the client (shell renderer, beam, dome_shell post feeder); it is
 * sent on arm/status changes and on login — never per tick.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MansionDomePayloads {
    private static final String VERSION = "v1woahdome";

    private MansionDomePayloads() {}

    /**
     * Server → dimension: the dome snapshot. {@code status} is a
     * {@link MansionDomeState} status byte; {@code dimension} is the dome's dimension id
     * (the login sync reaches players in EVERY dimension, so the client must gate its
     * visuals on it); {@code devicePos} is the emitter's probed roof stand (carried in
     * full — the probe may sit off the exact centre column, and the client beam must not
     * guess); {@code collapseStartGameTime} lets the client run the t0–t50 beam/shell
     * collapse timeline locally (0 while not collapsing).
     */
    public record S2CMansionDomePayload(byte status, ResourceLocation dimension,
            BlockPos centre, float shellRadius, BlockPos devicePos,
            long collapseStartGameTime) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CMansionDomePayload> TYPE =
                new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                        EclipseMod.MOD_ID, "woah_dome/state"));

        public static final StreamCodec<ByteBuf, S2CMansionDomePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BYTE, S2CMansionDomePayload::status,
                        ResourceLocation.STREAM_CODEC, S2CMansionDomePayload::dimension,
                        BlockPos.STREAM_CODEC, S2CMansionDomePayload::centre,
                        ByteBufCodecs.FLOAT, S2CMansionDomePayload::shellRadius,
                        BlockPos.STREAM_CODEC, S2CMansionDomePayload::devicePos,
                        ByteBufCodecs.VAR_LONG, S2CMansionDomePayload::collapseStartGameTime,
                        S2CMansionDomePayload::new);

        @Override
        public CustomPacketPayload.Type<S2CMansionDomePayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CMansionDomePayload.TYPE, S2CMansionDomePayload.STREAM_CODEC,
                MansionDomePayloads::handleState);
    }

    /** Runs on the client main thread; client class resolved lazily (dedicated-server safe). */
    private static void handleState(S2CMansionDomePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.woah.mansiondome.client.MansionDomeClient.handle(payload);
    }

    // ------------------------------------------------------------------ senders

    /** Login sync (the S2CGhostRevealPayload "once, then on change" law). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            PacketDistributor.sendToPlayer(player, snapshot(player.server));
        }
    }

    /**
     * Dimension-change refresh: the client's {@code Clone} reset drops loop windows but
     * KEEPS the snapshot — this resend makes the state authoritative again either way
     * (and covers players who missed a lifecycle broadcast while in another dimension).
     */
    @SubscribeEvent
    static void onPlayerChangedDimension(PlayerEvent.PlayerChangedDimensionEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            PacketDistributor.sendToPlayer(player, snapshot(player.server));
        }
    }

    /** Broadcast after every lifecycle change (arm, hit → destroy beats, reset). */
    public static void syncDimension(ServerLevel level) {
        PacketDistributor.sendToPlayersInDimension(level, snapshot(level.getServer()));
    }

    private static S2CMansionDomePayload snapshot(MinecraftServer server) {
        MansionDomeState state = MansionDomeState.get(server);
        return new S2CMansionDomePayload(state.status(), state.dimension().location(),
                state.centre(), state.shellRadius(), state.devicePos(),
                state.collapseStartGameTime());
    }
}
