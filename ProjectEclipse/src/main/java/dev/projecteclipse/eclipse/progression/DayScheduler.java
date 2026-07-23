package dev.projecteclipse.eclipse.progression;

import java.time.LocalDate;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.signal.EclipseSignals;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
import dev.projecteclipse.eclipse.progression.realtime.RealtimeDayService;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SundialPlaza;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-authoritative event-day clock. Days change only through {@link #setDay(MinecraftServer, int)}
 * (admin command, gametest helper) or the P4-B1 real-time engine
 * ({@code progression.realtime.RealtimeDayService}), which drives this same method at its
 * persisted real-world boundaries. On a day change the new day is persisted, the new state
 * is broadcast to every client and a global bell rings for every online player. Finally the
 * world-stage day triggers ({@code stages.json} {@code day:N} / {@code final_day}) are
 * evaluated, so e.g. the nether disc appears when day 2 fires — this is "the expansion
 * sequence" and it runs on every advance path, including quiet catch-up.
 *
 * <p><b>Rollover signals (P4)</b>: when the day moves UP BY EXACTLY 1 (the only shape a
 * rollover can take — scheduler fire, catch-up step, or a manual {@code /eclipse day set}
 * to current+1), {@code EclipseSignals.dayRollover} fires PRE before the new day is
 * persisted (awards resolve, offerings settle, analytics day-cut against the ENDED day)
 * and POST after all side effects and the real-time clock bookkeeping (quest re-roll,
 * recipe-lock rebroadcast, sidebar sync read the NEW day + fresh boundary). Any other
 * delta (jumps, decreases) is an admin correction: no signals, but the real-time clock
 * still re-anchors via {@link RealtimeDayService#onDayApplied}.</p>
 *
 * <p>{@link #setDayQuiet} is the catch-up variant: identical persistence/trigger/signal
 * behavior but WITHOUT the bell + announcement stack, so a multi-day offline catch-up
 * only celebrates the final day reached.</p>
 *
 * <p>Since worker 7 the playable boundary is the circular {@code border.SoftBorder}, which
 * follows the world STAGE — the legacy {@code days.json} {@code borderSize} field is still
 * parsed but no longer drives anything (a one-time deprecation warning is logged). Since
 * P4-B1 the same applies to {@code general.json dayAutoAdvance}: parsed but IGNORED
 * (deprecation warning below) — {@code realtime.json} drives automatic advances now.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DayScheduler {
    /** One-time deprecation warning guard for the legacy {@code days.json} borderSize field. */
    // statics: log-once-per-JVM warning flags only (deliberately NOT reset on ServerStopped,
    // matching the pre-P4 warnedBorderSizeDeprecated behavior — they carry no world state).
    private static boolean warnedBorderSizeDeprecated = false;
    /** One-time deprecation warning guard for the legacy {@code general.json dayAutoAdvance} flag. */
    private static boolean warnedDayAutoAdvanceDeprecated = false;
    /**
     * Reserved {@link EclipseWorldState} milestone-progress key holding the epoch day of the
     * last day advance. The pre-P4 auto-advance dedup read it; it is still stamped on every
     * change for external tooling/backward compat (the real-time engine keeps its own
     * zone-aware guard in {@code RealtimeState.lastAdvanceEpochDay}).
     */
    private static final String AUTO_ADVANCE_PROGRESS_KEY = "scheduler:last_auto_advance_epoch_day";

    private DayScheduler() {}

    /** The current event day (>= 1). */
    public static int getDay(MinecraftServer server) {
        return EclipseWorldState.get(server).getDay();
    }

    /**
     * Sets the current event day (clamped to >= 1), persists it and broadcasts
     * {@link S2CDayStatePayload} to all players. When the day actually changes, a global bell
     * cue plays for every online player. Idempotent and reversible: unlocks are derived from
     * the day in {@link UnlockState}, so lowering the day re-locks. The world border is NOT
     * touched here anymore — the W7 soft ring follows the world stage (day triggers below may
     * commit a stage, which moves the ring). A +1 change fires the PRE/POST
     * {@code dayRollover} signals (see class doc).
     */
    public static void setDay(MinecraftServer server, int day) {
        applyDay(server, day, false);
    }

    /**
     * Catch-up variant of {@link #setDay}: same persistence, signals, day triggers and
     * sundial move, but the bell + announcement stack stay silent. Used by the real-time
     * engine for all but the LAST day of a multi-day offline catch-up.
     */
    public static void setDayQuiet(MinecraftServer server, int day) {
        applyDay(server, day, true);
    }

    /** The single day-change choke point (rollover order: PRE → apply → clock → POST → sync). */
    private static void applyDay(MinecraftServer server, int day, boolean quiet) {
        int newDay = Math.max(1, day);
        EclipseWorldState state = EclipseWorldState.get(server);
        int previousDay = state.getDay();
        boolean changed = previousDay != newDay;
        // A rollover is precisely "+1": every scheduler fire and catch-up step has this
        // shape, and a manual `/eclipse day set <current+1>` is indistinguishable from one
        // (plan §2.1) — jumps/decreases are corrections and must not resolve awards etc.
        boolean rollover = newDay == previousDay + 1;
        if (rollover) {
            // PRE runs BEFORE the day is persisted: listeners still see the ended day's
            // state (awards compute, offerings resolve, analytics cut day N).
            EclipseSignals.fireDayRollover(server, previousDay, newDay,
                    EclipseSignals.DayRolloverPhase.PRE);
        }
        state.setDay(newDay);
        if (changed) {
            // ANY day change counts as today's advance — kept for backward compat (the
            // legacy auto-advance dedup key; see field doc).
            state.setMilestoneProgress(AUTO_ADVANCE_PROGRESS_KEY, LocalDate.now().toEpochDay());
        }

        EclipseConfig.DayPlan plan = EclipseConfig.day(newDay);
        if (!warnedBorderSizeDeprecated) {
            warnedBorderSizeDeprecated = true;
            EclipseMod.LOGGER.warn("days.json 'borderSize' is deprecated and ignored since W7: the "
                    + "circular soft border follows the world stage (stages.json radius + "
                    + "general.json borderOffset). Use /eclipse border ring set for manual overrides.");
        }

        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(newDay, state.getAltarLevel(), plan.goals()));
        if (changed && !quiet) {
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                online.playNotifySound(SoundEvents.BELL_BLOCK, SoundSource.MASTER, 1.0F, 1.0F);
            }
            // W8: the bell is augmented by a typewriter/sweep announcement + the day's new
            // unlock announcements, and the anonymized timeline is rebroadcast. Quiet
            // catch-up days skip this whole stack — the unlock-key baseline then diffs all
            // skipped days' keys into the FINAL (loud) day's announcements at once.
            AnnouncementService.onDayChanged(server, previousDay, newDay);
        }
        EclipseMod.LOGGER.info("Eclipse day set to {}{} (goals: {}; unlocked keys: {})",
                newDay, quiet ? " [quiet]" : "", plan.goals(), UnlockState.unlockedKeys(server));

        // World-stage day triggers (stages.json "day:N" / "final_day") — e.g. the nether
        // gets its first disc on day 2, BEFORE the portal unlock can be used. Runs on
        // quiet catch-up too: applyDayTriggers is cumulative-idempotent (takes max stage),
        // so multi-day terrain lands correctly in one sweep.
        WorldStageService.applyDayTriggers(server, newDay);

        // W5 sundial plaza: reposition the basalt shadow line around the sanctum.
        SundialPlaza.onDayChanged(server, previousDay, newDay);

        if (changed) {
            // Real-time clock bookkeeping BEFORE the POST signal, so POST listeners (quest
            // re-roll, sidebar sync) already read the fresh boundary: a service-driven
            // rollover installs its staged boundary, an out-of-band change re-anchors.
            RealtimeDayService.onDayApplied(server, previousDay, newDay);
        }
        if (rollover) {
            EclipseSignals.fireDayRollover(server, previousDay, newDay,
                    EclipseSignals.DayRolloverPhase.POST);
        }
        if (changed) {
            RealtimeDayService.broadcastClock(server);
        }
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        if (EclipseConfig.dayAutoAdvance() && !warnedDayAutoAdvanceDeprecated) {
            warnedDayAutoAdvanceDeprecated = true;
            EclipseMod.LOGGER.warn("general.json 'dayAutoAdvance' is deprecated and IGNORED since "
                    + "P4-B1: the real-time day engine (config/eclipse/realtime.json, /eclipse-rt, "
                    + "and the P5 command surface) drives automatic day advances now.");
        }
        EclipseConfig.DayPlan plan = EclipseConfig.day(state.getDay());
        EclipseMod.LOGGER.info("Eclipse day plan loaded: day {}/{} (goals: {}; unlocked keys: {})",
                state.getDay(), EclipseConfig.days().size(), plan.goals(),
                UnlockState.unlockedKeys(server));
    }
}
