package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.timeline.TimelineEntry;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.Style;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Timeline page: a horizontal drag-scrollable spine of {@code ClientStateCache.timeline}
 * nodes (W8's anonymized {@link TimelineEntry} list). Reached entries show the lit node +
 * icon + caption (clamped to two lines, the last one ellipsized); the last reached entry of
 * each section pulses as "current"; hidden/future entries render the locked node with
 * {@link GlitchText} "???" captions. Day entries come first, then a divider, then
 * altar-milestone entries ({@code unlockDay == 0}). Drag to scroll with inertia (velocity
 * decays 15%/tick); the screen shows the grab cursor while {@link #dragging()}. The bottom
 * {@value #HINT_BAND_HEIGHT}px of the page is reserved for the drag hint — the node scissor
 * stops above it so captions can never overlap — and the hint only shows while there is
 * something to scroll, fading out for the session after the first successful drag/scroll
 * (instantly hidden under {@code reducedFx}).
 */
@OnlyIn(Dist.CLIENT)
public class TimelineTab extends HandbookTab {
    private static final ResourceLocation NODE_LOCKED = handbookTexture("timeline_node_locked");
    private static final ResourceLocation NODE_UNLOCKED = handbookTexture("timeline_node_unlocked");
    private static final ResourceLocation NODE_CURRENT = handbookTexture("timeline_node_current");
    private static final ResourceLocation DIVIDER = handbookTexture("divider");

    private static final int NODE_SIZE = 32;
    private static final int NODE_SPACING = 58;
    /** Extra gap (with the divider art) between the day section and the milestone section. */
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
        // Start the view on the current day node.
        List<TimelineEntry> timeline = ClientStateCache.timeline;
        int currentIndex = 0;
        for (int i = 0; i < timeline.size(); i++) {
            TimelineEntry entry = timeline.get(i);
            if (entry.unlockDay() > 0 && entry.reached()) {
                currentIndex = i;
            }
        }
        scrollX = Mth.clamp(currentIndex * NODE_SPACING - width / 2.0F + NODE_SPACING, 0.0F, maxScroll());
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
        guiGraphics.fill(x, spineY - 1, x + width, spineY + 1, withAlpha(0x4A3C66, alpha));

        if (timeline.isEmpty()) {
            guiGraphics.drawCenteredString(font, Component.translatable("gui.eclipse.handbook.timeline.empty"),
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
                renderSectionDivider(guiGraphics, i, spineY, alpha);
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
        guiGraphics.drawCenteredString(font, Component.translatable("gui.eclipse.handbook.timeline.hint"),
                x + width / 2, y + height - 10, withAlpha(DIM_COLOR, alpha * strength));
    }

    private void renderSectionDivider(GuiGraphics guiGraphics, int index, int spineY, float alpha) {
        int dividerCenter = nodeCenterX(index, true) - SECTION_GAP / 2 - NODE_SPACING / 2;
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(DIVIDER, dividerCenter - 24, spineY - 6, 0, 0, 48, 12, 48, 12);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        guiGraphics.drawCenteredString(font, Component.translatable("gui.eclipse.handbook.timeline.milestones"),
                dividerCenter, spineY + 10, withAlpha(DIM_COLOR, alpha));
    }

    private void renderNode(GuiGraphics guiGraphics, TimelineEntry entry, int index, int centerX, int spineY,
            boolean current, float alpha) {
        ResourceLocation node = entry.hidden() ? NODE_LOCKED : current ? NODE_CURRENT : NODE_UNLOCKED;

        float scale = 1.0F;
        if (current && !EclipseClientConfig.reducedFx()) {
            scale = 1.0F + 0.07F * Mth.sin(net.minecraft.Util.getMillis() / 160.0F);
        }
        guiGraphics.pose().pushPose();
        guiGraphics.pose().translate(centerX, spineY, 0);
        guiGraphics.pose().scale(scale, scale, 1.0F);
        guiGraphics.pose().translate(-centerX, -spineY, 0);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha);
        guiGraphics.blit(node, centerX - NODE_SIZE / 2, spineY - NODE_SIZE / 2, 0, 0,
                NODE_SIZE, NODE_SIZE, NODE_SIZE, NODE_SIZE);
        if (!entry.hidden() && !entry.icon().equals(TimelineEntry.NO_ICON)) {
            guiGraphics.blit(entry.icon(), centerX - 6, spineY - 6, 0, 0, 12, 12, 12, 12);
        }
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);
        guiGraphics.pose().popPose();

        // Captions alternate above/below the spine so neighbors don't overlap.
        boolean below = index % 2 == 0;
        if (entry.hidden()) {
            String glitch = GlitchText.unknown(entry.id());
            int textY = below ? spineY + NODE_SIZE / 2 + 4 : spineY - NODE_SIZE / 2 - 12;
            guiGraphics.drawCenteredString(font, glitch, centerX, textY, withAlpha(DIM_COLOR, alpha));
            return;
        }
        List<String> caption = clampCaption(Component.translatable(entry.titleKey()).getString(), NODE_SPACING + 24);
        int textY = below ? spineY + NODE_SIZE / 2 + 4 : spineY - NODE_SIZE / 2 - 4 - caption.size() * 9;
        for (String line : caption) {
            guiGraphics.drawCenteredString(font, line, centerX, textY,
                    withAlpha(current ? ACCENT_COLOR : TEXT_COLOR, alpha));
            textY += 9;
        }
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
        String first = font.getSplitter().splitLines(text, maxWidth, Style.EMPTY).get(0).getString();
        String remainder = text.substring(Math.min(first.length(), text.length())).strip();
        if (remainder.isEmpty()) {
            return List.of(first);
        }
        return List.of(first, ellipsize(font, remainder, maxWidth));
    }

    private int nodeCenterX(int index, boolean afterSectionGap) {
        return x + 30 + index * NODE_SPACING + (afterSectionGap ? SECTION_GAP : 0) - Math.round(scrollX);
    }

    private float maxScroll() {
        int count = ClientStateCache.timeline.size();
        return Math.max(0, count * NODE_SPACING + SECTION_GAP + 60 - width);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0 && inRect(mouseX, mouseY)) {
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
        if (inRect(mouseX, mouseY)) {
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
