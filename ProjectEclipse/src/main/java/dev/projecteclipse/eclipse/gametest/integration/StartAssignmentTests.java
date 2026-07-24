package dev.projecteclipse.eclipse.gametest.integration;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.start.StartAssignmentService;
import dev.projecteclipse.eclipse.start.StartState;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/** P4-C1 acceptance for deterministic, balanced and restart-safe start-disc assignment. */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class StartAssignmentTests {
    private StartAssignmentTests() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void assignmentIsOrderIndependentAndBalanced(GameTestHelper helper) {
        List<UUID> ids = new ArrayList<>();
        for (int i = 0; i < 19; i++) {
            ids.add(GameTestSupport.testUuid(100 + i));
        }

        Map<UUID, Integer> forward = StartAssignmentService.assignIndexes(
                ids, DiscGeometry.PLAYER_DISC_COUNT);
        Collections.reverse(ids);
        Map<UUID, Integer> reversed = StartAssignmentService.assignIndexes(
                ids, DiscGeometry.PLAYER_DISC_COUNT);
        helper.assertTrue(forward.equals(reversed),
                "UUID sorting makes assignment independent of collection order");

        int[] loads = new int[DiscGeometry.PLAYER_DISC_COUNT];
        for (int index : forward.values()) {
            helper.assertTrue(index >= 0 && index < loads.length,
                    "every assignment references a valid player disc");
            loads[index]++;
        }
        int min = Integer.MAX_VALUE;
        int max = Integer.MIN_VALUE;
        for (int load : loads) {
            min = Math.min(min, load);
            max = Math.max(max, load);
        }
        helper.assertTrue(max - min <= 1,
                "round-robin anchor loads differ by at most one");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void assignmentStateSurvivesNbtRoundTrip(GameTestHelper helper) {
        Map<UUID, Integer> expected = new HashMap<>();
        expected.put(GameTestSupport.testUuid(201), 7);
        expected.put(GameTestSupport.testUuid(202), 0);
        expected.put(GameTestSupport.testUuid(203), 3);

        StartState original = new StartState();
        original.setAssignments(expected);
        CompoundTag encoded = original.save(new CompoundTag(),
                helper.getLevel().registryAccess());
        StartState decoded = StartState.load(encoded, helper.getLevel().registryAccess());

        helper.assertTrue(decoded.isAssigned(), "assigned flag persists");
        helper.assertTrue(decoded.assignments().equals(expected),
                "UUID to disc-index map persists exactly");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void discIndexResolvesToStableGeometry(GameTestHelper helper) {
        for (int index = 0; index < DiscGeometry.PLAYER_DISC_COUNT; index++) {
            helper.assertTrue(
                    DiscGeometry.playerDiscCenter(index)
                            .equals(DiscGeometry.playerDiscCenter(
                                    index + DiscGeometry.PLAYER_DISC_COUNT)),
                    "wrapped disc " + index + " resolves to the same anchor");
        }
        helper.succeed();
    }
}
