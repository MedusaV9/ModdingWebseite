package dev.projecteclipse.eclipse.client.sound;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * IDEA-07 §3 — the soft-border static whisper. A relative ambient loop (the
 * {@code LimboAmbience.LimboLoopSound} pattern) owned by {@code BorderFxRenderer}'s tick
 * handler, which calls {@link #update} with the exact per-tick proximity it just fed to
 * {@code EclipseFxState.setBorderProximity} (0 = far, 1 = touching the ring):
 * {@code volume = proximity² × 0.5}. Squaring keeps it a sub-audible hiss until the last
 * few blocks — an audible "you are grinding the edge of the world" warning that precedes
 * the W7 pushback burst ({@code SoftBorder.playGlitchFeedback}) instead of duplicating it.
 *
 * <p><b>Sound event:</b> resolves the W4-ATMOS ledger id {@code eclipse:ambient.border_static}
 * at start time, falling back to the shipped {@code EclipseSounds.EVENT_BORDER_GLITCH}
 * pitched {@value #FALLBACK_PITCH} while the sounds.json alias ask is pending (the
 * {@code UiSounds} self-healing pattern; the 15.7 KB glitch ogg loops acceptably as a
 * static bed at low pitch/volume).</p>
 *
 * <p><b>Lifecycle:</b> starts when proximity crosses {@value #START_THRESHOLD}, fades with
 * the squared curve, self-stops after {@value #SILENT_STOP_TICKS} silent ticks; the
 * one-attempt-per-approach guard and the {@code LoggingOut} reset are copied from
 * {@code LimboAmbience} (no per-tick retry storms, no instance leaks). One sound instance,
 * nothing charged to {@code FxBudget}.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class BorderStaticSound {
    /** W4-ATMOS ledger id (registry + sounds.json ask in W4-ATMOS_wiring.md). */
    private static final ResourceLocation STATIC_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "ambient.border_static");
    /** Fallback re-pitch of {@code event.border_glitch} — matches the pending alias (0.4). */
    private static final float FALLBACK_PITCH = 0.4F;

    /** IDEA-07 §3 volume law: {@code proximity² × 0.5}. */
    private static final float MAX_VOLUME = 0.5F;
    /** Whisper engages above this proximity; below it the approach guard re-arms. */
    private static final float START_THRESHOLD = 0.05F;
    /** Ticks of continuous silence before a live instance stops itself. */
    private static final int SILENT_STOP_TICKS = 40;

    /** Per-tick volume target, written by {@link #update}, read by the instance. */
    private static float targetVolume;
    @Nullable
    private static StaticSound staticSound;
    /** One play(...) attempt per border approach (LimboAmbience guard). */
    private static boolean soundStartedThisApproach;

    private BorderStaticSound() {}

    /**
     * The whisper hook — called once per client tick by {@code BorderFxRenderer} with the
     * proximity it just published (including the 0 of the no-level / far-away paths, so the
     * loop always winds down).
     */
    public static void update(float proximity) {
        targetVolume = proximity * proximity * MAX_VOLUME;
        if (proximity <= START_THRESHOLD) {
            soundStartedThisApproach = false;
            return;
        }
        StaticSound sound = staticSound;
        if ((sound == null || sound.isStopped()) && !soundStartedThisApproach) {
            soundStartedThisApproach = true;
            sound = new StaticSound();
            staticSound = sound;
            Minecraft.getInstance().getSoundManager().play(sound);
        }
    }

    /** Disconnect reset hook (mirrors {@code LimboAmbience.onLoggingOut}). */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        StaticSound sound = staticSound;
        if (sound != null) {
            sound.forceStop();
            staticSound = null;
        }
        soundStartedThisApproach = false;
        targetVolume = 0.0F;
    }

    /** Registered {@code ambient.border_static} or the down-pitched glitch fallback. */
    private static SoundEvent resolveStatic() {
        return BuiltInRegistries.SOUND_EVENT.getOptional(STATIC_ID)
                .orElseGet(EclipseSounds.EVENT_BORDER_GLITCH);
    }

    /**
     * The relative static bed. Volume chases the squared-proximity target with a small
     * per-tick step (smooths sprint approaches and teleports) and the instance stops itself
     * after {@value #SILENT_STOP_TICKS} silent ticks.
     */
    private static final class StaticSound extends AbstractTickableSoundInstance {
        private static final float VOLUME_STEP = 0.05F;

        private int silentTicks;

        private StaticSound() {
            super(resolveStatic(), SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
            this.looping = true;
            this.delay = 0;
            this.volume = 0.0F;
            this.relative = true;
            this.pitch = BuiltInRegistries.SOUND_EVENT.containsKey(STATIC_ID) ? 1.0F : FALLBACK_PITCH;
        }

        @Override
        public void tick() {
            float target = targetVolume;
            if (this.volume < target) {
                this.volume = Math.min(target, this.volume + VOLUME_STEP);
            } else if (this.volume > target) {
                this.volume = Math.max(target, this.volume - VOLUME_STEP);
            }
            if (this.volume <= 0.005F) {
                if (++this.silentTicks >= SILENT_STOP_TICKS) {
                    this.stop();
                }
            } else {
                this.silentTicks = 0;
            }
        }

        /** Disconnect teardown: kill the instance immediately, skipping the fade. */
        void forceStop() {
            this.stop();
        }
    }
}
