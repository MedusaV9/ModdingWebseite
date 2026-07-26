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
 * Server → client: one CHUNK of the cutscene path library as raw JSON documents keyed by
 * path id. Sent on login and after {@code /eclipse cutscene reloadpaths} / editor writes /
 * {@code /eclipse reload}; the client re-parses each document with
 * {@code cutscene.CutscenePath.parse}.
 *
 * <p>PAYLOADFIX (F-001): the library used to ride in ONE payload whose values went through
 * plain {@code STRING_UTF8} — a single path document over 32,767 chars (easily produced by
 * the in-game path editor; the old 512 KiB TOTAL cap explicitly allowed it) made the encoder
 * throw and kicked the joining player with "Failed to encode packet
 * 'clientbound/minecraft:custom_payload'". The library is now split into chunks by
 * {@code CutsceneService.libraryChunks}: {@code reset=true} on the first chunk replaces the
 * client cache, following chunks merge into it. Values use {@link NetCodecs#LARGE_UTF8}
 * (256K chars) and each chunk stays far below the 1 MiB play-phase payload budget.</p>
 */
public record S2CCutsceneLibraryPayload(boolean reset, Map<String, String> pathsJson)
        implements CustomPacketPayload {
    public S2CCutsceneLibraryPayload {
        pathsJson = Map.copyOf(pathsJson);
    }

    public static final CustomPacketPayload.Type<S2CCutsceneLibraryPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "cutscene_library"));

    public static final StreamCodec<ByteBuf, S2CCutsceneLibraryPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.BOOL, S2CCutsceneLibraryPayload::reset,
            ByteBufCodecs.map(LinkedHashMap::new, ByteBufCodecs.stringUtf8(256), NetCodecs.LARGE_UTF8),
            S2CCutsceneLibraryPayload::pathsJson,
            S2CCutsceneLibraryPayload::new);

    @Override
    public CustomPacketPayload.Type<S2CCutsceneLibraryPayload> type() {
        return TYPE;
    }
}
