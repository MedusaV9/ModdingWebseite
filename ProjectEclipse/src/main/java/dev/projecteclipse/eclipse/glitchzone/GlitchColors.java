package dev.projecteclipse.eclipse.glitchzone;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * GLITCHZONE accent-colour palette (F-049). Every {@link GlitchZoneEffects} effect carries
 * an optional colour id; the client resolves it to the {@code AccentColor} / {@code
 * AccentAmount} uniform pair that all five glitch fragment shaders read.
 *
 * <p><b>The default is not a colour.</b> {@link #DEFAULT} (the empty string) means "leave
 * the effect's shipped accent alone" and feeds {@code AccentAmount = 0}, which makes every
 * shader fall back to its own hard-coded constant (outline's phosphor green, void's sonar
 * green, invert's violet seam, scanline's warm phosphor, datamosh's untinted grade). So a
 * zone created without a colour is bit-identical to the pre-F-049 build — the colour system
 * can only ever ADD a deviation, never shift the baseline.</p>
 *
 * <p><b>Suffix syntax</b>: operators type one token, {@code <effect>_<colour>}
 * ({@code void_purple}, {@code outline_cyan}); {@link #split} takes it apart. Effect ids
 * carry no underscore today, but the split is written against the LAST underscore and only
 * accepts a split whose two halves are both valid — an effect id with an underscore in it
 * would still parse as itself.</p>
 */
public final class GlitchColors {
    /** "No colour commanded" — the shader keeps its shipped accent ({@code AccentAmount} 0). */
    public static final String DEFAULT = "";

    /** A linear-space accent colour. Shaders rescale it to the shipped accent's luma. */
    public record Rgb(float r, float g, float b) {}

    /** Neutral fed alongside {@code AccentAmount = 0}; the shaders ignore it there. */
    public static final Rgb NEUTRAL = new Rgb(1.0F, 1.0F, 1.0F);

    private static final Map<String, Rgb> PALETTE = new LinkedHashMap<>();

    static {
        // Saturated, high-contrast hues: these get luma-matched to each effect's shipped
        // accent in-shader, so only the HUE matters here — brightness is not a knob.
        PALETTE.put("purple", new Rgb(0.62F, 0.20F, 1.00F));
        PALETTE.put("green", new Rgb(0.30F, 0.95F, 0.62F));
        PALETTE.put("red", new Rgb(1.00F, 0.16F, 0.20F));
        PALETTE.put("cyan", new Rgb(0.18F, 0.92F, 1.00F));
        PALETTE.put("orange", new Rgb(1.00F, 0.52F, 0.12F));
        PALETTE.put("white", new Rgb(0.94F, 0.95F, 1.00F));
        PALETTE.put("pink", new Rgb(1.00F, 0.34F, 0.72F));
    }

    /** All colour ids, in the order they should be suggested to operators. */
    public static final List<String> IDS = List.copyOf(PALETTE.keySet());

    private GlitchColors() {}

    /** Whether {@code colour} is a palette id or {@link #DEFAULT}. */
    public static boolean isValid(String colour) {
        return colour.isEmpty() || PALETTE.containsKey(colour);
    }

    /** Palette entry, or {@link #NEUTRAL} for {@link #DEFAULT} / unknown ids. */
    public static Rgb rgb(String colour) {
        return PALETTE.getOrDefault(colour, NEUTRAL);
    }

    /**
     * The {@code AccentAmount} uniform: 0 for {@link #DEFAULT} (shader keeps its shipped
     * accent), 1 for a palette colour. Unknown ids read as default — a save written by a
     * newer build with an unknown colour degrades to the shipped look, never to black.
     */
    public static float amount(String colour) {
        return PALETTE.containsKey(colour) ? 1.0F : 0.0F;
    }

    /** Normalizes operator input ({@code null}/blank/unknown-case → a lowercase id). */
    public static String normalize(String colour) {
        if (colour == null) {
            return DEFAULT;
        }
        String lower = colour.toLowerCase(Locale.ROOT);
        return PALETTE.containsKey(lower) ? lower : DEFAULT;
    }

    /**
     * Splits {@code <effect>} or {@code <effect>_<colour>} into {@code [effect, colour]}
     * ({@code colour} is {@link #DEFAULT} when no valid suffix is present). The token is
     * returned as-is in slot 0 when it does not parse — the caller's own effect validation
     * then produces the usual "unknown effect" failure with the full token in the message.
     */
    public static String[] split(String token) {
        int cut = token.lastIndexOf('_');
        if (cut > 0 && cut < token.length() - 1) {
            String effect = token.substring(0, cut);
            String colour = token.substring(cut + 1);
            if (GlitchZoneEffects.isValid(effect) && PALETTE.containsKey(colour)) {
                return new String[] {effect, colour};
            }
        }
        return new String[] {token, DEFAULT};
    }

    /**
     * Suggestion vocabulary for the {@code effect} argument: every bare effect id followed
     * by every {@code <effect>_<colour>} pair. Brigadier prefix-filters the list, so typing
     * {@code void_} narrows it to the seven void colours.
     */
    public static List<String> effectSuggestions() {
        List<String> out = new ArrayList<>(
                GlitchZoneEffects.IDS.size() * (IDS.size() + 1));
        out.addAll(GlitchZoneEffects.IDS);
        for (String effect : GlitchZoneEffects.IDS) {
            for (String colour : IDS) {
                out.add(effect + "_" + colour);
            }
        }
        return out;
    }
}
