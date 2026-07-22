package dev.projecteclipse.eclipse.progression;

import java.time.LocalDate;
import java.time.LocalTime;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CDayStatePayload;
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
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-authoritative event-day clock. Days change only through {@link #setDay(MinecraftServer, int)}
 * (wired to the admin command) unless {@code dayAutoAdvance} is enabled in {@code general.json}
 * (default OFF), in which case the day advances once per real-world day at the configured
 * server-local time. On a day change the new day is persisted, the new state is broadcast to
 * every client and a global bell rings for every online player. Finally the world-stage day
 * triggers ({@code stages.json} {@code day:N} / {@code final_day}) are evaluated, so e.g. the
 * nether disc appears when day 2 fires.
 *
 * <p>Since worker 7 the playable boundary is the circular {@code border.SoftBorder}, which
 * follows the world STAGE — the legacy {@code days.json} {@code borderSize} field is still
 * parsed but no longer drives anything (a one-time deprecation warning is logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DayScheduler {
    /** Real-world clock is polled every 5 seconds; plenty for a once-per-day trigger. */
    private static final int AUTO_ADVANCE_CHECK_TICKS = 100;
    /** One-time deprecation warning guard for the legacy {@code days.json} borderSize field. */
    private static boolean warnedBorderSizeDeprecated = false;
    /**
     * Reserved {@link EclipseWorldState} milestone-progress key holding the epoch day of the
     * last automatic advance, so a restart never re-advances the same real-world day.
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
     * commit a stage, which moves the ring).
     */
    public static void setDay(MinecraftServer server, int day) {
        int newDay = Math.max(1, day);
        EclipseWorldState state = EclipseWorldState.get(server);
        int previousDay = state.getDay();
        boolean changed = previousDay != newDay;
        state.setDay(newDay);

        EclipseConfig.DayPlan plan = EclipseConfig.day(newDay);
        if (!warnedBorderSizeDeprecated) {
            warnedBorderSizeDeprecated = true;
            EclipseMod.LOGGER.warn("days.json 'borderSize' is deprecated and ignored since W7: the "
                    + "circular soft border follows the world stage (stages.json radius + "
                    + "general.json borderOffset). Use /eclipse border ring set for manual overrides.");
        }

        PacketDistributor.sendToAllPlayers(new S2CDayStatePayload(newDay, state.getAltarLevel(), plan.goals()));
        if (changed) {
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                online.playNotifySound(SoundEvents.BELL_BLOCK, SoundSource.MASTER, 1.0F, 1.0F);
            }
            // W8: the bell is augmented by a typewriter/sweep announcement + the day's new
            // unlock announcements, and the anonymized timeline is rebroadcast.
            AnnouncementService.onDayChanged(server, previousDay, newDay);
        }
        EclipseMod.LOGGER.info("Eclipse day set to {} (goals: {}; unlocked keys: {})",
                newDay, plan.goals(), UnlockState.unlockedKeys(server));

        // World-stage day triggers (stages.json "day:N" / "final_day") — e.g. the nether
        // gets its first disc on day 2, BEFORE the portal unlock can be used.
        WorldStageService.applyDayTriggers(server, newDay);

        // W5 sundial plaza: reposition the basalt shadow line around the sanctum.
        SundialPlaza.onDayChanged(server, previousDay, newDay);
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EclipseWorldState state = EclipseWorldState.get(server);
        // First boot with auto-advance on: stamp today so the first advance happens tomorrow.
        if (EclipseConfig.dayAutoAdvance() && state.getMilestoneProgress(AUTO_ADVANCE_PROGRESS_KEY) == 0L) {
            state.setMilestoneProgress(AUTO_ADVANCE_PROGRESS_KEY, LocalDate.now().toEpochDay());
        }
        EclipseConfig.DayPlan plan = EclipseConfig.day(state.getDay());
        EclipseMod.LOGGER.info("Eclipse day plan loaded: day {}/{} (goals: {}; unlocked keys: {}; autoAdvance: {})",
                state.getDay(), EclipseConfig.days().size(), plan.goals(),
                UnlockState.unlockedKeys(server), EclipseConfig.dayAutoAdvance());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % AUTO_ADVANCE_CHECK_TICKS != 0 || !EclipseConfig.dayAutoAdvance()) {
            return;
        }
        if (LocalTime.now().isBefore(EclipseConfig.dayAutoAdvanceTime())) {
            return;
        }
        EclipseWorldState state = EclipseWorldState.get(server);
        long todayEpochDay = LocalDate.now().toEpochDay();
        if (todayEpochDay <= state.getMilestoneProgress(AUTO_ADVANCE_PROGRESS_KEY)) {
            return;
        }
        state.setMilestoneProgress(AUTO_ADVANCE_PROGRESS_KEY, todayEpochDay);
        EclipseMod.LOGGER.info("Eclipse day auto-advance triggered at {}", LocalTime.now());
        setDay(server, getDay(server) + 1);
    }
}
