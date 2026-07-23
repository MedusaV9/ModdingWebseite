package dev.projecteclipse.eclipse.analytics;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonPrimitive;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * Loader for {@code config/eclipse/analytics.json} (P4 §2.4): sampler toggles, the per-sample
 * distance cap, per-day scratch-set caps, extra craft-allowlist ids and the retention window.
 * Missing file is created with defaults on first run; parse failures fall back to defaults in
 * memory (pattern: {@code EclipseConfig.loadOrCreate}). Hot-reloaded via the {@code ReloadHooks}
 * hook registered by {@link AnalyticsService}.
 *
 * <p>The craft allowlist is rebuilt on every (re)load: full per-item craft tracking is
 * unbounded, so {@code craft:<item_id>} detail is kept only for ids that appear in
 * {@code goals.json} / {@code quests.json} / {@code awards.json} (scanned textually for
 * resource-location-shaped strings — over-approximating is harmless, ids that are never
 * crafted never allocate a counter) plus the explicit {@code craftAllowlistExtras}.</p>
 */
public final class AnalyticsConfig {
    /** Immutable snapshot of the parsed config plus the derived craft allowlist. */
    public record Data(boolean samplerEnabled, long distanceSampleCapCm, int chunkSetCap,
            int maxDynamicKeysPerPlayerPerDay, List<String> craftAllowlistExtras, int retentionDays,
            Set<String> craftAllowlist) {}

    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    /** Matches namespaced resource-location-ish strings when scanning sibling configs. */
    private static final Pattern RESOURCE_ID = Pattern.compile("^#?[a-z0-9_.-]+:[a-z0-9_/.-]+$");

    /** Sibling config files scanned for craft-allowlist candidates (read-only; owned by B2/B6/B3). */
    private static final List<String> ALLOWLIST_SOURCES = List.of("goals.json", "quests.json", "awards.json");

    // statics reset on ServerStopped (via AnalyticsService.onServerStopped -> resetForNewSave)
    private static volatile Data data = null;

    private AnalyticsConfig() {}

    /** The active config snapshot, loading from disk on first access. */
    public static Data get() {
        Data current = data;
        if (current == null) {
            synchronized (AnalyticsConfig.class) {
                current = data;
                if (current == null) {
                    current = loadFrom(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
                    data = current;
                }
            }
        }
        return current;
    }

    /** Re-reads {@code analytics.json} (and rebuilds the craft allowlist). ReloadHooks entry point. */
    public static void reload() {
        data = loadFrom(FMLPaths.CONFIGDIR.get().resolve("eclipse"));
        EclipseMod.LOGGER.info("Eclipse analytics config loaded: sampler={}, distCap={}cm, chunkCap={}, "
                        + "keyCap={}, craftAllowlist={} ids, retention={} days",
                data.samplerEnabled(), data.distanceSampleCapCm(), data.chunkSetCap(),
                data.maxDynamicKeysPerPlayerPerDay(), data.craftAllowlist().size(), data.retentionDays());
    }

    /**
     * Loads (creating with defaults when missing) from an explicit directory — gametests inject
     * a doctored dir here instead of touching the live server config (plans_v3 P4 risk 8).
     */
    public static Data loadFrom(Path dir) {
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create config directory {}", dir, e);
        }
        Path file = dir.resolve("analytics.json");
        Data parsed;
        if (!Files.exists(file)) {
            parsed = defaults();
            try {
                Files.writeString(file, GSON.toJson(toJson(parsed)), StandardCharsets.UTF_8);
                EclipseMod.LOGGER.info("Created default Eclipse config {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default config {}", file, e);
            }
        } else {
            try {
                parsed = fromJson(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)));
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.error("Failed to read config {}; using built-in defaults", file, e);
                parsed = defaults();
            }
        }
        return withAllowlist(parsed, buildCraftAllowlist(dir, parsed.craftAllowlistExtras()));
    }

    /** Test hook: installs a fully-built snapshot (bypasses disk). Production never calls this. */
    public static void injectForTests(Data snapshot) {
        data = snapshot;
    }

    /** Drops the cached snapshot so the next access re-reads from disk (server stop / test cleanup). */
    public static void invalidate() {
        data = null;
    }

    /** Built-in defaults (also written to disk on first run). */
    public static Data defaults() {
        return new Data(true, 10_000L, 65_536, 2_048, List.of(), 20, Set.of());
    }

    /** Convenience for tests: defaults plus an explicit craft allowlist. */
    public static Data defaultsWithAllowlist(Set<String> craftAllowlist) {
        Data d = defaults();
        return withAllowlist(d, Set.copyOf(craftAllowlist));
    }

    private static Data withAllowlist(Data d, Set<String> allowlist) {
        return new Data(d.samplerEnabled(), d.distanceSampleCapCm(), d.chunkSetCap(),
                d.maxDynamicKeysPerPlayerPerDay(), d.craftAllowlistExtras(), d.retentionDays(), allowlist);
    }

    private static JsonElement toJson(Data d) {
        JsonObject obj = new JsonObject();
        obj.addProperty("samplerEnabled", d.samplerEnabled());
        obj.addProperty("distanceSampleCapCm", d.distanceSampleCapCm());
        obj.addProperty("chunkSetCap", d.chunkSetCap());
        obj.addProperty("maxDynamicKeysPerPlayerPerDay", d.maxDynamicKeysPerPlayerPerDay());
        JsonArray extras = new JsonArray();
        for (String id : d.craftAllowlistExtras()) {
            extras.add(id);
        }
        obj.add("craftAllowlistExtras", extras);
        obj.addProperty("retentionDays", d.retentionDays());
        return obj;
    }

    private static Data fromJson(JsonElement json) {
        JsonObject obj = json.getAsJsonObject();
        boolean samplerEnabled = !obj.has("samplerEnabled") || obj.get("samplerEnabled").getAsBoolean();
        long distCap = obj.has("distanceSampleCapCm") ? obj.get("distanceSampleCapCm").getAsLong() : 10_000L;
        int chunkCap = obj.has("chunkSetCap") ? obj.get("chunkSetCap").getAsInt() : 65_536;
        int keyCap = obj.has("maxDynamicKeysPerPlayerPerDay")
                ? obj.get("maxDynamicKeysPerPlayerPerDay").getAsInt() : 2_048;
        List<String> extras = new ArrayList<>();
        if (obj.has("craftAllowlistExtras") && obj.get("craftAllowlistExtras").isJsonArray()) {
            for (JsonElement el : obj.getAsJsonArray("craftAllowlistExtras")) {
                String id = el.getAsString().trim();
                if (!id.isEmpty()) {
                    extras.add(id);
                }
            }
        }
        int retention = obj.has("retentionDays") ? obj.get("retentionDays").getAsInt() : 20;
        return new Data(samplerEnabled, Math.max(100L, distCap), Math.max(64, chunkCap),
                Math.max(64, keyCap), List.copyOf(extras), Math.max(1, retention), Set.of());
    }

    /**
     * Scans sibling goal/quest/award configs (if present) for item-id-shaped strings and unions
     * the explicit extras. Bounded by config file sizes; runs only at (re)load time.
     */
    private static Set<String> buildCraftAllowlist(Path dir, List<String> extras) {
        Set<String> allow = new HashSet<>(extras);
        for (String name : ALLOWLIST_SOURCES) {
            Path file = dir.resolve(name);
            if (!Files.exists(file)) {
                continue;
            }
            try {
                collectResourceIds(JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)), allow);
            } catch (IOException | RuntimeException e) {
                EclipseMod.LOGGER.warn("Analytics craft-allowlist scan of {} failed; skipping it", file, e);
            }
        }
        return Set.copyOf(allow);
    }

    private static void collectResourceIds(JsonElement el, Set<String> out) {
        if (el == null) {
            return;
        }
        if (el.isJsonObject()) {
            for (var entry : el.getAsJsonObject().entrySet()) {
                collectResourceIds(entry.getValue(), out);
            }
        } else if (el.isJsonArray()) {
            for (JsonElement child : el.getAsJsonArray()) {
                collectResourceIds(child, out);
            }
        } else if (el.isJsonPrimitive()) {
            JsonPrimitive prim = el.getAsJsonPrimitive();
            if (prim.isString()) {
                String value = prim.getAsString();
                // Tags (#ns:path) are allowlisted without the marker: crafted stacks report plain ids.
                if (RESOURCE_ID.matcher(value).matches()) {
                    out.add(value.startsWith("#") ? value.substring(1) : value);
                }
            }
        }
    }
}
