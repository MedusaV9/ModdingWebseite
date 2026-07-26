package dev.projecteclipse.eclipse.network;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.core.UUIDUtil;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: one CHUNK of a player's skin-override PNG (F-050/F-051), or the
 * {@code reset} marker that drops an override again.
 *
 * <p>The whole point of shipping the image ourselves is that Project: Eclipse is mandatory
 * on clients, so an operator skin does NOT have to be a Mojang-signed profile texture — no
 * profile edit, no session server, no re-login. The bytes are a plain, already validated and
 * normalized 64×64 PNG (see {@code skin.SkinImages}).</p>
 *
 * <p>Chunking follows the PAYLOADFIX (F-001) discipline: a skin is capped at 256 KiB, which
 * would still fit one play-phase payload, but splitting at {@value #MAX_CHUNK_BYTES} keeps a
 * login sync of many overrides from parking hundreds of KiB in a single frame. Chunk 0 opens
 * a fresh assembly on the client, the last chunk ({@code chunkIndex == chunkCount - 1})
 * commits it — payload order on one connection is guaranteed, so no transfer id is needed.</p>
 */
public record S2CSkinOverridePayload(
        UUID player,
        boolean reset,
        boolean slim,
        int chunkIndex,
        int chunkCount,
        byte[] chunk) implements CustomPacketPayload {

    /** Wire size of one chunk; a 256 KiB skin therefore costs at most 8 payloads. */
    public static final int MAX_CHUNK_BYTES = 32 * 1024;

    public static final CustomPacketPayload.Type<S2CSkinOverridePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "skin_override"));

    private static final StreamCodec<ByteBuf, byte[]> CHUNK_CODEC = ByteBufCodecs.byteArray(MAX_CHUNK_BYTES);

    public static final StreamCodec<ByteBuf, S2CSkinOverridePayload> STREAM_CODEC = StreamCodec.of(
            S2CSkinOverridePayload::encode,
            S2CSkinOverridePayload::decode);

    /** The "override is gone" marker; carries no image bytes. */
    public static S2CSkinOverridePayload reset(UUID player) {
        return new S2CSkinOverridePayload(player, true, false, 0, 0, new byte[0]);
    }

    /** Splits a validated PNG into wire chunks (at least one, even for an empty image). */
    public static List<S2CSkinOverridePayload> split(UUID player, byte[] png, boolean slim) {
        int count = Math.max(1, (png.length + MAX_CHUNK_BYTES - 1) / MAX_CHUNK_BYTES);
        List<S2CSkinOverridePayload> parts = new ArrayList<>(count);
        for (int index = 0; index < count; index++) {
            int from = index * MAX_CHUNK_BYTES;
            int to = Math.min(png.length, from + MAX_CHUNK_BYTES);
            byte[] slice = new byte[Math.max(0, to - from)];
            System.arraycopy(png, from, slice, 0, slice.length);
            parts.add(new S2CSkinOverridePayload(player, false, slim, index, count, slice));
        }
        return parts;
    }

    private static void encode(ByteBuf buf, S2CSkinOverridePayload value) {
        UUIDUtil.STREAM_CODEC.encode(buf, value.player());
        ByteBufCodecs.BOOL.encode(buf, value.reset());
        ByteBufCodecs.BOOL.encode(buf, value.slim());
        ByteBufCodecs.VAR_INT.encode(buf, value.chunkIndex());
        ByteBufCodecs.VAR_INT.encode(buf, value.chunkCount());
        CHUNK_CODEC.encode(buf, value.chunk());
    }

    private static S2CSkinOverridePayload decode(ByteBuf buf) {
        return new S2CSkinOverridePayload(
                UUIDUtil.STREAM_CODEC.decode(buf),
                ByteBufCodecs.BOOL.decode(buf),
                ByteBufCodecs.BOOL.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                ByteBufCodecs.VAR_INT.decode(buf),
                CHUNK_CODEC.decode(buf));
    }

    @Override
    public CustomPacketPayload.Type<S2CSkinOverridePayload> type() {
        return TYPE;
    }
}
