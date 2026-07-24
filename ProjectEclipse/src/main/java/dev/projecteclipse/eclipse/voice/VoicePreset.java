package dev.projecteclipse.eclipse.voice;

import java.util.Locale;

import javax.annotation.Nullable;

/**
 * W4-TOGGLES voice-changer presets. Pure parameter holder — no Voice Chat API imports, so
 * commands/config/persistence can reference presets even when Simple Voice Chat is absent.
 * The DSP interpretation of these numbers lives in {@link VoiceDsp}; the opus decode/encode
 * plumbing lives in {@link VoiceChangerPlugin} (the only API-importing class).
 */
public enum VoicePreset {
    /** Pass-through (no DSP cost). */
    OFF(1.0F, 0.0F, 0.0F, false),
    /** Deeper voice (naive resample pitch ~0.8). */
    DEEP(0.8F, 0.0F, 0.0F, false),
    /** Higher voice (naive resample pitch ~1.25). */
    HIGH(1.25F, 0.0F, 0.0F, false),
    /** Slightly deep + slow tremolo wobble. */
    GHOST(0.9F, 0.35F, 6.0F, false),
    /** Random micro pitch jump every 20 ms frame ({@link VoiceDsp#GLITCH_PITCH_MIN}..{@link VoiceDsp#GLITCH_PITCH_MAX}). */
    GLITCH(1.0F, 0.0F, 0.0F, true);

    private final float basePitch;
    private final float tremoloDepth;
    private final float tremoloHz;
    private final boolean randomPitchPerFrame;

    VoicePreset(float basePitch, float tremoloDepth, float tremoloHz, boolean randomPitchPerFrame) {
        this.basePitch = basePitch;
        this.tremoloDepth = tremoloDepth;
        this.tremoloHz = tremoloHz;
        this.randomPitchPerFrame = randomPitchPerFrame;
    }

    public float basePitch() {
        return basePitch;
    }

    public float tremoloDepth() {
        return tremoloDepth;
    }

    public float tremoloHz() {
        return tremoloHz;
    }

    public boolean randomPitchPerFrame() {
        return randomPitchPerFrame;
    }

    /** Stable lowercase id used in commands, config and NBT. */
    public String id() {
        return name().toLowerCase(Locale.ROOT);
    }

    @Nullable
    public static VoicePreset byId(String id) {
        for (VoicePreset preset : values()) {
            if (preset.id().equals(id)) {
                return preset;
            }
        }
        return null;
    }
}
