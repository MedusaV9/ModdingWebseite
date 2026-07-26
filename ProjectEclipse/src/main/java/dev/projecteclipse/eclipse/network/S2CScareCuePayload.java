package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;

/**
 * Server → client: play ONE scare script on the receiving player only (F-064/F-065 —
 * the Scare framework). The payload is deliberately tiny: a {@code scareId} naming a
 * client-side script from {@code client.scare.ScareScripts} plus a {@code seed} so
 * per-run randomization (glitch-text character rolls, overlay jitter phases, timing
 * wobble) is decided once by the server and every replay of the same send looks the
 * same. Everything visible/audible is produced purely client-side by
 * {@code client.scare.ScareDirector} — the server never spawns entities, particles or
 * sounds for a scare, so ONLY the targeted player ever perceives it.
 *
 * <p>Unknown ids are ignored with a debug log (an old client meeting a new script name
 * degrades to nothing rather than misbehaving). The id is bounds-clamped through
 * {@link NetCodecs#clampedUtf8} like every other short-string payload field.</p>
 */
public record S2CScareCuePayload(String scareId, long seed) implements CustomPacketPayload {
    /** Script ids are short slugs ({@code static_face}); 64 chars is generous headroom. */
    public static final int MAX_ID_CHARS = 64;

    public static final CustomPacketPayload.Type<S2CScareCuePayload> TYPE =
            new CustomPacketPayload.Type<>(ResourceLocation.fromNamespaceAndPath(
                    EclipseMod.MOD_ID, "scare_cue"));

    public static final StreamCodec<ByteBuf, S2CScareCuePayload> STREAM_CODEC = StreamCodec.composite(
            NetCodecs.clampedUtf8(MAX_ID_CHARS), S2CScareCuePayload::scareId,
            ByteBufCodecs.VAR_LONG, S2CScareCuePayload::seed,
            S2CScareCuePayload::new);

    @Override
    public CustomPacketPayload.Type<S2CScareCuePayload> type() {
        return TYPE;
    }
}
