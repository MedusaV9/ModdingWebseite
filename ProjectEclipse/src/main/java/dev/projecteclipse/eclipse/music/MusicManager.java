package dev.projecteclipse.eclipse.music;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Iterator;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.menu.EclipseTitleScreen;
import dev.projecteclipse.eclipse.client.xbox.XboxEraSounds;
import dev.projecteclipse.eclipse.ferryman.ArenaDimension;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.stormfx.StormInteriorFx;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.CustomizeGuiOverlayEvent;

/**
 * Client-side situation score: one managed music channel with a 2-second crossfade.
 *
 * <p>Priority is explicit cue, boss, expansion, Xbox dimension, Limbo, title screen. While
 * either side of a custom crossfade is audible, vanilla's music scheduler is stopped so menu
 * and biome tracks never double-play. The {@link SoundSource#MUSIC} category still applies the
 * player's vanilla Music slider after {@link MusicConfig#volumeMultiplier()}.</p>
 *
 * <p><b>MUSICFADE — how a fade-out actually works now.</b> Every voice is a
 * {@link MusicFadeSound} that owns its own volume envelope and only stops itself once the
 * envelope reaches zero. Fading voices live in {@link #fading} until the engine drops them;
 * they are NEVER force-stopped just because the channel went idle. The old single
 * {@code outgoing} slot did exactly that: {@code onClientTick} re-entered
 * {@code transitionTo(null)} on every idle tick (its guard was {@code current == null}, which
 * is true while idle) and the first thing that method did with a {@code null} target was
 * {@code outgoing.forceStop()} — so every fade-to-silence died one tick after it started and
 * the music cut off hard. Cue→cue crossfades were unaffected, which is why only "the music
 * ends abruptly" was ever reported.</p>
 *
 * <p><b>What a fade can never survive</b>: a dimension change. {@code Minecraft.setLevel}
 * runs {@code updateScreenAndTick} → {@code soundManager.stop()} → {@code SoundEngine.stopAll},
 * which kills every channel instantly. Sequences that hop dimensions (the limbo → overworld
 * start cutscene) must therefore START their fade before the hop — see
 * {@code limbo.StartEventCutscene}'s music-fade beat — because no client-side envelope can
 * outlive the engine wipe.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class MusicManager {
    /** Default crossfade length of a ladder swap (2 s). */
    private static final int FADE_TICKS = 40;
    /** Concurrent fading-out voices kept alive; the oldest beyond this is force-stopped. */
    private static final int MAX_FADING_VOICES = 3;
    /**
     * How long a boss cue survives without its bossbar RENDER event firing (M-2). The
     * {@code BossEventProgress} hook goes silent whenever the boss-bar GUI layer is skipped
     * — F1 hide-GUI and the cutscene letterbox's layer cancellation — even though the fight
     * is still running. No payload-fed boss lifecycle source exists client-side
     * ({@code S2CBossbarStylePayload} tags a bar UUID with a theme but carries neither the
     * boss identity nor an end signal), so the render hook stays and this 100-tick grace
     * bridges letterboxed boss intros and brief F1 use instead of the old 1 s.
     */
    private static final long BOSS_SEEN_GRACE_MILLIS = 100L * 50L;
    /** fog_storm rung hysteresis on {@link StormInteriorFx#interiorAmount()} (arm/disarm). */
    private static final float FOG_STORM_ARM = 0.55F;
    private static final float FOG_STORM_DISARM = 0.15F;
    /** eclipse_totality rung threshold on {@link EclipseFxState#eclipseAmount}. */
    private static final float TOTALITY_THRESHOLD = 0.6F;
    /** Manager-side ticks granted for the engine to accept a freshly played instance. */
    private static final int START_GRACE_TICKS = 10;
    /** Consecutive refused starts before a cue is given up (C19 anti-mute belt). */
    private static final int FAILED_STARTS_LIMIT = 3;

    @Nullable
    private static MusicFadeSound current;
    /** Voices running out their fade-out envelope; dropped once the engine forgets them. */
    private static final List<MusicFadeSound> fading = new ArrayList<>(MAX_FADING_VOICES + 1);
    @Nullable
    private static MusicCues forcedCue;
    private static int forcedTicks;

    @Nullable
    private static MusicCues observedBossCue;
    private static long bossSeenMillis;

    private static boolean suppressSituation;
    @Nullable
    private static MusicCues suppressedSituation;

    /** fog_storm hysteresis latch: armed above {@link #FOG_STORM_ARM}, released below {@link #FOG_STORM_DISARM}. */
    private static boolean fogStormArmed;

    /**
     * Music memory (IDEA-08 #4): the situation cue being held past its rung going quiet.
     * Mirrors {@code observedBossCue}'s grace, generalized to any cue with
     * {@link MusicCues#lingerTicks()} &gt; 0. Rung upgrades bypass it so fights take over
     * instantly; only drops (to silence or a weaker rung) are held.
     */
    @Nullable
    private static MusicCues lingerCue;
    private static int lingerTicksLeft;

    /**
     * C19 anti-mute belt: cues whose instances the engine repeatedly refuses to start (or
     * culls before the fade-in completes, e.g. an unplayable asset) are latched here and
     * excluded from selection. Without the latch a broken cue keeps {@code current}
     * occupied forever, which keeps {@link net.minecraft.client.sounds.MusicManager}
     * muted every tick — total silence instead of falling back to vanilla music.
     */
    private static final EnumSet<MusicCues> deadCues = EnumSet.noneOf(MusicCues.class);
    private static final EnumMap<MusicCues, Integer> failedStarts = new EnumMap<>(MusicCues.class);

    private MusicManager() {}

    /** Starts an explicit cue (used by payload handlers and client sequence hooks). */
    public static void play(MusicCues cue) {
        forcedCue = cue;
        forcedTicks = cue.looping() ? Integer.MAX_VALUE : cue.durationTicks();
        suppressSituation = false;
    }

    /**
     * Fades out explicit and automatic music over the default {@value #FADE_TICKS}-tick
     * crossfade. The current automatic situation remains muted until it changes, so
     * {@code /dev music stop} does not restart the same cue next tick.
     */
    public static void stop() {
        fadeOut(FADE_TICKS);
    }

    /**
     * MUSICFADE entry point: fades the channel to silence over {@code ticks} — the voice
     * keeps streaming at a falling volume and stops itself only at zero. Same muting
     * semantics as {@link #stop()} (the situation underneath stays suppressed until it
     * changes), just with a caller-chosen fade length: cinematic hand-offs want a long
     * musical fade, a dev stop wants the short one.
     *
     * <p>Callers whose sequence crosses a DIMENSION CHANGE must start the fade early
     * enough to finish before the hop — {@code SoundEngine.stopAll()} runs on every
     * {@code Minecraft.setLevel} and no envelope survives it (see the class doc).</p>
     */
    public static void fadeOut(int ticks) {
        Minecraft minecraft = Minecraft.getInstance();
        forcedCue = null;
        forcedTicks = 0;
        lingerCue = null;
        lingerTicksLeft = 0;
        suppressedSituation = naturalCue(minecraft);
        suppressSituation = true;
        transitionTo(minecraft, null, Math.max(1, ticks));
    }

    /**
     * Clears the forced cue iff it matches, letting the situation ladder resume immediately.
     * Unlike {@link #stop()} this never mutes the underlying situation — intended for
     * private overrides such as the Lantern Gaze {@code kill_contract} release, where the
     * boss theme underneath must come back the moment the override ends.
     */
    public static void release(MusicCues cue) {
        if (forcedCue == cue) {
            forcedCue = null;
            forcedTicks = 0;
        }
    }

    public static String currentCueId() {
        return current == null ? "" : current.cue().id();
    }

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        Minecraft minecraft = Minecraft.getInstance();
        cleanupFinished(minecraft);

        if (forcedCue != null && forcedTicks != Integer.MAX_VALUE && forcedTicks > 0) {
            forcedTicks--;
            if (forcedTicks == 0) {
                forcedCue = null;
            }
        }

        MusicCues natural = naturalCue(minecraft);
        if (suppressSituation) {
            if (natural == suppressedSituation) {
                natural = null;
            } else {
                suppressSituation = false;
                suppressedSituation = null;
            }
        }
        natural = applyLinger(natural);

        MusicCues desired = MusicConfig.enabled() ? (forcedCue != null ? forcedCue : natural) : null;
        if (desired != null && deadCues.contains(desired)) {
            desired = null;
        }
        // MUSICFADE: compare against the ACTIVE cue (null while idle), never against
        // `current == null`. The old guard re-entered transitionTo on every idle tick,
        // which force-stopped the voice that was still fading out.
        MusicCues activeCue = current == null ? null : current.cue();
        if (activeCue != desired) {
            transitionTo(minecraft, desired, FADE_TICKS);
        }

        // Minecraft's scheduler may have started a track earlier in the same client tick.
        // Stop it throughout both halves of our fade to guarantee no double-playing. When no
        // cue is active (nothing desired, nothing fading) vanilla music must keep running.
        if (current != null || !fading.isEmpty()) {
            minecraft.getMusicManager().stopPlaying();
        }
    }

    /**
     * Boss state already reaches the client as a vanilla bossbar plus an Eclipse style payload.
     * Reading the translatable bossbar name here distinguishes Herald/Ferryman without adding a
     * duplicate fight-state packet or changing {@code ClientStateCache}.
     */
    @SubscribeEvent(receiveCanceled = true)
    static void onBossbar(CustomizeGuiOverlayEvent.BossEventProgress event) {
        if (!(event.getBossEvent().getName().getContents() instanceof TranslatableContents translatable)) {
            return;
        }
        MusicCues cue = switch (translatable.getKey()) {
            case "entity.eclipse.herald.bossbar" -> MusicCues.BOSS_HERALD;
            case "entity.eclipse.ferryman.bossbar" -> MusicCues.BOSS_FERRYMAN;
            case "entity.eclipse.rift_warden.bossbar" -> MusicCues.BOSS_RIFT_WARDEN;
            case "entity.eclipse.fog_tyrant.bossbar" -> MusicCues.BOSS_FOG_TYRANT;
            default -> null;
        };
        // Other bossbars may render later in the same frame. They must not erase a matching
        // Eclipse boss observed above; the grace window clears it when that bar disappears.
        if (cue != null) {
            observedBossCue = cue;
            bossSeenMillis = Util.getMillis();
        }
    }

    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        forceStopAll();
        forcedCue = null;
        forcedTicks = 0;
        observedBossCue = null;
        bossSeenMillis = 0L;
        suppressSituation = false;
        suppressedSituation = null;
        fogStormArmed = false;
        lingerCue = null;
        lingerTicksLeft = 0;
        deadCues.clear();
        failedStarts.clear();
    }

    @Nullable
    private static MusicCues naturalCue(Minecraft minecraft) {
        if (minecraft.level != null && observedBossCue != null
                && Util.getMillis() - bossSeenMillis <= BOSS_SEEN_GRACE_MILLIS) {
            return observedBossCue;
        }
        if (minecraft.level != null) {
            // fog_storm: inside a hunting fog storm. Asymmetric 0.55/0.15 hysteresis on the
            // smoothed interior scalar stops wall-skimming flap; brief exits are then covered
            // by the cue's 200-tick linger (music memory).
            float interior = StormInteriorFx.interiorAmount();
            if (fogStormArmed ? interior < FOG_STORM_DISARM : interior > FOG_STORM_ARM) {
                fogStormArmed = !fogStormArmed;
            }
            if (fogStormArmed) {
                return MusicCues.FOG_STORM;
            }
            // eclipse_totality: black-sun drone while the eclipse grade is (near) total.
            // Below boss/storm priority so fights and storm interiors keep their themes.
            if (EclipseFxState.eclipseAmount(0.0F) > TOTALITY_THRESHOLD) {
                return MusicCues.ECLIPSE_TOTALITY;
            }
            var dimension = minecraft.level.dimension();
            if ((dimension == Level.OVERWORLD && ClientStateCache.stageAnimatingOverworld)
                    || (dimension == Level.NETHER && ClientStateCache.stageAnimatingNether)) {
                return MusicCues.EXPANSION_THEME;
            }
            if (XboxDimensions.isXboxDimension(dimension)) {
                // C17 seam: while XboxEraSounds streams an actual C418-era vanilla track,
                // the nostalgia bed yields the channel; it resumes in the gaps between
                // tracks (XboxEraSounds keeps vanilla's scheduler muted meanwhile).
                return XboxEraSounds.eraTrackPlaying() ? null : MusicCues.XBOX_NOSTALGIA;
            }
            // The C10 ferryman arena is limbo-styled (same sky, same dread): it shares the
            // ambience bed so spectators beyond bossbar range are not left in silence.
            if (dimension == LimboDimension.LIMBO || ArenaDimension.isArena(dimension)) {
                return MusicCues.LIMBO_AMBIENCE;
            }
            // day_final: the last planned day's dread bed — weakest in-world rung, colors
            // the gaps between beats on day 14 and bows out to every rung above.
            if (dimension == Level.OVERWORLD && ClientStateCache.day >= FinaleRitual.FINALE_DAY) {
                return MusicCues.DAY_FINAL;
            }
        }
        if (minecraft.screen instanceof EclipseTitleScreen) {
            return MusicCues.TITLE_THEME;
        }
        return null;
    }

    /**
     * Situation-ladder rank for the linger comparison (higher = louder claim). Matches the
     * branch order in {@link #naturalCue}; non-situation cues rank 0 and never linger.
     */
    private static int situationRank(@Nullable MusicCues cue) {
        if (cue == null) {
            return 0;
        }
        return switch (cue) {
            case BOSS_HERALD, BOSS_FERRYMAN, BOSS_RIFT_WARDEN, BOSS_FOG_TYRANT -> 8;
            case FOG_STORM -> 7;
            case ECLIPSE_TOTALITY -> 6;
            case EXPANSION_THEME -> 5;
            case XBOX_NOSTALGIA -> 4;
            case LIMBO_AMBIENCE -> 3;
            case DAY_FINAL -> 2;
            case TITLE_THEME -> 1;
            default -> 0;
        };
    }

    /**
     * Music memory (IDEA-08 #4): when the natural cue would drop from the current looping
     * situation to silence or a strictly weaker rung, keep returning the current cue for its
     * {@link MusicCues#lingerTicks()} window. Upgrades (storm → boss) bypass the hold.
     */
    @Nullable
    private static MusicCues applyLinger(@Nullable MusicCues natural) {
        if (suppressSituation) {
            lingerCue = null;
            lingerTicksLeft = 0;
            return natural;
        }
        MusicCues held = lingerCue != null ? lingerCue
                : (current != null && current.cue() == forcedCue ? null
                        : current != null ? current.cue() : null);
        if (held == null || held.lingerTicks() <= 0
                || situationRank(natural) >= situationRank(held)) {
            lingerCue = null;
            lingerTicksLeft = 0;
            return natural;
        }
        // C17 seam, linger edition: the nostalgia bed yields to a STREAMING era track
        // immediately — holding it for its linger window would double-play both (the
        // tutorial-world music overlap). The bed still lingers across dimension exits.
        if (held == MusicCues.XBOX_NOSTALGIA && XboxEraSounds.eraTrackPlaying()) {
            lingerCue = null;
            lingerTicksLeft = 0;
            return natural;
        }
        if (lingerCue == null) {
            lingerCue = held;
            lingerTicksLeft = held.lingerTicks();
        }
        if (lingerTicksLeft-- > 0) {
            return lingerCue;
        }
        lingerCue = null;
        lingerTicksLeft = 0;
        return natural;
    }

    /**
     * Retargets the channel to {@code cue} ({@code null} = silence). The outgoing voice is
     * handed a {@code fadeOutTicks}-long envelope and parked in {@link #fading} — it keeps
     * streaming and stops ITSELF at zero. Nothing here ever hard-stops a voice.
     */
    private static void transitionTo(Minecraft minecraft, @Nullable MusicCues cue, int fadeOutTicks) {
        if (current != null && current.cue() == cue) {
            return;
        }
        // Un-fade resume (IDEA-08 #4): a fading voice keeps streaming until its envelope
        // hits zero, so cancelling that fade mid-flight resumes the SAME sound at the SAME
        // playback position — a brief exit dips and swells instead of restarting from bar 1.
        MusicFadeSound resumed = null;
        if (cue != null) {
            for (Iterator<MusicFadeSound> iterator = fading.iterator(); iterator.hasNext();) {
                MusicFadeSound voice = iterator.next();
                if (voice.cue() == cue && !voice.isStopped()) {
                    resumed = voice;
                    iterator.remove();
                    break;
                }
            }
        }
        if (current != null) {
            current.fadeOut(fadeOutTicks);
            parkFading(current);
            current = null;
        }
        if (resumed != null) {
            resumed.resume(FADE_TICKS);
            current = resumed;
        } else if (cue != null) {
            MusicFadeSound voice = new MusicFadeSound(cue, FADE_TICKS);
            current = voice;
            minecraft.getSoundManager().play(voice);
        }
    }

    /** Parks a fading voice, force-stopping the oldest one past the concurrency cap. */
    private static void parkFading(MusicFadeSound voice) {
        fading.add(voice);
        while (fading.size() > MAX_FADING_VOICES) {
            fading.remove(0).forceStop();
        }
    }

    private static void cleanupFinished(Minecraft minecraft) {
        for (Iterator<MusicFadeSound> iterator = fading.iterator(); iterator.hasNext();) {
            MusicFadeSound voice = iterator.next();
            voice.advanceManagerAge();
            // Drop the reference only; a voice that reached zero already stopped itself,
            // and one the engine forgot (dimension change wipe) is gone either way.
            if (voice.isStopped() || voice.managerAge() > START_GRACE_TICKS
                    && !minecraft.getSoundManager().isActive(voice)) {
                iterator.remove();
            }
        }
        MusicFadeSound active = current;
        if (active != null) {
            active.advanceManagerAge();
            // `reachedFullLevel` latches once the fade-in completed, i.e. the engine really
            // played the cue; `managerAge` is manager-owned and always advances, so it also
            // catches a start the engine refused outright.
            if (active.reachedFullLevel()) {
                failedStarts.remove(active.cue());
            }
            if (active.isStopped()) {
                current = null;
            } else if (active.managerAge() > START_GRACE_TICKS
                    && !minecraft.getSoundManager().isActive(active)) {
                // The engine refused the start or culled the instance before its fade-in
                // finished (unplayable stream). A natural end of a non-looping cue — or the
                // dimension-change engine wipe — happens at full level and is NOT a failure.
                if (!active.reachedFullLevel()) {
                    noteFailedStart(active.cue());
                }
                current = null;
            }
        }
    }

    private static void noteFailedStart(MusicCues cue) {
        int failures = failedStarts.merge(cue, 1, Integer::sum);
        if (failures >= FAILED_STARTS_LIMIT && deadCues.add(cue)) {
            EclipseMod.LOGGER.warn(
                    "Music cue '{}' failed to start {} times (engine refused it or the asset "
                            + "is unplayable) — giving it up so vanilla music can resume",
                    cue.id(), failures);
        }
    }

    /** Teardown only (logout / world swap): a hard stop of every voice, no fade. */
    private static void forceStopAll() {
        if (current != null) {
            current.forceStop();
            current = null;
        }
        for (MusicFadeSound voice : fading) {
            voice.forceStop();
        }
        fading.clear();
    }
}
