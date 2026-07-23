package dev.projecteclipse.eclipse.anticheat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.Locale;
import java.util.Set;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Reloadable behavioral anti-xray settings from
 * {@code config/eclipse/anti_xray.json}. This is deliberately separate from
 * {@code anticheat.json}, which owns client mod-list screening.
 */
public final class AntiXrayConfig {
    public enum ActionMode {
        NOTIFY_ONLY,
        SLOWDOWN
    }

    /** Immutable snapshot read by the block-break hot path. */
    public record Data(
            boolean enabled,
            int windowSize,
            int minimumSamples,
            double softThreshold,
            double hardThreshold,
            Set<ResourceLocation> valuableOres,
            ActionMode actionMode,
            int slowdownDurationTicks,
            int slowdownAmplifier) {
        public Data {
            valuableOres = Set.copyOf(valuableOres);
        }
    }

    private static final String FILE_NAME = "anti_xray.json";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static volatile Data current;

    private AntiXrayConfig() {}

    /** Active immutable settings, loaded lazily on first use. */
    public static Data get() {
        Data snapshot = current;
        if (snapshot == null) {
            synchronized (AntiXrayConfig.class) {
                snapshot = current;
                if (snapshot == null) {
                    snapshot = loadFrom(defaultDirectory());
                    current = snapshot;
                }
            }
        }
        return snapshot;
    }

    /** Re-reads the standard config file for {@code /dev reload}. */
    public static synchronized void reload() {
        current = loadFrom(defaultDirectory());
        EclipseMod.LOGGER.info(
                "Behavioral anti-xray config loaded: enabled={}, window={}, minimum={}, "
                        + "thresholds={}/{}, ores={}, action={}",
                current.enabled(), current.windowSize(), current.minimumSamples(),
                current.softThreshold(), current.hardThreshold(),
                current.valuableOres().size(), current.actionMode());
    }

    /**
     * Loads from an explicit directory, creating a default file when absent.
     * Public for deterministic config gametests.
     */
    public static Data loadFrom(Path directory) {
        Path file = directory.resolve(FILE_NAME);
        try {
            Files.createDirectories(directory);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create anti-xray config directory {}", directory, e);
        }

        if (!Files.exists(file)) {
            Data defaults = defaults();
            try {
                Files.writeString(file, GSON.toJson(toJson(defaults)), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
            return defaults;
        }

        try {
            return fromJson(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)));
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
            return defaults();
        }
    }

    /**
     * Persists threshold changes made through {@code /dev anticheat threshold}.
     * The volatile snapshot changes only after the file write succeeds.
     */
    public static synchronized boolean updateThresholds(double soft, double hard) {
        if (!Double.isFinite(soft) || !Double.isFinite(hard)
                || soft < 0.0D || hard > 100.0D || soft > hard) {
            return false;
        }
        Data old = get();
        Data updated = new Data(old.enabled(), old.windowSize(), old.minimumSamples(),
                soft, hard, old.valuableOres(), old.actionMode(),
                old.slowdownDurationTicks(), old.slowdownAmplifier());
        Path file = defaultDirectory().resolve(FILE_NAME);
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, GSON.toJson(toJson(updated)), StandardCharsets.UTF_8);
            current = updated;
            return true;
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to persist anti-xray thresholds to {}", file, e);
            return false;
        }
    }

    /** Test hook; production settings always come from disk. */
    public static void injectForTests(Data snapshot) {
        current = snapshot;
    }

    /** Clears the lazy snapshot for test/server lifecycle cleanup. */
    public static void invalidate() {
        current = null;
    }

    public static Data defaults() {
        return new Data(
                true,
                32,
                8,
                70.0D,
                90.0D,
                Set.of(
                        ResourceLocation.parse("minecraft:diamond_ore"),
                        ResourceLocation.parse("minecraft:deepslate_diamond_ore"),
                        ResourceLocation.parse("minecraft:ancient_debris")),
                ActionMode.NOTIFY_ONLY,
                600,
                0);
    }

    private static Data fromJson(JsonElement json) {
        JsonObject object = json.getAsJsonObject();
        Data fallback = defaults();
        boolean enabled = boolOr(object, "enabled", fallback.enabled());
        int window = clamp(intOr(object, "windowSize", fallback.windowSize()), 1, 4096);
        int minimum = clamp(intOr(object, "minimumSamples", fallback.minimumSamples()), 1, window);
        double soft = clamp(doubleOr(object, "softThreshold", fallback.softThreshold()), 0.0D, 100.0D);
        double hard = clamp(doubleOr(object, "hardThreshold", fallback.hardThreshold()), soft, 100.0D);
        Set<ResourceLocation> ores = parseOres(object, fallback.valuableOres());
        ActionMode action = parseAction(stringOr(object, "actionMode", fallback.actionMode().name()));
        int duration = clamp(intOr(object, "slowdownDurationTicks",
                fallback.slowdownDurationTicks()), 20, 12_000);
        int amplifier = clamp(intOr(object, "slowdownAmplifier",
                fallback.slowdownAmplifier()), 0, 4);
        return new Data(enabled, window, minimum, soft, hard, ores, action, duration, amplifier);
    }

    private static JsonObject toJson(Data data) {
        JsonObject object = new JsonObject();
        object.addProperty("_comment",
                "Behavioral ore-exposure detection only. No packet/chunk obfuscation and never auto-bans.");
        object.addProperty("enabled", data.enabled());
        object.addProperty("windowSize", data.windowSize());
        object.addProperty("minimumSamples", data.minimumSamples());
        object.addProperty("softThreshold", data.softThreshold());
        object.addProperty("hardThreshold", data.hardThreshold());
        JsonArray ores = new JsonArray();
        data.valuableOres().stream().map(ResourceLocation::toString).sorted().forEach(ores::add);
        object.add("valuableOres", ores);
        object.addProperty("actionMode", data.actionMode().name().toLowerCase(Locale.ROOT));
        object.addProperty("slowdownDurationTicks", data.slowdownDurationTicks());
        object.addProperty("slowdownAmplifier", data.slowdownAmplifier());
        return object;
    }

    private static Set<ResourceLocation> parseOres(JsonObject object, Set<ResourceLocation> fallback) {
        if (!object.has("valuableOres") || !object.get("valuableOres").isJsonArray()) {
            return fallback;
        }
        Set<ResourceLocation> ores = new LinkedHashSet<>();
        for (JsonElement element : object.getAsJsonArray("valuableOres")) {
            ResourceLocation id = ResourceLocation.tryParse(element.getAsString());
            if (id != null) {
                ores.add(id);
            }
        }
        return Set.copyOf(ores);
    }

    private static ActionMode parseAction(String value) {
        try {
            return ActionMode.valueOf(value.strip().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            return ActionMode.NOTIFY_ONLY;
        }
    }

    private static Path defaultDirectory() {
        return FMLPaths.CONFIGDIR.get().resolve(EclipseMod.MOD_ID);
    }

    private static boolean boolOr(JsonObject object, String key, boolean fallback) {
        return object.has(key) ? object.get(key).getAsBoolean() : fallback;
    }

    private static int intOr(JsonObject object, String key, int fallback) {
        return object.has(key) ? object.get(key).getAsInt() : fallback;
    }

    private static double doubleOr(JsonObject object, String key, double fallback) {
        return object.has(key) ? object.get(key).getAsDouble() : fallback;
    }

    private static String stringOr(JsonObject object, String key, String fallback) {
        return object.has(key) ? object.get(key).getAsString() : fallback;
    }

    private static int clamp(int value, int minimum, int maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    private static double clamp(double value, double minimum, double maximum) {
        if (!Double.isFinite(value)) {
            return minimum;
        }
        return Math.max(minimum, Math.min(maximum, value));
    }
}
