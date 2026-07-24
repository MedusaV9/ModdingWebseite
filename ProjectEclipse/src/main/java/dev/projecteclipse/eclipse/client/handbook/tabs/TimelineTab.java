package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.timeline.TimelineEntry;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.FormattedText;
import net.minecraft.network.chat.Style;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Timeline page, Quiet Eclipse v3 (plans_v3 P3 §3.1): a horizontal drag-scrollable spine
 * of {@code ClientStateCache.timeline} nodes, now drawn flat — {@value #NODE_SIZE}px
 * squares from pure fills (reached = accent fill, current = accent fill + softly pulsing
 * ring, hidden/future = raised fill + hairline border) instead of the v2 32px textures.
 * Day entries come first, then a hairline divider + DIM label for the altar-milestone
 * section (replacing the v2 divider art). Reached entries show their 12px icon on the
 * side of the spine opposite their caption; hidden entries stay {@link GlitchText} "???".
 *
 * <p>B5 fixed twice: {@link #onShown()} centers on the newest REACHED node including the
 * {@value #SECTION_GAP}px section gap when that node sits in the milestone section, and
 * {@link #maxScroll()} only adds the gap when milestone entries actually exist (no dead
 * scroll zone). B20 fixed: presses are only consumed while there is something to scroll,
 * so clicks over a non-scrolling page fall through instead of being swallowed.</p>
 *
 * <p>Kept from v2 (it works): drag with inertia (velocity decays 15%/tick), the reserved
 * bottom hint band whose hint fades out for the session after the first successful
 * drag/scroll, and the two-line caption clamp.</p>
 */
@OnlyIn(Dist.CLIENT)
public class TimelineTab extends HandbookTab {
    /** Flat node edge length (§3.1 "flat 10px nodes"). */
    private static final int NODE_SIZE = 10;
    private static final int NODE_SPACING = 58;
    /** Extra gap (with the hairline divider) between the day and the milestone section. */
    private static final int SECTION_GAP = 64;
    /** Bottom band reserved for the drag hint; node/caption rendering is scissored above it. */
    private static final int HINT_BAND_HEIGHT = 14;
    /** Hint fade-out speed once dismissed (~12 ticks to fully gone). */
    private static final float HINT_FADE_PER_TICK = 0.08F;

    /** The drag hint has served its purpose for this game session (survives reopening). */
    private static boolean hintDismissed;
    /** Remaining hint strength while fading after dismissal, 1..0. */
    private static float hintAlpha = 1.0F;

    private float scrollX;
    private float velocity;
    private boolean dragging;

    @Override
    public String id() {
        return "timeline";
    }

    @Override
    public void onShown() {
        velocity = 0.0F;
        dragging = false;
        // Start the view on the newest reached node — day OR milestone (B5: include the
        // section gap when that node lives past the divider).
        List<TimelineEntry> timeline = ClientStateCache.timeline;
        int currentIndex = 0;
        for (int i = 0; i < timeline.size(); i++) {
            if (timeline.get(i).reached()) {
                currentIndex = i;
            }
        }
        int firstMilestone = firstMilestoneIndex(timeline);
        int gap = firstMilestone >= 0 && currentIndex >= firstMilestone ? SECTION_GAP : 0;
        scrollX = Mth.clamp(30 + currentIndex * NODE_SPACING + gap - width / 2.0F, 0.0F, maxScroll());
    }

    @Override
    public void tick() {
        if (!dragging && Math.abs(velocity) > 0.05F) {
            scrollX = Mth.clamp(scrollX + velocity, 0.0F, maxScroll());
            velocity *= 0.85F;
        }
        if (hintDismissed && hintAlpha > 0.0F) {
            hintAlpha = Math.max(0.0F, hintAlpha - HINT_FADE_PER_TICK);
        }
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        List<TimelineEntry> timeline = ClientStateCache.timeline;
        int spineY = y + height / 2;

        // The scissor stops above the reserved hint band: captions can never overlap it.
        guiGraphics.enableScissor(x, y, x + width, y + height - HINT_BAND_HEIGHT);
        guiGraphics.fill(x, spineY - 1, x + width, spineY + 1,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));

        if (timeline.isEmpty()) {
            guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.handbook.timeline.empty"),
                    x + width / 2, spineY - 20, withAlpha(DIM_COLOR, alpha));
        }

        int lastReachedDayIndex = -1;
        int lastReachedMilestoneIndex = -1;
        for (int i = 0; i < timeline.size(); i++) {
            TimelineEntry entry = timeline.get(i);
            if (entry.reached()) {
                if (entry.unlockDay() > 0) {
                    lastReachedDayIndex = i;
                } else {
                    lastReachedMilestoneIndex = i;
                }
            }
        }

        boolean milestoneSectionSeen = false;
        for (int i = 0; i < timeline.size(); i++) {
            TimelineEntry entry = timeline.get(i);
            boolean milestone = entry.unlockDay() <= 0;
            if (milestone && !milestoneSectionSeen) {
                milestoneSectionSeen = true;
                renderSectionDivider(guiGraphics, i, alpha);
            }
            int nodeCenterX = nodeCenterX(i, milestoneSectionSeen);
            if (nodeCenterX < x - NODE_SPACING || nodeCenterX > x + width + NODE_SPACING) {
                continue;
            }
            boolean current = i == lastReachedDayIndex || i == lastReachedMilestoneIndex;
            renderNode(guiGraphics, entry, i, nodeCenterX, spineY, current, alpha);
        }
        guiGraphics.disableScissor();

        renderDragHint(guiGraphics, timeline, alpha);
    }

    /**
     * Drag hint in the reserved bottom band: only while there is actually something to
     * scroll, and fading out for the rest of the session after the first successful
     * drag/scroll ({@code reducedFx} skips the fade and hides it immediately).
     */
    private void renderDragHint(GuiGraphics guiGraphics, List<TimelineEntry> timeline, float alpha) {
        if (timeline.isEmpty() || maxScroll() <= 0.0F) {
            return;
        }
        float strength = hintDismissed ? (EclipseClientConfig.reducedFx() ? 0.0F : hintAlpha) : 1.0F;
        if (strength <= 0.05F) {
            return;
        }
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.handbook.timeline.hint"),
                x + width / 2, y + height - 10, withAlpha(DIM_COLOR, alpha * strength));
    }

    /**
     * Milestone-section divider, v3: a vertical hairline through the page with the section
     * label at the top of the content area (clear of both caption rows) — no divider art.
     */
    private void renderSectionDivider(GuiGraphics guiGraphics, int index, float alpha) {
        int dividerCenter = nodeCenterX(index, true) - SECTION_GAP / 2 - NODE_SPACING / 2;
        guiGraphics.fill(dividerCenter, y + 12, dividerCenter + 1, y + height - HINT_BAND_HEIGHT - 2,
                EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));
        String label = ellipsize(font,
                EclipseLang.trString("gui.eclipse.handbook.timeline.milestones"), SECTION_GAP + 80);
        guiGraphics.drawCenteredString(font, label, dividerCenter, y + 2, withAlpha(DIM_COLOR, alpha));
    }

    /**
     * One flat node: reached = accent fill; current additionally breathes a 1px ring
     * (static under {@code reducedFx}); hidden/future = raised fill + hairline border.
     * The entry icon (12px, 1:1) sits on the opposite side of the spine from the caption.
     */
    private void renderNode(GuiGraphics guiGraphics, TimelineEntry entry, int index, int centerX, int spineY,
            boolean current, float alpha) {
        int half = NODE_SIZE / 2;
        int x0 = centerX - half;
        int y0 = spineY - half;
        if (entry.hidden() || !entry.reached()) {
            guiGraphics.fill(x0, y0, x0 + NODE_SIZE, y0 + NODE_SIZE,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
            drawFrame(guiGraphics, x0, y0, NODE_SIZE,
                    EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha));
        } else {
            guiGraphics.fill(x0, y0, x0 + NODE_SIZE, y0 + NODE_SIZE, withAlpha(ACCENT_COLOR, alpha));
        }
        if (current) {
            float ringAlpha = EclipseClientConfig.reducedFx() ? 0.8F
                    : 0.55F + 0.35F * Mth.sin(net.minecraft.Util.getMillis() / 320.0F);
            drawFrame(guiGraphics, x0 - 3, y0 - 3, NODE_SIZE + 6, withAlpha(ACCENT_COLOR, alpha * ringAlpha));
        }

        // Captions alternate above/below the spine so neighbors don't overlap.
        boolean captionBelow = index % 2 == 0;
        if (!entry.hidden() && !entry.icon().equals(TimelineEntry.NO_ICON)) {
            int iconY = captionBelow ? y0 - 6 - 12 : y0 + NODE_SIZE + 6;
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
            guiGraphics.blit(entry.icon(), centerX - 6, iconY, 0, 0, 12, 12, 12, 12);
            guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        }

        if (entry.hidden()) {
            String glitch = GlitchText.unknown(entry.id());
            int textY = captionBelow ? spineY + half + 6 : spineY - half - 14;
            guiGraphics.drawCenteredString(font, glitch, centerX, textY, withAlpha(DIM_COLOR, alpha));
            return;
        }
        List<String> caption = clampCaption(EclipseLang.trString(entry.titleKey()), NODE_SPACING + 24);
        int textY = captionBelow ? spineY + half + 6 : spineY - half - 6 - caption.size() * 9;
        for (String line : caption) {
            guiGraphics.drawCenteredString(font, line, centerX, textY,
                    withAlpha(current ? ACCENT_COLOR : TEXT_COLOR, alpha));
            textY += 9;
        }
    }

    /** 1px square frame outline from fills. */
    private static void drawFrame(GuiGraphics guiGraphics, int x0, int y0, int size, int color) {
        guiGraphics.fill(x0, y0, x0 + size, y0 + 1, color);
        guiGraphics.fill(x0, y0 + size - 1, x0 + size, y0 + size, color);
        guiGraphics.fill(x0, y0 + 1, x0 + 1, y0 + size - 1, color);
        guiGraphics.fill(x0 + size - 1, y0 + 1, x0 + size, y0 + size - 1, color);
    }

    /**
     * Word-wraps a node caption onto at most two lines; when the remainder after line one
     * still overflows, it is {@link #ellipsize}d so a marathon title can't stack a third
     * line into a neighboring caption (or the hint band).
     */
    private List<String> clampCaption(String text, int maxWidth) {
        if (font.width(text) <= maxWidth) {
            return List.of(text);
        }
        List<FormattedText> split = font.getSplitter().splitLines(text, maxWidth, Style.EMPTY);
        if (split.isEmpty()) {
            // Whitespace-ish captions can overflow yet split to nothing — never index [0].
            return List.of(ellipsize(font, text, maxWidth));
        }
        String first = split.get(0).getString();
        String remainder = text.substring(Math.min(first.length(), text.length())).strip();
        if (remainder.isEmpty()) {
            return List.of(first);
        }
        return List.of(first, ellipsize(font, remainder, maxWidth));
    }

    private int nodeCenterX(int index, boolean afterSectionGap) {
        return x + 30 + index * NODE_SPACING + (afterSectionGap ? SECTION_GAP : 0) - Math.round(scrollX);
    }

    /** First index of the milestone section ({@code unlockDay <= 0}), or -1 when absent. */
    private static int firstMilestoneIndex(List<TimelineEntry> timeline) {
        for (int i = 0; i < timeline.size(); i++) {
            if (timeline.get(i).unlockDay() <= 0) {
                return i;
            }
        }
        return -1;
    }

    /** B5: the section gap only counts toward the scroll range when milestones exist. */
    private float maxScroll() {
        List<TimelineEntry> timeline = ClientStateCache.timeline;
        int gap = firstMilestoneIndex(timeline) >= 0 ? SECTION_GAP : 0;
        return Math.max(0, timeline.size() * NODE_SPACING + gap + 60 - width);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        // B20: only consume presses the page actually uses — no scroll range, no grab.
        if (button == 0 && inRect(mouseX, mouseY) && maxScroll() > 0.0F) {
            dragging = true;
            velocity = 0.0F;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (dragging && button == 0) {
            scrollX = Mth.clamp(scrollX - (float) dragX, 0.0F, maxScroll());
            // Smooth the release velocity over recent drag deltas.
            velocity = velocity * 0.5F - (float) dragX * 0.5F;
            if (dragX != 0.0D) {
                hintDismissed = true; // the hint has taught its lesson for this session
            }
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (dragging && button == 0) {
            dragging = false;
            if (EclipseClientConfig.reducedFx()) {
                velocity = 0.0F;
            }
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0F) {
            scrollX = Mth.clamp(scrollX - (float) (scrollYDelta + scrollXDelta) * 24.0F, 0.0F, maxScroll());
            velocity = 0.0F;
            if (scrollXDelta != 0.0D || scrollYDelta != 0.0D) {
                hintDismissed = true;
            }
            return true;
        }
        return false;
    }

    @Override
    public boolean dragging() {
        return dragging;
    }
}
