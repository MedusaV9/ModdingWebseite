package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Client → server: a config-file edit from the W14 goal editor GUI. UNTRUSTED input —
 * {@code devtools.ConfigEditor.handleEdit} requires {@code hasPermissions(3)}, allowlists the
 * file name ({@code days.json} / {@code milestones.json}), rejects payloads over
 * {@value #MAX_JSON_BYTES} bytes and re-validates + normalizes the JSON against the
 * {@code EclipseConfig} schema before anything touches disk.
 */
public record C2SConfigEditPayload(String fileName, String json) implements CustomPacketPayload {
    /** Hard size limit (bytes of UTF-8 JSON) enforced on both sides. */
    public static final int MAX_JSON_BYTES = 64 * 1024;

    public static final CustomPacketPayload.Type<C2SConfigEditPayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "config_edit"));

    public static final StreamCodec<ByteBuf, C2SConfigEditPayload> STREAM_CODEC = StreamCodec.composite(
            ByteBufCodecs.stringUtf8(256), C2SConfigEditPayload::fileName,
            ByteBufCodecs.stringUtf8(MAX_JSON_BYTES), C2SConfigEditPayload::json,
            C2SConfigEditPayload::new);

    @Override
    public CustomPacketPayload.Type<C2SConfigEditPayload> type() {
        return TYPE;
    }
}
