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

    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        // WAVE10: central helper — configures the mock connection so tick broadcasters
        // (InvLockSync/UnlockSync) can't crash the GameTestServer on a lingering mock.
        return GameTestSupport.mockServerPlayerInLevel(helper);
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

        // FIX-ECON formula 8·1.3^n, rounded: 8, 10, 14, 18, 23, ...
        helper.assertTrue(defaults.costForCount(0) == 8, "cost(0)=8");
        helper.assertTrue(defaults.costForCount(1) == 10, "cost(1)=10 (10.4)");
        helper.assertTrue(defaults.costForCount(2) == 14, "cost(2)=14 (13.52)");
        helper.assertTrue(defaults.costForCount(3) == 18, "cost(3)=18 (17.576)");
        helper.assertTrue(defaults.costForCount(4) == 23, "cost(4)=23 (22.85)");
        for (int n = 1; n < 10; n++) {
            helper.assertTrue(defaults.costForCount(n) > defaults.costForCount(n - 1),
                    "cost ladder strictly escalates at n=" + n);
        }

        // FIX-ECON: no permanent level-cost penalty — the multiplier is 1.0 at every count.
        helper.assertTrue(defaults.levelCostMultiplier(0) == 1.0D, "mult(0)==1.0 exact");
        helper.assertTrue(defaults.levelCostMultiplier(1) == 1.0D, "mult(1)==1.0 (no penalty)");
        helper.assertTrue(defaults.levelCostMultiplier(5) == 1.0D, "mult(5)==1.0 (no penalty)");

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
            helper.assertTrue(RebirthApi.costForNext(player.server, player.getUUID()) == 10,
                    "next price escalated to 10");
            double multiplier = RebirthApi.levelCostMultiplier(player.server, player.getUUID());
            helper.assertTrue(multiplier == 1.0D, "multiplier stays 1.0 after one rebirth (FIX-ECON)");

            // Re-earn the same XP: with the 1.0 multiplier the curve is unchanged, so the
            // level comes straight back — the reset itself is the price, not a penalty.
            SkillsApi.setTotalXp(player, xpForL3);
            int level = SkillsApi.getLevel(player.server, player.getUUID());
            SkillCurve.Params scaled = RebirthHooks.curveFor(player.server, player.getUUID(), base);
            helper.assertTrue(Math.abs(scaled.baseCost() - base.baseCost()) < 1.0E-6D,
                    "curveFor leaves baseCost unscaled at mult 1.0");
            helper.assertTrue(level == SkillCurve.levelForXp(xpForL3, scaled),
                    "getLevel routes through the scaled curve");
            helper.assertTrue(level == 3, "old L3 XP reaches level 3 again, got " + level);
        } finally {
            resetPlayer(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadCodecsRoundTrip(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(S2CRebirthStatePayload.STREAM_CODEC,
                new S2CRebirthStatePayload(3, 33, 1.520875F, true));
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
