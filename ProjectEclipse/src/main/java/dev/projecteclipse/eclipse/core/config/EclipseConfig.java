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
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads the six Eclipse config files from {@code <config>/eclipse/}:
 * {@code general.json}, {@code days.json}, {@code milestones.json}, {@code modgate.json},
 * {@code anticheat.json} and {@code stages.json}. Missing files are created with sensible
 * defaults on first run. Parse or IO failures are logged and the built-in defaults are used
 * in memory instead.
 */
public final class EclipseConfig {
    /**
     * General tunables: grave grace period in minutes (non-owners may loot after 1x, graves scatter
     * after 3x), the day auto-advance switch, and the per-tick nanoTime budget (in ms) of the
     * runtime ring-growth terrain sweep. {@code dayAutoAdvance} defaults to {@code false}
     * (days only change via the admin command / {@code DayScheduler.setDay}); when enabled, the day
     * advances once per real-world day at {@code dayAutoAdvanceTime} ({@code HH:mm}, server-local time).
     * {@code cutscenesFreezeDuringUnlocks} (JSON: nested {@code "cutscenes":{"freezeDuringUnlocks"}},
     * default true) is the dev toggle for the freeze + {@code unlock_ring} cinematic during
     * animated ring-growth unlocks. {@code borderOffset} (default 12) is how far the W7 soft
     * border ring sits outside the committed stage radius; {@code borderFxRange} (default 8)
     * is the default client-FX visibility band in blocks (overridable per world via
     * {@code /eclipse border fx range}).
     */
    public record General(int graveGraceMinutes, boolean dayAutoAdvance, String dayAutoAdvanceTime,
            int ringBlocksBudgetMs, boolean cutscenesFreezeDuringUnlocks, int borderOffset,
            int borderFxRange) {}

    /**
     * One entry of a dimension's stage timeline ({@code stages.json}): the disc radius reached
     * at that stage, what triggers it ({@code "intro_fusion"}, {@code "milestone:N"},
     * {@code "day:N"} or {@code "final_day"}), the structure ids worker 5's stamper places when
     * the stage's terrain sweep completes, and an informational per-annulus ore budget (the
     * actual vein shaping lives in {@code DiscTerrainFunction}'s band factors).
     */
    public record StageEntry(int stage, int radius, String trigger, List<String> structures,
            Map<String, Integer> oreBudget) {}

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
    private static volatile Map<String, List<StageEntry>> stages = defaultStages();
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

    /** Per-tick nanoTime budget (ms) of the runtime ring-growth sweep (default 2, clamped >= 1). */
    public static int ringBlocksBudgetMs() {
        return Math.max(1, general().ringBlocksBudgetMs());
    }

    /** Whether animated ring-growth unlocks freeze players + play {@code unlock_ring} (default true). */
    public static boolean freezeDuringUnlocks() {
        return general().cutscenesFreezeDuringUnlocks();
    }

    /** Soft-border ring offset outside the committed stage radius, in blocks (default 12). */
    public static int borderOffset() {
        return general().borderOffset();
    }

    /** Default soft-border FX visibility band in blocks (default 8, clamped >= 1). */
    public static int borderFxRange() {
        return Math.max(1, general().borderFxRange());
    }

    /**
     * The stage timeline of the given disc dimension ({@code "overworld"} / {@code "nether"}),
     * ordered by stage, from {@code stages.json}. Stage 0 is implicit (pre-intro geometry) and
     * never listed.
     */
    public static List<StageEntry> stages(String dimensionName) {
        ensureLoaded();
        return stages.getOrDefault(dimensionName, List.of());
    }

    /** The {@code stages.json} entry for the given dimension and stage, or {@code null}. */
    public static StageEntry stage(String dimensionName, int stage) {
        for (StageEntry entry : stages(dimensionName)) {
            if (entry.stage() == stage) {
                return entry;
            }
        }
        return null;
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
        stages = loadOrCreate(dir.resolve("stages.json"),
                EclipseConfig::defaultStages, EclipseConfig::stagesToJson, EclipseConfig::stagesFromJson);
        applyStageRadii();
        loaded = true;
        EclipseMod.LOGGER.info("Eclipse config loaded: {} days, {} milestones, {} gated namespaces, "
                        + "{} anti-cheat entries, grave grace {} min, {} overworld + {} nether stages, "
                        + "ring budget {} ms",
                days.size(), milestones.size(), modGate.gatedNamespaces().size(),
                antiCheat.blockedModIdSubstrings().size(), general.graveGraceMinutes(),
                stages.getOrDefault("overworld", List.of()).size(),
                stages.getOrDefault("nether", List.of()).size(), general.ringBlocksBudgetMs());
    }

    /**
     * Publishes the configured stage radii into the {@link StageRadii} seam consumed by the
     * chunk generator and the ring-growth sweep. Index 0 keeps the built-in stage-0 value
     * (96 overworld main disc / 0 nether); indexes above the highest configured stage are
     * clamped by {@code StageRadii.radius}. Runs on every (re)load so {@code /eclipse reload}
     * applies radius edits immediately.
     */
    private static void applyStageRadii() {
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            List<StageEntry> entries = stages.getOrDefault(profile.name(), List.of());
            int maxStage = 0;
            for (StageEntry entry : entries) {
                maxStage = Math.max(maxStage, entry.stage());
            }
            int[] radii = new int[maxStage + 1];
            radii[0] = profile == DiscProfile.NETHER ? 0 : DiscGeometry.MAIN_DISC_RADIUS;
            int previous = radii[0];
            for (int stage = 1; stage <= maxStage; stage++) {
                StageEntry entry = null;
                for (StageEntry candidate : entries) {
                    if (candidate.stage() == stage) {
                        entry = candidate;
                        break;
                    }
                }
                previous = entry != null ? entry.radius() : previous;
                radii[stage] = previous;
            }
            StageRadii.set(profile, radii);
        }
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
        return new General(30, false, "08:00", 2, true, 12, 8);
    }

    private static JsonElement generalToJson(General general) {
        JsonObject obj = new JsonObject();
        obj.addProperty("graveGraceMinutes", general.graveGraceMinutes());
        obj.addProperty("dayAutoAdvance", general.dayAutoAdvance());
        obj.addProperty("dayAutoAdvanceTime", general.dayAutoAdvanceTime());
        obj.addProperty("ringBlocksBudgetMs", general.ringBlocksBudgetMs());
        obj.addProperty("borderOffset", general.borderOffset());
        obj.addProperty("borderFxRange", general.borderFxRange());
        JsonObject cutscenes = new JsonObject();
        cutscenes.addProperty("freezeDuringUnlocks", general.cutscenesFreezeDuringUnlocks());
        obj.add("cutscenes", cutscenes);
        return obj;
    }

    private static General generalFromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        int graveGraceMinutes = obj.has("graveGraceMinutes") ? obj.get("graveGraceMinutes").getAsInt() : 30;
        boolean dayAutoAdvance = obj.has("dayAutoAdvance") && obj.get("dayAutoAdvance").getAsBoolean();
        String dayAutoAdvanceTime = obj.has("dayAutoAdvanceTime") ? obj.get("dayAutoAdvanceTime").getAsString() : "08:00";
        int ringBlocksBudgetMs = obj.has("ringBlocksBudgetMs") ? obj.get("ringBlocksBudgetMs").getAsInt() : 2;
        // Pre-W6 general.json files have no "cutscenes" object — the toggle defaults to true.
        boolean freezeDuringUnlocks = !obj.has("cutscenes")
                || !obj.getAsJsonObject("cutscenes").has("freezeDuringUnlocks")
                || obj.getAsJsonObject("cutscenes").get("freezeDuringUnlocks").getAsBoolean();
        // Pre-W7 general.json files have no border fields — soft-border defaults apply.
        int borderOffset = obj.has("borderOffset") ? obj.get("borderOffset").getAsInt() : 12;
        int borderFxRange = obj.has("borderFxRange") ? obj.get("borderFxRange").getAsInt() : 8;
        return new General(Math.max(0, graveGraceMinutes), dayAutoAdvance, dayAutoAdvanceTime,
                Math.max(1, ringBlocksBudgetMs), freezeDuringUnlocks, Math.max(0, borderOffset),
                Math.max(1, borderFxRange));
    }

    // --- days.json ---

    /**
     * The v2 14-day arc (spec {@code docs/ideas/04_content.md} §6). Nether opens on day 2
     * ("The Burning Door"); day 7/14 are the boss days. Day 7's {@code enchanting} key is
     * SPECIAL: {@code progression.UnlockState} unions it only once the Herald has fallen.
     * {@code borderSize} is deprecated since W7 (soft border follows {@code stages.json})
     * but still written for backward compat.
     */
    private static List<DayPlan> defaultDays() {
        List<DayPlan> plans = new ArrayList<>(14);
        plans.add(new DayPlan(1, List.of("Survive the first night", "Bank 16 logs and a set of stone tools", "Everyone touches the altar"), List.of(), 1000.0D));
        plans.add(new DayPlan(2, List.of("Enter the Nether", "Smelt 8 gold ingots", "Raise the altar to level 1"), List.of("nether", "main_inventory"), 1000.0D));
        plans.add(new DayPlan(3, List.of("Build your first Create contraption", "Forge a full iron toolset", "Scout the new village ring"), List.of("workbenches", "create"), 1500.0D));
        plans.add(new DayPlan(4, List.of("Cook three Farmer's Delight meals", "Establish a reliable food farm", "Wear full iron armor"), List.of("armor", "farmersdelight", "simulated"), 1500.0D));
        plans.add(new DayPlan(5, List.of("Take to the skies", "Bank 24 iron ingots", "Rig something with Supplementaries"), List.of("aeronautics", "supplementaries"), 2000.0D));
        plans.add(new DayPlan(6, List.of("Find the nether fortress", "Collect 6 blaze rods", "Craft the Herald's Lure"), List.of(), 2000.0D));
        plans.add(new DayPlan(7, List.of("Summon the Herald at dusk", "Defeat the Herald", "Deposit the Herald Core at the altar"), List.of("enchanting"), 2000.0D));
        plans.add(new DayPlan(8, List.of("Fill a team ender chest", "Bank 16 ender pearls", "Raise the altar to level 4"), List.of("ender_chests", "sophisticatedbackpacks", "sable"), 2500.0D));
        plans.add(new DayPlan(9, List.of("Brew strength and fire resistance", "Electrify a Create machine", "Pool 24 umbral shards"), List.of("brewing", "createaddition"), 2500.0D));
        plans.add(new DayPlan(10, List.of("Find a smithing template", "Upgrade a tool to netherite", "Fortify your base"), List.of("smithing"), 2500.0D));
        plans.add(new DayPlan(11, List.of("Everyone reaches 4+ hearts", "Revive a banned player", "Assemble an End raid kit"), List.of(), 3000.0D));
        plans.add(new DayPlan(12, List.of("Locate the stronghold", "Breach the portal room", "Hold the portal room overnight"), List.of("end"), 3000.0D));
        plans.add(new DayPlan(13, List.of("Defeat the Ender Dragon", "Claim the dragon egg", "All survivors return home"), List.of(), 3000.0D));
        plans.add(new DayPlan(14, List.of("Offer the egg at dusk", "Survive the crossing", "Defeat the Ferryman before the ship sinks"), List.of(), 3000.0D));
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

    /**
     * The v2 milestone costs (spec §6): L4 is the boss lock — it demands the Herald Core
     * (day-7 guaranteed drop) on top of the pearls, so the altar cannot out-pace the arc.
     */
    private static List<Milestone> defaultMilestones() {
        return List.of(
                new Milestone(1, List.of(new ItemCost("minecraft:iron_ingot", 16)), List.of("create")),
                new Milestone(2, List.of(new ItemCost("minecraft:gold_ingot", 16)), List.of("simulated")),
                new Milestone(3, List.of(new ItemCost("minecraft:diamond", 8)), List.of("aeronautics")),
                new Milestone(4, List.of(new ItemCost("eclipse:herald_core", 1), new ItemCost("minecraft:ender_pearl", 16)), List.of("sable")),
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

    /**
     * v2 gated namespaces (spec §5): the four v1 mods plus Farmer's Delight (day 4),
     * Supplementaries (day 5), Sophisticated Backpacks (day 8) and Create: Crafts &
     * Additions (day 9). The Aeronautics bundle additionally ships Create: Offroad
     * (namespace {@code offroad}) — gated with the {@code aeronautics} key so the whole
     * suite unlocks together. Their LIBRARIES ({@code sophisticatedcore}, {@code moonlight})
     * are deliberately NOT gated — gating a library would brick its dependents entirely.
     */
    private static ModGate defaultModGate() {
        List<String> namespaces = List.of("create", "simulated", "aeronautics", "sable",
                "farmersdelight", "supplementaries", "sophisticatedbackpacks", "createaddition",
                "offroad");
        Map<String, String> unlockKeys = new LinkedHashMap<>();
        for (String namespace : namespaces) {
            unlockKeys.put(namespace, namespace);
        }
        unlockKeys.put("offroad", "aeronautics");
        return new ModGate(namespaces, Collections.unmodifiableMap(unlockKeys));
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

    // --- stages.json ---

    /**
     * Defaults from {@code docs/ideas/01_world_terrain.md} §C/§D: overworld stages 1..5
     * (r 225/300/360/420/480; intro fusion, altar milestones 2..4, final day) and nether
     * stages 1..3 (r 80/120/160 on days 2/10/12). Structure ids match the
     * {@code disc_map.json} landmark list worker 5 stamps from.
     */
    private static Map<String, List<StageEntry>> defaultStages() {
        Map<String, List<StageEntry>> defaults = new LinkedHashMap<>();
        defaults.put("overworld", List.of(
                new StageEntry(1, 225, "intro_fusion", List.of(), Map.of()),
                new StageEntry(2, 300, "milestone:2", List.of("eclipse:desert_temple"),
                        Map.of("iron", 400, "gold", 90, "diamond", 40)),
                new StageEntry(3, 360, "milestone:3", List.of("eclipse:jungle_temple"),
                        Map.of("iron", 300, "gold", 80, "diamond", 25)),
                new StageEntry(4, 420, "milestone:4", List.of("eclipse:village_plains"),
                        Map.of("iron", 250, "gold", 70, "diamond", 15)),
                new StageEntry(5, 480, "final_day", List.of("eclipse:stronghold_emergence"),
                        Map.of("iron", 200, "gold", 60, "diamond", 10))));
        defaults.put("nether", List.of(
                new StageEntry(1, 80, "day:2", List.of("eclipse:fortress_core"),
                        Map.of("quartz", 300, "ancient_debris", 12)),
                new StageEntry(2, 120, "day:10", List.of(), Map.of("quartz", 200, "ancient_debris", 10)),
                new StageEntry(3, 160, "day:12", List.of(), Map.of("quartz", 150, "ancient_debris", 8))));
        return Collections.unmodifiableMap(defaults);
    }

    private static JsonElement stagesToJson(Map<String, List<StageEntry>> stages) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Per-dimension world stage timeline (separate from days.json). "
                + "radius = fused disc radius in blocks; trigger = intro_fusion | milestone:N (altar level) "
                + "| day:N | final_day; structures = ids stamped by the structure worker when the stage's "
                + "terrain sweep completes; oreBudget documents the intended per-annulus vein budget. "
                + "Edit and run /eclipse reload to apply radii; already-committed stages are not re-swept.");
        for (Map.Entry<String, List<StageEntry>> dimension : stages.entrySet()) {
            JsonArray array = new JsonArray(dimension.getValue().size());
            for (StageEntry entry : dimension.getValue()) {
                JsonObject obj = new JsonObject();
                obj.addProperty("stage", entry.stage());
                obj.addProperty("radius", entry.radius());
                obj.addProperty("trigger", entry.trigger());
                obj.add("structures", stringArray(entry.structures()));
                JsonObject budget = new JsonObject();
                for (Map.Entry<String, Integer> ore : entry.oreBudget().entrySet()) {
                    budget.addProperty(ore.getKey(), ore.getValue());
                }
                obj.add("oreBudget", budget);
                array.add(obj);
            }
            root.add(dimension.getKey(), array);
        }
        return root;
    }

    private static Map<String, List<StageEntry>> stagesFromJson(JsonElement json) {
        JsonObject root = json.getAsJsonObject();
        Map<String, List<StageEntry>> parsed = new LinkedHashMap<>();
        for (String dimension : List.of("overworld", "nether")) {
            if (!root.has(dimension)) {
                parsed.put(dimension, defaultStages().get(dimension));
                continue;
            }
            List<StageEntry> entries = new ArrayList<>();
            for (JsonElement element : root.getAsJsonArray(dimension)) {
                JsonObject obj = element.getAsJsonObject();
                Map<String, Integer> oreBudget = new LinkedHashMap<>();
                if (obj.has("oreBudget")) {
                    for (Map.Entry<String, JsonElement> ore : obj.getAsJsonObject("oreBudget").entrySet()) {
                        oreBudget.put(ore.getKey(), ore.getValue().getAsInt());
                    }
                }
                entries.add(new StageEntry(
                        obj.get("stage").getAsInt(),
                        obj.get("radius").getAsInt(),
                        obj.has("trigger") ? obj.get("trigger").getAsString() : "manual",
                        obj.has("structures") ? stringList(obj.getAsJsonArray("structures")) : List.of(),
                        Collections.unmodifiableMap(oreBudget)));
            }
            entries.sort(java.util.Comparator.comparingInt(StageEntry::stage));
            parsed.put(dimension, List.copyOf(entries));
        }
        return Collections.unmodifiableMap(parsed);
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
