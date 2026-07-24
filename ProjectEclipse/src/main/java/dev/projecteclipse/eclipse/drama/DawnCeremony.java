package dev.projecteclipse.eclipse.drama;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.awards.AwardService;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import dev.projecteclipse.eclipse.network.fx.S2CCaptionPayload;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.timeline.AnnouncementService;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * W4-CEREMONY / IDEA-09 #1 — THE DAWN CEREMONY: a tiny server-side presentation sequencer
 * that spreads the day-rollover's LOUD beats over ~10 s instead of piling them into one
 * server tick. State stays 100% synchronous in {@code DayScheduler.applyDay} (persist,
 * day-state payloads, triggers, sundial, clock — untouched); only the presentation calls
 * move into spaced beats, using the exact {@code Task}/{@code schedule()} pattern proven in
 * {@code sequence.ExpansionSequence}:
 *
 * <ol>
 *   <li><b>T+0</b> — the boundary flip itself: {@code S2CDayStatePayload} sync and the
 *       client-side {@code LastMinuteHush} release land (nothing to do here).</li>
 *   <li><b>T+{@value #BEAT_SUN_PULSE}</b> — dawn sun pulse (IDEA-09 #2): the eclipsed sun
 *       swallows for one breath — {@code sendEclipsePhase(BUILDUP, 0.35, 10)} followed by
 *       {@code (ENDING, 0.0, 30)}, the {@code ExpansionSequence} pair at lower intensity.
 *       Skipped while an expansion sweep is live (its grade owns the sky).</li>
 *   <li><b>T+{@value #BEAT_TOLL}</b> — the dawn toll: three descending bell strikes
 *       (1.0 → 0.84 → 0.7, spaced {@value #TOLL_SPACING_TICKS} ticks) with a quiet
 *       {@code event.eclipse_drone} tail — the signature that replaces the flat vanilla
 *       bell of the pre-ceremony stack.</li>
 *   <li><b>T+{@value #BEAT_DAY_ANNOUNCE}</b> — {@code AnnouncementService.onDayChanged}:
 *       day typewriter/sweep, unlock sweeps, timeline rebroadcast (moved, not changed).</li>
 *   <li><b>T+{@value #BEAT_GOALS}</b> — goals reveal: one calm subtitle pointing at the
 *       day's decrees (the goal DATA already rides the T+0 day-state sync).</li>
 *   <li><b>T+{@value #BEAT_AWARDS}</b> — awards roulette:
 *       {@link AwardService#sendRevealNow} on non-expansion days.
 *       {@code AwardService.onDayRollover} POST gates its inline send behind
 *       {@link #isRunning}, so the ceremony owns this timing; expansion days keep the
 *       END-seam call in {@code ExpansionSequence.beginEnd} (the client dedupes by day
 *       via {@code AwardsOverlay.HANDLED_DAYS}, so a double send stays safe).</li>
 * </ol>
 *
 * <p><b>Wiring</b> (owner: DayScheduler — exact diff in
 * {@code docs/plans_v3/wiring/W4-CEREMONY_wiring.md}): the {@code changed && !quiet} block
 * of {@code DayScheduler.applyDay} calls {@link #begin} INSTEAD of the inline bell loop +
 * {@code AnnouncementService.onDayChanged}. Until that diff lands this class is inert and
 * every rollover behaves exactly as today ({@link #isRunning} is then always false, so the
 * {@code AwardService} POST gate falls through to the current inline send).</p>
 *
 * <p><b>Guards</b>: quiet catch-up days never reach the hook (unchanged contract); a
 * mid-ceremony restart simply drops the pending beats — every beat is a re-broadcastable
 * payload, no state. Statics reset on {@link ServerStoppedEvent} per house rule.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DawnCeremony {
    // --- beat offsets (ticks after begin; T-0 == the boundary flip / hush release) ---
    private static final int BEAT_SUN_PULSE = 10;
    private static final int BEAT_TOLL = 20;
    private static final int BEAT_DAY_ANNOUNCE = 40;
    private static final int BEAT_GOALS = 140;
    private static final int BEAT_AWARDS = 200;
    /** {@link #isRunning} window: the last beat plus a small margin. */
    private static final int CEREMONY_TICKS = BEAT_AWARDS + 20;

    // --- sun pulse (S2CEclipsePhasePayload contract: 1=BUILDUP 3=ENDING) ---
    private static final int ECLIPSE_BUILDUP = 1;
    private static final int ECLIPSE_ENDING = 3;
    private static final float PULSE_INTENSITY = 0.35F;
    private static final int PULSE_IN_TICKS = 10;
    private static final int PULSE_OUT_TICKS = 30;

    // --- dawn toll ---
    private static final float[] TOLL_PITCHES = {1.0F, 0.84F, 0.7F};
    private static final int TOLL_SPACING_TICKS = 8;
    private static final float DRONE_TAIL_VOLUME = 0.25F;

    private static final String CAPTION_GOALS = "eclipse.caption.dawn.goals";

    // statics reset on ServerStopped
    /** Tick scheduler for the ceremony beats (ExpansionSequence Task pattern). Server thread only. */
    private static final List<Task> TASKS = new ArrayList<>();
    /** Absolute server tick the running ceremony ends at; {@code -1} = idle. */
    private static long ceremonyEndTick = -1L;

    private DawnCeremony() {}

    /**
     * Starts the dawn ceremony for a LOUD (non-quiet) rollover. Called from
     * {@code DayScheduler.applyDay}'s {@code changed && !quiet} block (wiring diff) in
     * place of the inline bell + announcement stack. A superseding rollover (dev
     * {@code /eclipse day set} spam) drops the previous ceremony's pending beats.
     */
    public static void begin(MinecraftServer server, int previousDay, int newDay) {
        TASKS.clear();
        ceremonyEndTick = server.getTickCount() + CEREMONY_TICKS;
        schedule(server, BEAT_SUN_PULSE, () -> sunPulse(server));
        schedule(server, BEAT_TOLL, () -> dawnToll(server));
        schedule(server, BEAT_DAY_ANNOUNCE,
                () -> AnnouncementService.onDayChanged(server, previousDay, newDay));
        schedule(server, BEAT_GOALS, () -> goalsReveal(server, newDay));
        schedule(server, BEAT_AWARDS, () -> awardsRoulette(server));
        EclipseMod.LOGGER.info("DawnCeremony: day {} -> {} — beats scheduled over {} ticks",
                previousDay, newDay, CEREMONY_TICKS);
    }

    /**
     * Whether a dawn ceremony is currently sequencing beats. {@code AwardService}'s POST
     * rollover branch gates its inline {@code sendRevealNow} behind this so the ceremony
     * owns the roulette timing on non-expansion days.
     */
    public static boolean isRunning(MinecraftServer server) {
        return ceremonyEndTick >= 0L && server.getTickCount() < ceremonyEndTick;
    }

    // ------------------------------------------------------------------ beats

    /** IDEA-09 #2: one 40-tick "eclipse blink" — the sun swallows for a breath at dawn. */
    private static void sunPulse(MinecraftServer server) {
        if (expansionLive()) {
            return; // the expansion cinematic's grade owns the sky this morning
        }
        boolean rim = permanentRim(server);
        FxPayloads.sendEclipsePhase(server, ECLIPSE_BUILDUP, PULSE_INTENSITY, PULSE_IN_TICKS, rim);
        schedule(server, PULSE_IN_TICKS,
                () -> FxPayloads.sendEclipsePhase(server, ECLIPSE_ENDING, 0.0F, PULSE_OUT_TICKS, rim));
    }

    /** Three descending strikes + a quiet drone tail — the signature dawn toll. */
    private static void dawnToll(MinecraftServer server) {
        for (int i = 0; i < TOLL_PITCHES.length; i++) {
            float pitch = TOLL_PITCHES[i];
            schedule(server, i * TOLL_SPACING_TICKS, () -> {
                for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                    online.playNotifySound(SoundEvents.BELL_BLOCK, SoundSource.MASTER, 1.0F, pitch);
                }
            });
        }
        schedule(server, TOLL_PITCHES.length * TOLL_SPACING_TICKS, () -> {
            for (ServerPlayer online : server.getPlayerList().getPlayers()) {
                online.playNotifySound(EclipseSounds.EVENT_ECLIPSE_DRONE.get(), SoundSource.AMBIENT,
                        DRONE_TAIL_VOLUME, 1.1F);
            }
        });
    }

    /** One calm subtitle; the goal data itself already synced at T+0 with the day state. */
    private static void goalsReveal(MinecraftServer server, int newDay) {
        if (EclipseConfig.day(newDay).goals().isEmpty()) {
            return;
        }
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            PacketDistributor.sendToPlayer(online,
                    new S2CCaptionPayload(CAPTION_GOALS, 100, S2CCaptionPayload.STYLE_SUBTITLE));
        }
    }

    /** Non-expansion days: the ceremony owns the roulette start (see class doc). */
    private static void awardsRoulette(MinecraftServer server) {
        if (expansionLive()) {
            return; // ExpansionSequence.beginEnd owns the reveal seam on expansion days
        }
        AwardService.sendRevealNow(server);
    }

    // ------------------------------------------------------------------ guards

    /** Whether an expansion sweep is live (proxy for a running ExpansionSequence cinematic). */
    private static boolean expansionLive() {
        return RingGrowthService.isRunning(DiscProfile.OVERWORLD)
                || RingGrowthService.isRunning(DiscProfile.NETHER);
    }

    /** Post-intro worlds keep the purple sun rim latched (ExpansionSequence convention). */
    private static boolean permanentRim(MinecraftServer server) {
        return EclipseWorldState.get(server).isStartEventDone();
    }

    // ------------------------------------------------------------------ scheduler (ExpansionSequence pattern)

    private record Task(long dueTick, Runnable action) {}

    private static void schedule(MinecraftServer server, int delayTicks, Runnable action) {
        TASKS.add(new Task(server.getTickCount() + Math.max(0, delayTicks), action));
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (TASKS.isEmpty()) {
            return;
        }
        long now = event.getServer().getTickCount();
        List<Task> due = null;
        Iterator<Task> iterator = TASKS.iterator();
        while (iterator.hasNext()) {
            Task task = iterator.next();
            if (task.dueTick() <= now) {
                iterator.remove();
                if (due == null) {
                    due = new ArrayList<>(4);
                }
                due.add(task);
            }
        }
        if (due != null) {
            for (Task task : due) {
                task.action().run(); // may schedule again — TASKS is not iterated here
            }
        }
    }

    /** Statics reset so a singleplayer relaunch (same JVM) never leaks across saves. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        TASKS.clear();
        ceremonyEndTick = -1L;
    }
}
