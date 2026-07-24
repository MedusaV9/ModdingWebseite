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
 */
public final class GoalConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
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
                            spec.reward(), spec.text(), spec.weight(), spec.minDay(), spec.maxDay());
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

    // --- defaults: the migrated days.json arc (§2.2/§3.4 anchors, slightly harder) ---

    private static String goalsComment() {
        return "Per-day mains + sides (plans_v3 P4 §2.2 GoalSpec schema). trigger.type is one of: "
                + String.join(", ", TriggerType.ids())
                + ". scope: each_player | team_total | team_all. Counts: travel_distance in meters, "
                + "stat_threshold in raw stat units (distances cm, damage tenths). manual goals may "
                + "carry trigger.beatId — authored beats: herald_summoned, herald_defeated, finale_begun, "
                + "dragon_defeated, ferryman_defeated, altar_level_<n>, shard_pool_<n>, all_hearts_<n>. "
                + "External engine beats: player_revived, crossing_survived. "
                + "Days missing here fall back to days.json strings as manual mains. Edit + /eclipse reload.";
    }

    private static String questsComment() {
        return "Personal quest pool (kind personal). Each player draws personalPerDay quests per day, "
                + "deterministically seeded from (worldSeed, uuid, day); lifetime-completed quests never "
                + "repeat. weight = draw weight (0 = disabled); minDay/maxDay bound the drawable window "
                + "(0 = open). Edit + /eclipse reload.";
    }

    static JsonElement defaultGoalsJson() {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", goalsComment());
        JsonArray days = new JsonArray();
        addDay(days, 1,
                List.of(main("d01_timber", Scope.TEAM_TOTAL,
                                count(TriggerType.MINE_BLOCK, "#minecraft:logs", 96),
                                text("Fell 96 logs as a team", "Fällt als Team 96 Stämme"), xp(300)),
                        main("d01_stone_age", Scope.TEAM_ALL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:stone_pickaxe", 1),
                                text("Everyone crafts a stone pickaxe", "Jeder fertigt eine Steinspitzhacke"), xp(250)),
                        main("d01_touch_altar", Scope.TEAM_ALL, location(0, 0, 10),
                                text("Everyone touches the altar", "Jeder berührt den Altar"),
                                new Reward(300, 0, List.of(new GoalSpec.ItemReward("eclipse:umbral_shard", 2))))),
                List.of(side("d01_unscathed", Scope.TEAM_ALL,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive the first night unscathed", "Übersteht die erste Nacht unversehrt"), xp(200)),
                        side("d01_scout", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 24),
                                text("Explore 24 new chunks", "Erkundet 24 neue Chunks"), xp(100)),
                        side("d01_descend", Scope.EACH_PLAYER, depth(-16),
                                text("Descend below Y -16", "Steigt unter Y -16 hinab"), xp(100))));
        addDay(days, 2,
                List.of(main("d02_burning_door", Scope.EACH_PLAYER,
                                count(TriggerType.VISIT_BIOMES, "#minecraft:is_nether", 1),
                                text("Enter the Nether", "Betretet den Nether"), xp(300)),
                        main("d02_gold_rush", Scope.TEAM_TOTAL,
                                count(TriggerType.SMELT_ITEM, "minecraft:gold_ingot", 24),
                                text("Smelt 24 gold ingots as a team", "Schmelzt als Team 24 Goldbarren"), xp(300)),
                        main("d02_altar_1", Scope.TEAM_TOTAL, beat("altar_level_1"),
                                text("Raise the altar to level 1", "Erhebt den Altar auf Stufe 1"),
                                reward(350, 1))),
                List.of(side("d02_pest_control", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "any_hostile", 10),
                                text("Slay 10 hostile mobs", "Erlegt 10 feindliche Monster"), xp(120)),
                        side("d02_prospector", Scope.EACH_PLAYER,
                                count(TriggerType.MINE_BLOCK, "#minecraft:iron_ores", 12),
                                text("Mine 12 iron ore blocks", "Baut 12 Eisenerzblöcke ab"), xp(120)),
                        side("d02_mason", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 64),
                                text("Place 64 blocks", "Setzt 64 Blöcke"), xp(100))));
        addDay(days, 3,
                List.of(main("d03_iron_pickaxes", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:iron_pickaxe", 1),
                                text("Everyone forges an iron pickaxe",
                                        "Jeder schmiedet eine Eisenspitzhacke"), xp(300)),
                        main("d03_iron_axes", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:iron_axe", 1),
                                text("Everyone forges an iron axe",
                                        "Jeder schmiedet eine Eisenaxt"), xp(300)),
                        main("d03_iron_swords", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:iron_sword", 1),
                                text("Everyone forges an iron sword",
                                        "Jeder schmiedet ein Eisenschwert"), reward(350, 1))),
                List.of(side("d03_rancher", Scope.EACH_PLAYER, count(TriggerType.BREED_ANIMALS, "", 4),
                                text("Breed 4 animals", "Züchtet 4 Tiere"), xp(120)),
                        side("d03_devout", Scope.TEAM_TOTAL, deposit("", "MILESTONE", 8),
                                text("Feed 8 items into the altar milestone", "Speist 8 Gegenstände in den Altar-Meilenstein"), xp(120)),
                        side("d03_delver", Scope.EACH_PLAYER, depth(-32),
                                text("Descend below Y -32", "Steigt unter Y -32 hinab"), xp(100)),
                        side("d03_toolsmith", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:iron_pickaxe", 1),
                                text("Craft an iron pickaxe", "Fertigt eine Eisenspitzhacke"), xp(100))));
        addDay(days, 4,
                List.of(main("d04_feast", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:bread", 24),
                                text("Bake 24 loaves for the settlement",
                                        "Backt 24 Brote für die Siedlung"), xp(300)),
                        main("d04_husbandry", Scope.TEAM_TOTAL, count(TriggerType.BREED_ANIMALS, "", 12),
                                text("Breed 12 animals for the pantry", "Züchtet 12 Tiere für die Vorratskammer"), xp(300)),
                        main("d04_iron_wall", Scope.EACH_PLAYER,
                                count(TriggerType.CRAFT_ITEM, "minecraft:iron_chestplate", 1),
                                text("Everyone forges an iron chestplate",
                                        "Jeder schmiedet einen Eisenharnisch"), reward(350, 1))),
                List.of(side("d04_smelter", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 32),
                                text("Smelt 32 items", "Schmelzt 32 Gegenstände"), xp(120)),
                        side("d04_wander", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 2000),
                                text("Travel 2000 meters", "Legt 2000 Meter zurück"), xp(100)),
                        side("d04_leap", Scope.EACH_PLAYER,
                                stat("minecraft:custom/minecraft:jump", 500),
                                text("Jump 500 times", "Springt 500 Mal"), xp(100))));
        addDay(days, 5,
                List.of(main("d05_skyward", Scope.TEAM_TOTAL,
                                count(TriggerType.EXPLORE_CHUNKS, "", 160),
                                text("Chart 160 new chunks as a team",
                                        "Kartiert als Team 160 neue Chunks"), xp(350)),
                        main("d05_iron_stock", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:iron_ingot", 96),
                                text("Stockpile 96 iron ingots as a team", "Hortet als Team 96 Eisenbarren"), xp(300)),
                        main("d05_tinker", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:piston", 16),
                                text("Craft 16 pistons for the workshops",
                                        "Fertigt 16 Kolben für die Werkstätten"), reward(350, 1))),
                List.of(side("d05_charter", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 40),
                                text("Explore 40 new chunks", "Erkundet 40 neue Chunks"), xp(120)),
                        side("d05_amethyst", Scope.EACH_PLAYER,
                                count(TriggerType.COLLECT_ITEM, "minecraft:amethyst_shard", 4),
                                text("Collect 4 amethyst shards", "Sammelt 4 Amethystscherben"), xp(100)),
                        side("d05_hisser", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:creeper", 3),
                                text("Defuse 3 creepers", "Entschärft 3 Creeper"), xp(120))));
        addDay(days, 6,
                List.of(main("d06_fortress", Scope.TEAM_TOTAL,
                                count(TriggerType.MINE_BLOCK, "minecraft:nether_bricks", 48),
                                text("Break 48 bricks from a Nether fortress",
                                        "Brecht 48 Netherziegel aus einer Netherfestung"), xp(350)),
                        main("d06_blaze_hoard", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:blaze_rod", 12),
                                text("Collect 12 blaze rods as a team", "Sammelt als Team 12 Lohenruten"), xp(350)),
                        main("d06_lure", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "eclipse:heralds_lure", 1),
                                text("Craft the Herald's Lure", "Fertigt den Köder des Herolds"),
                                reward(400, 1))),
                List.of(side("d06_blaze_slayer", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:blaze", 5),
                                text("Slay 5 blazes", "Erlegt 5 Lohen"), xp(140)),
                        side("d06_night_nerves", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(150)),
                        side("d06_far_afield", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 3000),
                                text("Travel 3000 meters", "Legt 3000 Meter zurück"), xp(100))));
        addDay(days, 7,
                List.of(main("d07_summon", Scope.TEAM_TOTAL, beat("herald_summoned"),
                                text("Summon the Herald at dusk", "Beschwört den Herold in der Dämmerung"), xp(300)),
                        main("d07_slay", Scope.TEAM_TOTAL, beat("herald_defeated"),
                                text("Defeat the Herald", "Bezwingt den Herold"), new Reward(400, 2, List.of())),
                        main("d07_core", Scope.TEAM_TOTAL, deposit("eclipse:herald_core", "MILESTONE", 1),
                                text("Deposit the Herald Core at the altar", "Legt den Heroldskern am Altar nieder"), xp(350))),
                List.of(side("d07_stand", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 15),
                                text("Slay 15 hostile mobs", "Erlegt 15 feindliche Monster"), xp(140)),
                        side("d07_rampart", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 128),
                                text("Place 128 blocks", "Setzt 128 Blöcke"), xp(120)),
                        side("d07_watchful", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 20),
                                text("Explore 20 new chunks", "Erkundet 20 neue Chunks"), xp(100))));
        addDay(days, 8,
                List.of(main("d08_hoard", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:ender_chest", 4),
                                text("Craft 4 ender chests for the team",
                                        "Fertigt 4 Endertruhen für das Team"), xp(300)),
                        main("d08_pearls", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_pearl", 24),
                                text("Collect 24 ender pearls as a team", "Sammelt als Team 24 Enderperlen"), xp(350)),
                        main("d08_altar_4", Scope.TEAM_TOTAL, beat("altar_level_4"),
                                text("Raise the altar to level 4", "Erhebt den Altar auf Stufe 4"),
                                reward(450, 2))),
                List.of(side("d08_endermen", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:enderman", 3),
                                text("Slay 3 endermen", "Erlegt 3 Endermen"), xp(140)),
                        side("d08_banker", Scope.TEAM_TOTAL, deposit("", "SHARD_BANK", 8),
                                text("Bank 8 umbral shards", "Zahlt 8 Umbralsplitter ein"), xp(120)),
                        side("d08_deep", Scope.EACH_PLAYER, depth(-64),
                                text("Descend below Y -64", "Steigt unter Y -64 hinab"), xp(120))));
        addDay(days, 9,
                List.of(main("d09_alchemy", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:potion", 8),
                                text("Prepare 8 potions for the team",
                                        "Bereitet 8 Tränke für das Team vor"), xp(350)),
                        main("d09_voltage", Scope.TEAM_TOTAL,
                                count(TriggerType.CRAFT_ITEM, "minecraft:repeater", 16),
                                text("Craft 16 redstone repeaters",
                                        "Fertigt 16 Redstone-Verstärker"), xp(350)),
                        main("d09_pool", Scope.TEAM_TOTAL, beat("shard_pool_32"),
                                text("Pool 32 umbral shards", "Sammelt 32 Umbralsplitter im Gemeinschaftspool"),
                                reward(400, 1))),
                List.of(side("d09_furnace", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 24),
                                text("Smelt 24 items", "Schmelzt 24 Gegenstände"), xp(120)),
                        side("d09_biomes", Scope.EACH_PLAYER, count(TriggerType.VISIT_BIOMES, "", 3),
                                text("Visit 3 different biomes", "Besucht 3 verschiedene Biome"), xp(120)),
                        side("d09_cull", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 12),
                                text("Slay 12 hostile mobs", "Erlegt 12 feindliche Monster"), xp(120))));
        addDay(days, 10,
                List.of(main("d10_template", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:netherite_upgrade_smithing_template", 1),
                                text("Find a smithing template", "Findet eine Schmiedevorlage"), xp(350)),
                        main("d10_debris", Scope.TEAM_TOTAL,
                                count(TriggerType.MINE_BLOCK, "minecraft:ancient_debris", 12),
                                text("Mine 12 ancient debris", "Baut 12 antiken Schrott ab"), xp(400)),
                        main("d10_bastion", Scope.TEAM_TOTAL, count(TriggerType.PLACE_BLOCKS, "", 256),
                                text("Fortify your base — place 256 blocks", "Befestigt eure Basis — setzt 256 Blöcke"), xp(250))),
                List.of(side("d10_wither", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:wither_skeleton", 3),
                                text("Slay 3 wither skeletons", "Erlegt 3 Witherskelette"), xp(150)),
                        side("d10_smelt", Scope.EACH_PLAYER, count(TriggerType.SMELT_ITEM, "", 32),
                                text("Smelt 32 items", "Schmelzt 32 Gegenstände"), xp(120)),
                        side("d10_trek", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 4000),
                                text("Travel 4000 meters", "Legt 4000 Meter zurück"), xp(100))));
        addDay(days, 11,
                List.of(main("d11_hearts", Scope.TEAM_ALL, beat("all_hearts_4"),
                                text("Everyone reaches 4+ hearts", "Jeder erreicht 4+ Herzen"), xp(400)),
                        main("d11_revive", Scope.TEAM_TOTAL, beat("player_revived"),
                                text("Revive a banned player", "Erweckt einen gebannten Spieler wieder"),
                                reward(450, 2)),
                        main("d11_end_kit", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_eye", 12),
                                text("Assemble 12 eyes of ender", "Stellt 12 Enderaugen zusammen"),
                                reward(350, 1))),
                List.of(side("d11_shepherd", Scope.EACH_PLAYER, count(TriggerType.BREED_ANIMALS, "", 6),
                                text("Breed 6 animals", "Züchtet 6 Tiere"), xp(120)),
                        side("d11_iron_nerves", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(150)),
                        side("d11_tithe", Scope.TEAM_TOTAL, deposit("", "", 16),
                                text("Deposit 16 items at the altar", "Legt 16 Gegenstände am Altar nieder"), xp(120))));
        addDay(days, 12,
                List.of(main("d12_stronghold", Scope.TEAM_TOTAL, location(0, -400, 48),
                                text("Locate the stronghold at the southern rim",
                                        "Ortet die Festung am südlichen Rand"), reward(350, 1)),
                        main("d12_breach", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_eye", 16),
                                text("Bring 16 eyes of ender to the breach",
                                        "Bringt 16 Enderaugen zum Durchbruch"), xp(350)),
                        main("d12_purge", Scope.TEAM_TOTAL,
                                count(TriggerType.KILL_ENTITY, "minecraft:silverfish", 16),
                                text("Purge 16 silverfish from the stronghold",
                                        "Säubert die Festung von 16 Silberfischchen"), xp(300))),
                List.of(side("d12_charter", Scope.EACH_PLAYER, count(TriggerType.EXPLORE_CHUNKS, "", 40),
                                text("Explore 40 new chunks", "Erkundet 40 neue Chunks"), xp(120)),
                        side("d12_ender", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "minecraft:enderman", 5),
                                text("Slay 5 endermen", "Erlegt 5 Endermen"), xp(140)),
                        side("d12_mason", Scope.EACH_PLAYER, count(TriggerType.PLACE_BLOCKS, "", 128),
                                text("Place 128 blocks", "Setzt 128 Blöcke"), xp(100))));
        addDay(days, 13,
                List.of(main("d13_dragon", Scope.TEAM_TOTAL, beat("dragon_defeated"),
                                text("Defeat the Ender Dragon", "Bezwingt den Enderdrachen"),
                                new Reward(500, 2, List.of())),
                        main("d13_egg", Scope.TEAM_TOTAL,
                                count(TriggerType.COLLECT_ITEM, "minecraft:dragon_egg", 1),
                                text("Claim the dragon egg", "Beansprucht das Drachenei"),
                                reward(450, 1)),
                        main("d13_home", Scope.TEAM_ALL, location(0, 0, 48),
                                text("All survivors return home", "Alle Überlebenden kehren heim"), xp(300))),
                List.of(side("d13_hostiles", Scope.EACH_PLAYER, count(TriggerType.KILL_ENTITY, "any_hostile", 24),
                                text("Slay 24 hostile mobs", "Erlegt 24 feindliche Monster"), xp(160)),
                        side("d13_pearls", Scope.EACH_PLAYER,
                                count(TriggerType.COLLECT_ITEM, "minecraft:ender_pearl", 8),
                                text("Collect 8 ender pearls", "Sammelt 8 Enderperlen"), xp(120)),
                        side("d13_watch", Scope.EACH_PLAYER,
                                count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), xp(150))));
        addDay(days, 14,
                List.of(main("d14_offer", Scope.TEAM_TOTAL, beat("finale_begun"),
                                text("Offer the egg at dusk", "Opfert das Ei in der Dämmerung"), xp(300)),
                        main("d14_crossing", Scope.TEAM_TOTAL, beat("crossing_survived"),
                                text("Survive the crossing", "Überlebt die Überfahrt"), xp(450)),
                        main("d14_ferryman", Scope.TEAM_TOTAL, beat("ferryman_defeated"),
                                text("Defeat the Ferryman before the ship sinks",
                                        "Bezwingt den Fährmann, bevor das Schiff sinkt"),
                                reward(650, 4))),
                List.of(side("d14_last_stand", Scope.EACH_PLAYER,
                                count(TriggerType.KILL_ENTITY, "any_hostile", 25),
                                text("Slay 25 hostile mobs", "Erlegt 25 feindliche Monster"), xp(150)),
                        side("d14_tribute", Scope.TEAM_TOTAL, deposit("", "", 24),
                                text("Deposit 24 items at the altar", "Legt 24 Gegenstände am Altar nieder"), xp(120)),
                        side("d14_sprint", Scope.EACH_PLAYER, count(TriggerType.TRAVEL_DISTANCE, "", 2000),
                                text("Travel 2000 meters", "Legt 2000 Meter zurück"), xp(100))));
        root.add("days", days);
        return root;
    }

    static JsonElement defaultQuestsJson() {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", questsComment());
        root.addProperty("personalPerDay", 3);
        JsonArray quests = new JsonArray();
        for (GoalSpec spec : defaultPersonalPool()) {
            quests.add(spec.toJson());
        }
        root.add("quests", quests);
        return root;
    }

    private static List<GoalSpec> defaultPersonalPool() {
        List<GoalSpec> pool = new ArrayList<>();
        pool.add(personal("p_explorer", count(TriggerType.EXPLORE_CHUNKS, "", 40),
                text("Explore 40 new chunks", "Erkundet 40 neue Chunks"), 3, 0, 0, xp(150)));
        pool.add(personal("p_hunter", count(TriggerType.KILL_ENTITY, "any_hostile", 15),
                text("Slay 15 hostile mobs", "Erlegt 15 feindliche Monster"), 3, 0, 0, xp(150)));
        pool.add(personal("p_wanderer", count(TriggerType.TRAVEL_DISTANCE, "", 3000),
                text("Travel 3000 meters", "Legt 3000 Meter zurück"), 3, 0, 0, xp(150)));
        pool.add(personal("p_torchbearer", count(TriggerType.CRAFT_ITEM, "minecraft:torch", 64),
                text("Craft 64 torches", "Fertigt 64 Fackeln"), 3, 0, 0, xp(120)));
        pool.add(personal("p_coal_seam", count(TriggerType.MINE_BLOCK, "#minecraft:coal_ores", 24),
                text("Mine 24 coal ore blocks", "Baut 24 Kohleerzblöcke ab"), 3, 0, 0, xp(130)));
        pool.add(personal("p_iron_vein", count(TriggerType.MINE_BLOCK, "#minecraft:iron_ores", 16),
                text("Mine 16 iron ore blocks", "Baut 16 Eisenerzblöcke ab"), 3, 0, 0, xp(140)));
        pool.add(personal("p_gold_seam", count(TriggerType.MINE_BLOCK, "#minecraft:gold_ores", 8),
                text("Mine 8 gold ore blocks", "Baut 8 Golderzblöcke ab"), 2, 2, 0, xp(150)));
        pool.add(personal("p_diamond_gleam", count(TriggerType.MINE_BLOCK, "#minecraft:diamond_ores", 3),
                text("Mine 3 diamond ore blocks", "Baut 3 Diamanterzblöcke ab"), 1, 3, 0,
                new Reward(200, 1, List.of())));
        pool.add(personal("p_deep_delver", depth(-48),
                text("Descend below Y -48", "Steigt unter Y -48 hinab"), 2, 0, 0, xp(120)));
        pool.add(personal("p_biome_taster", count(TriggerType.VISIT_BIOMES, "", 3),
                text("Visit 3 different biomes", "Besucht 3 verschiedene Biome"), 3, 0, 0, xp(130)));
        pool.add(personal("p_breeder", count(TriggerType.BREED_ANIMALS, "", 4),
                text("Breed 4 animals", "Züchtet 4 Tiere"), 2, 2, 0, xp(130)));
        pool.add(personal("p_stoker", count(TriggerType.SMELT_ITEM, "", 24),
                text("Smelt 24 items", "Schmelzt 24 Gegenstände"), 3, 0, 0, xp(120)));
        pool.add(personal("p_builder", count(TriggerType.PLACE_BLOCKS, "", 128),
                text("Place 128 blocks", "Setzt 128 Blöcke"), 3, 0, 0, xp(120)));
        pool.add(personal("p_devout", deposit("", "", 8),
                text("Deposit 8 items at the altar", "Legt 8 Gegenstände am Altar nieder"), 2, 2, 0,
                new Reward(150, 1, List.of())));
        pool.add(personal("p_night_owl", count(TriggerType.SURVIVE_NIGHT_NO_DAMAGE, "", 1),
                text("Survive a night without damage", "Übersteht eine Nacht ohne Schaden"), 2, 0, 0, xp(180)));
        pool.add(personal("p_leaper", stat("minecraft:custom/minecraft:jump", 500),
                text("Jump 500 times", "Springt 500 Mal"), 2, 0, 0, xp(100)));
        pool.add(personal("p_swimmer", stat("minecraft:custom/minecraft:swim_one_cm", 20000),
                text("Swim 200 meters", "Schwimmt 200 Meter"), 1, 0, 0, xp(110)));
        pool.add(personal("p_climber", stat("minecraft:custom/minecraft:climb_one_cm", 5000),
                text("Climb 50 meters", "Klettert 50 Meter"), 1, 0, 0, xp(100)));
        pool.add(personal("p_defuser", count(TriggerType.KILL_ENTITY, "minecraft:creeper", 5),
                text("Defuse 5 creepers", "Entschärft 5 Creeper"), 2, 0, 0, xp(150)));
        pool.add(personal("p_angler", stat("minecraft:custom/minecraft:fish_caught", 5),
                text("Catch 5 fish", "Fangt 5 Fische"), 1, 0, 0, xp(130)));
        pool.add(personal("p_lumberjack", count(TriggerType.MINE_BLOCK, "#minecraft:logs", 64),
                text("Fell 64 logs", "Fällt 64 Stämme"), 2, 1, 6, xp(140)));
        pool.add(personal("p_stoneworker", count(TriggerType.MINE_BLOCK, "minecraft:deepslate", 128),
                text("Mine 128 deepslate", "Baut 128 Tiefenschiefer ab"), 2, 2, 0, xp(140)));
        pool.add(personal("p_redstone_hand", count(TriggerType.CRAFT_ITEM, "minecraft:repeater", 8),
                text("Craft 8 redstone repeaters", "Fertigt 8 Redstone-Verstärker"), 2, 3, 0, xp(150)));
        pool.add(personal("p_blaze_hunter", count(TriggerType.KILL_ENTITY, "minecraft:blaze", 8),
                text("Slay 8 blazes", "Erlegt 8 Lohen"), 1, 6, 11, reward(190, 1)));
        pool.add(personal("p_ender_hunter", count(TriggerType.KILL_ENTITY, "minecraft:enderman", 6),
                text("Slay 6 endermen", "Erlegt 6 Endermen"), 2, 6, 0, xp(180)));
        pool.add(personal("p_alchemist", count(TriggerType.COLLECT_ITEM, "minecraft:potion", 4),
                text("Prepare 4 potions", "Bereitet 4 Tränke vor"), 2, 6, 0, xp(150)));
        pool.add(personal("p_adept", count(TriggerType.SKILL_LEVEL, "", 10),
                text("Reach skill level 10", "Erreicht Skill-Level 10"), 1, 3, 0, reward(220, 1)));
        pool.add(personal("p_unique_offering", deposit("", "OFFERING", 1),
                text("Make today's altar offering", "Bringt das heutige Altaropfer dar"),
                2, 2, 0, reward(140, 1)));
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

    private static GoalSpec personal(String id, Trigger trigger, Localized text, int weight,
            int minDay, int maxDay, Reward reward) {
        return new GoalSpec(id, Kind.PERSONAL, Scope.EACH_PLAYER, trigger, reward, text, weight, minDay, maxDay);
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
