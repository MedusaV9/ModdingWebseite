package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.function.DoubleConsumer;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The shared minimal scrollbar of the handbook tabs (plans_v3 P3 §3.1 / W2: "all scroll
 * containers get the shared scrollbar helper" — fixes the B7 affordance gap where Rewards
 * scrolled invisibly while Rules drew its own bar). A {@value #WIDTH}px track on the right
 * edge of a tab's content rect: {@link EclipseUiTheme#HAIRLINE} track, {@link
 * EclipseUiTheme#ACCENT} thumb, no arrows, no texture — pure fills per §2.1.
 *
 * <p>Not an {@code AbstractWidget}: tabs already own their scroll state (wheel + content
 * drag), so the bar is a stateless-drawing/stateful-dragging helper the tab consults from
 * its own mouse handlers. It only ever consumes input while {@link #scrollable()}, keeping
 * the B20 rule ("tabs must only consume clicks they use") intact. Pressing the track jumps
 * the thumb to the cursor and starts a drag in one motion; the press blips through
 * {@link UiSounds#click()} (§2.3 — every interactive element sounds through UiSounds).</p>
 *
 * <p>Usage per frame: {@link #layout} + {@link #size} (cheap, call from {@code render}),
 * then {@link #render}. From input handlers: {@link #mouseClicked}, {@link #mouseDragged},
 * {@link #mouseReleased}; include {@link #dragging()} in the tab's own {@code dragging()}
 * so the screen keeps the grab cursor while the thumb is held.</p>
 */
@OnlyIn(Dist.CLIENT)
final class TabScrollbar {
    /** Drawn track width; the click target is padded {@value #HIT_PAD}px to each side. */
    static final int WIDTH = 2;
    private static final int HIT_PAD = 3;
    private static final int MIN_THUMB = 12;

    private int trackX;
    private int trackY;
    private int trackHeight;
    private int viewSize = 1;
    private int contentSize;
    private boolean dragging;
    /** While dragging: cursor-y minus thumb-top, so the thumb never jumps under the hand. */
    private double grabOffset;

    /** Positions the track so its right edge sits at {@code rightEdgeX} (content right). */
    void layout(int rightEdgeX, int y, int height) {
        this.trackX = rightEdgeX - WIDTH;
        this.trackY = y;
        this.trackHeight = Math.max(1, height);
    }

    /** Updates the view/content extent the thumb proportions derive from. */
    void size(int viewSize, int contentSize) {
        this.viewSize = Math.max(1, viewSize);
        this.contentSize = Math.max(0, contentSize);
    }

    double maxScroll() {
        return Math.max(0, contentSize - viewSize);
    }

    /** Whether there is anything to scroll (bar hidden and input ignored otherwise). */
    boolean scrollable() {
        return maxScroll() > 0.0D;
    }

    boolean dragging() {
        return dragging;
    }

    void render(GuiGraphics guiGraphics, double scroll, float alpha) {
        if (!scrollable()) {
            return;
        }
        guiGraphics.fill(trackX, trackY, trackX + WIDTH, trackY + trackHeight,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));
        int thumb = thumbHeight();
        int thumbY = thumbY(scroll, thumb);
        guiGraphics.fill(trackX, thumbY, trackX + WIDTH, thumbY + thumb,
                EclipseUiTheme.withAlpha(dragging ? EclipseUiTheme.TEXT : EclipseUiTheme.ACCENT, alpha));
    }

    /**
     * Press handling: returns {@code true} (and starts a drag) when the press lands on the
     * padded track. A press outside the thumb first jumps the thumb center to the cursor.
     */
    boolean mouseClicked(double mouseX, double mouseY, double scroll, DoubleConsumer setScroll) {
        if (!scrollable() || mouseX < trackX - HIT_PAD || mouseX >= trackX + WIDTH + HIT_PAD
                || mouseY < trackY || mouseY >= trackY + trackHeight) {
            return false;
        }
        int thumb = thumbHeight();
        int thumbY = thumbY(scroll, thumb);
        dragging = true;
        if (mouseY >= thumbY && mouseY < thumbY + thumb) {
            grabOffset = mouseY - thumbY;
        } else {
            grabOffset = thumb / 2.0D;
            setScroll.accept(scrollForThumbTop(mouseY - grabOffset, thumb));
        }
        UiSounds.click();
        return true;
    }

    /** Drag handling: while dragging, maps the cursor back to a scroll value. */
    boolean mouseDragged(double mouseY, DoubleConsumer setScroll) {
        if (!dragging) {
            return false;
        }
        setScroll.accept(scrollForThumbTop(mouseY - grabOffset, thumbHeight()));
        return true;
    }

    boolean mouseReleased() {
        if (!dragging) {
            return false;
        }
        dragging = false;
        return true;
    }

    private int thumbHeight() {
        int proportional = (int) ((long) trackHeight * viewSize / Math.max(viewSize, contentSize));
        return Mth.clamp(proportional, Math.min(MIN_THUMB, trackHeight), trackHeight);
    }

    private int thumbY(double scroll, int thumb) {
        double max = maxScroll();
        double t = max <= 0.0D ? 0.0D : Mth.clamp(scroll / max, 0.0D, 1.0D);
        return trackY + (int) Math.round((trackHeight - thumb) * t);
    }

    private double scrollForThumbTop(double thumbTop, int thumb) {
        int travel = trackHeight - thumb;
        if (travel <= 0) {
            return 0.0D;
        }
        double t = Mth.clamp((thumbTop - trackY) / travel, 0.0D, 1.0D);
        return t * maxScroll();
    }
}
