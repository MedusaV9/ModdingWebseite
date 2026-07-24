package dev.projecteclipse.eclipse.progression.realtime;

import java.time.ZoneId;

import net.minecraft.server.MinecraftServer;

/**
 * FROZEN dev-API surface of the real-time day engine (plan §2.1) — P5-W3 surfaces the
 * polished command set on top of exactly these entry points; P4-B1's
 * {@code /eclipse-rt} reference commands call the same ones. All methods are
 * server-thread only, idempotent where sensible, and broadcast
 * {@code S2CDayClockPayload} themselves — callers never need a manual re-sync.
 *
 * <p>Return conventions: {@code -1} = precondition failed (not armed / not paused /
 * already paused); otherwise the documented epoch-millis or remaining-millis value.
 * {@link #setBoundary} throws {@link IllegalArgumentException} with a human-readable
 * reason for bad specs (surface it as command feedback, the W14 pattern).</p>
 */
public final class RealtimeDayApi {
    private RealtimeDayApi() {}

    /**
     * Arms the recurring cadence ({@code realtime.json} zone + boundaryTime). Clears pause
     * and any one-shot override. Returns the next boundary (epoch millis).
     */
    public static long arm(MinecraftServer server) {
        return RealtimeDayService.arm(server);
    }

    /** Disarms entirely: no further advances, countdown hidden on all clients. */
    public static void disarm(MinecraftServer server) {
        RealtimeDayService.disarm(server);
    }

    /** Whether the engine is armed (running or paused). */
    public static boolean isArmed(MinecraftServer server) {
        return RealtimeState.get(server).isArmed();
    }

    /** Whether the countdown is currently frozen by {@link #pause}. */
    public static boolean isPaused(MinecraftServer server) {
        return RealtimeState.get(server).isArmed() && RealtimeState.get(server).isPaused();
    }

    /**
     * Freezes the countdown (remaining window stored). Returns the frozen remaining
     * millis, or {@code -1} when not running.
     */
    public static long pause(MinecraftServer server) {
        return RealtimeDayService.pause(server);
    }

    /**
     * Resumes a paused countdown ({@code boundary = now + frozen remaining}). Returns the
     * new boundary (epoch millis), or {@code -1} when not paused.
     */
    public static long resume(MinecraftServer server) {
        return RealtimeDayService.resume(server);
    }

    /**
     * Shifts the boundary (or the frozen remaining window while paused) by
     * {@code deltaMillis}; negative = sooner, clamped to
     * {@link RealtimeDayService#MIN_FUTURE_MILLIS} from now. Marks a one-shot override and
     * broadcasts immediately (clients spool the timer from the payload change). Returns
     * the new remaining millis, or {@code -1} when disarmed.
     */
    public static long addMillis(MinecraftServer server, long deltaMillis) {
        return RealtimeDayService.addMillis(server, deltaMillis);
    }

    /**
     * Sets an explicit one-shot boundary from {@code +NhNNm[NNs]} or an ISO-8601 local
     * date-time interpreted in {@code specZone} (pass
     * {@code RealtimeConfig.get().zone()} unless a legacy server-local surface requires
     * {@link ZoneId#systemDefault()}). Arms a disarmed engine. Returns the target epoch
     * millis.
     *
     * @throws IllegalArgumentException when the spec is unparseable or not in the future
     */
    public static long setBoundary(MinecraftServer server, String spec, ZoneId specZone) {
        return RealtimeDayService.setBoundarySpec(server, spec, specZone);
    }

    /** One human-readable status line (armed/paused/boundary/zone/day). */
    public static String status(MinecraftServer server) {
        return RealtimeDayService.status(server);
    }
}
