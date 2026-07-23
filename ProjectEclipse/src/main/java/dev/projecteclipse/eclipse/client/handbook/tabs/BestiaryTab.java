package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.FormattedText;
import net.minecraft.network.chat.Style;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Bestiary page, Quiet Eclipse v3 (plans_v3 P3 §3.1): flat raised cards for every entry of
 * the static {@link #CREATURES} roster — the six v2 arc creatures plus the Drift Lantern
 * (the limbo sea ambience mob, witnessed from day 1 on the ghost ship). A card unlocks
 * once {@code ClientStateCache.day >= introDay}; locked cards keep the pure silhouette +
 * {@link GlitchText} treatment and hide the intro day, so future content stays unreadable.
 *
 * <p><b>Adding future mobs is one roster line.</b> Entries are fully data-driven and
 * degrade gracefully while their lang keys are still in another worker's langdrop: the
 * name resolves {@code bestiary.eclipse.<id>.name} → {@code entity.eclipse.<id>} → a
 * prettified id, and missing {@code bestiary.eclipse.<id>.lore} renders the DIM
 * "records pending" line instead of a raw key. Silhouettes are code-drawn (no textures);
 * ids without a dedicated shape fall back to a generic wisp so a new entry never shows a
 * missing-texture checker.</p>
 */
@OnlyIn(Dist.CLIENT)
public class BestiaryTab extends HandbookTab {
    /** id + intro day; lang keys and the silhouette derive from the id. Keep chronological. */
    private record Creature(String id, int introDay) {}

    /**
     * The bestiary roster (single client-side source, kept in sync with the spawn rules):
     * v2 arc — Deckhand day 1 ghost ship, Gazer night 3, The Other first Pale Night day 4,
     * Umbral Stalker night 5, Herald day 7, Ferryman day 14 — plus the P6 Drift Lantern
     * (limbo ambience, day 1). Future P6 mobs: append here, ship lang keys via langdrop.
     */
    private static final List<Creature> CREATURES = List.of(
            new Creature("deckhand", 1),
            new Creature("drift_lantern", 1),
            new Creature("gazer", 3),
            new Creature("the_other", 4),
            new Creature("umbral_stalker", 5),
            new Creature("herald", 7),
            new Creature("ferryman", 14));

    private static final int CARD_GAP = 4;
    /** Two card columns need at least this much content width; below it, one column. */
    private static final int TWO_COLUMN_MIN_WIDTH = 310;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    private final TabScrollbar scrollbar = new TabScrollbar();
    private double scrollAmount;
    private boolean dragging;

    @Override
    public String id() {
        return "bestiary";
    }

    @Override
    public void onShown() {
        dragging = false;
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
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
        int day = ClientStateCache.day;
        int columns = columns();
        int cardWidth = (width - SCROLLBAR_INSET - (columns - 1) * CARD_GAP) / columns;
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

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    /** Flat card: raised fill + hairline frame; unlocked cards get a 2px accent left edge. */
    private void renderCard(GuiGraphics guiGraphics, Creature creature, int index, boolean unlocked,
            int cardX, int cardY, int cardWidth, int cardHeight, float alpha) {
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + cardHeight,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        int border = EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha);
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + 1, border);
        guiGraphics.fill(cardX, cardY + cardHeight - 1, cardX + cardWidth, cardY + cardHeight, border);
        guiGraphics.fill(cardX, cardY + 1, cardX + 1, cardY + cardHeight - 1, border);
        guiGraphics.fill(cardX + cardWidth - 1, cardY + 1, cardX + cardWidth, cardY + cardHeight - 1, border);
        if (unlocked) {
            guiGraphics.fill(cardX, cardY, cardX + 2, cardY + cardHeight, withAlpha(ACCENT_COLOR, alpha));
        }

        int silhouetteSize = Math.min(cardHeight - 8, 36);
        drawSilhouette(guiGraphics, creature.id(), cardX + 6, cardY + (cardHeight - silhouetteSize) / 2,
                silhouetteSize, unlocked, alpha);

        int textX = cardX + silhouetteSize + 11;
        int textWidth = cardX + cardWidth - textX - 4;
        int textY = cardY + 4;
        // Hard-clip to the card so long names/labels never bleed into the neighbor.
        guiGraphics.enableScissor(cardX + 1, cardY + 1, cardX + cardWidth - 1, cardY + cardHeight - 1);
        if (unlocked) {
            guiGraphics.drawString(font, ellipsize(font, creatureName(creature), textWidth),
                    textX, textY, withAlpha(ACCENT_COLOR, alpha));
            textY += 10;
            guiGraphics.drawString(font,
                    ellipsize(font, EclipseLang.trString("gui.eclipse.handbook.bestiary.day",
                            creature.introDay()), textWidth),
                    textX, textY, withAlpha(DIM_COLOR, alpha));
            textY += 11;
            boolean hasLore = EclipseLang.hasKey("bestiary.eclipse." + creature.id() + ".lore");
            String lore = hasLore
                    ? EclipseLang.trString("bestiary.eclipse." + creature.id() + ".lore")
                    : EclipseLang.trString("gui.eclipse.handbook.bestiary.pending");
            int loreColor = hasLore ? TEXT_COLOR : DIM_COLOR;
            List<FormattedText> wrapped = font.getSplitter().splitLines(lore, textWidth, Style.EMPTY);
            for (int line = 0; line < wrapped.size(); line++) {
                if (textY > cardY + cardHeight - 9) {
                    break;
                }
                String text = wrapped.get(line).getString();
                if (line + 1 < wrapped.size() && textY + 9 > cardY + cardHeight - 9) {
                    // More lore exists but this is the last line that fits — mark the cut.
                    text = ellipsize(font, text + "\u2026", textWidth);
                }
                guiGraphics.drawString(font, text, textX, textY, withAlpha(loreColor, alpha));
                textY += 9;
            }
        } else {
            guiGraphics.drawString(font, GlitchText.scramble(9, index + 40), textX, textY,
                    withAlpha(DIM_COLOR, alpha));
            textY += 10;
            guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.handbook.bestiary.locked"),
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
     * Display name with graceful degradation (new mobs land before their bestiary lang
     * keys): {@code bestiary.eclipse.<id>.name} → {@code entity.eclipse.<id>} → the id
     * prettified ({@code drift_lantern} → "Drift Lantern").
     */
    private static String creatureName(Creature creature) {
        String bestiaryKey = "bestiary.eclipse." + creature.id() + ".name";
        if (EclipseLang.hasKey(bestiaryKey)) {
            return EclipseLang.trString(bestiaryKey);
        }
        String entityKey = "entity.eclipse." + creature.id();
        if (EclipseLang.hasKey(entityKey)) {
            return EclipseLang.trString(entityKey);
        }
        return prettifyId(creature.id());
    }

    /** {@code umbral_stalker} → "Umbral Stalker" (last-resort fallback, never a raw key). */
    private static String prettifyId(String id) {
        StringBuilder pretty = new StringBuilder(id.length());
        for (String word : id.split("_")) {
            if (word.isEmpty()) {
                continue;
            }
            if (pretty.length() > 0) {
                pretty.append(' ');
            }
            pretty.append(word.substring(0, 1).toUpperCase(Locale.ROOT)).append(word.substring(1));
        }
        return pretty.isEmpty() ? id : pretty.toString();
    }

    /**
     * Code-drawn creature silhouette in a {@code size} px box: black shape when locked,
     * violet-tinted with glinting eyes when unlocked. Rect-composition programmer art —
     * real portraits would be a texture swap in a later art pass. Ids without a dedicated
     * shape render the generic wisp so future roster lines never break the page.
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
            case "ferryman" -> { // tall robe, hood, oar staff, lantern
                cell(guiGraphics, boxX, boxY, u, 3, 0, 4, 3, body); // hood
                cell(guiGraphics, boxX, boxY, u, 2, 3, 6, 9, body); // robe
                cell(guiGraphics, boxX, boxY, u, 9, 0, 1, 12, body); // oar
                cell(guiGraphics, boxX, boxY, u, 0, 5, 2, 1, body); // lantern chain
                cell(guiGraphics, boxX, boxY, u, 0, 6, 1, 2, eye); // lantern glow
                cell(guiGraphics, boxX, boxY, u, 4, 1, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 6, 1, 1, 1, eye);
            }
            case "drift_lantern" -> { // soul-lantern jellyfish: cage, flame, trailing tendrils
                cell(guiGraphics, boxX, boxY, u, 5, 0, 2, 1, body); // handle loop
                cell(guiGraphics, boxX, boxY, u, 3, 1, 6, 6, body); // glass cage
                cell(guiGraphics, boxX, boxY, u, 5, 3, 2, 2, eye); // guttering flame
                cell(guiGraphics, boxX, boxY, u, 4, 7, 4, 1, body); // cage base
                cell(guiGraphics, boxX, boxY, u, 3, 8, 1, 3, body); // kelp tendrils
                cell(guiGraphics, boxX, boxY, u, 5, 9, 1, 3, body);
                cell(guiGraphics, boxX, boxY, u, 7, 8, 1, 3, body);
                cell(guiGraphics, boxX, boxY, u, 9, 9, 1, 2, body);
            }
            default -> { // generic wisp fallback for roster entries without dedicated art
                cell(guiGraphics, boxX, boxY, u, 3, 2, 6, 6, body); // shroud
                cell(guiGraphics, boxX, boxY, u, 4, 1, 4, 1, body); // crown
                cell(guiGraphics, boxX, boxY, u, 4, 8, 1, 3, body); // trailing wisps
                cell(guiGraphics, boxX, boxY, u, 6, 8, 2, 2, body);
                cell(guiGraphics, boxX, boxY, u, 8, 8, 1, 3, body);
                cell(guiGraphics, boxX, boxY, u, 4, 4, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 7, 4, 1, 1, eye);
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
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseClicked(mouseX, mouseY, scrollAmount, value -> scrollAmount = value)) {
            return true;
        }
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            dragging = true;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double dragX, double dragY) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseDragged(mouseY, value -> scrollAmount = value)) {
            return true;
        }
        if (dragging) {
            scrollAmount = Mth.clamp(scrollAmount - dragY, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        if (scrollbar.mouseReleased()) {
            return true;
        }
        if (dragging) {
            dragging = false;
            return true;
        }
        return false;
    }

    @Override
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * 16.0D, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    private int contentHeight() {
        int columns = columns();
        int rows = (CREATURES.size() + columns - 1) / columns;
        return rows * (cardHeight() + CARD_GAP) - CARD_GAP + 4;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
