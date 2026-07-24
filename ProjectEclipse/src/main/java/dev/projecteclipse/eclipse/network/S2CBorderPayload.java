package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: soft-border ring state of one disc dimension. {@code dim} is the disc
 * profile name ({@code "overworld"} / {@code "nether"}); the ring is animated client-side
 * from {@code fromRadius} to {@code toRadius} over {@code lerpTicks} ticks starting at
 * receipt ({@code lerpTicks == 0} snaps), so a radius change costs exactly one packet.
 * {@code toRadius <= 0} means the ring is inactive in that dimension (nether before its
 * first disc stage). {@code fxRange} is the client FX visibility band in blocks.
 *
 * <p>Sent by {@code border.SoftBorder} at login and on every ring/FX-range change; cached in
 * {@link dev.projecteclipse.eclipse.client.ClientStateCache} and consumed by
 * {@code border.client.BorderFxRenderer}.</p>
 */
public record S2CBorderPayload(String dim, double centerX, double centerZ,
        float fromRadius, float toRadius, int lerpTicks, float fxRange)
        implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CBorderPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "border"));

    // Written explicitly: StreamCodec.composite tops out at 6 components in 1.21.1.
    public static final StreamCodec<ByteBuf, S2CBorderPayload> STREAM_CODEC = StreamCodec.of(
            (buf, payload) -> {
                ByteBufCodecs.STRING_UTF8.encode(buf, payload.dim());
                buf.writeDouble(payload.centerX());
                buf.writeDouble(payload.centerZ());
                buf.writeFloat(payload.fromRadius());
                buf.writeFloat(payload.toRadius());
                ByteBufCodecs.VAR_INT.encode(buf, payload.lerpTicks());
                buf.writeFloat(payload.fxRange());
            },
            buf -> new S2CBorderPayload(
                    ByteBufCodecs.STRING_UTF8.decode(buf),
                    buf.readDouble(),
                    buf.readDouble(),
                    buf.readFloat(),
                    buf.readFloat(),
                    ByteBufCodecs.VAR_INT.decode(buf),
                    buf.readFloat()));

    @Override
    public CustomPacketPayload.Type<S2CBorderPayload> type() {
        return TYPE;
    }
}
