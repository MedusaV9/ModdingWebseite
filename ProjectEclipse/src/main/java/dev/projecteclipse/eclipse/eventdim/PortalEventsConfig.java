package dev.projecteclipse.eclipse.eventdim;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.atomic.AtomicBoolean;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/portal_events.json} (V5-FIXGUARD / EVAL-SAT-F #3 —
 * the portal auto-roll gate). Missing file is created with defaults on first load; parse
 * errors keep the previous values (temp-parse-then-swap, the {@code XboxEventConfig}
 * pattern). Registered in {@link ReloadHooks} so {@code /eclipse reload} and
 * {@code /dev reload} both re-read it.
 *
 * <pre>{@code
 * {
 *   "autoRoll": false,
 *   "minDay": 4
 * }
 * }</pre>
 *
 * <ul>
 *   <li>{@code autoRoll} (default {@code false} — scheduling stays with the ops team
 *       unless explicitly enabled): when {@code true}, {@link PortalAutoRoll} rolls ONE
 *       weighted {@link PortalEventScheduler} variant at a random slot inside each
 *       eclipse day's real-time window.</li>
 *   <li>{@code minDay} (default 4): days before this never auto-roll.</li>
 * </ul>
 */
public final class PortalEventsConfig {

    /** Immutable snapshot of the config file. */
    public record Values(boolean autoRoll, int minDay) {}

    static final int DEFAULT_MIN_DAY = 4;

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    private static final String FILE_NAME = "portal_events.json";
    private static final AtomicBoolean BOOTSTRAPPED = new AtomicBoolean();

    private static volatile Values values = defaults();

    private PortalEventsConfig() {}

    public static Values get() {
        return values;
    }

    /** Registers the shared reload hook and performs the initial load. Idempotent. */
    public static void bootstrap() {
        if (BOOTSTRAPPED.compareAndSet(false, true)) {
            ReloadHooks.register(FILE_NAME, PortalEventsConfig::reload);
            reload();
        }
    }

    /** Re-reads the file; creates it with defaults when absent. Never leaves half-applied state. */
    public static void reload() {
        Path file = configFile();
        try {
            if (!Files.exists(file)) {
                writeDefaults(file);
            }
            String raw = Files.readString(file, StandardCharsets.UTF_8);
            Values parsed = parse(JsonParser.parseString(raw).getAsJsonObject());
            values = parsed;
            EclipseMod.LOGGER.info("Loaded {} (autoRoll={}, minDay={})",
                    file, parsed.autoRoll(), parsed.minDay());
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to load {} — keeping previous values", file, e);
        }
    }

    /**
     * {@code /dev portal auto on|off}: flips the gate in memory AND persists it back to
     * {@code portal_events.json} (read-modify-write preserving unrelated fields — the
     * {@code RealtimeConfig.setCadence} pattern). A file write failure keeps the in-memory
     * switch so the running server still honors the operator's command.
     */
    public static Values setAutoRoll(boolean autoRoll) {
        Values current = values;
        values = new Values(autoRoll, current.minDay());
        Path file = configFile();
        try {
            Files.createDirectories(file.getParent());
            JsonObject root = Files.isRegularFile(file)
                    ? JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject()
                    : defaultJson();
            root.addProperty("autoRoll", autoRoll);
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
            EclipseMod.LOGGER.info("PortalEventsConfig: autoRoll={} persisted to {}", autoRoll, file);
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("PortalEventsConfig: autoRoll switched in memory but persisting {} failed",
                    file, e);
        }
        return values;
    }

    private static Path configFile() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve(FILE_NAME);
    }

    private static Values defaults() {
        return new Values(false, DEFAULT_MIN_DAY);
    }

    private static Values parse(JsonObject root) {
        boolean autoRoll = root.has("autoRoll") && root.get("autoRoll").getAsBoolean();
        int minDay = root.has("minDay")
                ? Math.max(1, root.get("minDay").getAsInt()) : DEFAULT_MIN_DAY;
        return new Values(autoRoll, minDay);
    }

    private static JsonObject defaultJson() {
        Values def = defaults();
        JsonObject root = new JsonObject();
        root.addProperty("autoRoll", def.autoRoll());
        root.addProperty("minDay", def.minDay());
        return root;
    }

    private static void writeDefaults(Path file) throws IOException {
        Files.createDirectories(file.getParent());
        Files.writeString(file, GSON.toJson(defaultJson()), StandardCharsets.UTF_8);
        EclipseMod.LOGGER.info("Created default {}", file);
    }
}
