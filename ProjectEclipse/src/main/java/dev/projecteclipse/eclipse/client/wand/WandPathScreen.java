package dev.projecteclipse.eclipse.client.wand;

import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.network.wand.C2SWandChoosePathPayload;
import dev.projecteclipse.eclipse.wand.WandPath;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The first-right-click path chooser (IDEA-19 §"three paths, one choice"): a quiet
 * three-card Eclipse panel — Phasenriss / Glutherz / Sternenfall — matching the
 * {@link EclipseUiTheme} handbook language (no busy radial, no textures; hairlines,
 * panel fills and one accent per path). Hover lifts a card; click sends the
 * {@code C2SWandChoosePathPayload} and closes — the SERVER locks the path
 * ({@code WandPowers.handleChoosePath} re-validates ownership + NONE state, so mashing
 * two cards or a stale screen cannot double-lock.
 *
 * <p>ESC = decide later (the wand stays pathless and simply reopens the chooser on the
 * next right-click). Pausing is disabled so the world keeps breathing behind the veil.</p>
 */
public final class WandPathScreen extends Screen {
    private static final WandPath[] PATHS = {WandPath.RISS, WandPath.GLUT, WandPath.STERN};
    private static final int[] ACCENTS = {0xFFB98CFF, 0xFFFF9A4D, 0xFF7FE7FF};

    private static final int CARD_W = 108;
    private static final int CARD_H = 138;
    private static final int CARD_GAP = 14;

    private WandPathScreen() {
        super(Component.translatable("wand.eclipse.screen.title"));
    }

    /** Client-side opener (called from {@code EclipseWandItem#use} on a pathless wand). */
    public static void open() {
        Minecraft.getInstance().setScreen(new WandPathScreen());
    }

    @Override
    public boolean isPauseScreen() {
        return false;
    }

    private int cardX(int index) {
        int total = PATHS.length * CARD_W + (PATHS.length - 1) * CARD_GAP;
        return (this.width - total) / 2 + index * (CARD_W + CARD_GAP);
    }

    private int cardY() {
        return (this.height - CARD_H) / 2;
    }

    private int hoveredCard(double mouseX, double mouseY) {
        int y = cardY();
        if (mouseY < y || mouseY >= y + CARD_H) {
            return -1;
        }
        for (int i = 0; i < PATHS.length; i++) {
            int x = cardX(i);
            if (mouseX >= x && mouseX < x + CARD_W) {
                return i;
            }
        }
        return -1;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick) {
        guiGraphics.fill(0, 0, this.width, this.height, EclipseUiTheme.VEIL);
        super.render(guiGraphics, mouseX, mouseY, partialTick);

        int titleY = cardY() - 28;
        guiGraphics.drawCenteredString(this.font, this.title, this.width / 2, titleY,
                EclipseUiTheme.TEXT);
        guiGraphics.drawCenteredString(this.font,
                Component.translatable("wand.eclipse.screen.final"), this.width / 2, titleY + 12,
                EclipseUiTheme.DIM);

        int hovered = hoveredCard(mouseX, mouseY);
        for (int i = 0; i < PATHS.length; i++) {
            renderCard(guiGraphics, i, i == hovered);
        }

        guiGraphics.drawCenteredString(this.font,
                Component.translatable("wand.eclipse.screen.later"), this.width / 2,
                cardY() + CARD_H + 14, EclipseUiTheme.DIM);
    }

    private void renderCard(GuiGraphics guiGraphics, int index, boolean hovered) {
        WandPath path = PATHS[index];
        int accent = ACCENTS[index];
        int x = cardX(index);
        int y = cardY() - (hovered ? 3 : 0);

        EclipseUiTheme.drawPanel(guiGraphics, x, y, CARD_W, CARD_H, hovered ? 1.0F : 0.86F);
        // Accent top bar — each path announces its color before its words.
        guiGraphics.fill(x + 1, y + 1, x + CARD_W - 1, y + 3,
                EclipseUiTheme.withAlpha(accent, hovered ? 1.0F : 0.7F));

        int textX = x + 9;
        int textY = y + 12;
        guiGraphics.drawString(this.font, Component.translatable(path.langKey()), textX, textY, accent);
        textY += 12;
        String key = path.name().toLowerCase(Locale.ROOT);
        List<FormattedCharSequence> tag = this.font.split(
                Component.translatable("wand.eclipse.screen." + key + ".tag"), CARD_W - 18);
        for (FormattedCharSequence line : tag) {
            guiGraphics.drawString(this.font, line, textX, textY, EclipseUiTheme.TEXT);
            textY += 10;
        }
        textY += 4;
        EclipseUiTheme.drawHairline(guiGraphics, textX, x + CARD_W - 9, textY);
        textY += 6;
        for (int power = 0; power < 3; power++) {
            guiGraphics.drawString(this.font, Component.literal("L" + (power + 1) + " ")
                            .append(Component.translatable(path.powerLangKey(power))),
                    textX, textY, EclipseUiTheme.DIM);
            textY += 10;
        }

        Component choose = Component.translatable("wand.eclipse.screen.choose");
        guiGraphics.drawCenteredString(this.font, choose, x + CARD_W / 2, y + CARD_H - 14,
                hovered ? accent : EclipseUiTheme.DIM);
    }

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0) {
            int card = hoveredCard(mouseX, mouseY);
            if (card >= 0) {
                PacketDistributor.sendToServer(new C2SWandChoosePathPayload(PATHS[card].id()));
                onClose();
                return true;
            }
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }
}
