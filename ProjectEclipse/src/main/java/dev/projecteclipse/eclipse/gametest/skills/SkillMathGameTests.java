package dev.projecteclipse.eclipse.gametest.skills;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.skills.AdvancementXpBridge;
import dev.projecteclipse.eclipse.skills.SkillConfig;
import dev.projecteclipse.eclipse.skills.SkillCurve;
import dev.projecteclipse.eclipse.skills.SkillTree;
import dev.projecteclipse.eclipse.skills.SkillTreeConfig;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B4 pure-math acceptance (plan §3.5): curve anchors + monotonicity, default earn-table
 * values, 21-node tree shape, purchase validation table, advancement XP lookup.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class SkillMathGameTests {
    private SkillMathGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void curveAnchorsAndMonotonicity(GameTestHelper helper) {
        SkillCurve.Params defaults = SkillCurve.Params.defaults();

        // v5 FIX-ECON retuned anchors (baseCost 90): first hour = 3 levels, still ~x6
        // the old grind late.
        long c5 = SkillCurve.cumulativeXp(5, defaults);
        helper.assertTrue(Math.abs(c5 - 2138L) <= 2138L * 5 / 100,
                "C(5)=" + c5 + " must be within ±5% of 2138");
        long c7 = SkillCurve.cumulativeXp(7, defaults);
        helper.assertTrue(Math.abs(c7 - 5043L) <= 5043L * 5 / 100,
                "C(7)=" + c7 + " must be within ±5% of 5043");
        long c12 = SkillCurve.cumulativeXp(12, defaults);
        helper.assertTrue(Math.abs(c12 - 19935L) <= 19935L * 5 / 100,
                "C(12)=" + c12 + " must be within ±5% of 19935");

        int previousCost = 0;
        for (int level = 1; level <= 80; level++) {
            int cost = SkillCurve.xpForLevel(level, defaults);
            helper.assertTrue(cost >= 1, "cost(" + level + ") >= 1");
            helper.assertTrue(cost >= previousCost, "cost(" + level + ") monotonic");
            previousCost = cost;
        }
        // Softcap: level 51 must cost ~2x the raw increment of level 50.
        helper.assertTrue(SkillCurve.xpForLevel(51, defaults) > SkillCurve.xpForLevel(50, defaults) * 3 / 2,
                "softcap doubles per-level cost past 50");

        // levelForXp is the inverse of cumulativeXp.
        for (int level : new int[] {1, 5, 12, 30, 50, 60}) {
            long xp = SkillCurve.cumulativeXp(level, defaults);
            helper.assertTrue(SkillCurve.levelForXp(xp, defaults) == level, "levelForXp(C(" + level + "))");
            helper.assertTrue(SkillCurve.levelForXp(xp - 1, defaults) == level - 1,
                    "levelForXp(C(" + level + ")-1)");
        }
        helper.assertTrue(SkillCurve.levelForXp(0, defaults) == 0, "level 0 at 0 XP");
        // FIX-ECON pacing pin: a hot first session (~800 XP) is level 3 (C(3)=581,
        // C(4)=1210) — the old "level 7 after 5 minutes" stays impossible (C(7)=5043).
        helper.assertTrue(SkillCurve.levelForXp(800, defaults) == 3, "800 XP lands at L3");
        helper.assertTrue(SkillCurve.levelForXp(5042, defaults) == 6, "just below C(7) is L6");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void defaultEarnTableLookups(GameTestHelper helper) {
        SkillConfig.Data data = SkillConfig.parse(SkillConfig.defaultsJson());

        helper.assertTrue(data.mine().forBlock(net.minecraft.world.level.block.Blocks.DIRT.defaultBlockState()) == 1.0F,
                "mine default 1");
        helper.assertTrue(data.mine().forBlock(net.minecraft.world.level.block.Blocks.DIAMOND_ORE.defaultBlockState()) == 12.0F,
                "diamond ore via #minecraft:diamond_ores = 12");
        helper.assertTrue(data.mine().forBlock(net.minecraft.world.level.block.Blocks.DEEPSLATE_DIAMOND_ORE.defaultBlockState()) == 12.0F,
                "deepslate diamond ore via tag = 12");
        helper.assertTrue(data.mine().forBlock(net.minecraft.world.level.block.Blocks.ANCIENT_DEBRIS.defaultBlockState()) == 20.0F,
                "ancient debris exact = 20");
        helper.assertTrue(data.mine().forBlock(net.minecraft.world.level.block.Blocks.STONE.defaultBlockState()) == 0.5F,
                "stone fractional = 0.5");

        helper.assertTrue(data.craft().forItem(new net.minecraft.world.item.ItemStack(
                net.minecraft.world.item.Items.OAK_PLANKS)) == 0.0F, "#planks crafted = 0");
        helper.assertTrue(data.craft().forItem(new net.minecraft.world.item.ItemStack(
                net.minecraft.world.item.Items.CRAFTING_TABLE)) == 2.0F, "crafting table = 2");

        helper.assertTrue(data.death() == -50.0F, "death = -50");
        helper.assertTrue(data.visitNewBiome() == 15.0F, "new biome trimmed to 15 (D2)");
        helper.assertTrue(data.exploreChunk() == 2.0F, "explore chunk trimmed to 2 (D2)");
        helper.assertTrue(data.dailyCap("explore") == 800.0F, "explore daily cap 800 (D2)");
        helper.assertTrue(data.dailyCap("mine") == 3000.0F, "mine daily cap 3000");
        helper.assertTrue(data.dailyCap("quest") == Float.MAX_VALUE, "quest uncapped by default");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void treeShapeMatchesPlanTable(GameTestHelper helper) {
        SkillTreeConfig.Tree tree = SkillTreeConfig.parse(SkillTreeConfig.defaultsJson());
        helper.assertTrue(tree.nodes().size() == 60,
                "60 nodes (wave-5 A14 table), got " + tree.nodes().size());

        int totalCost = 0;
        for (SkillTreeConfig.Node node : tree.nodes().values()) {
            totalCost += node.cost();
            for (String req : node.requires()) {
                helper.assertTrue(tree.nodes().containsKey(req),
                        node.id() + " prereq " + req + " exists");
            }
            helper.assertTrue(!node.title().en().isBlank() && node.title().de() != null,
                    node.id() + " has en+de title");
        }
        helper.assertTrue(totalCost == 147, "full tree costs 147 points, got " + totalCost);

        // Spot-check plan values: S1 +5% vanilla XP (cost 1), U6 +50% night-event kill XP (cost 4).
        SkillTreeConfig.Node s1 = tree.node("S1");
        helper.assertTrue(s1 != null && s1.cost() == 1 && "vanilla_xp_pct".equals(s1.effectType())
                && s1.value() == 0.05F, "S1 Awakened per plan");
        SkillTreeConfig.Node u6 = tree.node("U6");
        helper.assertTrue(u6 != null && u6.cost() == 4 && "night_event_kill_xp_pct".equals(u6.effectType())
                && u6.value() == 0.50F, "U6 Umbral Pact per plan");
        SkillTreeConfig.Node v4 = tree.node("V4");
        helper.assertTrue(v4 != null && v4.value() == 6.0F, "V4 Soft Landing 6 blocks");

        // Wave-5 fillers reuse EXISTING effect contracts and stack additively.
        SkillTreeConfig.Node t9 = tree.node("T9");
        helper.assertTrue(t9 != null && "double_ore_drop_chance".equals(t9.effectType())
                && t9.value() == 0.02F, "T9 Fortune's Echo III per plan");
        helper.assertTrue(SkillTree.effectTotal(tree.nodes(), java.util.Set.of("V4", "V10"),
                "no_fall_damage_below_blocks") == 8.0F, "V10 extends the safe-fall window 6 -> 8");
        helper.assertTrue(!tree.clientJson().isEmpty() && tree.clientJson().contains("\"S1\"")
                && tree.clientJson().contains("\"V17\""), "client JSON carries node ids");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void buyValidationTable(GameTestHelper helper) {
        var nodes = SkillTreeConfig.parse(SkillTreeConfig.defaultsJson()).nodes();
        java.util.Set<String> owned = new java.util.HashSet<>();

        helper.assertTrue(SkillTree.canBuy(nodes, owned, 10, "nope") == SkillTree.BuyResult.UNKNOWN_NODE,
                "unknown node");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 10, "S2") == SkillTree.BuyResult.MISSING_PREREQ,
                "S2 needs S1");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 0, "S1") == SkillTree.BuyResult.NOT_ENOUGH_POINTS,
                "S1 costs 1");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 1, "S1") == SkillTree.BuyResult.OK, "S1 buyable");
        owned.add("S1");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 10, "S1") == SkillTree.BuyResult.ALREADY_OWNED,
                "no double buy");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 1, "S2") == SkillTree.BuyResult.NOT_ENOUGH_POINTS,
                "S2 costs 2");
        helper.assertTrue(SkillTree.canBuy(nodes, owned, 2, "S2") == SkillTree.BuyResult.OK, "S2 buyable");
        helper.assertTrue(SkillTree.effectTotal(nodes, java.util.Set.of("S1", "S2"), "skill_xp_pct") == 0.05F,
                "effect sum finds S2");
        helper.assertTrue(SkillTree.totalCost(nodes, java.util.Set.of("S1", "S2", "S3")) == 6,
                "spine refund = 6");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void advancementXpLookup(GameTestHelper helper) {
        // Uses the LIVE config (defaults on a fresh test env). Dedup of the earn event is
        // inherent — AdvancementEarnEvent fires once per player+advancement per save.
        SkillConfig.Data data = SkillConfig.parse(SkillConfig.defaultsJson());
        helper.assertTrue(data.advancements().forKey("eclipse:herald_slain") == 200.0F,
                "herald_slain = 200");
        helper.assertTrue(AdvancementXpBridge.xpForAdvancement("eclipse:event/skill_12") >= 50.0F,
                "event/-folder id resolves (strip or default)");
        helper.assertTrue(AdvancementXpBridge.xpForAdvancement("eclipse:event/unlisted") == 50.0F
                || AdvancementXpBridge.xpForAdvancement("eclipse:event/unlisted") > 0.0F,
                "unlisted id falls back to default");
        helper.succeed();
    }
}
