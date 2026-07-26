package dev.projecteclipse.eclipse.glitchzone;

import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.resources.ResourceLocation;

/**
 * Canonical GLITCHZONE effect ids — the single list shared by the {@code /dev glitch}
 * suggestion provider, {@link GlitchZoneService} validation and the client pipeline rows
 * ({@code client.GlitchZoneFx}). Each id owns one Veil post pipeline
 * {@code assets/eclipse/pinwheel/post/glitch_<id>.json} + fragment shader
 * {@code glitch_<id>.fsh}; adding an effect = add the asset pair and one entry here.
 *
 * <p>Accent COLOUR is orthogonal to the effect id ({@link GlitchColors}): every effect reads
 * the same {@code AccentColor}/{@code AccentAmount} uniform pair, so there is no
 * {@code void_purple} entry in this list — that is {@code void} wearing {@code purple}.</p>
 */
public final class GlitchZoneEffects {
    /** World renders black; only green edge outlines remain (wireframe/scanner readout). */
    public static final String OUTLINE = "outline";
    /** Macroblock UV smears, chroma shift and full-frame tear lines (broken codec). */
    public static final String DATAMOSH = "datamosh";
    /** CRT/VHS: rolling bar, chromatic aberration, colour bleed, hold jitter, static. */
    public static final String SCANLINES = "scanlines";
    /** Negative palette with unstable hue rotation and posterization steps. */
    public static final String INVERT = "invert";
    /**
     * Near-black desaturation; a depth-banded sonar contour pulses out from the camera, or
     * from the zone centre when {@link GlitchZone#originAtCentre} is set (F-048).
     */
    public static final String VOID = "void";

    /** All effect ids, in the order they should be suggested to operators. */
    public static final List<String> IDS = List.of(OUTLINE, DATAMOSH, SCANLINES, INVERT, VOID);

    private GlitchZoneEffects() {}

    public static boolean isValid(String effect) {
        return IDS.contains(effect);
    }

    /** Veil post pipeline id of an effect: {@code eclipse:glitch_<effect>}. */
    public static ResourceLocation pipelineId(String effect) {
        return ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glitch_" + effect);
    }
}
