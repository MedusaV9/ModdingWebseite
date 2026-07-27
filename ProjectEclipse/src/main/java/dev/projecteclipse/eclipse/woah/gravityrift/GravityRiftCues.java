package dev.projecteclipse.eclipse.woah.gravityrift;

import dev.projecteclipse.eclipse.network.fx.FxCues;
import net.minecraft.resources.ResourceLocation;

/**
 * WOAH-02 logical FX cue ids, kept in the feature's own package (the
 * {@code ResonanceCues} precedent — the shared {@code network/fx/FxCues} file stays
 * frozen; its public {@link FxCues#cue(String)} helper keeps the
 * {@code eclipse:fx/cue/…} namespace law intact). Rows live in the client registrar
 * {@code woah.gravityrift.client.GravityRiftFxRows}; the sender is
 * {@link GravityRiftService}.
 */
public final class GravityRiftCues {
    /**
     * Pulse telegraph + beat in ONE staged asset (the {@code CUE_DAWN_TOLL} "pacing
     * staged INSIDE the asset" principle): sent {@value GravityRiftZone#PULSE_TELEGRAPH_TICKS}
     * ticks BEFORE the launch beat; the asset ramps a converging shimmer for 1.5 s, then
     * fires the expanding ground ring + upward wave exactly on the beat. Pos = heart
     * center; {@code a} = 0; range 256 (the far-field hook).
     */
    public static final ResourceLocation CUE_GRAVITY_PULSE = FxCues.cue("woah_gravity_pulse");
    /**
     * Heart-hit inversion start: amethyst shatter burst + rising debris sheet. Pos =
     * heart center; {@code a} = 1 accepted / 0 cooldown dud (the dud plays a small
     * fizzle only). Range 128.
     */
    public static final ResourceLocation CUE_GRAVITY_INVERT = FxCues.cue("woah_gravity_invert");
    /**
     * Inversion end resolve: settling downward wave + heart re-light. Pos = heart
     * center; range 128.
     */
    public static final ResourceLocation CUE_GRAVITY_RESOLVE = FxCues.cue("woah_gravity_resolve");
    /**
     * WINDOWED LOOP — ambient anti-gravity motes drifting up through the bowl (the
     * near-field "dust falls upward" read). Managed by the client ambience's
     * hysteresis window via {@code PhotonFxRegistry.ensureLoop}/{@code releaseLoop};
     * pos = heart center.
     */
    public static final ResourceLocation CUE_GRAVITY_MOTES = FxCues.cue("woah_gravity_motes");
    /**
     * WINDOWED LOOP — the 90-block light column above the heart (the plan §1 landmark
     * beacon). Same loop management as {@link #CUE_GRAVITY_MOTES}; pos = heart center.
     */
    public static final ResourceLocation CUE_GRAVITY_COLUMN = FxCues.cue("woah_gravity_column");

    private GravityRiftCues() {}
}
