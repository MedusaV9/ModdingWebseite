package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Rules page, Quiet Eclipse v3 (plans_v3 P3 §3.1): the ten event rules (lang keys
 * {@code gui.eclipse.artifact.rules.line1..10}, kept verbatim so translations survive) as
 * a flat scrolling text column directly on the panel — the v2 parchment texture is gone
 * (nothing stretches, §2). Mouse wheel, vertical content drag or the shared
 * {@link TabScrollbar} scroll; the screen shows the grab cursor while {@link #dragging()}.
 * Presses are only consumed while there is actually something to scroll (B20 rule).
 */
@OnlyIn(Dist.CLIENT)
public class RulesTab extends HandbookTab {
    private static final int RULE_LINE_COUNT = 10;
    private static final int LINE_HEIGHT = 11;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    private final List<FormattedCharSequence> lines = new ArrayList<>();
    private final TabScrollbar scrollbar = new TabScrollbar();
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
            lines.addAll(font.split(EclipseLang.tr("gui.eclipse.artifact.rules.line" + i),
                    width - SCROLLBAR_INSET));
            lines.add(FormattedCharSequence.EMPTY);
        }
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
    }

    @Override
    public void onShown() {
        dragging = false;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        guiGraphics.enableScissor(x, y, x + width, y + height);
        int lineY = y + 2 - (int) scrollAmount;
        for (FormattedCharSequence line : lines) {
            if (lineY > y - LINE_HEIGHT && lineY < y + height) {
                guiGraphics.drawString(font, line, x, lineY, withAlpha(TEXT_COLOR, alpha));
            }
            lineY += LINE_HEIGHT;
        }
        guiGraphics.disableScissor();

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseClicked(mouseX, mouseY, scrollAmount, value -> scrollAmount = value)) {
            return true;
        }
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            dragging = true;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseDragged(mouseY, value -> scrollAmount = value)) {
            return true;
        }
        if (dragging) {
            scrollAmount = Mth.clamp(scrollAmount - dragY, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseReleased()) {
            return true;
        }
        if (dragging) {
            dragging = false;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * LINE_HEIGHT * 2, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    private int contentHeight() {
        return lines.size() * LINE_HEIGHT + 4;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
