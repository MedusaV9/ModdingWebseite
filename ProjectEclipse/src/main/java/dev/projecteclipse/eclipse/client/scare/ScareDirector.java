package dev.projecteclipse.eclipse.client.scare;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.GlitchZoneFx;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.cutscene.client.CameraDirector;
import dev.projecteclipse.eclipse.veilfx.EclipseFxState;
import dev.projecteclipse.eclipse.veilfx.PhotonBridge;
import net.minecraft.client.Minecraft;
import net.minecraft.client.resources.sounds.SimpleSoundInstance;
import net.minecraft.core.BlockPos;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.util.Mth;
import net.minecraft.world.phys.Vec3;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.client.event.ClientTickEvent;

/**
 * The client end of the Scare framework (F-064): receives {@code S2CScareCuePayload}
 * (via {@code EclipsePayloads}' main-thread handler), looks the id up in
 * {@link ScareScripts} and plays the script's beats against a wall-clock timeline.
 * Everything the victim sees/hears comes from here — the server never spawns anything.
 *
 * <p><b>Timeline</b>: script ticks = {@code elapsedMillis / 50} (the {@code JumpscareOverlay}
 * wall-clock law — a stalled render/tick can't freeze a face on screen). Windowed beats are
 * evaluated functionally per frame/tick; one-shot beats fire exactly once when the timeline
 * crosses their tick. A new cue REPLACES the running script after a full cleanup — scares
 * never stack.</p>
 *
 * <p><b>Effect routing</b> (all existing seams, nothing new render-side):</p>
 * <ul>
 *   <li>Overlays / glitch text / flashes / blackouts → {@link ScareOverlay} (HUD layer).</li>
 *   <li>{@code PostPulse} → {@link GlitchZoneFx#handle} — the same five glitch pipelines
 *       the GLITCHZONE event drives, inheriting the Iris gate, the reducedFx Detail gate
 *       and the client easing. Only the strongest active pulse is forwarded (the fx state
 *       holds ONE target effect); a scare inside a live glitch zone momentarily wrestles
 *       the zone's sync for the target — accepted, both write the same self-healing
 *       target state.</li>
 *   <li>{@code GhostPulse} → {@link EclipseFxState#setGhost}; the pre-scare ghost state is
 *       snapshotted and restored (a 0-lives ghost keeps their grade after the scare).</li>
 *   <li>{@code FovKick} → {@link CameraDirector#setExternalFovScale} (borrowed exactly like
 *       {@code CreditsClient}; restored to 1 the moment no kick is active).</li>
 *   <li>{@code Shake} → {@link CameraDirector#addShakeImpulse(float, int, float)}.</li>
 *   <li>{@code Sound} → UI one-shots; {@code SoundRamp} → {@link ScareRampSound}.</li>
 *   <li>{@code Photon} → {@link PhotonBridge#spawn} anchored near the camera.</li>
 *   <li>{@code Transition} → {@link EclipseFxState#startTransitionGlitch} (the
 *       {@code eclipse:rift_glitch} takeover — the backrooms hop cover).</li>
 * </ul>
 *
 * <p><b>reducedFx</b> (photosensitivity/perf, the §A4 spirit): no shake, no FOV kicks, no
 * Photon, sounds at half volume; {@link ScareOverlay} swaps overlays/flashes for a soft
 * vignette pulse. Blackouts and transitions stay — they are covers (the backrooms clip must
 * still hide its teleport), not stimulation.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ScareDirector {
    /** Millis per script tick (the vanilla tick, wall-clock). */
    private static final float MILLIS_PER_TICK = 50.0F;

    @Nullable
    private static ScareScript script;
    private static long startMillis;
    private static long seed;
    /** Half-volume flag latched at cue time (mid-scare config flips don't retro-scale). */
    private static boolean reduced;
    /** One flag per beat index; one-shot beats fire when the timeline crosses them. */
    private static boolean[] fired = new boolean[0];
    /** Live ramp voices so a replaced/aborted script can silence its beds. */
    private static final List<ScareRampSound> RAMPS = new ArrayList<>();
    /** Whether this scare currently commands the glitch fx target / the external FOV. */
    private static boolean glitchOwned;
    private static boolean fovOwned;
    /** Ghost-grade state before the scare (restored — 0-lives ghosts keep their grade). */
    private static boolean ghostBefore;
    private static boolean ghostOwned;

    private ScareDirector() {}

    // ------------------------------------------------------------------ cue entry

    /** {@code S2CScareCuePayload} entry point (client main thread, see EclipsePayloads). */
    public static void handle(String scareId, long cueSeed) {
        if (Minecraft.getInstance().level == null) {
            return; // cue raced a disconnect — nothing to haunt
        }
        ScareScript next = ScareScripts.byId(scareId);
        if (next == null) {
            EclipseMod.LOGGER.debug("Ignoring unknown scare id '{}' (older client?)", scareId);
            return;
        }
        stop(); // one scare at a time; a new cue replaces cleanly
        script = next;
        startMillis = System.currentTimeMillis();
        seed = cueSeed;
        reduced = EclipseClientConfig.reducedFx();
        fired = new boolean[next.beats().size()];
        ghostBefore = EclipseFxState.ghostAmount(1.0F) > 0.5F;
        EclipseMod.LOGGER.debug("Scare '{}' started (seed {}, reducedFx {})",
                scareId, Long.toHexString(cueSeed), reduced);
    }

    // ------------------------------------------------------------------ state reads (overlay)

    @Nullable
    static ScareScript active() {
        return script;
    }

    /** Script time in ticks (fractional), wall-clock based. */
    static float time() {
        return (System.currentTimeMillis() - startMillis) / MILLIS_PER_TICK;
    }

    static boolean reducedFx() {
        return reduced;
    }

    /**
     * Deterministic per-cue noise in [0,1): SplitMix64-style avalanche of the wire seed and
     * the caller's stream coordinates (beat index, character index, time bucket …). This is
     * the ONLY randomness source of a running scare — same seed, same shudder.
     */
    static float noise(long a, long b) {
        long z = seed ^ (a * 0x9E3779B97F4A7C15L) ^ (b * 0xC2B2AE3D27D4EB4FL);
        z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
        z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
        z ^= z >>> 31;
        return (z >>> 40) / (float) (1 << 24);
    }

    // ------------------------------------------------------------------ tick engine

    @SubscribeEvent
    static void onClientTick(ClientTickEvent.Post event) {
        ScareScript current = script;
        if (current == null) {
            return;
        }
        float t = time();
        if (t >= current.durationTicks()) {
            stop();
            return;
        }
        fireOneShots(current, t);
        driveGlitchPulses(current, t);
        driveGhostPulses(current, t);
        driveFovKicks(current, t);
        RAMPS.removeIf(ScareRampSound::isStopped);
    }

    private static void fireOneShots(ScareScript current, float t) {
        List<ScareScript.Beat> beats = current.beats();
        for (int i = 0; i < beats.size(); i++) {
            if (fired[i]) {
                continue;
            }
            switch (beats.get(i)) {
                case ScareScript.Sound sound when t >= sound.at() -> {
                    fired[i] = true;
                    play(sound.sound().get(), sound.volume(), sound.pitch());
                }
                case ScareScript.SoundRamp ramp when t >= ramp.start() -> {
                    fired[i] = true;
                    ScareRampSound voice = new ScareRampSound(ramp.sound().get(),
                            ramp.end() - ramp.start(), ramp.fromVolume(), ramp.toVolume(),
                            ramp.pitch(), ramp.loop(), reduced ? 0.5F : 1.0F);
                    RAMPS.add(voice);
                    Minecraft.getInstance().getSoundManager().play(voice);
                }
                case ScareScript.Shake shake when t >= shake.at() -> {
                    fired[i] = true;
                    if (!reduced) {
                        CameraDirector.addShakeImpulse(shake.strength(), shake.ticks(), shake.freq());
                    }
                }
                case ScareScript.Photon photon when t >= photon.at() -> {
                    fired[i] = true;
                    if (!reduced) {
                        spawnPhoton(photon);
                    }
                }
                case ScareScript.Transition transition when t >= transition.at() -> {
                    fired[i] = true;
                    EclipseFxState.startTransitionGlitch(transition.in(), transition.hold(),
                            transition.out());
                }
                default -> { /* windowed beats are evaluated functionally, not fired */ }
            }
        }
    }

    private static void play(SoundEvent sound, float volume, float pitch) {
        Minecraft.getInstance().getSoundManager().play(
                SimpleSoundInstance.forUI(sound, pitch, volume * (reduced ? 0.5F : 1.0F)));
    }

    /** Camera-anchored Photon spawn: camera position + view/up/right offsets. */
    private static void spawnPhoton(ScareScript.Photon photon) {
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null) {
            return;
        }
        Vec3 look = minecraft.player.getViewVector(1.0F);
        Vec3 up = new Vec3(0.0D, 1.0D, 0.0D);
        Vec3 right = look.cross(up).normalize();
        Vec3 pos = minecraft.gameRenderer.getMainCamera().getPosition()
                .add(look.scale(photon.forward()))
                .add(up.scale(photon.up()))
                .add(right.scale(photon.right()));
        PhotonBridge.spawn(photon.fxId(), pos, PhotonBridge.SpawnOptions.DEFAULT
                .withScale(photon.scale(), photon.scale(), photon.scale())
                .withAllowMulti(true));
    }

    /** Forwards the strongest active pulse into the shared glitch fx state (one target). */
    private static void driveGlitchPulses(ScareScript current, float t) {
        String effect = "";
        String colour = "";
        float strength = 0.0F;
        for (ScareScript.Beat beat : current.beats()) {
            if (beat instanceof ScareScript.PostPulse pulse) {
                float value = pulse.peak() * ScareScript.envelope(t, pulse.start(), pulse.end(),
                        pulse.rampIn(), pulse.rampOut());
                if (value > strength) {
                    strength = value;
                    effect = pulse.effect();
                    colour = pulse.colour();
                }
            }
        }
        if (strength > 0.0F) {
            GlitchZoneFx.handle(effect, strength, colour, false, BlockPos.ZERO);
            glitchOwned = true;
        } else if (glitchOwned) {
            GlitchZoneFx.handle("", 0.0F, "", false, BlockPos.ZERO);
            glitchOwned = false;
        }
    }

    private static void driveGhostPulses(ScareScript current, float t) {
        boolean wanted = false;
        for (ScareScript.Beat beat : current.beats()) {
            if (beat instanceof ScareScript.GhostPulse pulse
                    && t >= pulse.start() && t < pulse.end()) {
                wanted = true;
                break;
            }
        }
        if (wanted) {
            EclipseFxState.setGhost(true);
            ghostOwned = true;
        } else if (ghostOwned) {
            EclipseFxState.setGhost(ghostBefore);
            ghostOwned = false;
        }
    }

    /** Strongest (furthest-from-1) active FOV envelope wins; released the moment none run. */
    private static void driveFovKicks(ScareScript current, float t) {
        if (reduced) {
            return; // dolly nausea is exactly what reducedFx opts out of
        }
        float scale = 1.0F;
        for (ScareScript.Beat beat : current.beats()) {
            if (beat instanceof ScareScript.FovKick kick) {
                float env = ScareScript.envelope(t, kick.at(), kick.at() + kick.duration(),
                        kick.rampIn(), kick.rampOut());
                float value = Mth.lerp(env, 1.0F, kick.scale());
                if (Math.abs(value - 1.0F) > Math.abs(scale - 1.0F)) {
                    scale = value;
                }
            }
        }
        if (scale != 1.0F) {
            CameraDirector.setExternalFovScale(scale);
            fovOwned = true;
        } else if (fovOwned) {
            CameraDirector.setExternalFovScale(1.0F);
            fovOwned = false;
        }
    }

    // ------------------------------------------------------------------ teardown

    /** Full cleanup: releases every borrowed seam and silences the script's own voices. */
    private static void stop() {
        if (script == null) {
            return;
        }
        if (glitchOwned) {
            GlitchZoneFx.handle("", 0.0F, "", false, BlockPos.ZERO);
            glitchOwned = false;
        }
        if (ghostOwned) {
            EclipseFxState.setGhost(ghostBefore);
            ghostOwned = false;
        }
        if (fovOwned) {
            CameraDirector.setExternalFovScale(1.0F);
            fovOwned = false;
        }
        for (ScareRampSound ramp : RAMPS) {
            ramp.forceStop();
        }
        RAMPS.clear();
        script = null;
    }

    /** Disconnect reset — a scare can never leak into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        // The engine drops all sounds and the fx blackboards reset themselves on logout;
        // stop() still runs for the seams that do not (external FOV scale).
        stop();
    }
}
