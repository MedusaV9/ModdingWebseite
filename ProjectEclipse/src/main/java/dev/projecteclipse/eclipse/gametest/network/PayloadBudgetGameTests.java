package dev.projecteclipse.eclipse.gametest.network;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.network.NetCodecs;
import dev.projecteclipse.eclipse.network.S2CCutsceneLibraryPayload;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.S2CSkillTreePayload;
import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.network.codec.StreamCodec;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * PAYLOADFIX (F-001) budget acceptance: every payload that carries config-/operator-grown
 * strings must encode realistic MAXIMUM data without an {@code EncoderException} (which
 * kicks the joining player with "Failed to encode packet
 * 'clientbound/minecraft:custom_payload'") and must stay under 900 KB per packet — safety
 * margin below the vanilla 1 MiB play-phase custom-payload cap (NeoForge does NOT split
 * oversized payloads automatically).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class PayloadBudgetGameTests {
    /** Per-packet budget: 1 MiB play-phase cap minus id/framing headroom. */
    private static final int MAX_ENCODED_BYTES = 900 * 1024;

    private PayloadBudgetGameTests() {}

    /** Encodes with the wire codec, asserts the budget, and returns the decoded value. */
    private static <T> T encodeWithinBudget(StreamCodec<ByteBuf, T> codec, T value) {
        ByteBuf buf = Unpooled.buffer();
        try {
            codec.encode(buf, value);
            if (buf.readableBytes() > MAX_ENCODED_BYTES) {
                throw new AssertionError("Encoded payload is " + buf.readableBytes()
                        + " bytes — over the " + MAX_ENCODED_BYTES + " byte budget");
            }
            return codec.decode(buf);
        } finally {
            buf.release();
        }
    }

    private static String repeat(char c, int count) {
        return String.valueOf(c).repeat(count);
    }

    /**
     * The exact F-001 regression: a skill tree / cutscene document beyond the old 32,767-char
     * {@code STRING_UTF8} bound must now encode cleanly (it used to throw
     * {@code EncoderException: String too big} and kick every joining player).
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void oversized32kDocumentsEncode(GameTestHelper helper) {
        String doc40k = "{\"nodes\":[\"" + repeat('a', 40_000) + "\"]}";
        S2CSkillTreePayload tree = encodeWithinBudget(S2CSkillTreePayload.STREAM_CODEC,
                new S2CSkillTreePayload(doc40k));
        helper.assertTrue(doc40k.equals(tree.json()), "40K-char skill tree survives unchanged");

        S2CCutsceneLibraryPayload lib = encodeWithinBudget(S2CCutsceneLibraryPayload.STREAM_CODEC,
                new S2CCutsceneLibraryPayload(true, Map.of("intro", doc40k)));
        helper.assertTrue(doc40k.equals(lib.pathsJson().get("intro")),
                "40K-char cutscene doc survives unchanged");
        helper.succeed();
    }

    /** Skill tree at the codec's LARGE_DOC bound encodes and stays under the packet budget. */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void skillTreeAtMaxBoundWithinBudget(GameTestHelper helper) {
        String maxDoc = repeat('x', NetCodecs.LARGE_DOC_MAX_CHARS);
        S2CSkillTreePayload decoded = encodeWithinBudget(S2CSkillTreePayload.STREAM_CODEC,
                new S2CSkillTreePayload(maxDoc));
        helper.assertTrue(decoded.json().length() == NetCodecs.LARGE_DOC_MAX_CHARS,
                "max-bound skill tree round-trips");
        helper.succeed();
    }

    /**
     * Realistic-max cutscene library (many multi-10K docs + one illegal oversized one):
     * every chunk encodes under budget, the first chunk resets, followers merge, and the
     * oversized document is dropped by the sanitizer instead of throwing in the encoder.
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void cutsceneLibraryChunksWithinBudget(GameTestHelper helper) {
        Map<String, String> library = new LinkedHashMap<>();
        for (int i = 0; i < 24; i++) {
            library.put("path_" + i, "{\"points\":\"" + repeat('p', 60_000) + "\"}");
        }
        String tooBigId = "path_too_big";
        library.put(tooBigId, repeat('z', NetCodecs.LARGE_DOC_MAX_CHARS + 1));

        List<S2CCutsceneLibraryPayload> chunks = CutsceneService.libraryChunks(library);
        helper.assertTrue(chunks.size() > 1, "library splits into multiple chunks");
        helper.assertTrue(chunks.get(0).reset(), "first chunk resets the client cache");

        Map<String, String> reassembled = new LinkedHashMap<>();
        for (int i = 0; i < chunks.size(); i++) {
            S2CCutsceneLibraryPayload chunk = chunks.get(i);
            helper.assertTrue(chunk.reset() == (i == 0), "only the first chunk resets");
            S2CCutsceneLibraryPayload decoded =
                    encodeWithinBudget(S2CCutsceneLibraryPayload.STREAM_CODEC, chunk);
            reassembled.putAll(decoded.pathsJson());
        }
        helper.assertTrue(!reassembled.containsKey(tooBigId), "oversized doc dropped, not sent");
        helper.assertTrue(reassembled.size() <= library.size() - 1, "reassembly has no extras");
        for (Map.Entry<String, String> entry : reassembled.entrySet()) {
            helper.assertTrue(entry.getValue().equals(library.get(entry.getKey())),
                    "synced doc unchanged: " + entry.getKey());
        }
        helper.succeed();
    }

    /**
     * Display-text payloads (quest rows, day goal lines) must CLAMP absurd operator text
     * instead of throwing: a truncated HUD line is recoverable, a kicked player is not.
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void displayTextsClampInsteadOfKick(GameTestHelper helper) {
        String essay = repeat('e', 100_000);
        S2CQuestStatePayload quests = encodeWithinBudget(S2CQuestStatePayload.STREAM_CODEC,
                new S2CQuestStatePayload(3, List.of(
                        new S2CQuestStatePayload.QuestEntry("q_long", (byte) 0, essay, essay,
                                1, 8, false, false, 2, 30))));
        S2CQuestStatePayload.QuestEntry entry = quests.entries().get(0);
        helper.assertTrue(entry.textEn().length() == 4096, "quest textEn clamped to 4096");
        helper.assertTrue(entry.textDe().length() == 4096, "quest textDe clamped to 4096");
        helper.assertTrue("q_long".equals(entry.id()), "short id untouched");

        S2CDayStatePayload day = encodeWithinBudget(S2CDayStatePayload.STREAM_CODEC,
                new S2CDayStatePayload(3, 2, List.of("normal goal", essay)));
        helper.assertTrue("normal goal".equals(day.goals().get(0)), "short goal untouched");
        helper.assertTrue(day.goals().get(1).length() == 2048, "long goal clamped to 2048");
        helper.succeed();
    }
}
