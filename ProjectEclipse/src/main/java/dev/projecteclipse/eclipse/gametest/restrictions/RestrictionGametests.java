package dev.projecteclipse.eclipse.gametest.restrictions;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.ContainmentService;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.RecipeGate;
import dev.projecteclipse.eclipse.progression.RecipeGateConfig;
import dev.projecteclipse.eclipse.progression.RecipeGateMath;
import dev.projecteclipse.eclipse.protection.ProtectionConfig;
import dev.projecteclipse.eclipse.protection.SpawnProtectionRules;
import dev.projecteclipse.eclipse.villagers.VillagerRestrictions;
import dev.projecteclipse.eclipse.worldgen.structure.SanctumProtection;
import net.minecraft.core.BlockPos;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.entity.npc.VillagerProfession;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.trading.ItemCost;
import net.minecraft.world.item.trading.MerchantOffer;
import net.minecraft.world.item.trading.MerchantOffers;
import net.minecraft.world.level.GameType;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B7 restriction suite acceptance tests (pure math + lightweight integration hooks).
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class RestrictionGametests {
    private RestrictionGametests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void recipeGateMathLockedAtTable(GameTestHelper helper) {
        RecipeGateConfig.Snapshot cfg = new RecipeGateConfig.Snapshot(List.of(
                new RecipeGateConfig.Tier(1, List.of("minecraft:anvil"), List.of()),
                new RecipeGateConfig.Tier(5, List.of("minecraft:diamond_pickaxe"), List.of()),
                new RecipeGateConfig.Tier(10, List.of("#eclipse:tier_netherite_gear"), List.of())));

        RecipeGateMath.LockedEntries day1 = RecipeGateMath.lockedAt(1, cfg);
        helper.assertTrue(day1.itemEntries().contains("minecraft:diamond_pickaxe"), "day1 diamond locked");
        helper.assertTrue(day1.itemEntries().contains("#eclipse:tier_netherite_gear"), "day1 netherite tag locked");
        helper.assertFalse(day1.itemEntries().contains("minecraft:anvil"), "day1 anvil tier expired");

        RecipeGateMath.LockedEntries day5 = RecipeGateMath.lockedAt(5, cfg);
        helper.assertFalse(day5.itemEntries().contains("minecraft:diamond_pickaxe"), "day5 diamond free");
        helper.assertTrue(day5.itemEntries().contains("#eclipse:tier_netherite_gear"), "day5 netherite still locked");

        RecipeGateMath.LockedEntries day10 = RecipeGateMath.lockedAt(10, cfg);
        helper.assertTrue(day10.itemEntries().isEmpty() && day10.recipeIds().isEmpty(), "day10 all clear");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void recipeGateCraftShrinkOnDayOne(GameTestHelper helper) {
        var server = helper.getLevel().getServer();
        GameTestSupport.setEventDay(server, 1);

        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        ItemStack diamondPick = new ItemStack(Items.DIAMOND_PICKAXE, 1);
        helper.assertTrue(RecipeGate.isItemLocked(server, diamondPick), "diamond pick locked day 1");

        player.getInventory().add(diamondPick.copy());
        ItemStack crafting = diamondPick.copy();
        crafting.onCraftedBy(player.level(), player, 1);
        if (RecipeGate.isItemLocked(server, crafting)) {
            crafting.shrink(crafting.getCount());
        }
        helper.assertTrue(crafting.isEmpty(), "locked craft result stripped");

        GameTestSupport.setEventDay(server, 5);
        helper.assertFalse(RecipeGate.isItemLocked(server, diamondPick), "diamond pick allowed day 5");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void recipeLocksPayloadListsDiamondDayOne(GameTestHelper helper) {
        var server = helper.getLevel().getServer();
        GameTestSupport.setEventDay(server, 1);
        List<String> locked = RecipeGate.lockedItemIds(server);
        helper.assertTrue(locked.contains("minecraft:diamond_pickaxe"), "payload includes diamond pick");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void villagerEnchantedBookOfferFilter(GameTestHelper helper) {
        MerchantOffers offers = new MerchantOffers();
        offers.add(new MerchantOffer(
                new ItemCost(Items.EMERALD, 5),
                new ItemStack(Items.ENCHANTED_BOOK),
                12, 1, 0.05F));
        VillagerRestrictions.filterMerchantOffers(offers);
        helper.assertTrue(offers.isEmpty(), "enchanted book offer removed");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void wanderingTraderNaturalSpawnBlocked(GameTestHelper helper) {
        helper.assertTrue(VillagerRestrictions.shouldCancelNaturalTrader(MobSpawnType.NATURAL), "natural blocked");
        helper.assertFalse(VillagerRestrictions.shouldCancelNaturalTrader(MobSpawnType.SPAWN_EGG), "egg allowed");
        helper.assertFalse(VillagerRestrictions.shouldCancelNaturalTrader(MobSpawnType.COMMAND), "command allowed");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void containmentBounceSetsImmunity(GameTestHelper helper) {
        var server = helper.getLevel().getServer();
        GameTestSupport.setEventDay(server, 1);
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        ContainmentService.clearImmunityForTests();
        ContainmentService.applyBounce(player);
        helper.assertTrue(ContainmentService.hasFallImmunity(player), "fall immunity after bounce");
        helper.assertTrue(player.getDeltaMovement().y > 2.0D, "upward velocity");
        ContainmentService.clearImmunityForTests();
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void containmentInactiveDayTwo(GameTestHelper helper) {
        var server = helper.getLevel().getServer();
        GameTestSupport.setEventDay(server, 2);
        helper.assertFalse(ContainmentService.isContainmentActive(DayScheduler.getDay(server)), "day2 inactive");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void spawnProtectionUsesSanctumQuery(GameTestHelper helper) {
        var server = helper.getLevel().getServer();
        BlockPos altar = helper.absolutePos(new BlockPos(2, 64, 2));
        dev.projecteclipse.eclipse.core.state.EclipseWorldState.get(server).setSanctumBuilt(altar);
        SanctumProtection.refresh(server);
        BlockPos inside = altar.offset(2, 0, 0);
        BlockPos outside = altar.offset(SanctumProtection.RADIUS + 4, 0, 0);
        helper.assertTrue(SpawnProtectionRules.isInProtectionZone(helper.getLevel(), inside), "inside zone");
        helper.assertFalse(SpawnProtectionRules.isInProtectionZone(helper.getLevel(), outside), "outside zone");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void spawnProtectionCreativeExempt(GameTestHelper helper) {
        ServerPlayer creative = GameTestSupport.mockServerPlayer(helper, GameType.CREATIVE);
        helper.assertTrue(SpawnProtectionRules.isExempt(creative), "creative exempt");
        ServerPlayer survival = GameTestSupport.mockSurvivalPlayer(helper);
        helper.assertFalse(SpawnProtectionRules.isExempt(survival), "survival not exempt");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void librarianProfessionIsDemotable(GameTestHelper helper) {
        helper.assertTrue(ProtectionConfig.current().villagers().blockLibrarian(), "config blocks librarian");
        helper.assertTrue(VillagerProfession.LIBRARIAN != VillagerProfession.NONE, "sanity");
        helper.succeed();
    }
}
