package dev.projecteclipse.eclipse.client.menu;

import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/** Quiet-Eclipse scrolling credits, backed by {@code assets/eclipse/credits.json}. */
@OnlyIn(Dist.CLIENT)
public final class CreditsScreen extends Screen {
    private static final ResourceLocation CREDITS =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "credits.json");
    private static final double AUTO_SCROLL_PER_TICK = 0.25D;

    @Nullable
    private final Screen parent;
    private final List<CreditSection> sections = new ArrayList<>();

    private int panelX;
    private int panelY;
    private int panelW;
    private int panelH;
    private int contentTop;
    private int contentBottom;
    private int contentHeight;
    private double scroll;
    private boolean autoScroll = true;
    private boolean loadFailed;

    public CreditsScreen(@Nullable Screen parent) {
        super(EclipseLang.tr("gui.eclipse.credits.title"));
        this.parent = parent;
    }

    @Override
    protected void init() {
        panelW = Mth.clamp(width - 24, 320, 620);
        panelH = Mth.clamp(height - 24, 220, 430);
        panelX = (width - panelW) / 2;
        panelY = (height - panelH) / 2;
        contentTop = panelY + 42;
        contentBottom = panelY + panelH - 34;

        if (sections.isEmpty() && !loadFailed) {
            loadCredits();
        }
        contentHeight = measureContent();

        int doneW = 120;
        addRenderableWidget(Button.builder(CommonComponents.GUI_DONE, button -> onClose())
                .bounds(panelX + (panelW - doneW) / 2, panelY + panelH - 27, doneW, 20)
                .build(EclipseMenuButton::new));
    }

    private void loadCredits() {
        try {
            var resource = minecraft.getResourceManager().getResource(CREDITS)
                    .orElseThrow(() -> new IllegalStateException("Missing " + CREDITS));
            try (var reader = new InputStreamReader(resource.open(), StandardCharsets.UTF_8)) {
                JsonObject root = JsonParser.parseReader(reader).getAsJsonObject();
                for (var sectionJson : root.getAsJsonArray("sections")) {
                    JsonObject section = sectionJson.getAsJsonObject();
                    List<CreditEntry> entries = new ArrayList<>();
                    for (var entryJson : section.getAsJsonArray("entries")) {
                        JsonObject entry = entryJson.getAsJsonObject();
                        List<String> details = new ArrayList<>();
                        for (var detail : entry.getAsJsonArray("details")) {
                            details.add(detail.getAsString());
                        }
                        entries.add(new CreditEntry(entry.get("name").getAsString(), List.copyOf(details)));
                    }
                    sections.add(new CreditSection(section.get("titleKey").getAsString(), List.copyOf(entries)));
                }
            }
        } catch (Exception exception) {
            loadFailed = true;
            EclipseMod.LOGGER.error("Could not load {}", CREDITS, exception);
        }
    }

    private int measureContent() {
        if (loadFailed) {
            return 20;
        }
        int width = panelW - 40;
        int height = 0;
        for (CreditSection section : sections) {
            height += 18;
            for (CreditEntry entry : section.entries) {
                height += 11;
                for (String detail : entry.details) {
                    height += font.split(Component.literal(detail), width - 8).size() * 10;
                }
                height += 7;
            }
            height += 8;
        }
        return height;
    }

    @Override
    public void tick() {
        if (autoScroll && maxScroll() > 0.0D) {
            scroll = Math.min(maxScroll(), scroll + AUTO_SCROLL_PER_TICK);
        }
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fill(0, 0, width, height, EclipseUiTheme.VEIL);
        EclipseUiTheme.drawPanel(guiGraphics, panelX, panelY, panelW, panelH);
        guiGraphics.drawCenteredString(font, title, width / 2, panelY + 10, EclipseUiTheme.ACCENT);
        guiGraphics.drawCenteredString(font, EclipseLang.tr("gui.eclipse.credits.subtitle"),
                width / 2, panelY + 23, EclipseUiTheme.DIM);
        EclipseUiTheme.drawHairline(guiGraphics, panelX + 12, panelX + panelW - 12, panelY + 36);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);
        int contentX = panelX + 20;
        int contentW = panelW - 40;
        int y = contentTop - (int) Math.round(scroll);

        guiGraphics.enableScissor(contentX - 2, contentTop, contentX + contentW + 2, contentBottom);
        if (loadFailed) {
            guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.credits.load_error"),
                    contentX, y, EclipseUiTheme.DANGER);
        } else {
            for (CreditSection section : sections) {
                guiGraphics.drawString(font, EclipseLang.tr(section.titleKey),
                        contentX, y, EclipseUiTheme.ACCENT);
                EclipseUiTheme.drawHairline(guiGraphics, contentX, contentX + contentW, y + 11);
                y += 18;

                for (CreditEntry entry : section.entries) {
                    guiGraphics.drawString(font, entry.name, contentX + 2, y, EclipseUiTheme.TEXT);
                    y += 11;
                    for (String detail : entry.details) {
                        List<FormattedCharSequence> wrapped =
                                font.split(Component.literal(detail), contentW - 8);
                        for (FormattedCharSequence line : wrapped) {
                            guiGraphics.drawString(font, line, contentX + 8, y, EclipseUiTheme.DIM);
                            y += 10;
                        }
                    }
                    y += 7;
                }
                y += 8;
            }
        }
        guiGraphics.disableScissor();
        renderScrollbar(guiGraphics);
    }

    private void renderScrollbar(GuiGraphics guiGraphics) {
        double max = maxScroll();
        if (max <= 0.0D) {
            return;
        }
        int trackX = panelX + panelW - 14;
        int view = contentBottom - contentTop;
        int thumb = Math.max(12, view * view / Math.max(view, contentHeight));
        int travel = view - thumb;
        int thumbY = contentTop + (int) Math.round(travel * scroll / max);
        guiGraphics.fill(trackX, contentTop, trackX + 2, contentBottom, EclipseUiTheme.HAIRLINE);
        guiGraphics.fill(trackX, thumbY, trackX + 2, thumbY + thumb, EclipseUiTheme.ACCENT);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollX, double scrollY) {
        autoScroll = false;
        scroll = Mth.clamp(scroll - scrollY * 24.0D, 0.0D, maxScroll());
        return true;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight - (contentBottom - contentTop));
    }

    @Override
    public void onClose() {
        minecraft.setScreen(parent);
    }

    @Override
    public boolean isPauseScreen() {
        return true;
    }

    private record CreditSection(String titleKey, List<CreditEntry> entries) {}

    private record CreditEntry(String name, List<String> details) {}
}
