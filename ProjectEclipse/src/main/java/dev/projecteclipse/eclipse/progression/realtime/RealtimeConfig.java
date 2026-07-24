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
 *   "configVersion": 2,
 *   "zone": "Europe/Berlin",
 *   "boundaryTime": "18:00",
 *   "cadenceMode": "interval",
 *   "intervalHours": 2.0,
 *   "autoArmOnStartEvent": true,
 *   "catchUpMaxDays": 13,
 *   "clientSyncSeconds": 5
 * }
 * }</pre>
 *
 * <p>D6: {@code cadenceMode} selects how the next boundary is derived — {@code "daily"}
 * (the classic {@code boundaryTime}-in-{@code zone} chain) or {@code "interval"}
 * (every {@code intervalHours} real hours, the "phase every 2 h" experience).
 * {@code intervalHours} is only read in interval mode. FIX-ECON flipped the DEFAULT to
 * {@code interval}/2.0 h — daily mode stays fully available via config or
 * {@code /dev phase daily}.</p>
 *
 * <p>FIX-ECON (EVAL-SAT-S #1 pattern): {@code configVersion} gates a
 * backup-and-regenerate migration — a file older than {@link #CONFIG_VERSION} is copied
 * to {@code realtime.json.bak-v<oldVersion>} and rewritten with current defaults.</p>
 */
public final class RealtimeConfig {
    /** D6 cadence selector: once per real day at {@code boundaryTime}, or every N hours. */
    public enum CadenceMode {
        DAILY, INTERVAL;

        /** Lenient parse; anything unrecognized falls back to the {@link #INTERVAL} default. */
        static CadenceMode fromString(String raw) {
            return "daily".equalsIgnoreCase(raw) ? DAILY : INTERVAL;
        }

        public String id() {
            return name().toLowerCase(java.util.Locale.ROOT);
        }
    }

    /** Parsed config values; {@code zone}/{@code boundaryTime} are already validated. */
    public record Config(ZoneId zone, LocalTime boundaryTime, CadenceMode cadenceMode,
            double intervalHours, boolean autoArmOnStartEvent,
            int catchUpMaxDays, int clientSyncSeconds) {

        /** Interval cadence length in millis, clamped ≥ 5 s (plan D6). */
        public long intervalMillis() {
            return Math.max(5_000L, (long) (intervalHours * 3_600_000.0));
        }
    }

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "realtime.json";
    private static final String DEFAULT_ZONE = "Europe/Berlin";
    private static final String DEFAULT_BOUNDARY_TIME = "18:00";
    private static final double DEFAULT_INTERVAL_HOURS = 2.0;
    /**
     * Version 2 = the FIX-ECON interval/2.0h cadence default. Files without a
     * {@code configVersion} field count as version 1 (the old daily-default era) and are
     * backed up + regenerated on load.
     */
    private static final int CONFIG_VERSION = 2;

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

    /**
     * Re-reads {@code realtime.json}, creating it with defaults when missing. FIX-ECON
     * (EVAL-SAT-S #1 pattern): a file whose {@code configVersion} is older than
     * {@link #CONFIG_VERSION} is backed up to {@code realtime.json.bak-v<oldVersion>} and
     * regenerated with the current defaults (interval/2.0h cadence), logged clearly.
     */
    public static void reload() {
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            if (!Files.isRegularFile(file)) {
                Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
            } else {
                migrateIfOutdated(file);
            }
            String json = Files.readString(file, StandardCharsets.UTF_8);
            config = parse(json);
            EclipseMod.LOGGER.info("RealtimeConfig loaded: zone={}, boundaryTime={}, cadenceMode={}, "
                            + "intervalHours={}, autoArm={}, catchUpMaxDays={}, clientSyncSeconds={}",
                    config.zone(), config.boundaryTime(), config.cadenceMode().id(),
                    config.intervalHours(), config.autoArmOnStartEvent(),
                    config.catchUpMaxDays(), config.clientSyncSeconds());
        } catch (Exception e) {
            EclipseMod.LOGGER.error("RealtimeConfig failed to load {}; using defaults", file, e);
            config = defaultConfig();
        }
    }

    /**
     * D6: switches the cadence and persists it to {@code realtime.json} (read-modify-write
     * preserving unrelated fields). {@code intervalHours} is only rewritten when
     * {@code mode == INTERVAL}; a file write failure keeps the in-memory switch so the
     * running server still honors the operator's command.
     */
    public static Config setCadence(CadenceMode mode, double intervalHours) {
        Config current = config;
        double hours = mode == CadenceMode.INTERVAL
                ? Math.max(5.0 / 3600.0, intervalHours) : current.intervalHours();
        config = new Config(current.zone(), current.boundaryTime(), mode, hours,
                current.autoArmOnStartEvent(), current.catchUpMaxDays(), current.clientSyncSeconds());
        Path file = configDir.resolve(FILE_NAME);
        try {
            Files.createDirectories(configDir);
            JsonObject root = Files.isRegularFile(file)
                    ? JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject()
                    : defaultJson();
            root.addProperty("cadenceMode", mode.id());
            root.addProperty("intervalHours", hours);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("RealtimeConfig: cadence persisted — mode={}, intervalHours={}",
                    mode.id(), hours);
        } catch (Exception e) {
            EclipseMod.LOGGER.error("RealtimeConfig: cadence switched in memory but persisting {} failed",
                    file, e);
        }
        return config;
    }

    /**
     * FIX-ECON version-gated migration: an on-disk file older than {@link #CONFIG_VERSION}
     * (missing field = v1) is copied aside as {@code realtime.json.bak-v<oldVersion>} and
     * replaced by the current defaults — nothing is preserved, the new cadence default
     * replaces the old file wholesale (same pattern as {@code GoalConfig}).
     */
    private static void migrateIfOutdated(Path file) throws java.io.IOException {
        int fileVersion = 1;
        try {
            JsonObject root = JsonParser.parseString(
                    Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            if (root.has("configVersion")) {
                fileVersion = root.get("configVersion").getAsInt();
            }
        } catch (Exception e) {
            EclipseMod.LOGGER.warn("realtime.json: unreadable while checking configVersion; "
                    + "treating as v1", e);
        }
        if (fileVersion >= CONFIG_VERSION) {
            return;
        }
        Path backup = file.resolveSibling(FILE_NAME + ".bak-v" + fileVersion);
        Files.copy(file, backup, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
        EclipseMod.LOGGER.warn("realtime.json was config version {} (< {}): backed the old file "
                + "up to {} and regenerated defaults (cadenceMode=interval, intervalHours=2.0). "
                + "Re-apply any custom tuning by editing the new file.",
                fileVersion, CONFIG_VERSION, backup.getFileName());
    }

    static Config defaultConfig() {
        return new Config(ZoneId.of(DEFAULT_ZONE), LocalTime.of(18, 0), CadenceMode.INTERVAL,
                DEFAULT_INTERVAL_HOURS, true, 13, 5);
    }

    private static JsonObject defaultJson() {
        JsonObject root = new JsonObject();
        root.addProperty("configVersion", CONFIG_VERSION);
        root.addProperty("zone", DEFAULT_ZONE);
        root.addProperty("boundaryTime", DEFAULT_BOUNDARY_TIME);
        // FIX-ECON default: a fresh phase every 2 real hours; daily stays available
        // ("cadenceMode": "daily" or /dev phase daily).
        root.addProperty("cadenceMode", CadenceMode.INTERVAL.id());
        root.addProperty("intervalHours", DEFAULT_INTERVAL_HOURS);
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
        CadenceMode cadenceMode = root.has("cadenceMode")
                ? CadenceMode.fromString(root.get("cadenceMode").getAsString()) : CadenceMode.INTERVAL;
        double intervalHours = DEFAULT_INTERVAL_HOURS;
        if (root.has("intervalHours")) {
            double parsed = root.get("intervalHours").getAsDouble();
            if (parsed > 0.0) {
                intervalHours = parsed;
            } else {
                EclipseMod.LOGGER.warn("realtime.json: invalid intervalHours '{}'; using {}",
                        parsed, DEFAULT_INTERVAL_HOURS);
            }
        }
        boolean autoArm = !root.has("autoArmOnStartEvent") || root.get("autoArmOnStartEvent").getAsBoolean();
        int catchUpMaxDays = root.has("catchUpMaxDays")
                ? Math.max(0, root.get("catchUpMaxDays").getAsInt()) : 13;
        int clientSyncSeconds = root.has("clientSyncSeconds")
                ? Math.max(1, root.get("clientSyncSeconds").getAsInt()) : 5;
        return new Config(zone, boundaryTime, cadenceMode, intervalHours, autoArm,
                catchUpMaxDays, clientSyncSeconds);
    }
}
