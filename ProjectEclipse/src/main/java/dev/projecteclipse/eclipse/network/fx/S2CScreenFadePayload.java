package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: fullscreen fade (P2 §3.2): rise over {@code inTicks}, hold
 * {@code holdTicks}, release over {@code outTicks}, color {@code argb}. Dispatched to W2's
 * {@code cutscene.client.CaptionRenderer#fade}; usable outside cutscenes too.
 *
 * <p><b>{@code sustained}</b> (BLACKSCREEN fix) marks the few holds a controller owns and
 * is contractually going to release itself — the credits' card-to-card blacks and the
 * cutscene chunk-preload veil. Everything else is clamped client-side to
 * {@code CaptionRenderer.MAX_HOLD_TICKS} so no stray or desynced fade can park the screen
 * at black; see that constant for the rationale. The four-argument constructor (the
 * original, frozen shape) keeps every existing sender on the safe default.</p>
 */
public record S2CScreenFadePayload(int inTicks, int holdTicks, int outTicks, int argb,
        boolean sustained) implements CustomPacketPayload {

    /** Safe default: a fade the client is free to time out. */
    public S2CScreenFadePayload(int inTicks, int holdTicks, int outTicks, int argb) {
        this(inTicks, holdTicks, outTicks, argb, false);
    }

    /** A hold whose owning sequence guarantees the release (see the class doc). */
    public static S2CScreenFadePayload sustained(int inTicks, int holdTicks, int outTicks, int argb) {
        return new S2CScreenFadePayload(inTicks, holdTicks, outTicks, argb, true);
    }

    public static final CustomPacketPayload.Type<S2CScreenFadePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/screen_fade"));

    public static final StreamCodec<ByteBuf, S2CScreenFadePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::inTicks,
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::holdTicks,
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::outTicks,
            ByteBufCodecs.INT, S2CScreenFadePayload::argb,
            ByteBufCodecs.BOOL, S2CScreenFadePayload::sustained,
            S2CScreenFadePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CScreenFadePayload> type() {
        return TYPE;
    }
}
