package dev.projecteclipse.eclipse.gametest.revive;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.glitch.GlitchDrops;
import dev.projecteclipse.eclipse.glitch.GlitchSpawnService;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.ritual.HeartExtractorItem;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.RandomSource;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** P4-B8 extractor, recipe, and soft glitched-entity seam acceptance tests. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class ReviveGameTests {
    private ReviveGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void extractorMathKeepsOneHeart(GameTestHelper helper) {
        helper.assertTrue(HeartExtractorItem.canExtract(3), "three hearts can pay two");
        helper.assertFalse(HeartExtractorItem.canExtract(2), "two hearts would cross safety floor");
        helper.assertTrue(HeartExtractorItem.heartsAfterExtraction(5) == 3, "5 - 2 = 3");
        helper.assertTrue(HeartExtractorItem.FRAGMENT_REWARD == 4, "reward is four fragments");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void extractorFinishRemovesTwoAndGivesFour(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        LivesApi.set(player, 5);
        ItemStack extractor = new ItemStack(EclipseItems.HEART_EXTRACTOR.get());

        EclipseItems.HEART_EXTRACTOR.get().finishUsingItem(extractor, helper.getLevel(), player);

        helper.assertTrue(LivesApi.get(player) == 3, "exactly two max hearts removed");
        helper.assertTrue(player.getInventory().countItem(EclipseItems.HEART_FRAGMENT.get()) == 4,
                "exactly four fragments received");
        helper.assertTrue(extractor.getDamageValue() == 1, "extractor loses one durability");
        helper.assertTrue(player.hasEffect(MobEffects.MOVEMENT_SLOWDOWN), "pain slow applied");
        helper.assertTrue(player.hasEffect(MobEffects.WEAKNESS), "pain weakness applied");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void extractorFinishRefusesUnsafeSacrifice(GameTestHelper helper) {
        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        LivesApi.set(player, 2);
        ItemStack extractor = new ItemStack(EclipseItems.HEART_EXTRACTOR.get());

        EclipseItems.HEART_EXTRACTOR.get().finishUsingItem(extractor, helper.getLevel(), player);

        helper.assertTrue(LivesApi.get(player) == 2, "unsafe use preserves hearts");
        helper.assertTrue(player.getInventory().countItem(EclipseItems.HEART_FRAGMENT.get()) == 0,
                "unsafe use grants no fragments");
        helper.assertTrue(extractor.getDamageValue() == 0, "unsafe use costs no durability");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void b8RecipesLoadAndSigilUnlocks(GameTestHelper helper) {
        var manager = helper.getLevel().getRecipeManager();
        List<ResourceLocation> ids = List.of(
                id("heart_extractor"),
                id("revive_sigil"),
                id("vitae_shard_glitch"));
        for (ResourceLocation id : ids) {
            helper.assertTrue(manager.byKey(id).isPresent(), "recipe loaded: " + id);
        }

        var sigilRecipe = manager.byKey(id("revive_sigil")).orElseThrow();
        Item result = sigilRecipe.value()
                .getResultItem(helper.getLevel().registryAccess())
                .getItem();
        helper.assertTrue(result == EclipseItems.REVIVE_SIGIL.get(), "sigil recipe result");

        ServerPlayer player = GameTestSupport.mockSurvivalPlayer(helper);
        player.resetRecipes(List.of(sigilRecipe));
        helper.assertFalse(player.getRecipeBook().contains(sigilRecipe), "sigil starts locked");
        helper.assertTrue(player.awardRecipes(List.of(sigilRecipe)) == 1, "sigil recipe unlock awarded");
        helper.assertTrue(player.getRecipeBook().contains(sigilRecipe), "sigil recipe now known");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void glitchDecisionsAndMissingEntitiesAreSafe(GameTestHelper helper) {
        helper.assertTrue(GlitchSpawnService.shouldAttemptSpawn(
                true, 3, 3, true, true, 0, 12, 0.2D, 0.35D, 1.0F),
                "eligible fresh-ring sample");
        helper.assertFalse(GlitchSpawnService.shouldAttemptSpawn(
                true, 3, 3, true, false, 0, 12, 0.0D, 1.0D, 1.0F),
                "daytime blocked");
        helper.assertFalse(GlitchSpawnService.shouldAttemptSpawn(
                true, 3, 3, true, true, 12, 12, 0.0D, 1.0D, 1.0F),
                "population cap enforced");
        helper.assertTrue(GlitchSpawnService.isWithinConfiguredFreshWindow(0.75D, 72_000, 24_000),
                "18k-old ring inside 24k window");
        helper.assertFalse(GlitchSpawnService.isWithinConfiguredFreshWindow(0.5D, 72_000, 24_000),
                "36k-old ring outside 24k window");
        helper.assertTrue(GlitchSpawnService.resolveEntityType("eclipse:not_registered_b8").isEmpty(),
                "missing P6 entity soft-fails");

        RandomSource random = RandomSource.create(0xB8L);
        int normal = GlitchDrops.rollDropCount(random, 1, 2, 0, 1);
        int looting = GlitchDrops.rollDropCount(random, 1, 2, 3, 1);
        helper.assertTrue(normal >= 1 && normal <= 2, "normal drop range");
        helper.assertTrue(looting >= 1 && looting <= 3, "Looting adds at most one");
        helper.succeed();
    }

    private static ResourceLocation id(String path) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, path);
    }
}
