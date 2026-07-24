package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: request one rebirth (W-SKILLTREE's confirm button, D11). Carries no
 * data on purpose — the server re-validates EVERYTHING (shard balance, Leben cap, event
 * dimension, max-rebirths) in {@code RebirthService.handleRebirthRequest}; the client's
 * cached cost/count are advisory display state only.
 */
public record C2SRebirthPayload() implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SRebirthPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "rebirth_request"));

    public static final StreamCodec<ByteBuf, C2SRebirthPayload> STREAM_CODEC =
            StreamCodec.unit(new C2SRebirthPayload());

    @Override
    public Type<C2SRebirthPayload> type() {
        return TYPE;
    }
}
