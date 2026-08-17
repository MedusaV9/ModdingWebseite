package de.sonic0810.goobymod.client.config;

import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.components.Tooltip;
import net.minecraft.client.gui.screens.ConfirmScreen;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.CommonComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.util.Mth;

/**
 * In-game configuration screen for the Gooby client options, opened via the
 * Config button in the NeoForge mod list. Edits happen on a
 * {@link GoobyConfigDraft}: Done saves everything at once, Reset Defaults
 * restores the built-in defaults into the draft. Cancel (or Esc) discards —
 * with unsaved changes a confirmation screen is shown first. The right side
 * shows a live static preview of the companion card including the
 * GUI-scale-dependent offset clamping.
 */
public final class GoobyConfigScreen extends Screen {
    private static final int HEADER_HEIGHT = 33;
    private static final int FOOTER_HEIGHT = 33;
    private static final int BUTTON_WIDTH = 100;
    private static final int BUTTON_GAP = 8;
    private static final int PREVIEW_MARGIN = 8;

    private final Screen lastScreen;
    private final GoobyConfigDraft draft;
    private GoobyConfigList list;
    private int previewX;
    private int previewWidth;

    public GoobyConfigScreen(Screen lastScreen) {
        super(Component.translatable("config.goobymod.screen.title"));
        this.lastScreen = lastScreen;
        this.draft = GoobyConfigDraft.fromConfig();
    }

    @Override
    protected void init() {
        // Keep the scroll position when the screen re-initializes (window
        // resize, GUI scale change, returning from the discard confirmation).
        double scrollAmount = this.list != null ? this.list.getScrollAmount() : 0.0;

        this.previewWidth = Mth.clamp(this.width * 2 / 5, 120, 190);
        int listWidth = this.width - this.previewWidth - 2 * PREVIEW_MARGIN;
        this.previewX = listWidth + PREVIEW_MARGIN;
        int contentHeight = this.height - HEADER_HEIGHT - FOOTER_HEIGHT;

        this.list = new GoobyConfigList(this.minecraft, listWidth, contentHeight,
                HEADER_HEIGHT, this.draft);
        this.list.setScrollAmount(scrollAmount);
        addRenderableWidget(this.list);

        int buttonY = this.height - FOOTER_HEIGHT + (FOOTER_HEIGHT - 20) / 2;
        int buttonsLeft = this.width / 2 - (3 * BUTTON_WIDTH + 2 * BUTTON_GAP) / 2;
        addRenderableWidget(Button.builder(Component.translatable("config.goobymod.reset"),
                        button -> {
                            this.draft.resetToDefaults();
                            this.list.syncFromDraft();
                        })
                .bounds(buttonsLeft, buttonY, BUTTON_WIDTH, 20)
                .tooltip(Tooltip.create(Component.translatable("config.goobymod.reset.tooltip")))
                .build());
        addRenderableWidget(Button.builder(CommonComponents.GUI_CANCEL, button -> onClose())
                .bounds(buttonsLeft + BUTTON_WIDTH + BUTTON_GAP, buttonY, BUTTON_WIDTH, 20)
                .build());
        addRenderableWidget(Button.builder(CommonComponents.GUI_DONE, button -> saveAndClose())
                .bounds(buttonsLeft + 2 * (BUTTON_WIDTH + BUTTON_GAP), buttonY, BUTTON_WIDTH, 20)
                .build());
    }

    @Override
    public void render(GuiGraphics graphics, int mouseX, int mouseY, float partialTick) {
        super.render(graphics, mouseX, mouseY, partialTick);
        graphics.drawCenteredString(this.font, this.title, this.width / 2, 12, 0xFFFFFF);
        CompanionHudPreview.renderPanel(graphics, this.font, this.draft, this.previewX,
                HEADER_HEIGHT, this.previewWidth, this.width, this.height);
    }

    private void saveAndClose() {
        this.draft.saveToConfig();
        this.minecraft.setScreen(this.lastScreen);
    }

    /**
     * Esc and the Cancel button both discard the draft; with unsaved changes a
     * confirmation screen is shown first (its own Esc returns to editing).
     */
    @Override
    public void onClose() {
        if (this.draft.isDirty()) {
            this.minecraft.setScreen(new ConfirmScreen(
                    discard -> this.minecraft.setScreen(discard ? this.lastScreen : this),
                    Component.translatable("config.goobymod.discard.title"),
                    Component.translatable("config.goobymod.discard.message"),
                    Component.translatable("config.goobymod.discard.confirm"),
                    Component.translatable("config.goobymod.discard.keepEditing")));
            return;
        }
        this.minecraft.setScreen(this.lastScreen);
    }
}
