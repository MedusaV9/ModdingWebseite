package dev.projecteclipse.eclipse.offering;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardConfig;
import dev.projecteclipse.eclipse.core.config.Localized;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Secret, server-only offering value table ({@code config/eclipse/offering_values.json}).
 * The generated defaults cover vanilla progression from junk through event relics; no value
 * or tier is ever sent before day resolution.
 */
public final class OfferingConfig {
    public record Data(
            Map<String, Integer> tiers,
            Map<String, String> byTag,
            Map<String, String> byItem,
            String defaultTier,
            double enchantedMultiplier,
            int renamedBonus,
            Set<String> junk,
            AwardConfig.Reward winnerReward,
            Localized bestOfferingTitle,
            Localized bestOfferingStatLine) {
        public Data {
            tiers = immutableOrderedMap(tiers);
            byTag = immutableOrderedMap(byTag);
            byItem = immutableOrderedMap(byItem);
            defaultTier = defaultTier == null ? "junk" : defaultTier;
            enchantedMultiplier = Math.clamp(enchantedMultiplier, 1.0D, 100.0D);
            renamedBonus = Math.max(0, renamedBonus);
            junk = Set.copyOf(junk);
            winnerReward = winnerReward == null ? AwardConfig.Reward.NONE : winnerReward;
            bestOfferingTitle = bestOfferingTitle == null
                    ? new Localized("Best Offering", "Bestes Opfer") : bestOfferingTitle;
            bestOfferingStatLine = bestOfferingStatLine == null
                    ? new Localized("made yesterday's most valuable unique offering ({value})",
                            "hat gestern das wertvollste einzigartige Opfer gebracht ({value})")
                    : bestOfferingStatLine;
        }

        private static <K, V> Map<K, V> immutableOrderedMap(Map<K, V> source) {
            return Collections.unmodifiableMap(new LinkedHashMap<>(source));
        }
    }

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    // JVM-global config snapshot; per-save offerings live in OfferingState.
    private static volatile Data data;
    private static volatile Path directoryOverride;

    private OfferingConfig() {}

    public static Data get() {
        Data current = data;
        if (current == null) {
            synchronized (OfferingConfig.class) {
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
        EclipseMod.LOGGER.info("Eclipse offering table loaded: {} item ids, {} tags, enchant x{}",
                data.byItem().size(), data.byTag().size(), data.enchantedMultiplier());
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
        Path file = directory.resolve("offering_values.json");
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
            EclipseMod.LOGGER.error("Failed to load {}; using built-in offering defaults", file, e);
            return defaults();
        }
    }

    private static Path configDirectory() {
        return directoryOverride != null ? directoryOverride : FMLPaths.CONFIGDIR.get().resolve("eclipse");
    }

    /** Built-in event values; deliberately broad so unlisted/modded items fail safe to junk. */
    public static Data defaults() {
        Map<String, Integer> tiers = new LinkedHashMap<>();
        tiers.put("junk", 0);
        tiers.put("common", 5);
        tiers.put("useful", 15);
        tiers.put("valuable", 40);
        tiers.put("rare", 100);
        tiers.put("epic", 250);

        Map<String, String> tags = new LinkedHashMap<>();
        tags.put("#minecraft:dirt", "junk");
        tags.put("#minecraft:sand", "junk");
        tags.put("#minecraft:logs", "common");
        tags.put("#minecraft:planks", "common");
        tags.put("#minecraft:coals", "common");
        tags.put("#minecraft:iron_ores", "useful");
        tags.put("#minecraft:copper_ores", "useful");
        tags.put("#minecraft:gold_ores", "valuable");
        tags.put("#minecraft:redstone_ores", "useful");
        tags.put("#minecraft:lapis_ores", "useful");
        tags.put("#minecraft:diamond_ores", "valuable");
        tags.put("#minecraft:emerald_ores", "valuable");
        tags.put("#minecraft:wool", "common");
        tags.put("#minecraft:flowers", "common");
        tags.put("#minecraft:music_discs", "rare");

        Map<String, String> items = new LinkedHashMap<>();
        // Explicit junk: familiar throwaways must never win through a tag/datapack surprise.
        put(items, "junk", "minecraft:dirt", "minecraft:coarse_dirt", "minecraft:rooted_dirt",
                "minecraft:podzol", "minecraft:sand", "minecraft:red_sand",
                "minecraft:cobblestone", "minecraft:stone", "minecraft:gravel",
                "minecraft:netherrack", "minecraft:rotten_flesh", "minecraft:poisonous_potato",
                "minecraft:spider_eye", "minecraft:bone", "minecraft:stick", "minecraft:bowl");
        put(items, "common", "minecraft:coal", "minecraft:charcoal", "minecraft:flint",
                "minecraft:clay_ball", "minecraft:brick", "minecraft:glass", "minecraft:leather",
                "minecraft:string", "minecraft:feather", "minecraft:paper", "minecraft:honeycomb",
                "minecraft:ink_sac", "minecraft:glow_ink_sac", "minecraft:prismarine_shard",
                "minecraft:wheat", "minecraft:gunpowder");
        put(items, "useful", "minecraft:iron_ingot", "minecraft:copper_ingot",
                "minecraft:redstone", "minecraft:lapis_lazuli", "minecraft:quartz",
                "minecraft:amethyst_shard", "minecraft:slime_ball", "minecraft:magma_cream",
                "minecraft:blaze_rod", "minecraft:phantom_membrane", "minecraft:scute",
                "minecraft:armadillo_scute", "minecraft:experience_bottle",
                "minecraft:golden_carrot", "minecraft:trial_key",
                "eclipse:umbral_shard");
        put(items, "valuable", "minecraft:gold_ingot", "minecraft:gold_block",
                "minecraft:emerald", "minecraft:ender_pearl",
                "minecraft:obsidian", "minecraft:crying_obsidian", "minecraft:ghast_tear",
                "minecraft:golden_apple", "minecraft:shulker_shell", "minecraft:nautilus_shell",
                "minecraft:prismarine_crystals", "minecraft:echo_shard", "minecraft:heart_of_the_sea",
                "minecraft:wither_skeleton_skull", "minecraft:iron_block", "minecraft:ender_eye",
                "eclipse:glitch_shard");
        put(items, "rare", "minecraft:diamond", "minecraft:emerald_block",
                "minecraft:netherite_scrap", "minecraft:netherite_ingot", "minecraft:trident",
                "minecraft:elytra", "minecraft:conduit", "minecraft:nether_star",
                "minecraft:heavy_core", "minecraft:ominous_trial_key", "minecraft:end_crystal",
                "minecraft:dragon_breath");
        put(items, "epic", "minecraft:diamond_block", "minecraft:netherite_block",
                "minecraft:enchanted_golden_apple",
                "minecraft:totem_of_undying", "minecraft:dragon_egg", "minecraft:beacon",
                "minecraft:mace", "minecraft:dragon_head",
                "eclipse:heart_fragment", "eclipse:herald_core",
                "eclipse:revive_sigil");

        Set<String> junk = new LinkedHashSet<>();
        junk.add("minecraft:dirt");
        junk.add("minecraft:coarse_dirt");
        junk.add("minecraft:rooted_dirt");
        junk.add("minecraft:podzol");
        junk.add("minecraft:cobblestone");
        junk.add("minecraft:stone");
        junk.add("minecraft:gravel");
        junk.add("minecraft:sand");
        junk.add("minecraft:red_sand");
        junk.add("minecraft:netherrack");
        junk.add("minecraft:rotten_flesh");
        junk.add("minecraft:poisonous_potato");

        return new Data(tiers, tags, items, "junk", 1.5D, 0, junk,
                new AwardConfig.Reward(300, 3, java.util.List.of()),
                new Localized("Best Offering", "Bestes Opfer"),
                new Localized("made yesterday's most valuable unique offering ({value})",
                        "hat gestern das wertvollste einzigartige Opfer gebracht ({value})"));
    }

    private static void put(Map<String, String> map, String tier, String... ids) {
        for (String id : ids) {
            map.put(id, tier);
        }
    }

    private static Data fromJson(JsonElement element) {
        JsonObject root = element.getAsJsonObject();
        Data defaults = defaults();
        Map<String, Integer> tiers = integerMap(root, "tiers", defaults.tiers());
        Map<String, String> tags = stringMap(root, "byTag", defaults.byTag());
        Map<String, String> items = stringMap(root, "byItem", defaults.byItem());
        String defaultTier = root.has("default") ? root.get("default").getAsString() : defaults.defaultTier();
        double enchanted = root.has("enchantedMultiplier")
                ? root.get("enchantedMultiplier").getAsDouble() : defaults.enchantedMultiplier();
        int renamed = defaults.renamedBonus();
        if (root.has("modifiers")) {
            JsonObject modifiers = root.getAsJsonObject("modifiers");
            renamed = modifiers.has("renamedBonus") ? modifiers.get("renamedBonus").getAsInt() : renamed;
        }
        Set<String> junk = new LinkedHashSet<>(defaults.junk());
        if (root.has("junk")) {
            junk.clear();
            for (JsonElement value : root.getAsJsonArray("junk")) {
                junk.add(value.getAsString());
            }
        }
        AwardConfig.Reward reward = root.has("winnerReward")
                ? parseReward(root.getAsJsonObject("winnerReward")) : defaults.winnerReward();
        Localized title = root.has("bestOfferingTitle")
                ? Localized.parse(root.get("bestOfferingTitle")) : defaults.bestOfferingTitle();
        Localized stat = root.has("bestOfferingStatLine")
                ? Localized.parse(root.get("bestOfferingStatLine")) : defaults.bestOfferingStatLine();
        return new Data(tiers, tags, items, defaultTier, enchanted, renamed, junk, reward, title, stat);
    }

    private static Map<String, Integer> integerMap(JsonObject root, String key, Map<String, Integer> fallback) {
        if (!root.has(key)) {
            return fallback;
        }
        Map<String, Integer> result = new LinkedHashMap<>();
        root.getAsJsonObject(key).entrySet().forEach(entry ->
                result.put(entry.getKey(), Math.max(0, entry.getValue().getAsInt())));
        return result;
    }

    private static Map<String, String> stringMap(JsonObject root, String key, Map<String, String> fallback) {
        if (!root.has(key)) {
            return fallback;
        }
        Map<String, String> result = new LinkedHashMap<>();
        root.getAsJsonObject(key).entrySet().forEach(entry ->
                result.put(entry.getKey(), entry.getValue().getAsString()));
        return result;
    }

    private static AwardConfig.Reward parseReward(JsonObject obj) {
        java.util.List<AwardConfig.ItemReward> items = new java.util.ArrayList<>();
        if (obj.has("items")) {
            for (JsonElement element : obj.getAsJsonArray("items")) {
                JsonObject item = element.getAsJsonObject();
                items.add(new AwardConfig.ItemReward(item.get("id").getAsString(),
                        item.has("count") ? item.get("count").getAsInt() : 1));
            }
        }
        return new AwardConfig.Reward(obj.has("skillXp") ? obj.get("skillXp").getAsInt() : 0,
                obj.has("shards") ? obj.get("shards").getAsInt() : 0, items);
    }

    private static JsonObject toJson(Data config) {
        JsonObject root = new JsonObject();
        JsonObject tiers = new JsonObject();
        config.tiers().forEach(tiers::addProperty);
        root.add("tiers", tiers);
        root.add("byTag", stringMapJson(config.byTag()));
        root.add("byItem", stringMapJson(config.byItem()));
        root.addProperty("default", config.defaultTier());
        root.addProperty("enchantedMultiplier", config.enchantedMultiplier());
        JsonObject modifiers = new JsonObject();
        modifiers.addProperty("renamedBonus", config.renamedBonus());
        root.add("modifiers", modifiers);
        com.google.gson.JsonArray junk = new com.google.gson.JsonArray();
        config.junk().forEach(junk::add);
        root.add("junk", junk);
        JsonObject reward = new JsonObject();
        reward.addProperty("skillXp", config.winnerReward().skillXp());
        reward.addProperty("shards", config.winnerReward().shards());
        com.google.gson.JsonArray rewardItems = new com.google.gson.JsonArray();
        for (AwardConfig.ItemReward item : config.winnerReward().items()) {
            JsonObject entry = new JsonObject();
            entry.addProperty("id", item.id());
            entry.addProperty("count", item.count());
            rewardItems.add(entry);
        }
        reward.add("items", rewardItems);
        root.add("winnerReward", reward);
        root.add("bestOfferingTitle", config.bestOfferingTitle().toJsonElement());
        root.add("bestOfferingStatLine", config.bestOfferingStatLine().toJsonElement());
        return root;
    }

    private static JsonObject stringMapJson(Map<String, String> values) {
        JsonObject object = new JsonObject();
        values.forEach(object::addProperty);
        return object;
    }
}
