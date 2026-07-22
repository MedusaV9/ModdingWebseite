package dev.projecteclipse.eclipse.client.handbook;

import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.AbstractWidget;
import net.minecraft.client.gui.narration.NarrationElementOutput;
import net.minecraft.network.chat.Component;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Base widget of the Eclipse UI suite ({@code docs/ideas/03_ui_ux.md} §A/§B): hover
 * edge-detect ({@code wasHovered} flip → one {@link UiSounds#hover()} blip), a 2px purple
 * glow border that fades in over ~4 ticks, and a {@link CursorManager#requestPointer()}
 * per hovered frame (the owning screen applies it via {@code CursorManager.endFrame()}).
 * Subclasses draw their face in {@link #renderContent} and get the hover suite for free.
 * Shared with later UI workers (W15 menu / settings screens) — keep it free of
 * handbook-specific state.
 */
@OnlyIn(Dist.CLIENT)
public abstract class EclipseWidget extends AbstractWidget {
    protected static final int GLOW_COLOR = 0xB98CFF;
    /** Fraction the glow moves toward its target per rendered frame at 60 fps (~4 ticks total). */
    private static final float GLOW_STEP_PER_TICK = 0.25F;

    /** Animated hover glow, 0..1. */
    protected float glow;
    private boolean wasHovered;
    private long lastFrameMillis;

    protected EclipseWidget(int x, int y, int width, int height, Component message) {
        super(x, y, width, height, message);
    }

    @Override
    protected final void renderWidget(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        boolean hovered = isHoveredOrFocused();
        if (hovered && !wasHovered) {
            onHoverStart();
        }
        wasHovered = hovered;
        advanceGlow(hovered);
        if (hovered) {
            whileHovered();
        }
        renderContent(guiGraphics, mouseX, mouseY, partialTick);
        if (glow > 0.02F) {
            renderGlowBorder(guiGraphics, glow);
        }
    }

    /** The widget's face; the glow border is drawn on top by the base class. */
    protected abstract void renderContent(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick);

    /** Hover edge (false → true): one hover blip. Override to silence or extend. */
    protected void onHoverStart() {
        UiSounds.hover();
    }

    /** Every rendered frame while hovered: ask for the pointing-hand cursor. */
    protected void whileHovered() {
        CursorManager.requestPointer();
    }

    /** 2px glow rectangle around the widget bounds, alpha scaled by {@code strength}. */
    protected void renderGlowBorder(GuiGraphics guiGraphics, float strength) {
        int alpha = (int) (strength * 190.0F);
        int color = (alpha << 24) | GLOW_COLOR;
        int x0 = getX() - 1;
        int y0 = getY() - 1;
        int x1 = getX() + width + 1;
        int y1 = getY() + height + 1;
        guiGraphics.fill(x0, y0, x1, y0 + 2, color);
        guiGraphics.fill(x0, y1 - 2, x1, y1, color);
        guiGraphics.fill(x0, y0 + 2, x0 + 2, y1 - 2, color);
        guiGraphics.fill(x1 - 2, y0 + 2, x1, y1 - 2, color);
    }

    /** Frame-rate independent glow easing (fade-in/out over ~4 ticks). */
    private void advanceGlow(boolean hovered) {
        long now = System.currentTimeMillis();
        float elapsedTicks = lastFrameMillis == 0L ? 1.0F : Math.min(4.0F, (now - lastFrameMillis) / 50.0F);
        lastFrameMillis = now;
        float target = hovered ? 1.0F : 0.0F;
        float step = GLOW_STEP_PER_TICK * elapsedTicks;
        if (glow < target) {
            glow = Math.min(target, glow + step);
        } else if (glow > target) {
            glow = Math.max(target, glow - step);
        }
    }

    @Override
    protected void updateWidgetNarration(NarrationElementOutput narrationElementOutput) {
        defaultButtonNarrationText(narrationElementOutput);
    }
}
