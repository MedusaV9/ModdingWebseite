package dev.projecteclipse.eclipse.client.handbook;

import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.util.RandomSource;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Redacted "???"-style glitch text for anonymized content (hidden timeline entries, locked
 * bestiary cards — {@code docs/ideas/03_ui_ux.md} §E). Characters are re-rolled every
 * 3 ticks: the roll seed is derived from wall-clock millis bucketed to 150 ms (3 ticks at
 * 20 TPS), so callers can regenerate every frame without tracking tick events and still see
 * a stable string within each 3-tick window. A per-call {@code salt} keeps different slots
 * (nodes, cards) from glitching in lockstep. With {@code reducedFx} the text is a calm
 * static run of {@code ?}s.
 */
@OnlyIn(Dist.CLIENT)
public final class GlitchText {
    /** Glyph pool: ASCII noise + a few box/rune-feeling chars the vanilla font ships. */
    private static final char[] GLYPHS =
            "?#%&$@*+xX/\\|=~^:;<>±§¤×÷".toCharArray();
    private static final long ROLL_MILLIS = 150L; // 3 ticks
    /** Reused roll source, re-seeded per call (render thread only) — no per-call allocation. */
    private static final RandomSource RANDOM = RandomSource.create();

    private GlitchText() {}

    /** A glitched string of {@code length} chars for the given slot salt. */
    public static String scramble(int length, int salt) {
        if (EclipseClientConfig.reducedFx()) {
            return "?".repeat(Math.max(1, length));
        }
        RANDOM.setSeed(Util.getMillis() / ROLL_MILLIS * 31L + salt * 7919L);
        StringBuilder builder = new StringBuilder(length);
        for (int i = 0; i < length; i++) {
            builder.append(GLYPHS[RANDOM.nextInt(GLYPHS.length)]);
        }
        return builder.toString();
    }

    /** The classic "???" node label, still shimmering: 3 chars biased toward question marks. */
    public static String unknown(int salt) {
        if (EclipseClientConfig.reducedFx()) {
            return "???";
        }
        RANDOM.setSeed(Util.getMillis() / ROLL_MILLIS * 31L + salt * 7919L);
        StringBuilder builder = new StringBuilder(3);
        for (int i = 0; i < 3; i++) {
            builder.append(RANDOM.nextInt(3) == 0 ? GLYPHS[RANDOM.nextInt(GLYPHS.length)] : '?');
        }
        return builder.toString();
    }
}
