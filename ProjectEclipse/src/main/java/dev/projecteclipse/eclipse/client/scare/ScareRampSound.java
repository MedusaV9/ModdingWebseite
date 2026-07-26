package dev.projecteclipse.eclipse.client.scare;

import net.minecraft.client.resources.sounds.AbstractTickableSoundInstance;
import net.minecraft.client.resources.sounds.SoundInstance;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.sounds.SoundSource;
import net.minecraft.util.Mth;

/**
 * The voice of one {@link ScareScript.SoundRamp} beat: a relative (head-locked) sound whose
 * volume slides linearly from {@code fromVolume} to {@code toVolume} over the beat window,
 * then stops itself. The {@code MusicFadeSound} pattern, single-shot: per-tick volume writes
 * are the only real fade mechanism client-side, and {@code canStartSilent} keeps the engine
 * from refusing a 0-volume start (whisper beds start inaudible by design).
 *
 * <p>{@code masterScale} carries the reducedFx half-volume rule (decided once at start by
 * {@link ScareDirector} — mid-ramp config flips don't retro-scale a running scare).
 * {@link #forceStop()} is the director's teardown path (script replaced, logout).</p>
 */
final class ScareRampSound extends AbstractTickableSoundInstance {
    private final int durationTicks;
    private final float fromVolume;
    private final float toVolume;
    private final float masterScale;
    private int age;

    ScareRampSound(SoundEvent sound, int durationTicks, float fromVolume, float toVolume,
            float pitch, boolean loop, float masterScale) {
        super(sound, SoundSource.AMBIENT, SoundInstance.createUnseededRandom());
        this.durationTicks = Math.max(1, durationTicks);
        this.fromVolume = fromVolume;
        this.toVolume = toVolume;
        this.masterScale = masterScale;
        this.pitch = pitch;
        this.looping = loop;
        this.delay = 0;
        this.relative = true;
        this.volume = fromVolume * masterScale;
    }

    @Override
    public boolean canStartSilent() {
        return true;
    }

    @Override
    public void tick() {
        this.age++;
        float progress = Mth.clamp(this.age / (float) this.durationTicks, 0.0F, 1.0F);
        this.volume = Mth.lerp(progress, this.fromVolume, this.toVolume) * this.masterScale;
        if (this.age >= this.durationTicks) {
            stop();
        }
    }

    /** Director teardown (script replaced mid-ramp / logout) — never called by the engine. */
    void forceStop() {
        stop();
    }
}
