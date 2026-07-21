package dev.projecteclipse.eclipse.network;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: current event day, altar level, and the day's goal lines. */
public record S2CDayStatePayload(int day, int altarLevel, List<String> goals) implements CustomPacketPayload {
    public S2CDayStatePayload {
        goals = List.copyOf(goals);
    }

    public static final CustomPacketPayload.Type<S2CDayStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_state"));

    public static final StreamCodec<ByteBuf, S2CDayStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::day,
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::altarLevel,
            ByteBufCodecs.STRING_UTF8.apply(ByteBufCodecs.list()), S2CDayStatePayload::goals,
            S2CDayStatePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CDayStatePayload> type() {
        return TYPE;
    }
}
