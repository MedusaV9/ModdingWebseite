package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * Synced day-timer state for the R7 day-timer HUD ({@code docs/plans_v3/P3_ui.md} §3.6),
 * derived entirely from the {@code S2CDayClockPayload} fields the existing handler writes
 * into {@link ClientStateCache} ({@code boundaryEpochMillis}, {@code serverNowEpochMillis},
 * {@code dayClockPaused}, ...). The client NEVER computes the deadline itself — it renders
 * {@code boundary - serverNow} where {@code serverNow} is re-derived every frame from the
 * last payload's server clock plus the local millis elapsed since receipt
 * ({@code clockSyncLocalMillis}), so a ±5 min local clock skew is irrelevant.
 *
 * <p><b>Spool detection</b>: {@code RealtimeDayService.addMillis} broadcasts a fresh clock
 * payload on every dev {@code /dev timer add|sub|set} — per its javadoc, "P3 animates the
 * spool from consecutive payloads whose boundary changed while the day did not". The tick
 * handler below snapshots the cache fields once per client tick and starts a spool whenever
 * the boundary (running) or the frozen remaining window (paused) jumps while day and
 * pause-state are unchanged. The displayed value then eases from the pre-jump reading to
 * the live remaining time over {@code clamp(|delta|·0.02, 0.4s, 1.5s)} (~20 ticks for
 * typical shifts); {@code reducedFx} snaps.</p>
 *
 * <p><b>Zero crossing</b>: the first tick where the running remaining time hits 0 for a
 * given boundary stamps {@link #zeroBlinkStartMillis} and fires {@code ui.timer_zero}
 * exactly once (guarded per boundary value). The timer never triggers anything else — the
 * day flip is entirely server-driven.</p>
 *
 * <p>Frozen API (§7.2) for the W5 sidebar expanded card: {@link #remainingMillis()} /
 * {@link #warnMillis()}. Everything is client-thread only (tick + render).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class DayTimerCache {
    /** Boundary/pause-window jumps below this are treated as re-sync drift, not a spool. */
    private static final long SPOOL_MIN_DELTA_MILLIS = 250L;
    private static final long SPOOL_MIN_MILLIS = 400L;
    private static final long SPOOL_MAX_MILLIS = 1_500L;
    /** Fallback warn window when the day window is unknown (§3.6 default: last 60 min). */
    private static final long DEFAULT_WARN_MILLIS = 60L * 60_000L;

    // --- spool state (monotonic Util.getMillis clock) ---
    private static long spoolStartMillis;
    private static long spoolDurationMillis;
    private static long spoolFromRemaining;
    private static boolean spoolRising;

    // --- change-detection snapshot (previous client tick) ---
    private static boolean snapshotValid;
    private static int lastDay;
    private static long lastBoundary;
    private static long lastPauseRemaining;
    private static boolean lastPaused;
    private static boolean lastArmed;
    /** Displayed remaining at the END of the previous tick — the spool's start value. */
    private static long lastShownRemaining;

    // --- zero-crossing bookkeeping ---
    private static long lastComputedRemaining = -1L;
    private static long zeroFiredBoundary;
    private static long zeroBlinkStartMillis;

    private DayTimerCache() {}

    /** Whether the real-time day clock is armed (a boundary was synced and not cleared). */
    public static boolean armed() {
        return ClientStateCache.boundaryEpochMillis > 0L;
    }

    public static boolean paused() {
        return ClientStateCache.dayClockPaused;
    }

    public static int day() {
        return ClientStateCache.dayClockDay;
    }

    /**
     * True remaining real time to the next day boundary in ms (frozen window while paused,
     * clamped ≥ 0, {@code 0} when disarmed). Frozen §7.2 API — W5's expanded sidebar card
     * mirrors this value.
     */
    public static long remainingMillis() {
        if (!armed()) {
            return 0L;
        }
        if (ClientStateCache.dayClockPaused) {
            return Math.max(0L, ClientStateCache.pauseRemainingMillis);
        }
        return Math.max(0L, ClientStateCache.boundaryEpochMillis - serverNowMillis());
    }

    /** Displayed remaining ms: {@link #remainingMillis()} with the odometer spool easing. */
    public static long displayedRemainingMillis() {
        long target = remainingMillis();
        if (spoolStartMillis == 0L) {
            return target;
        }
        float t = (Util.getMillis() - spoolStartMillis) / (float) spoolDurationMillis;
        if (t >= 1.0F) {
            return target;
        }
        float eased = easeInOutCubic(t);
        return spoolFromRemaining + Math.round((target - spoolFromRemaining) * (double) eased);
    }

    /** Full boundary-to-boundary window in ms, or 0 when unknown. */
    public static long windowMillis() {
        long boundary = ClientStateCache.boundaryEpochMillis;
        long previous = ClientStateCache.prevBoundaryEpochMillis;
        return boundary > 0L && previous > 0L && boundary > previous ? boundary - previous : 0L;
    }

    /** Displayed remaining fraction of the day window, 0..1 (1 when the window is unknown). */
    public static float remainingFraction() {
        long window = windowMillis();
        if (window <= 0L) {
            return 1.0F;
        }
        return Mth.clamp(displayedRemainingMillis() / (float) window, 0.0F, 1.0F);
    }

    /**
     * Purple warn window in ms: the final 10% of the day window (§3.6 / "last 10% strongly
     * purple"), falling back to the plan's 60-minute default while the window is unknown.
     * Frozen §7.2 API.
     */
    public static long warnMillis() {
        long window = windowMillis();
        return window > 0L ? Math.max(30_000L, window / 10L) : DEFAULT_WARN_MILLIS;
    }

    /** Whether the odometer spool animation is currently running. */
    public static boolean spooling() {
        return spoolStartMillis != 0L && Util.getMillis() - spoolStartMillis < spoolDurationMillis;
    }

    /** Spool direction: {@code true} when the remaining time jumped UP (dev added time). */
    public static boolean spoolRising() {
        return spoolRising;
    }

    /** Monotonic millis of the last 00:00:00 crossing, or 0 (drives the 3-blink + hold look). */
    public static long zeroBlinkStartMillis() {
        return zeroBlinkStartMillis;
    }

    /** Server "now" extrapolated from the last payload's clock + local elapsed time. */
    private static long serverNowMillis() {
        long syncLocal = ClientStateCache.clockSyncLocalMillis;
        if (syncLocal == 0L) {
            return ClientStateCache.serverNowEpochMillis;
        }
        return ClientStateCache.serverNowEpochMillis + (System.currentTimeMillis() - syncLocal);
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        if (Minecraft.getInstance().level == null) {
            reset();
            return;
        }
        int day = ClientStateCache.dayClockDay;
        long boundary = ClientStateCache.boundaryEpochMillis;
        boolean paused = ClientStateCache.dayClockPaused;
        long pauseRemaining = ClientStateCache.pauseRemainingMillis;
        boolean armed = boundary > 0L;

        if (snapshotValid) {
            if (armed && lastArmed && day == lastDay && paused == lastPaused) {
                long delta = paused ? pauseRemaining - lastPauseRemaining : boundary - lastBoundary;
                if (Math.abs(delta) > SPOOL_MIN_DELTA_MILLIS) {
                    beginSpool(delta > 0L);
                }
            } else if (day != lastDay || armed != lastArmed || paused != lastPaused) {
                // Day flip / arm / pause transitions snap — remaining stays continuous there.
                spoolStartMillis = 0L;
            }
        }
        lastDay = day;
        lastBoundary = boundary;
        lastPaused = paused;
        lastPauseRemaining = pauseRemaining;
        lastArmed = armed;
        snapshotValid = true;

        long remaining = remainingMillis();
        if (armed && !paused && lastComputedRemaining > 0L && remaining == 0L
                && zeroFiredBoundary != boundary) {
            zeroFiredBoundary = boundary;
            zeroBlinkStartMillis = Util.getMillis();
            if (EclipseClientConfig.showDayTimer()) {
                UiSounds.timerZero();
            }
        }
        lastComputedRemaining = remaining;
        lastShownRemaining = displayedRemainingMillis();
    }

    /** Starts (or retargets) the odometer spool from the pre-jump displayed reading. */
    private static void beginSpool(boolean rising) {
        if (EclipseClientConfig.reducedFx()) {
            spoolStartMillis = 0L; // §3.6: reducedFx snaps
            return;
        }
        spoolFromRemaining = lastShownRemaining;
        long delta = Math.abs(remainingMillis() - spoolFromRemaining);
        spoolDurationMillis = Mth.clamp(Math.round(delta * 0.02D), SPOOL_MIN_MILLIS, SPOOL_MAX_MILLIS);
        spoolStartMillis = Util.getMillis();
        spoolRising = rising;
    }

    private static void reset() {
        spoolStartMillis = 0L;
        snapshotValid = false;
        lastComputedRemaining = -1L;
        zeroFiredBoundary = 0L;
        zeroBlinkStartMillis = 0L;
        lastShownRemaining = 0L;
    }

    private static float easeInOutCubic(float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        if (t < 0.5F) {
            return 4.0F * t * t * t;
        }
        float inv = -2.0F * t + 2.0F;
        return 1.0F - inv * inv * inv / 2.0F;
    }
}
