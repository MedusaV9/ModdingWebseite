package dev.projecteclipse.eclipse.collections;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loads {@code config/eclipse/collections.json} (D1 Skyblock-style collections:
 * IDEAS-collections §6). {@code RecipeGateConfig} pattern: written with the fully
 * authored 17-collection default set on first run, hot-reload via the {@code
 * ReloadHooks} entry that {@link CollectionsService} registers ({@code /eclipse reload}
 * re-runs the threshold sweep so LOWERED thresholds grant retroactively).
 *
 * <p>Validation (fail-safe): unknown {@code lane} → collection skipped with WARN;
 * non-increasing tier thresholds → tier list truncated at the violation; {@code
 * unlockItems} are never validated against the recipe registry (tags may load later —
 * same leniency as RecipeGate's missing-tag DEBUG). A parse failure of an EXISTING file
 * keeps the previous snapshot instead of falling back to defaults, so a typo during a
 * live event can never re-lock everyone's recipes.</p>
 *
 * <p><b>Migration (EVAL-V6-COMPLETE A#7):</b> {@code configVersion} gates a TARGETED
 * in-place patch (not GoalConfig's backup-and-regenerate — collections are more likely
 * to carry deliberate server tuning). A parseable file older than
 * {@link #CONFIG_VERSION} (missing field = v1) gets the cumulative cobblestone
 * {@code dailyCreditCap} delta applied — v1's uncapped default AND v2's interim 600
 * (which shipped in deviation of EVAL-DOPA-F #9; AUDIT-v7 §1.8) both land on
 * {@value #COBBLESTONE_DAILY_CREDIT_CAP} — is stamped with the current version and
 * written back. Any other positive cap is deliberate operator tuning and is respected.
 * Unparseable files are left untouched (the reload path already keeps the previous
 * snapshot for those).</p>
 *
 * <p><b>Dev-run note:</b> an existing {@code run/config/eclipse/collections.json} is
 * migrated in place on the next launch (or {@code /eclipse reload}); deleting it
 * regenerates the full default set with the current cap — no manual edit needed.</p>
 */
public final class CollectionsConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE = "collections.json";

    /**
     * Version 2 = EVAL-DOPA-F #9 / EVAL-V6-COMPLETE A#7: cobblestone gained its REAL
     * daily credit cap — but shipped 600/day in deviation of EVAL-DOPA-F's explicit
     * 1500. Version 3 = AUDIT-v7 §1.8: the cap is corrected to the required 1500;
     * the migration also lifts stale 600 files (EVAL-DOPA-F's number wins). The default
     * writer alone never reaches servers whose {@code collections.json} predates the
     * change, so {@link #migrateIfOutdated} patches those files in place. Bump when a
     * shipped default must reach live files.
     */
    public static final int CONFIG_VERSION = 3;
    /** The cobblestone daily credit cap (EVAL-DOPA-F #9's required 1500; AUDIT-v7 §1.8). */
    private static final long COBBLESTONE_DAILY_CREDIT_CAP = 1500L;
    /**
     * The interim cap the v2 default writer + migration shipped (600 — the EVAL-DOPA-F
     * deviation). The v3 migration treats exactly this value as "still the stale shipped
     * default" and lifts it to {@link #COBBLESTONE_DAILY_CREDIT_CAP}; any other positive
     * value is deliberate operator tuning and is kept.
     */
    private static final long LEGACY_V2_COBBLESTONE_CAP = 600L;

    /** Valid signal lanes (IDEAS-collections §4.1). */
    public static final Set<String> LANES = Set.of("mine", "harvest", "kill", "shard_bank", "pickup");
    public static final String LANE_MINE = "mine";
    public static final String LANE_HARVEST = "harvest";
    public static final String LANE_KILL = "kill";
    public static final String LANE_SHARD_BANK = "shard_bank";
    public static final String LANE_PICKUP = "pickup";

    private static volatile Snapshot current = Snapshot.empty();
    private static volatile Set<String> pickupAllowlist = Set.of();
    private static volatile boolean loaded = false;

    private CollectionsConfig() {}

    /**
     * One reward tier; {@code unlockItems} use recipegate entry syntax (ids or
     * {@code #tags}). {@code shards} (FIX-ECON): PERSONAL umbral shards credited through
     * {@code ShardEconomy.addShards} on tier-up — the chunky T4+ tiers pay 1–2 so
     * collections fund the rebirth ladder (DOPA-S-03 gap).
     */
    public record Tier(long threshold, int xp, int points, int shards, List<String> unlockItems) {
        public Tier {
            unlockItems = List.copyOf(unlockItems);
        }
    }

    /**
     * One collection definition. {@code ids} take block/entity/item ids or {@code #tags}
     * depending on the lane; {@code dailyCreditCap} 0 = uncapped (default, §5.7).
     */
    public record Collection(String id, String category, String icon, String lane, List<String> ids,
            long dailyCreditCap, List<Tier> tiers) {
        public Collection {
            ids = List.copyOf(ids);
            tiers = List.copyOf(tiers);
        }
    }

    public record Snapshot(boolean toastsEnabled, String xpSourceKey, List<Collection> collections) {
        public Snapshot {
            collections = List.copyOf(collections);
        }

        static Snapshot empty() {
            return new Snapshot(true, "collection", List.of());
        }

        /** Definition by id, or {@code null}. */
        public Collection byId(String id) {
            for (Collection collection : collections) {
                if (collection.id().equals(id)) {
                    return collection;
                }
            }
            return null;
        }
    }

    public static Snapshot current() {
        ensureLoaded();
        return current;
    }

    /**
     * Exact item ids counted by any {@code pickup}-lane collection — the bound of the
     * {@code ItemEntityPickupEvent.Post} lane in {@code AnalyticsService} (tag entries are
     * deliberately NOT expanded here; the pickup lane stays a tiny exact-id allowlist).
     */
    public static Set<String> pickupAllowlist() {
        ensureLoaded();
        return pickupAllowlist;
    }

    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve(FILE);
        try {
            Files.createDirectories(configDir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create collections config directory {}", configDir, e);
        }

        JsonObject root;
        if (!Files.exists(file)) {
            root = defaultRoot();
            try {
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        } else {
            try {
                root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            } catch (IOException | RuntimeException e) {
                // §6: parse failure keeps the previous snapshot (never re-lock a live event).
                EclipseMod.LOGGER.error("Failed to read config {}; keeping previous collections snapshot", file, e);
                loaded = true;
                return;
            }
            migrateIfOutdated(root, file);
        }

        apply(parse(root));
        EclipseMod.LOGGER.info("Collections config loaded ({} collection(s))", current.collections().size());
    }

    public static synchronized void reloadDefault() {
        reload(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    /** Test seam: installs a parsed snapshot as current (gametests / dev tooling). */
    public static synchronized void apply(Snapshot snapshot) {
        current = snapshot;
        Set<String> allowlist = new LinkedHashSet<>();
        for (Collection collection : snapshot.collections()) {
            if (LANE_PICKUP.equals(collection.lane())) {
                for (String id : collection.ids()) {
                    if (!id.startsWith("#")) {
                        allowlist.add(id);
                    }
                }
            }
        }
        pickupAllowlist = Set.copyOf(allowlist);
        loaded = true;
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reloadDefault();
        }
    }

    /**
     * Version-gated in-place migration of a parseable existing file (class doc).
     * Cumulative cobblestone delta: {@code dailyCreditCap} becomes
     * {@value #COBBLESTONE_DAILY_CREDIT_CAP} when the file still carries a shipped
     * default — the v1 uncapped default (missing or {@code <= 0}) or the stale v2
     * interim {@value #LEGACY_V2_COBBLESTONE_CAP} (AUDIT-v7 §1.8: EVAL-DOPA-F's 1500
     * wins); any other positive cap is deliberate operator tuning and is respected.
     * The patched root is stamped and written back so the migration runs once; a failed
     * write keeps the patched in-memory root (the sweep still sees the cap this
     * session).
     */
    private static void migrateIfOutdated(JsonObject root, Path file) {
        int fileVersion = 1;
        try {
            if (root.has("configVersion")) {
                fileVersion = root.get("configVersion").getAsInt();
            }
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("{}: malformed configVersion; treating as v1 ({})",
                    file.getFileName(), e.getMessage());
        }
        if (fileVersion >= CONFIG_VERSION) {
            return;
        }
        boolean capped = false;
        if (root.has("collections") && root.get("collections").isJsonArray()) {
            for (JsonElement element : root.getAsJsonArray("collections")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                JsonObject collection = element.getAsJsonObject();
                if (!collection.has("id") || !"cobblestone".equals(idOf(collection))) {
                    continue;
                }
                long cap = 0L;
                try {
                    cap = collection.has("dailyCreditCap") ? collection.get("dailyCreditCap").getAsLong() : 0L;
                } catch (RuntimeException ignored) {
                    // malformed cap value — treat as the old uncapped default and patch it
                }
                if (cap <= 0L || cap == LEGACY_V2_COBBLESTONE_CAP) {
                    collection.addProperty("dailyCreditCap", COBBLESTONE_DAILY_CREDIT_CAP);
                    capped = true;
                }
            }
        }
        root.addProperty("configVersion", CONFIG_VERSION);
        try {
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.warn("{} migrated v{} -> v{}: cobblestone dailyCreditCap {}",
                    file.getFileName(), fileVersion, CONFIG_VERSION,
                    capped ? "set to " + COBBLESTONE_DAILY_CREDIT_CAP : "already customized, kept");
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write migrated config {} — patch applies in-memory only", file, e);
        }
    }

    private static String idOf(JsonObject collection) {
        try {
            return collection.get("id").getAsString();
        } catch (RuntimeException e) {
            return "";
        }
    }

    // ------------------------------------------------------------------ parsing

    /** Public for gametests (validation pins). Never throws; bad entries degrade per class doc. */
    public static Snapshot parse(JsonObject root) {
        boolean toasts = !root.has("toastsEnabled") || root.get("toastsEnabled").getAsBoolean();
        String sourceKey = root.has("xpSourceKey") ? root.get("xpSourceKey").getAsString() : "collection";
        List<Collection> collections = new ArrayList<>();
        if (root.has("collections") && root.get("collections").isJsonArray()) {
            for (JsonElement element : root.getAsJsonArray("collections")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                Collection parsed = parseCollection(element.getAsJsonObject());
                if (parsed != null) {
                    collections.add(parsed);
                }
            }
        }
        return new Snapshot(toasts, sourceKey, collections);
    }

    private static Collection parseCollection(JsonObject obj) {
        String id = obj.has("id") ? obj.get("id").getAsString() : "";
        if (id.isBlank()) {
            EclipseMod.LOGGER.warn("Collections config: entry without id skipped");
            return null;
        }
        String lane = obj.has("lane") ? obj.get("lane").getAsString().toLowerCase(Locale.ROOT) : "";
        if (!LANES.contains(lane)) {
            EclipseMod.LOGGER.warn("Collections config: collection '{}' has unknown lane '{}' — skipped", id, lane);
            return null;
        }
        String category = obj.has("category") ? obj.get("category").getAsString().toLowerCase(Locale.ROOT) : "event";
        String icon = obj.has("icon") ? obj.get("icon").getAsString() : "minecraft:chest";
        long cap = obj.has("dailyCreditCap") ? Math.max(0L, obj.get("dailyCreditCap").getAsLong()) : 0L;
        List<String> ids = readStringList(obj, "ids");

        List<Tier> tiers = new ArrayList<>();
        long previousThreshold = 0L;
        if (obj.has("tiers") && obj.get("tiers").isJsonArray()) {
            for (JsonElement element : obj.getAsJsonArray("tiers")) {
                if (!element.isJsonObject()) {
                    continue;
                }
                JsonObject tierObj = element.getAsJsonObject();
                long threshold = tierObj.has("threshold") ? tierObj.get("threshold").getAsLong() : 0L;
                if (threshold <= previousThreshold) {
                    EclipseMod.LOGGER.warn(
                            "Collections config: collection '{}' tier threshold {} not above {} — tier list truncated",
                            id, threshold, previousThreshold);
                    break;
                }
                previousThreshold = threshold;
                int xp = tierObj.has("xp") ? Math.max(0, tierObj.get("xp").getAsInt()) : 0;
                int points = tierObj.has("points") ? Math.max(0, tierObj.get("points").getAsInt()) : 0;
                int shards = tierObj.has("shards") ? Math.max(0, tierObj.get("shards").getAsInt()) : 0;
                tiers.add(new Tier(threshold, xp, points, shards, readStringList(tierObj, "unlockItems")));
            }
        }
        if (tiers.isEmpty()) {
            EclipseMod.LOGGER.warn("Collections config: collection '{}' has no valid tiers — skipped", id);
            return null;
        }
        return new Collection(id, category, icon, lane, ids, cap, tiers);
    }

    private static List<String> readStringList(JsonObject obj, String key) {
        if (!obj.has(key) || !obj.get(key).isJsonArray()) {
            return List.of();
        }
        JsonArray array = obj.getAsJsonArray(key);
        List<String> out = new ArrayList<>(array.size());
        for (JsonElement element : array) {
            if (element.isJsonPrimitive()) {
                out.add(element.getAsString());
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ defaults (IDEAS-collections §1)

    /** Public for gametests (default-set pins: 17 collections, XP budget). */
    public static JsonObject defaultRoot() {
        JsonObject root = new JsonObject();
        root.addProperty("_doc", "Collections: lanes mine|harvest|kill|shard_bank|pickup; ids take "
                + "block/entity/item ids or #tags; thresholds strictly increasing; unlockItems use "
                + "recipegate syntax (ids or #tags); dailyCreditCap 0 = uncapped; shards (FIX-ECON) = "
                + "PERSONAL umbral shards credited on tier-up (chunky T4+ tiers pay 1-2 so "
                + "collections fund the rebirth ladder).");
        root.addProperty("configVersion", CONFIG_VERSION);
        root.addProperty("toastsEnabled", true);
        root.addProperty("xpSourceKey", "collection");
        JsonArray collections = new JsonArray();

        // --- Mining (7) — lane mine, natural blocks only (§1.1) ---
        // EVAL-DOPA-F #9: cobblestone ships a REAL daily credit cap (1500/day, the
        // eval's explicit number — AUDIT-v7 §1.8 closed the interim 600 deviation) —
        // the stone lane is the one infinitely farmable counter, so an uncapped default
        // turns a quarry night into a whole ladder sweep.
        collections.add(collection("cobblestone", "mining", "minecraft:cobblestone", "mine",
                ids("minecraft:stone", "minecraft:cobblestone", "minecraft:deepslate", "minecraft:cobbled_deepslate"),
                COBBLESTONE_DAILY_CREDIT_CAP,
                tier(50, 50, 0),
                tier(250, 100, 0, "minecraft:stonecutter"),
                tier(1000, 150, 0, "minecraft:dispenser", "minecraft:dropper"),
                tier(2500, 250, 0, 1, "minecraft:piston", "minecraft:sticky_piston"),
                tier(6000, 400, 1, 2),
                tier(12500, 600, 1, 2)));
        // EVAL-DOPA-F #9: one +1 SP MOVED from T5 down to T2 (early skill-point hit;
        // the ladder's total SP budget is unchanged).
        collections.add(collection("coal", "mining", "minecraft:coal", "mine",
                ids("minecraft:coal_ore", "minecraft:deepslate_coal_ore"),
                tier(25, 40, 0),
                tier(100, 75, 1, "minecraft:campfire"),
                tier(300, 125, 0, "minecraft:fire_charge"),
                tier(750, 200, 0, 1),
                tier(1500, 300, 0, 2),
                tier(3000, 450, 0, 2)));
        collections.add(collection("copper", "mining", "minecraft:copper_ingot", "mine",
                ids("minecraft:copper_ore", "minecraft:deepslate_copper_ore"),
                tier(20, 40, 0),
                tier(80, 75, 0, "minecraft:lightning_rod"),
                tier(250, 125, 0, "minecraft:brush"),
                tier(600, 200, 0, 1, "minecraft:spyglass"),
                tier(1200, 300, 0, 2),
                tier(2400, 450, 1, 2)));
        collections.add(collection("iron", "mining", "minecraft:iron_ingot", "mine",
                ids("minecraft:iron_ore", "minecraft:deepslate_iron_ore"),
                tier(15, 50, 0),
                tier(75, 100, 0, "minecraft:shield"),
                tier(250, 175, 0, "minecraft:crossbow", "minecraft:minecart", "minecraft:rail"),
                // ⚠ deliberate union with the recipegate.json day-2 anvil lock (§1.1).
                tier(600, 275, 0, 1, "minecraft:anvil"),
                tier(1250, 400, 1, 2, "minecraft:blast_furnace"),
                tier(2500, 600, 1, 2)));
        collections.add(collection("gold", "mining", "minecraft:gold_ingot", "mine",
                ids("minecraft:gold_ore", "minecraft:deepslate_gold_ore", "minecraft:nether_gold_ore"),
                tier(10, 50, 0),
                tier(40, 100, 0, "minecraft:clock"),
                tier(120, 175, 0, "minecraft:powered_rail"),
                tier(300, 275, 0, 1, "minecraft:golden_apple"),
                tier(600, 400, 1, 2),
                tier(1200, 600, 0, 2)));
        collections.add(collection("redstone", "mining", "minecraft:redstone", "mine",
                ids("minecraft:redstone_ore", "minecraft:deepslate_redstone_ore"),
                tier(10, 50, 0),
                tier(40, 100, 0, "minecraft:repeater"),
                tier(150, 175, 0, "minecraft:hopper", "minecraft:comparator"),
                tier(400, 275, 0, 1, "minecraft:observer"),
                tier(800, 400, 1, 2),
                tier(1600, 600, 1, 2)));
        collections.add(collection("diamond", "mining", "minecraft:diamond", "mine",
                ids("minecraft:diamond_ore", "minecraft:deepslate_diamond_ore"),
                tier(5, 75, 0),
                tier(20, 150, 0, "minecraft:jukebox"),
                tier(60, 250, 0, "minecraft:smithing_table"),
                tier(150, 400, 2, 1),
                tier(400, 600, 1, 2)));

        // --- Farming (3) — lane harvest, mature crops only; pumpkin rides mine (§1.2/§2.2) ---
        collections.add(collection("wheat", "farming", "minecraft:wheat", "harvest",
                ids("minecraft:wheat"),
                tier(30, 40, 0),
                tier(150, 100, 0, "minecraft:hay_block"),
                tier(500, 175, 0, "minecraft:cake"),
                tier(1250, 275, 0, 1, "minecraft:target"),
                tier(2500, 450, 1, 2)));
        collections.add(collection("carrot", "farming", "minecraft:carrot", "harvest",
                ids("minecraft:carrots"),
                tier(25, 40, 0),
                tier(125, 100, 0, "minecraft:carrot_on_a_stick"),
                tier(400, 175, 0),
                // Golden carrot is owned HERE, not by Gold (single-gate rule §1).
                tier(1000, 275, 0, 1, "minecraft:golden_carrot"),
                tier(2000, 450, 1, 2)));
        collections.add(collection("pumpkin", "farming", "minecraft:pumpkin", "mine",
                ids("minecraft:pumpkin"),
                tier(10, 40, 0),
                tier(50, 100, 0, "minecraft:jack_o_lantern"),
                tier(150, 175, 0, "minecraft:pumpkin_pie"),
                tier(400, 275, 0, 1),
                tier(800, 450, 1, 2)));

        // --- Wood (1) — lane mine on #minecraft:logs (§1.3) ---
        // EVAL-DOPA-F #9: one +1 SP MOVED from T5 down to T3 (early skill-point hit;
        // the ladder's total SP budget is unchanged).
        collections.add(collection("timber", "wood", "minecraft:oak_log", "mine",
                ids("#minecraft:logs"),
                tier(40, 50, 0),
                tier(200, 100, 0, "minecraft:barrel"),
                tier(600, 175, 1, "minecraft:smoker"),
                tier(1500, 275, 0, 1, "minecraft:loom", "minecraft:cartography_table"),
                tier(3000, 400, 0, 2),
                tier(6000, 600, 1, 2)));

        // --- Mobs (4) — lane kill: kills, not drops (Looting-neutral, §1.4) ---
        collections.add(collection("rotten_flesh", "mobs", "minecraft:rotten_flesh", "kill",
                ids("minecraft:zombie", "minecraft:zombie_villager", "minecraft:husk", "minecraft:drowned"),
                tier(10, 40, 0),
                tier(50, 100, 0),
                tier(150, 200, 1),
                tier(400, 325, 0, 1),
                tier(800, 500, 1, 2)));
        collections.add(collection("bone", "mobs", "minecraft:bone", "kill",
                ids("minecraft:skeleton", "minecraft:stray", "minecraft:bogged"),
                tier(10, 40, 0),
                tier(50, 100, 0, "minecraft:bone_block"),
                tier(150, 200, 0),
                tier(400, 325, 1, 1),
                tier(800, 500, 1, 2)));
        collections.add(collection("string", "mobs", "minecraft:string", "kill",
                ids("minecraft:spider", "minecraft:cave_spider"),
                tier(8, 40, 0),
                tier(40, 100, 0, "minecraft:fishing_rod"),
                tier(120, 200, 0, "minecraft:scaffolding"),
                tier(300, 325, 0, 1, "minecraft:lead"),
                tier(600, 500, 1, 2)));
        collections.add(collection("ender_pearl", "mobs", "minecraft:ender_pearl", "kill",
                ids("minecraft:enderman"),
                tier(3, 75, 0),
                // ⚠ deliberate union with the day-12 "end" UnlockState arc (§1.4).
                tier(10, 150, 0, "minecraft:ender_eye"),
                tier(30, 250, 0, "minecraft:ender_chest"),
                tier(75, 400, 0, 1, "minecraft:end_crystal"),
                tier(150, 600, 2, 2)));

        // --- Event (2) — lanes shard_bank / pickup (§1.5) ---
        collections.add(collection("umbral_shards", "event", "eclipse:umbral_shard", "shard_bank",
                ids("eclipse:umbral_shard"),
                tier(5, 75, 0),
                tier(25, 150, 0, "eclipse:eclipse_wand"),
                tier(75, 250, 1),
                tier(200, 400, 1, 1),
                tier(500, 600, 2, 2)));
        collections.add(collection("glitch_shards", "event", "eclipse:glitch_shard", "pickup",
                ids("eclipse:glitch_shard"),
                tier(3, 75, 0),
                tier(15, 150, 0),
                tier(50, 250, 1),
                tier(125, 400, 1, 1),
                tier(300, 600, 2, 2)));

        root.add("collections", collections);
        return root;
    }

    private static JsonObject collection(String id, String category, String icon, String lane,
            JsonArray ids, JsonObject... tiers) {
        return collection(id, category, icon, lane, ids, 0L, tiers);
    }

    /** Cap-aware variant (EVAL-DOPA-F #9: cobblestone ships a real daily credit cap). */
    private static JsonObject collection(String id, String category, String icon, String lane,
            JsonArray ids, long dailyCreditCap, JsonObject... tiers) {
        JsonObject obj = new JsonObject();
        obj.addProperty("id", id);
        obj.addProperty("category", category);
        obj.addProperty("icon", icon);
        obj.addProperty("lane", lane);
        obj.add("ids", ids);
        obj.addProperty("dailyCreditCap", dailyCreditCap);
        JsonArray tierArray = new JsonArray();
        for (JsonObject tier : tiers) {
            tierArray.add(tier);
        }
        obj.add("tiers", tierArray);
        return obj;
    }

    private static JsonArray ids(String... entries) {
        JsonArray array = new JsonArray();
        for (String entry : entries) {
            array.add(entry);
        }
        return array;
    }

    private static JsonObject tier(long threshold, int xp, int points, String... unlockItems) {
        return tier(threshold, xp, points, 0, unlockItems);
    }

    /** FIX-ECON: chunky (T4+) tiers pay 1–2 PERSONAL umbral shards on top of XP/points. */
    private static JsonObject tier(long threshold, int xp, int points, int shards, String... unlockItems) {
        JsonObject obj = new JsonObject();
        obj.addProperty("threshold", threshold);
        obj.addProperty("xp", xp);
        if (points > 0) {
            obj.addProperty("points", points);
        }
        if (shards > 0) {
            obj.addProperty("shards", shards);
        }
        if (unlockItems.length > 0) {
            JsonArray unlocks = new JsonArray();
            for (String item : unlockItems) {
                unlocks.add(item);
            }
            obj.add("unlockItems", unlocks);
        }
        return obj;
    }
}
