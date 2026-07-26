package dev.projecteclipse.eclipse.music;

import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;

/**
 * MUSICFADE — the one voice of {@link MusicManager}'s channel: a relative, streamed
 * {@link SoundInstance} whose volume is owned EXCLUSIVELY by an explicit fade envelope.
 *
 * <p>The envelope is a level in {@code [0,1]} moved by a per-tick {@link #step}; the
 * audible volume is {@code level * MusicConfig.volumeMultiplier() * cue.gain()}. A
 * fade-out lowers the level every engine tick and only calls {@link #stop()} once it
 * actually reaches zero — that is the whole contract callers rely on, and the reason
 * nothing outside this class may call {@code stop()} on a music voice except
 * {@link #forceStop()} (teardown/logout).</p>
 *
 * <p><b>Why an explicit envelope</b>: {@code SoundInstance.volume} is read by the engine
 * every tick for tickable instances, so per-tick volume writes are the only real fade
 * mechanism client-side — there is no engine-level fade API. Fade lengths are per call
 * ({@link #fadeIn(int)} / {@link #fadeOut(int)}), which is what lets the start cutscene
 * ask for a long musical fade while a ladder swap keeps the short crossfade.</p>
 *
 * <p><b>canStartSilent</b> is the C19 fix kept verbatim: every voice starts at volume 0
 * and {@code SoundEngine.play} refuses zero-volume starts otherwise ("skipped playing
 * sound …, volume was zero"), which used to mute the whole channel forever.</p>
 */
final class MusicFadeSound extends AbstractTickableSoundInstance {
    private final MusicCues cue;
    /** Envelope level in [0,1]; 0 = silent, 1 = the cue's full (config-scaled) volume. */
    private float level;
    /** Per-tick level delta: positive while fading in, negative while fading out. */
    private float step;
    /** Set by {@link #fadeOut(int)}: the voice stops itself when the level hits zero. */
    private boolean fadingOut;
    /** Latched once the envelope reached full level (a real, audible start happened). */
    private boolean reachedFullLevel;
    /** Manager-owned age; advances even while the engine refuses to start the sound. */
    private int managerAge;

    MusicFadeSound(MusicCues cue, int fadeInTicks) {
        super(cue.sound(), SoundSource.MUSIC, SoundInstance.createUnseededRandom());
        this.cue = cue;
        this.looping = cue.looping();
        this.delay = 0;
        this.relative = true;
        this.volume = 0.0F;
        this.step = stepFor(fadeInTicks);
    }

    @Override
    public boolean canStartSilent() {
        return true;
    }

    @Override
    public void tick() {
        this.level = Mth.clamp(this.level + this.step, 0.0F, 1.0F);
        if (this.level >= 1.0F) {
            this.reachedFullLevel = true;
        }
        // WANDFIX-6: cue.gain() trims quiet ceremonial stings under the config volume.
        this.volume = MusicConfig.volumeMultiplier() * this.cue.gain() * this.level;
        if (this.fadingOut && this.level <= 0.0F) {
            stop();
        }
    }

    MusicCues cue() {
        return this.cue;
    }

    /** Starts (or restarts) a fade UP to full level over {@code ticks}. */
    void fadeIn(int ticks) {
        this.fadingOut = false;
        this.step = stepFor(ticks);
    }

    /**
     * Fades the voice DOWN from wherever it currently is and stops it at zero. A
     * non-positive {@code ticks} degrades to an immediate stop (dev/teardown paths).
     */
    void fadeOut(int ticks) {
        if (ticks <= 0) {
            forceStop();
            return;
        }
        this.fadingOut = true;
        this.step = -stepFor(ticks);
    }

    /** Cancels an in-flight fade-out; the SAME stream swells back from its position. */
    void resume(int fadeInTicks) {
        fadeIn(fadeInTicks);
    }

    /** Hard stop — teardown only (logout, world swap, an unplayable voice being given up). */
    void forceStop() {
        stop();
    }

    /**
     * Whether the envelope ever reached full level. {@link MusicManager} uses it to tell a
     * natural end (a non-looping cue running out) from an engine-refused start.
     */
    boolean reachedFullLevel() {
        return this.reachedFullLevel;
    }

    int managerAge() {
        return this.managerAge;
    }

    void advanceManagerAge() {
        this.managerAge++;
    }

    private static float stepFor(int ticks) {
        return 1.0F / Math.max(1, ticks);
    }
}
