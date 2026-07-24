package dev.projecteclipse.eclipse.bootstrap;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.bootstrap.PackBootstrap.Reason;
import dev.projecteclipse.eclipse.bootstrap.PackBootstrap.Report;
import dev.projecteclipse.eclipse.bootstrap.PackBootstrap.Violation;
import net.minecraft.Util;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;

/**
 * Quiet-Eclipse-style pack warning, rebuilt for readability (plans_v5 D7): dark panel with a
 * purple edge, violations grouped by reason (missing / wrong version / unknown / blocked) with
 * per-row status glyphs and a two-column id | version layout, pixel-smooth scrolling with a
 * draggable scrollbar, a clear download hint (clickable when the manifest hint is a URL) and a
 * copy-report button.
 *
 * <p>Blur fix: on 1.21.1 the vanilla no-level background path composites the menu-blur pass over
 * anything the screen painted, which made this screen unreadable. {@link #renderBackground} now
 * paints the gradient + panel itself and {@link #renderBlurredBackground} is a deliberate no-op,
 * so nothing vanilla blurs over the panel.</p>
 */
public final class BootstrapScreen extends Screen {
    private static final int PANEL_WIDTH = 430;
    private static final int ROW_HEIGHT = 12;
    private static final int HEADER_HEIGHT = 16;
    private static final int SCROLLBAR_WIDTH = 3;
    private static final int ACCENT = 0xFFB98CFF;
    private static final int MUTED = 0xFFAAA2B8;
    private static final int ERROR = 0xFFFF7B8B;
    private static final int AMBER = 0xFFFFC66D;
    private static final int UNKNOWN_BLUE = 0xFFBFD9FF;
    private static final int DETAIL = 0xFFE8E2F2;

    /** One rendered list line: a reason-group header or an id | detail violation row. */
    private record Row(Component text, Component detail, int color, boolean header) {}

    private final Screen parent;
    private final Report report;
    private final List<Row> rows = new ArrayList<>();

    private int panelX;
    private int panelWidth;
    private int panelTop;
    private int panelBottom;
    private int listTop;
    private int listBottom;
    private double scroll;
    private boolean scrollbarDragging;
    private double scrollbarGrabOffset;
    private Button copyButton;

    public BootstrapScreen(Screen parent, Report report) {
        super(Component.translatable("bootstrap.eclipse.title"));
        this.parent = parent;
        this.report = report;
    }

    @Override
    protected void init() {
        panelWidth = Math.min(PANEL_WIDTH, this.width - 24);
        panelX = (this.width - panelWidth) / 2;
        panelTop = Math.max(14, this.height / 2 - 152);
        panelBottom = Math.min(this.height - 10, this.height / 2 + 152);
        listTop = panelTop + 46;
        listBottom = Math.max(listTop + 24, panelBottom - 86);
        buildRows();

        int inner = panelWidth - 24;
        int half = (inner - 8) / 2;
        int utilY = listBottom + 27;
        copyButton = Button.builder(Component.translatable("bootstrap.eclipse.copy_report"),
                        button -> copyReport())
                .bounds(panelX + 12, utilY, hasDownloadLink() ? half : inner, 18)
                .build();
        addRenderableWidget(copyButton);
        if (hasDownloadLink()) {
            addRenderableWidget(Button.builder(Component.translatable("bootstrap.eclipse.open_download"),
                            button -> Util.getPlatform().openUri(report.downloadHintUrl()))
                    .bounds(panelX + 12 + half + 8, utilY, half, 18)
                    .build());
        }

        int buttonY = panelBottom - 26;
        int mainWidth = report.allowContinue() ? half : inner;
        addRenderableWidget(Button.builder(Component.translatable("bootstrap.eclipse.quit"),
                        button -> this.minecraft.stop())
                .bounds(panelX + 12, buttonY, mainWidth, 20)
                .build());
        if (report.allowContinue()) {
            addRenderableWidget(Button.builder(Component.translatable("bootstrap.eclipse.continue"),
                            button -> this.minecraft.setScreen(parent))
                    .bounds(panelX + 12 + mainWidth + 8, buttonY, mainWidth, 20)
                    .build());
        }
    }

    /** Paints gradient + panel + list; deliberately never calls the vanilla blur/menu path. */
    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fillGradient(0, 0, this.width, this.height, 0xFF090711, 0xFF151020);
        guiGraphics.fill(panelX - 2, panelTop - 2, panelX + panelWidth + 2, panelBottom + 2, ACCENT);
        guiGraphics.fill(panelX, panelTop, panelX + panelWidth, panelBottom, 0xF215111F);

        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, panelTop + 10, ACCENT);
        guiGraphics.drawCenteredString(this.font,
                Component.translatable("bootstrap.eclipse.summary", report.violations().size()),
                this.width / 2, panelTop + 23, 0xFFFFFFFF);
        if (report.devBypass()) {
            guiGraphics.drawCenteredString(this.font,
                    Component.translatable("bootstrap.eclipse.bypass"),
                    this.width / 2, panelTop + 34, ACCENT);
        }

        renderList(guiGraphics);
        renderScrollbar(guiGraphics);
        renderHints(guiGraphics);
    }

    /** Blur-fix half of D7: the vanilla menu-blur pass must never composite over the panel. */
    @Override
    protected void renderBlurredBackground(float partialTick) {
        // no-op by design
    }

    private void renderList(GuiGraphics guiGraphics) {
        scroll = Mth.clamp(scroll, 0.0D, maxScroll());
        guiGraphics.enableScissor(panelX + 8, listTop, panelX + panelWidth - 14, listBottom);
        int y = listTop - (int) Math.round(scroll);
        for (Row row : rows) {
            int rowHeight = row.header() ? HEADER_HEIGHT : ROW_HEIGHT;
            if (y + rowHeight >= listTop && y <= listBottom) {
                if (row.header()) {
                    guiGraphics.drawString(this.font, row.text(), panelX + 12, y + 4, ACCENT, true);
                    guiGraphics.fill(panelX + 12, y + HEADER_HEIGHT - 2,
                            panelX + panelWidth - 16, y + HEADER_HEIGHT - 1, 0x55B98CFF);
                } else {
                    guiGraphics.drawString(this.font, row.text(), panelX + 16, y + 2, row.color(), true);
                    guiGraphics.drawString(this.font, row.detail(), panelX + detailColumnX(), y + 2,
                            DETAIL, true);
                }
            }
            y += rowHeight;
            if (y > listBottom + ROW_HEIGHT) {
                break;
            }
        }
        guiGraphics.disableScissor();
        // Fade hint when there is more content below the fold.
        if (scroll < maxScroll()) {
            guiGraphics.fillGradient(panelX + 8, listBottom - 8, panelX + panelWidth - 14, listBottom,
                    0x0015111F, 0xC015111F);
        }
    }

    private void renderScrollbar(GuiGraphics guiGraphics) {
        if (maxScroll() <= 0) {
            return;
        }
        int trackX = scrollbarX();
        guiGraphics.fill(trackX, listTop, trackX + SCROLLBAR_WIDTH, listBottom, 0x33FFFFFF);
        int thumbHeight = thumbHeight();
        int thumbY = thumbY(thumbHeight);
        guiGraphics.fill(trackX, thumbY, trackX + SCROLLBAR_WIDTH, thumbY + thumbHeight,
                scrollbarDragging ? 0xFFFFFFFF : ACCENT);
    }

    private void renderHints(GuiGraphics guiGraphics) {
        int hintY = listBottom + 5;
        guiGraphics.drawCenteredString(this.font, Component.translatable("bootstrap.eclipse.download_hint"),
                this.width / 2, hintY, MUTED);
        if (!hasDownloadLink() && !report.downloadHintUrl().isBlank()) {
            guiGraphics.drawCenteredString(this.font, Component.literal(report.downloadHintUrl()),
                    this.width / 2, hintY + 11, ACCENT);
        }
        if (!report.allowContinue()) {
            guiGraphics.drawCenteredString(this.font,
                    Component.translatable("bootstrap.eclipse.continue_disabled"),
                    this.width / 2, panelBottom - 37, ERROR);
        }
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        if (maxScroll() > 0) {
            scroll = Mth.clamp(scroll - scrollY * 24.0D, 0.0D, maxScroll());
            return true;
        }
        return super.mouseScrolled(mouseX, mouseY, scrollX, scrollY);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0 && maxScroll() > 0) {
            int trackX = scrollbarX();
            if (mouseX >= trackX - 3 && mouseX <= trackX + SCROLLBAR_WIDTH + 3
                    && mouseY >= listTop && mouseY <= listBottom) {
                scrollbarDragging = true;
                int thumbHeight = thumbHeight();
                int thumbY = thumbY(thumbHeight);
                if (mouseY >= thumbY && mouseY < thumbY + thumbHeight) {
                    scrollbarGrabOffset = mouseY - thumbY;
                } else {
                    scrollbarGrabOffset = thumbHeight / 2.0D;
                    setScrollFromThumbTop(mouseY - scrollbarGrabOffset, thumbHeight);
                }
                return true;
            }
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (scrollbarDragging) {
            setScrollFromThumbTop(mouseY - scrollbarGrabOffset, thumbHeight());
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, dragX, dragY);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (scrollbarDragging) {
            scrollbarDragging = false;
            return true;
        }
        return super.mouseReleased(mouseX, mouseY, button);
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

    // ------------------------------------------------------------------ rows & report

    private void buildRows() {
        rows.clear();
        addGroup(Reason.MISSING, "bootstrap.eclipse.group.missing", ERROR);
        addGroup(Reason.VERSION, "bootstrap.eclipse.group.version", AMBER);
        addGroup(Reason.UNKNOWN, "bootstrap.eclipse.group.unknown", UNKNOWN_BLUE);
        addGroup(Reason.BLOCKED, "bootstrap.eclipse.group.blocked", ERROR);
    }

    private void addGroup(Reason reason, String headerKey, int color) {
        List<Violation> group = report.violations().stream()
                .filter(violation -> violation.reason() == reason)
                .toList();
        if (group.isEmpty()) {
            return;
        }
        rows.add(new Row(Component.translatable(headerKey, group.size()), Component.empty(), ACCENT, true));
        int idWidth = detailColumnX() - 20;
        for (Violation violation : group) {
            rows.add(new Row(clipped(statusGlyph(reason) + " " + violation.modId(), idWidth),
                    detailLine(violation), color, false));
        }
    }

    private static String statusGlyph(Reason reason) {
        return switch (reason) {
            case MISSING -> "✖";
            case VERSION -> "≠";
            case UNKNOWN -> "?";
            case BLOCKED -> "!";
        };
    }

    private static Component detailLine(Violation violation) {
        return switch (violation.reason()) {
            case MISSING -> Component.translatable("bootstrap.eclipse.row.missing",
                    violation.expectedVersion());
            case VERSION -> Component.translatable("bootstrap.eclipse.row.version",
                    violation.installedVersion(), violation.expectedVersion());
            case UNKNOWN -> Component.translatable("bootstrap.eclipse.row.unknown",
                    violation.installedVersion());
            case BLOCKED -> Component.translatable("bootstrap.eclipse.row.blocked",
                    violation.installedVersion());
        };
    }

    private Component clipped(String text, int maxWidth) {
        if (this.font.width(text) <= maxWidth) {
            return Component.literal(text);
        }
        String cut = this.font.plainSubstrByWidth(text, Math.max(0, maxWidth - this.font.width("…")));
        return Component.literal(cut + "…");
    }

    private void copyReport() {
        StringBuilder text = new StringBuilder("Eclipse pack check report\n");
        for (Violation violation : report.violations()) {
            text.append(violation.reason().name()).append(' ').append(violation.modId());
            if (!violation.installedVersion().isBlank()) {
                text.append(" installed=").append(violation.installedVersion());
            }
            if (!violation.expectedVersion().isBlank()) {
                text.append(" expected=").append(violation.expectedVersion());
            }
            text.append('\n');
        }
        text.append("\nLoaded mods (").append(report.loadedMods().size()).append("):\n");
        report.loadedMods().forEach((id, version) ->
                text.append("  ").append(id).append('@').append(version).append('\n'));
        this.minecraft.keyboardHandler.setClipboard(text.toString());
        if (copyButton != null) {
            copyButton.setMessage(Component.translatable("bootstrap.eclipse.copied"));
        }
    }

    // ------------------------------------------------------------------ geometry

    private boolean hasDownloadLink() {
        String url = report.downloadHintUrl();
        return url.startsWith("http://") || url.startsWith("https://");
    }

    private int detailColumnX() {
        return (int) (panelWidth * 0.44D);
    }

    private int scrollbarX() {
        return panelX + panelWidth - 12;
    }

    private int contentHeight() {
        int total = 0;
        for (Row row : rows) {
            total += row.header() ? HEADER_HEIGHT : ROW_HEIGHT;
        }
        return total;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - (listBottom - listTop));
    }

    private int thumbHeight() {
        int viewHeight = listBottom - listTop;
        int proportional = (int) ((long) viewHeight * viewHeight / Math.max(viewHeight, contentHeight()));
        return Mth.clamp(proportional, Math.min(12, viewHeight), viewHeight);
    }

    private int thumbY(int thumbHeight) {
        double max = maxScroll();
        double t = max <= 0.0D ? 0.0D : Mth.clamp(scroll / max, 0.0D, 1.0D);
        return listTop + (int) Math.round((listBottom - listTop - thumbHeight) * t);
    }

    private void setScrollFromThumbTop(double thumbTop, int thumbHeight) {
        int travel = listBottom - listTop - thumbHeight;
        if (travel <= 0) {
            return;
        }
        double t = Mth.clamp((thumbTop - listTop) / travel, 0.0D, 1.0D);
        scroll = t * maxScroll();
    }
}
