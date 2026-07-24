package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: open the artifact screen. Always sent AFTER a fresh
 * {@link S2CLivesPayload} + {@link S2CDayStatePayload} on the same connection, so the
 * client cache is guaranteed up to date when the screen opens.
 */
public record S2COpenArtifactPayload() implements CustomPacketPayload {
    public static final CustomPacketPayload.Type<S2COpenArtifactPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "open_artifact"));

    public static final StreamCodec<ByteBuf, S2COpenArtifactPayload> STREAM_CODEC =
            StreamCodec.unit(new S2COpenArtifactPayload());

    @Override
    public CustomPacketPayload.Type<S2COpenArtifactPayload> type() {
        return TYPE;
    }
}
