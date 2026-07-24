package dev.projecteclipse.eclipse.client.hud;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;

/**
 * Allocation-free, wall-clock marquee for one scissored HUD row.
 *
 * <p>Overflow travels at 24 logical pixels/second, pauses 1.5 seconds at both ends and
 * returns smoothly instead of jumping. The row phase salt prevents several long goals from
 * moving in lockstep. Callers keep {@code active=false} until the panel is hovered; this
 * leaves the calm default state still and resets cleanly to the readable start edge.</p>
 */
public final class MarqueeText {
    public static final float PIXELS_PER_SECOND = 24.0F;
    public static final long END_PAUSE_MILLIS = 1_500L;

    private MarqueeText() {}

    /**
     * Draws a single line under the caller's current pose.
     *
     * @param clipLeft/Top/Right/Bottom absolute GUI-space coordinates; unlike drawing,
     *        {@link GuiGraphics} scissoring does not follow the current pose
     */
    public static void render(GuiGraphics guiGraphics, Font font, String text,
            int x, int y, int width, int color, long nowMillis, int phaseSalt, boolean active,
            int clipLeft, int clipTop, int clipRight, int clipBottom) {
        if (text == null || text.isEmpty() || width <= 0) {
            return;
        }
        int textWidth = font.width(text);
        if (textWidth <= width) {
            guiGraphics.drawString(font, text, x, y, color);
            return;
        }

        float offset = active ? offset(textWidth - width, nowMillis, phaseSalt) : 0.0F;
        guiGraphics.enableScissor(clipLeft, clipTop, clipRight, clipBottom);
        guiGraphics.drawString(font, text, x - Math.round(offset), y, color);
        guiGraphics.disableScissor();
    }

    /** Pure marquee position used by rendering and integration assertions. */
    public static float offset(int overflowPixels, long nowMillis, int phaseSalt) {
        if (overflowPixels <= 0) {
            return 0.0F;
        }
        // SidebarPanel passes hover-relative time. Stagger rows by extending their first pause
        // instead of adding an offset to the cycle: phase jumps would visibly teleport text.
        long staggerMillis = Math.floorMod((long) phaseSalt * 379L, END_PAUSE_MILLIS);
        long elapsed = nowMillis - staggerMillis;
        if (elapsed <= 0L) {
            return 0.0F;
        }
        long travelMillis = Math.max(1L,
                Math.round(overflowPixels / PIXELS_PER_SECOND * 1_000.0F));
        long period = END_PAUSE_MILLIS * 2L + travelMillis * 2L;
        long phase = Math.floorMod(elapsed, period);
        if (phase < END_PAUSE_MILLIS) {
            return 0.0F;
        }
        phase -= END_PAUSE_MILLIS;
        if (phase < travelMillis) {
            return overflowPixels * (phase / (float) travelMillis);
        }
        phase -= travelMillis;
        if (phase < END_PAUSE_MILLIS) {
            return overflowPixels;
        }
        phase -= END_PAUSE_MILLIS;
        return overflowPixels * (1.0F - phase / (float) travelMillis);
    }

    /** Convenience color fade for callers crossfading between collapsed and expanded content. */
    static int faded(int color, float alpha) {
        return EclipseUiTheme.withAlpha(color, alpha);
    }
}
