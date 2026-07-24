package dev.projecteclipse.eclipse.gametest;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.analytics.PlacedBlockData;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.network.S2CAwardRevealPayload;
import dev.projecteclipse.eclipse.network.S2CBuffStatePayload;
import dev.projecteclipse.eclipse.network.S2CDayClockPayload;
import dev.projecteclipse.eclipse.network.S2CGhostRevealPayload;
import dev.projecteclipse.eclipse.network.S2CQuestStatePayload;
import dev.projecteclipse.eclipse.network.S2CRecipeLocksPayload;
import dev.projecteclipse.eclipse.network.S2CSidebarStatePayload;
import dev.projecteclipse.eclipse.network.S2CSkillProcPayload;
import dev.projecteclipse.eclipse.network.S2CSkillStatePayload;
import dev.projecteclipse.eclipse.network.S2CSkillTreePayload;
import dev.projecteclipse.eclipse.network.C2SSkillNodeBuyPayload;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-A1 harness smoke tests: mock player spawn, isolated signal dispatch, and payload codec
 * round-trips for every new P4 wire type.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class HarnessSmokeTest {
    private HarnessSmokeTest() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void mockPlayerExists(GameTestHelper helper) {
        GameTestSupport.mockSurvivalPlayer(helper);
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void signalsDispatchAndUnregister(GameTestHelper helper) {
        AtomicInteger deaths = new AtomicInteger();
        Runnable unregister = GameTestSupport.registerPlayerDeathCounter(deaths);

        var player = GameTestSupport.mockSurvivalPlayer(helper);
        try {
            EclipseSignals.firePlayerDeath(player, null);
            helper.assertTrue(deaths.get() == 1, "playerDeath listener");
        } finally {
            // Remove only this test's listener; production service listeners stay intact.
            unregister.run();
        }
        EclipseSignals.firePlayerDeath(player, null);
        helper.assertTrue(deaths.get() == 1, "test listener removed");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void payloadCodecRoundTrips(GameTestHelper helper) {
        GameTestSupport.assertPayloadRoundTrip(S2CDayClockPayload.STREAM_CODEC,
                new S2CDayClockPayload(3, 1_700_000_000_000L, 1_699_000_000_000L,
                        1_700_000_100_000L, true, 60_000L));

        GameTestSupport.assertPayloadRoundTrip(S2CQuestStatePayload.STREAM_CODEC,
                new S2CQuestStatePayload(2, List.of(
                        new S2CQuestStatePayload.QuestEntry("q1", (byte) 0, "Mine iron", "Eisen abbauen",
                                4, 32, false, true))));

        GameTestSupport.assertPayloadRoundTrip(S2CSkillStatePayload.STREAM_CODEC,
                new S2CSkillStatePayload(5, 1200L, 80, 200, 4, 1,
                        List.of("S1", "T2"), true, false));

        GameTestSupport.assertPayloadRoundTrip(S2CSkillProcPayload.STREAM_CODEC,
                new S2CSkillProcPayload("double_ore", 2.0F));

        UUID winner = GameTestSupport.testUuid(1);
        GameTestSupport.assertPayloadRoundTrip(S2CAwardRevealPayload.STREAM_CODEC,
                new S2CAwardRevealPayload(1, List.of(
                        new S2CAwardRevealPayload.Category("most_kills", "Bloodiest", "Blutigste",
                                "+400 XP", "+400 EP",
                                List.of(new S2CAwardRevealPayload.Candidate(winner, 42L)),
                                List.of(winner)))));

        GameTestSupport.assertPayloadRoundTrip(S2CBuffStatePayload.STREAM_CODEC,
                new S2CBuffStatePayload(List.of(
                        new S2CBuffStatePayload.Buff("double_skill_xp", "Double XP", "Doppelte EP",
                                1_800_000_000_000L, 2.0F))));

        GameTestSupport.assertPayloadRoundTrip(S2CRecipeLocksPayload.STREAM_CODEC,
                new S2CRecipeLocksPayload(List.of("minecraft:diamond_pickaxe"), List.of()));

        GameTestSupport.assertPayloadRoundTrip(S2CSidebarStatePayload.STREAM_CODEC,
                new S2CSidebarStatePayload(4, 1_800_000_000_000L, false,
                        7, 50, 120, 2, 1, 3, 0, 2, 1, 2,
                        List.of("double_ore_drops"), 8));

        GameTestSupport.assertPayloadRoundTrip(S2CGhostRevealPayload.STREAM_CODEC,
                new S2CGhostRevealPayload(99, "PlayerOne", 60));

        GameTestSupport.assertPayloadRoundTrip(S2CSkillTreePayload.STREAM_CODEC,
                new S2CSkillTreePayload("{\"nodes\":[]}"));

        GameTestSupport.assertPayloadRoundTrip(C2SSkillNodeBuyPayload.STREAM_CODEC,
                new C2SSkillNodeBuyPayload("S1"));

        PlacedBlockData data = PlacedBlockData.empty();
        data.sectionBits(0, true)[0] = 0x1L;
        GameTestSupport.assertCodecRoundTrip(PlacedBlockData.CODEC, data);

        helper.succeed();
    }
}
