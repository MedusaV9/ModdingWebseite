package dev.projecteclipse.eclipse.woah.echogrove;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxPayloads;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WOAH-05 memory-flood timer + timeline (plan §3.5) — the woah moment. Every
 * ~1800t (±200, jittered per roll; 1200t base after the finale) the whole hollow
 * flips into its past for 160t: overlay pool grows in 4 radius waves, echoes
 * brighten, the grade goes golden (client latch off {@code CUE_ECHO_FLOOD}), the
 * music-box motif plays, then everything shrinks back under falling ash.
 *
 * <p>The countdown only runs while a player is within {@value #GATE_DIST} blocks
 * of the tree — paused otherwise, missed floods are never "caught up". A running
 * flood always finishes cleanly even if everyone leaves mid-flood (pushes are
 * one-shot transforms; leaving them half-grown would strand the pool).</p>
 *
 * <p><b>Music-box fallback (plan §6.1, risk §11.5):</b> the motif is sequenced
 * server-side from {@code NOTE_BLOCK_CHIME}/{@code NOTE_BLOCK_BELL} on a 6t grid —
 * zero new assets, ships day one. When {@code music/echo_music_box.ogg} lands
 * later, the client latch in {@code EchoGroveFx} takes over and this sequencer is
 * silenced by flipping {@link #NOTE_FALLBACK} (build-time choice, plan §6.1).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MemoryFloodService {
    /** Countdown gate — matches the scene service gate (plan §3.5). */
    private static final double GATE_DIST = 96.0D;
    public static final int FLOOD_TICKS = 160;
    private static final int BASE_INTERVAL = 1800;
    private static final int AFTERGLOW_INTERVAL = 1200;
    private static final int INTERVAL_JITTER = 200;
    /** Scale-up/-down interpolation window (plan §5.1). */
    private static final int WAVE_WINDOW = 20;
    /** Cue range — the flood must latch the grade well outside the bowl. */
    private static final double CUE_RANGE = 256.0D;

    /**
     * Build-time motif choice (plan §6.1): {@code true} = server-sequenced
     * note-block music box (no audio asset needed). Flip to {@code false} once
     * {@code assets/eclipse/sounds/music/echo_music_box.ogg} exists — then the
     * client plays the real track from the {@code CUE_ECHO_FLOOD} latch instead.
     */
    private static final boolean NOTE_FALLBACK = true;

    /**
     * The music-box motif: {vanilla note-block note 0–24, 6t-grid step, bell-layer
     * flag}. A-minor, falling home to A — wistful, not spooky. Pitch is the vanilla
     * table: 2^((note−12)/12).
     */
    private static final int[][] MOTIF = {
            {15, 0, 1}, {18, 1, 0}, {22, 2, 0}, {17, 4, 0},
            {15, 5, 1}, {18, 6, 0}, {20, 8, 0}, {22, 9, 0},
            {17, 11, 0}, {15, 12, 1}, {10, 14, 0}, {15, 16, 1}};
    private static final int MOTIF_GRID = 6;

    /** One scheduled fallback note (also used by the deposit chime). */
    private static final class PendingNote {
        int delay;
        final Vec3 pos;
        final int note;
        final boolean bell;
        final float volume;

        PendingNote(int delay, Vec3 pos, int note, boolean bell, float volume) {
            this.delay = delay;
            this.pos = pos;
            this.note = note;
            this.bell = bell;
            this.volume = volume;
        }
    }

    private static int nextFloodInTicks = -1;
    /** −1 idle, else 0..{@link #floodHoldTicks} timeline cursor. */
    private static int floodTick = -1;
    private static int floodHoldTicks = FLOOD_TICKS;
    private static boolean floodAfterglowVariant;
    private static final List<PendingNote> NOTE_QUEUE = new ArrayList<>();

    private MemoryFloodService() {}

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        ServerLevel level = event.getServer().overworld();
        drainNotes(level);
        EchoGroveState state = EchoGroveState.get(event.getServer());
        if (!state.placed() || state.treeCenter() == null) {
            return;
        }
        BlockPos tree = state.treeCenter();
        // Pool window driver runs regardless of flood state (spawn/discard hysteresis).
        EchoOverlayBuilder.tickWindow(level, tree, state.finaleDone());
        if (floodTick >= 0) {
            tickFlood(level, tree, state);
            return;
        }
        if (!anyPlayerWithin(level, tree, GATE_DIST)) {
            return; // countdown paused — no idle spam, no catch-up (plan §3.5)
        }
        if (nextFloodInTicks < 0) {
            rollTimer(level, state.finaleDone());
        }
        if (--nextFloodInTicks > 0) {
            return;
        }
        nextFloodInTicks = 0; // hold at zero until the pool has finished batching in
        if (EchoOverlayBuilder.poolReady()) {
            start(level, tree, FLOOD_TICKS, state.finaleDone());
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        nextFloodInTicks = -1;
        floodTick = -1;
        floodHoldTicks = FLOOD_TICKS;
        floodAfterglowVariant = false;
        NOTE_QUEUE.clear();
    }

    // ------------------------------------------------------------------ timeline

    /**
     * Starts a flood NOW (timer path, {@code /dev woah echo flood [ticks]} and the
     * finale's forced 600t hold). {@code afterglow} picks the warmer cue variant
     * ({@code b=1}, plan §3.5).
     */
    public static void start(ServerLevel level, BlockPos tree, int holdTicks, boolean afterglow) {
        if (floodTick >= 0 && holdTicks <= floodHoldTicks - floodTick) {
            return; // an equal-or-longer flood is already running
        }
        floodTick = 0;
        floodHoldTicks = Math.max(80, holdTicks);
        floodAfterglowVariant = afterglow;
        Vec3 center = Vec3.atCenterOf(tree);
        FxPayloads.sendFxEvent(level, EchoGroveCues.CUE_ECHO_FLOOD, center,
                floodHoldTicks, afterglow ? 1.0F : 0.0F, CUE_RANGE);
        if (NOTE_FALLBACK) {
            queueMotif(center.add(0.0D, EchoGroveLayout.TREE_HEIGHT * 0.75D, 0.0D),
                    floodHoldTicks >= 400 ? 2 : 1);
        }
        EclipseMod.LOGGER.debug("MemoryFloodService: flood start (hold {}t, afterglow {})",
                floodHoldTicks, afterglow);
    }

    private static void tickFlood(ServerLevel level, BlockPos tree, EchoGroveState state) {
        int t = floodTick++;
        boolean finaleDone = state.finaleDone();
        // Grow pushes: one wave per tick t0–t3, from the tree outward (plan §5.2).
        if (t >= 0 && t < EchoOverlayBuilder.WAVES) {
            EchoOverlayBuilder.pushWave(t, true, WAVE_WINDOW, finaleDone);
        }
        if (t == 0) {
            EchoSceneService.setGlowAll(1.0F);
        }
        if (t == 2) {
            EchoOverlayBuilder.brightnessStep(true); // hidden inside the growth motion
        }
        // Shrink pushes mirror the grow at the tail (t140–t143 on the 160t base).
        int shrinkStart = floodHoldTicks - WAVE_WINDOW;
        if (t >= shrinkStart && t < shrinkStart + EchoOverlayBuilder.WAVES) {
            EchoOverlayBuilder.pushWave(t - shrinkStart, false, WAVE_WINDOW, finaleDone);
        }
        if (t == floodHoldTicks - 2 && !finaleDone) {
            EchoOverlayBuilder.brightnessStep(false); // last allowed step ≤ 3 (plan §3.5)
        }
        if (t >= floodHoldTicks) {
            EchoSceneService.setGlowAll(0.0F);
            floodTick = -1;
            floodHoldTicks = FLOOD_TICKS;
            rollTimer(level, finaleDone);
        }
    }

    private static void rollTimer(ServerLevel level, boolean finaleDone) {
        int base = finaleDone ? AFTERGLOW_INTERVAL : BASE_INTERVAL;
        nextFloodInTicks = base + level.random.nextInt(INTERVAL_JITTER * 2 + 1) - INTERVAL_JITTER;
    }

    public static boolean floodActive() {
        return floodTick >= 0;
    }

    /** Countdown snapshot for {@code /dev woah echo status} (−1 = not rolled yet). */
    public static int ticksUntilFlood() {
        return nextFloodInTicks;
    }

    /** Dev reset support: cancel a running flood and re-park (pool handled by caller). */
    public static void cancelFlood() {
        floodTick = -1;
        floodHoldTicks = FLOOD_TICKS;
        nextFloodInTicks = -1;
        EchoSceneService.setGlowAll(0.0F);
    }

    // ------------------------------------------------------------------ note fallback

    /** Queues the motif {@code repeats}× (finale plays it twice back to back — plan §6.5). */
    private static void queueMotif(Vec3 pos, int repeats) {
        int motifSpan = (MOTIF[MOTIF.length - 1][1] + 4) * MOTIF_GRID;
        for (int r = 0; r < repeats; r++) {
            for (int[] row : MOTIF) {
                int delay = row[1] * MOTIF_GRID + r * motifSpan;
                NOTE_QUEUE.add(new PendingNote(delay, pos, row[0], false, 0.55F));
                if (row[2] == 1) {
                    // Bell layer one octave down, quiet — the "wound spring" body.
                    NOTE_QUEUE.add(new PendingNote(delay, pos,
                            Math.max(0, row[0] - 12), true, 0.28F));
                }
            }
        }
    }

    /**
     * The deposit chime (plan §3.6 "Abgabe"): three ascending notes, the whole
     * cadence a semitone higher per deposited fragment — the tree audibly "fills up".
     */
    public static void playDepositChime(ServerLevel level, Vec3 pos, int deposited) {
        int base = 12 + Math.min(5, Math.max(1, deposited));
        NOTE_QUEUE.add(new PendingNote(0, pos, base, false, 0.7F));
        NOTE_QUEUE.add(new PendingNote(4, pos, base + 4, false, 0.7F));
        NOTE_QUEUE.add(new PendingNote(8, pos, base + 7, true, 0.7F));
    }

    private static void drainNotes(ServerLevel level) {
        if (NOTE_QUEUE.isEmpty()) {
            return;
        }
        Iterator<PendingNote> it = NOTE_QUEUE.iterator();
        while (it.hasNext()) {
            PendingNote note = it.next();
            if (--note.delay >= 0) {
                continue;
            }
            it.remove();
            float pitch = (float) Math.pow(2.0D, (note.note - 12) / 12.0D);
            level.playSound(null, note.pos.x, note.pos.y, note.pos.z,
                    note.bell ? SoundEvents.NOTE_BLOCK_BELL : SoundEvents.NOTE_BLOCK_CHIME,
                    SoundSource.RECORDS, note.volume, pitch);
        }
    }

    private static boolean anyPlayerWithin(ServerLevel level, BlockPos tree, double dist) {
        double distSq = dist * dist;
        Vec3 center = Vec3.atCenterOf(tree);
        for (ServerPlayer player : level.players()) {
            if (player.position().distanceToSqr(center) <= distSq) {
                return true;
            }
        }
        return false;
    }
}
