package dev.projecteclipse.eclipse.progression.realtime;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.format.DateTimeParseException;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Pure, static real-time day-boundary math (R1, P4-B1). No Minecraft types, no statics
 * with state — everything here is deterministic from its arguments so gametests can
 * cover the DST / catch-up / clock-skew edge cases without a running clock.
 *
 * <p>All epoch values are UTC millis; time-zone conversion happens only inside these
 * helpers ("UTC-internal, zone at the edges").</p>
 */
public final class RealtimeMath {
    /**
     * Relative spec accepted by {@link #parseSpec}: {@code +2h30m}, {@code +45m}, {@code +90s}
     * (at least one part). The leading sign is captured so {@link #parseSignedOffsetMillis}
     * can reuse the same grammar for {@code /eclipse-rt add -20m}.
     */
    private static final Pattern RELATIVE_SPEC =
            Pattern.compile("([+-])(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?");

    private RealtimeMath() {}

    /**
     * The next occurrence of {@code boundaryTime} in {@code zone} STRICTLY after
     * {@code nowEpochMillis}, as epoch millis.
     *
     * <p>DST-correct by construction: {@link ZonedDateTime#of} normalizes a wall time that
     * falls inside a spring-forward gap by shifting it forward by the gap length (Berlin
     * 2026-03-29: a 02:30 boundary resolves to 03:30 CEST), and resolves an ambiguous
     * fall-back wall time to the EARLIER offset (Berlin 2026-10-25: 02:30 resolves to
     * 02:30 CEST, the first pass). Successive 18:00 boundaries across those transitions
     * are therefore 23 h / 25 h apart — never silently 24 h.</p>
     */
    public static long nextBoundary(long nowEpochMillis, ZoneId zone, LocalTime boundaryTime) {
        Instant now = Instant.ofEpochMilli(nowEpochMillis);
        LocalDate localToday = now.atZone(zone).toLocalDate();
        ZonedDateTime candidate = ZonedDateTime.of(localToday, boundaryTime, zone);
        if (!candidate.toInstant().isAfter(now)) {
            candidate = ZonedDateTime.of(localToday.plusDays(1), boundaryTime, zone);
        }
        return candidate.toInstant().toEpochMilli();
    }

    /** The calendar day of {@code epochMillis} in {@code zone}, as {@link LocalDate#toEpochDay}. */
    public static long epochDay(long epochMillis, ZoneId zone) {
        return Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate().toEpochDay();
    }

    /**
     * Parses a boundary spec into absolute epoch millis: {@code +NhNNmNNs} relative to
     * {@code nowEpochMillis}, or an ISO-8601 local date-time ({@code 2026-08-01T18:00[:ss]})
     * interpreted in {@code zone}. Moved here from {@code devtools.PhaseScheduler} (W14);
     * the legacy delegate passes {@link ZoneId#systemDefault()} to keep
     * {@code /eclipse schedule next} verbatim, while {@code /eclipse-rt set} passes the
     * configured {@code realtime.json} zone.
     *
     * @throws IllegalArgumentException with a human-readable reason when unparseable
     */
    public static long parseSpec(String spec, long nowEpochMillis, ZoneId zone) {
        String trimmed = spec.trim();
        if (trimmed.startsWith("+")) {
            return nowEpochMillis + parseSignedOffsetMillis(trimmed);
        }
        try {
            LocalDateTime local = LocalDateTime.parse(trimmed);
            return ZonedDateTime.of(local, zone).toInstant().toEpochMilli();
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException("Bad date-time '" + spec
                    + "' — use ISO-8601 (e.g. 2026-08-01T18:00) or +NhNNm");
        }
    }

    /**
     * Parses a SIGNED relative offset ({@code +1h30m}, {@code -20m}, {@code +90s}) into
     * millis. Backs {@code /eclipse-rt add} where negative shifts are legal.
     *
     * @throws IllegalArgumentException when the spec has no sign, no parts, or bad syntax
     */
    public static long parseSignedOffsetMillis(String spec) {
        Matcher matcher = RELATIVE_SPEC.matcher(spec.trim());
        if (!matcher.matches() || (matcher.group(2) == null && matcher.group(3) == null
                && matcher.group(4) == null)) {
            throw new IllegalArgumentException("Bad relative spec '" + spec
                    + "' — use e.g. +2h30m, +45m, +90s or -20m");
        }
        long hours = matcher.group(2) == null ? 0 : Long.parseLong(matcher.group(2));
        long minutes = matcher.group(3) == null ? 0 : Long.parseLong(matcher.group(3));
        long seconds = matcher.group(4) == null ? 0 : Long.parseLong(matcher.group(4));
        long magnitude = ((hours * 60 + minutes) * 60 + seconds) * 1000L;
        return "-".equals(matcher.group(1)) ? -magnitude : magnitude;
    }

    /**
     * Result of {@link #catchUpPlan}: advance the event day {@code days} times, then set
     * the clock to {@code newBoundaryEpochMillis} (with {@code newPrevBoundaryEpochMillis}
     * as the progress origin — the last boundary that actually elapsed).
     */
    public record CatchUp(int days, long newBoundaryEpochMillis, long newPrevBoundaryEpochMillis) {}

    /**
     * How many day advances a downtime window owes, stepping boundary-by-boundary (NOT
     * collapsing to one — the pre-P4 {@code PhaseScheduler} bug class): starting from the
     * persisted {@code boundaryEpochMillis}, each elapsed boundary counts one day until
     * (a) the next boundary is in the future, (b) {@code currentDay + days} reaches
     * {@code maxDay}, or (c) {@code catchUpMaxDays} is exhausted.
     *
     * <p>When the loop stops for (b)/(c) with the stepped boundary still in the past, the
     * returned boundary is re-anchored to {@code nextBoundary(now)} so the clock resumes
     * sanely instead of re-firing every poll.</p>
     */
    public static CatchUp catchUpPlan(long nowEpochMillis, long boundaryEpochMillis, ZoneId zone,
            LocalTime boundaryTime, int currentDay, int maxDay, int catchUpMaxDays) {
        int days = 0;
        long boundary = boundaryEpochMillis;
        long prevBoundary = boundaryEpochMillis;
        while (boundary != 0L && boundary <= nowEpochMillis
                && currentDay + days < maxDay && days < catchUpMaxDays) {
            days++;
            prevBoundary = boundary;
            boundary = nextBoundary(boundary, zone, boundaryTime);
        }
        if (boundary != 0L && boundary <= nowEpochMillis) {
            // Cap hit ((b) or (c)) with elapsed boundaries left over: re-anchor forward.
            boundary = nextBoundary(nowEpochMillis, zone, boundaryTime);
        }
        return new CatchUp(days, boundary, prevBoundary);
    }

    /** {@code 2h 14m} / {@code 14m 3s} / {@code 42s} (coarsest two units) — bossbar/status text. */
    public static String remainingText(long millis) {
        long totalSeconds = Math.max(0L, millis / 1000L);
        long hours = totalSeconds / 3600;
        long minutes = totalSeconds % 3600 / 60;
        long seconds = totalSeconds % 60;
        if (hours > 0) {
            return hours + "h " + minutes + "m";
        }
        if (minutes > 0) {
            return minutes + "m " + seconds + "s";
        }
        return seconds + "s";
    }
}
