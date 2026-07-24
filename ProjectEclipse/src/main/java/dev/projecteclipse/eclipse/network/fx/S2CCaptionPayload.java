package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: cinematic caption (P2 §3.2, FROZEN shape). {@code style}: 0=SUBTITLE,
 * 1=TITLE, 2=WHISPER. Dispatched to W2's {@code cutscene.client.CaptionRenderer#enqueue}
 * (drawn inside the letterbox layer, immune to cutscene HUD suppression). {@code langKey}
 * is translated client-side — all caption strings ship en+de via langdrop.
 */
public record S2CCaptionPayload(String langKey, int durationTicks, int style)
        implements CustomPacketPayload {

    public static final int STYLE_SUBTITLE = 0;
    public static final int STYLE_TITLE = 1;
    public static final int STYLE_WHISPER = 2;

    public static final CustomPacketPayload.Type<S2CCaptionPayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/caption"));

    public static final StreamCodec<ByteBuf, S2CCaptionPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CCaptionPayload::langKey,
            ByteBufCodecs.VAR_INT, S2CCaptionPayload::durationTicks,
            ByteBufCodecs.VAR_INT, S2CCaptionPayload::style,
            S2CCaptionPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CCaptionPayload> type() {
        return TYPE;
    }
}
