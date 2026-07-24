package dev.projecteclipse.eclipse.cutscene;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Collection;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import net.neoforged.fml.loading.FMLPaths;

/**
 * The server-side camera-path library: loads/saves {@code config/eclipse/cutscenes/<id>.json}.
 * On first run the five bundled default paths (JSON assets under
 * {@code assets/eclipse/cutscenes/}) are copied into the config directory, so operators can
 * edit them like every other Eclipse config file:
 * <ul>
 *   <li>{@code intro_v3_ship} — limbo ghost-ship deck flyaround (start event TILT and the
 *       finale arrival), anchor {@code player}.</li>
 *   <li>{@code intro_v3_flight} — intro v3 crane path over the fusing discs toward the
 *       vortex, anchor {@code world} (play anchor = vortex center, supplied by
 *       {@code sequence.IntroSequence}).</li>
 *   <li>{@code intro_v3_reveal} — intro v3 orbit of the revealed floating altar island,
 *       anchor {@code world} (play anchor = altar position).</li>
 *   <li>{@code unlock_ring} — orbital shot template at a ring edge, anchor {@code world}
 *       (per-play anchor position supplied by the unlock-growth integration).</li>
 *   <li>{@code finale_return} — reverse-intro descent used by the day-14 finale (W12).</li>
 * </ul>
 *
 * <p><b>Default refresh</b> (P2 R12): bundled defaults get reshot across waves (W2 reshot
 * {@code finale_return}; W6/W7 replace the intro/unlock shots), so "copy only when missing"
 * would pin every existing install to the first version it ever saw. {@code reload()}
 * therefore tracks the installed default's SHA-256 per id in
 * {@code config/eclipse/cutscene_defaults_manifest.json} (parent dir — never scanned as a
 * path): when the bundled asset changes, a config file still byte-identical to the
 * previously installed default is upgraded in place; a file the operator edited is kept
 * and a warning explains that deleting it adopts the new default. Files that predate the
 * manifest upgrade only when byte-identical to a known old default
 * ({@link #LEGACY_DEFAULT_HASHES}); otherwise they are never touched (warned only).</p>
 *
 * <p>Same failure policy as {@code EclipseConfig}: parse/IO failures are logged and the file
 * is skipped, never thrown. All mutation goes through {@link #save} so the on-disk file, the
 * in-memory cache and the raw-JSON strings (synced to clients via
 * {@code S2CCutsceneLibraryPayload}) never drift apart.</p>
 */
public final class CutscenePaths {
    /** Bundled defaults copied to {@code config/eclipse/cutscenes/} on first run. */
    private static final List<String> DEFAULT_IDS =
            List.of("intro_v3_ship", "intro_v3_flight", "intro_v3_reveal", "unlock_ring",
                    "expansion_skyward", "expansion_flyover", "finale_return");
    private static final String BUNDLED_RESOURCE_ROOT = "/assets/eclipse/cutscenes/";
    /** Sits in {@code config/eclipse/} (NOT in {@code cutscenes/} — the loader scans that). */
    private static final String MANIFEST_NAME = "cutscene_defaults_manifest.json";
    /** Operator files larger than this are skipped on load (keeps the client sync bounded). */
    private static final long MAX_FILE_BYTES = 128 * 1024;
    private static final Gson MANIFEST_GSON = new GsonBuilder().setPrettyPrinting().create();

    /**
     * SHA-256 fingerprints of bundled defaults shipped by OLD versions: a config file that
     * predates the manifest but is byte-identical to one of these is a stale default, not an
     * operator edit, and upgrades in place. Reshooting a bundled JSON? Append the hash of the
     * version you replaced (W6/W7: intro/unlock shots).
     */
    private static final Map<String, List<String>> LEGACY_DEFAULT_HASHES = Map.of(
            "finale_return", List.of("6a0fcdab0fb32e8e3c66e0dc725b53d36304c70350a07df55f462ed48574bb43"),
            // W7 reshot the unlock_ring orbit; the v2-era default hash stays on record so
            // untouched config copies upgrade in place.
            "unlock_ring", List.of("2d5f63f7cb778bd799f185e700549fcc1e213488229b63fff5a0a4cd457eaefa"),
            // W6 deleted the v1 intro pair from DEFAULT_IDS (superseded by the intro_v3_*
            // shots). Their shipped hashes stay on record so a future re-adoption of either
            // id can still tell "stale old default" from "operator edit"; stale config
            // copies of deleted ids are left alone by design (see the W2 wiring doc — the
            // manual cleanup is documented in P2-W6_wiring.md).
            "intro_submerge", List.of("b3057c0891435933ac3782af052897657676ec2b529435ff67f75d0284a0ddb3"),
            "intro_rise", List.of("69592d1efea3b0ed59c47ad1f8d346b0c59333113f462cc067beafbb65c74f0a"));

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
        Map<String, String> manifest = readManifest();
        boolean manifestDirty = false;
        for (String id : DEFAULT_IDS) {
            Path file = dir.resolve(id + ".json");
            byte[] bundled;
            try (InputStream in = CutscenePaths.class.getResourceAsStream(BUNDLED_RESOURCE_ROOT + id + ".json")) {
                if (in == null) {
                    EclipseMod.LOGGER.error("Bundled cutscene path asset missing: {}{}.json",
                            BUNDLED_RESOURCE_ROOT, id);
                    continue;
                }
                bundled = in.readAllBytes();
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to read bundled cutscene path {}{}.json",
                        BUNDLED_RESOURCE_ROOT, id, e);
                continue;
            }
            String bundledHash = sha256Hex(bundled);
            String installedHash = manifest.get(id);
            try {
                if (!Files.exists(file)) {
                    Files.write(file, bundled);
                    manifest.put(id, bundledHash);
                    manifestDirty = true;
                    EclipseMod.LOGGER.info("Created default cutscene path {}", file);
                    continue;
                }
                String fileHash = sha256Hex(Files.readAllBytes(file));
                if (fileHash.equals(bundledHash)) {
                    // Already current; adopt into the manifest if it predates it.
                    if (!bundledHash.equals(installedHash)) {
                        manifest.put(id, bundledHash);
                        manifestDirty = true;
                    }
                } else if (installedHash == null) {
                    if (LEGACY_DEFAULT_HASHES.getOrDefault(id, List.of()).contains(fileHash)) {
                        // Byte-identical to a default an old version shipped: stale, upgrade.
                        Files.write(file, bundled);
                        manifest.put(id, bundledHash);
                        manifestDirty = true;
                        EclipseMod.LOGGER.info("Refreshed bundled cutscene path {} (matched an old shipped "
                                + "default)", file);
                    } else {
                        // Pre-manifest file that differs from every known default: cannot tell an
                        // operator edit from a stale old default — never clobber, only explain.
                        EclipseMod.LOGGER.warn("Cutscene path {} predates the defaults manifest and differs "
                                + "from the current bundled default; delete the file (and reload) to adopt "
                                + "the new version, or keep it to keep your edits", file);
                    }
                } else if (fileHash.equals(installedHash)) {
                    // Untouched old default + changed bundled asset: safe in-place upgrade.
                    Files.write(file, bundled);
                    manifest.put(id, bundledHash);
                    manifestDirty = true;
                    EclipseMod.LOGGER.info("Refreshed bundled cutscene path {} (new default, file was unedited)",
                            file);
                } else if (!bundledHash.equals(installedHash)) {
                    EclipseMod.LOGGER.warn("Bundled cutscene default '{}' changed but {} has local edits; "
                            + "keeping the local file (delete it and reload to adopt the new default)",
                            id, file);
                }
                // else: operator edited, bundled unchanged — normal customization, stay quiet.
            } catch (IOException e) {
                EclipseMod.LOGGER.error("Failed to write default cutscene path {}", file, e);
            }
        }
        if (manifestDirty) {
            writeManifest(manifest);
        }

        Map<String, CutscenePath> parsed = new LinkedHashMap<>();
        Map<String, String> raw = new LinkedHashMap<>();
        try (var stream = Files.list(dir)) {
            for (Path file : stream.filter(f -> f.getFileName().toString().endsWith(".json"))
                    .sorted().toList()) {
                String fileName = file.getFileName().toString();
                String fallbackId = fileName.substring(0, fileName.length() - ".json".length());
                try {
                    long size = Files.size(file);
                    if (size > MAX_FILE_BYTES) {
                        EclipseMod.LOGGER.warn("Cutscene path {} is {} bytes (limit {}); skipping",
                                fileName, size, MAX_FILE_BYTES);
                        continue;
                    }
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

    // ---------------------------------------------------------------------------------------
    // Bundled-defaults manifest (id -> SHA-256 of the default content this mod last installed)

    private static Path manifestFile() {
        return FMLPaths.CONFIGDIR.get().resolve("eclipse").resolve(MANIFEST_NAME);
    }

    private static Map<String, String> readManifest() {
        Path file = manifestFile();
        Map<String, String> manifest = new LinkedHashMap<>();
        if (!Files.exists(file)) {
            return manifest;
        }
        try {
            JsonObject obj = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8))
                    .getAsJsonObject();
            for (String key : obj.keySet()) {
                if (obj.get(key).isJsonPrimitive()) {
                    manifest.put(key, obj.get(key).getAsString());
                }
            }
        } catch (IOException | RuntimeException e) {
            // Corrupt manifest degrades to pre-manifest behaviour (warn-only, never clobber).
            EclipseMod.LOGGER.warn("Failed to read {}; treating all defaults as pre-manifest", file, e);
        }
        return manifest;
    }

    private static void writeManifest(Map<String, String> manifest) {
        Path file = manifestFile();
        JsonObject obj = new JsonObject();
        manifest.forEach(obj::addProperty);
        try {
            Files.createDirectories(file.getParent());
            Files.writeString(file, MANIFEST_GSON.toJson(obj), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write {}", file, e);
        }
    }

    private static String sha256Hex(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JVM without SHA-256", e);
        }
    }
}
