package dev.projecteclipse.eclipse.client;

import java.util.ArrayList;
import java.util.List;

import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Scrollable multiline rules page, opened from {@link ArtifactScreen}. The rule text lives
 * in the lang files ({@code gui.eclipse.artifact.rules.line1..N}, de + en); mouse wheel
 * scrolls, the back button returns to the artifact screen.
 */
@OnlyIn(Dist.CLIENT)
public class RulesScreen extends Screen {
    private static final int RULE_LINE_COUNT = 10;
    private static final int TEXT_WIDTH = 260;
    private static final int LINE_HEIGHT = 11;
    private static final int TEXT_COLOR = 0xFFE8E0F5;

    private final Screen parent;
    private final List<FormattedCharSequence> lines = new ArrayList<>();
    private double scrollAmount;
    private int viewTop;
    private int viewBottom;

    public RulesScreen(Screen parent) {
        super(Component.translatable("gui.eclipse.artifact.rules.title"));
        this.parent = parent;
    }

    @Override
    protected void init() {
        this.viewTop = 40;
        this.viewBottom = this.height - 40;
        this.lines.clear();
        for (int i = 1; i <= RULE_LINE_COUNT; i++) {
            this.lines.addAll(this.font.split(Component.translatable("gui.eclipse.artifact.rules.line" + i), TEXT_WIDTH));
            this.lines.add(FormattedCharSequence.EMPTY); // blank line between rules
        }
        addRenderableWidget(Button.builder(CommonComponents.GUI_BACK, button -> onClose())
                .bounds(this.width / 2 - 40, this.height - 30, 80, 20)
                .build());
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, 16, 0xFFB98CFF);

        int textX = (this.width - TEXT_WIDTH) / 2;
        guiGraphics.enableScissor(0, this.viewTop, this.width, this.viewBottom);
        int y = this.viewTop + 4 - (int) this.scrollAmount;
        for (FormattedCharSequence line : this.lines) {
            if (y > this.viewTop - LINE_HEIGHT && y < this.viewBottom) {
                guiGraphics.drawString(this.font, line, textX, y, TEXT_COLOR);
            }
            y += LINE_HEIGHT;
        }
        guiGraphics.disableScissor();
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (super.mouseScrolled(mouseX, mouseY, scrollX, scrollY)) {
            return true;
        }
        this.scrollAmount = Mth.clamp(this.scrollAmount - scrollY * LINE_HEIGHT * 2, 0.0D, maxScroll());
        return true;
    }

    private double maxScroll() {
        int contentHeight = this.lines.size() * LINE_HEIGHT + 8;
        return Math.max(0, contentHeight - (this.viewBottom - this.viewTop));
    }

    @Override
    public void onClose() {
        this.minecraft.setScreen(this.parent);
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }
}
