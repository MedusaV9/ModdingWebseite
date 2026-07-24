package dev.projecteclipse.eclipse.music;

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

/** Self-registering S2C transport for dev music controls and the credits screen. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class MusicPayloads {
    private static final String VERSION = "music1";

    private MusicPayloads() {}

    /** Empty cue id means stop; otherwise it is one of {@link MusicCues#ids()}. */
    public record S2CMusicCuePayload(String cueId) implements CustomPacketPayload {
        public static final Type<S2CMusicCuePayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "music/cue"));
        public static final StreamCodec<ByteBuf, S2CMusicCuePayload> STREAM_CODEC =
                ByteBufCodecs.STRING_UTF8.map(S2CMusicCuePayload::new, S2CMusicCuePayload::cueId);

        @Override
        public Type<S2CMusicCuePayload> type() {
            return TYPE;
        }
    }

    public record S2COpenCreditsPayload() implements CustomPacketPayload {
        public static final Type<S2COpenCreditsPayload> TYPE = new Type<>(
                ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "music/open_credits"));
        public static final StreamCodec<ByteBuf, S2COpenCreditsPayload> STREAM_CODEC =
                StreamCodec.unit(new S2COpenCreditsPayload());

        @Override
        public Type<S2COpenCreditsPayload> type() {
            return TYPE;
        }
    }

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CMusicCuePayload.TYPE, S2CMusicCuePayload.STREAM_CODEC,
                MusicPayloads::handleCue);
        registrar.playToClient(S2COpenCreditsPayload.TYPE, S2COpenCreditsPayload.STREAM_CODEC,
                MusicPayloads::handleCredits);
    }

    private static void handleCue(S2CMusicCuePayload payload, IPayloadContext context) {
        if (payload.cueId().isEmpty()) {
            MusicCues.stop();
        } else if (!MusicCues.play(payload.cueId())) {
            EclipseMod.LOGGER.warn("Received unknown music cue '{}'", payload.cueId());
        }
    }

    /** Runs on the client main thread only; the client class is resolved lazily, never on the dedicated server. */
    private static void handleCredits(S2COpenCreditsPayload payload, IPayloadContext context) {
        MusicClientHooks.openCredits();
    }

    public static void sendPlay(ServerPlayer player, String cueId) {
        PacketDistributor.sendToPlayer(player, new S2CMusicCuePayload(cueId));
    }

    public static void sendStop(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2CMusicCuePayload(""));
    }

    public static void sendOpenCredits(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2COpenCreditsPayload());
    }
}
