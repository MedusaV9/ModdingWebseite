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
     * {@code legacyStrongholdSelfHeal} (V5-FIXGUARD / EVAL-SAT-S #5, default {@code false})
     * is the explicit opt-in for the {@code StrongholdEmergence} start-up self-heal on
     * legacy saves whose {@code stages.json} still lists {@code eclipse:stronghold_emergence}.
     */
    public record General(int graveGraceMinutes, boolean dayAutoAdvance, String dayAutoAdvanceTime,
            int ringBlocksBudgetMs, boolean cutscenesFreezeDuringUnlocks, int borderOffset,
            int borderFxRange, boolean randomizeMapSeed, boolean legacyStrongholdSelfHeal) {}

    /**
     * One entry of a dimension's stage timeline ({@code stages.json}): the disc radius reached
     * at that stage, what triggers it ({@code "intro_fusion"}, {@code "milestone:N"},
     * {@code "day:N"} or {@code "final_day"}), the structure ids worker 5's stamper places when
     * the stage's terrain sweep completes, and a LEGACY per-annulus ore budget — ore
     * distribution is actually fixed by the terrain generator ({@code DiscTerrainFunction}'s
     * noise tables), so the field is parsed for backward compat only and no longer written.
     */
    public record StageEntry(int stage, int radius, String trigger, List<String> structures,
            Map<String, Integer> oreBudget) {}

    /**
     * Per-day plan: three goals, progression unlock keys, and the optional announcement/
     * timeline {@code title}/{@code subtitle} literals (empty = use the generic lang
     * fallback). The per-day lines live SERVER-SIDE on purpose: shipping them as lang keys
     * would let clients datamine the anonymized arc ("DAY 14 — THE FERRYMAN") straight out
     * of the jar. {@code borderSize} is deprecated since W7 (the soft border follows
     * {@code stages.json}) — parsed for backward compat, never written, {@code 0} when absent.
     *
     * <p>Wave-5 (PLAN-C §C13 / A5-extra): optional {@code titleDone}/{@code subtitleDone}
     * variants replace the regular lines once the day's content is actually beaten
     * (server truth via {@code timeline.DayTextConditions}) — so the timeline and
     * announcements stop advertising already-beaten content. Absent/blank = never swap
     * (fully backward compatible with existing {@code days.json} files).</p>
     */
    public record DayPlan(int day, List<Localized> localizedGoals, List<String> unlocks,
            double borderSize, Localized localizedTitle, Localized localizedSubtitle,
            Localized localizedTitleDone, Localized localizedSubtitleDone) {
        public DayPlan {
            localizedGoals = List.copyOf(localizedGoals);
            unlocks = List.copyOf(unlocks);
            localizedTitle = localizedTitle == null ? Localized.of("") : localizedTitle;
            localizedSubtitle = localizedSubtitle == null ? Localized.of("") : localizedSubtitle;
            localizedTitleDone = localizedTitleDone == null ? Localized.of("") : localizedTitleDone;
            localizedSubtitleDone = localizedSubtitleDone == null ? Localized.of("") : localizedSubtitleDone;
        }

        /** Pre-Wave-5 canonical shape (no done-variants) — kept so existing callers compile. */
        public DayPlan(int day, List<Localized> localizedGoals, List<String> unlocks,
                double borderSize, Localized localizedTitle, Localized localizedSubtitle) {
            this(day, localizedGoals, unlocks, borderSize, localizedTitle, localizedSubtitle,
                    Localized.of(""), Localized.of(""));
        }

        /** Backward-compatible constructor for the built-in English-only defaults. */
        public DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize,
                String title, String subtitle) {
            this(day, goals, unlocks, borderSize, title, subtitle, "", "");
        }

        /** English-only defaults WITH the beaten-content done-variants (days 12/13). */
        public DayPlan(int day, List<String> goals, List<String> unlocks, double borderSize,
                String title, String subtitle, String titleDone, String subtitleDone) {
            this(day, localize(goals), unlocks, borderSize, Localized.of(title), Localized.of(subtitle),
                    Localized.of(titleDone), Localized.of(subtitleDone));
        }

        /** Legacy English view used by old command/editor seams. */
        public List<String> goals() {
            List<String> english = new ArrayList<>(localizedGoals.size());
            for (Localized goal : localizedGoals) {
                english.add(goal.en());
            }
            return List.copyOf(english);
        }

        /** Legacy English view used by old timeline/editor seams. */
        public String title() {
            return localizedTitle.en();
        }

        /** Legacy English view used by old timeline/editor seams. */
        public String subtitle() {
            return localizedSubtitle.en();
        }

        private static List<Localized> localize(List<String> strings) {
            List<Localized> localized = new ArrayList<>(strings.size());
            for (String string : strings) {
                localized.add(Localized.of(string));
            }
            return List.copyOf(localized);
        }
    }

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

    /** Whether new saves randomize the Eclipse map seed on first boot (default {@code false}). */
    public static boolean randomizeMapSeed() {
        return general().randomizeMapSeed();
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

    /**
     * The plan for the given day. Unmatched days fall back to the nearest LOWER configured
     * day (so a gap in {@code days.json} keeps showing the preceding plan rather than
     * jumping to the last one); days before the first plan clamp to the first.
     */
    public static DayPlan day(int day) {
        ensureLoaded();
        List<DayPlan> plans = days;
        DayPlan floor = null;
        for (DayPlan plan : plans) { // ordered by day (daysFromJson sorts)
            if (plan.day() == day) {
                return plan;
            }
            if (plan.day() < day) {
                floor = plan;
            }
        }
        return floor != null ? floor : plans.get(0);
    }

    /** The highest configured day in {@code days.json} — the auto-advance/scheduler ceiling. */
    public static int maxDay() {
        ensureLoaded();
        List<DayPlan> plans = days;
        return plans.get(plans.size() - 1).day();
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
        ReloadHooks.runAll();
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
        return new General(30, false, "08:00", 2, true, 12, 8, false, false);
    }

    private static JsonElement generalToJson(General general) {
        JsonObject obj = new JsonObject();
        obj.addProperty("graveGraceMinutes", general.graveGraceMinutes());
        obj.addProperty("dayAutoAdvance", general.dayAutoAdvance());
        obj.addProperty("dayAutoAdvanceTime", general.dayAutoAdvanceTime());
        obj.addProperty("ringBlocksBudgetMs", general.ringBlocksBudgetMs());
        obj.addProperty("borderOffset", general.borderOffset());
        obj.addProperty("borderFxRange", general.borderFxRange());
        obj.addProperty("randomizeMapSeed", general.randomizeMapSeed());
        obj.addProperty("legacyStrongholdSelfHeal", general.legacyStrongholdSelfHeal());
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
        boolean randomizeMapSeed = obj.has("randomizeMapSeed") && obj.get("randomizeMapSeed").getAsBoolean();
        // V5-FIXGUARD / EVAL-SAT-S #5: legacy saves must OPT IN to the stronghold self-heal.
        boolean legacyStrongholdSelfHeal = obj.has("legacyStrongholdSelfHeal")
                && obj.get("legacyStrongholdSelfHeal").getAsBoolean();
        return new General(Math.max(0, graveGraceMinutes), dayAutoAdvance, dayAutoAdvanceTime,
                Math.max(1, ringBlocksBudgetMs), freezeDuringUnlocks, Math.max(0, borderOffset),
                Math.max(1, borderFxRange), randomizeMapSeed, legacyStrongholdSelfHeal);
    }

    // --- days.json ---

    /**
     * The v2 14-day arc (spec {@code docs/ideas/04_content.md} §6). Nether opens on day 2
     * ("The Burning Door"); day 7/14 are the boss days. Day 7's {@code enchanting} key is
     * SPECIAL: {@code progression.UnlockState} unions it only once the Herald has fallen.
     * The {@code title}/{@code subtitle} literals are the former
     * {@code announce.eclipse.day.N.title/.sub} lang lines, moved here verbatim so the
     * anonymized arc cannot be datamined from the client jar (see {@link DayPlan}).
     * The deprecated {@code borderSize} is no longer written (see {@link DayPlan}).
     *
     * <p>LANGAUDIT: every goal/title/subtitle default now ships as a dual-language
     * {@link Localized} — English-only defaults made German-locale players see English
     * day announcements and timeline entries (the reported "Day 1" / double-language
     * day-change bug). NOTE: an existing {@code days.json} on disk wins over these
     * defaults; regenerate or hand-merge the {@code de} lines for live servers.</p>
     */
    private static List<DayPlan> defaultDays() {
        List<DayPlan> plans = new ArrayList<>(14);
        plans.add(new DayPlan(1, List.of(
                new Localized("Survive the first night", "Überlebt die erste Nacht"),
                new Localized("Gather 16 logs and a set of stone tools as a team", "Sammelt als Team 16 Holzstämme und einen Satz Steinwerkzeuge"),
                new Localized("Everyone touches the altar", "Alle berühren den Altar")), List.of(), 0.0D,
                new Localized("DAY 1 — FIRST LIGHT", "TAG 1 — ERSTES LICHT"),
                new Localized("Day 1. Survive the night — the eclipse is watching.", "Tag 1. Überlebt die Nacht — die Eclipse beobachtet euch.")));
        plans.add(new DayPlan(2, List.of(
                new Localized("Enter the Nether", "Betretet den Nether"),
                new Localized("Smelt 8 gold ingots", "Schmelzt 8 Goldbarren"),
                new Localized("Raise the altar to level 1", "Hebt den Altar auf Stufe 1")), List.of("nether", "main_inventory"), 0.0D,
                new Localized("DAY 2 — THE BURNING DOOR", "TAG 2 — DAS BRENNENDE TOR"),
                new Localized("Day 2. The nether gate groans open early — and your packs with it.", "Tag 2. Das Nethertor ächzt zu früh auf — und eure Rucksäcke mit ihm.")));
        plans.add(new DayPlan(3, List.of(
                new Localized("Build your first Create contraption", "Baut eure erste Create-Konstruktion"),
                new Localized("Forge a full iron toolset", "Schmiedet einen vollständigen Satz Eisenwerkzeuge"),
                new Localized("Scout the newly risen desert ring", "Erkundet den neu erhobenen Wüstenring")), List.of("workbenches", "create"), 0.0D,
                new Localized("DAY 3 — MACHINES IN THE DARK", "TAG 3 — MASCHINEN IM DUNKELN"),
                new Localized("Day 3. Workstations hum; contraptions may turn.", "Tag 3. Werkstationen summen; Konstruktionen dürfen sich drehen.")));
        plans.add(new DayPlan(4, List.of(
                new Localized("Cook three Farmer's Delight meals", "Kocht drei Farmer's-Delight-Gerichte"),
                new Localized("Establish a reliable food farm", "Errichtet eine verlässliche Nahrungsfarm"),
                new Localized("Wear full iron armor", "Tragt vollständige Eisenrüstung")), List.of("armor", "farmersdelight", "simulated"), 0.0D,
                new Localized("DAY 4 — THE FEAST", "TAG 4 — DAS FESTMAHL"),
                new Localized("Day 4. Armor up and set the table — trust is cooked, not given.", "Tag 4. Legt Rüstung an und deckt den Tisch — Vertrauen wird gekocht, nicht geschenkt.")));
        plans.add(new DayPlan(5, List.of(
                new Localized("Take to the skies", "Erhebt euch in die Lüfte"),
                new Localized("Gather 24 iron ingots as a team", "Sammelt als Team 24 Eisenbarren"),
                new Localized("Rig something with Supplementaries", "Baut etwas mit Supplementaries")), List.of("aeronautics", "supplementaries"), 0.0D,
                new Localized("DAY 5 — SKYWARD", "TAG 5 — HIMMELWÄRTS"),
                new Localized("Day 5. The sky opens for the daring.", "Tag 5. Der Himmel öffnet sich den Wagemutigen.")));
        plans.add(new DayPlan(6, List.of(
                new Localized("Find the nether fortress", "Findet die Netherfestung"),
                new Localized("Collect 6 blaze rods", "Sammelt 6 Lohenruten"),
                new Localized("Craft the Herald's Lure", "Fertigt den Köder des Herolds")), List.of(), 0.0D,
                new Localized("DAY 6 — FORTRESS", "TAG 6 — DIE FESTUNG"),
                new Localized("Day 6. Find the fortress. Craft the lure. Dusk tomorrow decides.", "Tag 6. Findet die Festung. Fertigt den Köder. Die morgige Dämmerung entscheidet.")));
        plans.add(new DayPlan(7, List.of(
                new Localized("Summon the Herald at dusk", "Beschwört den Herold in der Abenddämmerung"),
                new Localized("Defeat the Herald", "Bezwingt den Herold"),
                new Localized("Deposit the Herald Core at the altar", "Legt den Heroldkern am Altar nieder")), List.of("enchanting"), 0.0D,
                new Localized("DAY 7 — THE HERALD", "TAG 7 — DER HEROLD"),
                new Localized("Day 7. At dusk it descends. Enchanting belongs to its killers.", "Tag 7. In der Dämmerung steigt er herab. Das Verzaubern gehört seinen Bezwingern.")));
        plans.add(new DayPlan(8, List.of(
                new Localized("Fill a team ender chest", "Füllt eine Team-Endertruhe"),
                new Localized("Bank 16 ender pearls", "Hinterlegt 16 Enderperlen"),
                new Localized("Raise the altar to level 4", "Hebt den Altar auf Stufe 4")), List.of("ender_chests", "sophisticatedbackpacks", "sable"), 0.0D,
                new Localized("DAY 8 — THE HOARD", "TAG 8 — DER HORT"),
                new Localized("Day 8. Ender chests keep what you cannot.", "Tag 8. Endertruhen bewahren, was ihr nicht bewahren könnt.")));
        plans.add(new DayPlan(9, List.of(
                new Localized("Brew strength and fire resistance", "Braut Stärke und Feuerresistenz"),
                new Localized("Electrify a Create machine", "Elektrifiziert eine Create-Maschine"),
                new Localized("Pool 24 umbral shards", "Legt als Team 24 Umbrasplitter zusammen")), List.of("brewing", "createaddition"), 0.0D,
                new Localized("DAY 9 — ALCHEMY AND VOLTAGE", "TAG 9 — ALCHEMIE UND SPANNUNG"),
                new Localized("Day 9. Cauldrons bubble; machines crackle awake.", "Tag 9. Kessel brodeln; Maschinen erwachen knisternd.")));
        plans.add(new DayPlan(10, List.of(
                new Localized("Find a smithing template", "Findet eine Schmiedevorlage"),
                new Localized("Upgrade a tool to netherite", "Wertet ein Werkzeug zu Netherit auf"),
                new Localized("Fortify your base", "Befestigt eure Basis")), List.of("smithing"), 0.0D,
                new Localized("DAY 10 — DEEP RUIN", "TAG 10 — TIEFE RUINEN"),
                new Localized("Day 10. Netherite awaits the patient smith.", "Tag 10. Netherit erwartet den geduldigen Schmied.")));
        plans.add(new DayPlan(11, List.of(
                new Localized("Everyone reaches 4+ hearts", "Alle erreichen mindestens 4 Herzen"),
                new Localized("Revive a banned player", "Belebt einen verbannten Spieler wieder"),
                new Localized("Assemble an End raid kit", "Stellt eine Ausrüstung für den Sturm auf das Ende zusammen")), List.of(), 0.0D,
                new Localized("DAY 11 — THE WEAKEST LINK", "TAG 11 — DAS SCHWÄCHSTE GLIED"),
                new Localized("Day 11. A chain is judged by its weakest link.", "Tag 11. Eine Kette wird an ihrem schwächsten Glied gemessen.")));
        // Days 12/13 carry done-variants (C13/A5-extra): once the End has arrived / the
        // dragon has fallen, the timeline and announcements stop advertising the hunt.
        // B15: day 12 targets the End disc in the sky — the stronghold no longer spawns.
        plans.add(new DayPlan(12, List.of(
                new Localized("Locate the End disc in the sky", "Ortet die Endscheibe am Himmel"),
                new Localized("Open the rift to the End disc", "Öffnet den Riss zur Endscheibe"),
                new Localized("Purge the endermites around the rift", "Vertilgt die Endermiten rund um den Riss")), List.of("end"), 0.0D,
                new Localized("DAY 12 — THE SKY SHARD", "TAG 12 — DER HIMMELSSPLITTER"),
                new Localized("Day 12. A shard of the End hangs in the sky — the rift hums above the clouds.", "Tag 12. Ein Splitter des Endes hängt am Himmel — der Riss summt über den Wolken."),
                new Localized("DAY 12 — THE OPEN RIFT", "TAG 12 — DER OFFENE RISS"),
                new Localized("Day 12. The rift stands open — the sky has given up its secret.", "Tag 12. Der Riss steht offen — der Himmel hat sein Geheimnis preisgegeben.")));
        plans.add(new DayPlan(13, List.of(
                new Localized("Defeat the Ender Dragon", "Bezwingt den Enderdrachen"),
                new Localized("Claim the dragon egg", "Fordert das Drachenei"),
                new Localized("All survivors return home", "Alle Überlebenden kehren heim")), List.of(), 0.0D,
                new Localized("DAY 13 — THE DRAGON", "TAG 13 — DER DRACHE"),
                new Localized("Day 13. Bring the dragon down and claim the egg.", "Tag 13. Holt den Drachen vom Himmel und fordert das Ei."),
                new Localized("DAY 13 — THE SILENT SKY", "TAG 13 — DER STILLE HIMMEL"),
                new Localized("The dragon has fallen. Rest — tomorrow the ship sails.", "Der Drache ist gefallen. Ruht euch aus — morgen sticht das Schiff in See.")));
        plans.add(new DayPlan(14, List.of(
                new Localized("Offer the egg at dusk", "Opfert das Ei in der Abenddämmerung"),
                new Localized("Survive the crossing", "Überlebt die Überfahrt"),
                new Localized("Defeat the Ferryman before the ship sinks", "Bezwingt den Fährmann, bevor das Schiff sinkt")), List.of(), 0.0D,
                new Localized("DAY 14 — THE FERRYMAN", "TAG 14 — DER FÄHRMANN"),
                new Localized("Day 14. Gather. The ship sails at dusk.", "Tag 14. Versammelt euch. Das Schiff sticht in der Dämmerung in See.")));
        return plans;
    }

    private static JsonElement daysToJson(List<DayPlan> plans) {
        JsonArray array = new JsonArray(plans.size());
        for (DayPlan plan : plans) {
            JsonObject obj = new JsonObject();
            obj.addProperty("day", plan.day());
            JsonArray goals = new JsonArray(plan.localizedGoals().size());
            for (Localized goal : plan.localizedGoals()) {
                goals.add(goal.toJsonElement());
            }
            obj.add("goals", goals);
            obj.add("unlocks", stringArray(plan.unlocks()));
            // The deprecated borderSize is deliberately NOT written (still parsed, see DayPlan).
            if (!plan.localizedTitle().isBlank()) {
                obj.add("title", plan.localizedTitle().toJsonElement());
            }
            if (!plan.localizedSubtitle().isBlank()) {
                obj.add("subtitle", plan.localizedSubtitle().toJsonElement());
            }
            if (!plan.localizedTitleDone().isBlank()) {
                obj.add("titleDone", plan.localizedTitleDone().toJsonElement());
            }
            if (!plan.localizedSubtitleDone().isBlank()) {
                obj.add("subtitleDone", plan.localizedSubtitleDone().toJsonElement());
            }
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
                    localizedList(obj.getAsJsonArray("goals")),
                    stringList(obj.getAsJsonArray("unlocks")),
                    // Legacy field: pre-W16 files (and ConfigEditor normalization) still carry it.
                    obj.has("borderSize") ? obj.get("borderSize").getAsDouble() : 0.0D,
                    obj.has("title") ? Localized.fromJson(obj.get("title")) : Localized.of(""),
                    obj.has("subtitle") ? Localized.fromJson(obj.get("subtitle")) : Localized.of(""),
                    obj.has("titleDone") ? Localized.fromJson(obj.get("titleDone")) : Localized.of(""),
                    obj.has("subtitleDone") ? Localized.fromJson(obj.get("subtitleDone")) : Localized.of("")));
        }
        if (plans.isEmpty()) {
            throw new IllegalStateException("days.json contains no day entries");
        }
        plans.sort(java.util.Comparator.comparingInt(DayPlan::day));
        return plans;
    }

    // --- milestones.json ---

    /**
     * The v3 event milestone costs (P4 §2.6): multi-item, pooled sinks sized for a 20–30
     * player team. L4 remains boss-locked by the guaranteed Herald Core.
     *
     * <p><b>FINAL-DOPA-SOL §3 ladder fix:</b> the old table was circular — L1 demanded
     * iron ({@code unlockStage 2}, opened by milestone 2), L2 gold (same) and L3
     * diamonds + 72 emeralds (stage 3 / no Eclipse emerald ore), deadlocking the altar
     * before L1. Each level now consumes only materials mineable BEFORE it (with the
     * matching {@code ores.json} unlock stages): L1 copper/coal era (stage 0, day 1–2),
     * L2 iron era (iron stage 0, amethyst geodes day 2–3), L3 gold era (gold stage 1 +
     * redstone from the stage-2 ring milestone 2 raised, day 4–5), L4 diamond era
     * (diamond stage 2, Herald Core day 7, day 8), L5 netherite era (debris behind the
     * day-10 Nether annulus, quartz from day 2). Emerald blocks are dropped entirely
     * (eval: "Seventy-two emeralds are not [reasonable]"). Counts stay deliberately
     * chunky — pooled team sinks, not solo errands.
     */
    private static List<Milestone> defaultMilestones() {
        return List.of(
                // L1 — copper/coal era: both unlockStage 0, mineable from minute one.
                new Milestone(1, List.of(
                        new ItemCost("minecraft:copper_ingot", 48),
                        new ItemCost("minecraft:coal", 32)), List.of("create")),
                // L2 — iron era: iron is unlockStage 0 (FINAL-DOPA-SOL fix), amethyst
                // is geode loot the eval rates "reasonable by day 2–3".
                new Milestone(2, List.of(
                        new ItemCost("minecraft:iron_ingot", 48),
                        new ItemCost("minecraft:amethyst_shard", 16)), List.of("simulated")),
                // L3 — gold era: gold unlockStage 1 (starting disc band 1 + Nether gold
                // from day 2); redstone sits in the stage-2 ring that milestone 2 raised.
                new Milestone(3, List.of(
                        new ItemCost("minecraft:gold_ingot", 32),
                        new ItemCost("minecraft:redstone", 32)), List.of("aeronautics")),
                // L4 — diamond era, still boss-locked: diamond unlockStage 2 is open
                // since milestone 2 (~day 3), the Core drops from the day-7 Herald.
                new Milestone(4, List.of(
                        new ItemCost("eclipse:herald_core", 1),
                        new ItemCost("minecraft:diamond", 24),
                        new ItemCost("minecraft:ender_pearl", 32),
                        new ItemCost("minecraft:obsidian", 16)), List.of("sable")),
                // L5 — netherite era: ancient debris opens with the day-10 Nether
                // annulus; 48 quartz blocks are 10+ days of day-2-unlocked quartz.
                new Milestone(5, List.of(
                        new ItemCost("minecraft:netherite_ingot", 4),
                        new ItemCost("minecraft:quartz_block", 48)), List.of("end")));
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
     * {@code disc_map.json} landmark list worker 5 stamps from. No ore budgets: ore
     * distribution is fixed by the terrain generator (see {@link StageEntry}).
     */
    private static Map<String, List<StageEntry>> defaultStages() {
        Map<String, List<StageEntry>> defaults = new LinkedHashMap<>();
        defaults.put("overworld", List.of(
                new StageEntry(1, 150, "intro_fusion", List.of(), Map.of()),
                new StageEntry(2, 210, "milestone:2",
                        List.of("eclipse:desert_temple", "minecraft:pillager_outpost"), Map.of()),
                new StageEntry(3, 280, "milestone:3",
                        List.of("eclipse:jungle_temple", "minecraft:trial_chambers"), Map.of()),
                new StageEntry(4, 360, "milestone:4",
                        List.of("eclipse:village_plains", "minecraft:mansion", "minecraft:ancient_city"), Map.of()),
                // plans_v5 PLAN-B B15: the stronghold no longer spawns — the End-disc
                // finale replaced it (EndDiscService/EndConfig own their own trigger),
                // so stage 5 grows terrain only. Frozen saves that already committed
                // stage 5 keep their stronghold; new saves never get one.
                new StageEntry(5, 440, "final_day", List.of(), Map.of())));
        // IDEA-17 (W4-NETHER): 1:1 nether disc — radii aligned with the overworld growth
        // beats. Must stay in lockstep with FrozenParams.DEFAULT_NETHER_RADII (the freeze
        // file is built from THESE entries; the FrozenParams constant is the fallback).
        defaults.put("nether", List.of(
                new StageEntry(1, 150, "day:2", List.of("eclipse:fortress_core"), Map.of()),
                new StageEntry(2, 280, "day:10", List.of(), Map.of()),
                new StageEntry(3, 440, "day:12", List.of(), Map.of())));
        return Collections.unmodifiableMap(defaults);
    }

    private static JsonElement stagesToJson(Map<String, List<StageEntry>> stages) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Per-dimension world stage timeline (separate from days.json). "
                + "radius = fused disc radius in blocks; trigger = intro_fusion | milestone:N (altar level) "
                + "| day:N | final_day; structures = ids stamped by the structure worker when the stage's "
                + "terrain sweep completes. Ore distribution is fixed by the terrain generator's noise "
                + "tables and is not configurable (legacy oreBudget entries are parsed but ignored). "
                + "Edit and run /eclipse reload to apply radii; already-committed stages are not re-swept.");
        for (Map.Entry<String, List<StageEntry>> dimension : stages.entrySet()) {
            JsonArray array = new JsonArray(dimension.getValue().size());
            for (StageEntry entry : dimension.getValue()) {
                JsonObject obj = new JsonObject();
                obj.addProperty("stage", entry.stage());
                obj.addProperty("radius", entry.radius());
                obj.addProperty("trigger", entry.trigger());
                obj.add("structures", stringArray(entry.structures()));
                // The legacy oreBudget is deliberately NOT written (still parsed, see StageEntry).
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

    private static List<Localized> localizedList(JsonArray array) {
        if (array == null) {
            return List.of();
        }
        List<Localized> result = new ArrayList<>(array.size());
        array.forEach(element -> result.add(Localized.fromJson(element)));
        return List.copyOf(result);
    }
}
