package dev.projecteclipse.eclipse.worldgen.fog;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import javax.annotation.Nullable;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.storage.loot.LootTable;

/**
 * Dev-editable fog-storm chest loot table ids. Loaded from {@code fog_storm_loot.json} in the
 * save-local {@code eclipse/} directory (extracted from the per-save freeze). P5 commands call
 * {@link #setChestLoot} to swap tables live.
 */
public final class StormLootData {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final ResourceKey<LootTable> DEFAULT_TABLE =
            ResourceKey.create(net.minecraft.core.registries.Registries.LOOT_TABLE,
                    ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "fog_storm/storm_cache"));

    private static volatile Map<String, List<ResourceKey<LootTable>>> chestTables = Map.of();
    private static final Map<String, Map<Integer, ResourceKey<LootTable>>> liveOverrides = new ConcurrentHashMap<>();

    private StormLootData() {}

    /** Loot table for chest {@code idx} (0..2) at {@code siteId}. */
    public static ResourceKey<LootTable> chestTable(String siteId, int idx) {
        Map<Integer, ResourceKey<LootTable>> overrides = liveOverrides.get(siteId);
        if (overrides != null) {
            ResourceKey<LootTable> override = overrides.get(idx);
            if (override != null) {
                return override;
            }
        }
        List<ResourceKey<LootTable>> tables = chestTables.get(siteId);
        if (tables != null && idx >= 0 && idx < tables.size()) {
            return tables.get(idx);
        }
        return DEFAULT_TABLE;
    }

    /**
     * Swaps one chest's loot table at runtime (P5 {@code /eclipse-worldgen} seam). Does not
     * rewrite already-generated chests until they are re-opened or the site is re-placed.
     */
    public static void setChestLoot(String siteId, int idx, ResourceLocation table) {
        liveOverrides.computeIfAbsent(siteId, k -> new ConcurrentHashMap<>())
                .put(idx, ResourceKey.create(net.minecraft.core.registries.Registries.LOOT_TABLE, table));
        EclipseMod.LOGGER.info("StormLootData: {} chest {} -> {}", siteId, idx, table);
    }

    /** Re-reads {@code fog_storm_loot.json} from {@code configDir} (save-local after freeze). */
    public static synchronized void reload(Path configDir) {
        Path file = configDir.resolve("fog_storm_loot.json");
        if (!Files.isRegularFile(file)) {
            chestTables = defaultTables();
            writeDefaultIfAbsent(configDir, file);
            return;
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            chestTables = parseSites(root);
            EclipseMod.LOGGER.info("StormLootData: loaded loot tables for {} fog sites", chestTables.size());
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("StormLootData: failed to read {}; using defaults", file, e);
            chestTables = defaultTables();
        }
    }

    /** Clears live overrides when the server session ends. */
    public static void clearSession() {
        liveOverrides.clear();
        chestTables = Map.of();
    }

    private static Map<String, List<ResourceKey<LootTable>>> defaultTables() {
        Map<String, List<ResourceKey<LootTable>>> defaults = new LinkedHashMap<>();
        List<ResourceKey<LootTable>> triple = List.of(DEFAULT_TABLE, DEFAULT_TABLE, DEFAULT_TABLE);
        defaults.put("eclipse:fog_storm_1", triple);
        defaults.put("eclipse:fog_storm_2", triple);
        return Map.copyOf(defaults);
    }

    private static void writeDefaultIfAbsent(Path configDir, Path file) {
        try {
            Files.createDirectories(configDir);
            if (!Files.exists(file)) {
                JsonObject root = new JsonObject();
                root.addProperty("_comment", "Per-site fog storm chest loot (3 chests each). "
                        + "Validated-if-present enchant ids may reference P4 registrations.");
                JsonObject sites = new JsonObject();
                for (Map.Entry<String, List<ResourceKey<LootTable>>> entry : defaultTables().entrySet()) {
                    sites.add(entry.getKey(), tablesToJson(entry.getValue()));
                }
                root.add("sites", sites);
                Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            }
        } catch (IOException e) {
            EclipseMod.LOGGER.warn("StormLootData: failed to write default {}", file, e);
        }
    }

    private static Map<String, List<ResourceKey<LootTable>>> parseSites(JsonObject root) {
        if (!root.has("sites")) {
            return defaultTables();
        }
        JsonObject sites = root.getAsJsonObject("sites");
        Map<String, List<ResourceKey<LootTable>>> parsed = new LinkedHashMap<>();
        for (Map.Entry<String, JsonElement> entry : sites.entrySet()) {
            List<ResourceKey<LootTable>> tables = parseTableList(entry.getValue());
            if (!tables.isEmpty()) {
                parsed.put(entry.getKey(), List.copyOf(tables));
            }
        }
        return parsed.isEmpty() ? defaultTables() : Map.copyOf(parsed);
    }

    private static List<ResourceKey<LootTable>> parseTableList(JsonElement element) {
        List<ResourceKey<LootTable>> tables = new ArrayList<>(3);
        if (element.isJsonArray()) {
            for (JsonElement item : element.getAsJsonArray()) {
                ResourceLocation loc = ResourceLocation.tryParse(item.getAsString());
                if (loc != null) {
                    tables.add(ResourceKey.create(net.minecraft.core.registries.Registries.LOOT_TABLE, loc));
                }
            }
        }
        while (tables.size() < 3) {
            tables.add(DEFAULT_TABLE);
        }
        return tables.subList(0, 3);
    }

    private static JsonArray tablesToJson(List<ResourceKey<LootTable>> tables) {
        JsonArray array = new JsonArray();
        for (ResourceKey<LootTable> table : tables) {
            array.add(table.location().toString());
        }
        return array;
    }
}
