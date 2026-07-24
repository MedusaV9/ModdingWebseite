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
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Client side of the server view-distance push. {@code FxPayloads} dispatches
 * {@link S2CViewDistancePayload} here (frozen entry point {@link #handle}). Two server
 * sources share this transport: P2's transient cinematic bumps ({@code
 * cutscene.ViewDistanceService}) and P5-W34's persistent per-player pins ({@code
 * devtools.dev.DevViewDistance} — which defers its sends while a cinematic session is
 * active and re-sends on its falling edge, so the two never interleave).
 *
 * <p><b>Behaviour</b> (WB-SLOTLOCK closes P5-W34's "client transport cannot lower an
 * existing setting" limitation): a payload with {@code chunks > 0} overrides
 * {@code options.renderDistance} for as long as the request stands —</p>
 * <ul>
 *   <li>while {@link EclipseClientConfig#allowServerRenderDistance()} is on (the §7.1
 *       opt-out, default ON), the requested value is applied EXACTLY (clamped to the
 *       vanilla 2–32 slider range) — server pins can now LOWER the effective render
 *       distance;</li>
 *   <li>otherwise, while {@link EclipseClientConfig#cinematicViewDistance()} is on, the
 *       original upward-only cinematic semantics apply (a player already rendering
 *       further keeps their own setting);</li>
 *   <li>with both toggles off the request is held but nothing is touched.</li>
 * </ul>
 *
 * <p>Both toggles are respected LIVE: a once-per-second tick check re-evaluates the
 * standing request when either config value flips, restoring the player's own value the
 * moment they opt out and re-applying if they opt back in. A payload with
 * {@code chunks == 0} (cinematic end, {@code /dev viewdist unpin}) drops the request and
 * restores; so do logout/disconnect. The player's own value is held in
 * {@link #savedRenderDistance} — options.txt is never permanently mutated.</p>
 *
 * <p><b>Crash-robust</b> (mirrors {@code WaveOverlay}'s volume marker): the original render
 * distance is persisted to {@code config/}{@value #RESTORE_MARKER_NAME} before the first
 * mutation and the marker is deleted after a successful restore. If the session dies
 * mid-override (kill -9, crash), the next launch's first client tick finds the marker,
 * restores the saved value, saves the options and deletes it — an overridden render
 * distance can never stick permanently. (Persistent pins re-arrive on the next login via
 * {@code DevViewDistance}'s login hook, so crash recovery never "loses" a pin.)</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ViewDistanceClient {
    /** Crash-recovery marker in the config dir: the pre-override render distance, JSON. */
    private static final String RESTORE_MARKER_NAME = "eclipse-viewdistance-restore.json";
    private static final String MARKER_KEY = "renderDistance";
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().disableHtmlEscaping().create();
    /** Vanilla render-distance slider range (DevViewDistance clamps the same way). */
    private static final int MIN_CHUNKS = 2;
    private static final int MAX_CHUNKS = 32;
    /** Config toggles are polled once per second — cheap, and plenty "live" for a TOML flip. */
    private static final int TOGGLE_POLL_TICKS = 20;

    /** The player's own render distance while an override is active, or {@code -1} when inactive. */
    private static int savedRenderDistance = -1;
    /** The standing server request (pin or cinematic push), or {@code -1} when none. */
    private static int requestedChunks = -1;
    /** Last observed toggle pair (bit0 = allowServerRenderDistance, bit1 = cinematicViewDistance). */
    private static int lastToggleBits = -1;
    /** One-shot flag: the crash-recovery marker check runs on the very first client tick. */
    private static boolean recoveryChecked;
    private static int tickCounter;

    private ViewDistanceClient() {}

    /**
     * FROZEN entry point — called by {@code FxPayloads} on the client main thread.
     * {@code chunks > 0} is a standing override request, {@code chunks == 0} drops it.
     */
    public static void handle(S2CViewDistancePayload payload) {
        Minecraft minecraft = Minecraft.getInstance();
        int chunks = payload.chunks();
        if (chunks <= 0) {
            requestedChunks = -1;
            restore(minecraft);
            return;
        }
        requestedChunks = Mth.clamp(chunks, MIN_CHUNKS, MAX_CHUNKS);
        apply(minecraft);
    }

    /**
     * Applies the standing request under the current toggles: exact (may lower) with
     * {@code allowServerRenderDistance}, upward-only with {@code cinematicViewDistance},
     * hands-off (restoring anything already applied) with neither.
     */
    private static void apply(Minecraft minecraft) {
        if (requestedChunks < 0) {
            return;
        }
        int current = minecraft.options.renderDistance().get();
        int original = savedRenderDistance >= 0 ? savedRenderDistance : current;
        int target;
        if (EclipseClientConfig.allowServerRenderDistance()) {
            target = requestedChunks;
        } else if (EclipseClientConfig.cinematicViewDistance()) {
            target = Math.max(requestedChunks, original);
        } else {
            EclipseMod.LOGGER.info(
                    "ViewDistanceClient: holding server request of {} (both player toggles off)",
                    requestedChunks);
            restore(minecraft);
            return;
        }
        if (target == current && savedRenderDistance < 0) {
            return; // Nothing to change and nothing to restore later.
        }
        if (savedRenderDistance < 0) {
            // Crash safety: persist the original BEFORE the first mutation.
            savedRenderDistance = current;
            writeRestoreMarker(current);
        }
        if (target != current) {
            minecraft.options.renderDistance().set(target);
            EclipseMod.LOGGER.info("ViewDistanceClient: server render-distance override {} -> {} (own value {} will restore)",
                    current, target, savedRenderDistance);
        }
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

    /** First tick: crash recovery. Every second: live re-evaluation on config-toggle flips. */
    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (!recoveryChecked) {
            recoveryChecked = true;
            recoverCrashedBump(Minecraft.getInstance());
        }
        if (++tickCounter % TOGGLE_POLL_TICKS != 0) {
            return;
        }
        int toggleBits = (EclipseClientConfig.allowServerRenderDistance() ? 1 : 0)
                | (EclipseClientConfig.cinematicViewDistance() ? 2 : 0);
        if (toggleBits == lastToggleBits) {
            return;
        }
        // Re-apply ONLY on a toggle flip — never every second, so a player manually
        // moving the vanilla slider mid-override is not fought frame by frame.
        lastToggleBits = toggleBits;
        if (requestedChunks > 0) {
            apply(Minecraft.getInstance());
        }
    }

    /** Disconnect/logout always restores — the server-side watchdog cannot reach us anymore. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        requestedChunks = -1;
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
            EclipseMod.LOGGER.error("Failed to write {}; a crash mid-override could keep the server render distance", file, e);
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
     * override and restore — put its saved render distance back, persist the options (the
     * crashed session may have saved the overridden value into options.txt) and drop the
     * marker.
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
                EclipseMod.LOGGER.info("Restored render distance {} left overridden by a crashed session", original);
            }
        } catch (IOException | RuntimeException e) {
            EclipseMod.LOGGER.error("Failed to restore render distance from {}", file, e);
        }
        deleteRestoreMarker();
    }
}
