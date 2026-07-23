package dev.projecteclipse.eclipse.gametest.realtime;

import java.time.LocalTime;
import java.time.ZoneId;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B1 pure-math acceptance: {@code nextBoundary} across the 2026 Berlin DST
 * transitions, catch-up counting with both caps, and spec parsing. All expected epoch
 * millis were computed independently (python {@code zoneinfo}) — the tests never
 * re-derive them through the code under test.
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class RealtimeMathTest {
    private static final ZoneId BERLIN = ZoneId.of("Europe/Berlin");
    private static final LocalTime SIX_PM = LocalTime.of(18, 0);
    private static final LocalTime HALF_PAST_TWO = LocalTime.of(2, 30);

    // Independently computed epoch millis (Europe/Berlin, python zoneinfo):
    /** 2026-03-28T18:00+01:00 — the evening before the spring-forward night. */
    private static final long MAR28_1800_CET = 1_774_717_200_000L;
    /** 2026-03-29T18:00+02:00 — 23 real hours later (one wall-clock day across the gap). */
    private static final long MAR29_1800_CEST = 1_774_800_000_000L;
    /** 2026-03-29T01:59+01:00 — one minute before the 02:00→03:00 gap opens. */
    private static final long MAR29_0159_CET = 1_774_745_940_000L;
    /** 2026-03-29T03:30+02:00 — where a 02:30 wall time inside the gap normalizes to. */
    private static final long MAR29_0330_CEST = 1_774_747_800_000L;
    /** 2026-10-24T18:00+02:00 — the evening before the fall-back night. */
    private static final long OCT24_1800_CEST = 1_792_857_600_000L;
    /** 2026-10-25T18:00+01:00 — 25 real hours later (one wall-clock day across the overlap). */
    private static final long OCT25_1800_CET = 1_792_947_600_000L;
    /** 2026-10-25T01:00+02:00 — before the ambiguous 02:00-03:00 hour. */
    private static final long OCT25_0100_CEST = 1_792_882_800_000L;
    /** 2026-10-25T02:30+02:00 — the EARLIER of the two 02:30 wall times that night. */
    private static final long OCT25_0230_CEST_EARLIER = 1_792_888_200_000L;
    /** 2026-07-01T12:00+02:00 (no transition anywhere near). */
    private static final long JUL01_1200 = 1_782_900_000_000L;
    private static final long JUL01_1800 = 1_782_921_600_000L;
    private static final long JUL02_1800 = 1_783_008_000_000L;
    private static final long JUL03_1800 = 1_783_094_400_000L;
    private static final long JUL04_1800 = 1_783_180_800_000L;
    /** 2026-07-04T12:00+02:00 (JUL04_1800 - 6 h). */
    private static final long JUL04_1200 = 1_783_159_200_000L;
    /** 2026-08-01T18:00+02:00 — ISO parse expectation. */
    private static final long AUG01_1800 = 1_785_600_000_000L;

    private RealtimeMathTest() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nextBoundaryPlainAndStrictlyAfter(GameTestHelper helper) {
        // Midday → the same day's 18:00.
        assertEquals(helper, RealtimeMath.nextBoundary(JUL01_1200, BERLIN, SIX_PM),
                JUL01_1800, "plain same-day boundary");
        // Exactly AT the boundary → strictly after → the next day's.
        assertEquals(helper, RealtimeMath.nextBoundary(JUL01_1800, BERLIN, SIX_PM),
                JUL02_1800, "boundary instant rolls to next day");
        // One millisecond before still hits today.
        assertEquals(helper, RealtimeMath.nextBoundary(JUL01_1800 - 1L, BERLIN, SIX_PM),
                JUL01_1800, "1 ms early stays same-day");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nextBoundaryDstSpringForwardBerlin(GameTestHelper helper) {
        // 18:00 boundary across the 2026-03-29 02:00→03:00 gap: 23 real hours apart.
        long next = RealtimeMath.nextBoundary(MAR28_1800_CET, BERLIN, SIX_PM);
        assertEquals(helper, next, MAR29_1800_CEST, "spring 18:00 boundary");
        assertEquals(helper, next - MAR28_1800_CET, 23L * 3_600_000L, "spring interval is 23h");
        // A boundary time INSIDE the skipped hour normalizes forward by the gap length.
        assertEquals(helper, RealtimeMath.nextBoundary(MAR29_0159_CET, BERLIN, HALF_PAST_TWO),
                MAR29_0330_CEST, "02:30 in the gap resolves to 03:30 CEST");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void nextBoundaryDstFallBackBerlin(GameTestHelper helper) {
        // 18:00 boundary across the 2026-10-25 03:00→02:00 overlap: 25 real hours apart.
        long next = RealtimeMath.nextBoundary(OCT24_1800_CEST, BERLIN, SIX_PM);
        assertEquals(helper, next, OCT25_1800_CET, "fall 18:00 boundary");
        assertEquals(helper, next - OCT24_1800_CEST, 25L * 3_600_000L, "fall interval is 25h");
        // An ambiguous boundary time resolves to the EARLIER offset (first 02:30, CEST).
        assertEquals(helper, RealtimeMath.nextBoundary(OCT25_0100_CEST, BERLIN, HALF_PAST_TWO),
                OCT25_0230_CEST_EARLIER, "ambiguous 02:30 takes the earlier pass");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void epochDayUsesZoneCalendar(GameTestHelper helper) {
        // 2026-07-01T23:30 Berlin is already 2026-07-02 in e.g. Asia/Tokyo — zone matters.
        long lateEvening = JUL01_1800 + 5L * 3_600_000L + 1_800_000L; // 23:30 Berlin
        helper.assertTrue(
                RealtimeMath.epochDay(lateEvening, BERLIN)
                        == RealtimeMath.epochDay(JUL01_1200, BERLIN),
                "23:30 Berlin is still the same Berlin epoch day");
        helper.assertTrue(
                RealtimeMath.epochDay(lateEvening, ZoneId.of("Asia/Tokyo"))
                        == RealtimeMath.epochDay(JUL01_1200, BERLIN) + 1,
                "same instant is already the next day in Tokyo");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void catchUpPlanCountsMissedBoundaries(GameTestHelper helper) {
        // Down from Jul 1 (boundary 18:00) until Jul 4 12:00 → exactly 3 elapsed boundaries.
        RealtimeMath.CatchUp plan = RealtimeMath.catchUpPlan(
                JUL04_1200, JUL01_1800, BERLIN, SIX_PM, 1, 14, 13);
        assertEquals(helper, plan.days(), 3L, "3 missed boundaries -> +3 days");
        assertEquals(helper, plan.newBoundaryEpochMillis(), JUL04_1800, "resumes at Jul 4 18:00");
        assertEquals(helper, plan.newPrevBoundaryEpochMillis(), JUL03_1800, "origin is last elapsed");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void catchUpPlanRespectsMaxDayAndCap(GameTestHelper helper) {
        // maxDay cap: current day 12 of 14 → only 2 of the 3 elapsed boundaries advance,
        // and the leftover elapsed boundary re-anchors forward past `now`.
        RealtimeMath.CatchUp maxDayCapped = RealtimeMath.catchUpPlan(
                JUL04_1200, JUL01_1800, BERLIN, SIX_PM, 12, 14, 13);
        assertEquals(helper, maxDayCapped.days(), 2L, "capped at maxDay");
        assertEquals(helper, maxDayCapped.newBoundaryEpochMillis(), JUL04_1800,
                "leftover elapsed boundary re-anchors after now");

        // catchUpMaxDays cap: cap 2 → 2 advances, re-anchored the same way.
        RealtimeMath.CatchUp capCapped = RealtimeMath.catchUpPlan(
                JUL04_1200, JUL01_1800, BERLIN, SIX_PM, 1, 14, 2);
        assertEquals(helper, capCapped.days(), 2L, "capped at catchUpMaxDays");
        assertEquals(helper, capCapped.newBoundaryEpochMillis(), JUL04_1800, "re-anchored");

        // Nothing elapsed → zero days, boundary untouched.
        RealtimeMath.CatchUp none = RealtimeMath.catchUpPlan(
                JUL01_1200, JUL01_1800, BERLIN, SIX_PM, 1, 14, 13);
        assertEquals(helper, none.days(), 0L, "future boundary owes nothing");
        assertEquals(helper, none.newBoundaryEpochMillis(), JUL01_1800, "boundary untouched");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void parseSpecRelativeIsoAndErrors(GameTestHelper helper) {
        assertEquals(helper, RealtimeMath.parseSpec("+2h30m", 1_000L, BERLIN),
                1_000L + 9_000_000L, "+2h30m relative");
        assertEquals(helper, RealtimeMath.parseSpec("+90s", 0L, BERLIN), 90_000L, "+90s relative");
        assertEquals(helper, RealtimeMath.parseSpec("2026-08-01T18:00", 0L, BERLIN),
                AUG01_1800, "ISO in Berlin");
        // Signed offsets for /eclipse-rt add.
        assertEquals(helper, RealtimeMath.parseSignedOffsetMillis("-20m"), -1_200_000L, "-20m");
        assertEquals(helper, RealtimeMath.parseSignedOffsetMillis("+1h"), 3_600_000L, "+1h");
        assertThrows(helper, () -> RealtimeMath.parseSpec("garbage", 0L, BERLIN), "garbage spec");
        assertThrows(helper, () -> RealtimeMath.parseSignedOffsetMillis("20m"), "missing sign");
        assertThrows(helper, () -> RealtimeMath.parseSignedOffsetMillis("+"), "sign without parts");
        helper.succeed();
    }

    private static void assertEquals(GameTestHelper helper, long actual, long expected, String what) {
        helper.assertTrue(actual == expected,
                what + ": expected " + expected + " but got " + actual);
    }

    private static void assertThrows(GameTestHelper helper, Runnable body, String what) {
        try {
            body.run();
        } catch (IllegalArgumentException expected) {
            return;
        }
        helper.fail(what + ": expected IllegalArgumentException");
    }
}
