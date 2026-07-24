package dev.projecteclipse.eclipse.gametest.realtime;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.ZoneId;
import java.util.concurrent.atomic.AtomicLong;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.gametest.GameTestSupport;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeConfig;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayApi;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeMath;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import net.minecraft.gametest.framework.GameTest;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.server.MinecraftServer;
import net.neoforged.neoforge.gametest.GameTestHolder;
import net.neoforged.neoforge.gametest.PrefixGameTestTemplate;

/**
 * D6 acceptance: the {@code cadenceMode: interval} phase chain. Boundaries chain every
 * {@code intervalHours} with an injected {@link EclipseClock}, the epoch-day dedup guard
 * does NOT apply in interval mode (several advances per calendar day are the point),
 * catch-up steps interval-by-interval, and the cadence switch persists through a
 * {@code realtime.json} write + reload round-trip.
 *
 * <p>Same hygiene as {@link RealtimeEngineTest}: injected-clock tests run synchronously in
 * one invocation, and every test disarms, restores the entry day, the system clock and the
 * real config directory before succeeding.</p>
 */
@PrefixGameTestTemplate(false)
@GameTestHolder(EclipseMod.MOD_ID)
public final class IntervalCadenceTests {
    /** 2026-07-01T12:00+02:00 Berlin (same instant as RealtimeEngineTest.JUL01_1200). */
    private static final long JUL01_1200 = 1_782_900_000_000L;
    private static final long TWO_HOURS = 7_200_000L;

    private IntervalCadenceTests() {}

    private static Path intervalConfigDir(double hours) {
        try {
            Path dir = Files.createTempDirectory("eclipse-interval-test");
            Files.writeString(dir.resolve("realtime.json"), """
                    { "zone": "Europe/Berlin", "boundaryTime": "18:00",
                      "cadenceMode": "interval", "intervalHours": %s,
                      "autoArmOnStartEvent": false, "catchUpMaxDays": 13, "clientSyncSeconds": 5 }
                    """.formatted(hours));
            return dir;
        } catch (Exception e) {
            throw new AssertionError("temp config dir", e);
        }
    }

    private static void restoreRealConfig() {
        RealtimeConfig.setConfigDirForTests(
                net.neoforged.fml.loading.FMLPaths.CONFIGDIR.get().resolve("eclipse"));
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void intervalChainFiresTwicePerCalendarDayNoDedup(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            RealtimeConfig.setConfigDirForTests(intervalConfigDir(2.0));
            helper.assertTrue(RealtimeConfig.get().cadenceMode() == RealtimeConfig.CadenceMode.INTERVAL,
                    "interval config loaded");
            GameTestSupport.setEventDay(server, 2);

            long boundary = RealtimeDayApi.arm(server);
            helper.assertTrue(boundary == JUL01_1200 + TWO_HOURS,
                    "armed 2h out (14:00 Berlin), got " + boundary);

            // 14:00 Berlin: first interval fire.
            clock.set(JUL01_1200 + TWO_HOURS + 1_000L);
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 3, "first interval advanced to day 3");
            RealtimeState state = RealtimeState.get(server);
            long second = state.getBoundaryEpochMillis();
            helper.assertTrue(second == clock.get() + TWO_HOURS,
                    "re-armed 2h from the fire (16:00 Berlin), got " + second);

            // 16:00 Berlin, SAME calendar day: the epoch-day guard must NOT block interval mode.
            ZoneId berlin = ZoneId.of("Europe/Berlin");
            helper.assertTrue(RealtimeMath.epochDay(clock.get(), berlin)
                            == RealtimeMath.epochDay(second, berlin),
                    "both fires land on the same Berlin calendar day");
            clock.set(second + 1_000L);
            RealtimeDayService.runFireCheckNow(server);
            helper.assertTrue(DayScheduler.getDay(server) == 4,
                    "second same-calendar-day interval advanced to day 4 (no epoch-day dedup)");
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            restoreRealConfig();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void intervalCatchUpStepsIntervalByInterval(GameTestHelper helper) {
        MinecraftServer server = helper.getLevel().getServer();
        int entryDay = DayScheduler.getDay(server);
        AtomicLong clock = new AtomicLong(JUL01_1200);
        EclipseClock.setEpochMillisSupplier(clock::get);
        try {
            RealtimeConfig.setConfigDirForTests(intervalConfigDir(2.0));
            GameTestSupport.setEventDay(server, 1);
            RealtimeDayApi.arm(server); // boundary 14:00

            clock.set(JUL01_1200 + 6 * 3_600_000L + 1_800_000L); // "reboot" at 18:30 Berlin
            int advanced = RealtimeDayService.runCatchUpNow(server);

            helper.assertTrue(advanced == 3, "3 elapsed intervals (14/16/18h) caught up, got " + advanced);
            helper.assertTrue(DayScheduler.getDay(server) == 4, "day landed on 4");
            RealtimeState state = RealtimeState.get(server);
            helper.assertTrue(state.getBoundaryEpochMillis() == JUL01_1200 + 8 * 3_600_000L,
                    "clock resumes at the next interval slot (20:00 Berlin), got "
                            + state.getBoundaryEpochMillis());
            helper.assertTrue(RealtimeDayService.runCatchUpNow(server) == 0,
                    "second catch-up owes nothing");
        } finally {
            RealtimeDayApi.disarm(server);
            EclipseClock.resetToSystem();
            restoreRealConfig();
            GameTestSupport.setEventDay(server, Math.max(1, entryDay));
        }
        helper.succeed();
    }

    @GameTest(template = GameTestSupport.EMPTY_TEMPLATE)
    public static void cadenceSwitchPersistsThroughReloadRoundTrip(GameTestHelper helper) {
        try {
            Path dir = intervalConfigDir(2.0);
            RealtimeConfig.setConfigDirForTests(dir);

            // interval -> daily: persisted and re-parsed, intervalHours preserved.
            RealtimeConfig.setCadence(RealtimeConfig.CadenceMode.DAILY, 0.0);
            RealtimeConfig.reload();
            RealtimeConfig.Config reloaded = RealtimeConfig.get();
            helper.assertTrue(reloaded.cadenceMode() == RealtimeConfig.CadenceMode.DAILY,
                    "daily mode survives the file round-trip");
            helper.assertTrue(reloaded.intervalHours() == 2.0,
                    "intervalHours untouched by the daily switch, got " + reloaded.intervalHours());

            // daily -> interval 0.5h: persisted and re-parsed.
            RealtimeConfig.setCadence(RealtimeConfig.CadenceMode.INTERVAL, 0.5);
            RealtimeConfig.reload();
            reloaded = RealtimeConfig.get();
            helper.assertTrue(reloaded.cadenceMode() == RealtimeConfig.CadenceMode.INTERVAL,
                    "interval mode survives the file round-trip");
            helper.assertTrue(reloaded.intervalHours() == 0.5,
                    "intervalHours survives, got " + reloaded.intervalHours());
            helper.assertTrue(reloaded.intervalMillis() == 1_800_000L,
                    "intervalMillis derives 30m, got " + reloaded.intervalMillis());

            // Unrelated fields must survive the read-modify-write.
            helper.assertTrue(!reloaded.autoArmOnStartEvent(),
                    "unrelated autoArmOnStartEvent=false preserved by the cadence write");
        } finally {
            restoreRealConfig();
        }
        helper.succeed();
    }
}
