package dev.projecteclipse.eclipse.network;

import java.util.LinkedHashMap;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: the full cutscene path library as raw JSON documents keyed by path id
 * (a few KB). Sent on login and after {@code /eclipse cutscene reloadpaths} / editor writes /
 * {@code /eclipse reload}; the client re-parses each document with
 * {@code cutscene.CutscenePath.parse} and replaces its cached library wholesale.
 */
public record S2CCutsceneLibraryPayload(Map<String, String> pathsJson) implements CustomPacketPayload {
    public S2CCutsceneLibraryPayload {
        pathsJson = Map.copyOf(pathsJson);
    }

    public static final CustomPacketPayload.Type<S2CCutsceneLibraryPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_library"));

    public static final StreamCodec<ByteBuf, S2CCutsceneLibraryPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.map(LinkedHashMap::new, ByteBufCodecs.STRING_UTF8, ByteBufCodecs.STRING_UTF8),
            S2CCutsceneLibraryPayload::pathsJson,
            S2CCutsceneLibraryPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CCutsceneLibraryPayload> type() {
        return TYPE;
    }
}
