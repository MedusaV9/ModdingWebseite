package dev.projecteclipse.eclipse.gametest.collections;

import java.util.List;
import java.util.UUID;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.AnalyticsService;
import dev.projecteclipse.eclipse.analytics.PlacedBlockTracker;
import dev.projecteclipse.eclipse.collections.CollectionTiers;
import dev.projecteclipse.eclipse.collections.CollectionsConfig;
import dev.projecteclipse.eclipse.collections.CollectionsService;
import dev.projecteclipse.eclipse.collections.CollectionsState;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionDeltaPayload;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionTierPayload;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionsPayload;
import dev.projecteclipse.eclipse.progression.RecipeGateApi;
import dev.projecteclipse.eclipse.skills.SkillState;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CropBlock;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D1 collections acceptance (IDEAS-collections §7): counting through the REAL analytics
 * lanes (mine natural-only via {@code PlacedBlockCheck}, harvest max-age-only), the
 * threshold sweep (multi-tier crossing pays XP+points exactly once, monotonic — never
 * re-pays, never revokes), the {@code RecipeGate} per-player collection unlock, payload
 * codec round-trips, config validation fail-safes and the SavedData NBT round-trip.
 *
 * <p>Counting tests drive {@link AnalyticsService#handleBreak} (the single break owner)
 * rather than firing signals directly, so the placed-block anti-abuse path is exercised
 * end-to-end. Tests reset the mock player's collections/skills entries first — mock
 * player UUIDs share one {@link CollectionsState} within a test world run.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class CollectionGameTests {
    private CollectionGameTests() {}

    /** Clean collections + skills slate for a mock player (fresh-entry pattern). */
    private static CollectionsState.Entry freshEntries(ServerPlayer player) {
        SkillState.Entry skills = SkillState.get(player.server).entry(player.getUUID());
        skills.totalXp = 0L;
        skills.spentPoints = 0;
        skills.ownedNodes.clear();
        skills.secretMultiplier = 1.0F;
        skills.lastLevelSeen = 0;
        skills.bonusPoints = 0;
        skills.xpRemainder = 0.0F;
        skills.capUsed.clear();
        CollectionsState.Entry entry = CollectionsState.get(player.server).entry(player.getUUID());
        entry.counts.clear();
        entry.grantedTiers.clear();
        entry.capUsed.clear();
        entry.capDay = 0;
        return entry;
    }

    // ------------------------------------------------------------------ counting

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void mineLaneCountsNaturalBlocksOnly(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        freshEntries(player);
        UUID uuid = player.getUUID();

        BlockPos naturalPos = helper.absolutePos(new BlockPos(0, 1, 0));
        BlockPos placedPos = helper.absolutePos(new BlockPos(1, 1, 0));
        PlacedBlockTracker.markPlaced(level, placedPos);

        // Natural iron ore break credits the Iron collection through the mine lane.
        AnalyticsService.handleBreak(player, level, naturalPos, Blocks.IRON_ORE.defaultBlockState());
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "iron") == 1L,
                "natural iron ore credited");

        // Player-placed ore is filtered by the PlacedBlockCheck lane — never credits (§5.1).
        AnalyticsService.handleBreak(player, level, placedPos, Blocks.IRON_ORE.defaultBlockState());
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "iron") == 1L,
                "placed ore filtered");

        // Deepslate variant counts into the same collection; unrelated blocks never do.
        AnalyticsService.handleBreak(player, level, naturalPos,
                Blocks.DEEPSLATE_IRON_ORE.defaultBlockState());
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "iron") == 2L,
                "deepslate variant pooled");
        AnalyticsService.handleBreak(player, level, naturalPos, Blocks.DIRT.defaultBlockState());
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "iron") == 2L,
                "dirt never credits iron");

        // Tag-based collection: any log id rides #minecraft:logs into Timber.
        AnalyticsService.handleBreak(player, level, naturalPos, Blocks.OAK_LOG.defaultBlockState());
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "timber") == 1L,
                "log tag credited timber");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void harvestLaneCountsMaxAgeCropsOnly(GameTestHelper helper) {
        ServerLevel level = helper.getLevel();
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        freshEntries(player);
        UUID uuid = player.getUUID();
        BlockPos pos = helper.absolutePos(new BlockPos(0, 1, 0));

        // Mature wheat credits the harvest lane EVEN with the placed bit set (planted
        // crops always carry it — max age is the rate limiter, §2.2).
        PlacedBlockTracker.markPlaced(level, pos);
        AnalyticsService.handleBreak(player, level, pos,
                Blocks.WHEAT.defaultBlockState().setValue(CropBlock.AGE, CropBlock.MAX_AGE));
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "wheat") == 1L,
                "mature wheat credited");

        // Immature wheat never credits — plant-and-break spam is worth nothing.
        PlacedBlockTracker.markPlaced(level, pos);
        AnalyticsService.handleBreak(player, level, pos,
                Blocks.WHEAT.defaultBlockState().setValue(CropBlock.AGE, 3));
        helper.assertTrue(CollectionsService.countOf(player.server, uuid, "wheat") == 1L,
                "immature wheat filtered");
        helper.succeed();
    }

    // ------------------------------------------------------------------ tier-up + gate unlock

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void tierSweepPaysOnceAndUnlocksRecipes(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        CollectionsState.Entry entry = freshEntries(player);
        SkillState.Entry skills = SkillState.get(player.server).entry(player.getUUID());
        UUID uuid = player.getUUID();

        // Diamond T3 (60) carries the smithing table; locked while the tier is unreached.
        ItemStack smithingTable = new ItemStack(Items.SMITHING_TABLE);
        helper.assertTrue(RecipeGateApi.isItemLockedFor(player, smithingTable),
                "smithing table collection-locked at tier 0");

        // Jump to 150: crosses T1..T4 in one sweep → 75+150+250+400 XP and T4's +2 points.
        helper.assertTrue(CollectionsService.setCount(player, "diamond", 150), "known id");
        helper.assertTrue(CollectionsService.grantedTierOf(player.server, uuid, "diamond") == 4,
                "tiers I-IV granted");
        helper.assertTrue(skills.totalXp == 875L, "tier XP paid once, got " + skills.totalXp);
        int pointsAfterSweep = SkillsApi.getUnspentPoints(player.server, uuid);
        helper.assertTrue(!RecipeGateApi.isItemLockedFor(player, smithingTable),
                "smithing table unlocked at tier III");

        // Idempotent: re-setting the same count re-pays nothing.
        CollectionsService.setCount(player, "diamond", 150);
        helper.assertTrue(skills.totalXp == 875L, "no double pay");
        helper.assertTrue(SkillsApi.getUnspentPoints(player.server, uuid) == pointsAfterSweep,
                "no double points");

        // Monotonic: lowering the counter never revokes tiers, XP or unlocks.
        CollectionsService.setCount(player, "diamond", 10);
        helper.assertTrue(CollectionsService.grantedTierOf(player.server, uuid, "diamond") == 4,
                "granted tier kept after lowering");
        helper.assertTrue(!RecipeGateApi.isItemLockedFor(player, smithingTable),
                "unlock kept after lowering");

        // Only the NEWLY crossed tier pays when progress resumes (T5 at 400: +600 XP).
        CollectionsService.setCount(player, "diamond", 400);
        helper.assertTrue(CollectionsService.grantedTierOf(player.server, uuid, "diamond") == 5,
                "tier V granted");
        helper.assertTrue(skills.totalXp == 1475L, "only T5 added XP, got " + skills.totalXp);
        helper.assertTrue(entry.count("diamond") == 400L, "counter hard-set");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void unknownCollectionIdRejected(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        freshEntries(player);
        helper.assertTrue(!CollectionsService.setCount(player, "no_such_collection", 5L),
                "unknown id rejected");
        helper.succeed();
    }

    // ------------------------------------------------------------------ config validation

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void configDefaultsAndValidationFailSafes(GameTestHelper helper) {
        // Default set pin: all 17 collections of IDEAS-collections §1 parse back.
        CollectionsConfig.Snapshot defaults = CollectionsConfig.parse(CollectionsConfig.defaultRoot());
        helper.assertTrue(defaults.collections().size() == 17,
                "17 default collections, got " + defaults.collections().size());
        helper.assertTrue(defaults.toastsEnabled() && defaults.xpSourceKey().equals("collection"),
                "default toasts + source key");
        CollectionsConfig.Collection iron = defaults.byId("iron");
        helper.assertTrue(iron != null && iron.tiers().size() == 6
                && iron.tiers().get(3).unlockItems().contains("minecraft:anvil"),
                "iron ladder pinned (anvil union tier IV)");

        // Unknown lane → collection skipped; non-increasing thresholds → truncated (§6).
        JsonObject bad = JsonParser.parseString("""
                {"collections":[
                  {"id":"badlane","lane":"swim","ids":["minecraft:dirt"],
                   "tiers":[{"threshold":1,"xp":10}]},
                  {"id":"truncated","lane":"mine","ids":["minecraft:dirt"],
                   "tiers":[{"threshold":10,"xp":10},{"threshold":5,"xp":10},
                            {"threshold":99,"xp":10}]}
                ]}""").getAsJsonObject();
        CollectionsConfig.Snapshot parsed = CollectionsConfig.parse(bad);
        helper.assertTrue(parsed.byId("badlane") == null, "unknown lane skipped");
        CollectionsConfig.Collection truncated = parsed.byId("truncated");
        helper.assertTrue(truncated != null && truncated.tiers().size() == 1,
                "non-increasing tier list truncated, got "
                        + (truncated == null ? "null" : truncated.tiers().size()));

        // Shared formatting helpers pinned (tab + toast render through these).
        helper.assertTrue(CollectionTiers.roman(2).equals("II") && CollectionTiers.roman(6).equals("VI"),
                "roman numerals");
        helper.assertTrue(CollectionTiers.formatCount(12500).equals("12\u202F500"),
                "thin-space grouping");
        helper.succeed();
    }

    // ------------------------------------------------------------------ wire + persistence

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadCodecsRoundTrip(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(S2CCollectionsPayload.STREAM_CODEC,
                new S2CCollectionsPayload(List.of(new S2CCollectionsPayload.Entry(
                        "iron", "mining", "minecraft:iron_ingot",
                        List.of(new S2CCollectionsPayload.Tier(15, 50, 0, List.of()),
                                new S2CCollectionsPayload.Tier(75, 100, 1,
                                        List.of("minecraft:shield", "#eclipse:some_tag"))),
                        42L, 1))));
        GameTestSupport.assertPayloadRoundTrip(S2CCollectionDeltaPayload.STREAM_CODEC,
                new S2CCollectionDeltaPayload("iron", 1240L));
        GameTestSupport.assertPayloadRoundTrip(S2CCollectionTierPayload.STREAM_CODEC,
                new S2CCollectionTierPayload("iron", 2, 100, 0, List.of("minecraft:shield")));
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void savedDataNbtRoundTrip(GameTestHelper helper) {
        UUID uuid = GameTestSupport.testUuid(71);
        CollectionsState state = new CollectionsState();
        CollectionsState.Entry entry = state.entry(uuid);
        entry.counts.put("iron", 1240L);
        entry.counts.put("glitch_shards", 3L);
        entry.grantedTiers.put("iron", 3);
        entry.capDay = 4;
        entry.capUsed.put("umbral_shards", 12L);

        var registries = helper.getLevel().registryAccess();
        CompoundTag saved = state.save(new CompoundTag(), registries);
        CollectionsState.Entry loaded = CollectionsState.load(saved, registries).entry(uuid);

        helper.assertTrue(loaded.count("iron") == 1240L && loaded.count("glitch_shards") == 3L,
                "counts");
        helper.assertTrue(loaded.grantedTier("iron") == 3 && loaded.grantedTier("wheat") == 0,
                "granted tiers");
        helper.assertTrue(loaded.capDay == 4 && loaded.capUsed.get("umbral_shards") == 12L,
                "cap bookkeeping");
        helper.succeed();
    }
}
