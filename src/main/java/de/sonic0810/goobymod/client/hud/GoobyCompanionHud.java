package de.sonic0810.goobymod.client.hud;

import de.sonic0810.goobymod.GoobyClientConfig;
import de.sonic0810.goobymod.GoobyMod;
import de.sonic0810.goobymod.client.fx.GoobyClientFx;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.entity.GoobyMood;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.EventPriority;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RenderGuiEvent;

/**
 * Compact companion card for the nearest own tamed Gooby: name, mood glyph,
 * whistle command, plus health and satisfaction bars — all values are already
 * synchronized entity data, so no extra networking is needed. The card fades
 * in/out via {@link GoobyClientFx} (auto-fade after inactivity) and hides
 * behind screens, the debug overlay and F1.
 */
@EventBusSubscriber(modid = GoobyMod.MODID, value = Dist.CLIENT)
public final class GoobyCompanionHud {
    private static final ResourceLocation ICON_FONT =
            ResourceLocation.fromNamespaceAndPath(GoobyMod.MODID, "icons");

    private static final int CARD_WIDTH = 128;
    private static final int CARD_HEIGHT = 44;
    private static final int PADDING = 5;
    private static final int BAR_WIDTH = 40;
    private static final int BAR_HEIGHT = 5;

    private static final int BACKGROUND_RGB = 0x241A12;
    private static final int BORDER_RGB = 0x8A6A4C;
    private static final int BORDER_ALERT_RGB = 0xE05050;
    private static final int NAME_RGB = 0xF2E3C6;
    private static final int SECONDARY_RGB = 0xC9B49A;
    private static final int BAR_BACK_RGB = 0x3A2A20;
    private static final int HEALTH_RGB = 0xE85C5C;
    private static final int SATISFACTION_RGB = 0xF2C14E;

    /** LOW priority keeps the card above the screen-effect vignette. */
    @SubscribeEvent(priority = EventPriority.LOW)
    public static void onRenderGui(RenderGuiEvent.Post event) {
        if (!GoobyClientConfig.showCompanionHud()) {
            return;
        }
        Minecraft minecraft = Minecraft.getInstance();
        if (minecraft.player == null || minecraft.level == null || minecraft.options.hideGui
                || minecraft.getDebugOverlay().showDebugScreen()) {
            return;
        }
        if (minecraft.screen != null && !(minecraft.screen instanceof ChatScreen)) {
            return;
        }
        GoobyEntity gooby = GoobyClientFx.trackedGooby();
        if (gooby == null) {
            return;
        }
        float partialTick = event.getPartialTick().getGameTimeDeltaPartialTick(true);
        float alpha = GoobyClientFx.hudAlpha(partialTick);
        if (alpha < 0.05F) {
            return;
        }
        renderCard(event.getGuiGraphics(), minecraft.font, gooby, alpha);
    }

    private static void renderCard(GuiGraphics graphics, Font font, GoobyEntity gooby, float alpha) {
        // Clamp so extreme offsets or tiny scaled GUIs never push the card fully
        // offscreen; if the GUI is smaller than the card, anchor at the top-left.
        int x = Math.max(0, Math.min(GoobyClientConfig.companionHudOffsetX(),
                graphics.guiWidth() - CARD_WIDTH));
        int y = Math.max(0, Math.min(GoobyClientConfig.companionHudOffsetY(),
                graphics.guiHeight() - CARD_HEIGHT));
        boolean alerting = gooby.isAlerting();
        GoobyMood mood = gooby.getMood();

        graphics.fill(x, y, x + CARD_WIDTH, y + CARD_HEIGHT, withAlpha(BACKGROUND_RGB, 0.80F * alpha));
        int borderColor = withAlpha(alerting ? BORDER_ALERT_RGB : BORDER_RGB, 0.90F * alpha);
        graphics.fill(x, y, x + CARD_WIDTH, y + 1, borderColor);
        graphics.fill(x, y + CARD_HEIGHT - 1, x + CARD_WIDTH, y + CARD_HEIGHT, borderColor);
        graphics.fill(x, y + 1, x + 1, y + CARD_HEIGHT - 1, borderColor);
        graphics.fill(x + CARD_WIDTH - 1, y + 1, x + CARD_WIDTH, y + CARD_HEIGHT - 1, borderColor);

        int innerX = x + PADDING;
        int innerRight = x + CARD_WIDTH - PADDING;

        // Row 1: mood glyph on the right, name clipped to the remaining space.
        String moodGlyph = moodGlyph(mood);
        int moodColor = withAlpha(moodColor(mood), alpha);
        int glyphWidth = font.width(moodGlyph);
        graphics.drawString(font, moodGlyph, innerRight - glyphWidth, y + PADDING, moodColor, false);
        String name = font.plainSubstrByWidth(gooby.getName().getString(),
                innerRight - innerX - glyphWidth - 3);
        graphics.drawString(font, name, innerX, y + PADDING, withAlpha(NAME_RGB, alpha), false);

        // Row 2: mood label on the left, whistle command right-aligned.
        graphics.drawString(font, Component.translatable(mood.translationKey()),
                innerX, y + 17, moodColor, false);
        GoobyCommand command = gooby.getCommandMode();
        Component commandIcon = Component.literal(command.icon())
                .withStyle(style -> style.withFont(ICON_FONT));
        Component commandName = Component.translatable(command.nameTranslationKey());
        int commandWidth = font.width(commandIcon) + 2 + font.width(commandName);
        int commandX = innerRight - commandWidth;
        int secondaryColor = withAlpha(SECONDARY_RGB, alpha);
        graphics.drawString(font, commandIcon, commandX, y + 17, secondaryColor, false);
        graphics.drawString(font, commandName, commandX + font.width(commandIcon) + 2, y + 17,
                secondaryColor, false);

        // Row 3: health and satisfaction bars.
        float healthFraction = Mth.clamp(gooby.getHealth() / gooby.getMaxHealth(), 0.0F, 1.0F);
        float satisfactionFraction = Mth.clamp(
                gooby.getSatisfaction() / (float) GoobyEntity.MAX_SATISFACTION, 0.0F, 1.0F);
        drawBar(graphics, font, "❤", innerX, y + 29, healthFraction, HEALTH_RGB, alpha);
        drawBar(graphics, font, "✦", innerX + 61, y + 29, satisfactionFraction, SATISFACTION_RGB, alpha);
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

    private static int withAlpha(int rgb, float alpha) {
        int a = Mth.clamp((int) (alpha * 255.0F), 0, 255);
        return (a << 24) | (rgb & 0x00FFFFFF);
    }

    private GoobyCompanionHud() {
    }
}
