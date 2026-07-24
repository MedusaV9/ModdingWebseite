package dev.projecteclipse.eclipse.gametest.realtime;

import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.devtools.PhaseScheduler;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayApi;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.MinecraftServer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * P4-B1 engine acceptance: rollover signal order through the {@code DayScheduler} choke
 * point, injected-clock fires ({@code EclipseClock} supplier swap), the same-calendar-day
 * epoch-day guard (clock-backwards hardening), multi-day catch-up, pause persistence
 * across an NBT round-trip, legacy {@code /eclipse schedule} one-shot semantics, and the
 * out-of-band {@code /eclipse day set} re-anchor.
 *
 * <p>Every injected-clock test runs synchronously inside one invocation (no server ticks
 * interleave with a swapped clock), and every test disarms the engine, restores the entry
 * day and resets the clock supplier before succeeding, so the shared gametest server stays
 * clean for sibling packages. Only the bossbar test spans real ticks — on the real clock.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class RealtimeEngineTest {
    private static final ZoneId BERLIN = ZoneId.of("Europe/Berlin");

    // Same independently computed Berlin instants as RealtimeMathTest.
    private static final long JUL01_1200 = 1_782_900_000_000L;
    private static final long JUL01_1800 = 1_782_921_600_000L;
    private static final long JUL02_1800 = 1_783_008_000_000L;
    private static final long JUL03_1800 = 1_783_094_400_000L;
    private static final long JUL04_1200 = 1_783_159_200_000L;
    private static final long JUL04_1800 = 1_783_180_800_000L;

    private RealtimeEngineTest() {}

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void pauseStateSurvivesNbtRoundTrip(GameTestHelper helper) {
        RealtimeState state = new RealtimeState();
        state.setArmed(true);
        state.setPaused(true);
        state.setPauseRemainingMillis(21_600_000L);
        state.setBoundaryEpochMillis(JUL01_1800);
        state.setPrevBoundaryEpochMillis(JUL01_1200);
        state.setLastAdvanceEpochDay(20_636L);
        state.setManualOverride(true);
        state.setArmedByScheduleOnly(true);
        state.setAutoArmDone(true);

        CompoundTag tag = state.save(new CompoundTag(), helper.getLevel().registryAccess());
        RealtimeState loaded = RealtimeState.load(tag, helper.getLevel().registryAccess());

        helper.assertTrue(loaded.isArmed(), "armed survives");
        helper.assertTrue(loaded.isPaused(), "paused survives");
        helper.assertTrue(loaded.getPauseRemainingMillis() == 21_600_000L, "frozen remaining survives");
        helper.assertTrue(loaded.getBoundaryEpochMillis() == JUL01_1800, "boundary survives");
        helper.assertTrue(loaded.getPrevBoundaryEpochMillis() == JUL01_1200, "prev boundary survives");
        helper.assertTrue(loaded.getLastAdvanceEpochDay() == 20_636L, "epoch-day guard survives");
        helper.assertTrue(loaded.isManualOverride(), "manual override survives");
        helper.assertTrue(loaded.isArmedByScheduleOnly(), "schedule-only flag survives");
        helper.assertTrue(loaded.isAutoArmDone(), "auto-arm flag survives");
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void rolloverSignalOrderPreSetPost(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicBoolean active = new AtomicBoolean(true);
        List<String> order = new ArrayList<>();
        EclipseSignals.onDayRollover((srv, ended, newDay, phase) -> {
            if (active.get()) {
                // Record the phase plus the day VISIBLE IN STATE at callback time: PRE must
                // still see the ended day (awards/offerings read it), POST the new day.
                order.add(phase + ":" + ended + ">" + newDay + "@" + DayScheduler.getDay(srv));
            }
        });
        try {
            GameTestSupport.setEventDay(server, 3);
            order.clear();
            DayScheduler.setDay(server, 4); // manual +1 = a full rollover
            helper.assertTrue(order.size() == 2, "exactly PRE+POST, got " + order);
            helper.assertTrue("PRE:3>4@3".equals(order.get(0)), "PRE before persist, got " + order);
            helper.assertTrue("POST:3>4@4".equals(order.get(1)), "POST after persist, got " + order);

            order.clear();
            DayScheduler.setDay(server, 6); // jump: an admin correction, never a rollover
            helper.assertTrue(order.isEmpty(), "jump fired signals: " + order);

            order.clear();
            DayScheduler.setDay(server, 5); // decrease: same
            helper.assertTrue(order.isEmpty(), "decrease fired signals: " + order);
        } finally {
            active.set(false);
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void injectedClockFireThenSameDayGuardThenNextDay(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            GameTestSupport.setEventDay(server, 2);
            RealtimeDayApi.arm(server);
            RealtimeState state = RealtimeState.get(server);
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL01_1800,
                    "armed on the Berlin 18:00 cadence, got " + state.getBoundaryEpochMillis());

            // One-shot boundary 60 s out; passing it advances exactly one day.
            RealtimeDayApi.setBoundary(server, "+1m", BERLIN);
            clock.set(JUL01_1200 + 120_000L);
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 3, "manual boundary advanced to day 3");
            helper.assertTrue(!state.isManualOverride(), "one-shot override consumed");
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL01_1800,
                    "re-armed to the cadence boundary, got " + state.getBoundaryEpochMillis());

            // The same Berlin calendar day already advanced -> the 18:00 slot is guard-
            // blocked (backwards-NTP / double-advance hardening) and skips to tomorrow.
            clock.set(JUL01_1800 + 3_600_000L); // 19:00 Berlin
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 3, "guard blocked the same-day slot");
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL02_1800,
                    "slot skipped to Jul 2 18:00, got " + state.getBoundaryEpochMillis());

            // Tomorrow's slot fires normally.
            clock.set(JUL02_1800 + 60_000L);
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 4, "next-day slot advanced to day 4");
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL03_1800,
                    "re-armed to Jul 3 18:00, got " + state.getBoundaryEpochMillis());
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void catchUpAdvancesOncePerMissedBoundary(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        AtomicBoolean active = new AtomicBoolean(true);
        List<String> signals = new ArrayList<>();
        EclipseSignals.onDayRollover((srv, ended, newDay, phase) -> {
            if (active.get()) {
                signals.add(phase + ":" + ended + ">" + newDay);
            }
        });
        try {
            GameTestSupport.setEventDay(server, 1);
            RealtimeDayApi.arm(server); // boundary Jul 1 18:00
            signals.clear();

            clock.set(JUL04_1200); // "reboot" 3 missed boundaries later
            int advanced = RealtimeDayService.runCatchUpNow(server);

            helper.assertTrue(advanced == 3, "caught up 3 days, got " + advanced);
            helper.assertTrue(DayScheduler.getDay(server) == 4, "day landed on 4");
            RealtimeState state = RealtimeState.get(server);
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL04_1800,
                    "clock resumes at Jul 4 18:00, got " + state.getBoundaryEpochMillis());
            helper.assertTrue(state.getPrevBoundaryEpochMillis() == JUL03_1800,
                    "origin is the last elapsed boundary, got " + state.getPrevBoundaryEpochMillis());
            List<String> expected = List.of("PRE:1>2", "POST:1>2", "PRE:2>3", "POST:2>3",
                    "PRE:3>4", "POST:3>4");
            helper.assertTrue(expected.equals(signals),
                    "PRE/POST fired per skipped day in order, got " + signals);

            helper.assertTrue(RealtimeDayService.runCatchUpNow(server) == 0,
                    "second catch-up owes nothing");
        } finally {
            active.set(false);
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void pauseFreezesAcrossElapsedBoundaryAndResumeShifts(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            GameTestSupport.setEventDay(server, 2);
            RealtimeDayApi.arm(server); // boundary Jul 1 18:00
            long frozen = RealtimeDayApi.pause(server);
            helper.assertTrue(frozen == 21_600_000L, "froze 6h remaining, got " + frozen);

            // The boundary instant passes while paused: nothing may fire.
            clock.set(JUL01_1200 + 36_000_000L); // 22:00 Berlin, 4h past the old boundary
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 2, "paused clock never fires");

            // Simulated save/load while paused: the frozen window is what persists.
            RealtimeState live = RealtimeState.get(server);
            CompoundTag tag = live.save(new CompoundTag(), helper.getLevel().registryAccess());
            RealtimeState reloaded = RealtimeState.load(tag, helper.getLevel().registryAccess());
            helper.assertTrue(reloaded.isPaused() && reloaded.getPauseRemainingMillis() == 21_600_000L,
                    "frozen remaining survives save/load, got " + reloaded.getPauseRemainingMillis());

            // Resume: boundary = now + frozen remaining (Jul 2 04:00), regardless of downtime.
            long resumed = RealtimeDayApi.resume(server);
            helper.assertTrue(resumed == JUL01_1200 + 36_000_000L + 21_600_000L,
                    "resume re-derives boundary from frozen remaining, got " + resumed);
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void legacyScheduleNextFiresOnceAndDisarms(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            GameTestSupport.setEventDay(server, 2);
            RealtimeDayApi.disarm(server); // pure-legacy usage: engine idle

            PhaseScheduler.scheduleNext(server, "+90s");
            helper.assertTrue(PhaseScheduler.isScheduled(server), "schedule pending");

            clock.addAndGet(100_000L);
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 3, "schedule advanced exactly one day");
            helper.assertTrue(!RealtimeDayApi.isArmed(server),
                    "engine armed only by the one-shot disarms after firing (W14 verbatim)");
            helper.assertTrue(!PhaseScheduler.isScheduled(server), "nothing scheduled anymore");
            helper.assertTrue(PhaseScheduler.clear(server) == null, "clear reports nothing to clear");

            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 3, "no further fires");

            // clear() on a pending schedule (never fired) also fully disarms a schedule-only arm.
            PhaseScheduler.scheduleNext(server, "+90s");
            helper.assertTrue(PhaseScheduler.clear(server) != null, "clear reports the cleared target");
            helper.assertTrue(!RealtimeDayApi.isArmed(server), "schedule-only arm cleared to disarmed");
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    /**
     * Acceptance "bossbar appears/disappears": the live 20-tick loop creates the countdown
     * bar for an armed engine; disarm removes it synchronously. Uses the REAL clock (the
     * armed cadence boundary is hours away — nothing can fire mid-test).
     */
    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void bossbarAppearsWhileArmedAndDisappearsOnDisarm(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        GameTestSupport.setEventDay(server, 2);
        RealtimeDayApi.arm(server);
        helper.runAfterDelay(45L, () -> { // ≥2 bar-update ticks later
            try {
                helper.assertTrue(RealtimeDayService.isBarVisible(),
                        "armed engine shows the countdown bossbar");
                RealtimeDayApi.disarm(server);
                helper.assertTrue(!RealtimeDayService.isBarVisible(),
                        "disarming removes the bossbar immediately");
            } finally {
                RealtimeDayApi.disarm(server);
                GameTestSupport.setEventDay(server, Math.max(1, entryDay));
            }
            helper.succeed();
        });
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void outOfBandDaySetReanchorsTheClock(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            GameTestSupport.setEventDay(server, 2);
            RealtimeDayApi.arm(server);
            RealtimeDayApi.setBoundary(server, "+1h", BERLIN); // manual 13:00 boundary
            RealtimeState state = RealtimeState.get(server);
            helper.assertTrue(state.isManualOverride(), "manual override pending");

            DayScheduler.setDay(server, 5); // out-of-band jump (admin correction)
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL01_1800,
                    "clock re-anchored to the cadence, got " + state.getBoundaryEpochMillis());
            helper.assertTrue(!state.isManualOverride(), "manual override dropped on re-anchor");
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }
}
