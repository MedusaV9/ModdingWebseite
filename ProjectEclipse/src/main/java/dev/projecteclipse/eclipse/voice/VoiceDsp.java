package dev.projecteclipse.eclipse.voice;

import java.util.Random;

/**
 * Naive, allocation-light PCM voice effects for the W4-TOGGLES voice changer. Operates on the
 * mono 48 kHz {@code short[]} frames (960 samples / 20 ms) that Simple Voice Chat's opus
 * decoder produces — but has zero Voice Chat API imports so it stays loadable (and unit
 * testable) without the mod.
 *
 * <p><b>Pitch algorithm</b> (deliberately simple/robust, per plan): linear-interpolation
 * resample of the frame by the pitch factor, then window-overlap back to the original frame
 * length — pitch-up frames are looped with a short equal-gain crossfade at each seam,
 * pitch-down frames are truncated. Each 20 ms frame is processed independently (no
 * inter-frame overlap-add), which produces a slight robotic/graininess at frame edges —
 * accepted artifact for a party voice changer; intelligibility is fine for 0.8–1.25×.</p>
 *
 * <p><b>CPU cost</b>: ~2×960 lerps + one 960-sample copy per frame per speaking player, i.e.
 * a few microseconds on any modern core. The opus re-encode in {@link VoiceChangerPlugin}
 * dominates the real cost (~100–300 µs/frame); the whole pipeline is measured against the
 * configured frame budget (default 2 ms) and auto-disables when exceeded.</p>
 */
public final class VoiceDsp {
    public static final float GLITCH_PITCH_MIN = 0.85F;
    public static final float GLITCH_PITCH_MAX = 1.25F;

    /** Max seam crossfade length in samples (2 ms at 48 kHz). */
    private static final int MAX_FADE_SAMPLES = 96;
    private static final float TWO_PI = (float) (Math.PI * 2.0);
    /** Sample rate the tremolo phase increment assumes (SVC is fixed at 48 kHz). */
    private static final float SAMPLE_RATE = 48_000.0F;

    private VoiceDsp() {}

    /** Per-speaker DSP carry-over (tremolo phase, glitch RNG). One instance per pipeline. */
    public static final class FxState {
        float tremoloPhase;
        final Random random = new Random();

        /** Called at end-of-transmission so the next utterance starts clean. */
        public void reset() {
            tremoloPhase = 0.0F;
        }
    }

    /**
     * Applies {@code preset} to one PCM frame. Returns the input array untouched for
     * {@link VoicePreset#OFF}; otherwise returns a new array of identical length.
     */
    public static short[] apply(short[] frame, VoicePreset preset, FxState fx) {
        if (preset == VoicePreset.OFF || frame == null || frame.length == 0) {
            return frame;
        }
        float pitch = preset.randomPitchPerFrame()
                ? GLITCH_PITCH_MIN + fx.random.nextFloat() * (GLITCH_PITCH_MAX - GLITCH_PITCH_MIN)
                : preset.basePitch();
        short[] out = pitchShift(frame, pitch);
        if (preset.tremoloDepth() > 0.0F) {
            if (out == frame) {
                out = frame.clone(); // never mutate the caller's buffer
            }
            fx.tremoloPhase = tremolo(out, fx.tremoloPhase,
                    TWO_PI * preset.tremoloHz() / SAMPLE_RATE, preset.tremoloDepth());
        }
        return out;
    }

    /**
     * Naive pitch shift keeping the frame length: resample by {@code pitch} (linear
     * interpolation), then truncate (pitch &lt; 1) or loop with a seam crossfade
     * (pitch &gt; 1) back to the input length. Returns the input array for a ~1.0 factor.
     */
    public static short[] pitchShift(short[] in, float pitch) {
        int n = in.length;
        if (n == 0 || Math.abs(pitch - 1.0F) < 1.0e-3F) {
            return in;
        }
        int m = Math.max(1, (int) (n / pitch));
        short[] resampled = new short[m];
        for (int j = 0; j < m; j++) {
            float pos = j * pitch;
            int i0 = (int) pos;
            if (i0 >= n - 1) {
                resampled[j] = in[n - 1];
            } else {
                float frac = pos - i0;
                resampled[j] = (short) (in[i0] * (1.0F - frac) + in[i0 + 1] * frac);
            }
        }
        if (m == n) {
            return resampled;
        }
        short[] out = new short[n];
        if (m > n) {
            // Deeper voice: the time-stretched signal is longer than the frame — keep the
            // head, drop the tail (loses (m-n)/m of the frame; the accepted naive artifact).
            System.arraycopy(resampled, 0, out, 0, n);
            return out;
        }
        // Higher voice: loop the shorter block, crossfading `fade` samples at every seam.
        int fade = Math.min(MAX_FADE_SAMPLES, m / 2);
        System.arraycopy(resampled, 0, out, 0, m);
        int outPos = m;
        while (outPos < n) {
            int seamStart = outPos - fade;
            for (int k = 0; k < fade; k++) {
                float t = (k + 1) / (float) (fade + 1);
                int idx = seamStart + k;
                out[idx] = (short) (out[idx] * (1.0F - t) + resampled[k] * t);
            }
            int copy = Math.min(m - fade, n - outPos);
            System.arraycopy(resampled, fade, out, outPos, copy);
            outPos += copy;
        }
        return out;
    }

    /**
     * In-place amplitude wobble. Returns the updated phase (carried across frames so the
     * tremolo is continuous while a player keeps talking).
     */
    public static float tremolo(short[] samples, float phase, float phaseIncrement, float depth) {
        for (int i = 0; i < samples.length; i++) {
            float gain = 1.0F - depth * (0.5F + 0.5F * (float) Math.sin(phase));
            samples[i] = (short) (samples[i] * gain);
            phase += phaseIncrement;
            if (phase > TWO_PI) {
                phase -= TWO_PI;
            }
        }
        return phase;
    }
}
