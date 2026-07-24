package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: shatter the first heart that is missing after this respawn. */
public record S2CHeartBurstPayload(int heartIndex) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CHeartBurstPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "heart_burst"));

    public static final StreamCodec<ByteBuf, S2CHeartBurstPayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(S2CHeartBurstPayload::new, S2CHeartBurstPayload::heartIndex);

    @Override
    public CustomPacketPayload.Type<S2CHeartBurstPayload> type() {
        return TYPE;
    }
}
