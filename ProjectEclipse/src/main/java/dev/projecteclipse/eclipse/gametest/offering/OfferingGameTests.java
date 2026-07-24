package dev.projecteclipse.eclipse.gametest.offering;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardsState;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.offering.OfferingConfig;
import dev.projecteclipse.eclipse.offering.OfferingRules;
import dev.projecteclipse.eclipse.offering.OfferingService;
import dev.projecteclipse.eclipse.offering.OfferingState;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.GameType;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** P4-B6 offering value, one/day, confirmation, duplicate and persistence coverage. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class OfferingGameTests {
    private OfferingGameTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void secretValuesJunkAndEnchantmentMultiplier(GameTestHelper helper) {
        OfferingConfig.Data config = OfferingConfig.defaults();
        ResourceLocation diamond = ResourceLocation.parse("minecraft:diamond");
        int base = OfferingRules.value(diamond, false, false, config);
        int enchanted = OfferingRules.value(diamond, true, false, config);
        helper.assertTrue(base == 40, "diamond default is valuable (40)");
        helper.assertTrue(enchanted == 60, "enchanted diamond applies floor(40×1.5)");
        helper.assertTrue(OfferingRules.value(ResourceLocation.parse("minecraft:dirt"),
                true, true, config) == 0, "explicit junk remains worthless with components");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void duplicateTypesCancelAndUniqueBestWins(GameTestHelper helper) {
        UUID a = GameTestSupport.testUuid(1);
        UUID b = GameTestSupport.testUuid(2);
        UUID c = GameTestSupport.testUuid(3);
        UUID d = GameTestSupport.testUuid(4);
        OfferingRules.Resolution result = OfferingRules.resolve(List.of(
                new OfferingRules.Input(a, "minecraft:diamond", 40),
                new OfferingRules.Input(b, "minecraft:diamond", 60),
                new OfferingRules.Input(c, "minecraft:gold_block", 40),
                new OfferingRules.Input(d, "minecraft:dirt", 0)));
        helper.assertTrue(result.offerings().stream()
                .filter(row -> row.itemId().equals("minecraft:diamond"))
                .allMatch(row -> row.duplicate() && row.value() == 0),
                "both copies are cancelled regardless of component value");
        helper.assertTrue(result.winners().equals(List.of(c)) && result.bestValue() == 40,
                "highest positive unique offering wins");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void confirmationWindowTracksExactItem(GameTestHelper helper) {
        helper.assertTrue(OfferingRules.needsConfirmation(100, null, "", "minecraft:diamond", 100),
                "first click arms");
        helper.assertTrue(!OfferingRules.needsConfirmation(150, 100L, "minecraft:diamond",
                "minecraft:diamond", 100), "same item inside window confirms");
        helper.assertTrue(OfferingRules.needsConfirmation(150, 100L, "minecraft:emerald",
                "minecraft:diamond", 100), "switching item re-arms");
        helper.assertTrue(OfferingRules.needsConfirmation(201, 100L, "minecraft:diamond",
                "minecraft:diamond", 100), "expired window re-arms");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void onePerDaySignalAndConsumption(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        ServerPlayer player = helper.makeMockServerPlayerInLevel();
        player.setGameMode(GameType.SURVIVAL);
        int day = DayScheduler.getDay(server);
        AtomicInteger signals = new AtomicInteger();
        EclipseSignals.onAltarDeposit((who, item, count, purpose) -> {
            if (who == player && purpose == EclipseSignals.AltarDepositPurpose.OFFERING) {
                signals.addAndGet(count);
            }
        });
        OfferingConfig.injectForTests(OfferingConfig.defaults());
        try {
            ItemStack stack = new ItemStack(Items.IRON_INGOT, 3);
            helper.assertTrue(OfferingService.accept(player, stack), "first offering accepted");
            helper.assertTrue(stack.getCount() == 2, "exactly one item consumed");
            helper.assertTrue(signals.get() == 1, "offering signal fired once");
            helper.assertTrue(!OfferingService.accept(player, stack), "second offering refused");
            helper.assertTrue(stack.getCount() == 2 && signals.get() == 1,
                    "refusal consumes and signals nothing");
            helper.assertTrue(OfferingState.get(server).hasOffered(day, player.getUUID()),
                    "one/day state persisted in the live ledger");
        } finally {
            OfferingConfig.invalidate();
            server.getPlayerList().remove(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void stateRoundTripAndRolloverIdempotence(GameTestHelper helper) {
        UUID duplicateA = GameTestSupport.testUuid(41);
        UUID duplicateB = GameTestSupport.testUuid(42);
        UUID winner = GameTestSupport.testUuid(43);
        OfferingState original = new OfferingState();
        original.add(913, new OfferingState.Offer(duplicateA, "minecraft:diamond", false, false));
        original.add(913, new OfferingState.Offer(duplicateB, "minecraft:diamond", true, false));
        original.add(913, new OfferingState.Offer(winner, "minecraft:netherite_ingot", false, false));
        helper.assertTrue(!original.add(913,
                new OfferingState.Offer(winner, "minecraft:dirt", false, false)), "one/day enforced");
        CompoundTag encoded = original.save(new CompoundTag(), helper.getLevel().registryAccess());
        OfferingState loaded = OfferingState.load(encoded, helper.getLevel().registryAccess());
        helper.assertTrue(loaded.offers(913).size() == 3, "offers survive NBT");

        MinecraftServer server = helper.getLevel().getServer();
        OfferingState live = OfferingState.get(server);
        live.add(914, new OfferingState.Offer(duplicateA, "minecraft:diamond", false, false));
        live.add(914, new OfferingState.Offer(duplicateB, "minecraft:diamond", true, false));
        live.add(914, new OfferingState.Offer(winner, "minecraft:netherite_ingot", false, false));
        OfferingConfig.injectForTests(OfferingConfig.defaults());
        try {
            OfferingState.DayResult first = OfferingService.resolveDay(server, 914);
            OfferingState.DayResult second = OfferingService.resolveDay(server, 914);
            helper.assertTrue(first.equals(second), "double rollover returns frozen result");
            helper.assertTrue(first.winners().equals(List.of(winner)), "duplicate diamonds score zero");
            helper.assertTrue(AwardsState.get(server).pending(winner).size() == 1,
                    "offline winner bonus queued once");
        } finally {
            OfferingConfig.invalidate();
        }
        helper.succeed();
    }
}
