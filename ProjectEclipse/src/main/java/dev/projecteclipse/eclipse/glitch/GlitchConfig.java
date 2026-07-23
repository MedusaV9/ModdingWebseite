package dev.projecteclipse.eclipse.glitch;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.event.server.ServerAboutToStartEvent;

/**
 * Hot-reloadable balance for the fresh-ring glitched-mob path. The runtime file is
 * {@code config/eclipse/glitch.json}; missing files are created from {@link #defaults()}.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GlitchConfig {
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "glitch.json";

    /** P6 contract: string ids only, so this package has no compile-time entity dependency. */
    public static final List<String> DEFAULT_ENTITY_IDS = List.of(
            "eclipse:glitched_husk",
            "eclipse:glitched_hound",
            "eclipse:glitched_tick");

    public record Data(
            boolean enabled,
            int minDay,
            boolean nightOnly,
            int spawnIntervalTicks,
            int spawnAttemptsPerInterval,
            double spawnChancePerSample,
            int maxAlive,
            double minPlayerDistance,
            double maxPlayerDistance,
            int freshRingWindowTicks,
            boolean dropsEnabled,
            double dropChance,
            int dropMin,
            int dropMax,
            int lootingBonusMax,
            List<String> entityIds) {
        public Data {
            entityIds = List.copyOf(entityIds);
        }
    }

    private static volatile Data current = defaults();

    static {
        ReloadHooks.register("glitch", GlitchConfig::reload);
    }

    private GlitchConfig() {}

    public static Data get() {
        return current;
    }

    public static Data defaults() {
        return new Data(
                true,
                3,
                true,
                100,
                6,
                0.35D,
                12,
                18.0D,
                96.0D,
                3 * 24_000,
                true,
                1.0D,
                1,
                2,
                1,
                DEFAULT_ENTITY_IDS);
    }

    /** Re-reads the standard runtime config. Called by {@code /eclipse reload}. */
    public static void reload() {
        current = loadFrom(FMLPaths.CONFIGDIR.get().resolve(EclipseMod.MOD_ID));
        EclipseMod.LOGGER.info(
                "Glitch config loaded: enabled={}, cadence={}t, attempts={}, chance={}, cap={}, "
                        + "freshWindow={}t, drops={}-{}",
                current.enabled(), current.spawnIntervalTicks(), current.spawnAttemptsPerInterval(),
                current.spawnChancePerSample(), current.maxAlive(), current.freshRingWindowTicks(),
                current.dropMin(), current.dropMax());
    }

    /**
     * Loads from an explicit directory so gametests can use a temporary config without touching
     * the live server directory.
     */
    public static Data loadFrom(Path configDir) {
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            if (!Files.isRegularFile(file)) {
                Files.writeString(file, GSON.toJson(toJson(defaults())), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
                return defaults();
            }
            return parse(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                    .getAsJsonObject());
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {}; using built-in glitch defaults", file, e);
            return defaults();
        }
    }

    @SubscribeEvent
    public static void onServerAboutToStart(ServerAboutToStartEvent event) {
        reload();
    }

    private static Data parse(JsonObject root) {
        Data fallback = defaults();
        boolean enabled = bool(root, "enabled", fallback.enabled());
        int minDay = integer(root, "minDay", fallback.minDay(), 1, 10_000);
        boolean nightOnly = bool(root, "nightOnly", fallback.nightOnly());
        int interval = integer(root, "spawnIntervalTicks", fallback.spawnIntervalTicks(), 20, 72_000);
        int attempts = integer(root, "spawnAttemptsPerInterval",
                fallback.spawnAttemptsPerInterval(), 0, 128);
        double chance = decimal(root, "spawnChancePerSample",
                fallback.spawnChancePerSample(), 0.0D, 1.0D);
        int maxAlive = integer(root, "maxAlive", fallback.maxAlive(), 0, 1_024);
        double minDistance = decimal(root, "minPlayerDistance",
                fallback.minPlayerDistance(), 0.0D, 1_024.0D);
        double maxDistance = decimal(root, "maxPlayerDistance",
                fallback.maxPlayerDistance(), minDistance, 4_096.0D);
        int freshTicks = integer(root, "freshRingWindowTicks",
                fallback.freshRingWindowTicks(), 20, 100 * 24_000);
        boolean dropsEnabled = bool(root, "dropsEnabled", fallback.dropsEnabled());
        double dropChance = decimal(root, "dropChance", fallback.dropChance(), 0.0D, 1.0D);
        int dropMin = integer(root, "dropMin", fallback.dropMin(), 0, 64);
        int dropMax = integer(root, "dropMax", fallback.dropMax(), dropMin, 64);
        int lootingBonus = integer(root, "lootingBonusMax", fallback.lootingBonusMax(), 0, 64);
        List<String> ids = readEntityIds(root, fallback.entityIds());
        return new Data(enabled, minDay, nightOnly, interval, attempts, chance, maxAlive,
                minDistance, maxDistance, freshTicks, dropsEnabled, dropChance, dropMin, dropMax,
                lootingBonus, ids);
    }

    private static List<String> readEntityIds(JsonObject root, List<String> fallback) {
        if (!root.has("entityIds") || !root.get("entityIds").isJsonArray()) {
            return fallback;
        }
        List<String> ids = new ArrayList<>();
        for (JsonElement element : root.getAsJsonArray("entityIds")) {
            if (!element.isJsonPrimitive()) {
                continue;
            }
            String id = element.getAsString();
            if (ResourceLocation.tryParse(id) != null) {
                ids.add(id);
            } else {
                EclipseMod.LOGGER.warn("Ignoring malformed glitched entity id '{}'", id);
            }
        }
        return List.copyOf(ids);
    }

    private static JsonObject toJson(Data data) {
        JsonObject root = new JsonObject();
        root.addProperty("_comment", "Fresh-ring glitched mob spawning and shard drops. "
                + "Recipe day-gating remains in recipegate.json under eclipse:vitae_shard_glitch.");
        root.addProperty("enabled", data.enabled());
        root.addProperty("minDay", data.minDay());
        root.addProperty("nightOnly", data.nightOnly());
        root.addProperty("spawnIntervalTicks", data.spawnIntervalTicks());
        root.addProperty("spawnAttemptsPerInterval", data.spawnAttemptsPerInterval());
        root.addProperty("spawnChancePerSample", data.spawnChancePerSample());
        root.addProperty("maxAlive", data.maxAlive());
        root.addProperty("minPlayerDistance", data.minPlayerDistance());
        root.addProperty("maxPlayerDistance", data.maxPlayerDistance());
        root.addProperty("freshRingWindowTicks", data.freshRingWindowTicks());
        root.addProperty("dropsEnabled", data.dropsEnabled());
        root.addProperty("dropChance", data.dropChance());
        root.addProperty("dropMin", data.dropMin());
        root.addProperty("dropMax", data.dropMax());
        root.addProperty("lootingBonusMax", data.lootingBonusMax());
        JsonArray ids = new JsonArray();
        data.entityIds().forEach(ids::add);
        root.add("entityIds", ids);
        return root;
    }

    private static boolean bool(JsonObject object, String key, boolean fallback) {
        try {
            return object.has(key) ? object.get(key).getAsBoolean() : fallback;
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring malformed glitch config key '{}'", key);
            return fallback;
        }
    }

    private static int integer(JsonObject object, String key, int fallback, int min, int max) {
        try {
            int value = object.has(key) ? object.get(key).getAsInt() : fallback;
            return Math.max(min, Math.min(max, value));
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring malformed glitch config key '{}'", key);
            return fallback;
        }
    }

    private static double decimal(JsonObject object, String key, double fallback,
            double min, double max) {
        try {
            double value = object.has(key) ? object.get(key).getAsDouble() : fallback;
            if (!Double.isFinite(value)) {
                return fallback;
            }
            return Math.max(min, Math.min(max, value));
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("Ignoring malformed glitch config key '{}'", key);
            return fallback;
        }
    }
}
