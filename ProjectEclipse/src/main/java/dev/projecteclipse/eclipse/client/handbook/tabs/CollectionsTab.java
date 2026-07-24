package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import dev.projecteclipse.eclipse.client.collections.ClientCollectionsCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.UiSounds;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.collections.CollectionTiers;
import dev.projecteclipse.eclipse.network.collections.S2CCollectionsPayload;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Collections page (D1, IDEAS-collections §3 — tab #9, id {@code collections}): a left
 * CATEGORY RAIL ({@code Mining · Farming · Wood · Mobs · Event} in config order, ACCENT
 * when active, small "n/m tiers" fraction under each label, gold when complete) and one
 * ROW per collection of the active category on the right:
 *
 * <ul>
 *   <li>item icon (config {@code icon}) + name;</li>
 *   <li><b>progress bar to the NEXT tier only</b> ({@code (count − prevThreshold) /
 *       (nextThreshold − prevThreshold)}), numeric {@code 1 240 / 2 500} right-aligned
 *       (thin-space grouping via {@link CollectionTiers#formatCount});</li>
 *   <li><b>tier pips</b> (diamonds) under the bar — filled = granted, hollow = future;
 *       all filled flips the row header to the gold "maxed" treatment;</li>
 *   <li><b>reward preview, NEXT tier only</b> (never the whole ladder — the Skyblock
 *       dopamine trick): "+275 XP · +1 SP · unlocks Anvil".</li>
 * </ul>
 *
 * <p>Maxed collections sink to the bottom of their category. Everything renders live
 * from {@link ClientCollectionsCache} (definitions ride the wire, so hot config edits
 * show without a client restart); before the first snapshot the page shows a quiet
 * "awaiting sync" line. Drag-scroll + wheel + {@link TabScrollbar} like Bestiary. New UI
 * keys degrade to English literals until the V5-COLLECTIONS langdrop is merged (house
 * literal-audit rule).</p>
 */
@OnlyIn(Dist.CLIENT)
public class CollectionsTab extends HandbookTab {
    /** Gold "maxed" treatment (§3) — warmer than GOOD, distinct from ACCENT. */
    private static final int GOLD_COLOR = 0xF0C96A;

    private static final int RAIL_W = 72;
    private static final int RAIL_W_NARROW = 52;
    private static final int NARROW_WIDTH = 260;
    private static final int RAIL_ENTRY_H = 24;
    private static final int ROW_H = 38;
    private static final int ROW_GAP = 4;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    private final TabScrollbar scrollbar = new TabScrollbar();
    private double scrollAmount;
    private boolean draggingRows;

    private String activeCategory = "";

    // --- layout cache (rebuilt when cache generation / category / width change) ---
    private List<ClientCollectionsCache.Entry> rows = List.of();
    private List<String> categories = List.of();
    private int layoutGeneration = -1;
    private String layoutCategory = "";

    @Override
    public String id() {
        return "collections";
    }

    @Override
    public void onShown() {
        draggingRows = false;
    }

    private int railWidth() {
        return width < NARROW_WIDTH ? RAIL_W_NARROW : RAIL_W;
    }

    private int rowsX() {
        return x + railWidth() + 6;
    }

    private int rowsWidth() {
        return width - railWidth() - 6;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        ensureLayout();
        if (categories.isEmpty()) {
            guiGraphics.drawString(font,
                    ellipsize(font, uiText("gui.eclipse.handbook.collections.empty",
                            "Awaiting server sync\u2026"), width),
                    x, y + 4, withAlpha(DIM_COLOR, alpha));
            return;
        }
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());

        renderRail(guiGraphics, alpha);
        int sepX = x + railWidth();
        guiGraphics.fill(sepX, y, sepX + 1, y + height, withAlpha(EclipseUiTheme.HAIRLINE & 0xFFFFFF, alpha));

        guiGraphics.enableScissor(rowsX(), y, rowsX() + rowsWidth(), y + height);
        int rowY = y - (int) scrollAmount;
        for (ClientCollectionsCache.Entry entry : rows) {
            if (rowY > y - ROW_H && rowY < y + height) {
                renderRow(guiGraphics, entry, rowsX(), rowY, rowsWidth() - SCROLLBAR_INSET, alpha);
            }
            rowY += ROW_H + ROW_GAP;
        }
        guiGraphics.disableScissor();

        scrollbar.layout(rowsX() + rowsWidth(), y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    // ------------------------------------------------------------------ category rail

    /** Label + "n/m" tier fraction per category; ACCENT active, gold when complete. */
    private void renderRail(GuiGraphics guiGraphics, float alpha) {
        guiGraphics.enableScissor(x, y, x + railWidth(), y + height);
        int entryY = y;
        for (String category : categories) {
            boolean active = category.equals(activeCategory);
            int granted = 0;
            int total = 0;
            for (ClientCollectionsCache.Entry entry : ClientCollectionsCache.all()) {
                if (entry.category().equals(category)) {
                    granted += entry.grantedTier();
                    total += entry.tiers().size();
                }
            }
            boolean complete = total > 0 && granted >= total;
            if (active) {
                guiGraphics.fill(x, entryY + 1, x + 2, entryY + RAIL_ENTRY_H - 3,
                        withAlpha(ACCENT_COLOR, alpha));
            }
            int labelColor = complete ? GOLD_COLOR : active ? ACCENT_COLOR : DIM_COLOR;
            guiGraphics.drawString(font,
                    ellipsize(font, categoryLabel(category), railWidth() - 8),
                    x + 5, entryY + 3, withAlpha(labelColor, alpha));
            guiGraphics.drawString(font,
                    ellipsize(font, granted + "/" + total, railWidth() - 8),
                    x + 5, entryY + 13, withAlpha(complete ? GOLD_COLOR : 0x554A70, alpha));
            entryY += RAIL_ENTRY_H;
        }
        guiGraphics.disableScissor();
    }

    /** {@code gui.eclipse.handbook.collections.category.<id>} → prettified fallback. */
    private static String categoryLabel(String category) {
        String key = "gui.eclipse.handbook.collections.category." + category;
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key)
                : ClientCollectionsCache.prettifyId(category);
    }

    // ------------------------------------------------------------------ rows

    private void renderRow(GuiGraphics guiGraphics, ClientCollectionsCache.Entry entry,
            int rowX, int rowY, int rowWidth, float alpha) {
        boolean maxed = entry.maxed();
        S2CCollectionsPayload.Tier next = entry.nextTier();

        guiGraphics.renderItem(iconStack(entry.icon()), rowX, rowY + 2);
        int textX = rowX + 20;
        int rowRight = rowX + rowWidth;

        // Numeric progress, right-aligned: "1 240 / 2 500", or the gold lifetime total.
        String counter = maxed
                ? CollectionTiers.formatCount(entry.count())
                : CollectionTiers.formatCount(entry.count()) + " / "
                        + CollectionTiers.formatCount(next.threshold());
        int counterWidth = font.width(counter);
        guiGraphics.drawString(font, counter, rowRight - counterWidth, rowY + 3,
                withAlpha(maxed ? GOLD_COLOR : TEXT_COLOR, alpha));

        // Name (gold when maxed — the §3 "maxed" header treatment).
        guiGraphics.drawString(font,
                ellipsize(font, ClientCollectionsCache.displayName(entry.id()),
                        rowRight - textX - counterWidth - 6),
                textX, rowY + 3, withAlpha(maxed ? GOLD_COLOR : ACCENT_COLOR, alpha));

        // Progress bar to the NEXT tier only (full gold when maxed).
        int barY = rowY + 14;
        guiGraphics.fill(textX, barY, rowRight, barY + 3,
                withAlpha(EclipseUiTheme.HAIRLINE & 0xFFFFFF, alpha));
        float progress;
        if (maxed) {
            progress = 1.0F;
        } else {
            long floor = entry.previousThreshold();
            long span = Math.max(1L, next.threshold() - floor);
            progress = Mth.clamp((entry.count() - floor) / (float) span, 0.0F, 1.0F);
        }
        int fill = Math.round((rowRight - textX) * progress);
        if (fill > 0) {
            guiGraphics.fill(textX, barY, textX + fill, barY + 3,
                    withAlpha(maxed ? GOLD_COLOR : ACCENT_COLOR, alpha));
        }

        // Tier pips: filled diamond per granted tier, hollow (hairline) for future ones.
        int pipY = rowY + 19;
        for (int pip = 0; pip < entry.tiers().size(); pip++) {
            drawPip(guiGraphics, textX + pip * 8, pipY,
                    pip < entry.grantedTier() ? (maxed ? GOLD_COLOR : ACCENT_COLOR)
                            : EclipseUiTheme.HAIRLINE & 0xFFFFFF, alpha);
        }

        // Reward preview — NEXT tier only, or the gold maxed line.
        String preview = maxed
                ? uiText("gui.eclipse.handbook.collections.maxed", "Collection complete")
                : nextRewardText(next);
        guiGraphics.drawString(font, ellipsize(font, preview, rowRight - textX),
                textX, rowY + 27, withAlpha(maxed ? GOLD_COLOR : DIM_COLOR, alpha));
    }

    /** "Next: +275 XP · +1 SP · unlocks Anvil, Piston +1" (pieces drop when absent). */
    private static String nextRewardText(S2CCollectionsPayload.Tier next) {
        StringBuilder text = new StringBuilder(
                uiText("gui.eclipse.handbook.collections.next", "Next:"));
        if (next.xp() > 0) {
            text.append(' ').append(uiText("gui.eclipse.collections.toast_xp", "+%s XP",
                    CollectionTiers.formatCount(next.xp())));
        }
        if (next.points() > 0) {
            text.append(" \u00b7 ").append(uiText("gui.eclipse.collections.toast_points",
                    "+%s SP", next.points()));
        }
        if (!next.unlockItems().isEmpty()) {
            StringBuilder names = new StringBuilder();
            int spelled = Math.min(next.unlockItems().size(), 2);
            for (int i = 0; i < spelled; i++) {
                if (i > 0) {
                    names.append(", ");
                }
                names.append(ClientCollectionsCache.unlockName(next.unlockItems().get(i)));
            }
            if (next.unlockItems().size() > spelled) {
                names.append(" +").append(next.unlockItems().size() - spelled);
            }
            text.append(" \u00b7 ").append(uiText("gui.eclipse.handbook.collections.unlocks",
                    "unlocks %s", names.toString()));
        }
        return text.toString();
    }

    /** 5px diamond pip (rows of width 1-3-5-3-1); filled/hollow is a color swap. */
    private static void drawPip(GuiGraphics guiGraphics, int pipX, int pipY, int color, float alpha) {
        int tinted = EclipseUiTheme.withAlpha(color, alpha);
        for (int row = 0; row < 5; row++) {
            int inset = Math.abs(row - 2);
            guiGraphics.fill(pipX + inset, pipY + row, pipX + 5 - inset, pipY + row + 1, tinted);
        }
    }

    /** Config {@code icon} id → renderable stack ({@code chest} when unknown/unparsable). */
    private static ItemStack iconStack(String iconId) {
        ResourceLocation id = ResourceLocation.tryParse(iconId);
        if (id != null && BuiltInRegistries.ITEM.containsKey(id)) {
            Item item = BuiltInRegistries.ITEM.get(id);
            if (item != Items.AIR) {
                return new ItemStack(item);
            }
        }
        return new ItemStack(Items.CHEST);
    }

    /** New UI keys ride the langdrop; fall back to the English literal, never a raw key. */
    private static String uiText(String key, String fallback, Object... args) {
        return EclipseLang.hasKey(key) ? EclipseLang.trString(key, args)
                : String.format(Locale.ROOT, fallback, args);
    }

    // ------------------------------------------------------------------ layout

    /** Rebuilds category + row lists when the synced snapshot or the selection changed. */
    private void ensureLayout() {
        int generation = ClientCollectionsCache.generation();
        if (layoutGeneration == generation && layoutCategory.equals(activeCategory)) {
            return;
        }
        categories = ClientCollectionsCache.categoryOrder();
        if (!categories.isEmpty() && !categories.contains(activeCategory)) {
            activeCategory = categories.get(0);
        }
        // Stable partition: in-progress rows first, maxed rows sink to the bottom (§3).
        List<ClientCollectionsCache.Entry> open = new ArrayList<>();
        List<ClientCollectionsCache.Entry> maxed = new ArrayList<>();
        for (ClientCollectionsCache.Entry entry : ClientCollectionsCache.all()) {
            if (entry.category().equals(activeCategory)) {
                (entry.maxed() ? maxed : open).add(entry);
            }
        }
        open.addAll(maxed);
        rows = List.copyOf(open);
        layoutGeneration = generation;
        layoutCategory = activeCategory;
    }

    private int contentHeight() {
        ensureLayout();
        return rows.isEmpty() ? 0 : rows.size() * (ROW_H + ROW_GAP) - ROW_GAP + 4;
    }

    private double maxScroll() {
        if (font == null) {
            return 0.0D;
        }
        return Math.max(0, contentHeight() - height);
    }

    // ------------------------------------------------------------------ input

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button != 0) {
            return false;
        }
        // Category rail press.
        if (mouseX >= x && mouseX < x + railWidth() && mouseY >= y && mouseY < y + height) {
            int index = (int) ((mouseY - y) / RAIL_ENTRY_H);
            if (index >= 0 && index < categories.size() && !categories.get(index).equals(activeCategory)) {
                activeCategory = categories.get(index);
                scrollAmount = 0.0D;
                layoutCategory = ""; // force the row list rebuild
                UiSounds.click();
            }
            return true;
        }
        if (scrollbar.mouseClicked(mouseX, mouseY, scrollAmount, value -> scrollAmount = value)) {
            return true;
        }
        if (inRect(mouseX, mouseY) && maxScroll() > 0.0D) {
            draggingRows = true;
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
        if (draggingRows) {
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
        if (draggingRows) {
            draggingRows = false;
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

    @Override
    public boolean dragging() {
        return draggingRows || scrollbar.dragging();
    }
}
