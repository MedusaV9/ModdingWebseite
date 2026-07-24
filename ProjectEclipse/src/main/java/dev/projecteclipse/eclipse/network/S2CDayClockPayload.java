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
 */
public record S2CDayClockPayload(
        int day,
        long boundaryEpochMillis,
        long prevBoundaryEpochMillis,
        long serverNowEpochMillis,
        boolean paused,
        long pauseRemainingMillis) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CDayClockPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_clock"));

    public static final StreamCodec<ByteBuf, S2CDayClockPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CDayClockPayload::day,
            ByteBufCodecs.VAR_LONG, S2CDayClockPayload::boundaryEpochMillis,
            ByteBufCodecs.VAR_LONG, S2CDayClockPayload::prevBoundaryEpochMillis,
            ByteBufCodecs.VAR_LONG, S2CDayClockPayload::serverNowEpochMillis,
            ByteBufCodecs.BOOL, S2CDayClockPayload::paused,
            ByteBufCodecs.VAR_LONG, S2CDayClockPayload::pauseRemainingMillis,
            S2CDayClockPayload::new);

    @Override
    public Type<S2CDayClockPayload> type() {
        return TYPE;
    }
}
