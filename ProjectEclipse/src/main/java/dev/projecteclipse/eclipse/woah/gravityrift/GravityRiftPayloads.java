package dev.projecteclipse.eclipse.woah.gravityrift;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
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
 * WOAH-02 self-registering payload registrar — the sanctioned
 * {@code EchoGrovePayloads} pattern: own MOD-bus {@link RegisterPayloadHandlersEvent}
 * subscriber under its own version group so the shared {@code network.EclipsePayloads}
 * hub stays untouched. The single S2C payload mirrors the rift lifecycle (built +
 * crater-floor anchor) and the inversion window; it is sent on login, on build and on
 * inversion start/end — never per tick. Pulse beats are NOT synced: both sides compute
 * the identical absolute raster {@code gameTime % PULSE_PERIOD == phaseOffset(anchor)}
 * (stateless-push law), so a beat can never drift between server physics and client FX.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GravityRiftPayloads {
    private static final String VERSION = "v1woahgravity";

    private GravityRiftPayloads() {}

    /**
     * Server → all: rift lifecycle + inversion snapshot. {@code anchor} is the
     * crater-floor center ({@code BlockPos.ZERO} until built — the {@code built} flag
     * gates all use); {@code invertRemainingTicks} counts down the FULL
     * {@value GravityRiftZone#INVERT_TOTAL_TICKS}-tick inversion window (0 = none).
     */
    public record S2CGravityRiftPayload(boolean built, BlockPos anchor, int invertRemainingTicks)
            implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CGravityRiftPayload> TYPE =
                new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                        EclipseMod.MOD_ID, "woah_gravity/state"));

        public static final StreamCodec<ByteBuf, S2CGravityRiftPayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BOOL, S2CGravityRiftPayload::built,
                        BlockPos.STREAM_CODEC, S2CGravityRiftPayload::anchor,
                        ByteBufCodecs.VAR_INT, S2CGravityRiftPayload::invertRemainingTicks,
                        S2CGravityRiftPayload::new);

        @Override
        public CustomPacketPayload.Type<S2CGravityRiftPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CGravityRiftPayload.TYPE, S2CGravityRiftPayload.STREAM_CODEC,
                GravityRiftPayloads::handleState);
    }

    /** Runs on the client main thread; client class resolved lazily (dedicated-server safe). */
    private static void handleState(S2CGravityRiftPayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.woah.gravityrift.client.GravityRiftClientState
                .handleState(payload);
    }

    // ------------------------------------------------------------------ senders

    /** Login sync (the S2CGhostRevealPayload "once, then on change" law). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            PacketDistributor.sendToPlayer(player, snapshot(player.serverLevel()));
        }
    }

    /** Broadcast after every lifecycle change (build, inversion start/end, dev reset). */
    public static void syncAll(ServerLevel level) {
        PacketDistributor.sendToAllPlayers(snapshot(level));
    }

    private static S2CGravityRiftPayload snapshot(ServerLevel level) {
        GravityRiftState state = GravityRiftState.get(level.getServer());
        BlockPos anchor = state.anchor() != null ? state.anchor() : BlockPos.ZERO;
        long gameTime = level.getServer().overworld().getGameTime();
        int remaining = (int) Math.max(0L, state.invertUntilGameTime() - gameTime);
        return new S2CGravityRiftPayload(state.built(), anchor, remaining);
    }
}
