package dev.projecteclipse.eclipse.gametest.goals;

import java.util.HashSet;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.goals.QuestMath;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B2 pure draw-math tests (plan §3.3 acceptance "draw determinism"): seeds and weighted
 * draws are reproducible bit-for-bit, without replacement, and never pick zero weights.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class QuestMathTest {
    private QuestMathTest() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void seedDeterministicAndSensitive(GameTestHelper helper) {
        UUID uuid = GameTestSupport.testUuid(7);
        long seed = QuestMath.seed(1234L, uuid, 3, 0);
        helper.assertTrue(seed == QuestMath.seed(1234L, uuid, 3, 0), "same inputs → same seed");
        helper.assertTrue(seed != QuestMath.seed(1234L, uuid, 4, 0), "day changes seed");
        helper.assertTrue(seed != QuestMath.seed(1234L, uuid, 3, 1), "nonce changes seed");
        helper.assertTrue(seed != QuestMath.seed(1235L, uuid, 3, 0), "world seed changes seed");
        helper.assertTrue(seed != QuestMath.seed(1234L, GameTestSupport.testUuid(8), 3, 0),
                "uuid changes seed");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void drawDeterministicDistinctAndWeighted(GameTestHelper helper) {
        List<QuestMath.Candidate> pool = List.of(
                new QuestMath.Candidate("a", 1),
                new QuestMath.Candidate("b", 5),
                new QuestMath.Candidate("c", 1),
                new QuestMath.Candidate("zero", 0),
                new QuestMath.Candidate("d", 2),
                new QuestMath.Candidate("e", 3));

        long seed = QuestMath.seed(42L, GameTestSupport.testUuid(1), 2, 0);
        List<String> first = QuestMath.draw(seed, pool, 3);
        List<String> second = QuestMath.draw(seed, pool, 3);
        helper.assertTrue(first.equals(second), "same seed → identical draw (got " + first
                + " vs " + second + ")");
        helper.assertTrue(first.size() == 3, "draws exactly n");
        helper.assertTrue(new HashSet<>(first).size() == 3, "without replacement");
        helper.assertTrue(!first.contains("zero"), "zero weight never drawn");

        // Different seeds decorrelate: at least one differing draw across a small sweep.
        boolean anyDifferent = false;
        for (int nonce = 1; nonce <= 8 && !anyDifferent; nonce++) {
            anyDifferent = !QuestMath.draw(
                    QuestMath.seed(42L, GameTestSupport.testUuid(1), 2, nonce), pool, 3).equals(first);
        }
        helper.assertTrue(anyDifferent, "different nonces eventually change the draw");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void drawExhaustsSmallPools(GameTestHelper helper) {
        List<QuestMath.Candidate> pool = List.of(
                new QuestMath.Candidate("only", 4),
                new QuestMath.Candidate("dead", 0));
        List<String> drawn = QuestMath.draw(99L, pool, 3);
        helper.assertTrue(drawn.equals(List.of("only")), "n > drawable returns all drawable");
        helper.assertTrue(QuestMath.draw(99L, List.of(), 3).isEmpty(), "empty pool → empty draw");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void bitmaskAndClamp(GameTestHelper helper) {
        helper.assertTrue(QuestMath.bitmask(List.of(true, false, true)) == 0b101, "bitmask order");
        helper.assertTrue(QuestMath.bitmask(List.of()) == 0, "empty mask");
        helper.assertTrue(QuestMath.clampToInt(Long.MAX_VALUE) == Integer.MAX_VALUE, "clamp high");
        helper.assertTrue(QuestMath.clampToInt(-5L) == -5, "clamp identity");
        helper.succeed();
    }
}
