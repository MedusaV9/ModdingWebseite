package dev.projecteclipse.eclipse.devtools;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import net.minecraft.server.MinecraftServer;

/**
 * W14 phase-scheduler command surface, since P4-B1 a THIN DELEGATE into the real-time day
 * engine ({@code progression.realtime.RealtimeDayService}) so the untouchable
 * {@code /eclipse schedule next|list|clear} subcommands keep working verbatim:
 *
 * <ul>
 *   <li>{@code scheduleNext} → a one-shot manual-override boundary
 *       ({@code RealtimeDayService.setBoundarySpec}, server-local ISO like before). An
 *       engine armed ONLY this way fires once and disarms — the exact legacy lifecycle.
 *       On an armed engine the override replaces the next cadence boundary once.</li>
 *   <li>{@code clear} → clears the override: schedule-only arms disarm fully (legacy
 *       "nothing scheduled"), cadence arms revert to the next {@code realtime.json}
 *       boundary.</li>
 *   <li>{@code isScheduled}/{@code describe} → report the pending one-shot override
 *       (the regular recurring cadence is intentionally NOT a "schedule" here; see
 *       {@code /eclipse-rt status} for the full engine state).</li>
 * </ul>
 *
 * <p>The countdown bossbar (purple, W8 {@code day} skin) moved WITH the firing logic into
 * {@code RealtimeDayService} — one bar serves both the legacy one-shots and the recurring
 * cadence. Persistence moved from {@code EclipseWorldState.nextPhaseEpochMillis} into
 * {@code RealtimeState} ({@code eclipse_realtime.dat}); a pending pre-P4 schedule is
 * migrated on server start and the legacy fields cleared.</p>
 */
public final class PhaseScheduler {
    private static final DateTimeFormatter TARGET_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault());

    private PhaseScheduler() {}

    /**
     * Parses a schedule spec into absolute epoch millis: {@code +NhNNm[NNs]} relative to now,
     * or a server-local ISO-8601 date-time ({@code 2026-08-01T18:00[:ss]}). Kept for API
     * compatibility; the math lives in {@link RealtimeMath#parseSpec} now.
     *
     * @throws IllegalArgumentException with a human-readable reason when unparseable
     */
    public static long parseSpec(String spec, long nowEpochMillis) {
        return RealtimeMath.parseSpec(spec, nowEpochMillis, ZoneId.systemDefault());
    }

    /**
     * Sets (replacing any previous) the next-phase one-shot boundary and shows the countdown
     * bar. Returns a feedback line for the command source.
     *
     * @throws IllegalArgumentException when the spec is unparseable or not in the future
     */
    public static String scheduleNext(MinecraftServer server, String spec) {
        long now = EclipseClock.epochMillis();
        long target = RealtimeDayService.setBoundarySpec(server, spec, ZoneId.systemDefault());
        int day = dev.projecteclipse.eclipse.progression.DayScheduler.getDay(server);
        EclipseMod.LOGGER.info("PhaseScheduler: next phase (day {} -> {}) scheduled at {} ({} from now)",
                day, day + 1, TARGET_FORMAT.format(Instant.ofEpochMilli(target)),
                RealtimeMath.remainingText(target - now));
        return "Next phase (day " + day + " -> " + (day + 1) + ") scheduled at "
                + TARGET_FORMAT.format(Instant.ofEpochMilli(target)) + " — in "
                + RealtimeMath.remainingText(target - now);
    }

    /** Clears the one-shot schedule. Returns a feedback line ({@code null} = nothing was set). */
    @Nullable
    public static String clear(MinecraftServer server) {
        long cleared = RealtimeDayService.clearManualOverride(server);
        if (cleared < 0L) {
            return null;
        }
        EclipseMod.LOGGER.info("PhaseScheduler: schedule cleared (was {})",
                TARGET_FORMAT.format(Instant.ofEpochMilli(cleared)));
        return "Phase schedule cleared (was " + TARGET_FORMAT.format(Instant.ofEpochMilli(cleared)) + ")";
    }

    /** Whether a one-shot next-phase schedule is currently set (manual override pending). */
    public static boolean isScheduled(MinecraftServer server) {
        return RealtimeDayService.isManualOverridePending(server);
    }

    /** One human-readable schedule line for {@code schedule list} and the W14 timeline inspector. */
    public static String describe(MinecraftServer server) {
        if (!isScheduled(server)) {
            return "none";
        }
        long target = RealtimeState.get(server).getBoundaryEpochMillis();
        long remaining = target - EclipseClock.epochMillis();
        return TARGET_FORMAT.format(Instant.ofEpochMilli(target))
                + (remaining > 0 ? " (in " + RealtimeMath.remainingText(remaining) + ")"
                        : " (due — firing shortly)");
    }
}
