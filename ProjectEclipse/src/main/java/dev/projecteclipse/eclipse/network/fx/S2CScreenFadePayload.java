package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: fullscreen fade (P2 §3.2, FROZEN shape): rise over {@code inTicks}, hold
 * {@code holdTicks}, release over {@code outTicks}, color {@code argb}. Dispatched to W2's
 * {@code cutscene.client.CaptionRenderer#fade}; usable outside cutscenes too.
 */
public record S2CScreenFadePayload(int inTicks, int holdTicks, int outTicks, int argb)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CScreenFadePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/screen_fade"));

    public static final StreamCodec<ByteBuf, S2CScreenFadePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::inTicks,
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::holdTicks,
            ByteBufCodecs.VAR_INT, S2CScreenFadePayload::outTicks,
            ByteBufCodecs.INT, S2CScreenFadePayload::argb,
            S2CScreenFadePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CScreenFadePayload> type() {
        return TYPE;
    }
}
