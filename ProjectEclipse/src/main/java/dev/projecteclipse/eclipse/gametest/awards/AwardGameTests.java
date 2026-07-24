package dev.projecteclipse.eclipse.gametest.awards;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsKeys;
import dev.projecteclipse.eclipse.analytics.AnalyticsState;
import dev.projecteclipse.eclipse.awards.AwardConfig;
import dev.projecteclipse.eclipse.awards.AwardMath;
import dev.projecteclipse.eclipse.awards.AwardService;
import dev.projecteclipse.eclipse.awards.AwardsState;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** P4-B6 award determinism, tie math, persistence, pending and idempotence coverage. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class AwardGameTests {
    private AwardGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void deterministicWeightedSelection(GameTestHelper helper) {
        List<AwardMath.Choice> pool = List.of(
                new AwardMath.Choice("combat", 10, Set.of("combat")),
                new AwardMath.Choice("neutral", 10, Set.of()));
        long seed = AwardMath.seed(12345L, 7, 0);
        List<String> first = AwardMath.pick(seed, pool, Set.of("combat"), 2);
        helper.assertTrue(first.equals(AwardMath.pick(seed, pool, Set.of("combat"), 2)),
                "same save/day seed gives the same draw");
        helper.assertTrue(AwardMath.allDistinct(first), "draw is without replacement");

        int combat = 0;
        int neutral = 0;
        for (int i = 0; i < 10_000; i++) {
            String selected = AwardMath.pick(AwardMath.seed(i, 7, 0), pool,
                    Set.of("combat"), 1).getFirst();
            if ("combat".equals(selected)) {
                combat++;
            } else {
                neutral++;
            }
        }
        helper.assertTrue(combat > neutral * 2.5D,
                "theme boost approaches 3x (combat=" + combat + ", neutral=" + neutral + ")");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void tiesSplitAndMinResolution(GameTestHelper helper) {
        UUID a = GameTestSupport.testUuid(1);
        UUID b = GameTestSupport.testUuid(2);
        UUID c = GameTestSupport.testUuid(3);
        AwardMath.Resolution max = AwardMath.resolve(List.of(
                new AwardMath.Candidate(c, 9),
                new AwardMath.Candidate(a, 26),
                new AwardMath.Candidate(b, 26)), AwardMath.Order.MAX);
        helper.assertTrue(max.winners().equals(List.of(a, b)), "all best-value ties win in UUID order");
        helper.assertTrue(AwardMath.splitReward(400, 2) == 200, "400 XP split two ways is 200");
        helper.assertTrue(AwardMath.splitReward(3, 2) == 2, "integer rewards round up");

        AwardMath.Resolution min = AwardMath.resolve(List.of(
                new AwardMath.Candidate(a, 0),
                new AwardMath.Candidate(b, 4)), AwardMath.Order.MIN);
        helper.assertTrue(min.winners().equals(List.of(a)), "zero is a valid minimum after eligibility filtering");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void stateRoundTripAndPendingDedup(GameTestHelper helper) {
        UUID winner = GameTestSupport.testUuid(21);
        AwardsState original = new AwardsState();
        AwardsState.CategoryResult category = new AwardsState.CategoryResult(
                "sheep", "kill:minecraft:sheep", "Flock's Bane", "Schrecken der Herde",
                "killed the most sheep yesterday (26)", "hat gestern am meisten Schafe getötet (26)",
                "Rewarded with 200 Skill XP", "Belohnt mit 200 Skill-EP",
                List.of(new AwardMath.Candidate(winner, 26)), List.of(winner));
        helper.assertTrue(original.putResolved(new AwardsState.ResolvedDay(91, List.of("sheep"),
                List.of(category))), "first resolution accepted");
        helper.assertTrue(!original.putResolved(new AwardsState.ResolvedDay(91, List.of(), List.of())),
                "second resolution rejected");
        AwardsState.PendingReward pending = new AwardsState.PendingReward("award:91:sheep:" + winner,
                200, 2, List.of(new AwardConfig.ItemReward("minecraft:diamond", 1)));
        helper.assertTrue(original.queue(winner, pending), "first queue accepted");
        helper.assertTrue(!original.queue(winner, pending), "stable id deduplicates pending reward");

        CompoundTag encoded = original.save(new CompoundTag(), helper.getLevel().registryAccess());
        AwardsState loaded = AwardsState.load(encoded, helper.getLevel().registryAccess());
        helper.assertTrue(loaded.resolved(91).orElseThrow().categories().getFirst().statLineDe()
                .contains("Schafe"), "bilingual stat line survives NBT");
        helper.assertTrue(loaded.pending(winner).size() == 1, "pending reward survives NBT");
        helper.assertTrue(loaded.takePending(winner).size() == 1 && loaded.takePending(winner).isEmpty(),
                "claim is one-shot");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void serviceResolutionIsIdempotentAndQueuesOffline(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int day = 912;
        UUID winner = GameTestSupport.testUuid(31);
        UUID runnerUp = GameTestSupport.testUuid(32);
        AwardConfig.Category category = new AwardConfig.Category("test_kills", AnalyticsKeys.KILL_TOTAL,
                AwardMath.Order.MAX, 1, new Localized("Test", "Test"),
                new Localized("won ({value})", "gewann ({value})"), "test",
                AwardConfig.Reward.NONE, Set.of(), false, false, false, List.of());
        AwardConfig.Data testConfig = new AwardConfig.Data(1, 1, 2,
                Map.of("test", new AwardConfig.Reward(100, 2, List.of())),
                List.of(category), Map.of());
        AwardConfig.injectForTests(testConfig);
        try {
            AnalyticsState analytics = AnalyticsState.get(server);
            analytics.add(day, winner, AnalyticsKeys.KILL_TOTAL, 12);
            analytics.add(day, winner, AnalyticsKeys.PLAYTIME_S, 10);
            analytics.add(day, runnerUp, AnalyticsKeys.KILL_TOTAL, 5);
            AwardsState.ResolvedDay first = AwardService.resolveDay(server, day);
            AwardsState.ResolvedDay second = AwardService.resolveDay(server, day);
            helper.assertTrue(first.equals(second), "repeated resolve returns frozen record");
            helper.assertTrue(first.categories().getFirst().winners().equals(List.of(winner)),
                    "analytics winner resolved");
            helper.assertTrue(first.categories().getFirst().candidates().size() == 1,
                    "candidate below min playtime filtered");
            helper.assertTrue(AwardsState.get(server).pending(winner).size() == 1,
                    "offline winner reward queued once");
        } finally {
            AwardConfig.invalidate();
        }
        helper.succeed();
    }
}
