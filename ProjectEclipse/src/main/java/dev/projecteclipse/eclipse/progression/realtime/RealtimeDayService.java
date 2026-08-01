package dev.projecteclipse.eclipse.progression.realtime;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.config.ReloadHooks;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.network.S2CDayClockPayload;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.offering.OfferingService;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.ritual.BeamEmitter;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Real-time day engine (R1, P4-B1): the 14-day arc advances at persistent real-world
 * boundaries ({@code realtime.json}: {@code zone} + {@code boundaryTime}, default Berlin
 * 18:00 — or, D6, {@code cadenceMode: "interval"} chaining every {@code intervalHours}
 * real hours via {@link #nextBoundaryFor}) instead of one-shot schedules. Replaces the
 * firing half of the W14
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
 *       login, and re-synced every {@code clientSyncSeconds} while armed. The countdown is
 *       presented ONLY by the client {@code DayTimerLayer} above the hotbar (PLAN-A A7) —
 *       the old W14 countdown bossbar is gone; this service never creates a
 *       {@code ServerBossEvent}.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RealtimeDayService {
    /** Wall-clock fire/auto-arm check cadence (5 s — the legacy scheduler/auto-advance poll). */
    private static final int FIRE_CHECK_TICKS = 100;
    /** Clock poll cadence (1 s — near-boundary fire checks + client re-sync window). */
    private static final int CLOCK_POLL_TICKS = 20;
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

    // --- WAVE5 (F-105 C) — C1 "Last Call" bookkeeping -----------------------------------
    // Offerings lapse wordlessly at the boundary today; the two whisper stages below give
    // every player WITHOUT a recorded offering a private nudge. Strictly anonymous: the
    // caption + muted bell ride per-player lanes (playNotifySound / sendToPlayer), no
    // global text, no names. T-90 s (not T-60 s) deliberately dodges the client-side
    // LastMinuteHush window, whose audio duck would swallow the bell.

    /** First whisper stage: T-10 min before the boundary. */
    private static final long LAST_CALL_10M_MILLIS = 600_000L;
    /** Second whisper stage: T-90 s (outside the 60 s LastMinuteHush duck window). */
    private static final long LAST_CALL_90S_MILLIS = 90_000L;
    /**
     * Last-minute altar agitation: one short {@link BeamEmitter} emit as each of these
     * remaining-ms marks elapses (4 flickers, spread over the final minute, world-visible).
     */
    private static final long[] LAST_CALL_FLICKER_MILLIS = { 55_000L, 40_000L, 25_000L, 10_000L };

    /** T-10m stage fired for the current day (reset in {@link #onDayApplied}). */
    // statics reset on ServerStopped
    private static boolean lastCall10mFired;
    /** T-90s stage fired for the current day (reset in {@link #onDayApplied}). */
    // statics reset on ServerStopped
    private static boolean lastCall90sFired;
    /** Next unconsumed index into {@link #LAST_CALL_FLICKER_MILLIS} (reset with the stages). */
    // statics reset on ServerStopped
    private static int lastCallFlickerIndex;

    private RealtimeDayService() {}

    /**
     * D6: the ONE schedule-derived boundary router. Daily mode chains {@code boundaryTime}
     * occurrences in {@code zone}; interval mode chains {@code intervalHours} steps.
     * {@code fromEpochMillis} is {@code now} for live derivations and the elapsed boundary
     * for catch-up stepping (both overloads treat it as the exclusive lower bound).
     */
    public static long nextBoundaryFor(RealtimeConfig.Config cfg, long fromEpochMillis) {
        if (cfg.cadenceMode() == RealtimeConfig.CadenceMode.INTERVAL) {
            return RealtimeMath.nextBoundary(fromEpochMillis, cfg.intervalMillis());
        }
        return RealtimeMath.nextBoundary(fromEpochMillis, cfg.zone(), cfg.boundaryTime());
    }

    // --- dev API backing (surfaced by RealtimeDayApi for P5-W3; reference commands in RealtimeCommands) ---

    /**
     * Arms the engine on the configured cadence: the next boundary is the next occurrence
     * of {@code boundaryTime} in {@code zone} after now (daily mode) or now +
     * {@code intervalHours} (interval mode). Clears pause, any one-shot override AND the
     * same-calendar-day dedup baseline (an explicit re-arm is operator intent to start a
     * fresh cadence). Returns the armed boundary (epoch millis).
     */
    public static long arm(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        long boundary = nextBoundaryFor(cfg, now);
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
        state.setBoundaryEpochMillis(nextBoundaryFor(cfg, now));
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

    /** Human-readable cadence description ({@code daily 18:00 Europe/Berlin} / {@code every 2h 0m}). */
    public static String cadenceText(RealtimeConfig.Config cfg) {
        return cfg.cadenceMode() == RealtimeConfig.CadenceMode.INTERVAL
                ? "every " + RealtimeMath.remainingText(cfg.intervalMillis())
                : "daily " + cfg.boundaryTime() + " " + cfg.zone();
    }

    /** One human-readable status line (dev commands + P5 surface). */
    public static String status(MinecraftServer server) {
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        int day = DayScheduler.getDay(server);
        String cadence = "cadence " + cadenceText(cfg);
        if (!state.isArmed()) {
            return "disarmed (day " + day + "/" + EclipseConfig.maxDay() + ", " + cadence + ")";
        }
        if (state.isPaused()) {
            return "PAUSED (day " + day + "/" + EclipseConfig.maxDay() + ", "
                    + RealtimeMath.remainingText(state.getPauseRemainingMillis()) + " frozen, "
                    + cadence + ")";
        }
        long now = EclipseClock.epochMillis();
        return "armed (day " + day + "/" + EclipseConfig.maxDay() + ", " + cadence
                + ", next boundary "
                + formatInstant(state.getBoundaryEpochMillis(), cfg.zone()) + " " + cfg.zone()
                + ", in " + RealtimeMath.remainingText(state.getBoundaryEpochMillis() - now) + ")"
                + (state.isManualOverride() ? " [one-shot override]" : "");
    }

    /**
     * D6 {@code /dev phase next}: advances the arc one day RIGHT NOW through the full
     * {@code DayScheduler.setDay} rollover (PRE/POST signals, bell, announcements). An
     * armed clock re-anchors via the {@link #onDayApplied} out-of-band branch (interval
     * mode: next phase in {@code intervalHours}; daily mode: the epoch-day stamp dedups
     * today's remaining slot). Returns the new day, or {@code -1} when the arc is already
     * on its final configured day.
     */
    public static int advancePhaseNow(MinecraftServer server) {
        int day = DayScheduler.getDay(server);
        if (day >= EclipseConfig.maxDay()) {
            return -1;
        }
        EclipseMod.LOGGER.info("RealtimeDayService: /dev phase next — advancing day {} -> {} now",
                day, day + 1);
        DayScheduler.setDay(server, day + 1);
        return DayScheduler.getDay(server);
    }

    /**
     * D6 cadence switch: persists the new mode/interval to {@code realtime.json}
     * ({@link RealtimeConfig#setCadence}) and, when the clock is armed and not paused,
     * re-derives the pending boundary from now on the new cadence (a pending one-shot
     * override is deliberately preserved — it fires first, then the new cadence chains).
     * Returns the resulting config.
     */
    public static RealtimeConfig.Config applyCadence(MinecraftServer server,
            RealtimeConfig.CadenceMode mode, double intervalHours) {
        RealtimeConfig.Config cfg = RealtimeConfig.setCadence(mode, intervalHours);
        RealtimeState state = RealtimeState.get(server);
        if (state.isArmed() && !state.isPaused() && !state.isManualOverride()) {
            long now = EclipseClock.epochMillis();
            state.setPrevBoundaryEpochMillis(now);
            state.setBoundaryEpochMillis(nextBoundaryFor(cfg, now));
            EclipseMod.LOGGER.info("RealtimeDayService: cadence now {} — next boundary {}",
                    cadenceText(cfg), formatInstant(state.getBoundaryEpochMillis(), cfg.zone()));
        }
        broadcastClock(server);
        return cfg;
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
                armed && state.isPaused() ? state.getPauseRemainingMillis() : 0L,
                state.getTimerColorMode());
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
        // WAVE5 (F-105 C) — C1: every applied day re-arms the Last-Call stages fresh.
        lastCall10mFired = false;
        lastCall90sFired = false;
        lastCallFlickerIndex = 0;
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
                EclipseMod.LOGGER.info("RealtimeDayService: one-shot schedule fired — engine disarmed "
                        + "(arm via /eclipse-rt arm for the recurring cadence)");
            } else {
                state.setBoundaryEpochMillis(pendingBoundaryEpochMillis);
            }
        } else if (state.isArmed() && previousDay != newDay) {
            // Out-of-band /eclipse day set (or a gametest helper): re-anchor per plan §2.1.
            state.setPrevBoundaryEpochMillis(now);
            state.setBoundaryEpochMillis(nextBoundaryFor(cfg, now));
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
        if (server.getTickCount() % CLOCK_POLL_TICKS != 0) {
            return;
        }
        RealtimeState state = RealtimeState.get(server);
        RealtimeConfig.Config cfg = RealtimeConfig.get();
        long now = EclipseClock.epochMillis();
        if (state.isArmed() && now - lastClientSyncMillis >= cfg.clientSyncSeconds() * 1000L) {
            broadcastClock(server);
        }
        tickLastCall(server, state, now); // WAVE5 (F-105 C) — C1, on the 1 s clock poll
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
        rollover(server, false, nextBoundaryFor(cfg, now));
    }

    // --- WAVE5 (F-105 C) — C1 Last Call at the altar (IDEA-09 #4) -----------------------

    /**
     * One Last-Call poll (1 s cadence from {@link #onServerTick}). Each whisper stage fires
     * at most once per day (flags reset in {@link #onDayApplied}); the whisper goes ONLY to
     * online players without a recorded offering for the current day
     * ({@link OfferingService#hasOfferedToday}). Inside the final minute the sanctum altar
     * additionally flickers its beam ({@value #LAST_CALL_FLICKER_MILLIS} marks, one emit per
     * poll so stacked marks read as a stutter, not a salvo). Quiet while disarmed/paused.
     */
    private static void tickLastCall(MinecraftServer server, RealtimeState state, long now) {
        if (!state.isArmed() || state.isPaused() || state.getBoundaryEpochMillis() == 0L) {
            return;
        }
        long remaining = state.getBoundaryEpochMillis() - now;
        if (remaining <= 0L) {
            return;
        }
        if (!lastCall10mFired && remaining <= LAST_CALL_10M_MILLIS && remaining > LAST_CALL_90S_MILLIS) {
            lastCall10mFired = true;
            whisperLastCall(server, "10m", "eclipse.caption.lastcall.tminus10m");
        }
        if (!lastCall90sFired && remaining <= LAST_CALL_90S_MILLIS) {
            // A boundary armed/set inside T-10m skips straight to the 90 s stage — the 10 m
            // flag latches too so a later backwards shift can never replay the early stage.
            lastCall10mFired = true;
            lastCall90sFired = true;
            whisperLastCall(server, "90s", "eclipse.caption.lastcall.tminus90s");
        }
        if (lastCallFlickerIndex < LAST_CALL_FLICKER_MILLIS.length
                && remaining <= LAST_CALL_FLICKER_MILLIS[lastCallFlickerIndex]) {
            lastCallFlickerIndex++;
            emitLastCallFlicker(server);
        }
    }

    /**
     * One private whisper wave: caption ({@code STYLE_WHISPER}) + muted bell to every online
     * player who has NOT offered today. Nothing global, no names anywhere but the DEBUG probe.
     */
    private static void whisperLastCall(MinecraftServer server, String stage, String captionKey) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            if (OfferingService.hasOfferedToday(player)) {
                continue;
            }
            PacketDistributor.sendToPlayer(player,
                    new S2CCaptionPayload(captionKey, 70, S2CCaptionPayload.STYLE_WHISPER));
            player.playNotifySound(SoundEvents.BELL_BLOCK, SoundSource.BLOCKS, 0.4F, 0.6F);
            EclipseMod.LOGGER.debug("[w5c-lastcall] stage={} player={}", stage, player.getScoreboardName());
        }
    }

    /** One short world-visible beam emit at the sanctum altar (null-safe for pre-intro worlds). */
    private static void emitLastCallFlicker(MinecraftServer server) {
        BlockPos altar = EclipseWorldState.get(server).getSanctumAltarPos();
        if (altar == null) {
            return;
        }
        BeamEmitter.emit(server.overworld(), altar);
        EclipseMod.LOGGER.debug("[w5c-lastcall] flicker {}/{} at {}",
                lastCallFlickerIndex, LAST_CALL_FLICKER_MILLIS.length, altar.toShortString());
    }

    /**
     * The monotonic guard: a schedule-derived boundary whose zone-local calendar day was
     * already advanced does not fire again (backwards NTP jumps, re-arm after a manual
     * {@code /eclipse day set} the same real day). Manual one-shot overrides bypass it.
     * D6: DAILY-mode only — interval mode legitimately advances several times per
     * calendar day, so the epoch-day dedup would eat every fire after the first.
     */
    private static boolean isGuardBlocked(RealtimeState state, RealtimeConfig.Config cfg) {
        return cfg.cadenceMode() == RealtimeConfig.CadenceMode.DAILY
                && !state.isManualOverride()
                && RealtimeMath.epochDay(state.getBoundaryEpochMillis(), cfg.zone())
                        <= state.getLastAdvanceEpochDay();
    }

    /** Skips a guard-blocked slot forward to the next schedule-derived boundary. */
    private static void skipGuardedSlot(MinecraftServer server, RealtimeState state,
            RealtimeConfig.Config cfg, long now) {
        long skipped = state.getBoundaryEpochMillis();
        state.setPrevBoundaryEpochMillis(skipped);
        state.setBoundaryEpochMillis(nextBoundaryFor(cfg, now));
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
                state.setBoundaryEpochMillis(nextBoundaryFor(cfg, now));
                broadcastClock(server);
                break;
            }
            if (isGuardBlocked(state, cfg)) {
                skipGuardedSlot(server, state, cfg, now);
                continue;
            }
            long stepped = nextBoundaryFor(cfg, boundary);
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

    // --- player/server lifecycle ---

    // PLAN-A A7: the countdown bossbar (ensureBar/updateBar/removeBar + the W8 `day` skin
    // tag) is deleted — the ONE day-timer surface is the client DayTimerLayer above the
    // hotbar, fed purely by S2CDayClockPayload.

    /** Late joiners get a fresh clock payload. */
    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        PacketDistributor.sendToPlayer(player, buildClockPayload(player.server));
    }

    /** Statics reset so a singleplayer relaunch (same JVM) never leaks across saves. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        rollingOver = false;
        pendingBoundaryEpochMillis = 0L;
        lastPollNowMillis = 0L;
        lastClientSyncMillis = 0L;
        // WAVE5 (F-105 C) — C1 Last-Call statics
        lastCall10mFired = false;
        lastCall90sFired = false;
        lastCallFlickerIndex = 0;
    }
}
