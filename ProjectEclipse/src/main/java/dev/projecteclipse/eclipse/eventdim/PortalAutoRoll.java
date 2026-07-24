package dev.projecteclipse.eclipse.eventdim;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.core.time.EclipseClock;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeConfig;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeState;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.util.RandomSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * V5-FIXGUARD / EVAL-SAT-F #3 — the config-gated portal AUTO-ROLL. The
 * {@link PortalEventScheduler} registry was deliberately command-only ("scheduling stays
 * with the ops team"); the eval's residual gap is that playtesters never meet the finished
 * backrooms/xbox content unless an operator remembers {@code /dev portal roll}. This
 * service adds the "future automation" hook the registry docs promised, OFF by default:
 *
 * <ul>
 *   <li><b>Gate</b> — {@code portal_events.json} ({@link PortalEventsConfig}):
 *       {@code autoRoll=true} plus {@code day >= minDay} (default 4). Toggle live via
 *       {@code /dev portal auto on|off} (persisted back to the file).</li>
 *   <li><b>Roll window</b> — ONE random slot per eclipse day: on every day-rollover POST
 *       signal (the realtime engine's choke point) a slot is drawn uniformly inside the
 *       new day's real-time window (boundary→boundary, 5-min margins so the portal never
 *       collides with the dawn ceremony or the next boundary's hush); the 100-tick poll
 *       fires the weighted {@link PortalEventScheduler#roll} when the slot elapses.</li>
 *   <li><b>Weights</b> — the existing registry rarities verbatim (xbox COMMON 4 :
 *       backrooms RARE 1; future variants join automatically).</li>
 *   <li><b>Announcement</b> — delegated to the variant's own start broadcast, which is
 *       the C16/C17 generic "Ein Portal hat sich geöffnet." for xbox and the C18 flavor
 *       line for backrooms — the auto-roll itself broadcasts NOTHING extra, so no
 *       schedule/variant details leak to players.</li>
 *   <li><b>One-per-day</b> — the consumed day is persisted
 *       ({@link EclipseWorldState#setPortalAutoRollDay}), so a restart after the slot
 *       fired never rolls a second portal the same day; a restart BEFORE the slot fired
 *       re-draws a slot in the remaining window. A failed open (event already running,
 *       missing region payload, …) still consumes the day's slot — one attempt per day,
 *       logged for the ops team.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class PortalAutoRoll {
    /** Poll cadence for the armed slot (the realtime engine's 5 s fire-check rhythm). */
    private static final int CHECK_TICKS = 100;
    /** The slot never lands closer than this to either day boundary (ceremony/hush space). */
    private static final long WINDOW_MARGIN_MILLIS = 5L * 60L * 1000L;

    /** Signal listeners are cleared on server stop; re-register per server (Analytics pattern). */
    private static final AtomicBoolean SIGNALS_REGISTERED = new AtomicBoolean(false);

    /** Day the armed slot belongs to; {@code 0} = nothing armed. Server thread only. */
    // statics reset on ServerStopped
    private static int scheduledDay = 0;
    /** Epoch millis the armed slot fires at. Server thread only. */
    // statics reset on ServerStopped
    private static long scheduledEpochMillis = 0L;

    private PortalAutoRoll() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        // Idempotent: first call loads portal_events.json + registers the reload hook
        // (/eclipse reload and /dev reload re-read it, the XboxEventConfig precedent).
        PortalEventsConfig.bootstrap();
        if (SIGNALS_REGISTERED.compareAndSet(false, true)) {
            EclipseSignals.onDayRollover((server, endedDay, newDay, phase) -> {
                if (phase == EclipseSignals.DayRolloverPhase.POST) {
                    armSlotFor(server, newDay);
                }
            });
        }
        // Restart mid-day: re-draw a slot in the REMAINING window unless the persisted
        // marker says this day's slot was already consumed before the restart.
        armSlotFor(event.getServer(), DayScheduler.getDay(event.getServer()));
    }

    /**
     * Re-evaluates the CURRENT day's slot against the live config — {@code /dev portal
     * auto on} arms a slot mid-day (unless the day already consumed one), {@code off}
     * drops the armed slot immediately.
     */
    public static void refresh(MinecraftServer server) {
        armSlotFor(server, DayScheduler.getDay(server));
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SIGNALS_REGISTERED.set(false);
        scheduledDay = 0;
        scheduledEpochMillis = 0L;
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (scheduledDay == 0 || event.getServer().getTickCount() % CHECK_TICKS != 0) {
            return;
        }
        MinecraftServer server = event.getServer();
        if (!PortalEventsConfig.get().autoRoll()) {
            // Toggled off (command or reload) while a slot was armed: drop it quietly.
            scheduledDay = 0;
            scheduledEpochMillis = 0L;
            return;
        }
        if (EclipseClock.epochMillis() < scheduledEpochMillis) {
            return;
        }
        int day = scheduledDay;
        scheduledDay = 0;
        scheduledEpochMillis = 0L;
        if (DayScheduler.getDay(server) != day) {
            return; // out-of-band day change since arming; the rollover signal re-armed already
        }
        fireRoll(server, day);
    }

    /**
     * Draws (or clears) the day's slot. Called from the day-rollover POST signal and from
     * server start (mid-day restart). No-op reasons are logged at debug except the
     * consumed-day guard, which is the interesting one for ops.
     */
    private static void armSlotFor(MinecraftServer server, int day) {
        scheduledDay = 0;
        scheduledEpochMillis = 0L;
        PortalEventsConfig.Values cfg = PortalEventsConfig.get();
        if (!cfg.autoRoll() || day < cfg.minDay()) {
            return;
        }
        if (EclipseWorldState.get(server).getPortalAutoRollDay() >= day) {
            EclipseMod.LOGGER.debug("PortalAutoRoll: day {} slot already consumed — not re-arming", day);
            return;
        }
        long now = EclipseClock.epochMillis();
        long windowEnd = dayWindowEnd(server, now);
        long latest = windowEnd - WINDOW_MARGIN_MILLIS;
        long earliest = now + WINDOW_MARGIN_MILLIS;
        if (latest <= earliest) {
            // Sliver of a day left (restart just before the boundary): fire mid-sliver.
            earliest = now;
            latest = Math.max(now + 1L, windowEnd);
        }
        RandomSource random = server.overworld().getRandom();
        scheduledEpochMillis = earliest + (long) (random.nextDouble() * (latest - earliest));
        scheduledDay = day;
        EclipseMod.LOGGER.info("PortalAutoRoll: day {} slot armed for {} ({})", day,
                RealtimeDayService.formatInstant(scheduledEpochMillis, RealtimeConfig.get().zone()),
                RealtimeConfig.get().zone());
    }

    /**
     * The end of the current day's real-time window: the armed engine's pending boundary
     * when available, else the next schedule-derived boundary (disarmed/paused servers
     * still get a sensibly-placed slot).
     */
    private static long dayWindowEnd(MinecraftServer server, long now) {
        RealtimeState state = RealtimeState.get(server);
        if (state.isArmed() && !state.isPaused() && state.getBoundaryEpochMillis() > now) {
            return state.getBoundaryEpochMillis();
        }
        return RealtimeDayService.nextBoundaryFor(RealtimeConfig.get(), now);
    }

    /** Consumes the day's slot, then rolls + opens one weighted variant (null operator). */
    private static void fireRoll(MinecraftServer server, int day) {
        EclipseWorldState.get(server).setPortalAutoRollDay(day);
        PortalEventScheduler.Variant variant =
                PortalEventScheduler.roll(server.overworld().getRandom());
        Component error = PortalEventScheduler.open(server, variant.id(), null);
        if (error != null) {
            EclipseMod.LOGGER.warn("PortalAutoRoll: day {} rolled '{}' but opening failed: {} — "
                    + "slot consumed, next roll tomorrow", day, variant.id(), error.getString());
            return;
        }
        EclipseMod.LOGGER.info("PortalAutoRoll: day {} — '{}' opened by the auto-roll", day, variant.id());
    }
}
