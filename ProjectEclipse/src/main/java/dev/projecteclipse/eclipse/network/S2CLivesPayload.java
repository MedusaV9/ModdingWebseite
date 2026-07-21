package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/** Server → client: the receiving player's current life count. */
public record S2CLivesPayload(int lives) implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CLivesPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "lives"));

    public static final StreamCodec<ByteBuf, S2CLivesPayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(S2CLivesPayload::new, S2CLivesPayload::lives);

    @Override
    public CustomPacketPayload.Type<S2CLivesPayload> type() {
        return TYPE;
    }
}
