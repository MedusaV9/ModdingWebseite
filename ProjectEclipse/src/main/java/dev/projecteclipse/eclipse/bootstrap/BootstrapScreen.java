package dev.projecteclipse.eclipse.bootstrap;

import dev.projecteclipse.eclipse.bootstrap.PackBootstrap.Report;
import dev.projecteclipse.eclipse.bootstrap.PackBootstrap.Violation;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;

/**
 * Minimal Quiet-Eclipse-style pack warning: dark panel, purple edge, itemized offenders and
 * an explicit acknowledgement button only when the baked manifest permits continuing.
 */
public final class BootstrapScreen extends Screen {
    private static final int PANEL_WIDTH = 390;
    private static final int ROW_HEIGHT = 16;
    private static final int VISIBLE_ROWS = 8;
    private static final int ACCENT = 0xFFB98CFF;
    private static final int MUTED = 0xFFAAA2B8;
    private static final int ERROR = 0xFFFF7B8B;

    private final Screen parent;
    private final Report report;
    private int scrollRow;

    public BootstrapScreen(Screen parent, Report report) {
        super(Component.translatable("bootstrap.eclipse.title"));
        this.parent = parent;
        this.report = report;
    }

    @Override
    protected void init() {
        int panelX = (this.width - Math.min(PANEL_WIDTH, this.width - 24)) / 2;
        int panelWidth = Math.min(PANEL_WIDTH, this.width - 24);
        int buttonY = Math.min(this.height - 36, this.height / 2 + 104);
        int buttonWidth = report.allowContinue() ? (panelWidth - 12) / 2 : panelWidth;

        addRenderableWidget(Button.builder(Component.translatable("bootstrap.eclipse.quit"),
                        button -> this.minecraft.stop())
                .bounds(panelX, buttonY, buttonWidth, 20)
                .build());
        if (report.allowContinue()) {
            addRenderableWidget(Button.builder(Component.translatable("bootstrap.eclipse.continue"),
                            button -> this.minecraft.setScreen(parent))
                    .bounds(panelX + buttonWidth + 12, buttonY, buttonWidth, 20)
                    .build());
        }
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fillGradient(0, 0, this.width, this.height, 0xFF090711, 0xFF151020);
        int panelWidth = Math.min(PANEL_WIDTH, this.width - 24);
        int panelX = (this.width - panelWidth) / 2;
        int panelTop = Math.max(18, this.height / 2 - 136);
        int panelBottom = Math.min(this.height - 12, this.height / 2 + 136);
        guiGraphics.fill(panelX - 2, panelTop - 2, panelX + panelWidth + 2, panelBottom + 2, ACCENT);
        guiGraphics.fill(panelX, panelTop, panelX + panelWidth, panelBottom, 0xEE17131F);

        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, panelTop + 14, ACCENT);
        guiGraphics.drawCenteredString(this.font,
                Component.translatable("bootstrap.eclipse.summary", report.violations().size()),
                this.width / 2, panelTop + 33, 0xFFFFFFFF);

        int listTop = panelTop + 55;
        int listBottom = listTop + VISIBLE_ROWS * ROW_HEIGHT;
        guiGraphics.enableScissor(panelX + 10, listTop - 2, panelX + panelWidth - 10, listBottom);
        int end = Math.min(report.violations().size(), scrollRow + VISIBLE_ROWS);
        for (int index = scrollRow; index < end; index++) {
            Violation violation = report.violations().get(index);
            Component line = violationLine(violation);
            guiGraphics.drawString(this.font, line, panelX + 14,
                    listTop + (index - scrollRow) * ROW_HEIGHT, ERROR, false);
        }
        guiGraphics.disableScissor();

        if (report.violations().size() > VISIBLE_ROWS) {
            guiGraphics.drawString(this.font,
                    Component.translatable("bootstrap.eclipse.scroll", scrollRow + 1, end,
                            report.violations().size()),
                    panelX + 14, listBottom + 3, MUTED, false);
        }

        int hintY = listBottom + 19;
        guiGraphics.drawCenteredString(this.font, Component.translatable("bootstrap.eclipse.hint"),
                this.width / 2, hintY, MUTED);
        if (!report.downloadHintUrl().isBlank()) {
            guiGraphics.drawCenteredString(this.font, report.downloadHintUrl(),
                    this.width / 2, hintY + 13, ACCENT);
        }
        if (!report.allowContinue()) {
            guiGraphics.drawCenteredString(this.font,
                    Component.translatable("bootstrap.eclipse.continue_disabled"),
                    this.width / 2, hintY + 27, ERROR);
        }

        super.render(guiGraphics, mouseX, mouseY, partialTick);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (report.violations().size() <= VISIBLE_ROWS) {
            return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
        }
        int max = report.violations().size() - VISIBLE_ROWS;
        scrollRow = Mth.clamp(scrollRow - (int) Math.signum(scrollY), 0, max);
        return true;
    }

    @Override
    public void onClose() {
        if (report.allowContinue()) {
            this.minecraft.setScreen(parent);
        }
    }

    @Override
    public boolean shouldCloseOnEsc() {
        return report.allowContinue();
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    private static Component violationLine(Violation violation) {
        return switch (violation.reason()) {
            case UNKNOWN -> Component.translatable("bootstrap.eclipse.reason.unknown",
                    violation.modId(), violation.installedVersion());
            case MISSING -> Component.translatable("bootstrap.eclipse.reason.missing",
                    violation.modId(), violation.expectedVersion());
            case VERSION -> Component.translatable("bootstrap.eclipse.reason.version",
                    violation.modId(), violation.installedVersion(), violation.expectedVersion());
            case BLOCKED -> Component.translatable("bootstrap.eclipse.reason.blocked",
                    violation.modId(), violation.installedVersion());
        };
    }
}
