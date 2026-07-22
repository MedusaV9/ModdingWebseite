package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.core.config.EclipseClientConfig;
import dev.projecteclipse.eclipse.timeline.TimelineEntry;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Timeline page: a horizontal drag-scrollable spine of {@code ClientStateCache.timeline}
 * nodes (W8's anonymized {@link TimelineEntry} list). Reached entries show the lit node +
 * icon + caption; the last reached entry of each section pulses as "current"; hidden/future
 * entries render the locked node with {@link GlitchText} "???" captions. Day entries come
 * first, then a divider, then altar-milestone entries ({@code unlockDay == 0}). Drag to
 * scroll with inertia (velocity decays 15%/tick); the screen shows the grab cursor while
 * {@link #dragging()}.
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
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        List<TimelineEntry> timeline = ClientStateCache.timeline;
        int spineY = y + height / 2;

        guiGraphics.enableScissor(x, y, x + width, y + height);
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

        guiGraphics.drawCenteredString(font, Component.translatable("gui.eclipse.handbook.timeline.hint"),
                x + width / 2, y + height - 10, withAlpha(DIM_COLOR, alpha));
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
        List<FormattedCharSequence> caption = font.split(Component.translatable(entry.titleKey()), NODE_SPACING + 24);
        int textY = below ? spineY + NODE_SIZE / 2 + 4 : spineY - NODE_SIZE / 2 - 4 - caption.size() * 9;
        for (FormattedCharSequence line : caption) {
            guiGraphics.drawCenteredString(font, line, centerX, textY,
                    withAlpha(current ? ACCENT_COLOR : TEXT_COLOR, alpha));
            textY += 9;
        }
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
            return true;
        }
        return false;
    }

    @Override
    public boolean dragging() {
        return dragging;
    }
}
