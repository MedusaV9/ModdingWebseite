package dev.projecteclipse.eclipse.woah.resonance;

import net.minecraft.util.RandomSource;

/**
 * WOAH-04 §6.1 — the one-place truth of the resonance field's pentatonic tuning.
 * A-major pentatonic over 1.5 octaves, 9 steps: the server plays the note-block
 * bell / amethyst chime layers at these pitches and the client pitches its choir
 * loops off the SAME table, so the valley never sings out of tune with itself.
 *
 * <p>Semitone offsets relative to pitch 1.0: {@code {−12,−10,−8,−5,−3,0,+2,+4,+7}}
 * → A3 B3 C#4 E4 F#4 A4 B4 C#5 E5 on the bell timbre. Every pitch stays inside
 * the vanilla-valid 0.5–2.0 window. Tone 0 is the lowest; the builder assigns the
 * low tones to the L monoliths (mass = depth, intuitively readable).</p>
 */
public final class ResonanceTones {
    /** Number of tone steps == number of monoliths. */
    public static final int TONE_COUNT = 9;
    /** Notes per puzzle melody (§3.2). */
    public static final int MELODY_LENGTH = 5;

    /** Semitone offsets of the 9 steps (A-major pentatonic, 1.5 octaves). */
    private static final int[] SEMITONES = {-12, -10, -8, -5, -3, 0, 2, 4, 7};

    /**
     * §6.3 finale chord: the A-E-A-E fifth stack — tone indices whose offsets are
     * {@code {−12, −5, 0, +7}}.
     */
    public static final int[] FINALE_CHORD = {0, 3, 5, 8};

    private ResonanceTones() {}

    /** Playback pitch of a tone index (equal temperament, {@code 2^(semitones/12)}). */
    public static float pitch(int toneIndex) {
        int clamped = Math.max(0, Math.min(TONE_COUNT - 1, toneIndex));
        return (float) Math.pow(2.0D, SEMITONES[clamped] / 12.0D);
    }

    /**
     * Rolls the {@value #MELODY_LENGTH}-note puzzle melody from a persisted seed:
     * tone indices 0–8, no direct repetition (§3.2 TEACH). Deterministic — the same
     * seed always yields the same melody, so a restart mid-puzzle stays stable.
     */
    public static int[] rollMelody(long seed) {
        RandomSource random = RandomSource.create(seed);
        int[] melody = new int[MELODY_LENGTH];
        int previous = -1;
        for (int i = 0; i < MELODY_LENGTH; i++) {
            int tone;
            do {
                tone = random.nextInt(TONE_COUNT);
            } while (tone == previous);
            melody[i] = tone;
            previous = tone;
        }
        return melody;
    }
}
