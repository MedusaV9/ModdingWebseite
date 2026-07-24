package dev.projecteclipse.eclipse.music;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.menu.EclipseTitleScreen;
import dev.projecteclipse.eclipse.limbo.LimboDimension;
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
        suppressedSituation = naturalCue(minecraft);
        suppressSituation = true;
        transitionTo(minecraft, null);
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
    }

    @Nullable
    private static MusicCues naturalCue(Minecraft minecraft) {
        if (minecraft.level != null && observedBossCue != null
                && Util.getMillis() - bossSeenMillis <= BOSS_SEEN_GRACE_MILLIS) {
            return observedBossCue;
        }
        if (minecraft.level != null) {
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
        }
        if (minecraft.screen instanceof EclipseTitleScreen) {
            return MusicCues.TITLE_THEME;
        }
        return null;
    }

    private static void transitionTo(Minecraft minecraft, @Nullable MusicCues cue) {
        if (current != null && current.cue == cue) {
            return;
        }
        if (outgoing != null) {
            outgoing.forceStop();
            outgoing = null;
        }
        if (current != null) {
            current.fadeOut();
            outgoing = current;
            current = null;
        }
        if (cue != null) {
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

        void forceStop() {
            stop();
        }
    }
}
