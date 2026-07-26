package dev.projecteclipse.eclipse.network;

import dev.projecteclipse.eclipse.EclipseMod;
import io.netty.buffer.ByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;

/**
 * Shared string codecs for Eclipse payloads (PAYLOADFIX / F-001).
 *
 * <p><b>Why this exists</b>: {@code ByteBufCodecs.STRING_UTF8} hard-fails the ENCODE with
 * {@code EncoderException("String too big")} at 32,767 chars ({@code Utf8String.write}).
 * Any payload that ships config-/operator-grown documents (cutscene JSONs, the skill tree
 * blob, quest text) through it turns one oversized string into a full client kick —
 * "Failed to encode packet 'clientbound/minecraft:custom_payload'" — on EVERY login,
 * because {@code IdDispatchCodec.encode} wraps the codec exception and netty tears the
 * connection down. Singleplayer is NOT exempt: since 1.20.5 the in-memory pipeline runs
 * {@code PacketEncoder} too (only the frame prepender is a no-op).</p>
 *
 * <p>Two remedies, chosen per field:</p>
 * <ul>
 *   <li>{@link #LARGE_UTF8} — an explicitly large bound for whole-document fields whose
 *       content must not be mutated (JSON blobs). Senders must still budget the payload
 *       (see {@code CutsceneService.libraryChunks} / {@code SkillService.sendTree}).</li>
 *   <li>{@link #clampedUtf8(int)} — display-text fields where silent truncation (plus a
 *       WARN log) is strictly better than kicking the player.</li>
 * </ul>
 */
public final class NetCodecs {
    /**
     * Char bound of one large synced document (256K chars ⇒ ≤ 768 KiB UTF-8 bytes), safely
     * inside the 1 MiB play-phase custom-payload budget with the id/framing overhead.
     */
    public static final int LARGE_DOC_MAX_CHARS = 256 * 1024;

    /** Whole-document string codec (JSON blobs). Encode still fails above the bound — senders must budget. */
    public static final StreamCodec<ByteBuf, String> LARGE_UTF8 =
            ByteBufCodecs.stringUtf8(LARGE_DOC_MAX_CHARS);

    private NetCodecs() {}

    /**
     * Display-text codec that TRUNCATES oversized values on encode (WARN log) instead of
     * throwing — a cut-off HUD line is recoverable, a kicked player is not. Truncation is
     * surrogate-safe. Decode uses the same char bound.
     */
    public static StreamCodec<ByteBuf, String> clampedUtf8(int maxChars) {
        StreamCodec<ByteBuf, String> bounded = ByteBufCodecs.stringUtf8(maxChars);
        return StreamCodec.of(
                (buf, value) -> bounded.encode(buf, clamp(value, maxChars)),
                bounded::decode);
    }

    /** Surrogate-safe truncation used by {@link #clampedUtf8(int)}; logs when it fires. */
    public static String clamp(String value, int maxChars) {
        if (value.length() <= maxChars) {
            return value;
        }
        int cut = maxChars;
        if (Character.isHighSurrogate(value.charAt(cut - 1))) {
            cut--;
        }
        EclipseMod.LOGGER.warn(
                "Payload string over {} chars ({}) — truncating instead of kicking the client: '{}…'",
                maxChars, value.length(), value.substring(0, Math.min(48, cut)));
        return value.substring(0, cut);
    }
}
