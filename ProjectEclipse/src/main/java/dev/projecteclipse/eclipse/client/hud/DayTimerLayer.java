package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import net.minecraft.Util;
import net.minecraft.client.DeltaTracker;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;

/**
 * R7 day-timer HUD ({@code docs/plans_v3/P3_ui.md} §3.6): a top-center real-time countdown
 * to the next day boundary, stacked under the bossbar stack via
 * {@link BossbarSkin#nextFreeBarY()} (and reserving its own row through
 * {@link BossbarSkin#reserveOverlayRow} so the announcement sweep stacks below it — see the
 * registration order in {@code EclipseGuiLayers}). All state comes from
 * {@link DayTimerCache}; this class only renders.
 *
 * <ul>
 *   <li><b>Digits</b>: {@code HH:MM:SS} ({@code DDdHH:MM} above 48 h, with a localized
 *       {@code d}/{@code T} day-unit glyph as the first separator — M-8) at 1.5x in fixed
 *       monospace cells (vanilla digits are uniformly 6px wide; the colon gets its own
 *       narrow cell), so the line never wobbles while ticking.</li>
 *   <li><b>Color</b>: lerps {@code TEXT → ACCENT} as the remaining day fraction shrinks
 *       below 50%, and {@code ACCENT → ACCENT_DEEP} (strongly purple) inside the final 10%
 *       ({@link DayTimerCache#warnMillis()}). A thin underline shows the remaining
 *       fraction.</li>
 *   <li><b>Odometer spool</b>: while {@link DayTimerCache#spooling()} (dev
 *       {@code /dev timer add|sub|set}), changed digit columns roll vertically (direction
 *       follows the shift sign) inside per-cell scissors; the eased value sweep makes the
 *       columns spool like an odometer over ~20 ticks. {@code reducedFx} snaps.</li>
 *   <li><b>Final 10 s</b>: digits pulse-scale 1.0→1.12 once per second. At 00:00:00 the
 *       line blinks 3 times ({@code ui.timer_zero} fires once, from the cache), then holds
 *       a DIM {@code 00:00:00} until the server flips the day — the timer itself triggers
 *       NOTHING.</li>
 *   <li><b>Paused</b>: frozen remaining window in {@code DIM} with a slow alpha pulse and a
 *       localized caption.</li>
 *   <li><b>Anti-clutter (B19/§3.13)</b>: hidden with {@code showDayTimer=false}, under F1
 *       ({@code hideGui}) and during cutscene HUD suppression (the layer is deliberately
 *       NOT letterbox-whitelisted). Appearing eases in with the §2.3 5-tick fade + 4px
 *       rise.</li>
 * </ul>
 *
 * <p>Hot path is allocation-free: digits render from pre-built glyph strings into reusable
 * arrays, captions are cached per {@code EclipseLang} generation, and all animation math is
 * wall-clock arithmetic.</p>
 */
public final class DayTimerLayer {
    public static final ResourceLocation LAYER_ID =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "day_timer");

    /** Base render scale of the digit line (§3.6: 1.5x digits). */
    private static final float SCALE = 1.5F;
    /** Single digit-column roll length; the eased spool re-triggers rolls while it runs. */
    private static final long ROLL_MILLIS = 120L;
    /** §2.3 appear motion: 5-tick fade + 4px rise. */
    private static final long APPEAR_MILLIS = 250L;
    /** 3 blinks (alpha 1/0.2) after the zero crossing. */
    private static final long BLINK_PHASE_MILLIS = 267L;
    private static final long BLINK_TOTAL_MILLIS = 1_600L;
    /** Final-window pulse: 1.0 → 1.12 once per second inside the last 10 s. */
    private static final long PULSE_WINDOW_MILLIS = 10_000L;
    private static final float PULSE_AMPLITUDE = 0.12F;

    /** Monospace cell layout at 1x: D D : D D : D D (digit cell 7px, colon cell 4px). */
    private static final int[] CELL_X = { 0, 7, 14, 18, 25, 32, 36, 43 };
    private static final int[] CELL_W = { 7, 7, 4, 7, 7, 4, 7, 7 };
    private static final int TOTAL_WIDTH = 50;
    /** ≥48 h layout (M-8): D D unit H H : M M — the unit cell fits a localized letter glyph. */
    private static final int[] DAY_CELL_X = { 0, 7, 14, 22, 29, 36, 40, 47 };
    private static final int[] DAY_CELL_W = { 7, 7, 8, 7, 7, 4, 7, 7 };
    private static final int DAY_TOTAL_WIDTH = 54;
    /** Vertical roll distance of one odometer step at 1x. */
    private static final float CELL_ROLL_HEIGHT = 10.0F;
    /** Pre-built glyphs — digit rendering never builds strings per frame. */
    private static final String[] GLYPHS = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":" };
    private static final int COLON = 10;
    /** Sentinel cell value rendered as the localized day-unit glyph ({@code d}/{@code T}). */
    private static final int DAY_UNIT = 11;

    // --- reusable per-frame state (client thread only; zero allocations while rendering) ---
    private static final int[] TARGET = new int[8];
    private static final int[] SHOWN = new int[8];
    private static final int[] PREVIOUS = new int[8];
    private static final long[] ROLL_START = new long[8];

    private static boolean visibleLastFrame;
    private static long appearStartMillis;

    /** Localized captions + day-unit glyph, cached per {@code EclipseLang} generation (R2 instant reload). */
    private static Component pausedCaption;
    private static Component zeroCaption;
    private static String dayUnitGlyph = "d";
    private static int captionGeneration = -1;

    private DayTimerLayer() {}

    /** {@code LayeredDraw.Layer} body, registered below the announcements by {@code EclipseGuiLayers}. */
    public static void render(GuiGraphics guiGraphics, DeltaTracker deltaTracker) {
        Minecraft minecraft = Minecraft.getInstance();
        if (!EclipseClientConfig.showDayTimer() || minecraft.level == null || minecraft.player == null
                || minecraft.options.hideGui || !DayTimerCache.armed()) {
            visibleLastFrame = false;
            return;
        }
        long now = Util.getMillis();
        boolean reduced = EclipseClientConfig.reducedFx();
        boolean appearing = !visibleLastFrame;
        if (appearing) {
            appearStartMillis = now;
        }
        visibleLastFrame = true;
        float appear = reduced ? 1.0F
                : easeOutCubic(Mth.clamp((now - appearStartMillis) / (float) APPEAR_MILLIS, 0.0F, 1.0F));

        refreshLocaleCache();

        // Digit targets from the (possibly spool-eased) displayed remaining time.
        long shownRemaining = DayTimerCache.displayedRemainingMillis();
        boolean dayMode = computeDigits((shownRemaining + 999L) / 1000L, TARGET);
        int[] cellX = dayMode ? DAY_CELL_X : CELL_X;
        int[] cellW = dayMode ? DAY_CELL_W : CELL_W;
        boolean rollEnabled = !reduced && !appearing && DayTimerCache.spooling();
        for (int i = 0; i < 8; i++) {
            if (TARGET[i] != SHOWN[i]) {
                PREVIOUS[i] = SHOWN[i];
                SHOWN[i] = TARGET[i];
                ROLL_START[i] = rollEnabled ? now : 0L;
            }
        }

        long remaining = DayTimerCache.remainingMillis();
        boolean paused = DayTimerCache.paused();
        boolean zeroHold = !paused && remaining == 0L;
        float fraction = DayTimerCache.remainingFraction();
        float alpha = appear;
        int rgb;
        if (paused) {
            rgb = EclipseUiTheme.DIM & 0xFFFFFF;
            if (!reduced) {
                // Frozen/pulsing look: slow 2s breathing while the server clock is paused.
                alpha *= 0.65F + 0.25F * Mth.sin(now * (Mth.TWO_PI / 2_000.0F));
            }
        } else if (zeroHold) {
            long blinkStart = DayTimerCache.zeroBlinkStartMillis();
            if (!reduced && blinkStart != 0L && now - blinkStart < BLINK_TOTAL_MILLIS) {
                rgb = EclipseUiTheme.ACCENT_DEEP & 0xFFFFFF;
                if ((now - blinkStart) / BLINK_PHASE_MILLIS % 2L != 0L) {
                    alpha *= 0.2F;
                }
            } else {
                rgb = EclipseUiTheme.DIM & 0xFFFFFF; // holds 00:00:00 DIM until the day flips
            }
        } else {
            rgb = colorForFraction(fraction);
        }

        // Final 10 s: pulse-scale once per second (never while a spool's rolls need scissors).
        float pulse = 1.0F;
        if (!reduced && !paused && !zeroHold && remaining <= PULSE_WINDOW_MILLIS
                && !DayTimerCache.spooling()) {
            pulse = 1.0F + PULSE_AMPLITUDE * easeOutCubic((remaining % 1_000L) / 1_000.0F);
        }

        Font font = minecraft.font;
        float totalWidthAbs = (dayMode ? DAY_TOTAL_WIDTH : TOTAL_WIDTH) * SCALE;
        int baseX = Math.round((guiGraphics.guiWidth() - totalWidthAbs) / 2.0F);
        int topY = BossbarSkin.nextFreeBarY() + 4 + Math.round(4.0F * (1.0F - appear));
        int digitHeightAbs = Math.round(9.0F * SCALE);
        int underlineY = topY + digitHeightAbs + 2;
        int color = EclipseUiTheme.withAlpha(0xFF000000 | rgb, alpha);

        boolean pulsing = pulse != 1.0F;
        if (pulsing) {
            guiGraphics.pose().pushPose();
            float centerX = guiGraphics.guiWidth() / 2.0F;
            float centerY = topY + digitHeightAbs / 2.0F;
            guiGraphics.pose().translate(centerX, centerY, 0.0F);
            guiGraphics.pose().scale(pulse, pulse, 1.0F);
            guiGraphics.pose().translate(-centerX, -centerY, 0.0F);
        }

        for (int i = 0; i < 8; i++) {
            float glyphX = baseX + cellX[i] * SCALE;
            long rollStart = ROLL_START[i];
            if (rollStart != 0L && now - rollStart < ROLL_MILLIS) {
                // Odometer roll: prev glyph slides out, new glyph slides in, inside the cell.
                float progress = easeOutCubic((now - rollStart) / (float) ROLL_MILLIS);
                float direction = DayTimerCache.spoolRising() ? -1.0F : 1.0F;
                float currentOffset = direction * (1.0F - progress) * CELL_ROLL_HEIGHT;
                float previousOffset = currentOffset - direction * CELL_ROLL_HEIGHT;
                guiGraphics.enableScissor(Mth.floor(glyphX), topY - 1,
                        Mth.ceil(glyphX + cellW[i] * SCALE), topY + digitHeightAbs + 1);
                drawGlyph(guiGraphics, font, glyphX, topY, cellW[i], PREVIOUS[i], previousOffset, color);
                drawGlyph(guiGraphics, font, glyphX, topY, cellW[i], SHOWN[i], currentOffset, color);
                guiGraphics.disableScissor();
            } else {
                drawGlyph(guiGraphics, font, glyphX, topY, cellW[i], SHOWN[i], 0.0F, color);
            }
        }

        // Thin remaining-fraction underline (frozen while paused, empty at zero).
        int underlineX1 = baseX + Math.round(totalWidthAbs);
        guiGraphics.fill(baseX, underlineY, underlineX1, underlineY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, 0.9F * alpha));
        int filled = Math.round(totalWidthAbs * fraction);
        if (filled > 0) {
            guiGraphics.fill(baseX, underlineY, baseX + filled, underlineY + 1, color);
        }
        if (pulsing) {
            guiGraphics.pose().popPose();
        }

        int bottom = underlineY + 1;
        if (paused || zeroHold) {
            Component caption = caption(paused);
            int captionX = guiGraphics.guiWidth() / 2 - font.width(caption) / 2;
            guiGraphics.drawString(font, caption, captionX, underlineY + 4,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.DIM, appear));
            bottom = underlineY + 4 + 9;
        }
        // Reserve the row BEFORE the announcement layer renders — its sweep stacks below.
        BossbarSkin.reserveOverlayRow(bottom + 4);
    }

    /** One monospace glyph, centered in its cell, drawn at {@link #SCALE} via a pose. */
    private static void drawGlyph(GuiGraphics guiGraphics, Font font, float cellX, int topY,
            int cellWidth, int glyph, float yOffset, int color) {
        String text = glyph == DAY_UNIT ? dayUnitGlyph : GLYPHS[glyph];
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(cellX, topY, 0.0F);
        guiGraphics.pose().scale(SCALE, SCALE, 1.0F);
        guiGraphics.drawString(font, text, (cellWidth - font.width(text)) / 2,
                Math.round(yOffset), color);
        guiGraphics.pose().popPose();
    }

    /**
     * Fills {@code out} with the 8 display cells: {@code HH:MM:SS}, or {@code DDdHH:MM}
     * above 48 h (§3.6 + M-8: the first separator becomes an explicit localized day-unit
     * glyph, so "02d05:33" can never read as 2 h 5 m 33 s). Returns whether day mode is
     * active so the caller picks the matching cell layout. No allocations — reused arrays
     * only.
     */
    private static boolean computeDigits(long totalSeconds, int[] out) {
        boolean dayMode = totalSeconds >= 48L * 3_600L;
        long first;
        long second;
        long third;
        if (dayMode) {
            first = Math.min(99L, totalSeconds / 86_400L);
            second = (totalSeconds % 86_400L) / 3_600L;
            third = (totalSeconds % 3_600L) / 60L;
        } else {
            first = Math.min(99L, totalSeconds / 3_600L);
            second = (totalSeconds % 3_600L) / 60L;
            third = totalSeconds % 60L;
        }
        out[0] = (int) (first / 10L);
        out[1] = (int) (first % 10L);
        out[2] = dayMode ? DAY_UNIT : COLON;
        out[3] = (int) (second / 10L);
        out[4] = (int) (second % 10L);
        out[5] = COLON;
        out[6] = (int) (third / 10L);
        out[7] = (int) (third % 10L);
        return dayMode;
    }

    /**
     * §3.6 color ramp: {@code TEXT} above half the window, lerping to {@code ACCENT} toward
     * the warn window (final 10%), then strongly purple ({@code ACCENT_DEEP}) inside it.
     */
    private static int colorForFraction(float fraction) {
        int text = EclipseUiTheme.TEXT & 0xFFFFFF;
        int accent = EclipseUiTheme.ACCENT & 0xFFFFFF;
        int deep = EclipseUiTheme.ACCENT_DEEP & 0xFFFFFF;
        if (fraction >= 0.5F) {
            return text;
        }
        if (fraction > 0.1F) {
            return lerpRgb(accent, text, (fraction - 0.1F) / 0.4F);
        }
        return lerpRgb(deep, accent, fraction / 0.1F);
    }

    private static int lerpRgb(int from, int to, float t) {
        t = Mth.clamp(t, 0.0F, 1.0F);
        int red = (int) Mth.lerp(t, (from >> 16) & 0xFF, (to >> 16) & 0xFF);
        int green = (int) Mth.lerp(t, (from >> 8) & 0xFF, (to >> 8) & 0xFF);
        int blue = (int) Mth.lerp(t, from & 0xFF, to & 0xFF);
        return (red << 16) | (green << 8) | blue;
    }

    /** Captions + day-unit glyph via {@code EclipseLang}, re-resolved on language generation bumps. */
    private static void refreshLocaleCache() {
        int generation = EclipseLang.generation();
        if (generation == captionGeneration && pausedCaption != null) {
            return;
        }
        captionGeneration = generation;
        pausedCaption = EclipseLang.tr("gui.eclipse.timer.paused");
        zeroCaption = EclipseLang.tr("gui.eclipse.timer.zero");
        String unit = EclipseLang.trString("gui.eclipse.timer.day_unit");
        // A missing key resolves to the key itself — fall back to the SI "d" glyph then.
        dayUnitGlyph = unit.isBlank() || unit.length() > 2 ? "d" : unit;
    }

    private static Component caption(boolean paused) {
        return paused ? pausedCaption : zeroCaption;
    }

    private static float easeOutCubic(float t) {
        float inv = 1.0F - Mth.clamp(t, 0.0F, 1.0F);
        return 1.0F - inv * inv * inv;
    }
}
