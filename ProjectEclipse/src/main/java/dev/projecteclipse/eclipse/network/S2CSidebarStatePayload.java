package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: consolidated sidebar stats (R18). No online player count — removed by design. */
public record S2CSidebarStatePayload(
        int day,
        long boundaryEpochMillis,
        boolean paused,
        int skillLevel,
        int xpIntoLevel,
        int xpForLevel,
        int altarLevel,
        int mainsDone,
        int mainsTotal,
        int sidesDone,
        int sidesTotal,
        int personalsDone,
        int personalsTotal,
        List<String> buffIds,
        int shards) implements CustomPacketPayload {

    public S2CSidebarStatePayload {
        buffIds = List.copyOf(buffIds);
    }

    public static final CustomPacketPayload.Type<S2CSidebarStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "sidebar_state"));

    public static final StreamCodec<ByteBuf, S2CSidebarStatePayload> STREAM_CODEC = StreamCodec.of(
            S2CSidebarStatePayload::encode,
            S2CSidebarStatePayload::decode);

    private static void encode(ByteBuf buf, S2CSidebarStatePayload value) {
        ByteBufCodecs.VAR_INT.encode(buf, value.day());
        ByteBufCodecs.VAR_LONG.encode(buf, value.boundaryEpochMillis());
        ByteBufCodecs.BOOL.encode(buf, value.paused());
        ByteBufCodecs.VAR_INT.encode(buf, value.skillLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.xpIntoLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.xpForLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.altarLevel());
        ByteBufCodecs.VAR_INT.encode(buf, value.mainsDone());
        ByteBufCodecs.VAR_INT.encode(buf, value.mainsTotal());
        ByteBufCodecs.VAR_INT.encode(buf, value.sidesDone());
        ByteBufCodecs.VAR_INT.encode(buf, value.sidesTotal());
        ByteBufCodecs.VAR_INT.encode(buf, value.personalsDone());
        ByteBufCodecs.VAR_INT.encode(buf, value.personalsTotal());
        ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).encode(buf, value.buffIds());
        ByteBufCodecs.VAR_INT.encode(buf, value.shards());
    }

    private static S2CSidebarStatePayload decode(ByteBuf buf) {
        return new S2CSidebarStatePayload(
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_LONG.decode(buf),
                ByteBufCodecs.BOOL.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()).decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf));
    }

    @Override
    public Type<S2CSidebarStatePayload> type() {
        return TYPE;
    }
}
