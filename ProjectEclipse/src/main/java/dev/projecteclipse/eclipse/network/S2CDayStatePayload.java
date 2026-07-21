package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: current event day and altar level. */
public record S2CDayStatePayload(int day, int altarLevel) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CDayStatePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_state"));

    public static final StreamCodec<ByteBuf, S2CDayStatePayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::day,
            ByteBufCodecs.VAR_INT, S2CDayStatePayload::altarLevel,
            S2CDayStatePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CDayStatePayload> type() {
        return TYPE;
    }
}
