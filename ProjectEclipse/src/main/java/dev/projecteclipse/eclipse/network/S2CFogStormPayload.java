package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.BlockPos;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: fog-storm site activation bounds for P2 fog walls and lightning visuals.
 * Client handler registration lives in {@code EclipsePayloads} (orchestrator merge).
 */
public record S2CFogStormPayload(String siteId, BlockPos center, int radius, boolean active)
        implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2CFogStormPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fog_storm"));

    public static final StreamCodec<ByteBuf, S2CFogStormPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.STRING_UTF8, S2CFogStormPayload::siteId,
            BlockPos.STREAM_CODEC, S2CFogStormPayload::center,
            ByteBufCodecs.VAR_INT, S2CFogStormPayload::radius,
            ByteBufCodecs.BOOL, S2CFogStormPayload::active,
            S2CFogStormPayload::new);

    @Override
    public Type<S2CFogStormPayload> type() {
        return TYPE;
    }
}
