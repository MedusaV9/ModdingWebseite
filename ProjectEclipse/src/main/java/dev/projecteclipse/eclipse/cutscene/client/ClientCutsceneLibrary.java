package dev.projecteclipse.eclipse.cutscene.client;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.cutscene.CutscenePath;
import dev.projecteclipse.eclipse.network.C2SCutsceneStatePayload;
import dev.projecteclipse.eclipse.network.S2CCutscenePlayPayload;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Client-side cache of the server-synced cutscene path library
 * ({@code S2CCutsceneLibraryPayload}, sent at login and after server-side path edits/reloads).
 * Documents are re-parsed with the same dist-neutral {@link CutscenePath#parse} the server
 * uses, so both sides always agree on a path's geometry and flags.
 */
public final class ClientCutsceneLibrary {
    private static volatile Map<String, CutscenePath> paths = Map.of();

    private ClientCutsceneLibrary() {}

    /** Replaces the library wholesale; malformed documents are logged and skipped. */
    public static void replace(Map<String, String> pathsJson) {
        Map<String, CutscenePath> parsed = new LinkedHashMap<>();
        for (Map.Entry<String, String> entry : pathsJson.entrySet()) {
            try {
                parsed.put(entry.getKey(), CutscenePath.parse(entry.getKey(), entry.getValue()));
            } catch (RuntimeException e) {
                EclipseMod.LOGGER.error("Ignoring malformed synced cutscene path '{}'", entry.getKey(), e);
            }
        }
        paths = Collections.unmodifiableMap(parsed);
        EclipseMod.LOGGER.info("Client cutscene library synced: {} paths ({})",
                parsed.size(), String.join(", ", parsed.keySet()));
    }

    /** The synced path for an id, or {@code null} (→ the player ACKs FINISHED instantly). */
    @Nullable
    public static CutscenePath get(String id) {
        return paths.get(id);
    }

    /**
     * {@code S2CCutscenePlayPayload} entry point. Until the camera director lands this ACKs
     * {@code FINISHED} instantly (same degradation as a missing path), so the server-side
     * freeze always releases and timelines never wait on a client that cannot render the shot.
     */
    public static void handlePlay(S2CCutscenePlayPayload payload) {
        if (payload.isStop()) {
            return;
        }
        EclipseMod.LOGGER.info("Cutscene '{}' requested; no camera director active — ACK FINISHED", payload.id());
        PacketDistributor.sendToServer(
                new C2SCutsceneStatePayload(payload.id(), C2SCutsceneStatePayload.State.FINISHED));
    }
}
