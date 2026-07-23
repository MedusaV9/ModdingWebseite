package dev.projecteclipse.eclipse.awards;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
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
import dev.projecteclipse.eclipse.core.config.Localized;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Server-only, hot-reloadable {@code config/eclipse/awards.json}. Category titles and stat
 * templates remain on the server until the reveal payload is built, keeping the daily draw
 * hidden from clients.
 */
public final class AwardConfig {
    public record ItemReward(String id, int count) {
        public ItemReward {
            id = id == null ? "" : id;
            count = Math.max(0, count);
        }
    }

    public record Reward(int skillXp, int shards, List<ItemReward> items) {
        public static final Reward NONE = new Reward(0, 0, List.of());

        public Reward {
            skillXp = Math.max(0, skillXp);
            shards = Math.max(0, shards);
            items = List.copyOf(items);
        }

        public Reward split(int winners) {
            return new Reward(AwardMath.splitReward(skillXp, winners),
                    AwardMath.splitReward(shards, winners), items);
        }

        public boolean isEmpty() {
            return skillXp == 0 && shards == 0 && items.isEmpty();
        }
    }

    public record Category(
            String id,
            String metric,
            AwardMath.Order order,
            int weight,
            Localized title,
            Localized statLine,
            String rewardType,
            Reward rewardOverride,
            Set<String> dayTags,
            boolean requiresPlaytime,
            boolean booby,
            boolean mobPoolByDay,
            List<String> orePool) {
        public Category {
            id = id == null ? "" : id;
            metric = metric == null ? "" : metric;
            weight = Math.max(0, weight);
            title = title == null ? Localized.of(id) : title;
            statLine = statLine == null ? Localized.of("{value}") : statLine;
            rewardType = rewardType == null ? "" : rewardType;
            rewardOverride = rewardOverride == null ? Reward.NONE : rewardOverride;
            dayTags = Set.copyOf(dayTags);
            orePool = List.copyOf(orePool);
        }

        public Reward reward(Map<String, Reward> rewardTables) {
            return rewardOverride.isEmpty()
                    ? rewardTables.getOrDefault(rewardType, Reward.NONE)
                    : rewardOverride;
        }

        public AwardMath.Choice choice() {
            return new AwardMath.Choice(id, weight, dayTags);
        }
    }

    public record Data(
            int categoriesPerDay,
            int minPlaytimeSeconds,
            int maxRerollsPerDay,
            Map<String, Reward> rewardTables,
            List<Category> categories,
            Map<Integer, Set<String>> dayThemes) {
        public Data {
            categoriesPerDay = Math.clamp(categoriesPerDay, 1, 8);
            minPlaytimeSeconds = Math.max(0, minPlaytimeSeconds);
            maxRerollsPerDay = Math.clamp(maxRerollsPerDay, 0, 100);
            rewardTables = Map.copyOf(rewardTables);
            categories = List.copyOf(categories);
            Map<Integer, Set<String>> themes = new LinkedHashMap<>();
            dayThemes.forEach((day, tags) -> themes.put(day, Set.copyOf(tags)));
            dayThemes = Map.copyOf(themes);
        }

        public Set<String> themesFor(int day) {
            return dayThemes.getOrDefault(day, Set.of());
        }
    }

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    // JVM-global config snapshot; per-save choices/resolutions live in AwardsState.
    private static volatile Data data;
    private static volatile Path directoryOverride;

    private AwardConfig() {}

    public static Data get() {
        Data current = data;
        if (current == null) {
            synchronized (AwardConfig.class) {
                current = data;
                if (current == null) {
                    current = loadFrom(configDirectory());
                    data = current;
                }
            }
        }
        return current;
    }

    public static synchronized void reload() {
        data = loadFrom(configDirectory());
        EclipseMod.LOGGER.info("Eclipse awards config loaded: {} categories, {} per day, {}s minimum playtime",
                data.categories().size(), data.categoriesPerDay(), data.minPlaytimeSeconds());
    }

    public static synchronized void setDirectoryOverride(Path directory) {
        directoryOverride = directory;
        reload();
    }

    public static void injectForTests(Data snapshot) {
        data = snapshot;
    }

    public static void invalidate() {
        data = null;
        directoryOverride = null;
    }

    public static Data loadFrom(Path directory) {
        Path file = directory.resolve("awards.json");
        try {
            Files.createDirectories(directory);
            if (!Files.exists(file)) {
                Data defaults = defaults();
                Files.writeString(file, GSON.toJson(toJson(defaults)), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
                return defaults;
            }
            return fromJson(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {}; using built-in award defaults", file, e);
            return defaults();
        }
    }

    private static Path configDirectory() {
        return directoryOverride != null ? directoryOverride : FMLPaths.CONFIGDIR.get().resolve("eclipse");
    }

    public static Data defaults() {
        Map<String, Reward> rewards = new LinkedHashMap<>();
        rewards.put("combat", new Reward(400, 4, List.of()));
        rewards.put("industry", new Reward(350, 3, List.of()));
        rewards.put("build", new Reward(300, 3, List.of()));
        rewards.put("explore", new Reward(350, 3, List.of()));
        rewards.put("altar", new Reward(300, 4, List.of()));
        rewards.put("consolation", new Reward(50, 1, List.of()));

        List<Category> categories = List.of(
                category("most_kills", "kill_total", "combat", 10, "Bloodiest Blade", "Blutigste Klinge",
                        "killed the most creatures yesterday ({value})",
                        "hat gestern die meisten Kreaturen getötet ({value})", Set.of("combat")),
                category("most_sheep", "kill:minecraft:sheep", "combat", 5, "Flock's Bane", "Schrecken der Herde",
                        "killed the most sheep yesterday ({value})",
                        "hat gestern am meisten Schafe getötet ({value})", Set.of("combat")),
                new Category("mob_specialist", "kill:$mob", AwardMath.Order.MAX, 6,
                        new Localized("$TARGET Hunter", "$TARGET-Jäger"),
                        new Localized("hunted the most $TARGET yesterday ({value})",
                                "hat gestern am meisten $TARGET gejagt ({value})"),
                        "combat", Reward.NONE, Set.of("combat"), false, false, true, List.of()),
                category("most_mined", "mine_total", "industry", 10, "Stonebreaker", "Steinbrecher",
                        "mined the most natural blocks yesterday ({value})",
                        "hat gestern die meisten natürlichen Blöcke abgebaut ({value})", Set.of("mining")),
                new Category("ore_baron", "mine:$ore", AwardMath.Order.MAX, 7,
                        new Localized("Ore Baron", "Erzbaron"),
                        new Localized("mined the most $TARGET yesterday ({value})",
                                "hat gestern am meisten $TARGET abgebaut ({value})"),
                        "industry", Reward.NONE, Set.of("mining"), false, false, false,
                        List.of("minecraft:coal_ore", "minecraft:deepslate_coal_ore",
                                "minecraft:iron_ore", "minecraft:deepslate_iron_ore",
                                "minecraft:copper_ore", "minecraft:deepslate_copper_ore",
                                "minecraft:gold_ore", "minecraft:deepslate_gold_ore",
                                "minecraft:redstone_ore", "minecraft:deepslate_redstone_ore",
                                "minecraft:lapis_ore", "minecraft:deepslate_lapis_ore",
                                "minecraft:diamond_ore", "minecraft:deepslate_diamond_ore",
                                "minecraft:emerald_ore", "minecraft:deepslate_emerald_ore",
                                "minecraft:nether_gold_ore", "minecraft:nether_quartz_ore",
                                "minecraft:ancient_debris")),
                category("master_builder", "place_total", "build", 12, "Master Builder", "Baumeister",
                        "placed the most blocks yesterday ({value})",
                        "hat gestern die meisten Blöcke gesetzt ({value})", Set.of("build")),
                category("architect", "place_types", "build", 8, "Architect", "Architekt",
                        "used the widest variety of blocks yesterday ({value})",
                        "hat gestern die größte Blockvielfalt genutzt ({value})", Set.of("build")),
                category("marathon", "dist_cm", "explore", 10, "Marathon", "Marathon",
                        "travelled the farthest yesterday ({value})",
                        "ist gestern am weitesten gereist ({value})", Set.of("explore")),
                category("globetrotter", "biomes", "explore", 7, "Globetrotter", "Weltenwanderer",
                        "discovered the most new biomes yesterday ({value})",
                        "hat gestern die meisten neuen Biome entdeckt ({value})", Set.of("explore")),
                category("trailblazer", "chunks_new", "explore", 7, "Trailblazer", "Pfadfinder",
                        "explored the most new chunks yesterday ({value})",
                        "hat gestern die meisten neuen Chunks erkundet ({value})", Set.of("explore")),
                category("industrialist", "craft_total", "industry", 8, "Industrialist", "Industrieller",
                        "crafted the most items yesterday ({value})",
                        "hat gestern die meisten Gegenstände hergestellt ({value})", Set.of("craft")),
                category("furnace_lord", "smelt_total", "industry", 7, "Furnace Lord", "Herr der Öfen",
                        "smelted the most items yesterday ({value})",
                        "hat gestern die meisten Gegenstände geschmolzen ({value})", Set.of("craft")),
                category("gladiator", "dmg_dealt", "combat", 9, "Gladiator", "Gladiator",
                        "dealt the most damage yesterday ({value})",
                        "hat gestern den meisten Schaden verursacht ({value})", Set.of("combat")),
                new Category("untouchable", "dmg_taken", AwardMath.Order.MIN, 7,
                        new Localized("Untouchable", "Unberührbar"),
                        new Localized("took the least damage yesterday ({value})",
                                "hat gestern den wenigsten Schaden erlitten ({value})"),
                        "explore", Reward.NONE, Set.of("combat"), true, false, false, List.of()),
                category("devout", "altar_value", "altar", 8, "Most Devout", "Hingebungsvollster",
                        "gave the altar the most value yesterday ({value})",
                        "hat gestern dem Altar den größten Wert geopfert ({value})", Set.of("altar")),
                category("banker", "shards_banked", "altar", 6, "Shard Banker", "Splitterbankier",
                        "banked the most Umbral Shards yesterday ({value})",
                        "hat gestern die meisten Umbral-Splitter eingelagert ({value})", Set.of("altar")),
                category("quest_zealot", "quests_done", "explore", 7, "Quest Zealot", "Quest-Eiferer",
                        "completed the most quests yesterday ({value})",
                        "hat gestern die meisten Quests abgeschlossen ({value})", Set.of("quest")),
                category("deep_diver", "depth_min_y", "explore", 6, "Deep Diver", "Tiefengänger",
                        "reached the greatest depth yesterday ({value})",
                        "hat gestern die größte Tiefe erreicht ({value})", Set.of("mining")),
                category("rancher", "breed_total", "industry", 5, "Rancher", "Viehzüchter",
                        "bred the most animals yesterday ({value})",
                        "hat gestern die meisten Tiere gezüchtet ({value})", Set.of("nature")),
                category("merchant", "trade_total", "industry", 5, "Merchant Prince", "Handelsfürst",
                        "completed the most trades yesterday ({value})",
                        "hat gestern die meisten Handelsgeschäfte abgeschlossen ({value})", Set.of("trade")),
                category("mainstay", "mains_done", "altar", 7, "Mainstay", "Stütze des Teams",
                        "completed the most main goals yesterday ({value})",
                        "hat gestern die meisten Hauptziele abgeschlossen ({value})", Set.of("quest")),
                category("side_seeker", "sides_done", "explore", 6, "Side Seeker", "Nebenpfad-Sucher",
                        "completed the most side goals yesterday ({value})",
                        "hat gestern die meisten Nebenziele abgeschlossen ({value})", Set.of("quest")),
                category("personal_best", "personals_done", "explore", 6,
                        "Personal Best", "Persönliche Bestleistung",
                        "completed the most personal quests yesterday ({value})",
                        "hat gestern die meisten persönlichen Quests abgeschlossen ({value})",
                        Set.of("quest")),
                new Category("cursed", "death", AwardMath.Order.MAX, 4,
                        new Localized("Most Cursed", "Meistverflucht"),
                        new Localized("fell most often yesterday ({value})",
                                "ist gestern am häufigsten gefallen ({value})"),
                        "consolation", Reward.NONE, Set.of("combat"), true, true, false, List.of()));

        Map<Integer, Set<String>> themes = Map.of(
                7, Set.of("combat"),
                10, Set.of("build"),
                14, Set.of("combat", "altar"));
        return new Data(3, 1_800, 5, rewards, categories, themes);
    }

    private static Category category(String id, String metric, String rewardType, int weight,
            String titleEn, String titleDe, String statEn, String statDe, Set<String> tags) {
        return new Category(id, metric, AwardMath.Order.MAX, weight,
                new Localized(titleEn, titleDe), new Localized(statEn, statDe),
                rewardType, Reward.NONE, tags, false, false, false, List.of());
    }

    private static Data fromJson(JsonElement element) {
        JsonObject root = element.getAsJsonObject();
        Data defaults = defaults();
        int perDay = intValue(root, "categoriesPerDay", defaults.categoriesPerDay());
        int minPlaytime = intValue(root, "minPlaytimeSeconds", defaults.minPlaytimeSeconds());
        int rerolls = intValue(root, "maxRerollsPerDay", defaults.maxRerollsPerDay());

        Map<String, Reward> rewardTables = new LinkedHashMap<>(defaults.rewardTables());
        if (root.has("rewardTables")) {
            rewardTables.clear();
            for (var entry : root.getAsJsonObject("rewardTables").entrySet()) {
                rewardTables.put(entry.getKey(), parseReward(entry.getValue().getAsJsonObject()));
            }
        }

        List<Category> categories = new ArrayList<>();
        if (root.has("categories")) {
            Set<String> ids = new LinkedHashSet<>();
            for (JsonElement categoryElement : root.getAsJsonArray("categories")) {
                Category category = parseCategory(categoryElement.getAsJsonObject());
                if (category.id().isBlank() || category.metric().isBlank() || !ids.add(category.id())) {
                    throw new IllegalArgumentException("award category ids/metrics must be non-empty and unique");
                }
                categories.add(category);
            }
        } else {
            categories.addAll(defaults.categories());
        }

        Map<Integer, Set<String>> themes = new LinkedHashMap<>();
        JsonObject themeObject = root.has("dayThemes") ? root.getAsJsonObject("dayThemes") : null;
        if (themeObject == null) {
            themes.putAll(defaults.dayThemes());
        } else {
            for (var entry : themeObject.entrySet()) {
                themes.put(Integer.parseInt(entry.getKey()), parseStrings(entry.getValue().getAsJsonArray()));
            }
        }
        return new Data(perDay, minPlaytime, rerolls, rewardTables, categories, themes);
    }

    private static Category parseCategory(JsonObject obj) {
        String id = stringValue(obj, "id", "");
        String metric = stringValue(obj, "metric", "");
        AwardMath.Order order = AwardMath.Order.parse(stringValue(obj, "order", "max"));
        int weight = intValue(obj, "weight", 1);
        Localized title = Localized.parse(obj.get("title"));
        Localized stat = Localized.parse(obj.get("statLine"));
        String rewardType = stringValue(obj, "rewardType", "");
        Reward reward = obj.has("reward") ? parseReward(obj.getAsJsonObject("reward")) : Reward.NONE;
        Set<String> tags = obj.has("dayTags") ? parseStrings(obj.getAsJsonArray("dayTags")) : Set.of();
        boolean playtime = boolValue(obj, "requiresPlaytime", false);
        boolean booby = boolValue(obj, "booby", false);
        boolean mobPool = boolValue(obj, "mobPoolByDay", false);
        List<String> ores = obj.has("orePool") ? List.copyOf(parseStrings(obj.getAsJsonArray("orePool"))) : List.of();
        return new Category(id, metric, order, weight, title, stat, rewardType, reward, tags,
                playtime, booby, mobPool, ores);
    }

    private static Reward parseReward(JsonObject obj) {
        List<ItemReward> items = new ArrayList<>();
        if (obj.has("items")) {
            for (JsonElement element : obj.getAsJsonArray("items")) {
                JsonObject item = element.getAsJsonObject();
                items.add(new ItemReward(stringValue(item, "id", ""), intValue(item, "count", 1)));
            }
        }
        return new Reward(intValue(obj, "skillXp", 0), intValue(obj, "shards", 0), items);
    }

    private static JsonObject toJson(Data config) {
        JsonObject root = new JsonObject();
        root.addProperty("categoriesPerDay", config.categoriesPerDay());
        root.addProperty("minPlaytimeSeconds", config.minPlaytimeSeconds());
        root.addProperty("maxRerollsPerDay", config.maxRerollsPerDay());
        JsonObject rewards = new JsonObject();
        config.rewardTables().forEach((id, reward) -> rewards.add(id, rewardJson(reward)));
        root.add("rewardTables", rewards);
        JsonArray categories = new JsonArray();
        for (Category category : config.categories()) {
            JsonObject obj = new JsonObject();
            obj.addProperty("id", category.id());
            obj.addProperty("metric", category.metric());
            obj.addProperty("order", category.order().name().toLowerCase(java.util.Locale.ROOT));
            obj.addProperty("weight", category.weight());
            obj.add("title", category.title().toJsonElement());
            obj.add("statLine", category.statLine().toJsonElement());
            if (!category.rewardType().isBlank()) {
                obj.addProperty("rewardType", category.rewardType());
            }
            if (!category.rewardOverride().isEmpty()) {
                obj.add("reward", rewardJson(category.rewardOverride()));
            }
            obj.add("dayTags", stringsJson(category.dayTags()));
            if (category.requiresPlaytime()) {
                obj.addProperty("requiresPlaytime", true);
            }
            if (category.booby()) {
                obj.addProperty("booby", true);
            }
            if (category.mobPoolByDay()) {
                obj.addProperty("mobPoolByDay", true);
            }
            if (!category.orePool().isEmpty()) {
                obj.add("orePool", stringsJson(category.orePool()));
            }
            categories.add(obj);
        }
        root.add("categories", categories);
        JsonObject themes = new JsonObject();
        config.dayThemes().forEach((day, tags) -> themes.add(Integer.toString(day), stringsJson(tags)));
        root.add("dayThemes", themes);
        return root;
    }

    private static JsonObject rewardJson(Reward reward) {
        JsonObject obj = new JsonObject();
        obj.addProperty("skillXp", reward.skillXp());
        obj.addProperty("shards", reward.shards());
        JsonArray items = new JsonArray();
        for (ItemReward item : reward.items()) {
            JsonObject entry = new JsonObject();
            entry.addProperty("id", item.id());
            entry.addProperty("count", item.count());
            items.add(entry);
        }
        obj.add("items", items);
        return obj;
    }

    private static JsonArray stringsJson(Iterable<String> values) {
        JsonArray array = new JsonArray();
        values.forEach(array::add);
        return array;
    }

    private static Set<String> parseStrings(JsonArray array) {
        Set<String> values = new LinkedHashSet<>();
        for (JsonElement value : array) {
            String text = value.getAsString().trim();
            if (!text.isEmpty()) {
                values.add(text);
            }
        }
        return values;
    }

    private static String stringValue(JsonObject obj, String key, String fallback) {
        return obj.has(key) ? obj.get(key).getAsString() : fallback;
    }

    private static int intValue(JsonObject obj, String key, int fallback) {
        return obj.has(key) ? obj.get(key).getAsInt() : fallback;
    }

    private static boolean boolValue(JsonObject obj, String key, boolean fallback) {
        return obj.has(key) ? obj.get(key).getAsBoolean() : fallback;
    }
}
