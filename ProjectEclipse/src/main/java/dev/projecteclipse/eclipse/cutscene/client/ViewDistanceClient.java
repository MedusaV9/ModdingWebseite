package dev.projecteclipse.eclipse.cutscene.client;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.network.fx.S2CViewDistancePayload;
import net.minecraft.client.Minecraft;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client side of the cinematic view-distance push (P2 R12). {@code FxPayloads} dispatches
 * {@link S2CViewDistancePayload} here (frozen entry point {@link #handle}).
 *
 * <p><b>Behaviour</b>: a payload with {@code chunks > 0} RAISES {@code options.renderDistance}
 * to that value for the duration of the cutscene session — only when
 * {@link EclipseClientConfig#cinematicViewDistance()} is enabled (the player toggle, default
 * ON) and only upward (a player already rendering further keeps their own setting). A payload
 * with {@code chunks == 0} restores the player's original value; so do logout/disconnect
 * (server-side end/watchdog sends the {@code 0} for the normal path).</p>
 *
 * <p><b>Crash-robust</b> (mirrors {@code WaveOverlay}'s volume marker): the original render
 * distance is persisted to {@code config/}{@value #RESTORE_MARKER_NAME} before the first
 * mutation and the marker is deleted after a successful restore. If the session dies
 * mid-cutscene (kill -9, crash), the next launch's first client tick finds the marker,
 * restores the saved value, saves the options and deletes it — a bumped render distance can
 * never stick permanently.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ViewDistanceClient {
    /** Crash-recovery marker in the config dir: the pre-bump render distance, JSON. */
    private static final String RESTORE_MARKER_NAME = "eclipse-viewdistance-restore.json";
    private static final String MARKER_KEY = "renderDistance";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();

    /** The player's own render distance while a bump is active, or {@code -1} when inactive. */
    private static int savedRenderDistance = -1;
    /** One-shot flag: the crash-recovery marker check runs on the very first client tick. */
    private static boolean recoveryChecked;

    private ViewDistanceClient() {}

    /**
     * FROZEN entry point — called by {@code FxPayloads} on the client main thread.
     * {@code chunks > 0} requests a temporary raise, {@code chunks == 0} restores.
     */
    public static void handle(S2CViewDistancePayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        int chunks = payload.chunks();
        if (chunks <= 0) {
            restore(minecraft);
            return;
        }
        if (!EclipseClientConfig.cinematicViewDistance()) {
            EclipseMod.LOGGER.info("ViewDistanceClient: ignoring cinematic bump to {} (player toggle off)", chunks);
            return;
        }
        int current = minecraft.options.renderDistance().get();
        if (savedRenderDistance < 0 && current >= chunks) {
            return; // Already rendering at least this far — nothing to raise or restore.
        }
        if (savedRenderDistance < 0) {
            // Crash safety: persist the original BEFORE the first mutation.
            savedRenderDistance = current;
            writeRestoreMarker(current);
        }
        // A re-push (e.g. chained cutscenes) keeps the ORIGINAL saved value, never the bump.
        minecraft.options.renderDistance().set(Math.max(chunks, minecraft.options.renderDistance().get()));
        EclipseMod.LOGGER.info("ViewDistanceClient: cinematic render distance {} -> {} (will restore)",
                savedRenderDistance, minecraft.options.renderDistance().get());
    }

    /** Puts the player's own render distance back and drops the crash marker. */
    private static void restore(Minecraft minecraft) {
        if (savedRenderDistance < 0) {
            return;
        }
        minecraft.options.renderDistance().set(savedRenderDistance);
        EclipseMod.LOGGER.info("ViewDistanceClient: restored render distance {}", savedRenderDistance);
        savedRenderDistance = -1;
        deleteRestoreMarker(); // Restore complete: the crash marker has nothing left to undo.
    }

    /** First tick: crash recovery. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!recoveryChecked) {
            recoveryChecked = true;
            recoverCrashedBump(Minecraft.getInstance());
        }
    }

    /** Disconnect/logout always restores — the server-side watchdog cannot reach us anymore. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        restore(Minecraft.getInstance());
    }

    // --- crash-recovery marker (config/eclipse-viewdistance-restore.json) ---

    private static Path restoreMarkerPath() {
        return FMLPaths.CONFIGDIR.get().resolve(RESTORE_MARKER_NAME);
    }

    private static void writeRestoreMarker(int renderDistance) {
        JsonObject root = new JsonObject();
        root.addProperty(MARKER_KEY, renderDistance);
        Path file = restoreMarkerPath();
        try {
            Files.writeString(file, GSON.toJson(root), StandardCharsets.UTF_8);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to write {}; a crash mid-cutscene could keep the raised render distance", file, e);
        }
    }

    private static void deleteRestoreMarker() {
        Path file = restoreMarkerPath();
        try {
            Files.deleteIfExists(file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("Failed to delete {}", file, e);
        }
    }

    /**
     * First-tick crash recovery: a leftover marker means the previous session died between
     * bump and restore — put its saved render distance back, persist the options (the crashed
     * session may have saved the bumped value into options.txt) and drop the marker.
     */
    private static void recoverCrashedBump(Minecraft minecraft) {
        Path file = restoreMarkerPath();
        if (!Files.exists(file)) {
            return;
        }
        try {
            JsonObject root = JsonParser.parseString(Files.readString(file, StandardCharsets.UTF_8)).getAsJsonObject();
            if (root.has(MARKER_KEY)) {
                int original = root.get(MARKER_KEY).getAsInt();
                minecraft.options.renderDistance().set(original);
                minecraft.options.save();
                EclipseMod.LOGGER.info("Restored render distance {} left raised by a crashed cutscene session", original);
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to restore render distance from {}", file, e);
        }
        deleteRestoreMarker();
    }
}
