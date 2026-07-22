package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.List;

import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Rules page: the v1 {@code client.RulesScreen} content (lang keys
 * {@code gui.eclipse.artifact.rules.line1..10}, kept verbatim so translations survive)
 * absorbed as a scrollable parchment panel. The standalone {@code RulesScreen} class was
 * deleted — its only opener was the v1 artifact popup this handbook replaced. Mouse wheel
 * or vertical drag scrolls; a slim scrollbar marks the position.
 */
@OnlyIn(Dist.CLIENT)
public class RulesTab extends HandbookTab {
    private static final ResourceLocation PARCHMENT = handbookTexture("parchment_tile");
    private static final int RULE_LINE_COUNT = 10;
    private static final int LINE_HEIGHT = 11;
    private static final int PADDING = 8;

    private final List<FormattedCharSequence> lines = new ArrayList<>();
    private double scrollAmount;
    private boolean dragging;

    @Override
    public String id() {
        return "rules";
    }

    @Override
    protected void onInit() {
        lines.clear();
        for (int i = 1; i <= RULE_LINE_COUNT; i++) {
            lines.addAll(font.split(Component.translatable("gui.eclipse.artifact.rules.line" + i),
                    width - 2 * PADDING - 8));
            lines.add(FormattedCharSequence.EMPTY);
        }
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        // Parchment panel behind the text (full texture squeezed into the rect).
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, alpha * 0.85F);
        guiGraphics.blit(PARCHMENT, x, y, 0, 0, width, height, width, height);
        guiGraphics.setColor(1.0F, 1.0F, 1.0F, 1.0F);

        guiGraphics.enableScissor(x, y, x + width, y + height);
        int lineY = y + PADDING - (int) scrollAmount;
        for (FormattedCharSequence line : lines) {
            if (lineY > y - LINE_HEIGHT && lineY < y + height) {
                guiGraphics.drawString(font, line, x + PADDING, lineY, withAlpha(TEXT_COLOR, alpha));
            }
            lineY += LINE_HEIGHT;
        }
        guiGraphics.disableScissor();

        // Slim scrollbar on the right edge.
        double max = maxScroll();
        if (max > 0.0D) {
            int track = height - 8;
            int thumb = Math.max(12, (int) (track * (height / (double) (contentHeight()))));
            int thumbY = y + 4 + (int) ((track - thumb) * (scrollAmount / max));
            guiGraphics.fill(x + width - 3, y + 4, x + width - 1, y + 4 + track, withAlpha(0x3A2F52, alpha));
            guiGraphics.fill(x + width - 3, thumbY, x + width - 1, thumbY + thumb, withAlpha(ACCENT_COLOR, alpha));
        }
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0 && inRect(mouseX, mouseY)) {
            dragging = true;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (dragging && button == 0) {
            scrollAmount = Mth.clamp(scrollAmount - dragY, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (dragging && button == 0) {
            dragging = false;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY)) {
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * LINE_HEIGHT * 2, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    private int contentHeight() {
        return lines.size() * LINE_HEIGHT + 2 * PADDING;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - height);
    }
}
