package dev.projecteclipse.eclipse.gametest.skills;

import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.network.C2SSkillNodeBuyPayload;
import dev.projecteclipse.eclipse.network.S2CSkillProcPayload;
import dev.projecteclipse.eclipse.network.S2CSkillStatePayload;
import dev.projecteclipse.eclipse.network.S2CSkillTreePayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillPerks;
import dev.projecteclipse.eclipse.skills.SkillService;
import dev.projecteclipse.eclipse.skills.SkillState;
import dev.projecteclipse.eclipse.skills.SkillTree;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.chunk.LevelChunk;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B4 stateful acceptance (plan §3.5): addXp multiplier order + remainder carry, level-up
 * point grants (once, never revoked), node buy/reset flow, death penalty raw+floor, daily
 * cap clamp/rollover, placed-block anti-abuse on ore procs, procmsg opt-out, payload codec
 * round-trips, SavedData NBT round-trip.
 *
 * <p>Uses {@code makeMockServerPlayerInLevel()} (NeoForge patch, deprecated-but-only-option
 * in 1.21.1) because the pipeline ends in real payload sends — vanilla's
 * {@code makeMockPlayer} returns a bare {@code Player} without a connection.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class SkillSystemGameTests {
    private SkillSystemGameTests() {}

    @SuppressWarnings("removal")
    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        return helper.makeMockServerPlayerInLevel();
    }

    private static SkillState.Entry freshEntry(ServerPlayer player) {
        SkillState.Entry entry = SkillState.get(player.server).entry(player.getUUID());
        entry.totalXp = 0L;
        entry.spentPoints = 0;
        entry.ownedNodes.clear();
        entry.secretMultiplier = 1.0F;
        entry.lastLevelSeen = 0;
        entry.bonusPoints = 0;
        entry.xpRemainder = 0.0F;
        entry.capUsed.clear();
        return entry;
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void xpPipelineOrderAndRemainder(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);

        // Base grant, no nodes, multiplier 1: applied == base.
        int applied = SkillsApi.addXp(player, "admin", 100.0F);
        helper.assertTrue(applied == 100, "base grant applied=" + applied);
        helper.assertTrue(entry.totalXp == 100L, "totalXp 100");

        // S2 (+5% all skill XP) folds in: 100 × 1.05 = 105.
        entry.ownedNodes.add("S2");
        applied = SkillsApi.addXp(player, "admin", 100.0F);
        helper.assertTrue(applied == 105, "S2 grant applied=" + applied);

        // Secret multiplier ×2 stacks multiplicatively after node scaling: 100 × 1.05 × 2 = 210.
        SkillsApi.setSecretMultiplier(player.server, player.getUUID(), 2.0F);
        applied = SkillsApi.addXp(player, "admin", 100.0F);
        helper.assertTrue(applied == 210, "secret×2 grant applied=" + applied);
        helper.assertTrue(SkillsApi.getSecretMultiplier(player.server, player.getUUID()) == 2.0F,
                "secret persisted");

        // Fractional remainder carries: 5 × 0.4 pays exactly 2 whole XP over time.
        SkillState.Entry entry2 = freshEntry(player);
        long before = entry2.totalXp;
        int sum = 0;
        for (int i = 0; i < 5; i++) {
            sum += SkillsApi.addXp(player, "admin", 0.4F);
        }
        helper.assertTrue(sum == 2 && entry2.totalXp - before == 2L,
                "remainder carry sum=" + sum + " delta=" + (entry2.totalXp - before));
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void levelUpPointsOnceAndNeverRevoked(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);
        SkillCurve.Params curve = SkillCurve.Params.defaults();

        // One signal per level crossed, in order (listener registration is JVM-sticky but
        // filtering on this test's player keeps it side-effect free afterwards).
        UUID watched = player.getUUID();
        List<Integer> levelsSeen = new java.util.concurrent.CopyOnWriteArrayList<>();
        EclipseSignals.onSkillLevelUp((who, newLevel) -> {
            if (who.getUUID().equals(watched)) {
                levelsSeen.add(newLevel);
            }
        });

        // Jump to exactly L3 worth of XP: 3 points granted (one per level).
        SkillsApi.setTotalXp(player, SkillCurve.cumulativeXp(3, curve));
        helper.assertTrue(SkillsApi.getLevel(player.server, player.getUUID()) == 3, "level 3");
        helper.assertTrue(entry.lastLevelSeen == 3, "lastLevelSeen 3");
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 3, "3 points");
        helper.assertTrue(levelsSeen.equals(List.of(1, 2, 3)), "signals fired 1,2,3: " + levelsSeen);

        // XP reduced back to 0: level drops but earned points are never clawed back.
        SkillsApi.setTotalXp(player, 0L);
        helper.assertTrue(SkillsApi.getLevel(player.server, player.getUUID()) == 0, "level back to 0");
        helper.assertTrue(entry.lastLevelSeen == 3, "lastLevelSeen kept");
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 3, "points kept");

        // Re-crossing already-rewarded levels grants nothing new; going past does.
        SkillsApi.setTotalXp(player, SkillCurve.cumulativeXp(4, curve));
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 4,
                "only L4 added a point");

        // Bonus points stack on top without touching level tracking.
        SkillsApi.addPoints(player, 2);
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 6, "bonus +2");
        helper.assertTrue(entry.lastLevelSeen == 4, "lastLevelSeen untouched by addPoints");
        helper.assertTrue(levelsSeen.equals(List.of(1, 2, 3, 4)), "re-crossing fired only L4");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nodeBuyAndResetFlow(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);

        helper.assertTrue(SkillService.buyNode(player, "S1") == SkillTree.BuyResult.NOT_ENOUGH_POINTS,
                "no points yet");
        SkillsApi.addPoints(player, 3);

        // Through the payload entry point (C2S handler A1 left as a stub).
        SkillService.handleNodeBuy(new C2SSkillNodeBuyPayload("S1"), player);
        helper.assertTrue(entry.ownedNodes.contains("S1"), "S1 owned via payload path");
        helper.assertTrue(entry.spentPoints == 1, "spent 1");

        helper.assertTrue(SkillService.buyNode(player, "S1") == SkillTree.BuyResult.ALREADY_OWNED,
                "no double buy");
        helper.assertTrue(SkillService.buyNode(player, "S3") == SkillTree.BuyResult.MISSING_PREREQ,
                "S3 needs S2");
        helper.assertTrue(SkillService.buyNode(player, "S2") == SkillTree.BuyResult.OK, "S2 bought");
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 0, "all spent");

        SkillsApi.resetTree(player);
        helper.assertTrue(entry.ownedNodes.isEmpty() && entry.spentPoints == 0, "tree reset");
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, player.getUUID()) == 3,
                "full refund");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void deathPenaltyRawAndFloored(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);

        // Negative XP skips every multiplier: secret ×10 must NOT amplify the -50 penalty.
        entry.totalXp = 100L;
        SkillsApi.setSecretMultiplier(player.server, player.getUUID(), 10.0F);
        int applied = SkillsApi.addXp(player, "death", -50.0F);
        helper.assertTrue(applied == -50, "raw penalty applied=" + applied);
        helper.assertTrue(entry.totalXp == 50L, "100-50=50, multiplier ignored");

        // Lifetime XP floors at 0 (partial application reported).
        applied = SkillsApi.addXp(player, "death", -80.0F);
        helper.assertTrue(applied == -50, "floored penalty applied=" + applied);
        helper.assertTrue(entry.totalXp == 0L, "floor at 0");
        SkillsApi.setSecretMultiplier(player.server, player.getUUID(), 1.0F);
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void dailyCapClampsAndRollsOver(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);

        // Default mine cap = 3000: a 5000 grant clamps, the next grant is fully eaten.
        int applied = SkillsApi.addXp(player, "mine", 5000.0F);
        helper.assertTrue(applied == 3000, "clamped to cap, applied=" + applied);
        helper.assertTrue(SkillsApi.addXp(player, "mine", 50.0F) == 0, "cap exhausted");
        helper.assertTrue(entry.totalXp == 3000L, "totalXp stopped at cap");

        // Uncapped sources are unaffected by the mine budget.
        helper.assertTrue(SkillsApi.addXp(player, "admin", 10.0F) == 10, "admin uncapped");

        // Simulate the day rolling over: stale capDay resets the per-source counters.
        entry.capDay = entry.capDay - 1;
        helper.assertTrue(SkillsApi.addXp(player, "mine", 50.0F) == 50, "cap reset next day");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void placedBlocksNeverFeedOreProcs(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);
        entry.ownedNodes.add("T2"); // 2% double ore drops
        entry.ownedNodes.add("T6"); // 1% bonus raw ore

        BlockPos placedPos = helper.absolutePos(new BlockPos(0, 1, 0));
        BlockPos naturalPos = helper.absolutePos(new BlockPos(1, 1, 0));
        LevelChunk chunk = level.getChunkAt(placedPos);
        PlacedBlockData data = PlacedBlockData.empty();
        long[] bits = data.sectionBits(level.getSectionIndex(placedPos.getY()), true);
        int blockIndex = ((placedPos.getY() & 15) << 8) | ((placedPos.getZ() & 15) << 4) | (placedPos.getX() & 15);
        bits[blockIndex >> 6] |= 1L << (blockIndex & 63);
        chunk.setData(EclipseAttachments.PLACED_BLOCKS, data);

        helper.assertTrue(SkillPerks.isPlaced(level, placedPos), "attachment bit read back");
        helper.assertTrue(!SkillPerks.isPlaced(level, naturalPos), "neighbor still natural");

        var ore = Blocks.IRON_ORE.defaultBlockState();
        // Same winning roll (< 2%): natural pos procs, placed pos never does.
        helper.assertTrue(SkillPerks.shouldDoubleOreDrops(player, ore, naturalPos, 0.01F), "natural procs");
        helper.assertTrue(!SkillPerks.shouldDoubleOreDrops(player, ore, placedPos, 0.01F), "placed blocked");
        helper.assertTrue(!SkillPerks.shouldDoubleOreDrops(player, ore, naturalPos, 0.5F), "losing roll");
        helper.assertTrue(!SkillPerks.shouldDoubleOreDrops(player, Blocks.DIRT.defaultBlockState(),
                naturalPos, 0.0F), "non-ore never procs");

        // T6 mirrors the same natural-only rule and maps ore family → raw item.
        var bonus = SkillPerks.bonusRawOreFor(player, ore, naturalPos, 0.005F);
        helper.assertTrue(bonus != null && bonus.is(Items.RAW_IRON), "bonus raw iron");
        helper.assertTrue(SkillPerks.bonusRawOreFor(player, ore, placedPos, 0.005F) == null,
                "no bonus from placed");
        var gold = SkillPerks.bonusRawOreFor(player, Blocks.DEEPSLATE_GOLD_ORE.defaultBlockState(),
                naturalPos, 0.005F);
        helper.assertTrue(gold != null && gold.is(Items.RAW_GOLD), "gold family mapped");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void procMessageOptOutRespected(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        freshEntry(player);

        helper.assertTrue(SkillsApi.isProcMessagesEnabled(player.server, player.getUUID()),
                "default opt-in");
        helper.assertTrue(SkillPerks.sendProcFeedback(player, "double_ore", 2.0F),
                "chat line sent while enabled");

        SkillsApi.setProcMessagesEnabled(player, false);
        helper.assertTrue(!SkillPerks.sendProcFeedback(player, "double_ore", 2.0F),
                "chat line suppressed after /skills procmsg off");
        helper.assertTrue(!SkillsApi.isProcMessagesEnabled(player.server, player.getUUID()),
                "opt-out persisted");

        SkillsApi.setProcMessagesEnabled(player, true);
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadCodecsRoundTrip(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(S2CSkillStatePayload.STREAM_CODEC,
                new S2CSkillStatePayload(12, 2650L, 40, 512, 12, 9, List.of("S1", "T2"), true, false));
        GameTestSupport.assertPayloadRoundTrip(S2CSkillProcPayload.STREAM_CODEC,
                new S2CSkillProcPayload("double_ore", 2.0F));
        GameTestSupport.assertPayloadRoundTrip(S2CSkillTreePayload.STREAM_CODEC,
                new S2CSkillTreePayload("{\"nodes\":[]}"));
        GameTestSupport.assertPayloadRoundTrip(C2SSkillNodeBuyPayload.STREAM_CODEC,
                new C2SSkillNodeBuyPayload("U3"));
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void savedDataNbtRoundTrip(GameTestHelper helper) {
        UUID uuid = GameTestSupport.testUuid(44);
        SkillState state = new SkillState();
        SkillState.Entry entry = state.entry(uuid);
        entry.totalXp = 12345L;
        entry.spentPoints = 5;
        entry.ownedNodes.add("S1");
        entry.ownedNodes.add("T2");
        entry.procMsgEnabled = false;
        entry.secretMultiplier = 1.5F;
        entry.lastLevelSeen = 9;
        entry.bonusPoints = 2;
        entry.xpRemainder = 0.75F;
        entry.capDay = 3;
        entry.capUsed.put("mine", 1200.0F);

        var registries = helper.getLevel().registryAccess();
        CompoundTag saved = state.save(new CompoundTag(), registries);
        SkillState.Entry loaded = SkillState.load(saved, registries).entry(uuid);

        helper.assertTrue(loaded.totalXp == 12345L && loaded.spentPoints == 5, "xp+spent");
        helper.assertTrue(loaded.ownedNodes.contains("S1") && loaded.ownedNodes.contains("T2")
                && loaded.ownedNodes.size() == 2, "nodes");
        helper.assertTrue(!loaded.procMsgEnabled, "procMsg flag");
        helper.assertTrue(loaded.secretMultiplier == 1.5F, "secret multiplier");
        helper.assertTrue(loaded.lastLevelSeen == 9 && loaded.bonusPoints == 2, "level tracking");
        helper.assertTrue(loaded.xpRemainder == 0.75F, "remainder");
        helper.assertTrue(loaded.capDay == 3 && loaded.capUsed.get("mine") == 1200.0F, "caps");
        helper.assertTrue(loaded.unspentPoints() == 6, "points math 9+2-5");
        helper.succeed();
    }
}
