package dev.projecteclipse.eclipse.cutscene.client;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;

/**
 * Client-side cache of the server-synced cutscene path library
 * ({@code S2CCutsceneLibraryPayload}, sent at login and after server-side path edits/reloads).
 * Documents are re-parsed with the same dist-neutral {@link CutscenePath#parse} the server
 * uses, so both sides always agree on a path's geometry and flags.
 *
 * <p>PAYLOADFIX (F-001): the library arrives in CHUNKS now (see
 * {@code CutsceneService.libraryChunks}). The first chunk of a sync carries
 * {@code reset=true} and replaces the cache; followers merge into it. Payloads are handled
 * on the client main thread in send order, so a reset+merge sequence is never interleaved
 * with another sync.</p>
 */
public final class ClientCutsceneLibrary {
    private static volatile Map<String, CutscenePath> paths = Map.of();

    private ClientCutsceneLibrary() {}

    /**
     * Applies one synced library chunk: {@code reset} replaces the whole cache (first chunk
     * of every sync), otherwise the entries merge into the current cache. Malformed
     * documents are logged and skipped.
     */
    public static void applyChunk(boolean reset, Map<String, String> pathsJson) {
        Map<String, CutscenePath> parsed = reset ? new LinkedHashMap<>() : new LinkedHashMap<>(paths);
        for (Map.Entry<String, String> entry : pathsJson.entrySet()) {
            try {
                parsed.put(entry.getKey(), CutscenePath.parse(entry.getKey(), entry.getValue()));
            } catch (RuntimeException e) {
                EclipseMod.LOGGER.error("Ignoring malformed synced cutscene path '{}'", entry.getKey(), e);
            }
        }
        paths = Collections.unmodifiableMap(parsed);
        EclipseMod.LOGGER.info("Client cutscene library {}: now {} paths ({})",
                reset ? "reset" : "merged", parsed.size(), String.join(", ", parsed.keySet()));
    }

    /** The synced path for an id, or {@code null} (→ the player ACKs FINISHED instantly). */
    @Nullable
    public static CutscenePath get(String id) {
        return paths.get(id);
    }

    /** Drops the synced library (disconnect hook): the next server sends its own copy. */
    public static void clear() {
        if (!paths.isEmpty()) {
            paths = Map.of();
            EclipseMod.LOGGER.info("Client cutscene library cleared on disconnect");
        }
    }
}
