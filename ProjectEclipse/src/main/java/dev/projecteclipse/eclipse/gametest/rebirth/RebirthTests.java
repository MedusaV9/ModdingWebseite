package dev.projecteclipse.eclipse.gametest.rebirth;

import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import dev.projecteclipse.eclipse.network.C2SRebirthPayload;
import dev.projecteclipse.eclipse.network.S2CRebirthStatePayload;
import dev.projecteclipse.eclipse.rebirth.RebirthApi;
import dev.projecteclipse.eclipse.rebirth.RebirthConfig;
import dev.projecteclipse.eclipse.rebirth.RebirthState;
import dev.projecteclipse.eclipse.skills.RebirthHooks;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillState;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D11 acceptance: cost ladder + multiplier math, refuse-at-cap, transaction atomicity
 * (insufficient shards = NOTHING changes), the full ceremony effect (shards consumed,
 * progression wiped, +1 Leben, count persisted) and the curve multiplier reaching
 * {@code SkillsApi.getLevel} after re-earning XP. Payload codec + SavedData round-trips.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class RebirthTests {
    private RebirthTests() {}

    @SuppressWarnings("removal")
    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        return helper.makeMockServerPlayerInLevel();
    }

    /** Zeroes skill + rebirth + economy + lives state so tests are order-independent. */
    private static void resetPlayer(ServerPlayer player) {
        SkillState.Entry skill = SkillState.get(player.server).entry(player.getUUID());
        skill.totalXp = 0L;
        skill.spentPoints = 0;
        skill.ownedNodes.clear();
        skill.secretMultiplier = 1.0F;
        skill.lastLevelSeen = 0;
        skill.bonusPoints = 0;
        skill.xpRemainder = 0.0F;
        skill.capUsed.clear();
        RebirthState.Entry rebirth = RebirthState.get(player.server).entry(player.getUUID());
        rebirth.count = 0;
        rebirth.timestamps.clear();
        ShardEconomy.setShards(player, 0);
        LivesApi.set(player, 5);
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void costLadderAndMultiplierMath(GameTestHelper helper) {
        RebirthConfig.Data defaults = RebirthConfig.parse(RebirthConfig.defaultsJson());

        // Plan formula 8·1.6^n, rounded: 8, 13, 20, 33, 52, ...
        helper.assertTrue(defaults.costForCount(0) == 8, "cost(0)=8");
        helper.assertTrue(defaults.costForCount(1) == 13, "cost(1)=13 (12.8)");
        helper.assertTrue(defaults.costForCount(2) == 20, "cost(2)=20 (20.48)");
        helper.assertTrue(defaults.costForCount(3) == 33, "cost(3)=33 (32.768)");
        helper.assertTrue(defaults.costForCount(4) == 52, "cost(4)=52 (52.43)");
        for (int n = 1; n < 10; n++) {
            helper.assertTrue(defaults.costForCount(n) > defaults.costForCount(n - 1),
                    "cost ladder strictly escalates at n=" + n);
        }

        // Level-cost multiplier 1.15^n; EXACTLY 1.0 for count 0 (RebirthHooks fast path).
        helper.assertTrue(defaults.levelCostMultiplier(0) == 1.0D, "mult(0)==1.0 exact");
        helper.assertTrue(Math.abs(defaults.levelCostMultiplier(1) - 1.15D) < 1.0E-9D, "mult(1)=1.15");
        helper.assertTrue(Math.abs(defaults.levelCostMultiplier(2) - 1.3225D) < 1.0E-9D, "mult(2)=1.3225");

        helper.assertTrue(defaults.maxRebirths() == 0, "uncapped by default");
        helper.assertTrue(defaults.lifeRewardPerRebirth() == 1, "+1 Leben per rebirth");
        helper.assertTrue(defaults.keepCollections() && defaults.keepWand(),
                "reset non-goals documented as kept");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void refusalsAreAtomic(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        resetPlayer(player);
        SkillState.Entry skill = SkillState.get(player.server).entry(player.getUUID());
        try {
            // Insufficient shards: one below the price — NOTHING may change.
            int cost = RebirthApi.costForNext(player.server, player.getUUID());
            ShardEconomy.setShards(player, cost - 1);
            SkillsApi.setTotalXp(player, 1000L);
            skill.ownedNodes.add("S1");
            skill.spentPoints = 1;
            helper.assertTrue(RebirthApi.tryRebirth(player) == RebirthApi.Result.NOT_ENOUGH_SHARDS,
                    "refused on shards");
            helper.assertTrue(ShardEconomy.getShards(player) == cost - 1, "shards untouched");
            helper.assertTrue(skill.totalXp == 1000L && skill.ownedNodes.contains("S1"),
                    "progression untouched");
            helper.assertTrue(LivesApi.get(player) == 5, "Leben untouched");
            helper.assertTrue(RebirthApi.count(player.server, player.getUUID()) == 0, "count untouched");

            // At the Leben cap: refuse instead of burning the +1 (shards stay).
            ShardEconomy.setShards(player, 999);
            LivesApi.set(player, HeartsService.MAX_HEARTS);
            helper.assertTrue(RebirthApi.tryRebirth(player) == RebirthApi.Result.AT_LIFE_CAP,
                    "refused at Leben cap");
            helper.assertTrue(ShardEconomy.getShards(player) == 999, "shards kept at cap");
            helper.assertTrue(skill.totalXp == 1000L, "progression kept at cap");
            helper.assertTrue(RebirthApi.count(player.server, player.getUUID()) == 0, "count kept at cap");
        } finally {
            resetPlayer(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void fullTransactionAndCurveMultiplier(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        resetPlayer(player);
        SkillState.Entry skill = SkillState.get(player.server).entry(player.getUUID());
        try {
            SkillCurve.Params base = SkillCurve.Params.defaults();
            long xpForL3 = SkillCurve.cumulativeXp(3, base);
            SkillsApi.setTotalXp(player, xpForL3);
            skill.ownedNodes.add("S1");
            skill.spentPoints = 1;
            int cost = RebirthApi.costForNext(player.server, player.getUUID());
            ShardEconomy.setShards(player, cost);

            helper.assertTrue(RebirthApi.tryRebirth(player) == RebirthApi.Result.OK, "ceremony ran");
            helper.assertTrue(ShardEconomy.getShards(player) == 0, "exact price consumed");
            helper.assertTrue(skill.totalXp == 0L && skill.xpRemainder == 0.0F, "XP wiped");
            helper.assertTrue(skill.ownedNodes.isEmpty() && skill.spentPoints == 0
                    && skill.bonusPoints == 0 && skill.lastLevelSeen == 0, "tree + points wiped");
            helper.assertTrue(LivesApi.get(player) == 6, "+1 Leben granted");
            helper.assertTrue(RebirthApi.count(player.server, player.getUUID()) == 1, "count 1");
            helper.assertTrue(RebirthApi.costForNext(player.server, player.getUUID()) == 13,
                    "next price escalated to 13");
            double multiplier = RebirthApi.levelCostMultiplier(player.server, player.getUUID());
            helper.assertTrue(Math.abs(multiplier - 1.15D) < 1.0E-9D, "multiplier 1.15 after one rebirth");

            // Re-earn the same XP: the multiplied curve prices L3 higher, so the level lags.
            SkillsApi.setTotalXp(player, xpForL3);
            int level = SkillsApi.getLevel(player.server, player.getUUID());
            SkillCurve.Params scaled = RebirthHooks.curveFor(player.server, player.getUUID(), base);
            helper.assertTrue(Math.abs(scaled.baseCost() - base.baseCost() * 1.15D) < 1.0E-6D,
                    "curveFor scales baseCost");
            helper.assertTrue(level == SkillCurve.levelForXp(xpForL3, scaled),
                    "getLevel routes through the scaled curve");
            helper.assertTrue(level < 3, "old L3 XP no longer reaches level 3, got " + level);
        } finally {
            resetPlayer(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadCodecsRoundTrip(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(S2CRebirthStatePayload.STREAM_CODEC,
                new S2CRebirthStatePayload(3, 33, 1.520875F));
        GameTestSupport.assertPayloadRoundTrip(C2SRebirthPayload.STREAM_CODEC, new C2SRebirthPayload());
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void savedDataNbtRoundTrip(GameTestHelper helper) {
        UUID uuid = GameTestSupport.testUuid(88);
        RebirthState state = new RebirthState();
        state.recordRebirth(uuid, 1000L);
        state.recordRebirth(uuid, 2000L);

        var registries = helper.getLevel().registryAccess();
        CompoundTag saved = state.save(new CompoundTag(), registries);
        RebirthState loaded = RebirthState.load(saved, registries);

        helper.assertTrue(loaded.count(uuid) == 2, "count round-trips");
        helper.assertTrue(loaded.entry(uuid).timestamps.equals(java.util.List.of(1000L, 2000L)),
                "audit timestamps round-trip in order");
        helper.assertTrue(loaded.count(GameTestSupport.testUuid(89)) == 0, "unknown uuid = 0");
        helper.succeed();
    }
}
