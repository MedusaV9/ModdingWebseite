package de.sonic0810.goobymod.client.hud;

import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyMood;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;

/**
 * Single source of truth for the companion card presentation: metrics, colors,
 * the GUI-size offset clamping and the static card rendering. Shared by the
 * live HUD ({@link GoobyCompanionHud}) and the config screen preview
 * ({@code CompanionHudPreview}), so the two can never drift apart. Rendering
 * only needs a {@link CardData} snapshot — no entity required.
 */
public final class CompanionCardRenderer {
    public static final int CARD_WIDTH = 128;
    public static final int CARD_HEIGHT = 44;

    public static final int BORDER_RGB = 0x8A6A4C;
    public static final int NAME_RGB = 0xF2E3C6;
    public static final int SECONDARY_RGB = 0xC9B49A;
    public static final int SATISFACTION_RGB = 0xF2C14E;

    private static final ResourceLocation ICON_FONT =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "icons");

    private static final int PADDING = 5;
    private static final int BAR_WIDTH = 40;
    private static final int BAR_HEIGHT = 5;

    private static final int BACKGROUND_RGB = 0x241A12;
    private static final int BORDER_ALERT_RGB = 0xE05050;
    private static final int BAR_BACK_RGB = 0x3A2A20;
    private static final int HEALTH_RGB = 0xE85C5C;

    /** Everything the card shows, decoupled from {@code GoobyEntity}. */
    public record CardData(String name, GoobyMood mood, GoobyCommand command,
            float healthFraction, float satisfactionFraction, boolean alerting) {
    }

    /**
     * Clamps a configured X offset so the card never leaves the screen; if the
     * GUI is narrower than the card, the card anchors at the left edge.
     */
    public static int clampOffsetX(int offsetX, int guiWidth) {
        return Math.max(0, Math.min(offsetX, guiWidth - CARD_WIDTH));
    }

    /** Vertical counterpart of {@link #clampOffsetX(int, int)}. */
    public static int clampOffsetY(int offsetY, int guiHeight) {
        return Math.max(0, Math.min(offsetY, guiHeight - CARD_HEIGHT));
    }

    /** Draws the complete card with its upper-left corner at {@code x}/{@code y}. */
    public static void renderCard(GuiGraphics graphics, Font font, CardData data,
            int x, int y, float alpha) {
        graphics.fill(x, y, x + CARD_WIDTH, y + CARD_HEIGHT, withAlpha(BACKGROUND_RGB, 0.80F * alpha));
        int borderColor = withAlpha(data.alerting() ? BORDER_ALERT_RGB : BORDER_RGB, 0.90F * alpha);
        drawFrame(graphics, x, y, CARD_WIDTH, CARD_HEIGHT, borderColor);

        int innerX = x + PADDING;
        int innerRight = x + CARD_WIDTH - PADDING;

        // Row 1: mood glyph on the right, name clipped to the remaining space.
        String moodGlyph = moodGlyph(data.mood());
        int moodColor = withAlpha(moodColor(data.mood()), alpha);
        int glyphWidth = font.width(moodGlyph);
        graphics.drawString(font, moodGlyph, innerRight - glyphWidth, y + PADDING, moodColor, false);
        String name = font.plainSubstrByWidth(data.name(), innerRight - innerX - glyphWidth - 3);
        graphics.drawString(font, name, innerX, y + PADDING, withAlpha(NAME_RGB, alpha), false);

        // Row 2: mood label on the left, whistle command right-aligned.
        graphics.drawString(font, Component.translatable(data.mood().translationKey()),
                innerX, y + 17, moodColor, false);
        Component commandIcon = Component.literal(data.command().icon())
                .withStyle(style -> style.withFont(ICON_FONT));
        Component commandName = Component.translatable(data.command().nameTranslationKey());
        int commandWidth = font.width(commandIcon) + 2 + font.width(commandName);
        int commandX = innerRight - commandWidth;
        int secondaryColor = withAlpha(SECONDARY_RGB, alpha);
        graphics.drawString(font, commandIcon, commandX, y + 17, secondaryColor, false);
        graphics.drawString(font, commandName, commandX + font.width(commandIcon) + 2, y + 17,
                secondaryColor, false);

        // Row 3: health and satisfaction bars.
        drawBar(graphics, font, "❤", innerX, y + 29, data.healthFraction(), HEALTH_RGB, alpha);
        drawBar(graphics, font, "✦", innerX + 61, y + 29, data.satisfactionFraction(),
                SATISFACTION_RGB, alpha);
    }

    /** 1px rectangle outline, also used for the preview panel and mini-map. */
    public static void drawFrame(GuiGraphics graphics, int x, int y, int width, int height,
            int color) {
        graphics.fill(x, y, x + width, y + 1, color);
        graphics.fill(x, y + height - 1, x + width, y + height, color);
        graphics.fill(x, y + 1, x + 1, y + height - 1, color);
        graphics.fill(x + width - 1, y + 1, x + width, y + height - 1, color);
    }

    public static int withAlpha(int rgb, float alpha) {
        int a = Mth.clamp((int) (alpha * 255.0F), 0, 255);
        return (a << 24) | (rgb & 0x00FFFFFF);
    }

    private static void drawBar(GuiGraphics graphics, Font font, String glyph, int x, int y,
            float fraction, int fillRgb, float alpha) {
        graphics.drawString(font, glyph, x, y, withAlpha(fillRgb, alpha), false);
        int barX = x + 11;
        int barY = y + 2;
        graphics.fill(barX, barY, barX + BAR_WIDTH, barY + BAR_HEIGHT,
                withAlpha(BAR_BACK_RGB, 0.85F * alpha));
        int filled = Math.round((BAR_WIDTH - 2) * fraction);
        if (filled > 0) {
            graphics.fill(barX + 1, barY + 1, barX + 1 + filled, barY + BAR_HEIGHT - 1,
                    withAlpha(fillRgb, alpha));
        }
    }

    private static String moodGlyph(GoobyMood mood) {
        return switch (mood) {
            case HAPPY -> "☺";
            case CONTENT -> "✦";
            case HUNGRY -> "♨";
            case SLEEPY -> "☾";
            case LONELY -> "☂";
            case SCARED -> "‼";
        };
    }

    private static int moodColor(GoobyMood mood) {
        return switch (mood) {
            case HAPPY -> 0xFFD966;
            case CONTENT -> 0xBFD9A8;
            case HUNGRY -> 0xE8A85C;
            case SLEEPY -> 0x9BB0E8;
            case LONELY -> 0xB8A8D8;
            case SCARED -> 0xE86A6A;
        };
    }

    private CompanionCardRenderer() {
    }
}
