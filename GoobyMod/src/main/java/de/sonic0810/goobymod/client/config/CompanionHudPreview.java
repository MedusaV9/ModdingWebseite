package de.sonic0810.goobymod.client.config;

import de.sonic0810.goobymod.client.hud.CompanionCardRenderer;
import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyMood;
import java.util.ArrayList;
import java.util.List;
import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FormattedCharSequence;

/**
 * Static demo rendering of the companion card for the config screen preview.
 * All card metrics, colors and the offset clamping come from
 * {@link CompanionCardRenderer}, the same code path the live HUD uses — only
 * the data is a fixed happy demo Gooby, so no entity is required. The
 * placement mini-map uses the real GUI-scaled screen size, so the clamping the
 * HUD applies is visible instantly.
 */
final class CompanionHudPreview {

    private static final int PANEL_BACK_ARGB = 0xC0140D08;
    private static final int MAP_BACK_ARGB = 0xE0000000;
    private static final int MAP_FRAME_ARGB = 0xFF4A3A2C;
    private static final int ALERT_ARGB = 0xFFE08050;
    private static final float HIDDEN_ALPHA = 0.35F;

    private static final float DEMO_HEALTH = 0.85F;
    private static final float DEMO_SATISFACTION = 0.70F;

    /**
     * Draws the whole preview panel.
     *
     * @param x upper-left corner of the reserved panel area
     * @param y upper edge of the reserved panel area
     * @param width width of the reserved panel area
     * @param guiWidth real, GUI-scale-dependent screen width used for
     *        clamping — identical to what the HUD sees in-game
     * @param guiHeight real screen height, see {@code guiWidth}
     * @return the height actually used by the panel
     */
    static int renderPanel(GuiGraphics graphics, Font font, GoobyConfigDraft draft,
            int x, int y, int width, int guiWidth, int guiHeight) {
        int pad = 6;
        int innerX = x + pad;
        int innerWidth = width - 2 * pad;

        // The exact clamping used by the live HUD.
        int clampedX = CompanionCardRenderer.clampOffsetX(draft.hudOffsetX, guiWidth);
        int clampedY = CompanionCardRenderer.clampOffsetY(draft.hudOffsetY, guiHeight);
        boolean clamped = clampedX != draft.hudOffsetX || clampedY != draft.hudOffsetY;

        // Measure all rows first so the frame hugs its content.
        int mapWidth = innerWidth;
        int mapHeight = Math.round(mapWidth * (guiHeight / (float) guiWidth));
        if (mapHeight > 56) {
            mapHeight = 56;
            mapWidth = Math.round(mapHeight * (guiWidth / (float) guiHeight));
        }
        float cardScale = Math.min(1.0F, innerWidth / (float) CompanionCardRenderer.CARD_WIDTH);
        int cardHeight = Math.round(CompanionCardRenderer.CARD_HEIGHT * cardScale);

        Component positionText = Component.translatable("config.goobymod.preview.position",
                clampedX, clampedY);
        List<FormattedCharSequence> captionLines = new ArrayList<>(
                font.split(positionText, innerWidth));
        if (!draft.showCompanionHud) {
            captionLines.addAll(font.split(
                    Component.translatable("config.goobymod.preview.hidden"), innerWidth));
        } else if (clamped) {
            captionLines.addAll(font.split(
                    Component.translatable("config.goobymod.preview.clamped"), innerWidth));
        }

        int titleY = y + pad;
        int mapY = titleY + 12;
        int cardY = mapY + mapHeight + 7;
        int captionY = cardY + cardHeight + 7;
        int panelHeight = captionY + captionLines.size() * 10 + pad - y;

        graphics.fill(x, y, x + width, y + panelHeight, PANEL_BACK_ARGB);
        CompanionCardRenderer.drawFrame(graphics, x, y, width, panelHeight,
                CompanionCardRenderer.withAlpha(CompanionCardRenderer.BORDER_RGB, 0.9F));

        graphics.drawString(font, Component.translatable("config.goobymod.preview"),
                innerX, titleY, CompanionCardRenderer.withAlpha(CompanionCardRenderer.NAME_RGB, 1.0F),
                false);

        renderPlacementMap(graphics, draft.showCompanionHud, innerX, mapY, mapWidth, mapHeight,
                clampedX, clampedY, guiWidth, guiHeight);

        float alpha = draft.showCompanionHud ? 1.0F : HIDDEN_ALPHA;
        var pose = graphics.pose();
        pose.pushPose();
        pose.translate(innerX, cardY, 0.0F);
        pose.scale(cardScale, cardScale, 1.0F);
        CompanionCardRenderer.renderCard(graphics, font, demoData(), 0, 0, alpha);
        pose.popPose();

        int captionColor = CompanionCardRenderer.withAlpha(CompanionCardRenderer.SECONDARY_RGB, 1.0F);
        int lineY = captionY;
        for (int i = 0; i < captionLines.size(); i++) {
            // Extra caption lines (hidden/clamped hints) use the alert color.
            int color = i == 0 ? captionColor : ALERT_ARGB;
            graphics.drawString(font, captionLines.get(i), innerX, lineY, color, false);
            lineY += 10;
        }
        return panelHeight;
    }

    /** A fixed happy demo Gooby — the preview never needs a real entity. */
    private static CompanionCardRenderer.CardData demoData() {
        return new CompanionCardRenderer.CardData(
                Component.translatable("entity.goobymod.gooby").getString(),
                GoobyMood.HAPPY, GoobyCommand.FOLLOW,
                DEMO_HEALTH, DEMO_SATISFACTION, false);
    }

    /** Miniature of the whole GUI viewport with the clamped card footprint. */
    private static void renderPlacementMap(GuiGraphics graphics, boolean showCard,
            int x, int y, int mapWidth, int mapHeight, int clampedX, int clampedY,
            int guiWidth, int guiHeight) {
        graphics.fill(x, y, x + mapWidth, y + mapHeight, MAP_BACK_ARGB);
        CompanionCardRenderer.drawFrame(graphics, x, y, mapWidth, mapHeight, MAP_FRAME_ARGB);

        float scaleX = mapWidth / (float) guiWidth;
        float scaleY = mapHeight / (float) guiHeight;
        int markerX = x + Math.round(clampedX * scaleX);
        int markerY = y + Math.round(clampedY * scaleY);
        int markerWidth = Math.max(3, Math.round(CompanionCardRenderer.CARD_WIDTH * scaleX));
        int markerHeight = Math.max(2, Math.round(CompanionCardRenderer.CARD_HEIGHT * scaleY));
        markerX = Math.min(markerX, x + mapWidth - 1 - markerWidth);
        markerY = Math.min(markerY, y + mapHeight - 1 - markerHeight);

        int markerColor = CompanionCardRenderer.withAlpha(CompanionCardRenderer.SATISFACTION_RGB,
                showCard ? 0.95F : HIDDEN_ALPHA);
        graphics.fill(markerX, markerY, markerX + markerWidth, markerY + markerHeight, markerColor);
    }

    private CompanionHudPreview() {
    }
}
