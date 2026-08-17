package dev.projecteclipse.eclipse.gametest.goals;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.UnlockState;
import dev.projecteclipse.eclipse.progression.goals.GoalConfig;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.QuestApi;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D5 acceptance: the {@code requiresUnlock} phase gate. Personal quests naming a
 * not-yet-granted {@code UnlockState} key never roll (nether quests before the nether
 * opens), gated SIDE goals never materialize before their key — and materialize the
 * moment it is granted mid-day (resolved-day cache keys on the unlock set) — while
 * MAIN goals are never filtered (the authored day arc must not strand).
 *
 * <p>Uses the default {@code EclipseConfig} day plans ({@code nether} unlocks with day 2)
 * and the derived {@code herald_slain} key (flag-driven, so a mid-day grant is one setter)
 * with doctored {@code GoalConfig} directories, per the {@code QuestEngineTest} pattern.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class PhaseAwareDrawTests {
    private PhaseAwareDrawTests() {}

    private static Path doctoredDir(String goalsJson, String questsJson) {
        try {
            Path dir = Files.createTempDirectory("eclipse-phase-test");
            // configVersion pins the doctored files to the current version so the
            // FIX-ECON backup-and-regenerate migration leaves them alone.
            Files.writeString(dir.resolve("goals.json"), pinVersion(goalsJson));
            Files.writeString(dir.resolve("quests.json"), pinVersion(questsJson));
            return dir;
        } catch (Exception e) {
            throw new AssertionError("temp config dir", e);
        }
    }

    private static String pinVersion(String json) {
        return json.replaceFirst("\\{",
                "{ \"configVersion\": " + GoalConfig.CONFIG_VERSION + ",");
    }

    private static void cleanup(MinecraftServer server, List<ServerPlayer> mocks) {
        for (ServerPlayer mock : mocks) {
            server.getPlayerList().remove(mock);
        }
        GoalConfig.setDirectoryOverride(null);
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void gatedPersonalsNeverRollBeforeUnlock(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = EclipseWorldState.get(server).getDay();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            // personalPerDay exceeds the pool, so every ELIGIBLE candidate is always drawn:
            // the draw content directly reveals the candidate filter.
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 1, "goals": [
                      { "id": "pa1_main", "kind": "main", "trigger": { "type": "manual" }, "text": "M" } ] } ] }
                    """, """
                    { "personalPerDay": 4, "quests": [
                      { "id": "pa1_free1", "trigger": { "type": "manual" }, "text": "F1", "weight": 1 },
                      { "id": "pa1_free2", "trigger": { "type": "manual" }, "text": "F2", "weight": 1 },
                      { "id": "pa1_neth1", "trigger": { "type": "manual" }, "text": "N1", "weight": 1,
                        "requiresUnlock": "nether" },
                      { "id": "pa1_neth2", "trigger": { "type": "manual" }, "text": "N2", "weight": 1,
                        "requiresUnlock": "nether" } ] }
                    """));
            GameTestSupport.setEventDay(server, 1);
            helper.assertTrue(!UnlockState.isUnlocked(server, "nether"),
                    "precondition: default day-1 plan has not granted 'nether'");
            ServerPlayer player = GameTestSupport.mockServerPlayerInLevel(helper);
            mocks.add(player);

            List<String> day1 = QuestApi.personals(server, player).stream().map(GoalSpec::id).toList();
            helper.assertTrue(Set.copyOf(day1).equals(Set.of("pa1_free1", "pa1_free2")),
                    "day 1 draws ONLY ungated quests (got " + day1 + ")");

            // Day 2 grants 'nether' (default plan) — the gated quests join the pool.
            GameTestSupport.setEventDay(server, 2);
            helper.assertTrue(UnlockState.isUnlocked(server, "nether"),
                    "precondition: default day-2 plan grants 'nether'");
            List<String> day2 = QuestApi.personals(server, player).stream().map(GoalSpec::id).toList();
            helper.assertTrue(Set.copyOf(day2).equals(
                            Set.of("pa1_free1", "pa1_free2", "pa1_neth1", "pa1_neth2")),
                    "day 2 draws the full pool incl. nether-gated (got " + day2 + ")");
            helper.succeed();
        } finally {
            cleanup(server, mocks);
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void gatedSideMaterializesWhenUnlockGrantedMidDay(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        EclipseWorldState worldState = EclipseWorldState.get(server);
        int entryDay = worldState.getDay();
        boolean heraldBefore = worldState.isHeraldDefeated();
        List<ServerPlayer> mocks = new ArrayList<>();
        try {
            GoalConfig.setDirectoryOverride(doctoredDir("""
                    { "days": [ { "day": 3, "goals": [
                      { "id": "pa2_main_gated", "kind": "main", "trigger": { "type": "manual" },
                        "text": "MG", "requiresUnlock": "herald_slain" },
                      { "id": "pa2_side_free", "kind": "side", "trigger": { "type": "manual" }, "text": "SF" },
                      { "id": "pa2_side_gated", "kind": "side", "trigger": { "type": "manual" },
                        "text": "SG", "requiresUnlock": "herald_slain" } ] } ] }
                    """, "{ \"personalPerDay\": 0, \"quests\": [] }"));
            worldState.setHeraldDefeated(false);
            GameTestSupport.setEventDay(server, 3);

            List<String> sides = QuestApi.sides(server).stream().map(GoalSpec::id).toList();
            helper.assertTrue(sides.equals(List.of("pa2_side_free")),
                    "locked side never materializes (got " + sides + ")");
            List<String> mains = QuestApi.mains(server).stream().map(GoalSpec::id).toList();
            helper.assertTrue(mains.equals(List.of("pa2_main_gated")),
                    "MAIN goals are never phase-filtered (got " + mains + ")");

            // Mid-day grant: the derived herald_slain key appears -> resolved cache rebuilds.
            worldState.setHeraldDefeated(true);
            List<String> sidesAfter = QuestApi.sides(server).stream().map(GoalSpec::id).toList();
            helper.assertTrue(sidesAfter.equals(List.of("pa2_side_free", "pa2_side_gated")),
                    "gated side materializes the moment its key is granted (got " + sidesAfter + ")");
            helper.succeed();
        } finally {
            worldState.setHeraldDefeated(heraldBefore);
            cleanup(server, mocks);
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
    }
}
