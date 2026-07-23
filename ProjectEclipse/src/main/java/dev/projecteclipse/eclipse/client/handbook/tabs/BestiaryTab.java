package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.FormattedText;
import net.minecraft.network.chat.Style;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Bestiary page: cards for the six v2 creatures. The DATA lives here client-side (this is
 * the single source W10–W12 keep in sync when the mobs land): entry ids, lang keys
 * ({@code bestiary.eclipse.<id>.name/.lore}) and intro days matching the v2 arc
 * ({@code docs/ideas/04_content.md} §1/§2/§6 — Deckhand day 1 ghost ship, Gazer night 3,
 * The Other first Pale Night day 4, Umbral Stalker night 5, Herald day 7, Ferryman day 14).
 * A card unlocks once {@code ClientStateCache.day >= introDay}; locked cards show a pure
 * silhouette + {@link GlitchText} name and hide the intro day, so future content stays
 * unreadable. Silhouettes are code-drawn (no textures — manifest marks these
 * procedural-only).
 */
@OnlyIn(Dist.CLIENT)
public class BestiaryTab extends HandbookTab {
    /** id, intro day; lang keys derive from the id. Keep in sync with W10-12 spawn rules. */
    private record Creature(String id, int introDay) {}

    private static final List<Creature> CREATURES = List.of(
            new Creature("deckhand", 1),
            new Creature("gazer", 3),
            new Creature("the_other", 4),
            new Creature("umbral_stalker", 5),
            new Creature("herald", 7),
            new Creature("ferryman", 14));

    private static final int CARD_GAP = 4;
    /** Two card columns need at least this much content width; below it, one column. */
    private static final int TWO_COLUMN_MIN_WIDTH = 310;

    private double scrollAmount;

    @Override
    public String id() {
        return "bestiary";
    }

    /** One column on narrow pages so name/lore text has room; two on wide screens. */
    private int columns() {
        return width < TWO_COLUMN_MIN_WIDTH ? 1 : 2;
    }

    private int cardHeight() {
        return Math.max(52, (height - 2 * CARD_GAP) / 3);
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        int day = ClientStateCache.day;
        int columns = columns();
        int cardWidth = (width - (columns - 1) * CARD_GAP) / columns;
        int cardHeight = cardHeight();

        guiGraphics.enableScissor(x, y, x + width, y + height);
        for (int i = 0; i < CREATURES.size(); i++) {
            Creature creature = CREATURES.get(i);
            int cardX = x + (i % columns) * (cardWidth + CARD_GAP);
            int cardY = y + (i / columns) * (cardHeight + CARD_GAP) - (int) scrollAmount;
            if (cardY > y - cardHeight && cardY < y + height) {
                renderCard(guiGraphics, creature, i, day >= creature.introDay(), cardX, cardY,
                        cardWidth, cardHeight, alpha);
            }
        }
        guiGraphics.disableScissor();
    }

    private void renderCard(GuiGraphics guiGraphics, Creature creature, int index, boolean unlocked,
            int cardX, int cardY, int cardWidth, int cardHeight, float alpha) {
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + cardHeight, withAlpha(0x160D26, alpha * 0.8F));
        int border = unlocked ? ACCENT_COLOR : 0x3A2F52;
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + 1, withAlpha(border, alpha));
        guiGraphics.fill(cardX, cardY + cardHeight - 1, cardX + cardWidth, cardY + cardHeight, withAlpha(border, alpha));
        guiGraphics.fill(cardX, cardY, cardX + 1, cardY + cardHeight, withAlpha(border, alpha));
        guiGraphics.fill(cardX + cardWidth - 1, cardY, cardX + cardWidth, cardY + cardHeight, withAlpha(border, alpha));

        int silhouetteSize = Math.min(cardHeight - 8, 36);
        drawSilhouette(guiGraphics, creature.id(), cardX + 5, cardY + (cardHeight - silhouetteSize) / 2,
                silhouetteSize, unlocked, alpha);

        int textX = cardX + silhouetteSize + 10;
        int textWidth = cardX + cardWidth - textX - 4;
        int textY = cardY + 4;
        // Hard-clip to the card so long names/labels never bleed into the neighbor.
        guiGraphics.enableScissor(cardX + 1, cardY + 1, cardX + cardWidth - 1, cardY + cardHeight - 1);
        if (unlocked) {
            guiGraphics.drawString(font, Component.translatable("bestiary.eclipse." + creature.id() + ".name"),
                    textX, textY, withAlpha(ACCENT_COLOR, alpha));
            textY += 10;
            guiGraphics.drawString(font,
                    Component.translatable("gui.eclipse.handbook.bestiary.day", creature.introDay()),
                    textX, textY, withAlpha(DIM_COLOR, alpha));
            textY += 11;
            List<FormattedText> lore = font.getSplitter().splitLines(
                    Component.translatable("bestiary.eclipse." + creature.id() + ".lore").getString(),
                    textWidth, Style.EMPTY);
            for (int line = 0; line < lore.size(); line++) {
                if (textY > cardY + cardHeight - 9) {
                    break;
                }
                String text = lore.get(line).getString();
                if (line + 1 < lore.size() && textY + 9 > cardY + cardHeight - 9) {
                    // More lore exists but this is the last line that fits — mark the cut.
                    text = ellipsize(font, text + "\u2026", textWidth);
                }
                guiGraphics.drawString(font, text, textX, textY, withAlpha(TEXT_COLOR, alpha));
                textY += 9;
            }
        } else {
            guiGraphics.drawString(font, GlitchText.scramble(9, index + 40), textX, textY,
                    withAlpha(DIM_COLOR, alpha));
            textY += 10;
            guiGraphics.drawString(font, Component.translatable("gui.eclipse.handbook.bestiary.locked"),
                    textX, textY, withAlpha(DIM_COLOR, alpha));
            textY += 11;
            for (int line = 0; line < 2 && textY <= cardY + cardHeight - 9; line++) {
                guiGraphics.drawString(font, GlitchText.scramble(Math.min(18, textWidth / 6), index * 7 + line),
                        textX, textY, withAlpha(0x554A70, alpha));
                textY += 9;
            }
        }
        guiGraphics.disableScissor();
    }

    /**
     * Code-drawn creature silhouette in a {@code size} px box: black shape when locked,
     * violet-tinted with glinting eyes when unlocked. Rect-composition programmer art —
     * real portraits would be a texture swap in a later art pass.
     */
    private void drawSilhouette(GuiGraphics guiGraphics, String id, int boxX, int boxY, int size,
            boolean unlocked, float alpha) {
        int body = withAlpha(unlocked ? 0x241638 : 0x08040F, alpha);
        int eye = withAlpha(unlocked ? 0xE8DCFF : 0x1A1226, alpha);
        // Work in a 12x12 virtual grid scaled to the box.
        float u = size / 12.0F;
        switch (id) {
            case "the_other" -> { // humanoid, unsettlingly plain
                cell(guiGraphics, boxX, boxY, u, 4, 0, 4, 3, body); // head
                cell(guiGraphics, boxX, boxY, u, 3, 3, 6, 5, body); // torso
                cell(guiGraphics, boxX, boxY, u, 2, 3, 1, 4, body); // arms
                cell(guiGraphics, boxX, boxY, u, 9, 3, 1, 4, body);
                cell(guiGraphics, boxX, boxY, u, 4, 8, 2, 4, body); // legs
                cell(guiGraphics, boxX, boxY, u, 6, 8, 2, 4, body);
                cell(guiGraphics, boxX, boxY, u, 5, 1, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 7, 1, 1, 1, eye);
            }
            case "gazer" -> { // hooded watcher floating above the ground
                cell(guiGraphics, boxX, boxY, u, 3, 0, 6, 4, body); // hood
                cell(guiGraphics, boxX, boxY, u, 2, 4, 8, 5, body); // cloak
                cell(guiGraphics, boxX, boxY, u, 3, 9, 2, 2, body); // tatters (gap = float)
                cell(guiGraphics, boxX, boxY, u, 7, 9, 2, 2, body);
                cell(guiGraphics, boxX, boxY, u, 4, 2, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 7, 2, 1, 1, eye);
            }
            case "umbral_stalker" -> { // low quadruped with spine shards
                cell(guiGraphics, boxX, boxY, u, 2, 5, 8, 3, body); // body
                cell(guiGraphics, boxX, boxY, u, 0, 4, 3, 3, body); // head
                cell(guiGraphics, boxX, boxY, u, 3, 8, 1, 4, body); // legs
                cell(guiGraphics, boxX, boxY, u, 5, 8, 1, 4, body);
                cell(guiGraphics, boxX, boxY, u, 7, 8, 1, 4, body);
                cell(guiGraphics, boxX, boxY, u, 9, 8, 1, 4, body);
                cell(guiGraphics, boxX, boxY, u, 4, 3, 1, 2, body); // spine shards
                cell(guiGraphics, boxX, boxY, u, 6, 2, 1, 3, body);
                cell(guiGraphics, boxX, boxY, u, 8, 3, 1, 2, body);
                cell(guiGraphics, boxX, boxY, u, 1, 5, 1, 1, eye);
            }
            case "deckhand" -> { // hunched rower with an oar
                cell(guiGraphics, boxX, boxY, u, 3, 1, 4, 3, body); // hooded head
                cell(guiGraphics, boxX, boxY, u, 2, 4, 5, 5, body); // hunched torso
                cell(guiGraphics, boxX, boxY, u, 2, 9, 5, 2, body); // robe base
                cell(guiGraphics, boxX, boxY, u, 7, 3, 4, 1, body); // extended arms
                cell(guiGraphics, boxX, boxY, u, 10, 1, 1, 10, body); // oar
            }
            case "herald" -> { // eclipsed godhead: core, corona shards, one blazing eye
                cell(guiGraphics, boxX, boxY, u, 4, 4, 4, 4, body); // core
                cell(guiGraphics, boxX, boxY, u, 5, 1, 2, 2, body); // corona shards
                cell(guiGraphics, boxX, boxY, u, 5, 9, 2, 2, body);
                cell(guiGraphics, boxX, boxY, u, 1, 5, 2, 2, body);
                cell(guiGraphics, boxX, boxY, u, 9, 5, 2, 2, body);
                cell(guiGraphics, boxX, boxY, u, 2, 2, 1, 1, body);
                cell(guiGraphics, boxX, boxY, u, 9, 2, 1, 1, body);
                cell(guiGraphics, boxX, boxY, u, 2, 9, 1, 1, body);
                cell(guiGraphics, boxX, boxY, u, 9, 9, 1, 1, body);
                cell(guiGraphics, boxX, boxY, u, 5, 5, 2, 2, eye);
            }
            default -> { // ferryman: tall robe, hood, oar staff, lantern
                cell(guiGraphics, boxX, boxY, u, 3, 0, 4, 3, body); // hood
                cell(guiGraphics, boxX, boxY, u, 2, 3, 6, 9, body); // robe
                cell(guiGraphics, boxX, boxY, u, 9, 0, 1, 12, body); // oar
                cell(guiGraphics, boxX, boxY, u, 0, 5, 2, 1, body); // lantern chain
                cell(guiGraphics, boxX, boxY, u, 0, 6, 1, 2, eye); // lantern glow
                cell(guiGraphics, boxX, boxY, u, 4, 1, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 6, 1, 1, 1, eye);
            }
        }
    }

    private static void cell(GuiGraphics guiGraphics, int boxX, int boxY, float unit,
            int gridX, int gridY, int gridW, int gridH, int color) {
        int x0 = boxX + Math.round(gridX * unit);
        int y0 = boxY + Math.round(gridY * unit);
        int x1 = boxX + Math.round((gridX + gridW) * unit);
        int y1 = boxY + Math.round((gridY + gridH) * unit);
        guiGraphics.fill(x0, y0, x1, y1, color);
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY)) {
            int columns = columns();
            int rows = (CREATURES.size() + columns - 1) / columns;
            double max = Math.max(0, rows * (cardHeight() + CARD_GAP) - height);
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * 16.0D, 0.0D, max);
            return true;
        }
        return false;
    }
}
