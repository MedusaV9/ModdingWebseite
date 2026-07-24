package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: request fresh artifact-menu data. The server replies with
 * {@link S2CLivesPayload} + {@link S2CDayStatePayload} followed by
 * {@link S2COpenArtifactPayload} (see {@code EclipsePayloads.sendArtifactState}).
 */
public record C2SOpenArtifactPayload() implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<C2SOpenArtifactPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "open_artifact_request"));

    public static final StreamCodec<ByteBuf, C2SOpenArtifactPayload> STREAM_CODEC =
            StreamCodec.unit(new C2SOpenArtifactPayload());

    @Override
    public CustomPacketPayload.Type<C2SOpenArtifactPayload> type() {
        return TYPE;
    }
}
