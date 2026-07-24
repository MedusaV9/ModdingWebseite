package dev.projecteclipse.eclipse.client.handbook;

import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The frozen "Quiet Eclipse" design system ({@code docs/plans_v3/P3_ui.md} §2): one flat
 * panel, one purple accent, generous whitespace, tiny purposeful motion. Every P3 screen
 * (handbook, settings, death screen, skill tree, roulette frame, loading text blocks)
 * renders through these tokens and helpers.
 *
 * <p>The entire system is {@code fill}/{@code text} only — there are NO structural texture
 * dependencies, so panels can never stretch or distort at odd aspect ratios (the B2 class
 * of bugs). Decorative textures are opt-in drop-ins added later by P2, never structural.
 * Small 1:1 icon blits (16px rail glyphs, 9px hearts) are fine — they are never scaled.</p>
 *
 * <p><b>Frozen contract (§7.2)</b> — sibling workers code against the palette constants and
 * {@link #drawPanel}, {@link #drawHairline}, {@link #drawHeader}, {@link #ellipsize},
 * {@link #withAlpha}. Do not rename or change semantics; additive-only evolution.</p>
 */
@OnlyIn(Dist.CLIENT)
public final class EclipseUiTheme {
    // --- §2.1 palette (ARGB, frozen) ---

    /** Panel fill: 95% near-black aubergine. */
    public static final int PANEL = 0xF2120B1E;
    /** Cards/rows sitting on top of {@link #PANEL}. */
    public static final int PANEL_RAISED = 0xF21A1128;
    /** 1px borders and dividers. */
    public static final int HAIRLINE = 0xFF2E2347;
    /** THE purple. Active states, headers, progress. */
    public static final int ACCENT = 0xFFB98CFF;
    /** Pressed states, timer end-phase. */
    public static final int ACCENT_DEEP = 0xFF7B4FD0;
    /** Primary text. */
    public static final int TEXT = 0xFFEDE7F8;
    /** Secondary text, captions. */
    public static final int DIM = 0xFF9A8FB8;
    /** Done ticks. */
    public static final int GOOD = 0xFF9AF0B0;
    /** Hearts lost, destructive actions. */
    public static final int DANGER = 0xFFE86078;
    /** Full-screen backdrop dim behind panels. */
    public static final int VEIL = 0xB8060310;

    // --- §2.2 spacing rhythm (baseline grid) ---

    /** Row height of the baseline grid. */
    public static final int ROW = 12;
    /** Gap between related elements. */
    public static final int GAP = 4;
    /** Inner panel padding. */
    public static final int PAD = 12;
    /** Gap between sections. */
    public static final int SECTION_GAP = 16;

    private EclipseUiTheme() {}

    /** {@link #drawPanel(GuiGraphics, int, int, int, int, float)} at full opacity. */
    public static void drawPanel(GuiGraphics guiGraphics, int x, int y, int width, int height) {
        drawPanel(guiGraphics, x, y, width, height, 1.0F);
    }

    /**
     * The one panel: {@link #PANEL} fill, 1px {@link #HAIRLINE} border, 1px {@link #ACCENT}
     * top edge. Pure fills — crisp at every window size, gui scale and aspect ratio.
     */
    public static void drawPanel(GuiGraphics guiGraphics, int x, int y, int width, int height, float alpha) {
        guiGraphics.fill(x, y, x + width, y + height, withAlpha(PANEL, alpha));
        int hairline = withAlpha(HAIRLINE, alpha);
        guiGraphics.fill(x, y + height - 1, x + width, y + height, hairline);
        guiGraphics.fill(x, y + 1, x + 1, y + height - 1, hairline);
        guiGraphics.fill(x + width - 1, y + 1, x + width, y + height - 1, hairline);
        guiGraphics.fill(x, y, x + width, y + 1, withAlpha(ACCENT, alpha));
    }

    /** {@link #drawHairline(GuiGraphics, int, int, int, float)} at full opacity. */
    public static void drawHairline(GuiGraphics guiGraphics, int x0, int x1, int y) {
        drawHairline(guiGraphics, x0, x1, y, 1.0F);
    }

    /** 1px horizontal {@link #HAIRLINE} divider from {@code x0} (inclusive) to {@code x1} (exclusive). */
    public static void drawHairline(GuiGraphics guiGraphics, int x0, int x1, int y, float alpha) {
        guiGraphics.fill(x0, y, x1, y + 1, withAlpha(HAIRLINE, alpha));
    }

    /** {@link #drawHeader(GuiGraphics, Font, Component, int, int, int, float)} at full opacity. */
    public static int drawHeader(GuiGraphics guiGraphics, Font font, Component title, int x, int y, int width) {
        return drawHeader(guiGraphics, font, title, x, y, width, 1.0F);
    }

    /**
     * Section header: plain {@link #ACCENT} title (no ornaments — §2.2) with a hairline
     * underneath spanning {@code width}. Returns the y where content should start
     * (baseline-grid friendly: title row + hairline + one {@link #GAP}).
     */
    public static int drawHeader(GuiGraphics guiGraphics, Font font, Component title, int x, int y, int width,
            float alpha) {
        guiGraphics.drawString(font, ellipsize(font, title.getString(), width), x, y, withAlpha(ACCENT, alpha));
        drawHairline(guiGraphics, x, x + width, y + 11, alpha);
        return y + 12 + GAP;
    }

    /**
     * Single-line clamp: text overflowing {@code maxWidth} is trimmed far enough to fit a
     * trailing {@code \u2026} so the reader can tell something was cut. Never scissor-chop
     * text (§2.2) — route every one-liner through this.
     */
    public static String ellipsize(Font font, String text, int maxWidth) {
        if (font.width(text) <= maxWidth) {
            return text;
        }
        String ellipsis = "\u2026";
        return font.plainSubstrByWidth(text, Math.max(0, maxWidth - font.width(ellipsis))).stripTrailing()
                + ellipsis;
    }

    /**
     * Multiplies a color's alpha by {@code alpha}. Accepts both ARGB tokens (their baked
     * alpha is scaled) and bare RGB ints (treated as opaque). The result is floored at
     * 4/255 because the vanilla font renders near-zero alpha as fully opaque — callers can
     * fade to zero without text popping back in.
     */
    public static int withAlpha(int color, float alpha) {
        int base = color >>> 24;
        if (base == 0) {
            base = 255;
        }
        int a = Math.max(4, Math.min(255, Math.round(base * alpha)));
        return (a << 24) | (color & 0xFFFFFF);
    }
}
