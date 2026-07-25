package dev.projecteclipse.eclipse.progression.goals;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Kind;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Reward;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Scope;
import dev.projecteclipse.eclipse.progression.goals.GoalSpec.Trigger;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads {@code config/eclipse/goals.json} (per-day mains + sides) and
 * {@code config/eclipse/quests.json} (personal pool) — plans_v3 P4 §2.2. Missing files are
 * created with the fully authored event defaults: the DEFAULT set migrates the legacy
 * {@code days.json} arc into {@link GoalSpec}s with real triggers and the harder §2.2/§3.4
 * balance targets.
 *
 * <p>Hot reload: {@code QuestEngine} registers a {@code ReloadHooks} hook, so
 * {@code /eclipse reload} re-reads both files; {@link #generation()} bumps on every reload
 * and the engine resyncs quest payloads when it observes the bump.</p>
 *
 * <p>Fallback safety: a day with no {@code goals.json} entry renders its legacy
 * {@code days.json} strings as {@code manual} mains ({@link #goalsForDay}), so a rewritten
 * or partial goals.json can never strand a day without goals.</p>
 *
 * <p>FIX-ECON (EVAL-SAT-S #1): {@code configVersion} gates a backup-and-regenerate
 * migration. A {@code goals.json}/{@code quests.json} older than {@link #CONFIG_VERSION}
 * (a missing field counts as v1) is copied to {@code <name>.bak-v<oldVersion>} and
 * regenerated with the current defaults — nothing is preserved, the v5 ladder replaces
 * the old authoring wholesale.</p>
 */
public final class GoalConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    /**
     * Version 2 = the v5 phase-aware/harder ladder (FIX-ECON migration cut-in). Version 3
     * = EVAL-DOPA-F #8: day-1 {@code TEAM_ALL} mains demoted to {@code EACH_PLAYER} (a
     * single no-show must not zero the onboarding day) and the slow-grinder personals
     * ({@code p_swimmer}/{@code p_leaper}) pushed to {@code minDay 2}. Bump when the
     * shipped default authoring must replace live files on servers.
     */
    public static final int CONFIG_VERSION = 3;
    /** Legacy sidebar bitmask limit — mirrored from {@code ConfigEditor.MAX_GOALS_PER_DAY}. */
    public static final int MAX_MAINS_PER_DAY = 8;
    private static final int MAX_DAYS = 64;
    private static final int MAX_GOALS_PER_DAY = 24;
    private static final int MAX_PERSONAL_POOL = 256;

    // statics reset on ServerStopped — NOT required here: config is JVM-global by design
    // (same lifetime as EclipseConfig); per-save state lives in QuestState only.
    private static volatile Map<Integer, List<GoalSpec>> dayGoals = Map.of();
    private static volatile List<GoalSpec> personalPool = List.of();
    private static volatile int personalPerDay = 3;
    private static volatile int generation = 0;
    private static volatile boolean loaded = false;
    /** Test hook: overrides the config directory (gametests point this at a temp dir). */
    private static volatile Path directoryOverride = null;

    private GoalConfig() {}

    // --- accessors ---

    /** Bumped on every (re)load; consumers cache resolved specs keyed by this. */
    public static int generation() {
        ensureLoaded();
        return generation;
    }

    /** How many personal quests each player is assigned per day ({@code quests.json}). */
    public static int personalPerDay() {
        ensureLoaded();
        return personalPerDay;
    }

    /** The authored personal pool (kind {@code personal}), in file order. */
    public static List<GoalSpec> personalPool() {
        ensureLoaded();
        return personalPool;
    }

    /**
     * Mains + sides for {@code day}, mains first (authored order). Days missing from
     * goals.json fall back to the legacy {@code days.json} strings as {@code manual} mains
     * with ids {@code legacy_d<day>_m<index>} (zero-migration safety).
     */
    public static List<GoalSpec> goalsForDay(int day) {
        ensureLoaded();
        List<GoalSpec> authored = dayGoals.get(day);
        if (authored != null && !authored.isEmpty()) {
            return authored;
        }
        List<Localized> legacy = EclipseConfig.day(day).localizedGoals();
        List<GoalSpec> fallback = new ArrayList<>(legacy.size());
        for (int i = 0; i < Math.min(legacy.size(), MAX_MAINS_PER_DAY); i++) {
            fallback.add(new GoalSpec("legacy_d" + day + "_m" + i, Kind.MAIN, Scope.EACH_PLAYER,
                    Trigger.manual(), Reward.NONE, legacy.get(i), 1, 0, 0));
        }
        return List.copyOf(fallback);
    }

    /** The mains of {@code day} in authored order (legacy adapter + payload source). */
    public static List<GoalSpec> mainsForDay(int day) {
        List<GoalSpec> mains = new ArrayList<>();
        for (GoalSpec spec : goalsForDay(day)) {
            if (spec.goalKind() == Kind.MAIN) {
                mains.add(spec);
            }
        }
        return mains;
    }

    /** The sides of {@code day} in authored order. */
    public static List<GoalSpec> sidesForDay(int day) {
        List<GoalSpec> sides = new ArrayList<>();
        for (GoalSpec spec : goalsForDay(day)) {
            if (spec.goalKind() == Kind.SIDE) {
                sides.add(spec);
            }
        }
        return sides;
    }

    /** Pool entry by id, or {@code null} (assignment ids may outlive an edited pool). */
    public static GoalSpec personalById(String id) {
        for (GoalSpec spec : personalPool()) {
            if (spec.id().equals(id)) {
                return spec;
            }
        }
        return null;
    }

    // --- loading ---

    /**
     * Points the loader at a different directory (pass {@code null} to restore the real
     * {@code config/eclipse/}) and reloads immediately. Gametest/dev hook only.
     */
    public static synchronized void setDirectoryOverride(Path dir) {
        directoryOverride = dir;
        reloadNow();
    }

    /** Re-reads both files, creating missing ones with defaults. Registered as a reload hook. */
    public static synchronized void reloadNow() {
        Path dir = directoryOverride != null ? directoryOverride
                : FMLPaths.CONFIGDIR.get().resolve("eclipse");
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }

        // FIX-ECON: version-gated migration BEFORE the load — outdated files are backed
        // up and deleted so loadOrCreate regenerates the current defaults.
        migrateIfOutdated(dir.resolve("goals.json"));
        migrateIfOutdated(dir.resolve("quests.json"));

        JsonElement goalsJson = loadOrCreate(dir.resolve("goals.json"), GoalConfig::defaultGoalsJson);
        JsonElement questsJson = loadOrCreate(dir.resolve("quests.json"), GoalConfig::defaultQuestsJson);

        Map<Integer, List<GoalSpec>> days;
        try {
            days = parseGoals(goalsJson);
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.error("goals.json invalid; using built-in defaults ({})", e.getMessage());
            days = parseGoals(defaultGoalsJson());
        }

        List<GoalSpec> pool;
        int perDay;
        try {
            JsonObject root = questsJson.getAsJsonObject();
            pool = parsePersonalPool(root);
            perDay = root.has("personalPerDay") ? Math.max(0, root.get("personalPerDay").getAsInt()) : 3;
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.error("quests.json invalid; using built-in defaults ({})", e.getMessage());
            JsonObject root = defaultQuestsJson().getAsJsonObject();
            pool = parsePersonalPool(root);
            perDay = 3;
        }

        dayGoals = Collections.unmodifiableMap(days);
        personalPool = List.copyOf(pool);
        personalPerDay = perDay;
        generation++;
        loaded = true;
        EclipseMod.LOGGER.info("Eclipse goal config loaded (gen {}): {} authored days, {} personal quests, "
                + "{} personals/day", generation, days.size(), pool.size(), perDay);
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reloadNow();
        }
    }

    /**
     * FIX-ECON (EVAL-SAT-S #1): an on-disk file older than {@link #CONFIG_VERSION}
     * (missing {@code configVersion} = v1) is copied aside as
     * {@code <name>.bak-v<oldVersion>} and deleted, so the following
     * {@link #loadOrCreate} regenerates the current v5 defaults. Preserves nothing by
     * design — the v5 ladder replaces the old authoring; the backup keeps it recoverable.
     */
    private static void migrateIfOutdated(Path file) {
        if (!Files.isRegularFile(file)) {
            return;
        }
        int fileVersion = 1;
        try {
            JsonElement root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8));
            if (root.isJsonObject() && root.getAsJsonObject().has("configVersion")) {
                fileVersion = root.getAsJsonObject().get("configVersion").getAsInt();
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.warn("{}: unreadable while checking configVersion; treating as v1 ({})",
                    file.getFileName(), e.getMessage());
        }
        if (fileVersion >= CONFIG_VERSION) {
            return;
        }
        Path backup = file.resolveSibling(file.getFileName() + ".bak-v" + fileVersion);
        try {
            Files.copy(file, backup, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
            Files.delete(file);
            EclipseMod.LOGGER.warn("{} was config version {} (< {}): backed the old file up to {} "
                    + "and regenerating the v5 defaults (phase-aware, harder ladder, shard rewards). "
                    + "Custom authoring must be re-applied to the new file.",
                    file.getFileName(), fileVersion, CONFIG_VERSION, backup.getFileName());
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to back up outdated config {} — keeping the old file",
                    file, e);
        }
    }

    private static JsonElement loadOrCreate(Path file, java.util.function.Supplier<JsonElement> defaults) {
        if (!Files.exists(file)) {
            JsonElement value = defaults.get();
            try {
                Files.writeString(file, GSON.toJson(value), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
            return value;
        }
        try {
            return JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
            return defaults.get();
        }
    }

    private static Map<Integer, List<GoalSpec>> parseGoals(JsonElement rootElement) {
        JsonObject root = rootElement.getAsJsonObject();
        Map<Integer, List<GoalSpec>> days = new LinkedHashMap<>();
        if (!root.has("days")) {
            return days;
        }
        for (JsonElement dayElement : root.getAsJsonArray("days")) {
            JsonObject dayObj = dayElement.getAsJsonObject();
            int day = dayObj.get("day").getAsInt();
            List<GoalSpec> specs = new ArrayList<>();
            for (JsonElement goalElement : dayObj.getAsJsonArray("goals")) {
                GoalSpec spec = GoalSpec.fromJson(goalElement.getAsJsonObject(), Kind.MAIN);
                if (spec.goalKind() == Kind.PERSONAL) {
                    EclipseMod.LOGGER.warn("goals.json day {} entry '{}' has kind 'personal' — "
                            + "personal quests belong in quests.json; treating as side", day, spec.id());
                    spec = new GoalSpec(spec.id(), Kind.SIDE, spec.scope(), spec.trigger(),
                            spec.reward(), spec.text(), spec.weight(), spec.minDay(), spec.maxDay(),
                            spec.requiresUnlock());
                }
                specs.add(spec);
            }
            // Mains first (stable order for the legacy bitmask), sides after, authored order kept.
            List<GoalSpec> ordered = new ArrayList<>(specs.size());
            for (GoalSpec spec : specs) {
                if (spec.goalKind() == Kind.MAIN) {
                    ordered.add(spec);
                }
            }
            int mains = ordered.size();
            if (mains > MAX_MAINS_PER_DAY) {
                EclipseMod.LOGGER.warn("goals.json day {} has {} mains (legacy bitmask caps at {})",
                        day, mains, MAX_MAINS_PER_DAY);
            }
            for (GoalSpec spec : specs) {
                if (spec.goalKind() != Kind.MAIN) {
                    ordered.add(spec);
                }
            }
            days.put(day, List.copyOf(ordered));
        }
        return days;
    }

    private static List<GoalSpec> parsePersonalPool(JsonObject root) {
        List<GoalSpec> pool = new ArrayList<>();
        if (!root.has("quests")) {
            return pool;
        }
        for (JsonElement element : root.getAsJsonArray("quests")) {
            pool.add(GoalSpec.fromJson(element.getAsJsonObject(), Kind.PERSONAL));
        }
        return pool;
    }

    // --- editor support (P5) ---

    /**
     * Strict validate + normalize for the reworked goal editor GUI (P5) — same contract as
     * {@code ConfigEditor.normalizeDays}: throws {@link IllegalArgumentException} with a
     * human-readable message on ANY problem, otherwise returns the normalized JSON to write.
     * Accepts either file shape: a {@code goals.json} root ({@code {"days":[...]}}) or a
     * {@code quests.json} root ({@code {"quests":[...]}}).
     */
    public static JsonElement validateAndNormalize(JsonElement root) {
        if (root == null || !root.isJsonObject()) {
            throw new IllegalArgumentException("root must be an object with \"days\" (goals.json) "
                    + "or \"quests\" (quests.json)");
        }
        JsonObject obj = root.getAsJsonObject();
        if (obj.has("days")) {
            return normalizeGoalsFile(obj);
        }
        if (obj.has("quests")) {
            return normalizeQuestsFile(obj);
        }
        throw new IllegalArgumentException("root must contain a \"days\" or \"quests\" array");
    }

    private static JsonObject normalizeGoalsFile(JsonObject rootIn) {
        if (!rootIn.get("days").isJsonArray()) {
            throw new IllegalArgumentException("\"days\" must be an array");
        }
        JsonArray daysIn = rootIn.getAsJsonArray("days");
        if (daysIn.size() > MAX_DAYS) {
            throw new IllegalArgumentException("too many day entries (" + daysIn.size() + " > " + MAX_DAYS + ")");
        }
        JsonObject out = new JsonObject();
        // Editor saves are stamped current so the version migration never eats them.
        out.addProperty("configVersion", CONFIG_VERSION);
        out.addProperty("_comment", goalsComment());
        JsonArray daysOut = new JsonArray(daysIn.size());
        Set<Integer> seenDays = new HashSet<>();
        Set<String> seenIds = new HashSet<>();
        for (JsonElement dayElement : daysIn) {
            if (!dayElement.isJsonObject()) {
                throw new IllegalArgumentException("day entries must be objects");
            }
            JsonObject dayObj = dayElement.getAsJsonObject();
            if (!dayObj.has("day") || !dayObj.get("day").isJsonPrimitive()) {
                throw new IllegalArgumentException("day entry missing int \"day\"");
            }
            int day = dayObj.get("day").getAsInt();
            if (day < 1 || !seenDays.add(day)) {
                throw new IllegalArgumentException("day " + day + " is " + (day < 1 ? "< 1" : "duplicated"));
            }
            if (!dayObj.has("goals") || !dayObj.get("goals").isJsonArray()) {
                throw new IllegalArgumentException("day " + day + " missing \"goals\" array");
            }
            JsonArray goalsIn = dayObj.getAsJsonArray("goals");
            if (goalsIn.size() > MAX_GOALS_PER_DAY) {
                throw new IllegalArgumentException("day " + day + " has " + goalsIn.size()
                        + " goals (max " + MAX_GOALS_PER_DAY + ")");
            }
            JsonArray goalsOut = new JsonArray(goalsIn.size());
            int mains = 0;
            for (JsonElement goalElement : goalsIn) {
                GoalSpec spec = validateSpec(goalElement, "day " + day, seenIds, false);
                if (spec.goalKind() == Kind.PERSONAL) {
                    throw new IllegalArgumentException("day " + day + " goal '" + spec.id()
                            + "': kind 'personal' belongs in quests.json");
                }
                if (spec.goalKind() == Kind.MAIN) {
                    mains++;
                }
                goalsOut.add(spec.toJson());
            }
            if (mains > MAX_MAINS_PER_DAY) {
                throw new IllegalArgumentException("day " + day + " has " + mains
                        + " mains (max " + MAX_MAINS_PER_DAY + " — legacy bitmask)");
            }
            JsonObject dayOut = new JsonObject();
            dayOut.addProperty("day", day);
            dayOut.add("goals", goalsOut);
            daysOut.add(dayOut);
        }
        out.add("days", daysOut);
        return out;
    }

    private static JsonObject normalizeQuestsFile(JsonObject rootIn) {
        if (!rootIn.get("quests").isJsonArray()) {
            throw new IllegalArgumentException("\"quests\" must be an array");
        }
        JsonArray questsIn = rootIn.getAsJsonArray("quests");
        if (questsIn.size() > MAX_PERSONAL_POOL) {
            throw new IllegalArgumentException("too many personal quests (" + questsIn.size()
                    + " > " + MAX_PERSONAL_POOL + ")");
        }
        int perDay = 3;
        if (rootIn.has("personalPerDay")) {
            perDay = rootIn.get("personalPerDay").getAsInt();
            if (perDay < 0 || perDay > 8) {
                throw new IllegalArgumentException("personalPerDay must be 0..8");
            }
        }
        JsonObject out = new JsonObject();
        out.addProperty("configVersion", CONFIG_VERSION);
        out.addProperty("_comment", questsComment());
        out.addProperty("personalPerDay", perDay);
        JsonArray questsOut = new JsonArray(questsIn.size());
        Set<String> seenIds = new HashSet<>();
        for (JsonElement element : questsIn) {
            GoalSpec spec = validateSpec(element, "quests", seenIds, true);
            if (spec.goalKind() != Kind.PERSONAL) {
                throw new IllegalArgumentException("quests.json entry '" + spec.id()
                        + "' must have kind 'personal'");
            }
            questsOut.add(spec.toJson());
        }
        out.add("quests", questsOut);
        return out;
    }

    private static GoalSpec validateSpec(JsonElement element, String where, Set<String> seenIds,
            boolean personal) {
        if (!element.isJsonObject()) {
            throw new IllegalArgumentException(where + ": goal entries must be objects");
        }
        JsonObject obj = element.getAsJsonObject();
        if (!obj.has("id") || obj.get("id").getAsString().isBlank()) {
            throw new IllegalArgumentException(where + ": goal missing non-blank \"id\"");
        }
        String id = obj.get("id").getAsString();
        if (!seenIds.add(id)) {
            throw new IllegalArgumentException(where + ": duplicate goal id '" + id + "'");
        }
        if (obj.has("kind") && Kind.byId(obj.get("kind").getAsString()) == Kind.MAIN
                && !"main".equals(obj.get("kind").getAsString())) {
            throw new IllegalArgumentException(where + " goal '" + id + "': unknown kind '"
                    + obj.get("kind").getAsString() + "'");
        }
        if (obj.has("scope")) {
            String scope = obj.get("scope").getAsString();
            if (Scope.byId(scope) == Scope.EACH_PLAYER && !"each_player".equals(scope)) {
                throw new IllegalArgumentException(where + " goal '" + id + "': unknown scope '" + scope + "'");
            }
        }
        if (!obj.has("trigger") || !obj.get("trigger").isJsonObject()) {
            throw new IllegalArgumentException(where + " goal '" + id + "': missing \"trigger\" object");
        }
        JsonObject trigger = obj.getAsJsonObject("trigger");
        String typeId = trigger.has("type") ? trigger.get("type").getAsString() : "";
        TriggerType type = TriggerType.byIdStrict(typeId);
        if (type == null) {
            throw new IllegalArgumentException(where + " goal '" + id + "': unknown trigger type '"
                    + typeId + "' (known: " + String.join(", ", TriggerType.ids()) + ")");
        }
        if (trigger.has("count") && trigger.get("count").getAsLong() < 1) {
            throw new IllegalArgumentException(where + " goal '" + id + "': trigger.count must be >= 1");
        }
        switch (type) {
            case VISIT_LOCATION -> {
                if (!trigger.has("radius") || trigger.get("radius").getAsInt() < 1) {
                    throw new IllegalArgumentException(where + " goal '" + id
                            + "': visit_location needs radius >= 1");
                }
            }
            case REACH_DEPTH -> {
                if (!trigger.has("y")) {
                    throw new IllegalArgumentException(where + " goal '" + id + "': reach_depth needs \"y\"");
                }
            }
            case STAT_THRESHOLD -> {
                if (!trigger.has("statId") || trigger.get("statId").getAsString().isBlank()) {
                    throw new IllegalArgumentException(where + " goal '" + id
                            + "': stat_threshold needs \"statId\"");
                }
            }
            default -> { }
        }
        if (!obj.has("text")) {
            throw new IllegalArgumentException(where + " goal '" + id + "': missing \"text\" (string or {en,de})");
        }
        if (personal && obj.has("weight") && obj.get("weight").getAsInt() < 0) {
            throw new IllegalArgumentException(where + " goal '" + id + "': weight must be >= 0");
        }
        return GoalSpec.fromJson(obj, personal ? Kind.PERSONAL : Kind.MAIN);
    }

    // --- defaults: the migrated days.json arc (§2.2/§3.4 anchors, plans_v5 D5 retune:
    // phase-aware requiresUnlock keys + a genuinely harder ladder — day 1–2 stay the
    // on-ramp, day 3+ pushes shape AND numbers; side XP scaled for the D2 curve retune;
    // every personal pays 1–2 shards, per the D14 economy handoff) ---

    private static String goalsComment() {
        return "Per-day mains + sides (plans_v3 P4 §2.2 GoalSpec schema). trigger.type is one of: "
                + String.join(", ", TriggerType.ids())
                + ". scope: each_player | team_total | team_all. Counts: travel_distance in meters, "
                + "stat_threshold in raw stat units (distances cm, damage tenths). manual goals may "
                + "carry trigger.beatId — authored beats: herald_summoned, herald_defeated, finale_begun, "
                + "dragon_defeated, ferryman_defeated, altar_level_<n>, shard_pool_<n>, all_hearts_<n>. "
                + "External engine beats: player_revived, crossing_survived, create_kinetics_built. "
                + "SIDE entries may carry requiresUnlock (an UnlockState key, e.g. nether/brewing/end): "
                + "the side stays hidden until the key is granted (plans_v5 D5). "
                + "Days missing here fall back to days.json strings as manual mains. Edit + /eclipse reload.";
    }

    private static String questsComment() {
        return "Personal quest pool (kind personal). Each player draws personalPerDay quests per day, "
                + "deterministically seeded from (worldSeed, uuid, day); lifetime-completed quests never "
                + "repeat. weight = draw weight (0 = disabled); minDay/maxDay bound the drawable window "
                + "(0 = open). requiresUnlock names an UnlockState key (nether, brewing, enchanting, "
                + "end, create, ...) that must be granted before the quest can roll — the real phase "
                + "gate (plans_v5 D5); day windows stay the coarse bound. Edit + /eclipse reload.";
    }

    static JsonElement defaultGoalsJson() {
        JsonObject root = new JsonObject();
        root.addProperty("configVersion", CONFIG_VERSION);
        root.addProperty("_comment", goalsComment());
        JsonArray days = new JsonArray();
        addDay(days, 1,
                List.of(main("d01_timber", Scope.TEAM_TOTAL,
                                count(TriggerType.MINE_BLOCK, "#minecraft:logs", 128),
                                text("Fell 128 logs as a team", "Fällt als Team 128 Stämme"), xp(300)),
                        // EVAL-DOPA-F #8: EACH_PLAYER, not TEAM_ALL — one day-1 no-show
                        // must not turn the strongest onboarding day into 1/3 mains done.
                        main("d01_stone_age", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:stone_pickaxe", 1),
                                text("Everyone crafts a stone pickaxe", "Jeder fertigt eine Steinspitzhacke"), xp(250)),
                        main("d01_touch_altar", Scope.EACH_PLAYER, location(0, 0, 10),
                                text("Everyone touches the altar", "Jeder berührt den Altar"),
                                new Reward(300, 0, List.of(new GoalSpec.ItemReward("eclipse:umbral_shard", 2))))),
                List.of(side("d01_unscathed", Scope.TEAM_ALL,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive the first night unscathed", "Übersteht die erste Nacht unversehrt"), xp(250)),
                        side("d01_scout", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 32),
                                text("Explore 32 new chunks", "Erkundet 32 neue Chunks"), xp(150)),
                        side("d01_descend", Scope.EACH_PLAYER, depth(-16),
                                text("Descend below Y -16", "Steigt unter Y -16 hinab"), xp(150))));
        addDay(days, 2,
                // B8: visit_dimension instead of visit_biomes — the biome signal fires only on
                // the FIRST-EVER nether-biome visit per player, so scouts who peeked in before
                // day 2 (or re-entries into known biomes) could never complete the quest.
                List.of(main("d02_burning_door", Scope.EACH_PLAYER,
                                count(TriggerType.VISIT_DIMENSION, "minecraft:the_nether", 1),
                                text("Enter the Nether", "Betretet den Nether"), xp(300)),
                        main("d02_gold_rush", Scope.TEAM_TOTAL,
                                count(TriggerType.SMELT_ITEM, "minecraft:gold_ingot", 32),
                                text("Smelt 32 gold ingots as a team", "Schmelzt als Team 32 Goldbarren"), xp(350)),
                        main("d02_altar_1", Scope.TEAM_TOTAL, beat("altar_level_1"),
                                text("Raise the altar to level 1", "Erhebt den Altar auf Stufe 1"),
                                reward(350, 1))),
                List.of(side("d02_pest_control", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "any_hostile", 16),
                                text("Slay 16 hostile mobs", "Erlegt 16 feindliche Monster"), xp(160)),
                        side("d02_prospector", Scope.EACH_PLAYER,
                                count(TriggerType.MINE_BLOCK, "#minecraft:iron_ores", 24),
                                text("Mine 24 iron ore blocks", "Baut 24 Eisenerzblöcke ab"), xp(170)),
                        side("d02_mason", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 128),
                                text("Place 128 blocks", "Setzt 128 Blöcke"), xp(150))));
        addDay(days, 3,
                List.of(main("d03_forge", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "#eclipse:tier_iron_gear", 12),
                                text("Forge two full iron kits — 12 pieces of iron gear as a team",
                                        "Schmiedet zwei volle Eisenausrüstungen — als Team 12 Teile Eisenausrüstung"), xp(400)),
                        main("d03_kinetics", Scope.TEAM_TOTAL, beat("create_kinetics_built"),
                                text("Power your first Create contraption",
                                        "Setzt eure erste Create-Konstruktion in Gang"), reward(400, 1)),
                        main("d03_survey", Scope.TEAM_TOTAL,
                                count(TriggerType.EXPLORE_CHUNKS, "", 96),
                                text("Chart 96 new chunks as a team",
                                        "Kartiert als Team 96 neue Chunks"), xp(350))),
                List.of(side("d03_delver", Scope.EACH_PLAYER, depth(-40),
                                text("Descend below Y -40", "Steigt unter Y -40 hinab"), xp(160)),
                        side("d03_pest", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "any_hostile", 20),
                                text("Slay 20 hostile mobs", "Erlegt 20 feindliche Monster"), xp(180)),
                        side("d03_prospector", Scope.EACH_PLAYER,
                                count(TriggerType.MINE_BLOCK, "#minecraft:iron_ores", 24),
                                text("Mine 24 iron ore blocks", "Baut 24 Eisenerzblöcke ab"), xp(180)),
                        side("d03_devout", Scope.TEAM_TOTAL, deposit("", "MILESTONE", 12),
                                text("Feed 12 items into the altar milestone", "Speist 12 Gegenstände in den Altar-Meilenstein"), xp(160))));
        addDay(days, 4,
                List.of(main("d04_feast", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "#eclipse:hearty_meals", 12),
                                text("Cook 12 hearty meals (Farmer's Delight)",
                                        "Kocht 12 herzhafte Mahlzeiten (Farmer's Delight)"), xp(400)),
                        main("d04_husbandry", Scope.TEAM_TOTAL, count(TriggerType.BREED_ANIMALS, "", 24),
                                text("Breed 24 animals for the pantry", "Züchtet 24 Tiere für die Vorratskammer"), xp(350)),
                        main("d04_iron_wall", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "#eclipse:tier_iron_armor", 4),
                                text("Everyone forges a full suit of iron armor",
                                        "Jeder schmiedet eine komplette Eisenrüstung"), reward(400, 1))),
                List.of(side("d04_smelter", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 64),
                                text("Smelt 64 items", "Schmelzt 64 Gegenstände"), xp(170)),
                        side("d04_wander", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 3000),
                                text("Travel 3000 meters", "Legt 3000 Meter zurück"), xp(150)),
                        side("d04_leap", Scope.EACH_PLAYER,
                                stat("minecraft:custom/minecraft:jump", 800),
                                text("Jump 800 times", "Springt 800 Mal"), xp(150))));
        addDay(days, 5,
                List.of(main("d05_skyward", Scope.TEAM_TOTAL,
                                count(TriggerType.EXPLORE_CHUNKS, "", 240),
                                text("Chart 240 new chunks as a team",
                                        "Kartiert als Team 240 neue Chunks"), xp(450)),
                        main("d05_iron_stock", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:iron_ingot", 128),
                                text("Stockpile 128 iron ingots as a team", "Hortet als Team 128 Eisenbarren"), xp(400)),
                        main("d05_tinker", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:piston", 24),
                                text("Craft 24 pistons for the workshops",
                                        "Fertigt 24 Kolben für die Werkstätten"), reward(450, 1))),
                List.of(side("d05_charter", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 56),
                                text("Explore 56 new chunks", "Erkundet 56 neue Chunks"), xp(180)),
                        side("d05_amethyst", Scope.EACH_PLAYER,
                                count(TriggerType.COLLECT_ITEM, "minecraft:amethyst_shard", 12),
                                text("Collect 12 amethyst shards", "Sammelt 12 Amethystscherben"), xp(160)),
                        side("d05_hisser", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:creeper", 8),
                                text("Defuse 8 creepers", "Entschärft 8 Creeper"), xp(180)),
                        side("d05_redstone", Scope.EACH_PLAYER,
                                count(TriggerType.MINE_BLOCK, "#minecraft:redstone_ores", 16),
                                text("Mine 16 redstone ore blocks", "Baut 16 Redstoneerzblöcke ab"), xp(170))));
        addDay(days, 6,
                List.of(main("d06_fortress", Scope.EACH_PLAYER,
                                count(TriggerType.MINE_BLOCK, "minecraft:nether_bricks", 24),
                                text("Everyone breaks 24 bricks from a Nether fortress",
                                        "Jeder bricht 24 Netherziegel aus einer Netherfestung"), xp(400)),
                        main("d06_blaze_hoard", Scope.EACH_PLAYER,
                                count(TriggerType.COLLECT_ITEM, "minecraft:blaze_rod", 4),
                                text("Everyone collects 4 blaze rods", "Jeder sammelt 4 Lohenruten"), xp(450)),
                        main("d06_lure", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "eclipse:heralds_lure", 1),
                                text("Craft the Herald's Lure", "Fertigt den Köder des Herolds"),
                                reward(500, 1))),
                List.of(side("d06_blaze_slayer", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:blaze", 8),
                                text("Slay 8 blazes", "Erlegt 8 Lohen"), xp(200), "nether"),
                        side("d06_night_nerves", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(220)),
                        side("d06_far_afield", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 4000),
                                text("Travel 4000 meters", "Legt 4000 Meter zurück"), xp(160))));
        addDay(days, 7,
                List.of(main("d07_summon", Scope.TEAM_TOTAL, beat("herald_summoned"),
                                text("Summon the Herald at dusk", "Beschwört den Herold in der Dämmerung"), xp(400)),
                        main("d07_slay", Scope.TEAM_TOTAL, beat("herald_defeated"),
                                text("Defeat the Herald", "Bezwingt den Herold"), new Reward(600, 2, List.of())),
                        main("d07_core", Scope.TEAM_TOTAL, deposit("eclipse:herald_core", "MILESTONE", 1),
                                text("Deposit the Herald Core at the altar", "Legt den Heroldskern am Altar nieder"), xp(450))),
                List.of(side("d07_altar_3", Scope.TEAM_TOTAL, beat("altar_level_3"),
                                text("Raise the altar to level 3", "Erhebt den Altar auf Stufe 3"),
                                reward(250, 1)),
                        side("d07_stand", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 30),
                                text("Slay 30 hostile mobs", "Erlegt 30 feindliche Monster"), xp(200)),
                        side("d07_rampart", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 192),
                                text("Place 192 blocks", "Setzt 192 Blöcke"), xp(170)),
                        side("d07_watchful", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 32),
                                text("Explore 32 new chunks", "Erkundet 32 neue Chunks"), xp(160))));
        addDay(days, 8,
                List.of(main("d08_hoard", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:ender_chest", 6),
                                text("Craft 6 ender chests for the team",
                                        "Fertigt 6 Endertruhen für das Team"), xp(400)),
                        main("d08_pearls", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_pearl", 32),
                                text("Collect 32 ender pearls as a team", "Sammelt als Team 32 Enderperlen"), xp(450)),
                        main("d08_altar_4", Scope.TEAM_TOTAL, beat("altar_level_4"),
                                text("Raise the altar to level 4", "Erhebt den Altar auf Stufe 4"),
                                reward(500, 2))),
                List.of(side("d08_endermen", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:enderman", 6),
                                text("Slay 6 endermen", "Erlegt 6 Endermen"), xp(200)),
                        side("d08_banker", Scope.TEAM_TOTAL, deposit("", "SHARD_BANK", 16),
                                text("Bank 16 umbral shards", "Zahlt 16 Umbralsplitter ein"), xp(170)),
                        side("d08_deep", Scope.EACH_PLAYER, depth(-64),
                                text("Descend below Y -64", "Steigt unter Y -64 hinab"), xp(170))));
        addDay(days, 9,
                List.of(main("d09_alchemy", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:potion", 16),
                                text("Prepare 16 potions for the team",
                                        "Bereitet 16 Tränke für das Team vor"), xp(450)),
                        main("d09_altar_5", Scope.TEAM_TOTAL, beat("altar_level_5"),
                                text("Raise the altar to level 5", "Erhebt den Altar auf Stufe 5"),
                                reward(500, 2)),
                        main("d09_pool", Scope.TEAM_TOTAL, beat("shard_pool_48"),
                                text("Pool 48 umbral shards", "Sammelt 48 Umbralsplitter im Gemeinschaftspool"),
                                reward(450, 1))),
                List.of(side("d09_voltage", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:repeater", 8),
                                text("Craft 8 redstone repeaters", "Fertigt 8 Redstone-Verstärker"), xp(190)),
                        side("d09_furnace", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 64),
                                text("Smelt 64 items", "Schmelzt 64 Gegenstände"), xp(170)),
                        side("d09_biomes", Scope.EACH_PLAYER, count(TriggerType.VISIT_BIOMES, "", 6),
                                text("Visit 6 different biomes", "Besucht 6 verschiedene Biome"), xp(170)),
                        side("d09_cull", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 24),
                                text("Slay 24 hostile mobs", "Erlegt 24 feindliche Monster"), xp(190))));
        addDay(days, 10,
                List.of(main("d10_template", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:netherite_upgrade_smithing_template", 1),
                                text("Find a smithing template", "Findet eine Schmiedevorlage"), xp(450)),
                        main("d10_debris", Scope.TEAM_TOTAL,
                                count(TriggerType.MINE_BLOCK, "minecraft:ancient_debris", 16),
                                text("Mine 16 ancient debris", "Baut 16 antiken Schrott ab"), xp(500)),
                        main("d10_bastion", Scope.TEAM_TOTAL, count(TriggerType.PLACE_BLOCKS, "", 384),
                                text("Fortify your base — place 384 blocks", "Befestigt eure Basis — setzt 384 Blöcke"), xp(350))),
                List.of(side("d10_wither", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:wither_skeleton", 5),
                                text("Slay 5 wither skeletons", "Erlegt 5 Witherskelette"), xp(210), "nether"),
                        side("d10_smelt", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 64),
                                text("Smelt 64 items", "Schmelzt 64 Gegenstände"), xp(170)),
                        side("d10_trek", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 5000),
                                text("Travel 5000 meters", "Legt 5000 Meter zurück"), xp(150))));
        addDay(days, 11,
                List.of(main("d11_hearts", Scope.TEAM_ALL, beat("all_hearts_4"),
                                text("Everyone reaches 4+ hearts", "Jeder erreicht 4+ Herzen"), xp(500)),
                        main("d11_revive", Scope.TEAM_TOTAL, beat("player_revived"),
                                text("Revive a banned player", "Erweckt einen gebannten Spieler wieder"),
                                reward(550, 2)),
                        main("d11_end_kit", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_eye", 16),
                                text("Assemble 16 eyes of ender", "Stellt 16 Enderaugen zusammen"),
                                reward(450, 1))),
                List.of(side("d11_shepherd", Scope.EACH_PLAYER, count(TriggerType.BREED_ANIMALS, "", 12),
                                text("Breed 12 animals", "Züchtet 12 Tiere"), xp(170)),
                        side("d11_iron_nerves", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(220)),
                        side("d11_tithe", Scope.TEAM_TOTAL, deposit("", "", 32),
                                text("Deposit 32 items at the altar", "Legt 32 Gegenstände am Altar nieder"), xp(170))));
        // B8 executes B15's quest seam: the stronghold no longer spawns, so the day-12
        // stronghold trio is replaced with End-disc equivalents at reward parity. The disc
        // materializes in the sky over the sanctum on day 12 (EndDiscService) and carries
        // minecraft:the_end biome above y 320 (DiscBiomeSource) — visit_biomes #is_end is
        // the "stood on the disc" detector, retro-healed on assignment via the lifetime set.
        addDay(days, 12,
                List.of(main("d12_end_disc", Scope.TEAM_TOTAL,
                                count(TriggerType.VISIT_BIOMES, "#minecraft:is_end", 1),
                                text("Locate the End disc in the sky above the sanctum",
                                        "Ortet die Endscheibe am Himmel über dem Heiligtum"), reward(450, 1)),
                        main("d12_rift", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_eye", 20),
                                text("Charge the rift — assemble 20 eyes of ender",
                                        "Ladet den Riss auf — stellt 20 Enderaugen zusammen"), xp(450)),
                        main("d12_war_chest", Scope.TEAM_TOTAL, beat("shard_pool_64"),
                                text("Stockpile 64 umbral shards for the crossing",
                                        "Hortet 64 Umbralsplitter für die Überfahrt"), reward(500, 2))),
                List.of(side("d12_mites", Scope.TEAM_TOTAL,
                                count(TriggerType.KILL_ENTITY, "minecraft:endermite", 8),
                                // 8, not the silverfish 24: endermites only appear from thrown
                                // ender pearls (~5%), so parity is in reward, not count.
                                text("Purge 8 endermites drawn by the rift",
                                        "Vernichtet 8 vom Riss angelockte Endermilben"), xp(190)),
                        side("d12_charter", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 56),
                                text("Explore 56 new chunks", "Erkundet 56 neue Chunks"), xp(180)),
                        side("d12_ender", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:enderman", 8),
                                text("Slay 8 endermen", "Erlegt 8 Endermen"), xp(200)),
                        side("d12_mason", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 192),
                                text("Place 192 blocks", "Setzt 192 Blöcke"), xp(160))));
        addDay(days, 13,
                List.of(main("d13_dragon", Scope.TEAM_TOTAL, beat("dragon_defeated"),
                                text("Defeat the Ender Dragon", "Bezwingt den Enderdrachen"),
                                new Reward(700, 3, List.of())),
                        main("d13_egg", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:dragon_egg", 1),
                                text("Claim the dragon egg", "Beansprucht das Drachenei"),
                                reward(550, 1)),
                        main("d13_home", Scope.TEAM_ALL, location(0, 0, 48),
                                text("All survivors return home", "Alle Überlebenden kehren heim"), xp(400))),
                List.of(side("d13_hostiles", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 40),
                                text("Slay 40 hostile mobs", "Erlegt 40 feindliche Monster"), xp(220)),
                        side("d13_pearls", Scope.EACH_PLAYER,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_pearl", 12),
                                text("Collect 12 ender pearls", "Sammelt 12 Enderperlen"), xp(180)),
                        side("d13_watch", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(220))));
        addDay(days, 14,
                List.of(main("d14_offer", Scope.TEAM_TOTAL, beat("finale_begun"),
                                text("Offer the egg at dusk", "Opfert das Ei in der Dämmerung"), xp(400)),
                        main("d14_crossing", Scope.TEAM_TOTAL, beat("crossing_survived"),
                                text("Survive the crossing", "Überlebt die Überfahrt"), xp(550)),
                        main("d14_ferryman", Scope.TEAM_TOTAL, beat("ferryman_defeated"),
                                text("Defeat the Ferryman before the ship sinks",
                                        "Bezwingt den Fährmann, bevor das Schiff sinkt"),
                                reward(800, 4))),
                List.of(side("d14_last_stand", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "any_hostile", 40),
                                text("Slay 40 hostile mobs", "Erlegt 40 feindliche Monster"), xp(220)),
                        side("d14_tribute", Scope.TEAM_TOTAL, deposit("", "", 40),
                                text("Deposit 40 items at the altar", "Legt 40 Gegenstände am Altar nieder"), xp(180)),
                        side("d14_sprint", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 3000),
                                text("Travel 3000 meters", "Legt 3000 Meter zurück"), xp(150))));
        root.add("days", days);
        return root;
    }

    static JsonElement defaultQuestsJson() {
        JsonObject root = new JsonObject();
        root.addProperty("configVersion", CONFIG_VERSION);
        root.addProperty("_comment", questsComment());
        root.addProperty("personalPerDay", 3);
        JsonArray quests = new JsonArray();
        for (GoalSpec spec : defaultPersonalPool()) {
            quests.add(spec.toJson());
        }
        root.add("quests", quests);
        return root;
    }

    /**
     * D14 (W-SHARDS): EVERY personal quest pays 1–2 PERSONAL umbral shards on top of its
     * skill XP — the quest ladder is rebirth's reliable base income (wave-1 landed:
     * rebirth spends the personal balance). 1 shard for everyday quests, 2 for the
     * harder/late-window ones. Existing quests.json files keep their old values
     * (loadOrCreate never rewrites) — delete the file or edit it, then /eclipse reload.
     */
    private static List<GoalSpec> defaultPersonalPool() {
        List<GoalSpec> pool = new ArrayList<>();
        pool.add(personal("p_explorer", count(TriggerType.EXPLORE_CHUNKS, "", 64),
                text("Explore 64 new chunks", "Erkundet 64 neue Chunks"), 3, 0, 0, reward(180, 1)));
        pool.add(personal("p_hunter", count(TriggerType.KILL_ENTITY, "any_hostile", 30),
                text("Slay 30 hostile mobs", "Erlegt 30 feindliche Monster"), 3, 0, 0, reward(190, 1)));
        pool.add(personal("p_wanderer", count(TriggerType.TRAVEL_DISTANCE, "", 5000),
                text("Travel 5000 meters", "Legt 5000 Meter zurück"), 3, 0, 0, reward(180, 1)));
        pool.add(personal("p_torchbearer", count(TriggerType.CRAFT_ITEM, "minecraft:torch", 128),
                text("Craft 128 torches", "Fertigt 128 Fackeln"), 3, 0, 5, reward(150, 1)));
        pool.add(personal("p_coal_seam", count(TriggerType.MINE_BLOCK, "#minecraft:coal_ores", 64),
                text("Mine 64 coal ore blocks", "Baut 64 Kohleerzblöcke ab"), 3, 0, 7, reward(160, 1)));
        pool.add(personal("p_iron_vein", count(TriggerType.MINE_BLOCK, "#minecraft:iron_ores", 48),
                text("Mine 48 iron ore blocks", "Baut 48 Eisenerzblöcke ab"), 3, 0, 0, reward(180, 1)));
        pool.add(personal("p_gold_seam", count(TriggerType.MINE_BLOCK, "#minecraft:gold_ores", 24),
                text("Mine 24 gold ore blocks", "Baut 24 Golderzblöcke ab"), 2, 2, 0, reward(190, 1)));
        pool.add(personal("p_diamond_gleam", count(TriggerType.MINE_BLOCK, "#minecraft:diamond_ores", 8),
                text("Mine 8 diamond ore blocks", "Baut 8 Diamanterzblöcke ab"), 1, 3, 0,
                reward(220, 2)));
        pool.add(personal("p_deep_delver", depth(-48),
                text("Descend below Y -48", "Steigt unter Y -48 hinab"), 2, 2, 0, reward(160, 1)));
        pool.add(personal("p_biome_taster", count(TriggerType.VISIT_BIOMES, "", 6),
                text("Visit 6 different biomes", "Besucht 6 verschiedene Biome"), 3, 0, 0, reward(170, 1)));
        pool.add(personal("p_breeder", count(TriggerType.BREED_ANIMALS, "", 10),
                text("Breed 10 animals", "Züchtet 10 Tiere"), 2, 2, 0, reward(170, 1)));
        pool.add(personal("p_stoker", count(TriggerType.SMELT_ITEM, "", 64),
                text("Smelt 64 items", "Schmelzt 64 Gegenstände"), 3, 0, 0, reward(160, 1)));
        pool.add(personal("p_builder", count(TriggerType.PLACE_BLOCKS, "", 320),
                text("Place 320 blocks", "Setzt 320 Blöcke"), 3, 0, 0, reward(160, 1)));
        pool.add(personal("p_devout", deposit("", "", 16),
                text("Deposit 16 items at the altar", "Legt 16 Gegenstände am Altar nieder"), 2, 2, 0,
                reward(180, 1)));
        pool.add(personal("p_night_owl", count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), 2, 0, 0,
                reward(220, 2)));
        // EVAL-DOPA-F #8: minDay 2 keeps day-1 personal draws snappy — the slow grinders
        // (jump 1000x, swim 500 m) never roll into the onboarding day.
        pool.add(personal("p_leaper", stat("minecraft:custom/minecraft:jump", 1000),
                text("Jump 1000 times", "Springt 1000 Mal"), 2, 2, 8, reward(150, 1)));
        pool.add(personal("p_swimmer", stat("minecraft:custom/minecraft:swim_one_cm", 50000),
                text("Swim 500 meters", "Schwimmt 500 Meter"), 1, 2, 0, reward(150, 1)));
        pool.add(personal("p_climber", stat("minecraft:custom/minecraft:climb_one_cm", 15000),
                text("Climb 150 meters", "Klettert 150 Meter"), 1, 0, 0, reward(150, 1)));
        pool.add(personal("p_defuser", count(TriggerType.KILL_ENTITY, "minecraft:creeper", 10),
                text("Defuse 10 creepers", "Entschärft 10 Creeper"), 2, 0, 0, reward(190, 1)));
        pool.add(personal("p_angler", stat("minecraft:custom/minecraft:fish_caught", 12),
                text("Catch 12 fish", "Fangt 12 Fische"), 1, 0, 0, reward(170, 1)));
        pool.add(personal("p_lumberjack", count(TriggerType.MINE_BLOCK, "#minecraft:logs", 160),
                text("Fell 160 logs", "Fällt 160 Stämme"), 2, 1, 6, reward(170, 1)));
        pool.add(personal("p_stoneworker", count(TriggerType.MINE_BLOCK, "minecraft:deepslate", 320),
                text("Mine 320 deepslate", "Baut 320 Tiefenschiefer ab"), 2, 2, 0, reward(170, 1)));
        pool.add(personal("p_redstone_hand", count(TriggerType.CRAFT_ITEM, "minecraft:repeater", 16),
                text("Craft 16 redstone repeaters", "Fertigt 16 Redstone-Verstärker"), 2, 3, 0, reward(190, 1)));
        pool.add(personal("p_blaze_hunter", count(TriggerType.KILL_ENTITY, "minecraft:blaze", 12),
                text("Slay 12 blazes", "Erlegt 12 Lohen"), 1, 6, 11, reward(230, 2), "nether"));
        pool.add(personal("p_fortress_raider", count(TriggerType.KILL_ENTITY, "minecraft:wither_skeleton", 4),
                text("Slay 4 wither skeletons", "Erlegt 4 Witherskelette"), 1, 6, 0,
                reward(230, 2), "nether"));
        pool.add(personal("p_ender_hunter", count(TriggerType.KILL_ENTITY, "minecraft:enderman", 10),
                text("Slay 10 endermen", "Erlegt 10 Endermen"), 2, 6, 0, reward(220, 2)));
        pool.add(personal("p_alchemist", count(TriggerType.COLLECT_ITEM, "minecraft:potion", 8),
                text("Prepare 8 potions", "Bereitet 8 Tränke vor"), 2, 6, 0,
                reward(220, 2), "brewing"));
        pool.add(personal("p_enchanter", stat("minecraft:custom/minecraft:enchant_item", 3),
                text("Enchant 3 items", "Verzaubert 3 Gegenstände"), 2, 7, 0,
                reward(220, 2), "enchanting"));
        pool.add(personal("p_end_touch", count(TriggerType.VISIT_BIOMES, "#minecraft:is_end", 1),
                text("Set foot in the End", "Betretet das Ende"), 1, 12, 0,
                reward(250, 2), "end"));
        pool.add(personal("p_adept", count(TriggerType.SKILL_LEVEL, "", 12),
                text("Reach skill level 12", "Erreicht Skill-Level 12"), 1, 3, 0, reward(260, 2)));
        pool.add(personal("p_unique_offering", deposit("", "OFFERING", 1),
                text("Make today's altar offering", "Bringt das heutige Altaropfer dar"),
                2, 2, 0, reward(180, 1)));
        return pool;
    }

    // --- compact spec builders (defaults only) ---

    private static void addDay(JsonArray days, int day, List<GoalSpec> mains, List<GoalSpec> sides) {
        JsonObject obj = new JsonObject();
        obj.addProperty("day", day);
        JsonArray goals = new JsonArray();
        for (GoalSpec spec : mains) {
            goals.add(spec.toJson());
        }
        for (GoalSpec spec : sides) {
            goals.add(spec.toJson());
        }
        obj.add("goals", goals);
        days.add(obj);
    }

    private static GoalSpec main(String id, Scope scope, Trigger trigger, Localized text, Reward reward) {
        return new GoalSpec(id, Kind.MAIN, scope, trigger, reward, text, 1, 0, 0);
    }

    private static GoalSpec side(String id, Scope scope, Trigger trigger, Localized text, Reward reward) {
        return new GoalSpec(id, Kind.SIDE, scope, trigger, reward, text, 1, 0, 0);
    }

    /** Side gated on an {@code UnlockState} key (plans_v5 D5: hidden until the key is granted). */
    private static GoalSpec side(String id, Scope scope, Trigger trigger, Localized text, Reward reward,
            String requiresUnlock) {
        return new GoalSpec(id, Kind.SIDE, scope, trigger, reward, text, 1, 0, 0, requiresUnlock);
    }

    private static GoalSpec personal(String id, Trigger trigger, Localized text, int weight,
            int minDay, int maxDay, Reward reward) {
        return new GoalSpec(id, Kind.PERSONAL, Scope.EACH_PLAYER, trigger, reward, text, weight, minDay, maxDay);
    }

    /** Personal gated on an {@code UnlockState} key (plans_v5 D5: never rolls before the grant). */
    private static GoalSpec personal(String id, Trigger trigger, Localized text, int weight,
            int minDay, int maxDay, Reward reward, String requiresUnlock) {
        return new GoalSpec(id, Kind.PERSONAL, Scope.EACH_PLAYER, trigger, reward, text, weight, minDay,
                maxDay, requiresUnlock);
    }

    private static Trigger count(TriggerType type, String target, long count) {
        return new Trigger(type, target, count, true, 0, 0, 0, 0, "", "", "");
    }

    private static Trigger location(int x, int z, int radius) {
        return new Trigger(TriggerType.VISIT_LOCATION, "", 1, true, x, z, radius, 0, "", "", "");
    }

    private static Trigger depth(int y) {
        return new Trigger(TriggerType.REACH_DEPTH, "", 1, true, 0, 0, 0, y, "", "", "");
    }

    private static Trigger stat(String statId, long count) {
        return new Trigger(TriggerType.STAT_THRESHOLD, "", count, true, 0, 0, 0, 0, statId, "", "");
    }

    private static Trigger beat(String beatId) {
        return new Trigger(TriggerType.MANUAL, "", 1, true, 0, 0, 0, 0, "", beatId, "");
    }

    private static Trigger deposit(String itemTarget, String purpose, long count) {
        return new Trigger(TriggerType.DEPOSIT_ALTAR, itemTarget, count, true, 0, 0, 0, 0, "", "", purpose);
    }

    private static Localized text(String en, String de) {
        return new Localized(en, de);
    }

    private static Reward xp(int skillXp) {
        return new Reward(skillXp, 0, List.of());
    }

    private static Reward reward(int skillXp, int shards) {
        return new Reward(skillXp, shards, List.of());
    }
}
