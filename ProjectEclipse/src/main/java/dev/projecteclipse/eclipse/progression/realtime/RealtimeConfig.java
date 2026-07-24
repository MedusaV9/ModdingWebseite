package dev.projecteclipse.eclipse.progression.realtime;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalTime;
import java.time.ZoneId;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;

/**
 * Loads {@code config/eclipse/realtime.json} (R1). Created with plan defaults on first
 * run; hot-reloaded via the {@code ReloadHooks} bridge registered by
 * {@link RealtimeDayService} ({@code /eclipse reload} → {@code EclipseConfig.reload()}
 * → hooks). The parsed {@code zone}/{@code boundaryTime} are validated here so the
 * engine never touches raw strings.
 *
 * <pre>{@code
 * {
 *   "zone": "Europe/Berlin",
 *   "boundaryTime": "18:00",
 *   "autoArmOnStartEvent": true,
 *   "catchUpMaxDays": 13,
 *   "clientSyncSeconds": 5
 * }
 * }</pre>
 */
public final class RealtimeConfig {
    /** Parsed config values; {@code zone}/{@code boundaryTime} are already validated. */
    public record Config(ZoneId zone, LocalTime boundaryTime, boolean autoArmOnStartEvent,
            int catchUpMaxDays, int clientSyncSeconds) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "realtime.json";
    private static final String DEFAULT_ZONE = "Europe/Berlin";
    private static final String DEFAULT_BOUNDARY_TIME = "18:00";

    private static volatile Config config = defaultConfig();
    private static volatile Path configDir =
            net.neoforged.fml.loading.FMLPaths.CONFIGDIR.get().resolve("eclipse");

    private RealtimeConfig() {}

    public static Config get() {
        return config;
    }

    /** Redirects the loader for gametests (injectable base path, plan risk 8) and reloads. */
    public static void setConfigDirForTests(Path dir) {
        configDir = dir;
        reload();
    }

    /** Re-reads {@code realtime.json}, creating it with defaults when missing. */
    public static void reload() {
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            if (!Files.isRegularFile(file)) {
                Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
            }
            String json = Files.readString(file, StandardCharsets.UTF_8);
            config = parse(json);
            EclipseMod.LOGGER.info("RealtimeConfig loaded: zone={}, boundaryTime={}, autoArm={}, "
                            + "catchUpMaxDays={}, clientSyncSeconds={}",
                    config.zone(), config.boundaryTime(), config.autoArmOnStartEvent(),
                    config.catchUpMaxDays(), config.clientSyncSeconds());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("RealtimeConfig failed to load {}; using defaults", file, e);
            config = defaultConfig();
        }
    }

    static Config defaultConfig() {
        return new Config(ZoneId.of(DEFAULT_ZONE), LocalTime.of(18, 0), true, 13, 5);
    }

    private static JsonObject defaultJson() {
        JsonObject root = new JsonObject();
        root.addProperty("zone", DEFAULT_ZONE);
        root.addProperty("boundaryTime", DEFAULT_BOUNDARY_TIME);
        root.addProperty("autoArmOnStartEvent", true);
        root.addProperty("catchUpMaxDays", 13);
        root.addProperty("clientSyncSeconds", 5);
        return root;
    }

    private static Config parse(String json) {
        JsonObject root = JsonParser.parseString(json).getAsJsonObject();
        ZoneId zone;
        String zoneText = root.has("zone") ? root.get("zone").getAsString() : DEFAULT_ZONE;
        try {
            zone = ZoneId.of(zoneText);
        } catch (Exception e) {
            EclipseMod.LOGGER.warn("realtime.json: invalid zone '{}'; using {}", zoneText, DEFAULT_ZONE);
            zone = ZoneId.of(DEFAULT_ZONE);
        }
        LocalTime boundaryTime;
        String timeText = root.has("boundaryTime")
                ? root.get("boundaryTime").getAsString() : DEFAULT_BOUNDARY_TIME;
        try {
            boundaryTime = LocalTime.parse(timeText);
        } catch (Exception e) {
            EclipseMod.LOGGER.warn("realtime.json: invalid boundaryTime '{}'; using {}",
                    timeText, DEFAULT_BOUNDARY_TIME);
            boundaryTime = LocalTime.of(18, 0);
        }
        boolean autoArm = !root.has("autoArmOnStartEvent") || root.get("autoArmOnStartEvent").getAsBoolean();
        int catchUpMaxDays = root.has("catchUpMaxDays")
                ? Math.max(0, root.get("catchUpMaxDays").getAsInt()) : 13;
        int clientSyncSeconds = root.has("clientSyncSeconds")
                ? Math.max(1, root.get("clientSyncSeconds").getAsInt()) : 5;
        return new Config(zone, boundaryTime, autoArm, catchUpMaxDays, clientSyncSeconds);
    }
}
