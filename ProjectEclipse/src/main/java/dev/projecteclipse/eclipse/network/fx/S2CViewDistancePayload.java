package dev.projecteclipse.eclipse.network.fx;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: temporary cinematic view-distance request (P2 §3.2, FROZEN shape).
 * {@code chunks == 0} restores the player's own setting. Dispatched to W2's
 * {@code cutscene.client.ViewDistanceClient#handle}; the client only obeys while
 * {@code EclipseClientConfig#cinematicViewDistance()} is enabled.
 */
public record S2CViewDistancePayload(int chunks) implements CustomPacketPayload {

    public static final CustomPacketPayload.Type<S2CViewDistancePayload> TYPE = new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fx/view_distance"));

    public static final StreamCodec<ByteBuf, S2CViewDistancePayload> STREAM_CODEC =
            ByteBufCodecs.VAR_INT.map(S2CViewDistancePayload::new, S2CViewDistancePayload::chunks);

    @Override
    public CustomPacketPayload.Type<S2CViewDistancePayload> type() {
        return TYPE;
    }
}
