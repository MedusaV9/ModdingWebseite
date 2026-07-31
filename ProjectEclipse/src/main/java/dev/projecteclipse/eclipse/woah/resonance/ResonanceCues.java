package dev.projecteclipse.eclipse.woah.resonance;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-04 logical FX cue ids + the frozen FX anchor id, kept in the feature's own
 * package (the shared {@code network/fx/FxCues} file is frozen for this lane — its
 * public {@link FxCues#cue(String)} helper keeps the {@code eclipse:fx/cue/…}
 * namespace law intact). Rows for these cues live in the client registrar
 * {@code woah.resonance.client.ResonancePhotonFxRows}; senders are
 * {@link ResonanceFieldService} and {@link ResonanceMelodyMachine}.
 */
public final class ResonanceCues {
    /**
     * Position lane, crystal top-mid; {@code a} = toneIndex 0–8, {@code b} = 0
     * player strike (glitter burst) / 1 teach pulse (glow flare only). Range 96.
     * The row leg forces {@code allowMulti} (fast strike volleys — the
     * {@code CUE_GLITCH_POP} law).
     */
    public static final ResourceLocation CUE_RESONANCE_STRIKE = FxCues.cue("woah_resonance_strike");
    /**
     * Cascade hop; pos = SOURCE crystal top, {@code a} = yaw toward the target
     * crystal in degrees (the {@code CUE_WARDEN_VOLLEY_TELEGRAPH} rotation
     * pattern), {@code b} = hop length in blocks (executor scale). Range 96,
     * {@code allowMulti}.
     */
    public static final ResourceLocation CUE_RESONANCE_PULSE = FxCues.cue("woah_resonance_pulse");
    /** Fail sting; pos = altar. Red edge flicker + dissonance dust. Range 96. */
    public static final ResourceLocation CUE_RESONANCE_FAIL = FxCues.cue("woah_resonance_fail");
    /**
     * Finale; pos = altar, {@code a} = 0. Range 256 — light column, glitter rain and
     * the ground shock ring in ONE asset with staged in-asset delays (the
     * {@code CUE_DAWN_TOLL} "pacing staged INSIDE the asset" principle).
     */
    public static final ResourceLocation CUE_RESONANCE_FINALE = FxCues.cue("woah_resonance_finale");
    /**
     * W13-C3 resonance-wave beat; pos = dais surface (altar.above bottom-center),
     * {@code a} = {@code b} = 0. Range 96. Photon-only ambient garnish (no Quasar
     * fallback — pre-row baseline was nothing, and the wave is never a gameplay
     * telegraph): the ground ring expands in sync with the server front
     * ({@code ResonanceWaveFx.FRONT_SPEED} 0.45 blocks/t → ring radius 36 over 80 t).
     */
    public static final ResourceLocation CUE_RESONANCE_WAVE = FxCues.cue("woah_resonance_wave");

    /**
     * Frozen FX anchor id of the tuning-fork altar center ({@code veilfx.FxAnchors}
     * style — the anchor API is generic, the id lives with its owner). Set by the
     * builder after placement; the client choir / far-LOD read it for fallback
     * anchoring alongside the geometry payload.
     */
    public static final ResourceLocation RESONANCE_CENTER =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "resonance_center");

    private ResonanceCues() {}
}
