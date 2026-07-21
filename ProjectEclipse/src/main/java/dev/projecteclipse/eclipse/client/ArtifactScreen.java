package dev.projecteclipse.eclipse.client;

import java.util.ArrayList;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.components.Button;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.FormattedCharSequence;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * The arm artifact's interface screen (a plain {@link Screen}, not a container menu).
 * All values are read live from {@link ClientStateCache} every frame, so state payloads
 * arriving while the screen is open update it without a reopen. Opened either by the
 * server via {@code S2COpenArtifactPayload} (artifact right-click / C2S request) or
 * locally by the {@code key.eclipse.menu} keybind.
 */
@OnlyIn(Dist.CLIENT)
public class ArtifactScreen extends Screen {
    private static final ResourceLocation BACKGROUND =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/artifact_menu.png");
    private static final ResourceLocation HEART_FULL =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_full.png");
    private static final ResourceLocation HEART_EMPTY =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/heart_empty.png");
    private static final ResourceLocation ALTAR_ICON =
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "textures/gui/icons/altar_progress.png");

    /** Window size drawn from the 256x256 background texture. */
    private static final int WINDOW_WIDTH = 176;
    private static final int WINDOW_HEIGHT = 166;
    private static final int MIN_HEARTS = 5;
    private static final int MAX_HEART_ICONS = 10;
    private static final int TEXT_COLOR = 0xFFE8E0F5;
    private static final int ACCENT_COLOR = 0xFFB98CFF;

    private int leftPos;
    private int topPos;

    public ArtifactScreen() {
        super(Component.translatable("gui.eclipse.artifact.title"));
    }

    @Override
    protected void init() {
        this.leftPos = (this.width - WINDOW_WIDTH) / 2;
        this.topPos = (this.height - WINDOW_HEIGHT) / 2;
        addRenderableWidget(Button.builder(
                        Component.translatable("gui.eclipse.artifact.rules"),
                        button -> this.minecraft.setScreen(new RulesScreen(this)))
                .bounds(this.leftPos + (WINDOW_WIDTH - 80) / 2, this.topPos + 136, 80, 20)
                .build());
    }

    @Override
    public void renderBackground(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.renderBackground(guiGraphics, mouseX, mouseY, partialTick);
        guiGraphics.blit(BACKGROUND, this.leftPos, this.topPos, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        int x = this.leftPos;
        int y = this.topPos;
        guiGraphics.drawCenteredString(this.font, this.title, x + WINDOW_WIDTH / 2, y + 8, ACCENT_COLOR);

        // Day (left) and lives hearts (right) on one row.
        guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.artifact.day", ClientStateCache.day),
                x + 10, y + 24, TEXT_COLOR);
        renderHearts(guiGraphics, x, y + 22);

        // The day's goals.
        guiGraphics.drawString(this.font, Component.translatable("gui.eclipse.artifact.goals"),
                x + 10, y + 40, ACCENT_COLOR);
        int lineY = y + 52;
        for (FormattedCharSequence line : wrappedGoalLines()) {
            if (lineY > y + 96) {
                break;
            }
            guiGraphics.drawString(this.font, line, x + 10, lineY, TEXT_COLOR);
            lineY += 10;
        }

        // Altar progress row, above the footer divider; the Rules button sits centered below it.
        guiGraphics.blit(ALTAR_ICON, x + 10, y + 106, 0, 0, 16, 16, 16, 16);
        guiGraphics.drawString(this.font,
                Component.translatable("gui.eclipse.artifact.altar", ClientStateCache.altarLevel),
                x + 30, y + 110, TEXT_COLOR);
    }

    /** Lives as heart icons, right-aligned: {@code lives} full hearts, padded to at least {@value #MIN_HEARTS}. */
    private void renderHearts(GuiGraphics guiGraphics, int windowX, int heartY) {
        int lives = Math.max(0, ClientStateCache.lives);
        int total = Math.min(MAX_HEART_ICONS, Math.max(MIN_HEARTS, lives));
        int startX = windowX + WINDOW_WIDTH - 10 - total * 10;
        for (int i = 0; i < total; i++) {
            ResourceLocation texture = i < lives ? HEART_FULL : HEART_EMPTY;
            guiGraphics.blit(texture, startX + i * 10, heartY, 0, 0, 9, 9, 9, 9);
        }
        if (lives > MAX_HEART_ICONS) {
            guiGraphics.drawString(this.font, "+" + (lives - MAX_HEART_ICONS), startX - 16, heartY + 1, TEXT_COLOR);
        }
    }

    private List<FormattedCharSequence> wrappedGoalLines() {
        List<String> goals = ClientStateCache.goals;
        List<FormattedCharSequence> lines = new ArrayList<>();
        if (goals.isEmpty()) {
            lines.addAll(this.font.split(Component.translatable("gui.eclipse.artifact.goals.none"), WINDOW_WIDTH - 20));
            return lines;
        }
        for (String goal : goals) {
            lines.addAll(this.font.split(Component.literal("\u2022 " + goal), WINDOW_WIDTH - 20));
        }
        return lines;
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }
}
