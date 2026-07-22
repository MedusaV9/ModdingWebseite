package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.timeline.TimelineEntry;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Full anonymized event timeline, sent by {@code timeline.TimelineService} at login and on
 * every day/altar change. Cached in {@code ClientStateCache.timeline}; W9's handbook
 * timeline tab renders from that cache.
 */
public record S2CTimelinePayload(List<TimelineEntry> entries) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CTimelinePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "timeline"));

    public static final StreamCodec<ByteBuf, S2CTimelinePayload> STREAM_CODEC = StreamCodec.composite(
            TimelineEntry.STREAM_CODEC.apply(ByteBufCodecs.list()), S2CTimelinePayload::entries,
            S2CTimelinePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CTimelinePayload> type() {
        return TYPE;
    }
}
