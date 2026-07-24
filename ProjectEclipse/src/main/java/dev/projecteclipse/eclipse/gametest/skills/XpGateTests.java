package dev.projecteclipse.eclipse.gametest.skills;

import com.google.gson.JsonObject;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.backrooms.BackroomsDimension;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.minigames.MinigameDimensions;
import dev.projecteclipse.eclipse.ritual.CreditsSequence;
import dev.projecteclipse.eclipse.skills.SkillConfig;
import dev.projecteclipse.eclipse.skills.SkillState;
import dev.projecteclipse.eclipse.skills.SkillsApi;
import dev.projecteclipse.eclipse.skills.XpGates;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.level.Level;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D2 acceptance: pre-event action-XP denial (the "level 5 before the start event" root
 * cause), the event-dimension predicate (limbo/minigame/xbox — the user's "backrooms"),
 * reward-source exemptions, and the config gate toggles. The retuned-curve anchor pins
 * live in {@link SkillMathGameTests#curveAnchorsAndMonotonicity}.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class XpGateTests {
    private XpGateTests() {}

    @SuppressWarnings("removal")
    private static ServerPlayer mockServerPlayer(GameTestHelper helper) {
        return helper.makeMockServerPlayerInLevel();
    }

    private static SkillState.Entry freshEntry(ServerPlayer player) {
        SkillState.Entry entry = SkillState.get(player.server).entry(player.getUUID());
        entry.totalXp = 0L;
        entry.spentPoints = 0;
        entry.ownedNodes.clear();
        entry.secretMultiplier = 1.0F;
        entry.lastLevelSeen = 0;
        entry.bonusPoints = 0;
        entry.xpRemainder = 0.0F;
        entry.capUsed.clear();
        return entry;
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void preEventGateBlocksActionXp(GameTestHelper helper) {
        ServerPlayer player = mockServerPlayer(helper);
        SkillState.Entry entry = freshEntry(player);
        EclipseWorldState world = EclipseWorldState.get(player.server);
        boolean eventWasDone = world.isStartEventDone();
        try {
            // Pre-event: every action lane is shut — the lobby grind pays nothing.
            world.setStartEventDone(false);
            helper.assertTrue(!XpGates.actionXpAllowed(player), "action XP denied pre-event");
            helper.assertTrue(!XpGates.allows(player, "mine"), "mine denied pre-event");
            helper.assertTrue(SkillsApi.addXp(player, "mine", 500.0F) == 0, "mine grant eaten");
            helper.assertTrue(SkillsApi.addXp(player, "kill", 500.0F) == 0, "kill grant eaten");
            helper.assertTrue(entry.totalXp == 0L, "totalXp untouched pre-event");

            // Reward sources bypass the gate (quest turn-ins must keep paying).
            helper.assertTrue(XpGates.isExemptSource("quest") && XpGates.allows(player, "quest"),
                    "quest exempt");
            helper.assertTrue(SkillsApi.addXp(player, "quest", 100.0F) == 100, "quest pays pre-event");
            helper.assertTrue(SkillsApi.addXp(player, "admin", 50.0F) == 50, "admin pays pre-event");
            // DOPA-S-04: award claims write the durable record before granting — the XP
            // must never be eaten by a gate.
            helper.assertTrue(XpGates.isExemptSource("award") && XpGates.allows(player, "award"),
                    "award exempt");
            // Minigame payout keys are deliberately NOT exempt (v5: XP off in minigames).
            helper.assertTrue(!XpGates.isExemptSource("minigame"), "minigame source not exempt");

            // Event done: the same action grant pays out.
            world.setStartEventDone(true);
            helper.assertTrue(XpGates.actionXpAllowed(player), "action XP open post-event");
            helper.assertTrue(SkillsApi.addXp(player, "mine", 100.0F) == 100, "mine pays post-event");
            helper.assertTrue(entry.totalXp == 250L, "100+50+100 total");
        } finally {
            world.setStartEventDone(eventWasDone);
            freshEntry(player);
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void eventDimensionPredicate(GameTestHelper helper) {
        // Limbo, both minigame arenas and every xbox/backrooms world are XP-dead zones.
        helper.assertTrue(XpGates.isEventDimension(LimboDimension.LIMBO), "limbo gated");
        helper.assertTrue(XpGates.isEventDimension(MinigameDimensions.ARENA), "minigame arena gated");
        helper.assertTrue(XpGates.isEventDimension(MinigameDimensions.SKY), "minigame sky gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU1), "xbox tu1 gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU12), "xbox tu12 gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU14), "xbox tu14 gated");
        // V5 era variants ride the same expanded BY_WORLD_ID map (incl. the late tu69 add).
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU19), "xbox tu19 gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU31), "xbox tu31 gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU69), "xbox tu69 gated");
        helper.assertTrue(XpGates.isEventDimension(XboxDimensions.XBOX_TU75), "xbox tu75 gated");
        // EVAL-POL-S #1: the three independently added v5 event dimensions.
        helper.assertTrue(XpGates.isEventDimension(BackroomsDimension.BACKROOMS), "backrooms gated");
        helper.assertTrue(XpGates.isEventDimension(ArenaDimension.ARENA), "ferryman arena gated");
        helper.assertTrue(XpGates.isEventDimension(CreditsSequence.EPILOGUE), "epilogue gated");
        // Progression dimensions stay open.
        helper.assertTrue(!XpGates.isEventDimension(Level.OVERWORLD), "overworld open");
        helper.assertTrue(!XpGates.isEventDimension(Level.NETHER), "nether open");
        helper.assertTrue(!XpGates.isEventDimension(Level.END), "end open");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void gateConfigTogglesParse(GameTestHelper helper) {
        // Defaults ship both gates ON.
        SkillConfig.Data defaults = SkillConfig.parse(SkillConfig.defaultsJson());
        helper.assertTrue(defaults.gatePreEvent(), "preEvent gate default on");
        helper.assertTrue(defaults.gateEventDimensions(), "eventDimensions gate default on");

        // Ops can switch each clause off for tests via skills.json → /eclipse reload.
        JsonObject root = new JsonObject();
        JsonObject gates = new JsonObject();
        gates.addProperty("preEvent", false);
        gates.addProperty("eventDimensions", false);
        root.add("gates", gates);
        SkillConfig.Data toggled = SkillConfig.parse(root);
        helper.assertTrue(!toggled.gatePreEvent(), "preEvent gate toggled off");
        helper.assertTrue(!toggled.gateEventDimensions(), "eventDimensions gate toggled off");

        // A legacy file without the block behaves as if both gates are on (migration-safe).
        SkillConfig.Data legacy = SkillConfig.parse(new JsonObject());
        helper.assertTrue(legacy.gatePreEvent() && legacy.gateEventDimensions(),
                "missing gates block = both on");
        helper.succeed();
    }
}
