package dev.projecteclipse.eclipse.gametest.analytics;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsApi;
import dev.projecteclipse.eclipse.analytics.AnalyticsConfig;
import dev.projecteclipse.eclipse.analytics.AnalyticsKeys;
import dev.projecteclipse.eclipse.analytics.AnalyticsSampler;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import dev.projecteclipse.eclipse.analytics.AnalyticsState;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.analytics.PlacedBlockTracker;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.chunk.LevelChunk;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B5 acceptance gametests (§3.6): placed-bit lifecycle + natural-check fan-out, per-day
 * counters, chunk-attachment persistence, sampler caps, rollover day-cut, leaderboard
 * ordering, craft allowlist and the sampler perf budget. Tests drive the service's core
 * handler methods directly (the event subscribers are one-line unwrappers) so results stay
 * deterministic regardless of listener state left behind by other suites.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class AnalyticsGameTests {
    private AnalyticsGameTests() {}

    /** Survival mock ServerPlayer (unique UUID per test = counter isolation). */
    private static ServerPlayer mockPlayer(GameTestHelper helper) {
        ServerPlayer player = helper.makeMockServerPlayerInLevel();
        player.setGameMode(GameType.SURVIVAL);
        return player;
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void placeMarksBreakClearsNoSignal(GameTestHelper helper) {
        ServerPlayer player = mockPlayer(helper);
        ServerLevel level = helper.getLevel();
        BlockPos pos = helper.absolutePos(new BlockPos(0, 1, 0));
        MinecraftServer server = level.getServer();
        int day = AnalyticsService.currentDay(server);

        AtomicInteger naturalFired = new AtomicInteger();
        EclipseSignals.onNaturalBlockMined((p, s, bp) -> {
            if (p == player) {
                naturalFired.incrementAndGet();
            }
        });

        helper.setBlock(new BlockPos(0, 1, 0), Blocks.COBBLESTONE);
        long minedBefore = AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.MINE_TOTAL);

        AnalyticsService.handlePlace(player, level, pos, Blocks.COBBLESTONE.defaultBlockState());
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, pos), "bit set after place");
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.PLACE_TOTAL) == 1L,
                "place_total counted");

        AnalyticsService.handleBreak(player, level, pos, Blocks.COBBLESTONE.defaultBlockState());
        helper.assertTrue(!PlacedBlockTracker.isPlaced(level, pos), "bit cleared after break");
        helper.assertTrue(naturalFired.get() == 0, "no naturalBlockMined for player-built block");
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.MINE_TOTAL)
                == minedBefore, "no mine credit for player-built block");

        // Re-placing the same spot re-marks (clear-on-break keeps the bit fresh).
        AnalyticsService.handlePlace(player, level, pos, Blocks.COBBLESTONE.defaultBlockState());
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, pos), "re-place re-marks");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void naturalBreakCountsAndFires(GameTestHelper helper) {
        ServerPlayer player = mockPlayer(helper);
        ServerLevel level = helper.getLevel();
        BlockPos pos = helper.absolutePos(new BlockPos(1, 1, 0));
        MinecraftServer server = level.getServer();
        int day = AnalyticsService.currentDay(server);

        AtomicInteger naturalFired = new AtomicInteger();
        EclipseSignals.onNaturalBlockMined((p, s, bp) -> {
            if (p == player) {
                naturalFired.incrementAndGet();
            }
        });

        helper.setBlock(new BlockPos(1, 1, 0), Blocks.IRON_ORE);
        // Never placed by a player -> natural verdict.
        AnalyticsService.handleBreak(player, level, pos, Blocks.IRON_ORE.defaultBlockState());

        helper.assertTrue(naturalFired.get() == 1, "naturalBlockMined fired exactly once");
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.MINE_TOTAL) == 1L,
                "mine_total counted");
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(),
                AnalyticsKeys.PREFIX_MINE + "minecraft:iron_ore") == 1L, "mine:<id> counted");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void placedBitsSurviveAttachmentPersistence(GameTestHelper helper) {
        ServerPlayer player = mockPlayer(helper);
        ServerLevel level = helper.getLevel();
        BlockPos surface = helper.absolutePos(new BlockPos(0, 1, 1));
        // Same chunk column, negative-Y section (disc world min_y is -176).
        BlockPos deep = new BlockPos(surface.getX(), -60, surface.getZ());

        AnalyticsService.handlePlace(player, level, surface, Blocks.COBBLESTONE.defaultBlockState());
        PlacedBlockTracker.markPlaced(level, deep);
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, surface), "surface bit set");
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, deep), "negative-Y bit set");

        LevelChunk chunk = level.getChunkAt(surface);
        PlacedBlockData data = chunk.getData(EclipseAttachments.PLACED_BLOCKS);
        GameTestSupport.assertCodecRoundTrip(PlacedBlockData.CODEC, data);

        // Real persistence path: serialize attachments, wipe the bits, read the NBT back.
        CompoundTag attachmentNbt = chunk.writeAttachmentsToNBT(level.registryAccess());
        PlacedBlockTracker.clear(level, surface);
        PlacedBlockTracker.clear(level, deep);
        helper.assertTrue(!PlacedBlockTracker.isPlaced(level, surface), "bit wiped pre-reload");
        chunk.readAttachmentsFromNBT(level.registryAccess(), attachmentNbt);
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, surface), "surface bit restored from NBT");
        helper.assertTrue(PlacedBlockTracker.isPlaced(level, deep), "negative-Y bit restored from NBT");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void distanceSamplerCapsTeleportJumps(GameTestHelper helper) {
        long walk = AnalyticsSampler.sampleDeltaCm(0, 64, 0, 3, 64, 4, 10_000L);
        helper.assertTrue(walk == 500L, "3-4-5 walk = 500 cm, got " + walk);
        long teleport = AnalyticsSampler.sampleDeltaCm(0, 64, 0, 5_000, 64, 0, 10_000L);
        helper.assertTrue(teleport == 10_000L, "teleport clamped to cap, got " + teleport);
        long still = AnalyticsSampler.sampleDeltaCm(8.5, 64, 8.5, 8.5, 64, 8.5, 10_000L);
        helper.assertTrue(still == 0L, "no movement = 0 cm");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void rolloverPreCutsScratchAndPrunes(GameTestHelper helper) {
        ServerPlayer player = mockPlayer(helper);
        ServerLevel level = helper.getLevel();
        MinecraftServer server = level.getServer();
        int day = AnalyticsService.currentDay(server);
        BlockPos pos = helper.absolutePos(new BlockPos(2, 1, 0));
        AnalyticsState state = AnalyticsState.get(server);

        // Distinct-type scratch: same type twice -> one place_types credit...
        AnalyticsService.handlePlace(player, level, pos, Blocks.OAK_PLANKS.defaultBlockState());
        AnalyticsService.handlePlace(player, level, pos, Blocks.OAK_PLANKS.defaultBlockState());
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.PLACE_TYPES) == 1L,
                "same type counted once per day");

        // ...rollover PRE resets the per-day sets, so the next day counts the type fresh.
        AnalyticsService.handleDayRollover(server, day, day + 1,
                EclipseSignals.DayRolloverPhase.PRE);
        AnalyticsService.handlePlace(player, level, pos, Blocks.OAK_PLANKS.defaultBlockState());
        helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.PLACE_TYPES) == 2L,
                "scratch cleared on rollover PRE");

        // Day keying isolates counters per day; day cut freezes ended-day values.
        UUID ghost = GameTestSupport.testUuid(41);
        state.add(700, ghost, AnalyticsKeys.KILL_TOTAL, 7L);
        state.add(701, ghost, AnalyticsKeys.KILL_TOTAL, 2L);
        helper.assertTrue(AnalyticsApi.value(server, 700, ghost, AnalyticsKeys.KILL_TOTAL) == 7L
                && AnalyticsApi.value(server, 701, ghost, AnalyticsKeys.KILL_TOTAL) == 2L,
                "per-day counters isolated");

        // Retention window prune (injected small retention; restored in finally).
        AnalyticsConfig.Data tight = new AnalyticsConfig.Data(true, 10_000L, 65_536, 2_048,
                List.of(), 2, Set.of());
        AnalyticsConfig.injectForTests(tight);
        try {
            AnalyticsService.handleDayRollover(server, 702, 703, EclipseSignals.DayRolloverPhase.PRE);
            helper.assertTrue(AnalyticsApi.value(server, 700, ghost, AnalyticsKeys.KILL_TOTAL) == 0L
                    && AnalyticsApi.value(server, 701, ghost, AnalyticsKeys.KILL_TOTAL) == 0L,
                    "days beyond retention pruned");
            helper.assertTrue(!state.knownDays().contains(700) && !state.knownDays().contains(701),
                    "pruned day maps dropped");
        } finally {
            AnalyticsConfig.invalidate();
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void topOrderingAndTies(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        AnalyticsState state = AnalyticsState.get(server);
        int day = 800;
        UUID low = GameTestSupport.testUuid(1);
        UUID tieA = GameTestSupport.testUuid(2);
        UUID tieB = GameTestSupport.testUuid(3);
        state.add(day, low, AnalyticsKeys.KILL_TOTAL, 5L);
        state.add(day, tieA, AnalyticsKeys.KILL_TOTAL, 9L);
        state.add(day, tieB, AnalyticsKeys.KILL_TOTAL, 9L);
        state.add(day, low, AnalyticsKeys.DEATH, 1L);

        List<AnalyticsApi.Entry> top = AnalyticsApi.top(server, day, AnalyticsKeys.KILL_TOTAL, 0);
        helper.assertTrue(top.size() == 3, "all players listed");
        helper.assertTrue(top.get(0).value() == 9L && top.get(1).value() == 9L && top.get(2).value() == 5L,
                "descending order");
        helper.assertTrue(top.get(0).uuid().compareTo(top.get(1).uuid()) < 0,
                "ties break by uuid deterministically");
        helper.assertTrue(AnalyticsApi.top(server, day, AnalyticsKeys.KILL_TOTAL, 2).size() == 2,
                "n truncates");
        // Missing key => value 0 rows still listed (min-order categories need them).
        List<AnalyticsApi.Entry> deaths = AnalyticsApi.top(server, day, AnalyticsKeys.DEATH, 0);
        helper.assertTrue(deaths.size() == 3 && deaths.get(0).value() == 1L
                && deaths.get(1).value() == 0L, "zero rows included, ordered");
        helper.assertTrue(AnalyticsApi.sumAcrossDays(server, low, AnalyticsKeys.KILL_TOTAL) >= 5L,
                "sumAcrossDays sees the day");
        helper.assertTrue(AnalyticsApi.onlineOrKnownUuids(server, day).containsAll(Set.of(low, tieA, tieB)),
                "known uuids include offline data holders");
        helper.assertTrue(AnalyticsApi.categories().contains(AnalyticsKeys.KILL_TOTAL),
                "categories() exposes the namespace");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void craftAllowlistHonored(GameTestHelper helper) {
        ServerPlayer player = mockPlayer(helper);
        MinecraftServer server = helper.getLevel().getServer();
        int day = AnalyticsService.currentDay(server);

        AnalyticsConfig.injectForTests(AnalyticsConfig.defaultsWithAllowlist(Set.of("minecraft:bread")));
        try {
            AnalyticsService.handleCraft(player, new ItemStack(Items.BREAD, 3));
            AnalyticsService.handleCraft(player, new ItemStack(Items.STICK, 4));
            helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(), AnalyticsKeys.CRAFT_TOTAL) == 7L,
                    "craft_total counts everything");
            helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(),
                    AnalyticsKeys.PREFIX_CRAFT + "minecraft:bread") == 3L, "allowlisted id tracked");
            helper.assertTrue(AnalyticsApi.value(server, day, player.getUUID(),
                    AnalyticsKeys.PREFIX_CRAFT + "minecraft:stick") == 0L, "non-allowlisted id dropped");
        } finally {
            AnalyticsConfig.invalidate();
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void killsDeathsDamageAndQuestCounters(GameTestHelper helper) {
        ServerPlayer killer = mockPlayer(helper);
        ServerPlayer victim = mockPlayer(helper);
        MinecraftServer server = helper.getLevel().getServer();
        int day = AnalyticsService.currentDay(server);

        AtomicInteger mobKills = new AtomicInteger();
        EclipseSignals.onMobKilled((p, v) -> {
            if (p == killer) {
                mobKills.incrementAndGet();
            }
        });
        var zombie = helper.spawnWithNoFreeWill(net.minecraft.world.entity.EntityType.ZOMBIE,
                new BlockPos(0, 1, 2));
        AnalyticsService.handleMobKilled(killer, zombie);
        helper.assertTrue(mobKills.get() == 1, "mobKilled signal fired");
        helper.assertTrue(AnalyticsApi.value(server, day, killer.getUUID(), AnalyticsKeys.KILL_TOTAL) == 1L
                && AnalyticsApi.value(server, day, killer.getUUID(),
                        AnalyticsKeys.PREFIX_KILL + "minecraft:zombie") == 1L,
                "kill counters");

        AnalyticsService.handlePlayerDeath(victim, killer);
        helper.assertTrue(AnalyticsApi.value(server, day, victim.getUUID(), AnalyticsKeys.DEATH) == 1L,
                "death counted");

        AnalyticsService.handleDamage(victim, killer, 3.5F);
        helper.assertTrue(AnalyticsApi.value(server, day, victim.getUUID(), AnalyticsKeys.DMG_TAKEN) == 35L,
                "dmg_taken x10 fixed point");
        helper.assertTrue(AnalyticsApi.value(server, day, killer.getUUID(), AnalyticsKeys.DMG_DEALT) == 35L,
                "dmg_dealt x10 fixed point");

        AnalyticsService.handleQuestCompleted(killer, (byte) 0);
        AnalyticsService.handleQuestCompleted(killer, (byte) 2);
        helper.assertTrue(AnalyticsApi.value(server, day, killer.getUUID(), AnalyticsKeys.QUESTS_DONE) == 2L
                && AnalyticsApi.value(server, day, killer.getUUID(), AnalyticsKeys.MAINS_DONE) == 1L
                && AnalyticsApi.value(server, day, killer.getUUID(), AnalyticsKeys.PERSONALS_DONE) == 1L,
                "quest kind counters");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void samplerBudget50Players(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        MinecraftServer server = level.getServer();
        List<ServerPlayer> players = new ArrayList<>(50);
        BlockPos origin = helper.absolutePos(new BlockPos(0, 2, 0));
        for (int i = 0; i < 50; i++) {
            ServerPlayer mock = mockPlayer(helper);
            mock.moveTo(origin.getX() + (i % 8) * 3.0D, origin.getY(), origin.getZ() + (i / 8) * 3.0D);
            players.add(mock);
        }
        AnalyticsConfig.Data cfg = AnalyticsConfig.defaults();
        // Warm-up passes populate anchors/sets and let the JIT see the path.
        for (int i = 0; i < 3; i++) {
            AnalyticsSampler.samplePlayers(server, players, cfg);
        }
        long best = Long.MAX_VALUE;
        for (int run = 0; run < 7; run++) {
            long start = System.nanoTime();
            AnalyticsSampler.samplePlayers(server, players, cfg);
            best = Math.min(best, System.nanoTime() - start);
        }
        // §3.6: one 1 Hz pass for 50 players must stay under 0.2 ms (generous bound;
        // best-of-7 filters GC/scheduler noise on shared CI-less machines).
        helper.assertTrue(best < 200_000L, "sampler pass took " + best + " ns for 50 players");
        helper.succeed();
    }
}
