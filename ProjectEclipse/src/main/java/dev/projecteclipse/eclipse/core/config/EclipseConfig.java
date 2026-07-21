package dev.projecteclipse.eclipse.core.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads the five Eclipse config files from {@code <config>/eclipse/}:
 * {@code general.json}, {@code days.json}, {@code milestones.json}, {@code modgate.json}
 * and {@code anticheat.json}. Missing files are created with sensible defaults on first
 * run. Parse or IO failures are logged and the built-in defaults are used in memory instead.
 */
public final class EclipseConfig {
    /**
     * General tunables: grave grace period in minutes (non-owners may loot after 1x, graves scatter
     * after 3x), and the day auto-advance switch. {@code dayAutoAdvance} defaults to {@code false}
     * (days only change via the admin command / {@code DayScheduler.setDay}); when enabled, the day
     * advances once per real-world day at {@code dayAutoAdvanceTime} ({@code HH:mm}, server-local time).
     */
    public record General(int graveGraceMinutes, boolean dayAutoAdvance, String dayAutoAdvanceTime) {}

    /** Per-day plan: three goals, progression unlock keys, and the world border size for that day. */
    public record DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize) {}

    /** A single item cost entry, e.g. {@code minecraft:diamond} x 8. */
    public record ItemCost(String item, int count) {}

    /** Altar milestone: paying {@code cost} at the altar grants the {@code rewards} unlock keys. */
    public record Milestone(int level, List<ItemCost> cost, List<String> rewards) {}

    /** Mod gating: namespaces whose content is locked until the mapped unlock key is granted. */
    public record ModGate(List<String> gatedNamespaces, Map<String, String> unlockKeys) {}

    /** Anti-cheat: mod-id substrings that are rejected on clients ({@code anticheat.json}). */
    public record AntiCheat(List<String> blockedModIdSubstrings) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    private static volatile General general = defaultGeneral();
    private static volatile List<DayPlan> days = List.of();
    private static volatile List<Milestone> milestones = List.of();
    private static volatile ModGate modGate = defaultModGate();
    private static volatile AntiCheat antiCheat = defaultAntiCheat();
    private static volatile boolean loaded = false;

    private EclipseConfig() {}

    /** The general configuration section ({@code general.json}). */
    public static General general() {
        ensureLoaded();
        return general;
    }

    /** Grave grace period in minutes (default 30). Non-owners may loot after 1x; the grave scatters after 3x. */
    public static int graveGraceMinutes() {
        return general().graveGraceMinutes();
    }

    /** Whether the event day auto-advances once per real-world day (default {@code false}: manual only). */
    public static boolean dayAutoAdvance() {
        return general().dayAutoAdvance();
    }

    /** The server-local time of day at which the day auto-advances; unparseable values fall back to 08:00. */
    public static java.time.LocalTime dayAutoAdvanceTime() {
        try {
            return java.time.LocalTime.parse(general().dayAutoAdvanceTime());
        } catch (java.time.format.DateTimeParseException e) {
            EclipseMod.LOGGER.warn("Invalid dayAutoAdvanceTime '{}' in general.json; using 08:00",
                    general().dayAutoAdvanceTime());
            return java.time.LocalTime.of(8, 0);
        }
    }

    /** All 14 day plans, ordered by day. */
    public static List<DayPlan> days() {
        ensureLoaded();
        return days;
    }

    /** The plan for the given day; days outside the configured range are clamped to the first/last plan. */
    public static DayPlan day(int day) {
        ensureLoaded();
        List<DayPlan> plans = days;
        DayPlan fallback = plans.get(plans.size() - 1);
        for (DayPlan plan : plans) {
            if (plan.day() == day) {
                return plan;
            }
        }
        return day < plans.get(0).day() ? plans.get(0) : fallback;
    }

    /** All altar milestones, ordered by level. */
    public static List<Milestone> milestones() {
        ensureLoaded();
        return milestones;
    }

    /** The milestone for the given altar level, or {@code null} if none is configured. */
    public static Milestone milestone(int level) {
        ensureLoaded();
        for (Milestone milestone : milestones) {
            if (milestone.level() == level) {
                return milestone;
            }
        }
        return null;
    }

    /** The mod gating configuration. */
    public static ModGate modGate() {
        ensureLoaded();
        return modGate;
    }

    /** The anti-cheat configuration ({@code anticheat.json}). */
    public static AntiCheat antiCheat() {
        ensureLoaded();
        return antiCheat;
    }

    /**
     * Adds ({@code gated=true}) or removes ({@code gated=false}) a namespace from the gated
     * list and persists {@code modgate.json}. When adding, the unlock key defaults to the
     * namespace itself unless one is already mapped. Returns whether anything changed.
     * Backs the {@code /eclipse modgate lock|unlock} admin command.
     */
    public static synchronized boolean setNamespaceGated(String namespace, boolean gated) {
        ensureLoaded();
        List<String> namespaces = new ArrayList<>(modGate.gatedNamespaces());
        boolean changed = gated
                ? !namespaces.contains(namespace) && namespaces.add(namespace)
                : namespaces.remove(namespace);
        if (!changed) {
            return false;
        }
        Map<String, String> unlockKeys = new LinkedHashMap<>(modGate.unlockKeys());
        if (gated) {
            unlockKeys.putIfAbsent(namespace, namespace);
        }
        modGate = new ModGate(List.copyOf(namespaces), Collections.unmodifiableMap(unlockKeys));
        Path file = FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("modgate.json");
        try {
            Files.writeString(file, GSON.toJson(modGateToJson(modGate)), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("Persisted modgate.json: namespace '{}' is now {}", namespace,
                    gated ? "gated" : "ungated");
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to persist {}; the change applies in memory only", file, e);
        }
        return true;
    }

    /** Re-reads all five config files from disk, creating any missing ones with defaults. */
    public static synchronized void reload() {
        Path dir = FMLPaths.CONFIGDIR.get().resolve("eclipse");
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }

        general = loadOrCreate(dir.resolve("general.json"),
                EclipseConfig::defaultGeneral, EclipseConfig::generalToJson, EclipseConfig::generalFromJson);
        days = List.copyOf(loadOrCreate(dir.resolve("days.json"),
                EclipseConfig::defaultDays, EclipseConfig::daysToJson, EclipseConfig::daysFromJson));
        milestones = List.copyOf(loadOrCreate(dir.resolve("milestones.json"),
                EclipseConfig::defaultMilestones, EclipseConfig::milestonesToJson, EclipseConfig::milestonesFromJson));
        modGate = loadOrCreate(dir.resolve("modgate.json"),
                EclipseConfig::defaultModGate, EclipseConfig::modGateToJson, EclipseConfig::modGateFromJson);
        antiCheat = loadOrCreate(dir.resolve("anticheat.json"),
                EclipseConfig::defaultAntiCheat, EclipseConfig::antiCheatToJson, EclipseConfig::antiCheatFromJson);
        loaded = true;
        EclipseMod.LOGGER.info("Eclipse config loaded: {} days, {} milestones, {} gated namespaces, "
                        + "{} anti-cheat entries, grave grace {} min",
                days.size(), milestones.size(), modGate.gatedNamespaces().size(),
                antiCheat.blockedModIdSubstrings().size(), general.graveGraceMinutes());
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reload();
        }
    }

    private interface JsonReader<T> {
        T fromJson(JsonElement json);
    }

    private interface JsonWriter<T> {
        JsonElement toJson(T value);
    }

    private static <T> T loadOrCreate(Path file, java.util.function.Supplier<T> defaults, JsonWriter<T> writer, JsonReader<T> reader) {
        if (!Files.exists(file)) {
            T value = defaults.get();
            try {
                Files.writeString(file, GSON.toJson(writer.toJson(value)), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
            return value;
        }
        try {
            return reader.fromJson(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
            return defaults.get();
        }
    }

    // --- general.json ---

    private static General defaultGeneral() {
        return new General(30, false, "08:00");
    }

    private static JsonElement generalToJson(General general) {
        JsonObject obj = new JsonObject();
        obj.addProperty("graveGraceMinutes", general.graveGraceMinutes());
        obj.addProperty("dayAutoAdvance", general.dayAutoAdvance());
        obj.addProperty("dayAutoAdvanceTime", general.dayAutoAdvanceTime());
        return obj;
    }

    private static General generalFromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        int graveGraceMinutes = obj.has("graveGraceMinutes") ? obj.get("graveGraceMinutes").getAsInt() : 30;
        boolean dayAutoAdvance = obj.has("dayAutoAdvance") && obj.get("dayAutoAdvance").getAsBoolean();
        String dayAutoAdvanceTime = obj.has("dayAutoAdvanceTime") ? obj.get("dayAutoAdvanceTime").getAsString() : "08:00";
        return new General(Math.max(0, graveGraceMinutes), dayAutoAdvance, dayAutoAdvanceTime);
    }

    // --- days.json ---

    private static List<DayPlan> defaultDays() {
        List<DayPlan> plans = new ArrayList<>(14);
        plans.add(new DayPlan(1, List.of("Survive the first night", "Gather basic resources", "Build a shelter near spawn"), List.of(), 1000.0D));
        plans.add(new DayPlan(2, List.of("Unlock your main inventory", "Collect 32 logs", "Craft a full set of stone tools"), List.of("main_inventory"), 1000.0D));
        plans.add(new DayPlan(3, List.of("Set up a crafting area", "Build your first Create contraption", "Scout the expanded border"), List.of("workbenches", "create"), 1500.0D));
        plans.add(new DayPlan(4, List.of("Craft a full set of armor", "Establish a reliable food farm", "Locate a village"), List.of("armor", "simulated"), 1500.0D));
        plans.add(new DayPlan(5, List.of("Take to the skies", "Smelt 16 iron ingots", "Expand your base"), List.of("aeronautics"), 2000.0D));
        plans.add(new DayPlan(6, List.of("Enter the Nether", "Find a nether fortress", "Collect 4 blaze rods"), List.of("nether"), 2000.0D));
        plans.add(new DayPlan(7, List.of("Build an enchanting setup", "Reach experience level 30", "Enchant a tool or weapon"), List.of("enchanting"), 2000.0D));
        plans.add(new DayPlan(8, List.of("Craft an ender chest", "Hunt endermen for pearls", "Stock your ender chest with valuables"), List.of("ender_chests"), 2500.0D));
        plans.add(new DayPlan(9, List.of("Brew your first potion", "Gather nether wart", "Brew a potion of strength"), List.of("brewing"), 2500.0D));
        plans.add(new DayPlan(10, List.of("Find a smithing template", "Upgrade a piece of gear to netherite", "Fortify your base"), List.of("smithing"), 2500.0D));
        plans.add(new DayPlan(11, List.of("Prepare supplies for the End", "Complete outstanding altar milestones", "Explore the final border expansion"), List.of(), 3000.0D));
        plans.add(new DayPlan(12, List.of("Locate the stronghold", "Open the end portal", "Enter the End"), List.of("end"), 3000.0D));
        plans.add(new DayPlan(13, List.of("Defeat the Ender Dragon", "Claim the dragon egg", "Return home safely"), List.of(), 3000.0D));
        plans.add(new DayPlan(14, List.of("Gather everyone for the finale", "Charge the altar one last time", "Face the Eclipse"), List.of(), 3000.0D));
        return plans;
    }

    private static JsonElement daysToJson(List<DayPlan> plans) {
        JsonArray array = new JsonArray(plans.size());
        for (DayPlan plan : plans) {
            JsonObject obj = new JsonObject();
            obj.addProperty("day", plan.day());
            obj.add("goals", stringArray(plan.goals()));
            obj.add("unlocks", stringArray(plan.unlocks()));
            obj.addProperty("borderSize", plan.borderSize());
            array.add(obj);
        }
        return array;
    }

    private static List<DayPlan> daysFromJson(JsonElement json) {
        List<DayPlan> plans = new ArrayList<>();
        for (JsonElement element : json.getAsJsonArray()) {
            JsonObject obj = element.getAsJsonObject();
            plans.add(new DayPlan(
                    obj.get("day").getAsInt(),
                    stringList(obj.getAsJsonArray("goals")),
                    stringList(obj.getAsJsonArray("unlocks")),
                    obj.get("borderSize").getAsDouble()));
        }
        if (plans.isEmpty()) {
            throw new IllegalStateException("days.json contains no day entries");
        }
        plans.sort(java.util.Comparator.comparingInt(DayPlan::day));
        return plans;
    }

    // --- milestones.json ---

    private static List<Milestone> defaultMilestones() {
        return List.of(
                new Milestone(1, List.of(new ItemCost("minecraft:iron_ingot", 16)), List.of("create")),
                new Milestone(2, List.of(new ItemCost("minecraft:gold_ingot", 16)), List.of("simulated")),
                new Milestone(3, List.of(new ItemCost("minecraft:diamond", 8)), List.of("aeronautics")),
                new Milestone(4, List.of(new ItemCost("minecraft:ender_pearl", 16)), List.of("sable")),
                new Milestone(5, List.of(new ItemCost("minecraft:netherite_ingot", 2)), List.of("end")));
    }

    private static JsonElement milestonesToJson(List<Milestone> milestones) {
        JsonArray array = new JsonArray(milestones.size());
        for (Milestone milestone : milestones) {
            JsonObject obj = new JsonObject();
            obj.addProperty("level", milestone.level());
            JsonArray cost = new JsonArray(milestone.cost().size());
            for (ItemCost itemCost : milestone.cost()) {
                JsonObject costObj = new JsonObject();
                costObj.addProperty("item", itemCost.item());
                costObj.addProperty("count", itemCost.count());
                cost.add(costObj);
            }
            obj.add("cost", cost);
            obj.add("rewards", stringArray(milestone.rewards()));
            array.add(obj);
        }
        return array;
    }

    private static List<Milestone> milestonesFromJson(JsonElement json) {
        List<Milestone> result = new ArrayList<>();
        for (JsonElement element : json.getAsJsonArray()) {
            JsonObject obj = element.getAsJsonObject();
            List<ItemCost> cost = new ArrayList<>();
            for (JsonElement costElement : obj.getAsJsonArray("cost")) {
                JsonObject costObj = costElement.getAsJsonObject();
                cost.add(new ItemCost(costObj.get("item").getAsString(), costObj.get("count").getAsInt()));
            }
            result.add(new Milestone(obj.get("level").getAsInt(), List.copyOf(cost), stringList(obj.getAsJsonArray("rewards"))));
        }
        result.sort(java.util.Comparator.comparingInt(Milestone::level));
        return result;
    }

    // --- modgate.json ---

    private static ModGate defaultModGate() {
        Map<String, String> unlockKeys = new LinkedHashMap<>();
        unlockKeys.put("create", "create");
        unlockKeys.put("simulated", "simulated");
        unlockKeys.put("aeronautics", "aeronautics");
        unlockKeys.put("sable", "sable");
        return new ModGate(List.of("create", "simulated", "aeronautics", "sable"), Collections.unmodifiableMap(unlockKeys));
    }

    private static JsonElement modGateToJson(ModGate modGate) {
        JsonObject obj = new JsonObject();
        obj.add("gatedNamespaces", stringArray(modGate.gatedNamespaces()));
        JsonObject unlockKeys = new JsonObject();
        for (Map.Entry<String, String> entry : modGate.unlockKeys().entrySet()) {
            unlockKeys.addProperty(entry.getKey(), entry.getValue());
        }
        obj.add("unlockKeys", unlockKeys);
        return obj;
    }

    private static ModGate modGateFromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        List<String> gatedNamespaces = stringList(obj.getAsJsonArray("gatedNamespaces"));
        Map<String, String> unlockKeys = new LinkedHashMap<>();
        for (Map.Entry<String, JsonElement> entry : obj.getAsJsonObject("unlockKeys").entrySet()) {
            unlockKeys.put(entry.getKey(), entry.getValue().getAsString());
        }
        return new ModGate(gatedNamespaces, Collections.unmodifiableMap(unlockKeys));
    }

    // --- anticheat.json ---

    private static AntiCheat defaultAntiCheat() {
        return new AntiCheat(List.of("xray", "advancedxray", "freecam", "freelook", "replaymod", "litematica"));
    }

    private static JsonElement antiCheatToJson(AntiCheat antiCheat) {
        JsonObject obj = new JsonObject();
        // JSON has no comments; this property documents the file in place.
        obj.addProperty("_comment", "Config-maintained anti-cheat blocklist: any loaded mod whose id "
                + "contains one of these substrings (case-insensitive) is rejected on clients. "
                + "Edit this list and run /eclipse reload to apply.");
        obj.add("blockedModIdSubstrings", stringArray(antiCheat.blockedModIdSubstrings()));
        return obj;
    }

    private static AntiCheat antiCheatFromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        return new AntiCheat(stringList(obj.getAsJsonArray("blockedModIdSubstrings")));
    }

    // --- helpers ---

    private static JsonArray stringArray(List<String> strings) {
        JsonArray array = new JsonArray(strings.size());
        strings.forEach(array::add);
        return array;
    }

    private static List<String> stringList(JsonArray array) {
        if (array == null) {
            return List.of();
        }
        List<String> result = new ArrayList<>(array.size());
        array.forEach(element -> result.add(element.getAsString()));
        return List.copyOf(result);
    }
}
