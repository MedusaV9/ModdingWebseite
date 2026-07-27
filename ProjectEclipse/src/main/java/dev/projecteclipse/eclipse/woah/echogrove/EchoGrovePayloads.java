package dev.projecteclipse.eclipse.woah.echogrove;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;

/**
 * WOAH-05 self-registering payload registrar (plan §3.7) — the sanctioned
 * {@code network.altar.AltarPayloads} pattern: own MOD-bus
 * {@link RegisterPayloadHandlersEvent} subscriber under its own version group,
 * so the shared {@code network.EclipsePayloads} hub stays untouched. The single
 * payload mirrors quest flags to the client (grade afterglow floor, orb glow
 * variants); it is sent on login and on every state change — never per tick.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EchoGrovePayloads {
    private static final String VERSION = "v1woahecho";

    private EchoGrovePayloads() {}

    /**
     * Server → all: grove lifecycle + quest snapshot. {@code treeCenter} is
     * {@code BlockPos.ZERO} until placed (the {@code placed} flag gates all use).
     */
    public record S2CEchoGrovePayload(boolean placed, BlockPos treeCenter, int collectedMask,
            int deposited, boolean finaleDone) implements CustomPacketPayload {

        public static final CustomPacketPayload.Type<S2CEchoGrovePayload> TYPE =
                new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                        EclipseMod.MOD_ID, "woah_echo/state"));

        public static final StreamCodec<ByteBuf, S2CEchoGrovePayload> STREAM_CODEC =
                StreamCodec.composite(
                        ByteBufCodecs.BOOL, S2CEchoGrovePayload::placed,
                        BlockPos.STREAM_CODEC, S2CEchoGrovePayload::treeCenter,
                        ByteBufCodecs.VAR_INT, S2CEchoGrovePayload::collectedMask,
                        ByteBufCodecs.VAR_INT, S2CEchoGrovePayload::deposited,
                        ByteBufCodecs.BOOL, S2CEchoGrovePayload::finaleDone,
                        S2CEchoGrovePayload::new);

        @Override
        public CustomPacketPayload.Type<S2CEchoGrovePayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CEchoGrovePayload.TYPE, S2CEchoGrovePayload.STREAM_CODEC,
                EchoGrovePayloads::handleState);
    }

    /** Runs on the client main thread; client class resolved lazily (dedicated-server safe). */
    private static void handleState(S2CEchoGrovePayload payload, IPayloadContext context) {
        dev.projecteclipse.eclipse.client.echo.EchoGroveClientState.handleState(payload);
    }

    // ------------------------------------------------------------------ senders

    /** Login sync (the S2CGhostRevealPayload "once, then on change" law). */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            PacketDistributor.sendToPlayer(player, snapshot(player.server));
        }
    }

    /** Broadcast after every quest/lifecycle change (deposit, collect, finale, reset). */
    public static void syncAll(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(snapshot(server));
    }

    private static S2CEchoGrovePayload snapshot(MinecraftServer server) {
        EchoGroveState state = EchoGroveState.get(server);
        BlockPos tree = state.treeCenter() != null ? state.treeCenter() : BlockPos.ZERO;
        return new S2CEchoGrovePayload(state.placed(), tree, state.collectedOrbs(),
                state.deposited(), state.finaleDone());
    }
}
