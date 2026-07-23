package dev.projecteclipse.eclipse.gametest.goals;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.economy.ShardEconomy;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.network.S2CGoalProgressPayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import dev.projecteclipse.eclipse.progression.goals.GoalConfig;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.QuestApi;
import dev.projecteclipse.eclipse.progression.goals.QuestDetectors;
import dev.projecteclipse.eclipse.progression.goals.QuestEngine;
import dev.projecteclipse.eclipse.progression.goals.QuestMath;
import dev.projecteclipse.eclipse.progression.goals.QuestState;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.stats.Stats;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Blocks;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.common.damagesource.DamageContainer;
import net.neoforged.neoforge.event.entity.living.BabyEntitySpawnEvent;
import net.neoforged.neoforge.event.entity.living.LivingDamageEvent;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B2 engine acceptance (plan §3.3): deterministic personal draws with lifetime
 * exclusion, every signal trigger completing from a synthetic fire, polled triggers from
 * teleports/stat mutation, team scopes + beats + ritual shims, the night watcher, the
 * legacy adapter and payload/state agreement. Each test doctors its own config dir
 * ({@code GoalConfig.setDirectoryOverride}) on its own day + unique goal ids, and removes
 * its mock players + restores the real config in {@code finally} (tests share one save).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class QuestEngineTest {
    private QuestEngineTest() {}

    // --- shared scaffolding ---

    private static Path doctoredDir(String goalsJson, String questsJson) {
        try {
            Path dir = Files.createTempDirectory("eclipse-quests-test");
            Files.writeString(dir.resolve("goals.json"), goalsJson);
            Files.writeString(dir.resolve("quests.json"), questsJson);
            return dir;
        } catch (Exception e) {
            throw new AssertionError("temp config dir", e);
        }
    }

    private static final String NO_PERSONALS = "{ \"personalPerDay\": 0, \"quests\": [] }";

    private static GoalSpec spec(MinecraftServer server, String id) {
        return QuestApi.byId(server, id).orElseThrow(
                () -> new AssertionError("goal '" + id + "' not resolvable"));
    }

    private static void cleanup(MinecraftServer server, List<ServerPlayer> mocks) {
        for (ServerPlayer mock : mocks) {
            server.getPlayerList().remove(mock);
        }
        GoalConfig.setDirectoryOverride(null);
    }

    // --- tests ---

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void personalDrawDeterministicAndLifetimeExcluded(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 2, "goals": [
                      { "id": "t1_main", "kind": "main", "trigger": { "type": "manual" }, "text": "T1" } ] } ] }
                    """, """
                    { "personalPerDay": 2, "quests": [
                      { "id": "t1_p1", "trigger": { "type": "manual" }, "text": "P1", "weight": 1 },
                      { "id": "t1_p2", "trigger": { "type": "manual" }, "text": "P2", "weight": 1 },
                      { "id": "t1_p3", "trigger": { "type": "manual" }, "text": "P3", "weight": 1 },
                      { "id": "t1_p4", "trigger": { "type": "manual" }, "text": "P4", "weight": 1 },
                      { "id": "t1_p5", "trigger": { "type": "manual" }, "text": "P5", "weight": 1 } ] }
                    """));
            GameTestSupport.setEventDay(server, 2);
            ServerPlayer player = helper.makeMockServerPlayerInLevel();
            mocks.add(player);

            List<GoalSpec> personals = QuestApi.personals(server, player);
            helper.assertTrue(personals.size() == 2, "2 personals drawn (got " + personals.size() + ")");
            List<String> assignedIds = personals.stream().map(GoalSpec::id).toList();
            helper.assertTrue(QuestApi.personals(server, player).stream().map(GoalSpec::id).toList()
                    .equals(assignedIds), "repeat ensure keeps the assignment");

            // The persisted assignment IS the pure-math draw (restart re-derives identically).
            List<QuestMath.Candidate> candidates = GoalConfig.personalPool().stream()
                    .map(p -> new QuestMath.Candidate(p.id(), p.weight())).toList();
            List<String> expected = QuestMath.draw(
                    QuestMath.seed(server.overworld().getSeed(), player.getUUID(), 2, 0), candidates, 2);
            helper.assertTrue(assignedIds.equals(expected),
                    "assignment matches QuestMath.draw (" + assignedIds + " vs " + expected + ")");

            // Complete one personal → lifetime-excluded from the reroll draw.
            String completedId = assignedIds.get(0);
            helper.assertTrue(QuestApi.complete(server, player, spec(server, completedId)), "manual complete");
            helper.assertTrue(!QuestApi.complete(server, player, spec(server, completedId)),
                    "second complete is a no-op");
            List<String> rerolled = QuestApi.reroll(server, player);
            helper.assertTrue(!rerolled.contains(completedId), "reroll excludes lifetime-completed "
                    + completedId + " (got " + rerolled + ")");
            helper.assertTrue(QuestApi.personals(server, player).stream().map(GoalSpec::id).toList()
                    .equals(rerolled), "reroll persisted");
            helper.succeed();
        } finally {
            cleanup(server, mocks);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void signalTriggersDriveProgressRewardsAndSignal(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 3, "goals": [
                      { "id": "t2_kill", "kind": "main",
                        "trigger": { "type": "kill_entity", "target": "minecraft:zombie", "count": 2 },
                        "reward": { "skillXp": 25, "shards": 3,
                                    "items": [ { "id": "minecraft:stick", "count": 2 } ] },
                        "text": "Kill zombies" },
                      { "id": "t2_mine", "kind": "side",
                        "trigger": { "type": "mine_block", "target": "minecraft:stone", "count": 1 }, "text": "Mine" },
                      { "id": "t2_craft", "kind": "side",
                        "trigger": { "type": "craft_item", "target": "minecraft:torch", "count": 4 }, "text": "Craft" },
                      { "id": "t2_deposit", "kind": "side",
                        "trigger": { "type": "deposit_altar", "count": 5 }, "text": "Deposit" },
                      { "id": "t2_chunks", "kind": "side",
                        "trigger": { "type": "explore_chunks", "count": 2 }, "text": "Explore" },
                      { "id": "t2_skill", "kind": "side",
                        "trigger": { "type": "skill_level", "count": 2 }, "text": "Level" },
                      { "id": "t2_smelt", "kind": "side",
                        "trigger": { "type": "smelt_item", "target": "minecraft:iron_ingot", "count": 1 }, "text": "Smelt" },
                      { "id": "t2_biomes", "kind": "side",
                        "trigger": { "type": "visit_biomes", "count": 2 }, "text": "Biomes" },
                      { "id": "t2_place", "kind": "side",
                        "trigger": { "type": "place_blocks", "count": 2 }, "text": "Place" },
                      { "id": "t2_breed", "kind": "side",
                        "trigger": { "type": "breed_animals", "count": 1 }, "text": "Breed" } ] } ] }
                    """, NO_PERSONALS));
            GameTestSupport.setEventDay(server, 3);
            ServerPlayer player = helper.makeMockServerPlayerInLevel();
            mocks.add(player);
            QuestDetectors.rearmSignalListenersForTest(server);
            List<String> completions = new CopyOnWriteArrayList<>();
            EclipseSignals.onQuestCompleted((who, questSpec, scope) -> {
                if (who.getUUID().equals(player.getUUID())) {
                    completions.add(questSpec.id());
                }
            });

            int shardsBefore = ShardEconomy.getShards(player);
            LivingEntity zombie = EntityType.ZOMBIE.create(helper.getLevel());
            helper.assertTrue(zombie != null, "zombie victim");
            EclipseSignals.fireMobKilled(player, zombie);
            helper.assertTrue(QuestApi.progress(server, player, spec(server, "t2_kill")) == 1, "kill 1/2");
            helper.assertTrue(!QuestApi.isDone(server, player, spec(server, "t2_kill")), "not done at 1/2");
            EclipseSignals.fireMobKilled(player, zombie);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_kill")), "kill done at 2/2");
            helper.assertTrue(ShardEconomy.getShards(player) == shardsBefore + 3, "shard reward granted");
            helper.assertTrue(player.getInventory().countItem(Items.STICK) >= 2, "item reward granted");
            helper.assertTrue(completions.contains("t2_kill"), "questCompleted signal fired");

            EclipseSignals.fireNaturalBlockMined(player, Blocks.STONE.defaultBlockState(), BlockPos.ZERO);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_mine")), "mine done");
            EclipseSignals.fireItemCrafted(player, new ItemStack(Items.TORCH, 4));
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_craft")), "craft done");
            EclipseSignals.fireAltarDeposit(player, BuiltInRegistries.ITEM.getKey(Items.IRON_INGOT), 5,
                    EclipseSignals.AltarDepositPurpose.MILESTONE);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_deposit")), "deposit done");
            EclipseSignals.fireChunkExplored(player, new ChunkPos(100, 100));
            EclipseSignals.fireChunkExplored(player, new ChunkPos(100, 101));
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_chunks")), "chunks done");
            EclipseSignals.fireSkillLevelUp(player, 2);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_skill")), "skill level done");
            EclipseSignals.fireItemSmelted(player, new ItemStack(Items.IRON_INGOT, 1));
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_smelt")), "smelt done");
            EclipseSignals.fireBiomeVisited(player, ResourceLocation.parse("minecraft:plains"));
            EclipseSignals.fireBiomeVisited(player, ResourceLocation.parse("minecraft:plains"));
            helper.assertTrue(!QuestApi.isDone(server, player, spec(server, "t2_biomes")),
                    "repeat biome does not double-count");
            EclipseSignals.fireBiomeVisited(player, ResourceLocation.parse("minecraft:desert"));
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_biomes")), "2 distinct biomes done");
            EclipseSignals.fireBlockPlaced(player, Blocks.STONE.defaultBlockState(), BlockPos.ZERO);
            EclipseSignals.fireBlockPlaced(player, Blocks.STONE.defaultBlockState(), BlockPos.ZERO.above());
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_place")), "place done");

            var cowA = EntityType.COW.create(helper.getLevel());
            var cowB = EntityType.COW.create(helper.getLevel());
            var calf = EntityType.COW.create(helper.getLevel());
            helper.assertTrue(cowA != null && cowB != null && calf != null, "breed entities");
            cowA.setInLove(player);
            NeoForge.EVENT_BUS.post(new BabyEntitySpawnEvent(cowA, cowB, calf));
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t2_breed")), "breed done");

            for (String id : List.of("t2_kill", "t2_mine", "t2_craft", "t2_deposit", "t2_chunks",
                    "t2_skill", "t2_smelt", "t2_biomes", "t2_place", "t2_breed")) {
                helper.assertTrue(completions.contains(id), "questCompleted carried " + id);
            }
            helper.succeed();
        } finally {
            cleanup(server, mocks);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void polledTriggersLocationDepthStatTravelCollect(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 4, "goals": [
                      { "id": "t3_loc", "kind": "main",
                        "trigger": { "type": "visit_location", "x": 5000, "z": 5000, "radius": 16 },
                        "text": "Visit" },
                      { "id": "t3_depth", "kind": "main",
                        "trigger": { "type": "reach_depth", "y": -32 }, "text": "Descend" },
                      { "id": "t3_stat", "kind": "main",
                        "trigger": { "type": "stat_threshold",
                                     "statId": "minecraft:custom/minecraft:jump", "count": 10 },
                        "text": "Jump" },
                      { "id": "t3_travel", "kind": "side",
                        "trigger": { "type": "travel_distance", "count": 50 }, "text": "Travel" },
                      { "id": "t3_collect", "kind": "side",
                        "trigger": { "type": "collect_item", "target": "minecraft:iron_ingot", "count": 3 },
                        "text": "Collect" } ] } ] }
                    """, NO_PERSONALS));
            GameTestSupport.setEventDay(server, 4);
            // Login AFTER day+config are live → stat baselines snapshot the current values.
            ServerPlayer player = helper.makeMockServerPlayerInLevel();
            mocks.add(player);

            QuestEngine.runPollNow(server);
            helper.assertTrue(!QuestApi.isDone(server, player, spec(server, "t3_loc")), "far → not visited");
            helper.assertTrue(!QuestApi.isDone(server, player, spec(server, "t3_stat")), "no jumps yet");

            player.teleportTo(5000.0D, -40.0D, 5000.0D);
            QuestEngine.runPollNow(server);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t3_loc")),
                    "teleport into radius + poll completes visit_location");
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t3_depth")),
                    "y=-40 <= -32 completes reach_depth");

            player.getStats().setValue(player, Stats.CUSTOM.get(Stats.JUMP),
                    player.getStats().getValue(Stats.CUSTOM.get(Stats.JUMP)) + 10);
            player.getStats().setValue(player, Stats.CUSTOM.get(Stats.WALK_ONE_CM),
                    player.getStats().getValue(Stats.CUSTOM.get(Stats.WALK_ONE_CM)) + 50 * 100);
            player.getStats().setValue(player, Stats.ITEM_PICKED_UP.get(Items.IRON_INGOT),
                    player.getStats().getValue(Stats.ITEM_PICKED_UP.get(Items.IRON_INGOT)) + 3);
            QuestEngine.runPollNow(server);
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t3_stat")),
                    "stat delta 10 completes stat_threshold");
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t3_travel")),
                    "5000 cm = 50 m completes travel_distance");
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t3_collect")),
                    "picked-up delta 3 completes collect_item");
            helper.succeed();
        } finally {
            cleanup(server, mocks);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void teamScopesBeatsAndRitualShims(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        int altarBefore = EclipseWorldState.get(server).getAltarLevel();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 5, "goals": [
                      { "id": "t4_total", "kind": "main", "scope": "team_total",
                        "trigger": { "type": "mine_block", "target": "minecraft:stone", "count": 3 },
                        "reward": { "shards": 1 }, "text": "Team mine" },
                      { "id": "t4_all", "kind": "main", "scope": "team_all",
                        "trigger": { "type": "reach_depth", "y": 320 }, "text": "Everyone below the sky" },
                      { "id": "t4_beat", "kind": "main", "scope": "team_total",
                        "trigger": { "type": "manual", "beatId": "altar_level_2" }, "text": "Altar 2" },
                      { "id": "t4_herald", "kind": "side",
                        "trigger": { "type": "manual", "beatId": "herald_summoned" }, "text": "Summon" } ] } ] }
                    """, NO_PERSONALS));
            GameTestSupport.setEventDay(server, 5);
            ServerPlayer playerA = helper.makeMockServerPlayerInLevel();
            ServerPlayer playerB = helper.makeMockServerPlayerInLevel();
            mocks.add(playerA);
            mocks.add(playerB);
            QuestDetectors.rearmSignalListenersForTest(server);

            // team_total: contributions from BOTH players feed one counter.
            int shardsA = ShardEconomy.getShards(playerA);
            int shardsB = ShardEconomy.getShards(playerB);
            EclipseSignals.fireNaturalBlockMined(playerA, Blocks.STONE.defaultBlockState(), BlockPos.ZERO);
            EclipseSignals.fireNaturalBlockMined(playerA, Blocks.STONE.defaultBlockState(), BlockPos.ZERO);
            helper.assertTrue(QuestApi.progress(server, playerA, spec(server, "t4_total")) == 2,
                    "team counter at 2");
            helper.assertTrue(!QuestApi.isDone(server, playerA, spec(server, "t4_total")), "not done at 2/3");
            EclipseSignals.fireNaturalBlockMined(playerB, Blocks.STONE.defaultBlockState(), BlockPos.ZERO);
            helper.assertTrue(QuestApi.isDone(server, playerA, spec(server, "t4_total"))
                    && QuestApi.isDone(server, playerB, spec(server, "t4_total")),
                    "team_total done for the whole team at 3/3");
            helper.assertTrue(ShardEconomy.getShards(playerA) == shardsA + 1
                    && ShardEconomy.getShards(playerB) == shardsB + 1,
                    "team completion rewards every online player");

            // team_all: both online players trivially satisfy y <= 320 on the next poll.
            QuestEngine.runPollNow(server);
            helper.assertTrue(QuestApi.isDone(server, playerA, spec(server, "t4_all")),
                    "team_all completes once every online player's part is satisfied");

            // Built-in world-state beat: altar level crossing completes the beat goal.
            EclipseWorldState.get(server).setAltarLevel(2);
            QuestEngine.runPollNow(server);
            helper.assertTrue(QuestApi.isDone(server, playerA, spec(server, "t4_beat")),
                    "altar_level_2 beat completes via poll");

            // Ritual shim: GoalTracker.onHeraldSummoned fires the herald_summoned beat.
            GoalTracker.onHeraldSummoned(server);
            helper.assertTrue(QuestApi.isDone(server, playerA, spec(server, "t4_herald"))
                    && QuestApi.isDone(server, playerB, spec(server, "t4_herald")),
                    "herald_summoned shim credits everyone online");
            QuestApi.completeTeamBeat(server, "herald_summoned"); // idempotent re-fire
            helper.succeed();
        } finally {
            EclipseWorldState.get(server).setAltarLevel(altarBefore);
            cleanup(server, mocks);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nightWatcherCreditsOnlyUndamagedSurvivors(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 6, "goals": [
                      { "id": "t5_main", "kind": "main", "trigger": { "type": "manual" }, "text": "T5" },
                      { "id": "t5_night", "kind": "side",
                        "trigger": { "type": "survive_night_no_damage", "count": 1 },
                        "text": "Survive" } ] } ] }
                    """, NO_PERSONALS));
            GameTestSupport.setEventDay(server, 6);
            ServerPlayer survivor = helper.makeMockServerPlayerInLevel();
            ServerPlayer wounded = helper.makeMockServerPlayerInLevel();
            mocks.add(survivor);
            mocks.add(wounded);

            QuestDetectors.forceNightStartForTest(List.of(survivor, wounded));
            helper.assertTrue(QuestDetectors.isNightEligibleForTest(server, survivor.getUUID())
                    && QuestDetectors.isNightEligibleForTest(server, wounded.getUUID()), "both armed at dusk");

            // Damage flag: a post-damage event during the night forfeits the credit.
            NeoForge.EVENT_BUS.post(new LivingDamageEvent.Post(wounded,
                    new DamageContainer(helper.getLevel().damageSources().generic(), 2.0F)));
            helper.assertTrue(!QuestDetectors.isNightEligibleForTest(server, wounded.getUUID()),
                    "damage drops eligibility");
            helper.assertTrue(QuestDetectors.isNightEligibleForTest(server, survivor.getUUID()),
                    "other player unaffected");

            CompoundTag saved = QuestState.get(server).save(
                    new CompoundTag(), helper.getLevel().registryAccess());
            QuestState reloaded = QuestState.load(saved, helper.getLevel().registryAccess());
            helper.assertTrue(reloaded.isNightEligible(6, survivor.getUUID())
                    && !reloaded.isNightEligible(6, wounded.getUUID()),
                    "night damage flags survive SavedData round-trip");

            QuestDetectors.forceDawnForTest(server);
            helper.assertTrue(QuestApi.isDone(server, survivor, spec(server, "t5_night")),
                    "undamaged survivor credited at dawn");
            helper.assertTrue(!QuestApi.isDone(server, wounded, spec(server, "t5_night")),
                    "damaged player not credited");
            helper.succeed();
        } finally {
            cleanup(server, mocks);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void legacyAdapterAndPayloadsMatchState(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 7, "goals": [
                      { "id": "t6_m0", "kind": "main", "trigger": { "type": "manual" },
                        "text": { "en": "First main", "de": "Erstes Hauptziel" } },
                      { "id": "t6_m1", "kind": "main", "trigger": { "type": "manual" }, "text": "Second main" },
                      { "id": "t6_s0", "kind": "side", "trigger": { "type": "manual", "count": 4 },
                        "text": "A side" } ] } ] }
                    """, NO_PERSONALS));
            GameTestSupport.setEventDay(server, 7);
            ServerPlayer player = helper.makeMockServerPlayerInLevel();
            mocks.add(player);

            // Legacy adapter: /eclipse goals tick path → mains[0] manual-complete + bitmask.
            helper.assertTrue(GoalTracker.mask(player, 7) == 0, "fresh mask empty");
            helper.assertTrue(GoalTracker.complete(player, 0), "legacy tick main[0]");
            helper.assertTrue(!GoalTracker.complete(player, 0), "double tick rejected");
            helper.assertTrue(!GoalTracker.complete(player, 9), "out of range rejected");
            helper.assertTrue(GoalTracker.mask(player, 7) == 0b01, "mask bit 0 set");
            helper.assertTrue(GoalTracker.mask(player, 6) == 0, "stale day reads 0");

            S2CGoalProgressPayload legacy = S2CGoalProgressPayload.currentFor(player);
            helper.assertTrue(legacy.goalLines().equals(List.of("First main", "Second main")),
                    "legacy lines are the mains' text (got " + legacy.goalLines() + ")");
            helper.assertTrue(legacy.done().equals(List.of(true, false)), "legacy flags match state");

            // Quest payload mirrors engine state and survives its stream codec.
            S2CQuestStatePayload payload = QuestEngine.buildPayload(server, player);
            helper.assertTrue(payload.day() == 7, "payload day");
            helper.assertTrue(payload.entries().size() == 3, "mains + side entries");
            S2CQuestStatePayload.QuestEntry first = payload.entries().get(0);
            helper.assertTrue(first.id().equals("t6_m0") && first.kind() == 0 && first.done()
                    && first.progress() == first.target(), "entry 0 done, progress clamped to target");
            helper.assertTrue(first.textEn().equals("First main") && first.textDe().equals("Erstes Hauptziel"),
                    "payload carries en+de literals");
            S2CQuestStatePayload.QuestEntry side = payload.entries().get(2);
            helper.assertTrue(side.id().equals("t6_s0") && side.kind() == 1 && !side.done()
                    && side.target() == 4, "side entry kind/target");
            GameTestSupport.assertPayloadRoundTrip(S2CQuestStatePayload.STREAM_CODEC, payload);

            // Admin revoke round-trip (QuestApi reference path for P5-W4).
            helper.assertTrue(QuestApi.complete(server, player, spec(server, "t6_s0")), "complete side");
            helper.assertTrue(QuestApi.isDone(server, player, spec(server, "t6_s0")), "side done");
            helper.assertTrue(QuestApi.revoke(server, player, spec(server, "t6_s0")), "revoke side");
            helper.assertTrue(!QuestApi.isDone(server, player, spec(server, "t6_s0")), "side un-done");
            helper.assertTrue(QuestApi.progress(server, player, spec(server, "t6_s0")) == 0,
                    "revoke clears progress");
            helper.succeed();
        } finally {
            cleanup(server, mocks);
        }
    }
}
