package dev.projecteclipse.eclipse.gametest.anticheat;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.anticheat.AntiXrayConfig;
import dev.projecteclipse.eclipse.anticheat.OreExposureRules;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** Unit-style GameTests for the production rolling-window and threshold math. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class OreExposureTests {
    private OreExposureTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void rollingWindowEvictsOldestSample(GameTestHelper helper) {
        OreExposureRules.RollingExposureWindow window =
                new OreExposureRules.RollingExposureWindow(4);
        window.add(true);
        window.add(true);
        window.add(false);
        window.add(true);

        helper.assertTrue(window.samples() == 4, "window fills to capacity");
        helper.assertTrue(window.unexposedSamples() == 3, "three encased samples");
        helper.assertTrue(window.exposedSamples() == 1, "one air-exposed sample");
        helper.assertTrue(window.score() == 75.0D, "3/4 gives score 75");

        window.add(false); // evicts the oldest encased sample
        helper.assertTrue(window.samples() == 4, "window remains bounded");
        helper.assertTrue(window.unexposedSamples() == 2, "oldest encased sample evicted");
        helper.assertTrue(window.score() == 50.0D, "2/4 gives score 50 after eviction");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void thresholdsRequireMinimumSamples(GameTestHelper helper) {
        AntiXrayConfig.Data config = AntiXrayConfig.defaults();

        OreExposureRules.PlayerSnapshot tooEarly = OreExposureRules.evaluate(7, 7, config);
        helper.assertTrue(tooEarly.level() == OreExposureRules.SuspicionLevel.CLEAR,
                "seven perfect samples stay clear below minimum eight");

        OreExposureRules.PlayerSnapshot soft = OreExposureRules.evaluate(8, 6, config);
        helper.assertTrue(soft.score() == 75.0D, "6/8 score is 75");
        helper.assertTrue(soft.level() == OreExposureRules.SuspicionLevel.SOFT,
                "75 crosses default soft threshold only");

        OreExposureRules.PlayerSnapshot exactSoft = OreExposureRules.evaluate(10, 7, config);
        helper.assertTrue(exactSoft.level() == OreExposureRules.SuspicionLevel.SOFT,
                "70 exactly reaches the inclusive soft threshold");

        OreExposureRules.PlayerSnapshot exactHard = OreExposureRules.evaluate(10, 9, config);
        helper.assertTrue(exactHard.level() == OreExposureRules.SuspicionLevel.HARD,
                "90 exactly reaches the inclusive hard threshold");

        OreExposureRules.PlayerSnapshot hard = OreExposureRules.evaluate(8, 8, config);
        helper.assertTrue(hard.level() == OreExposureRules.SuspicionLevel.HARD,
                "100 crosses hard threshold");

        OreExposureRules.PlayerSnapshot ordinary = OreExposureRules.evaluate(8, 5, config);
        helper.assertTrue(ordinary.level() == OreExposureRules.SuspicionLevel.CLEAR,
                "62.5 stays below the soft threshold");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void scoreBoundsAndDefaultActionAreFailSafe(GameTestHelper helper) {
        helper.assertTrue(OreExposureRules.scorePercent(12, 10) == 100.0D,
                "impossible over-count clamps to 100");
        helper.assertTrue(OreExposureRules.scorePercent(-1, 10) == 0.0D,
                "negative count clamps to zero");
        helper.assertTrue(OreExposureRules.scorePercent(1, 0) == 0.0D,
                "empty window scores zero");
        helper.assertTrue(AntiXrayConfig.defaults().actionMode()
                        == AntiXrayConfig.ActionMode.NOTIFY_ONLY,
                "default action only notifies; it never punishes or bans");
        helper.succeed();
    }
}
