package dev.projecteclipse.eclipse.cutscene;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * The server-side camera-path library: loads/saves {@code config/eclipse/cutscenes/<id>.json}.
 * On first run the four bundled default paths (JSON assets under
 * {@code assets/eclipse/cutscenes/}) are copied into the config directory, so operators can
 * edit them like every other Eclipse config file:
 * <ul>
 *   <li>{@code intro_submerge} — limbo ghost-ship submerge flyaround (start event TILT).</li>
 *   <li>{@code intro_rise} — overworld rise-out-of-the-ground shot, anchor {@code player}.</li>
 *   <li>{@code unlock_ring} — orbital shot template at a ring edge, anchor {@code world}
 *       (per-play anchor position supplied by the unlock-growth integration).</li>
 *   <li>{@code finale_return} — reverse-intro descent used by the day-14 finale (W12).</li>
 * </ul>
 *
 * <p>Same failure policy as {@code EclipseConfig}: parse/IO failures are logged and the file
 * is skipped, never thrown. All mutation goes through {@link #save} so the on-disk file, the
 * in-memory cache and the raw-JSON strings (synced to clients via
 * {@code S2CCutsceneLibraryPayload}) never drift apart.</p>
 */
public final class CutscenePaths {
    /** Bundled defaults copied to {@code config/eclipse/cutscenes/} on first run. */
    private static final List<String> DEFAULT_IDS =
            List.of("intro_submerge", "intro_rise", "unlock_ring", "finale_return");
    private static final String BUNDLED_RESOURCE_ROOT = "/assets/eclipse/cutscenes/";

    private static volatile Map<String, CutscenePath> paths = Map.of();
    private static volatile Map<String, String> rawJson = Map.of();
    private static volatile boolean loaded = false;

    private CutscenePaths() {}

    private static Path directory() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve("cutscenes");
    }

    /** Re-scans {@code config/eclipse/cutscenes/*.json}, copying bundled defaults first. */
    public static synchronized void reload() {
        Path dir = directory();
        try {
            Files.createDirectories(dir);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to create cutscene path directory {}", dir, e);
        }
        for (String id : DEFAULT_IDS) {
            Path file = dir.resolve(id + ".json");
            if (Files.exists(file)) {
                continue;
            }
            try (InputStream in = CutscenePaths.class.getResourceAsStream(BUNDLED_RESOURCE_ROOT + id + ".json")) {
                if (in == null) {
                    EclipseMod.LOGGER.error("Bundled cutscene path asset missing: {}{}.json",
                            BUNDLED_RESOURCE_ROOT, id);
                    continue;
                }
                Files.write(file, in.readAllBytes());
                EclipseMod.LOGGER.info("Created default cutscene path {}", file);
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default cutscene path {}", file, e);
            }
        }

        Map<String, CutscenePath> parsed = new LinkedHashMap<>();
        Map<String, String> raw = new LinkedHashMap<>();
        try (var stream = Files.list(dir)) {
            for (Path file : stream.filter(f -> f.getFileName().toString().endsWith(".json"))
                    .sorted().toList()) {
                String fileName = file.getFileName().toString();
                String fallbackId = fileName.substring(0, fileName.length() - ".json".length());
                try {
                    String json = Files.readString(file, StandardCharsets.UTF_8);
                    CutscenePath path = CutscenePath.parse(fallbackId, json);
                    if (path.keyframes().size() < 2) {
                        EclipseMod.LOGGER.warn("Cutscene path {} has fewer than 2 keyframes; skipping", fileName);
                        continue;
                    }
                    parsed.put(path.id(), path);
                    raw.put(path.id(), json);
                } catch (IOException | RuntimeException e) {
                    EclipseMod.LOGGER.error("Failed to parse cutscene path {}; skipping", file, e);
                }
            }
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to list cutscene path directory {}", dir, e);
        }
        paths = Collections.unmodifiableMap(parsed);
        rawJson = Collections.unmodifiableMap(raw);
        loaded = true;
        EclipseMod.LOGGER.info("Cutscene path library loaded: {} paths ({})",
                parsed.size(), String.join(", ", parsed.keySet()));
    }

    private static void ensureLoaded() {
        if (!loaded) {
            reload();
        }
    }

    /** The parsed path for an id, or {@code null}. */
    @Nullable
    public static CutscenePath get(String id) {
        ensureLoaded();
        return paths.get(id);
    }

    /** All loaded paths, in file order. */
    public static Collection<CutscenePath> all() {
        ensureLoaded();
        return paths.values();
    }

    /** Raw JSON documents by path id — the exact payload body of the client library sync. */
    public static Map<String, String> rawJsonById() {
        ensureLoaded();
        return rawJson;
    }

    /**
     * Writes a path to disk and refreshes the caches. Callers (editor commands) must re-sync
     * the client library afterwards ({@code CutsceneService.syncLibraryToAll}). Returns
     * whether the write succeeded.
     */
    public static synchronized boolean save(CutscenePath path) {
        ensureLoaded();
        Path file = directory().resolve(path.id() + ".json");
        String json = path.toJsonString();
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, json, StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to save cutscene path {}", file, e);
            return false;
        }
        Map<String, CutscenePath> parsed = new LinkedHashMap<>(paths);
        Map<String, String> raw = new LinkedHashMap<>(rawJson);
        parsed.put(path.id(), path);
        raw.put(path.id(), json);
        paths = Collections.unmodifiableMap(parsed);
        rawJson = Collections.unmodifiableMap(raw);
        EclipseMod.LOGGER.info("Saved cutscene path {} ({} keyframes)", path.id(), path.keyframes().size());
        return true;
    }
}
