package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.client.progression.ClientBestiaryCache;
import dev.projecteclipse.eclipse.progression.bestiary.BestiaryTiers;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.network.chat.FormattedText;
import net.minecraft.network.chat.Style;
import net.minecraft.util.Mth;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Bestiary page v2 (W4-BESTIARY): flat raised cards for every entry of the static
 * {@link #CREATURES} roster, now gated by the per-player KNOWLEDGE TIER synced from the
 * server ({@link ClientBestiaryCache}, {@link BestiaryTiers}) instead of the old day
 * gate — you learn a creature by hunting it, not by waiting:
 *
 * <ul>
 *   <li><b>T0 unseen</b> — pure silhouette, scrambled {@link GlitchText} name, "not yet
 *       witnessed" (compact card).</li>
 *   <li><b>T1 encountered</b> — name, first-seen day, kill/sighting counter, base lore.</li>
 *   <li><b>T2 hunter</b> — + field notes (hunting pattern, spawn grounds).</li>
 *   <li><b>T3 slayer</b> — + the WEAKNESS section with the {@link EclipseUiTheme#DANGER}
 *       accent bar.</li>
 * </ul>
 *
 * <p>Unlock pips (I/II/III) sit top-right on every card; cards below T3 show a subtle
 * "next entry at N kills" hint. Unlocked cards grow to fit their whole dossier (variable
 * height, rows sized to the taller neighbor) — the page scrolls, nothing is cut. The
 * text layout is cached against (width, lang generation, bestiary generation), so a
 * settled frame costs the same as v1; while the tab is closed nothing here runs at
 * all.</p>
 *
 * <p><b>Adding future mobs stays one roster line</b> and everything degrades gracefully
 * while lang keys ride another worker's langdrop: names fall back
 * {@code bestiary.eclipse.<id>.name} → {@code entity.eclipse.<id>} → prettified id, and
 * missing {@code .lore}/{@code .behavior}/{@code .weakness} render the DIM "records
 * pending" line instead of raw keys. Silhouettes are code-drawn; unknown ids get the
 * generic wisp.</p>
 */
@OnlyIn(Dist.CLIENT)
public class BestiaryTab extends HandbookTab {
    /** id + intro day; lang keys and the silhouette derive from the id. Keep chronological. */
    private record Creature(String id, int introDay) {}

    /**
     * The bestiary roster (single client-side source, kept in sync with the spawn rules):
     * v2 arc — Deckhand day 1 ghost ship, Gazer night 3, The Other first Pale Night day 4,
     * Umbral Stalker night 5, Herald day 7, Ferryman day 14 — plus the P6 roster (intro
     * days per {@code docs/plans_v3/handoff/P6_bestiary_entries.md}): Drift Lantern limbo
     * day 1, storm-scar pack day 6, the glitched family with the first fresh ring after
     * day 8, colossus/cultist day 9, sentinel/warden day 10, the Fog Tyrant day 12 — and
     * Orin the Sun-Reader (W4-WIZARD observatory hermit; the entry tolerates the family
     * being unwired and simply stays T0 until he exists). Future mobs: append here
     * (chronologically), ship lang keys via langdrop.
     */
    private static final List<Creature> CREATURES = List.of(
            new Creature("deckhand", 1),
            new Creature("drift_lantern", 1),
            new Creature("gazer", 3),
            new Creature("the_other", 4),
            new Creature("umbral_stalker", 5),
            new Creature("fog_revenant", 6),
            new Creature("storm_hound", 6),
            new Creature("herald", 7),
            new Creature("glitched_husk", 8),
            new Creature("glitched_hound", 8),
            new Creature("glitched_tick", 8),
            new Creature("fog_colossus", 9),
            new Creature("eclipse_cultist", 9),
            new Creature("pale_sentinel", 10),
            new Creature("rift_warden", 10),
            new Creature("wizard_orin", 11),
            new Creature("fog_tyrant", 12),
            new Creature("ferryman", 14));

    private static final int CARD_GAP = 4;
    /** Two card columns need at least this much content width; below it, one column. */
    private static final int TWO_COLUMN_MIN_WIDTH = 310;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    /** Compact T0 card (silhouette + scrambled lines). */
    private static final int LOCKED_CARD_HEIGHT = 52;
    private static final int LINE_H = 9;
    /** Unlocked header band: 24px silhouette box + name/meta rows beside it. */
    private static final int HEADER_H = 30;
    private static final int SIDE_PAD = 6;

    private final TabScrollbar scrollbar = new TabScrollbar();
    private double scrollAmount;
    private boolean dragging;

    // --- layout cache (rebuilt when width / lang / bestiary snapshot change) ---
    private int[] cardYs;
    private int[] cardHeights;
    private int cardWidth;
    private int totalHeight;
    private int layoutWidth = -1;
    private int layoutLangGen = -1;
    private int layoutBestiaryGen = -1;

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

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        ensureLayout();
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());

        guiGraphics.enableScissor(x, y, x + width, y + height);
        for (int i = 0; i < CREATURES.size(); i++) {
            Creature creature = CREATURES.get(i);
            int cardX = x + (i % columns()) * (cardWidth + CARD_GAP);
            int cardY = y + cardYs[i] - (int) scrollAmount;
            int cardHeight = cardHeights[i];
            if (cardY > y - cardHeight && cardY < y + height) {
                renderCard(guiGraphics, creature, i, ClientBestiaryCache.tierFor(creature.id()),
                        cardX, cardY, cardWidth, cardHeight, alpha);
            }
        }
        guiGraphics.disableScissor();

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    // ------------------------------------------------------------------ layout

    /**
     * Rebuilds card heights/positions when the content width, the lang tables or the
     * bestiary snapshot changed. Rows keep the roster order; a row is as tall as its
     * tallest card, so column neighbors stay aligned.
     */
    private void ensureLayout() {
        int langGen = EclipseLang.generation();
        int bestiaryGen = ClientBestiaryCache.generation();
        if (cardYs != null && layoutWidth == width && layoutLangGen == langGen
                && layoutBestiaryGen == bestiaryGen) {
            return;
        }
        layoutWidth = width;
        layoutLangGen = langGen;
        layoutBestiaryGen = bestiaryGen;

        int columns = columns();
        cardWidth = (width - SCROLLBAR_INSET - (columns - 1) * CARD_GAP) / columns;
        cardYs = new int[CREATURES.size()];
        cardHeights = new int[CREATURES.size()];
        int rowY = 0;
        for (int rowStart = 0; rowStart < CREATURES.size(); rowStart += columns) {
            int rowHeight = 0;
            for (int i = rowStart; i < Math.min(rowStart + columns, CREATURES.size()); i++) {
                cardHeights[i] = cardHeight(CREATURES.get(i));
                rowHeight = Math.max(rowHeight, cardHeights[i]);
            }
            for (int i = rowStart; i < Math.min(rowStart + columns, CREATURES.size()); i++) {
                cardYs[i] = rowY;
            }
            rowY += rowHeight + CARD_GAP;
        }
        totalHeight = rowY - CARD_GAP + 4;
    }

    /** Exact height this card needs at its current tier (dossiers grow, T0 stays compact). */
    private int cardHeight(Creature creature) {
        byte tier = ClientBestiaryCache.tierFor(creature.id());
        if (tier < BestiaryTiers.TIER_ENCOUNTERED) {
            return LOCKED_CARD_HEIGHT;
        }
        int bodyWidth = cardWidth - 2 * SIDE_PAD;
        int h = HEADER_H;
        h += wrap(sectionText(creature.id(), "lore"), bodyWidth).size() * LINE_H;
        if (tier >= BestiaryTiers.TIER_HUNTER) {
            h += 5 + LINE_H // divider + section label
                    + wrap(sectionText(creature.id(), "behavior"), bodyWidth).size() * LINE_H;
        }
        if (tier >= BestiaryTiers.TIER_SLAYER) {
            h += 5 + LINE_H
                    + wrap(sectionText(creature.id(), "weakness"), bodyWidth - 5).size() * LINE_H;
        } else {
            h += 3 + LINE_H; // "next entry at N" hint
        }
        return h + 5;
    }

    /** Section body ({@code bestiary.eclipse.<id>.<section>}) or the DIM pending line. */
    private static String sectionText(String id, String section) {
        String key = "bestiary.eclipse." + id + "." + section;
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key)
                : EclipseLang.trString("gui.eclipse.handbook.bestiary.pending");
    }

    private static boolean hasSection(String id, String section) {
        return EclipseLang.hasKey("bestiary.eclipse." + id + "." + section);
    }

    /**
     * New W4 UI keys ride the langdrop; until the integrator merges it, fall back to the
     * English literal instead of ever showing a raw key (house literal-audit rule).
     */
    private static String uiText(String key, String fallback, Object... args) {
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key, args)
                : String.format(Locale.ROOT, fallback, args);
    }

    private List<FormattedText> wrap(String text, int maxWidth) {
        return font.getSplitter().splitLines(text, Math.max(20, maxWidth), Style.EMPTY);
    }

    // ------------------------------------------------------------------ cards

    /** Flat card: raised fill + hairline frame; unlocked cards get a 2px accent left edge. */
    private void renderCard(GuiGraphics guiGraphics, Creature creature, int index, byte tier,
            int cardX, int cardY, int cardWidth, int cardHeight, float alpha) {
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + cardHeight,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        int border = EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha);
        guiGraphics.fill(cardX, cardY, cardX + cardWidth, cardY + 1, border);
        guiGraphics.fill(cardX, cardY + cardHeight - 1, cardX + cardWidth, cardY + cardHeight, border);
        guiGraphics.fill(cardX, cardY + 1, cardX + 1, cardY + cardHeight - 1, border);
        guiGraphics.fill(cardX + cardWidth - 1, cardY + 1, cardX + cardWidth, cardY + cardHeight - 1, border);
        if (tier >= BestiaryTiers.TIER_ENCOUNTERED) {
            guiGraphics.fill(cardX, cardY, cardX + 2, cardY + cardHeight, withAlpha(ACCENT_COLOR, alpha));
        }

        // Hard-clip to the card so long names/labels never bleed into the neighbor.
        guiGraphics.enableScissor(cardX + 1, cardY + 1, cardX + cardWidth - 1, cardY + cardHeight - 1);
        drawTierPips(guiGraphics, tier, cardX + cardWidth - 22, cardY + 4, alpha);
        if (tier >= BestiaryTiers.TIER_ENCOUNTERED) {
            renderDossier(guiGraphics, creature, tier, cardX, cardY, cardWidth, alpha);
        } else {
            renderLockedCard(guiGraphics, creature, index, cardX, cardY, cardWidth, cardHeight, alpha);
        }
        guiGraphics.disableScissor();
    }

    /** T0: big silhouette, scrambled name, "not yet witnessed", glitch filler lines. */
    private void renderLockedCard(GuiGraphics guiGraphics, Creature creature, int index,
            int cardX, int cardY, int cardWidth, int cardHeight, float alpha) {
        int silhouetteSize = Math.min(cardHeight - 8, 36);
        drawSilhouette(guiGraphics, creature.id(), cardX + 6, cardY + (cardHeight - silhouetteSize) / 2,
                silhouetteSize, false, alpha);
        int textX = cardX + silhouetteSize + 11;
        int textWidth = cardX + cardWidth - textX - 4;
        int textY = cardY + 4;
        guiGraphics.drawString(font, GlitchText.scramble(9, index + 40), textX, textY,
                withAlpha(DIM_COLOR, alpha));
        textY += 10;
        guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.handbook.bestiary.locked"),
                textX, textY, withAlpha(DIM_COLOR, alpha));
        textY += 11;
        for (int line = 0; line < 2 && textY <= cardY + cardHeight - LINE_H; line++) {
            guiGraphics.drawString(font, GlitchText.scramble(Math.min(18, textWidth / 6), index * 7 + line),
                    textX, textY, withAlpha(0x554A70, alpha));
            textY += LINE_H;
        }
    }

    /** T1+: header band (small silhouette, name, day + counter), then the tiered dossier. */
    private void renderDossier(GuiGraphics guiGraphics, Creature creature, byte tier,
            int cardX, int cardY, int cardWidth, float alpha) {
        String id = creature.id();
        drawSilhouette(guiGraphics, id, cardX + SIDE_PAD, cardY + 4, 24, true, alpha);
        int textX = cardX + SIDE_PAD + 24 + 6;
        int textWidth = cardX + cardWidth - textX - 26; // keep clear of the pips
        guiGraphics.drawString(font, ellipsize(font, ClientBestiaryCache.displayName(id), textWidth),
                textX, cardY + 4, withAlpha(ACCENT_COLOR, alpha));
        boolean sightings = BestiaryTiers.isSightingProgress(id);
        String counter = sightings
                ? uiText("gui.eclipse.handbook.bestiary.sightings", "Sightings: %s",
                        ClientBestiaryCache.countFor(id))
                : uiText("gui.eclipse.handbook.bestiary.kills", "Kills: %s",
                        ClientBestiaryCache.countFor(id));
        String meta = EclipseLang.trString("gui.eclipse.handbook.bestiary.day", creature.introDay())
                + " \u00b7 " + counter;
        guiGraphics.drawString(font, ellipsize(font, meta, textWidth + 22),
                textX, cardY + 15, withAlpha(DIM_COLOR, alpha));

        int bodyX = cardX + SIDE_PAD;
        int bodyWidth = cardWidth - 2 * SIDE_PAD;
        int textY = cardY + HEADER_H;

        // T1 — base lore.
        textY = drawWrapped(guiGraphics, sectionText(id, "lore"), bodyX, textY, bodyWidth,
                hasSection(id, "lore") ? TEXT_COLOR : DIM_COLOR, alpha);

        // T2 — field notes (hunting pattern + spawn grounds).
        if (tier >= BestiaryTiers.TIER_HUNTER) {
            textY += 2;
            EclipseUiTheme.drawHairline(guiGraphics, bodyX, bodyX + bodyWidth, textY, alpha);
            textY += 3;
            guiGraphics.drawString(font,
                    ellipsize(font, uiText("gui.eclipse.handbook.bestiary.behavior", "Field notes"),
                            bodyWidth),
                    bodyX, textY, withAlpha(EclipseUiTheme.ACCENT_DEEP & 0xFFFFFF, alpha));
            textY += LINE_H;
            textY = drawWrapped(guiGraphics, sectionText(id, "behavior"), bodyX, textY, bodyWidth,
                    hasSection(id, "behavior") ? TEXT_COLOR : DIM_COLOR, alpha);
        }

        // T3 — WEAKNESS with the DANGER accent bar.
        if (tier >= BestiaryTiers.TIER_SLAYER) {
            textY += 2;
            EclipseUiTheme.drawHairline(guiGraphics, bodyX, bodyX + bodyWidth, textY, alpha);
            textY += 3;
            int danger = EclipseUiTheme.DANGER & 0xFFFFFF;
            guiGraphics.drawString(font,
                    ellipsize(font, uiText("gui.eclipse.handbook.bestiary.weakness", "Weakness"),
                            bodyWidth - 5),
                    bodyX + 5, textY, withAlpha(danger, alpha));
            int barTop = textY;
            textY += LINE_H;
            textY = drawWrapped(guiGraphics, sectionText(id, "weakness"), bodyX + 5, textY,
                    bodyWidth - 5, hasSection(id, "weakness") ? TEXT_COLOR : DIM_COLOR, alpha);
            guiGraphics.fill(bodyX, barTop, bodyX + 2, textY - 2, withAlpha(danger, alpha));
        } else {
            // Subtle "next tier" hint (T0 unlocks by encounter, so only T1/T2 show one).
            int next = BestiaryTiers.nextCount(id, tier);
            if (next > 0) {
                String hint = sightings
                        ? uiText("gui.eclipse.handbook.bestiary.next_sightings",
                                "Next entry at %s sightings", next)
                        : uiText("gui.eclipse.handbook.bestiary.next_kills",
                                "Next entry at %s kills", next);
                textY += 3;
                guiGraphics.drawString(font, ellipsize(font, hint, bodyWidth),
                        bodyX, textY, withAlpha(0x554A70, alpha));
            }
        }
    }

    /** Wraps and draws one section body; returns the y below the last line. */
    private int drawWrapped(GuiGraphics guiGraphics, String text, int textX, int textY,
            int maxWidth, int color, float alpha) {
        for (FormattedText line : wrap(text, maxWidth)) {
            guiGraphics.drawString(font, line.getString(), textX, textY, withAlpha(color, alpha));
            textY += LINE_H;
        }
        return textY;
    }

    /** Unlock pips I/II/III: filled ACCENT per reached tier, hollow hairline otherwise. */
    private static void drawTierPips(GuiGraphics guiGraphics, byte tier, int pipX, int pipY, float alpha) {
        for (int pip = 1; pip <= 3; pip++) {
            int px = pipX + (pip - 1) * 6;
            int color = tier >= pip
                    ? EclipseUiTheme.withAlpha(EclipseUiTheme.ACCENT, alpha)
                    : EclipseUiTheme.withAlpha(EclipseUiTheme.HAIRLINE, alpha);
            guiGraphics.fill(px, pipY, px + 4, pipY + 4, color);
        }
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
            case "wizard_orin" -> { // pointed hat, robe, staff — the observatory hermit
                cell(guiGraphics, boxX, boxY, u, 5, 0, 2, 2, body); // hat tip
                cell(guiGraphics, boxX, boxY, u, 3, 2, 6, 1, body); // hat brim
                cell(guiGraphics, boxX, boxY, u, 4, 3, 4, 2, body); // head
                cell(guiGraphics, boxX, boxY, u, 3, 5, 6, 7, body); // robe
                cell(guiGraphics, boxX, boxY, u, 10, 1, 1, 11, body); // staff
                cell(guiGraphics, boxX, boxY, u, 10, 0, 1, 1, eye); // staff glow
                cell(guiGraphics, boxX, boxY, u, 5, 3, 1, 1, eye);
                cell(guiGraphics, boxX, boxY, u, 7, 3, 1, 1, eye);
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
        ensureLayout();
        return totalHeight;
    }

    private double maxScroll() {
        if (font == null) {
            return 0.0D;
        }
        return Math.max(0, contentHeight() - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
