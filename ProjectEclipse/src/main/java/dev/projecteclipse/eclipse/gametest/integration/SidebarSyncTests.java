package dev.projecteclipse.eclipse.gametest.integration;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.buffs.TimedBuffApi;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.hud.SidebarSyncService;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.S2CSidebarStatePayload;
import dev.projecteclipse.eclipse.progression.goals.QuestEngine;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import dev.projecteclipse.eclipse.skills.SkillConfig;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** P4-C1 acceptance for aggregate assembly, codec integrity and trailing debounce behavior. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class SidebarSyncTests {
    private SidebarSyncTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadAssemblesLiveServiceState(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        MinecraftServer server = player.server;
        EclipseWorldState world = EclipseWorldState.get(server);
        int oldDay = world.getDay();
        int oldAltar = world.getAltarLevel();
        long oldXp = SkillsApi.getTotalXp(server, player.getUUID());
        int oldShards = ShardEconomy.getShards(player);

        try {
            world.setDay(4);
            world.setAltarLevel(2);
            long expectedTotalXp = SkillCurve.cumulativeXp(7, SkillConfig.get().curve()) + 37L;
            SkillsApi.setTotalXp(player, expectedTotalXp);
            ShardEconomy.setShards(player, 11);

            S2CSidebarStatePayload payload = SidebarSyncService.buildPayload(player);
            RealtimeState realtime = RealtimeState.get(server);
            int expectedLevel = SkillCurve.levelForXp(expectedTotalXp, SkillConfig.get().curve());

            helper.assertTrue(payload.day() == 4, "day comes from EclipseWorldState");
            helper.assertTrue(payload.altarLevel() == 2, "altar level comes from EclipseWorldState");
            helper.assertTrue(payload.skillLevel() == expectedLevel,
                    "skill level is derived from live total XP");
            helper.assertTrue(payload.xpIntoLevel() == SkillCurve.xpIntoLevel(
                    expectedTotalXp, expectedLevel, SkillConfig.get().curve()),
                    "XP progress comes from the live skill curve");
            helper.assertTrue(payload.xpForLevel() == SkillCurve.xpForLevel(
                    expectedLevel + 1, SkillConfig.get().curve()),
                    "next-level XP cost comes from the live skill curve");
            helper.assertTrue(payload.shards() == 11,
                    "personal shard balance comes from ShardEconomy");
            helper.assertTrue(payload.boundaryEpochMillis()
                    == (realtime.isArmed() ? Math.max(0L, realtime.getBoundaryEpochMillis()) : 0L),
                    "boundary mirrors armed realtime state");
            helper.assertTrue(payload.paused() == (realtime.isArmed() && realtime.isPaused()),
                    "pause flag mirrors armed realtime state");

            assertQuestCounts(helper, payload, QuestEngine.buildPayload(server, player));
            List<String> expectedBuffs = TimedBuffApi.Holder.get().active(server).stream()
                    .filter(java.util.Objects::nonNull)
                    .map(String::trim)
                    .filter(id -> !id.isEmpty() && id.length() <= 128)
                    .collect(java.util.stream.Collectors.collectingAndThen(
                            java.util.stream.Collectors.toCollection(LinkedHashSet::new),
                            ids -> ids.stream().limit(32).toList()));
            helper.assertTrue(payload.buffIds().equals(expectedBuffs),
                    "buff ids come from the active timed-buff API");
            helper.assertTrue(SidebarSyncService.PAYLOAD_SCHEMA_VERSION == 1,
                    "sidebar payload schema revision is pinned");
            GameTestSupport.assertPayloadRoundTrip(
                    S2CSidebarStatePayload.STREAM_CODEC, payload);
        } finally {
            world.setDay(oldDay);
            world.setAltarLevel(oldAltar);
            SkillsApi.setTotalXp(player, oldXp);
            ShardEconomy.setShards(player, oldShards);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void spamCoalescesIntoOneTrailingBatch(GameTestHelper helper) {
        SidebarSyncService.DebounceBatch batch =
                new SidebarSyncService.DebounceBatch(SidebarSyncService.DEBOUNCE_TICKS);
        UUID spammed = GameTestSupport.testUuid(301);
        UUID quiet = GameTestSupport.testUuid(302);

        batch.mark(quiet, 0L);
        for (long tick = 0L; tick < 20L; tick++) {
            batch.mark(spammed, tick);
        }
        helper.assertTrue(batch.size() == 2,
                "spam retains one pending slot per player");
        helper.assertTrue(batch.drainDue(9L).isEmpty(),
                "nothing sends before the ten-tick debounce");
        helper.assertTrue(batch.drainDue(10L).equals(Set.of(quiet)),
                "independent player drains at its own deadline");
        helper.assertTrue(batch.drainDue(28L).isEmpty(),
                "re-marking postpones the spammed player's trailing edge");
        helper.assertTrue(batch.drainDue(29L).equals(Set.of(spammed)),
                "twenty mutations coalesce to one trailing send");
        helper.assertTrue(batch.drainDue(100L).isEmpty(),
                "the batch does not resend without a new mutation");
        helper.succeed();
    }

    private static void assertQuestCounts(GameTestHelper helper,
            S2CSidebarStatePayload sidebar, S2CQuestStatePayload quests) {
        int[] done = new int[3];
        int[] total = new int[3];
        for (S2CQuestStatePayload.QuestEntry entry : quests.entries()) {
            if (entry.kind() < 0 || entry.kind() >= total.length) {
                continue;
            }
            total[entry.kind()]++;
            if (entry.done()) {
                done[entry.kind()]++;
            }
        }
        helper.assertTrue(sidebar.mainsDone() == done[0]
                && sidebar.mainsTotal() == total[0], "main-goal aggregate matches QuestEngine");
        helper.assertTrue(sidebar.sidesDone() == done[1]
                && sidebar.sidesTotal() == total[1], "side-goal aggregate matches QuestEngine");
        helper.assertTrue(sidebar.personalsDone() == done[2]
                && sidebar.personalsTotal() == total[2],
                "personal-goal aggregate matches QuestEngine");
    }
}
