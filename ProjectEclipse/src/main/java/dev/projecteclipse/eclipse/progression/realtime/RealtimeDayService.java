package dev.projecteclipse.eclipse.progression.realtime;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.network.S2CBossbarStylePayload;
import dev.projecteclipse.eclipse.network.S2CDayClockPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.BossEvent;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Real-time day engine (R1, P4-B1): the 14-day arc advances at persistent real-world
 * boundaries ({@code realtime.json}: {@code zone} + {@code boundaryTime}, default Berlin
 * 18:00) instead of one-shot schedules. Replaces the firing half of the W14
 * {@code devtools.PhaseScheduler} (now a thin delegate into this service) and the
 * {@code dayAutoAdvance} half of {@code DayScheduler} (deprecated, parsed but ignored).
 *
 * <ul>
 *   <li><b>Model</b>: {@link RealtimeState} persists the next boundary; after every advance
 *       the following boundary is derived ({@link RealtimeMath#nextBoundary}) and persisted,
 *       so the arc re-arms itself across all 14 days and all restarts.</li>
 *   <li><b>Rollover choke point</b>: every advance goes through
 *       {@code DayScheduler.setDay(server, day + 1)}, which fires
 *       {@code EclipseSignals.dayRollover} PRE before persisting and POST after the legacy
 *       side effects (bell, announcements, {@code applyDayTriggers} ring expansion) — this
 *       service only decides WHEN and hands the boundary bookkeeping in via
 *       {@link #onDayApplied}.</li>
 *   <li><b>Catch-up</b>: on {@link ServerStartedEvent} elapsed boundaries are replayed one
 *       rollover per missed day (bounded by {@code catchUpMaxDays} and
 *       {@code EclipseConfig.maxDay()}), quiet except for the final day reached.</li>
 *   <li><b>Skew hardening</b>: {@code lastAdvanceEpochDay} (zone-local) blocks a second
 *       schedule-derived advance in the same calendar slot after a backwards wall-clock
 *       jump; a poll-to-poll regression &gt; 60 s logs a WARN. Manual one-shot boundaries
 *       ({@code /eclipse schedule next}, {@code /eclipse-rt set|add}) bypass the guard.</li>
 *   <li><b>Clients</b>: {@link S2CDayClockPayload} is broadcast on every state change, at
 *       login, and re-synced every {@code clientSyncSeconds} while armed. The countdown
 *       bossbar keeps the exact W14 rendering (purple, {@code day} theme).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RealtimeDayService {
    /** Wall-clock fire/auto-arm check cadence (5 s — the legacy scheduler/auto-advance poll). */
    private static final int FIRE_CHECK_TICKS = 100;
    /** Bossbar text/progress refresh cadence (1 s). */
    private static final int BAR_UPDATE_TICKS = 20;
    /**
     * W4-CEREMONY / IDEA-09 #2: inside this window before the boundary, the fire check runs
     * on EVERY bar pass (1 s) instead of the 5 s poll, so the flip lands ON the T-0 climax
     * ({@code LastMinuteHush} release + {@code ui.timer_zero}) instead of up to 5 s late.
     */
    private static final long NEAR_BOUNDARY_MILLIS = 15_000L;
    /** {@code add}/{@code set} clamp: a shifted boundary is never closer than this. */
    public static final long MIN_FUTURE_MILLIS = 5_000L;
    /** Poll-to-poll backwards jump beyond this logs a WARN (NTP correction etc.). */
    private static final long CLOCK_REGRESS_WARN_MILLIS = 60_000L;

    private static final DateTimeFormatter TARGET_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** ReloadHooks registration is once per JVM (hooks outlive saves by design). */
    private static final AtomicBoolean RELOAD_HOOK_REGISTERED = new AtomicBoolean();

    /** The one lazy global countdown bar; {@code null} whenever disarmed. */
    // statics reset on ServerStopped
    @Nullable
    private static ServerBossEvent bossEvent;
    /** True while THIS service drives a {@code DayScheduler.setDay} (rollover in flight). */
    // statics reset on ServerStopped
    private static boolean rollingOver = false;
    /** Boundary to install after the in-flight rollover's day is applied. */
    // statics reset on ServerStopped
    private static long pendingBoundaryEpochMillis = 0L;
    /** Last fire-check poll's clock reading (backwards-jump WARN baseline). */
    // statics reset on ServerStopped
    private static long lastPollNowMillis = 0L;
    /** Last client re-sync broadcast (epoch millis). */
    // statics reset on ServerStopped
    private static long lastClientSyncMillis = 0L;

    private RealtimeDayService() {}

    // --- dev API backing (surfaced by RealtimeDayApi for P5-W3; reference commands in RealtimeCommands) ---

    /**
     * Arms the engine on the configured cadence: the next boundary is the next occurrence
     * of {@code boundaryTime} in {@code zone} after now. Clears pause, any one-shot
     * override AND the same-calendar-day dedup baseline (an explicit re-arm is operator
     * intent to start a fresh cadence). Returns the armed boundary (epoch millis).
     */
    public static long arm(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        long boundary = RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime());
        state.setArmed(true);
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        state.setManualOverride(false);
        state.setArmedByScheduleOnly(false);
        state.setAutoArmDone(true);
        state.setLastAdvanceEpochDay(-1L);
        state.setPrevBoundaryEpochMillis(now);
        state.setBoundaryEpochMillis(boundary);
        EclipseMod.LOGGER.info("RealtimeDayService: armed — day {} advances at {} ({} from now)",
                DayScheduler.getDay(server), formatInstant(boundary, cfg.zone()),
                RealtimeMath.remainingText(boundary - now));
        broadcastClock(server);
        return boundary;
    }

    /** Disarms the engine entirely (no further advances; countdown hidden). */
    public static void disarm(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        state.setArmed(false);
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        state.setManualOverride(false);
        state.setArmedByScheduleOnly(false);
        state.setAutoArmDone(true);
        state.setBoundaryEpochMillis(0L);
        state.setPrevBoundaryEpochMillis(0L);
        removeBar();
        EclipseMod.LOGGER.info("RealtimeDayService: disarmed");
        broadcastClock(server);
    }

    /**
     * Freezes the countdown: the remaining window is stored and the boundary stops being
     * compared against the clock. Returns the frozen remaining millis, or {@code -1} when
     * the clock is not running (disarmed or already paused).
     */
    public static long pause(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed() || state.isPaused()) {
            return -1L;
        }
        long now = EclipseClock.epochMillis();
        long remaining = Math.max(0L, state.getBoundaryEpochMillis() - now);
        state.setPauseRemainingMillis(remaining);
        state.setPaused(true);
        EclipseMod.LOGGER.info("RealtimeDayService: paused with {} remaining",
                RealtimeMath.remainingText(remaining));
        broadcastClock(server);
        return remaining;
    }

    /**
     * Resumes a paused countdown: boundary = now + frozen remaining. Returns the new
     * boundary (epoch millis), or {@code -1} when not paused.
     */
    public static long resume(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed() || !state.isPaused()) {
            return -1L;
        }
        long now = EclipseClock.epochMillis();
        long boundary = now + Math.max(0L, state.getPauseRemainingMillis());
        state.setBoundaryEpochMillis(boundary);
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        EclipseMod.LOGGER.info("RealtimeDayService: resumed — boundary {}",
                formatInstant(boundary, RealtimeConfig.get().zone()));
        broadcastClock(server);
        return boundary;
    }

    /**
     * Shifts the pending boundary by {@code deltaMillis} (negative = sooner), clamped so it
     * never lands closer than {@link #MIN_FUTURE_MILLIS} from now. While paused the frozen
     * remaining window is shifted instead. Marks a one-shot manual override and broadcasts
     * the clock immediately (P3 animates the spool from consecutive payloads whose boundary
     * changed while the day did not). Returns the new remaining millis, or {@code -1} when
     * disarmed.
     */
    public static long addMillis(MinecraftServer server, long deltaMillis) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed()) {
            return -1L;
        }
        long now = EclipseClock.epochMillis();
        long remaining;
        if (state.isPaused()) {
            remaining = Math.max(MIN_FUTURE_MILLIS, state.getPauseRemainingMillis() + deltaMillis);
            state.setPauseRemainingMillis(remaining);
        } else {
            long boundary = Math.max(now + MIN_FUTURE_MILLIS, state.getBoundaryEpochMillis() + deltaMillis);
            state.setBoundaryEpochMillis(boundary);
            remaining = boundary - now;
        }
        state.setManualOverride(true);
        EclipseMod.LOGGER.info("RealtimeDayService: boundary shifted by {} ms — {} remaining",
                deltaMillis, RealtimeMath.remainingText(remaining));
        broadcastClock(server);
        return remaining;
    }

    /**
     * Sets an explicit one-shot boundary from a spec ({@code +NhNNm[NNs]} or ISO-8601 in
     * {@code specZone}); arms the engine when disarmed (tracked so a legacy
     * {@code /eclipse schedule clear} can fully disarm again) and clears any pause.
     * Returns the target epoch millis.
     *
     * @throws IllegalArgumentException when the spec is unparseable or not in the future
     */
    public static long setBoundarySpec(MinecraftServer server, String spec, ZoneId specZone) {
        long now = EclipseClock.epochMillis();
        long target = RealtimeMath.parseSpec(spec, now, specZone);
        if (target <= now) {
            throw new IllegalArgumentException("Target " + formatInstant(target, specZone)
                    + " is not in the future");
        }
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed()) {
            state.setArmed(true);
            state.setArmedByScheduleOnly(true);
            state.setAutoArmDone(true);
        }
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        state.setPrevBoundaryEpochMillis(now);
        state.setBoundaryEpochMillis(target);
        state.setManualOverride(true);
        EclipseMod.LOGGER.info("RealtimeDayService: one-shot boundary set to {} ({} from now)",
                formatInstant(target, specZone), RealtimeMath.remainingText(target - now));
        broadcastClock(server);
        return target;
    }

    /**
     * Clears a pending one-shot override (legacy {@code /eclipse schedule clear} semantics):
     * an engine armed ONLY by that schedule disarms fully; an engine on the regular cadence
     * reverts to the next schedule-derived boundary. Returns the cleared target, or
     * {@code -1} when no one-shot override was set.
     */
    public static long clearManualOverride(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed() || !state.isManualOverride()) {
            return -1L;
        }
        long cleared = state.getBoundaryEpochMillis();
        state.setManualOverride(false);
        if (state.isArmedByScheduleOnly()) {
            disarm(server);
            return cleared;
        }
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        state.setPrevBoundaryEpochMillis(now);
        state.setBoundaryEpochMillis(RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime()));
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        EclipseMod.LOGGER.info("RealtimeDayService: one-shot override cleared — reverted to {}",
                formatInstant(state.getBoundaryEpochMillis(), cfg.zone()));
        broadcastClock(server);
        return cleared;
    }

    /** Whether an explicit one-shot boundary is pending (legacy {@code isScheduled}). */
    public static boolean isManualOverridePending(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        return state.isArmed() && state.isManualOverride();
    }

    /** One human-readable status line (dev commands + P5 surface). */
    public static String status(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        int day = DayScheduler.getDay(server);
        if (!state.isArmed()) {
            return "disarmed (day " + day + "/" + EclipseConfig.maxDay() + ")";
        }
        if (state.isPaused()) {
            return "PAUSED (day " + day + "/" + EclipseConfig.maxDay() + ", "
                    + RealtimeMath.remainingText(state.getPauseRemainingMillis()) + " frozen)";
        }
        long now = EclipseClock.epochMillis();
        return "armed (day " + day + "/" + EclipseConfig.maxDay() + ", next boundary "
                + formatInstant(state.getBoundaryEpochMillis(), cfg.zone()) + " " + cfg.zone()
                + ", in " + RealtimeMath.remainingText(state.getBoundaryEpochMillis() - now) + ")"
                + (state.isManualOverride() ? " [one-shot override]" : "");
    }

    /** Formats an instant in the given zone for logs/feedback ({@code yyyy-MM-dd HH:mm:ss}). */
    public static String formatInstant(long epochMillis, ZoneId zone) {
        return TARGET_FORMAT.format(Instant.ofEpochMilli(epochMillis).atZone(zone));
    }

    // --- clock payload (S2CDayClockPayload; handler already fills client/ClientStateCache) ---

    /** Builds the current clock payload. {@code boundaryEpochMillis == 0} = clock hidden. */
    public static S2CDayClockPayload buildClockPayload(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        boolean armed = state.isArmed();
        return new S2CDayClockPayload(
                EclipseWorldState.get(server).getDay(),
                armed ? state.getBoundaryEpochMillis() : 0L,
                armed ? state.getPrevBoundaryEpochMillis() : 0L,
                EclipseClock.epochMillis(),
                armed && state.isPaused(),
                armed && state.isPaused() ? state.getPauseRemainingMillis() : 0L);
    }

    /** Broadcasts the clock to every online player (state changes + periodic re-sync). */
    public static void broadcastClock(MinecraftServer server) {
        lastClientSyncMillis = EclipseClock.epochMillis();
        PacketDistributor.sendToAllPlayers(buildClockPayload(server));
    }

    // --- DayScheduler integration ---

    /**
     * Called by {@code DayScheduler} after a day change is persisted and its legacy side
     * effects ran, BEFORE the POST rollover signal (so POST listeners already see the new
     * boundary). Two cases:
     *
     * <ul>
     *   <li><b>Service-driven rollover</b> ({@link #rollingOver}): installs the boundary
     *       staged by {@link #rollover} and stamps the fired slot's zone-local epoch day.
     *       A one-shot boundary on a schedule-only armed engine disarms after firing
     *       (verbatim W14 {@code PhaseScheduler} semantics).</li>
     *   <li><b>Out-of-band change</b> ({@code /eclipse day set}, gametest helpers): the
     *       armed clock re-anchors to the next schedule-derived boundary, and an INCREASE
     *       stamps today so the same-real-day cadence fire is deduped (legacy
     *       auto-advance parity).</li>
     * </ul>
     */
    public static void onDayApplied(MinecraftServer server, int previousDay, int newDay) {
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        if (rollingOver) {
            long firedBoundary = state.getBoundaryEpochMillis();
            boolean oneShotOnly = state.isManualOverride() && state.isArmedByScheduleOnly();
            state.setPrevBoundaryEpochMillis(firedBoundary);
            state.setLastAdvanceEpochDay(RealtimeMath.epochDay(
                    firedBoundary > 0L ? firedBoundary : now, cfg.zone()));
            state.setManualOverride(false);
            state.setArmedByScheduleOnly(false);
            if (oneShotOnly) {
                // Armed solely by a legacy one-shot schedule: fire once, then nothing re-arms.
                state.setArmed(false);
                state.setBoundaryEpochMillis(0L);
                removeBar();
                EclipseMod.LOGGER.info("RealtimeDayService: one-shot schedule fired — engine disarmed "
                        + "(arm via /eclipse-rt arm for the recurring cadence)");
            } else {
                state.setBoundaryEpochMillis(pendingBoundaryEpochMillis);
            }
        } else if (state.isArmed() && previousDay != newDay) {
            // Out-of-band /eclipse day set (or a gametest helper): re-anchor per plan §2.1.
            state.setPrevBoundaryEpochMillis(now);
            state.setBoundaryEpochMillis(RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime()));
            state.setManualOverride(false);
            state.setArmedByScheduleOnly(false);
            if (newDay > previousDay) {
                state.setLastAdvanceEpochDay(RealtimeMath.epochDay(now, cfg.zone()));
            }
            EclipseMod.LOGGER.info("RealtimeDayService: out-of-band day change {} -> {} — "
                    + "re-anchored next boundary to {}", previousDay, newDay,
                    formatInstant(state.getBoundaryEpochMillis(), cfg.zone()));
        }
        if (state.isArmed() && newDay >= EclipseConfig.maxDay()) {
            EclipseMod.LOGGER.info("RealtimeDayService: day {} is the final configured day — "
                    + "arc complete, disarming", newDay);
            state.setArmed(false);
            state.setPaused(false);
            state.setPauseRemainingMillis(0L);
            state.setBoundaryEpochMillis(0L);
            removeBar();
        }
    }

    /**
     * The single rollover entry: stages the post-advance boundary, then routes through
     * {@code DayScheduler} (which fires the PRE/POST {@code dayRollover} signals around the
     * legacy day side effects and calls back into {@link #onDayApplied} + a clock broadcast).
     */
    private static void rollover(MinecraftServer server, boolean quiet, long newBoundaryEpochMillis) {
        int endedDay = DayScheduler.getDay(server);
        int newDay = endedDay + 1;
        pendingBoundaryEpochMillis = newBoundaryEpochMillis;
        rollingOver = true;
        try {
            if (quiet) {
                DayScheduler.setDayQuiet(server, newDay);
            } else {
                DayScheduler.setDay(server, newDay);
            }
        } finally {
            rollingOver = false;
            pendingBoundaryEpochMillis = 0L;
        }
    }

    // --- tick driver + fire checks ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % BAR_UPDATE_TICKS != 0) {
            return;
        }
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        if (state.isArmed()) {
            ensureBar(server);
            updateBar(state, now);
            if (now - lastClientSyncMillis >= cfg.clientSyncSeconds() * 1000L) {
                broadcastClock(server);
            }
        } else {
            removeBar();
        }
        if (server.getTickCount() % FIRE_CHECK_TICKS != 0) {
            // W4-CEREMONY / IDEA-09 #2: near-boundary precision — one extra long compare per
            // second in the final 15 s. The epoch-day guard keeps extra checks idempotent;
            // the skew/auto-arm bookkeeping stays on the 5 s poll.
            if (state.isArmed() && !state.isPaused() && state.getBoundaryEpochMillis() > 0L
                    && state.getBoundaryEpochMillis() - now < NEAR_BOUNDARY_MILLIS) {
                runFireCheckNow(server);
            }
            return;
        }
        if (lastPollNowMillis != 0L && now < lastPollNowMillis - CLOCK_REGRESS_WARN_MILLIS) {
            EclipseMod.LOGGER.warn("RealtimeDayService: wall clock regressed {} ms between polls "
                            + "(NTP correction?) — the epoch-day guard prevents double advances",
                    lastPollNowMillis - now);
        }
        lastPollNowMillis = now;
        maybeAutoArm(server, state, cfg);
        runFireCheckNow(server);
    }

    /**
     * One live fire check (tick cadence; public so gametests can drive it with an injected
     * {@link EclipseClock}). Advances at most one day per call.
     */
    public static void runFireCheckNow(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed() || state.isPaused() || state.getBoundaryEpochMillis() == 0L) {
            return;
        }
        long now = EclipseClock.epochMillis();
        long boundary = state.getBoundaryEpochMillis();
        if (now < boundary) {
            return;
        }
        int day = DayScheduler.getDay(server);
        if (day >= EclipseConfig.maxDay()) {
            EclipseMod.LOGGER.info("RealtimeDayService: boundary reached but day {} is already the "
                    + "final configured day — disarming without advancing", day);
            disarm(server);
            return;
        }
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        if (isGuardBlocked(state, cfg)) {
            skipGuardedSlot(server, state, cfg, now);
            return;
        }
        EclipseMod.LOGGER.info("RealtimeDayService: boundary {} reached — advancing day {} -> {}",
                formatInstant(boundary, cfg.zone()), day, day + 1);
        rollover(server, false, RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime()));
    }

    /**
     * The monotonic guard: a schedule-derived boundary whose zone-local calendar day was
     * already advanced does not fire again (backwards NTP jumps, re-arm after a manual
     * {@code /eclipse day set} the same real day). Manual one-shot overrides bypass it.
     */
    private static boolean isGuardBlocked(RealtimeState state, RealtimeConfig.Config cfg) {
        return !state.isManualOverride()
                && RealtimeMath.epochDay(state.getBoundaryEpochMillis(), cfg.zone())
                        <= state.getLastAdvanceEpochDay();
    }

    /** Skips a guard-blocked slot forward to the next schedule-derived boundary. */
    private static void skipGuardedSlot(MinecraftServer server, RealtimeState state,
            RealtimeConfig.Config cfg, long now) {
        long skipped = state.getBoundaryEpochMillis();
        state.setPrevBoundaryEpochMillis(skipped);
        state.setBoundaryEpochMillis(RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime()));
        EclipseMod.LOGGER.info("RealtimeDayService: boundary {} skipped — its calendar day already "
                        + "advanced (epoch-day guard); next boundary {}",
                formatInstant(skipped, cfg.zone()),
                formatInstant(state.getBoundaryEpochMillis(), cfg.zone()));
        broadcastClock(server);
    }

    /** {@code autoArmOnStartEvent}: arm once, as soon as the intro has run (or already had). */
    private static void maybeAutoArm(MinecraftServer server, RealtimeState state, RealtimeConfig.Config cfg) {
        if (state.isArmed() || state.isAutoArmDone() || !cfg.autoArmOnStartEvent()) {
            return;
        }
        if (!EclipseWorldState.get(server).isStartEventDone()
                || DayScheduler.getDay(server) >= EclipseConfig.maxDay()) {
            return;
        }
        EclipseMod.LOGGER.info("RealtimeDayService: start event done — auto-arming the day clock");
        arm(server);
    }

    // --- startup: config, legacy migration, catch-up ---

    @SubscribeEvent
    static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        if (RELOAD_HOOK_REGISTERED.compareAndSet(false, true)) {
            ReloadHooks.register("realtime", RealtimeConfig::reload);
        }
        RealtimeConfig.reload();
        migrateLegacySchedule(server);
        lastPollNowMillis = EclipseClock.epochMillis();
        RealtimeState state = RealtimeState.get(server);
        maybeAutoArm(server, state, RealtimeConfig.get());
        int caughtUp = runCatchUpNow(server);
        EclipseMod.LOGGER.info("RealtimeDayService: startup complete — {} (caught up {} day{})",
                status(server), caughtUp, caughtUp == 1 ? "" : "s");
    }

    /**
     * Imports a pending pre-P4 {@code PhaseScheduler} schedule (persisted in
     * {@code EclipseWorldState.nextPhaseEpochMillis}) as a one-shot manual boundary, then
     * clears the legacy fields — the upgrade never drops a scheduled fire.
     */
    private static void migrateLegacySchedule(MinecraftServer server) {
        EclipseWorldState worldState = EclipseWorldState.get(server);
        long legacyTarget = worldState.getNextPhaseEpochMillis();
        if (legacyTarget == 0L) {
            return;
        }
        long legacyOrigin = worldState.getPhaseScheduledAtEpochMillis();
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed()) {
            state.setArmed(true);
            state.setArmedByScheduleOnly(true);
            state.setAutoArmDone(true);
        }
        state.setPaused(false);
        state.setPauseRemainingMillis(0L);
        state.setPrevBoundaryEpochMillis(legacyOrigin > 0L ? legacyOrigin : EclipseClock.epochMillis());
        state.setBoundaryEpochMillis(legacyTarget);
        state.setManualOverride(true);
        worldState.setPhaseSchedule(0L, 0L);
        EclipseMod.LOGGER.info("RealtimeDayService: migrated legacy phase schedule ({}) into the "
                        + "real-time engine as a one-shot boundary",
                formatInstant(legacyTarget, RealtimeConfig.get().zone()));
    }

    /**
     * Replays boundaries missed during downtime: one full rollover (PRE signals, day
     * side effects, POST signals) per missed day, quiet except for the FINAL day reached,
     * bounded by {@code catchUpMaxDays} and {@code EclipseConfig.maxDay()}. A pending
     * one-shot override fires at most once (its legacy contract). Returns the number of
     * days advanced. Public so gametests can drive it with an injected clock.
     */
    public static int runCatchUpNow(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        if (!state.isArmed() || state.isPaused() || state.getBoundaryEpochMillis() == 0L) {
            return 0;
        }
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        if (now < state.getBoundaryEpochMillis()) {
            return 0;
        }
        if (state.isManualOverride()) {
            // A one-shot boundary elapsed while down: fire exactly once (loud), like W14.
            int before = DayScheduler.getDay(server);
            runFireCheckNow(server);
            return DayScheduler.getDay(server) - before;
        }
        int advanced = 0;
        while (state.isArmed() && !state.isPaused() && !state.isManualOverride()) {
            long boundary = state.getBoundaryEpochMillis();
            if (boundary == 0L || now < boundary) {
                break;
            }
            int day = DayScheduler.getDay(server);
            if (day >= EclipseConfig.maxDay()) {
                break;
            }
            if (advanced >= cfg.catchUpMaxDays()) {
                EclipseMod.LOGGER.warn("RealtimeDayService: catch-up cap ({} days) reached with "
                        + "boundaries still elapsed — re-anchoring forward", cfg.catchUpMaxDays());
                state.setPrevBoundaryEpochMillis(boundary);
                state.setBoundaryEpochMillis(RealtimeMath.nextBoundary(now, cfg.zone(), cfg.boundaryTime()));
                broadcastClock(server);
                break;
            }
            if (isGuardBlocked(state, cfg)) {
                skipGuardedSlot(server, state, cfg, now);
                continue;
            }
            long stepped = RealtimeMath.nextBoundary(boundary, cfg.zone(), cfg.boundaryTime());
            boolean lastStep = stepped > now
                    || day + 1 >= EclipseConfig.maxDay()
                    || advanced + 1 >= cfg.catchUpMaxDays();
            EclipseMod.LOGGER.info("RealtimeDayService: catch-up — boundary {} elapsed while down; "
                            + "advancing day {} -> {}{}",
                    formatInstant(boundary, cfg.zone()), day, day + 1, lastStep ? "" : " (quiet)");
            rollover(server, !lastStep, stepped);
            advanced++;
        }
        return advanced;
    }

    // --- bossbar (exact W14 PhaseScheduler rendering: purple, `day` theme) ---

    /** Creates the countdown bar if missing: all online players + the W8 {@code day} skin tag. */
    private static void ensureBar(MinecraftServer server) {
        if (bossEvent != null) {
            return;
        }
        bossEvent = new ServerBossEvent(Component.translatable("bossbar.eclipse.schedule", "…"),
                BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.PROGRESS);
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            bossEvent.addPlayer(online);
        }
        PacketDistributor.sendToAllPlayers(
                new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_DAY));
        EclipseMod.LOGGER.info("RealtimeDayService: countdown bossbar created (id {})", bossEvent.getId());
    }

    private static void removeBar() {
        if (bossEvent != null) {
            bossEvent.removeAllPlayers();
            bossEvent = null;
        }
    }

    /** Whether the countdown bossbar currently exists (gametest assertion hook). */
    public static boolean isBarVisible() {
        return bossEvent != null;
    }

    /** Name "Next phase: 2h 14m" (frozen remaining while paused); progress = remaining/window. */
    private static void updateBar(RealtimeState state, long now) {
        if (bossEvent == null) {
            return;
        }
        long boundary = state.getBoundaryEpochMillis();
        long total = Math.max(1L, boundary - state.getPrevBoundaryEpochMillis());
        long remaining = state.isPaused()
                ? Math.max(0L, state.getPauseRemainingMillis())
                : Math.max(0L, boundary - now);
        bossEvent.setName(state.isPaused()
                ? Component.translatable("bossbar.eclipse.schedule.paused", RealtimeMath.remainingText(remaining))
                : Component.translatable("bossbar.eclipse.schedule", RealtimeMath.remainingText(remaining)));
        bossEvent.setProgress(Mth.clamp((float) remaining / total, 0.0F, 1.0F));
    }

    // --- player/server lifecycle ---

    /** Late joiners get the running bar (+ theme tag) and a fresh clock payload. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        if (bossEvent != null) {
            bossEvent.addPlayer(player);
            PacketDistributor.sendToPlayer(player,
                    new S2CBossbarStylePayload(bossEvent.getId(), S2CBossbarStylePayload.THEME_DAY));
        }
        PacketDistributor.sendToPlayer(player, buildClockPayload(player.server));
    }

    /** Drop stale bossbar references for disconnecting players. */
    @SubscribeEvent
    static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (bossEvent != null && event.getEntity() instanceof ServerPlayer player) {
            bossEvent.removePlayer(player);
        }
    }

    /** The schedule itself is persisted; only the transient bar needs pre-stop cleanup. */
    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        removeBar();
    }

    /** Statics reset so a singleplayer relaunch (same JVM) never leaks across saves. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        removeBar();
        rollingOver = false;
        pendingBoundaryEpochMillis = 0L;
        lastPollNowMillis = 0L;
        lastClientSyncMillis = 0L;
    }
}
