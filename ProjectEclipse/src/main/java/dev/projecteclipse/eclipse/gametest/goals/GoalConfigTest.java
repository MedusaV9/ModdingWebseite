package dev.projecteclipse.eclipse.gametest.goals;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.goals.GoalConfig;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec;
import dev.projecteclipse.eclipse.progression.goals.TriggerType;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B2 config tests: built-in defaults satisfy the §2.2 content shape, days missing from
 * goals.json render the legacy days.json strings as manual mains (doctored config dir via
 * {@link GoalConfig#setDirectoryOverride}), the editor validator accepts round-trips and
 * rejects broken input with readable messages, and {@link GoalSpec} JSON round-trips.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class GoalConfigTest {
    private GoalConfigTest() {}

    /** Fresh temp config dir; defaults are written on first load. */
    private static Path tempConfigDir(GameTestHelper helper) {
        try {
            return Files.createTempDirectory("eclipse-goals-test");
        } catch (Exception e) {
            throw new AssertionError("temp dir", e);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void defaultsCoverAllDaysWithValidTriggers(GameTestHelper helper) {
        try {
            GoalConfig.setDirectoryOverride(tempConfigDir(helper));
            Set<String> ids = new HashSet<>();
            for (int day = 1; day <= 14; day++) {
                List<GoalSpec> mains = GoalConfig.mainsForDay(day);
                List<GoalSpec> sides = GoalConfig.sidesForDay(day);
                helper.assertTrue(mains.size() == 3, "day " + day + ": 3 mains (got " + mains.size() + ")");
                helper.assertTrue(sides.size() >= 3 && sides.size() <= 5,
                        "day " + day + ": 3-5 sides (got " + sides.size() + ")");
                for (GoalSpec spec : GoalConfig.goalsForDay(day)) {
                    helper.assertTrue(!spec.id().startsWith("legacy_"),
                            "day " + day + " is authored, not fallback");
                    helper.assertTrue(ids.add(spec.id()), "duplicate id " + spec.id());
                    helper.assertTrue(TriggerType.byIdStrict(spec.trigger().type().id()) != null,
                            "registered trigger for " + spec.id());
                    helper.assertTrue(!spec.text().en().isBlank(), spec.id() + " has en text");
                    helper.assertTrue(!spec.text().pick("de").isBlank(), spec.id() + " has de text");
                }
            }
            helper.assertTrue(GoalConfig.personalPool().size() >= 20,
                    "personal pool >= 20 (got " + GoalConfig.personalPool().size() + ")");
            helper.assertTrue(GoalConfig.personalPerDay() == 3, "3 personals per day");
            for (GoalSpec spec : GoalConfig.personalPool()) {
                helper.assertTrue(spec.goalKind() == GoalSpec.Kind.PERSONAL, spec.id() + " is personal");
                helper.assertTrue(spec.weight() > 0, spec.id() + " drawable");
            }
            helper.assertTrue(TriggerType.ids().size() == 17, "17 registered trigger types");
            helper.succeed();
        } finally {
            GoalConfig.setDirectoryOverride(null);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void missingDayFallsBackToLegacyStrings(GameTestHelper helper) {
        try {
            Path dir = tempConfigDir(helper);
            // Doctored goals.json knows ONLY day 2 — every other day must fall back.
            Files.writeString(dir.resolve("goals.json"), """
                    { "days": [ { "day": 2, "goals": [
                      { "id": "d2_only", "kind": "main",
                        "trigger": { "type": "manual", "count": 1 }, "text": "Doctored" } ] } ] }
                    """);
            GoalConfig.setDirectoryOverride(dir);

            helper.assertTrue(GoalConfig.goalsForDay(2).size() == 1
                    && GoalConfig.goalsForDay(2).get(0).id().equals("d2_only"), "authored day 2 wins");

            List<String> legacy = EclipseConfig.day(9).goals();
            List<GoalSpec> fallback = GoalConfig.goalsForDay(9);
            helper.assertTrue(!legacy.isEmpty(), "days.json has day 9 strings");
            helper.assertTrue(fallback.size() == legacy.size(),
                    "fallback renders every legacy string (got " + fallback.size() + "/" + legacy.size() + ")");
            for (int i = 0; i < fallback.size(); i++) {
                GoalSpec spec = fallback.get(i);
                helper.assertTrue(spec.id().equals("legacy_d9_m" + i), "fallback id " + spec.id());
                helper.assertTrue(spec.goalKind() == GoalSpec.Kind.MAIN, "fallback is a main");
                helper.assertTrue(spec.trigger().type() == TriggerType.MANUAL, "fallback is manual");
                helper.assertTrue(spec.text().en().equals(legacy.get(i)), "fallback keeps the string");
            }
            helper.succeed();
        } catch (Exception e) {
            throw new AssertionError("fallback test", e);
        } finally {
            GoalConfig.setDirectoryOverride(null);
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void validatorAcceptsDefaultsAndRejectsBrokenInput(GameTestHelper helper) {
        try {
            Path dir = tempConfigDir(helper);
            GoalConfig.setDirectoryOverride(dir); // writes the default files
            JsonObject goals = JsonParser.parseString(Files.readString(dir.resolve("goals.json")))
                    .getAsJsonObject();
            JsonObject quests = JsonParser.parseString(Files.readString(dir.resolve("quests.json")))
                    .getAsJsonObject();

            // The shipped defaults validate cleanly and normalization is idempotent.
            var normalizedGoals = GoalConfig.validateAndNormalize(goals);
            helper.assertTrue(GoalConfig.validateAndNormalize(normalizedGoals).equals(normalizedGoals),
                    "goals normalization idempotent");
            var normalizedQuests = GoalConfig.validateAndNormalize(quests);
            helper.assertTrue(GoalConfig.validateAndNormalize(normalizedQuests).equals(normalizedQuests),
                    "quests normalization idempotent");

            assertRejected(helper, "{\"days\": 5}", "days not an array");
            assertRejected(helper, "{\"nothing\": []}", "missing days/quests");
            assertRejected(helper, """
                    { "days": [ { "day": 1, "goals": [
                      { "id": "bad", "trigger": { "type": "not_a_trigger" }, "text": "x" } ] } ] }
                    """, "unknown trigger type");
            assertRejected(helper, """
                    { "days": [ { "day": 1, "goals": [
                      { "id": "dup", "trigger": { "type": "manual" }, "text": "x" },
                      { "id": "dup", "trigger": { "type": "manual" }, "text": "y" } ] } ] }
                    """, "duplicate goal id");
            assertRejected(helper, """
                    { "quests": [
                      { "id": "p1", "kind": "main", "trigger": { "type": "manual" }, "text": "x" } ] }
                    """, "non-personal in quests.json");
            assertRejected(helper, """
                    { "days": [ { "day": 1, "goals": [
                      { "id": "loc", "trigger": { "type": "visit_location", "x": 0, "z": 0 }, "text": "x" } ] } ] }
                    """, "visit_location without radius");
            helper.succeed();
        } catch (Exception e) {
            throw new AssertionError("validator test", e);
        } finally {
            GoalConfig.setDirectoryOverride(null);
        }
    }

    private static void assertRejected(GameTestHelper helper, String json, String label) {
        try {
            GoalConfig.validateAndNormalize(JsonParser.parseString(json));
            throw new AssertionError("validator accepted broken input: " + label);
        } catch (IllegalArgumentException expected) {
            helper.assertTrue(expected.getMessage() != null && !expected.getMessage().isBlank(),
                    label + " has a readable message");
        }
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void goalSpecJsonRoundTrip(GameTestHelper helper) {
        GoalSpec original = new GoalSpec("rt_goal", GoalSpec.Kind.SIDE, GoalSpec.Scope.TEAM_TOTAL,
                new GoalSpec.Trigger(TriggerType.DEPOSIT_ALTAR, "minecraft:iron_ingot", 24, true,
                        0, 0, 0, 0, "", "", "offering"),
                new GoalSpec.Reward(40, 2, List.of(new GoalSpec.ItemReward("minecraft:bread", 3))),
                new Localized("Offer iron", "Eisen opfern"), 1, 0, 0);
        GoalSpec reparsed = GoalSpec.fromJson(original.toJson(), GoalSpec.Kind.MAIN);
        helper.assertTrue(reparsed.id().equals("rt_goal"), "id survives");
        helper.assertTrue(reparsed.goalKind() == GoalSpec.Kind.SIDE, "kind survives");
        helper.assertTrue(reparsed.scope() == GoalSpec.Scope.TEAM_TOTAL, "scope survives");
        helper.assertTrue(reparsed.trigger().type() == TriggerType.DEPOSIT_ALTAR, "trigger type survives");
        helper.assertTrue(reparsed.trigger().target().equals("minecraft:iron_ingot"), "target survives");
        helper.assertTrue(reparsed.trigger().count() == 24, "count survives");
        helper.assertTrue(reparsed.trigger().purpose().equals("OFFERING"), "purpose normalized upper");
        helper.assertTrue(reparsed.reward().skillXp() == 40 && reparsed.reward().shards() == 2,
                "reward numbers survive");
        helper.assertTrue(reparsed.reward().items().size() == 1
                && reparsed.reward().items().get(0).id().equals("minecraft:bread")
                && reparsed.reward().items().get(0).count() == 3, "reward items survive");
        helper.assertTrue(reparsed.text().en().equals("Offer iron")
                && reparsed.text().pick("de").equals("Eisen opfern"), "localized text survives");

        // Localized primitive form + de fallback.
        Localized plain = Localized.parse(JsonParser.parseString("\"Just english\""));
        helper.assertTrue(plain.en().equals("Just english") && plain.pick("de").equals("Just english"),
                "primitive Localized parses with de fallback");
        helper.succeed();
    }
}
