package dev.projecteclipse.eclipse.client.scare;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;

import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.util.Mth;

/**
 * One scare presentation (F-064) as pure data: an id, a total length and a list of timed
 * {@link Beat}s. Times are SCRIPT TICKS (1/20 s) from cue receipt; {@link ScareDirector}
 * maps wall-clock millis onto that axis (a stalled client tick can therefore never freeze
 * a scare mid-face — the {@code JumpscareOverlay} wall-clock law).
 *
 * <p>Beats are deliberately dumb records — every envelope (fade-in/hold/fade-out, ramps)
 * is evaluated functionally from the current script time by the director/overlay, so the
 * whole model is immutable and one script instance can be replayed forever. Randomness
 * (jitter phases, glitch-text character rolls) is NOT in the data either: the director
 * derives it per frame from the cue's wire {@code seed}, so one send = one look.</p>
 *
 * <p>Photosensitivity contract for script AUTHORS ({@code ScareScripts}): at most ONE
 * {@link Flash} per ~2 s window, flashes never shorter than 3 ticks, and blackouts are
 * fades — the model has no strobe primitive on purpose. Under {@code reducedFx} the
 * director additionally drops overlays/flashes/shake/FOV/Photon entirely (blackouts stay:
 * they are covers, not stimulation).</p>
 */
public record ScareScript(String id, int durationTicks, List<Beat> beats) {

    /** Marker for every timed element of a script. */
    public sealed interface Beat permits Overlay, GlitchText, PostPulse, GhostPulse, Blackout,
            Flash, FovKick, Shake, Sound, SoundRamp, Photon, Transition {}

    /**
     * A scare texture ({@code textures/scare/<texture>.png}, square) drawn on the HUD layer.
     * {@code cx}/{@code cy} are the CENTER in screen fractions (0..1); {@code size} is the
     * height fraction of the screen ({@code <= 0} = fullscreen stretch). {@code driftX}/
     * {@code driftY} move the center in screen fractions per SECOND; {@code jitter} is the
     * seeded shudder amplitude in GUI px. {@code rgb} multiplies the texture (white = as
     * authored).
     */
    public record Overlay(int start, int end, String texture, float cx, float cy, float size,
            float maxAlpha, int fadeIn, int fadeOut, float jitter, float driftX, float driftY,
            int rgb) implements Beat {}

    /**
     * One glitching text line, centered at {@code cy} (screen fraction). {@code key} is an
     * {@code message.eclipse.scare.text.*} lang key (resolved through {@code EclipseLang});
     * {@code glitch} in 0..1 is the per-character scramble probability at full envelope.
     */
    public record GlitchText(int start, int end, String key, float cy, int rgb, float glitch,
            float scale, int fadeIn, int fadeOut) implements Beat {}

    /**
     * A pulse of one GLITCHZONE post effect ({@code GlitchZoneEffects} id) at up to
     * {@code peak} strength, wearing {@code colour} ({@code GlitchColors} id or {@code ""}
     * for the effect's shipped accent). The director forwards the strongest active pulse
     * into {@code GlitchZoneFx.handle} — same pipeline rows, same Iris/reducedFx gates.
     */
    public record PostPulse(int start, int end, String effect, float peak, String colour,
            int rampIn, int rampOut) implements Beat {}

    /** Window during which the {@code eclipse:ghost_grade} pipeline is forced on. */
    public record GhostPulse(int start, int end) implements Beat {}

    /** Fade-to-black cover (always rendered, even under reducedFx — it is a cover, not FX). */
    public record Blackout(int start, int end, int fadeIn, int fadeOut, float maxAlpha)
            implements Beat {}

    /**
     * ONE bright fullscreen pop decaying linearly over {@code duration} ticks (min 3 by
     * authoring law). Not a strobe primitive: scripts space flashes ≥ 2 s apart.
     */
    public record Flash(int at, int duration, int rgb, float maxAlpha) implements Beat {}

    /**
     * External-FOV envelope: eases to {@code scale} over {@code rampIn}, holds, releases
     * over {@code rampOut} (total {@code duration}). {@code scale < 1} zooms IN (dolly).
     */
    public record FovKick(int at, int duration, float scale, int rampIn, int rampOut)
            implements Beat {}

    /** One {@code CameraDirector.addShakeImpulse(strength, ticks, freq)} at {@code at}. */
    public record Shake(int at, float strength, int ticks, float freq) implements Beat {}

    /** One UI-channel one-shot ({@code SimpleSoundInstance.forUI}) at {@code at}. */
    public record Sound(int at, Supplier<SoundEvent> sound, float volume, float pitch)
            implements Beat {}

    /**
     * A sound whose volume ramps linearly from {@code fromVolume} to {@code toVolume}
     * across the window, then stops ({@link ScareRampSound}). {@code loop} keeps a short
     * sample droning for the whole window (whisper/drone beds).
     */
    public record SoundRamp(int start, int end, Supplier<SoundEvent> sound, float fromVolume,
            float toVolume, float pitch, boolean loop) implements Beat {}

    /**
     * One camera-anchored Photon effect at {@code at}: spawned {@code forward}/{@code up}/
     * {@code right} blocks from the camera along its axes ({@code PhotonBridge.spawn};
     * silently skipped without Photon, under reducedFx, or when the asset is missing).
     */
    public record Photon(int at, ResourceLocation fxId, double forward, double up, double right,
            float scale) implements Beat {}

    /**
     * One {@code EclipseFxState.startTransitionGlitch(in, hold, out)} envelope at {@code at}
     * — the {@code eclipse:rift_glitch} full takeover used to cover the backrooms hops.
     */
    public record Transition(int at, int in, int hold, int out) implements Beat {}

    // ------------------------------------------------------------------ envelopes

    /** Trapezoid envelope 0..1 of a windowed beat at script time {@code t} (ticks). */
    public static float envelope(float t, int start, int end, int fadeIn, int fadeOut) {
        if (t < start || t >= end) {
            return 0.0F;
        }
        float env = 1.0F;
        if (fadeIn > 0) {
            env = Math.min(env, (t - start) / fadeIn);
        }
        if (fadeOut > 0) {
            env = Math.min(env, (end - t) / fadeOut);
        }
        return Mth.clamp(env, 0.0F, 1.0F);
    }

    // ------------------------------------------------------------------ builder

    /** Fluent builder — the only way {@code ScareScripts} assembles beat lists. */
    public static Builder script(String id, int durationTicks) {
        return new Builder(id, durationTicks);
    }

    public static final class Builder {
        private final String id;
        private final int durationTicks;
        private final List<Beat> beats = new ArrayList<>();

        private Builder(String id, int durationTicks) {
            this.id = id;
            this.durationTicks = durationTicks;
        }

        /** Positioned overlay (center {@code cx},{@code cy} in screen fractions). */
        public Builder overlay(int start, int end, String texture, float cx, float cy,
                float size, float alpha, int fadeIn, int fadeOut, float jitter,
                float driftX, float driftY) {
            beats.add(new Overlay(start, end, texture, cx, cy, size, alpha, fadeIn, fadeOut,
                    jitter, driftX, driftY, 0xFFFFFF));
            return this;
        }

        /** Positioned overlay with a color multiply (e.g. blood-red tint). */
        public Builder tinted(int start, int end, String texture, float cx, float cy,
                float size, float alpha, int fadeIn, int fadeOut, float jitter,
                float driftX, float driftY, int rgb) {
            beats.add(new Overlay(start, end, texture, cx, cy, size, alpha, fadeIn, fadeOut,
                    jitter, driftX, driftY, rgb));
            return this;
        }

        /** Fullscreen-stretched overlay (veils, static washes). */
        public Builder fullscreen(int start, int end, String texture, float alpha,
                int fadeIn, int fadeOut, float jitter) {
            beats.add(new Overlay(start, end, texture, 0.5F, 0.5F, 0.0F, alpha, fadeIn, fadeOut,
                    jitter, 0.0F, 0.0F, 0xFFFFFF));
            return this;
        }

        public Builder text(int start, int end, String key, float cy, int rgb, float glitch,
                float scale) {
            beats.add(new GlitchText(start, end, key, cy, rgb, glitch, scale, 6, 6));
            return this;
        }

        public Builder pulse(int start, int end, String effect, float peak, String colour) {
            beats.add(new PostPulse(start, end, effect, peak, colour, 8, 10));
            return this;
        }

        /** Pulse with explicit ramps (sharp hits vs slow washes). */
        public Builder pulse(int start, int end, String effect, float peak, String colour,
                int rampIn, int rampOut) {
            beats.add(new PostPulse(start, end, effect, peak, colour, rampIn, rampOut));
            return this;
        }

        public Builder ghost(int start, int end) {
            beats.add(new GhostPulse(start, end));
            return this;
        }

        public Builder blackout(int start, int end, int fadeIn, int fadeOut, float alpha) {
            beats.add(new Blackout(start, end, fadeIn, fadeOut, alpha));
            return this;
        }

        public Builder flash(int at, int duration, int rgb, float alpha) {
            beats.add(new Flash(at, Math.max(3, duration), rgb, alpha));
            return this;
        }

        public Builder fov(int at, int duration, float scale, int rampIn, int rampOut) {
            beats.add(new FovKick(at, duration, scale, rampIn, rampOut));
            return this;
        }

        public Builder shake(int at, float strength, int ticks, float freq) {
            beats.add(new Shake(at, strength, ticks, freq));
            return this;
        }

        public Builder sound(int at, Supplier<SoundEvent> sound, float volume, float pitch) {
            beats.add(new Sound(at, sound, volume, pitch));
            return this;
        }

        public Builder ramp(int start, int end, Supplier<SoundEvent> sound, float fromVolume,
                float toVolume, float pitch, boolean loop) {
            beats.add(new SoundRamp(start, end, sound, fromVolume, toVolume, pitch, loop));
            return this;
        }

        public Builder photon(int at, ResourceLocation fxId, double forward, double up,
                double right, float scale) {
            beats.add(new Photon(at, fxId, forward, up, right, scale));
            return this;
        }

        public Builder transition(int at, int in, int hold, int out) {
            beats.add(new Transition(at, in, hold, out));
            return this;
        }

        public ScareScript build() {
            return new ScareScript(id, durationTicks, List.copyOf(beats));
        }
    }
}
