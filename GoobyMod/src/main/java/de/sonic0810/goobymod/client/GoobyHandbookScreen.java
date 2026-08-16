package de.sonic0810.goobymod.client;

import de.sonic0810.goobymod.GoobyMod;
import java.util.List;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;

/** Illustrated, keyboard-accessible handbook with eight localized chapters. */
public final class GoobyHandbookScreen extends Screen {
    public static final int CHAPTER_COUNT = 8;
    public static final int PORTRAIT_FRAME_COUNT = 4;
    private static final int PANEL_WIDTH = 320;
    private static final int PANEL_HEIGHT = 218;
    private static final ResourceLocation[] PORTRAITS = resources("portrait_", PORTRAIT_FRAME_COUNT);
    private static final ResourceLocation[] CHAPTER_ICONS = resources("chapter_", CHAPTER_COUNT);

    private int chapter;
    private Button previous;
    private Button next;

    public GoobyHandbookScreen() {
        super(Component.translatable("handbook2.goobymod.title"));
    }

    @Override
    protected void init() {
        int left = (this.width - PANEL_WIDTH) / 2;
        int top = (this.height - PANEL_HEIGHT) / 2;
        int buttonWidth = 36;
        for (int index = 0; index < CHAPTER_COUNT; index++) {
            int selectedChapter = index;
            addRenderableWidget(Button.builder(
                            Component.translatable("handbook2.goobymod.chapter." + (index + 1) + ".short"),
                            button -> selectChapter(selectedChapter))
                    .bounds(left + 10 + index * 37, top + 30, buttonWidth, 20)
                    .build());
        }
        this.previous = addRenderableWidget(Button.builder(
                        Component.translatable("handbook2.goobymod.previous"),
                        button -> selectChapter(this.chapter - 1))
                .bounds(left + 10, top + PANEL_HEIGHT - 28, 78, 20)
                .build());
        this.next = addRenderableWidget(Button.builder(
                        Component.translatable("handbook2.goobymod.next"),
                        button -> selectChapter(this.chapter + 1))
                .bounds(left + PANEL_WIDTH - 88, top + PANEL_HEIGHT - 28, 78, 20)
                .build());
        updateNavigation();
    }

    private void selectChapter(int chapter) {
        this.chapter = Math.max(0, Math.min(CHAPTER_COUNT - 1, chapter));
        updateNavigation();
    }

    private void updateNavigation() {
        if (this.previous != null) {
            this.previous.active = this.chapter > 0;
        }
        if (this.next != null) {
            this.next.active = this.chapter + 1 < CHAPTER_COUNT;
        }
    }

    @Override
    public void render(GuiGraphics graphics, int mouseX, int mouseY, float partialTick) {
        renderBackground(graphics, mouseX, mouseY, partialTick);
        int left = (this.width - PANEL_WIDTH) / 2;
        int top = (this.height - PANEL_HEIGHT) / 2;
        graphics.fill(left, top, left + PANEL_WIDTH, top + PANEL_HEIGHT, 0xFFF7E7C8);
        graphics.fill(left + 3, top + 3, left + PANEL_WIDTH - 3, top + PANEL_HEIGHT - 3, 0xFF6F4527);
        graphics.fill(left + 5, top + 5, left + PANEL_WIDTH - 5, top + PANEL_HEIGHT - 5, 0xFFFFF4DC);

        graphics.drawCenteredString(this.font, this.title, this.width / 2, top + 11, 0x6B351E);
        int portraitFrame = (int) ((System.currentTimeMillis() / 260L) % PORTRAIT_FRAME_COUNT);
        graphics.blit(PORTRAITS[portraitFrame], left + 14, top + 64, 0, 0, 64, 64);
        graphics.blit(CHAPTER_ICONS[this.chapter], left + 34, top + 136, 0, 0, 24, 24);

        Component heading = Component.translatable(
                "handbook2.goobymod.chapter." + (this.chapter + 1) + ".title");
        Component body = Component.translatable(
                "handbook2.goobymod.chapter." + (this.chapter + 1) + ".body");
        graphics.drawString(this.font, heading, left + 88, top + 64, 0x6B351E, false);
        List<FormattedCharSequence> lines = this.font.split(body, 214);
        int lineY = top + 84;
        for (FormattedCharSequence line : lines) {
            graphics.drawString(this.font, line, left + 88, lineY, 0x3B2A20, false);
            lineY += 11;
        }
        super.render(graphics, mouseX, mouseY, partialTick);
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    private static ResourceLocation[] resources(String prefix, int count) {
        ResourceLocation[] resources = new ResourceLocation[count];
        for (int index = 0; index < count; index++) {
            resources[index] = ResourceLocation.fromNamespaceAndPath(
                    GoobyMod.MODID, "textures/gui/handbook/" + prefix + index + ".png");
        }
        return resources;
    }
}
