package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: real-time day clock state for sidebar countdown and boundary spool
 * animation (R1). Client derives offset from {@code serverNowEpochMillis}.
 *
 * <p>{@code timerColorMode} is the operator-set {@code /dev timer color} display mode for
 * the client {@code DayTimerLayer}: {@code auto} (default urgency ramp), {@code text},
 * {@code accent}, {@code deep}, or a {@code #rrggbb} literal.</p>
 */
public record S2CDayClockPayload(
        int day,
        long boundaryEpochMillis,
        long prevBoundaryEpochMillis,
        long serverNowEpochMillis,
        boolean paused,
        long pauseRemainingMillis,
        String timerColorMode) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CDayClockPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_clock"));

    // 7 fields — past StreamCodec.composite's 6-parameter overloads, so explicit encode/decode.
    public static final StreamCodec<ByteBuf, S2CDayClockPayload> STREAM_CODEC = StreamCodec.of(
            (buffer, payload) -> {
                ByteBufCodecs.VAR_INT.encode(buffer, payload.day());
                ByteBufCodecs.VAR_LONG.encode(buffer, payload.boundaryEpochMillis());
                ByteBufCodecs.VAR_LONG.encode(buffer, payload.prevBoundaryEpochMillis());
                ByteBufCodecs.VAR_LONG.encode(buffer, payload.serverNowEpochMillis());
                ByteBufCodecs.BOOL.encode(buffer, payload.paused());
                ByteBufCodecs.VAR_LONG.encode(buffer, payload.pauseRemainingMillis());
                ByteBufCodecs.STRING_UTF8.encode(buffer, payload.timerColorMode());
            },
            buffer -> new S2CDayClockPayload(
                    ByteBufCodecs.VAR_INT.decode(buffer),
                    ByteBufCodecs.VAR_LONG.decode(buffer),
                    ByteBufCodecs.VAR_LONG.decode(buffer),
                    ByteBufCodecs.VAR_LONG.decode(buffer),
                    ByteBufCodecs.BOOL.decode(buffer),
                    ByteBufCodecs.VAR_LONG.decode(buffer),
                    ByteBufCodecs.STRING_UTF8.decode(buffer)));

    @Override
    public Type<S2CDayClockPayload> type() {
        return TYPE;
    }
}
