package dev.projecteclipse.eclipse.music;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.menu.EclipseTitleScreen;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
import dev.projecteclipse.eclipse.ritual.FinaleRitual;
import dev.projecteclipse.eclipse.stormfx.StormInteriorFx;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.xboxevent.XboxDimensions;
import net.minecraft.Util;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;
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
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class MusicManager {
    private static final int FADE_TICKS = 40;
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

    @Nullable
    private static CueSound current;
    @Nullable
    private static CueSound outgoing;
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

    private MusicManager() {}

    /** Starts an explicit cue (used by payload handlers and client sequence hooks). */
    public static void play(MusicCues cue) {
        forcedCue = cue;
        forcedTicks = cue.looping() ? Integer.MAX_VALUE : cue.durationTicks();
        suppressSituation = false;
    }

    /**
     * Fades out explicit and automatic music. The current automatic situation remains muted
     * until it changes, so {@code /dev music stop} does not restart the same cue next tick.
     */
    public static void stop() {
        Minecraft minecraft = Minecraft.getInstance();
        forcedCue = null;
        forcedTicks = 0;
        lingerCue = null;
        lingerTicksLeft = 0;
        suppressedSituation = naturalCue(minecraft);
        suppressSituation = true;
        transitionTo(minecraft, null);
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
        return current == null ? "" : current.cue.id();
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
        if (current == null || current.cue != desired) {
            transitionTo(minecraft, desired);
        }

        // Minecraft's scheduler may have started a track earlier in the same client tick.
        // Stop it throughout both halves of our fade to guarantee no double-playing.
        if (current != null || outgoing != null || desired != null) {
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
                return MusicCues.XBOX_NOSTALGIA;
            }
            if (dimension == LimboDimension.LIMBO) {
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
                : (current != null && current.cue == forcedCue ? null
                        : current != null ? current.cue : null);
        if (held == null || held.lingerTicks() <= 0
                || situationRank(natural) >= situationRank(held)) {
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

    private static void transitionTo(Minecraft minecraft, @Nullable MusicCues cue) {
        if (current != null && current.cue == cue) {
            return;
        }
        // Un-fade resume (IDEA-08 #4): the fading instance keeps streaming until fade==0,
        // so cancelling its fade mid-flight resumes the SAME sound at the SAME playback
        // position — a brief exit dips and swells instead of restarting from bar 1.
        CueSound resumed = null;
        if (outgoing != null) {
            if (cue != null && outgoing.cue == cue && !outgoing.isStopped()) {
                resumed = outgoing;
            } else {
                outgoing.forceStop();
            }
            outgoing = null;
        }
        if (current != null) {
            current.fadeOut();
            outgoing = current;
            current = null;
        }
        if (resumed != null) {
            resumed.resume();
            current = resumed;
        } else if (cue != null) {
            current = new CueSound(cue);
            minecraft.getSoundManager().play(current);
        }
    }

    private static void cleanupFinished(Minecraft minecraft) {
        if (outgoing != null && (outgoing.isStopped()
                || outgoing.age > 10 && !minecraft.getSoundManager().isActive(outgoing))) {
            outgoing = null;
        }
        if (current != null && (current.isStopped()
                || current.age > 10 && !minecraft.getSoundManager().isActive(current))) {
            current = null;
        }
    }

    private static void forceStopAll() {
        if (current != null) {
            current.forceStop();
            current = null;
        }
        if (outgoing != null) {
            outgoing.forceStop();
            outgoing = null;
        }
    }

    /** Relative streamed sound whose volume is owned exclusively by the crossfade. */
    private static final class CueSound extends AbstractTickableSoundInstance {
        private final MusicCues cue;
        private int fade;
        private int fadeDirection = 1;
        private int age;

        CueSound(MusicCues cue) {
            super(cue.sound(), SoundSource.MUSIC, SoundInstance.createUnseededRandom());
            this.cue = cue;
            this.looping = cue.looping();
            this.delay = 0;
            this.relative = true;
            this.volume = 0.0F;
        }

        @Override
        public void tick() {
            age++;
            fade = Mth.clamp(fade + fadeDirection, 0, FADE_TICKS);
            volume = MusicConfig.volumeMultiplier() * fade / (float) FADE_TICKS;
            if (fadeDirection < 0 && fade == 0) {
                stop();
            }
        }

        void fadeOut() {
            fadeDirection = -1;
        }

        /** Cancels an in-flight fade-out (un-fade resume; position is preserved). */
        void resume() {
            fadeDirection = 1;
        }

        void forceStop() {
            stop();
        }
    }
}
