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
    /**
     * Cue-id prefix marking a release (clear-if-matching, situation ladder resumes) instead
     * of a play. Cue ids are lowercase identifiers, so the prefix can never collide.
     */
    private static final String RELEASE_PREFIX = "-";
    /**
     * MUSICFADE: cue-id prefix of a timed fade-out — {@code ~<ticks>} fades the channel to
     * silence over that many ticks (an empty id remains the default-length stop). Cue ids
     * are lowercase identifiers, so neither prefix can ever collide with one.
     */
    private static final String FADE_PREFIX = "~";
    /** Hard bound on a requested fade length (~30 s) — a bad packet can never wedge audio. */
    private static final int MAX_FADE_TICKS = 600;

    private MusicPayloads() {}

    /**
     * Empty cue id means stop; {@code -id} means release; {@code ~ticks} means a timed
     * fade-out; otherwise one of {@link MusicCues#ids()}.
     */
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
        String cueId = payload.cueId();
        if (cueId.isEmpty()) {
            MusicCues.stop();
        } else if (cueId.startsWith(FADE_PREFIX)) {
            MusicCues.fadeOut(parseFadeTicks(cueId.substring(FADE_PREFIX.length())));
        } else if (cueId.startsWith(RELEASE_PREFIX)) {
            if (!MusicCues.release(cueId.substring(RELEASE_PREFIX.length()))) {
                EclipseMod.LOGGER.warn("Received unknown music release '{}'", cueId);
            }
        } else if (!MusicCues.play(cueId)) {
            EclipseMod.LOGGER.warn("Received unknown music cue '{}'", cueId);
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

    /** MUSICFADE: fades the client's music channel to silence over {@code ticks}. */
    public static void sendFadeOut(ServerPlayer player, int ticks) {
        PacketDistributor.sendToPlayer(player,
                new S2CMusicCuePayload(FADE_PREFIX + clampFadeTicks(ticks)));
    }

    private static int parseFadeTicks(String raw) {
        try {
            return clampFadeTicks(Integer.parseInt(raw));
        } catch (NumberFormatException e) {
            EclipseMod.LOGGER.warn("Received malformed music fade '{}' — using the default fade", raw);
            return 40;
        }
    }

    private static int clampFadeTicks(int ticks) {
        return Math.max(1, Math.min(MAX_FADE_TICKS, ticks));
    }

    /** Releases a forced cue without muting the situation ladder (see {@link MusicCues#release}). */
    public static void sendRelease(ServerPlayer player, String cueId) {
        PacketDistributor.sendToPlayer(player, new S2CMusicCuePayload(RELEASE_PREFIX + cueId));
    }

    public static void sendOpenCredits(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2COpenCreditsPayload());
    }
}
