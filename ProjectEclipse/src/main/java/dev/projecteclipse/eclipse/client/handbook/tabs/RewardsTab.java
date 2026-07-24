package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
import dev.projecteclipse.eclipse.client.handbook.GlitchText;
import dev.projecteclipse.eclipse.client.lang.EclipseLang;
import dev.projecteclipse.eclipse.network.S2CMilestonesPayload;
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
 * Altar Offering page, Wave-5 A5 rework (was "Rewards"): instead of the full milestone
 * ladder, the page shows ONLY what matters right now — the tier the altar is currently
 * hungering for ({@code altarLevel + 1}, full costs as real item icons + granted unlock
 * keys, 2px accent edge) and one anonymized "???" teaser row for the tier after it
 * ({@link GlitchText}, no data — the server ships that entry as a data-free stub, see
 * {@code S2CMilestonesPayload}). Beaten tiers are not re-advertised and future tiers
 * never reach the client. With the ladder exhausted the page shows a single "sated"
 * line. Scroll plumbing (shared {@link TabScrollbar} + drag, B7/B20 rules) is kept for
 * the empty/none states and in case rows ever outgrow the panel.
 *
 * <p><b>D14 (W-SHARDS) addition:</b> a personal Umbral-Splitter block heads the page —
 * live balance from the sidebar cache ({@link ClientStateCache#sidebarShards}, resynced
 * within a second of every change per B14), the earn-lane list, and the explicit
 * TEAM-pool label (altar deposits fund the pool ONLY — they never join the personal
 * balance). RewardsTab is owned by D14 for this addition.</p>
 */
@OnlyIn(Dist.CLIENT)
public class RewardsTab extends HandbookTab {
    private static final int ROW_HEIGHT = 46;
    /** Right-side inset reserved for the scrollbar + a small gap. */
    private static final int SCROLLBAR_INSET = 8;

    private final TabScrollbar scrollbar = new TabScrollbar();
    private double scrollAmount;
    private boolean dragging;

    @Override
    public String id() {
        return "rewards";
    }

    @Override
    public void onShown() {
        dragging = false;
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        List<S2CMilestonesPayload.Entry> milestones = ClientStateCache.milestones;
        S2CMilestonesPayload.Entry target = currentTarget(milestones);
        S2CMilestonesPayload.Entry teaser = teaser(milestones);
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());

        guiGraphics.enableScissor(x, y, x + width, y + height);
        // D14: the personal shard block heads the page in every milestone state.
        int rowY = y + 2 - (int) scrollAmount;
        rowY += renderShardsHeader(guiGraphics, rowY, alpha);

        if (milestones.isEmpty()) {
            int textY = rowY + 6;
            for (var line : font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.none"), width - 8)) {
                guiGraphics.drawString(font, line, x + 4, textY, withAlpha(DIM_COLOR, alpha));
                textY += 10;
            }
        } else if (target == null && teaser == null) {
            // Ladder exhausted: every demanded offering has been made.
            int textY = rowY + 6;
            for (var line : font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.complete"), width - 8)) {
                guiGraphics.drawString(font, line, x + 4, textY, withAlpha(EclipseUiTheme.GOOD & 0xFFFFFF, alpha));
                textY += 10;
            }
        } else {
            if (target != null) {
                renderTargetRow(guiGraphics, target, rowY, alpha);
                rowY += ROW_HEIGHT;
            }
            if (teaser != null) {
                renderTeaserRow(guiGraphics, teaser, rowY, alpha);
            }
        }
        guiGraphics.disableScissor();

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    /**
     * D14: personal Umbral-Splitter block — balance (right-aligned, accent) from the
     * sidebar cache, the earn-lane list, then the TEAM-pool distinction in dim text.
     * Returns the block height consumed (also counted by {@link #contentHeight()}).
     */
    private int renderShardsHeader(GuiGraphics guiGraphics, int rowY, float alpha) {
        int rowWidth = width - SCROLLBAR_INSET;
        int headerHeight = shardsHeaderHeight();

        guiGraphics.fill(x, rowY, x + rowWidth, rowY + headerHeight - 4,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        guiGraphics.fill(x, rowY, x + 2, rowY + headerHeight - 4, withAlpha(ACCENT_COLOR, alpha));

        guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.handbook.rewards.shards.title"),
                x + 6, rowY + 4, withAlpha(TEXT_COLOR, alpha));
        String balance = EclipseLang.trString("gui.eclipse.handbook.rewards.shards.balance",
                ClientStateCache.sidebarShards);
        guiGraphics.drawString(font, balance, x + rowWidth - font.width(balance) - 6, rowY + 4,
                withAlpha(ACCENT_COLOR, alpha));

        int textY = rowY + 16;
        for (var line : font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.shards.sources"),
                rowWidth - 12)) {
            guiGraphics.drawString(font, line, x + 6, textY, withAlpha(TEXT_COLOR, alpha));
            textY += 10;
        }
        for (var line : font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.shards.pool_label"),
                rowWidth - 12)) {
            guiGraphics.drawString(font, line, x + 6, textY, withAlpha(DIM_COLOR, alpha));
            textY += 10;
        }
        return headerHeight;
    }

    /** Wrap-aware height of the shard block (title row + wrapped source/pool lines + padding). */
    private int shardsHeaderHeight() {
        int textWidth = width - SCROLLBAR_INSET - 12;
        int lines = font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.shards.sources"), textWidth).size()
                + font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.shards.pool_label"), textWidth).size();
        return 16 + lines * 10 + 8;
    }

    /**
     * The tier the altar currently hungers for: the lowest revealed entry above
     * {@code altarLevel}, or {@code null} while the client caches disagree for a beat
     * (the server re-broadcasts the trimmed ladder within a second of a level change).
     */
    private static S2CMilestonesPayload.Entry currentTarget(List<S2CMilestonesPayload.Entry> milestones) {
        S2CMilestonesPayload.Entry target = null;
        for (S2CMilestonesPayload.Entry milestone : milestones) {
            if (milestone.revealed() && milestone.level() > ClientStateCache.altarLevel
                    && (target == null || milestone.level() < target.level())) {
                target = milestone;
            }
        }
        return target;
    }

    /** The anonymized next-tier stub the server ships alongside the target, or {@code null}. */
    private static S2CMilestonesPayload.Entry teaser(List<S2CMilestonesPayload.Entry> milestones) {
        for (S2CMilestonesPayload.Entry milestone : milestones) {
            if (!milestone.revealed()) {
                return milestone;
            }
        }
        return null;
    }

    /** The hungering tier: full costs + grants, accent edge — the one actionable row. */
    private void renderTargetRow(GuiGraphics guiGraphics, S2CMilestonesPayload.Entry milestone,
            int rowY, float alpha) {
        int rowWidth = width - SCROLLBAR_INSET;

        guiGraphics.fill(x, rowY, x + rowWidth, rowY + ROW_HEIGHT - 4,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        guiGraphics.fill(x, rowY, x + 2, rowY + ROW_HEIGHT - 4, withAlpha(ACCENT_COLOR, alpha));

        guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.handbook.rewards.level", milestone.level()),
                x + 6, rowY + 4, withAlpha(TEXT_COLOR, alpha));

        String state = EclipseLang.trString("gui.eclipse.handbook.rewards.current");
        guiGraphics.drawString(font, state, x + rowWidth - font.width(state) - 6, rowY + 4,
                withAlpha(ACCENT_COLOR, alpha));

        // Offering costs as item icons with counts (icons skipped mid-crossfade: item
        // rendering ignores alpha and would burn opaque through the fade).
        String costLabel = EclipseLang.trString("gui.eclipse.handbook.rewards.cost");
        guiGraphics.drawString(font, costLabel, x + 6, rowY + 17, withAlpha(DIM_COLOR, alpha));
        if (alpha >= 0.5F) {
            renderCosts(guiGraphics, milestone.costs(), x + 6 + font.width(costLabel) + 4,
                    x + rowWidth - 6, rowY, alpha);
        }

        // Granted unlock keys as short names.
        StringBuilder grants = new StringBuilder();
        for (String key : milestone.rewards()) {
            if (grants.length() > 0) {
                grants.append(", ");
            }
            String shortKey = "gui.eclipse.handbook.rewards.key." + key;
            grants.append(EclipseLang.hasKey(shortKey) ? EclipseLang.trString(shortKey) : key);
        }
        if (grants.length() > 0) {
            String line = EclipseLang.trString("gui.eclipse.handbook.rewards.grants", grants.toString());
            guiGraphics.drawString(font, ellipsize(font, line, rowWidth - 12), x + 6, rowY + 33,
                    withAlpha(TEXT_COLOR, alpha));
        }
    }

    /** The "???" teaser: glitched header, sealed state, a single flavor line — no data. */
    private void renderTeaserRow(GuiGraphics guiGraphics, S2CMilestonesPayload.Entry milestone,
            int rowY, float alpha) {
        int rowWidth = width - SCROLLBAR_INSET;

        guiGraphics.fill(x, rowY, x + rowWidth, rowY + ROW_HEIGHT - 4,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));

        guiGraphics.drawString(font, GlitchText.unknown(milestone.level()),
                x + 6, rowY + 4, withAlpha(DIM_COLOR, alpha));

        String state = EclipseLang.trString("gui.eclipse.handbook.rewards.locked");
        guiGraphics.drawString(font, state, x + rowWidth - font.width(state) - 6, rowY + 4,
                withAlpha(DIM_COLOR, alpha));

        String flavor = EclipseLang.trString("gui.eclipse.handbook.rewards.tease");
        guiGraphics.drawString(font, ellipsize(font, flavor, rowWidth - 12), x + 6, rowY + 17,
                withAlpha(DIM_COLOR, alpha));
    }

    private void renderCosts(GuiGraphics guiGraphics, List<S2CMilestonesPayload.Cost> costs,
            int startX, int itemRight, int rowY, float alpha) {
        int itemX = startX;
        for (int i = 0; i < costs.size(); i++) {
            // Cap the row before an icon spills past the right edge: the first icon that no
            // longer fits (or would leave no room for the marker of those after it) becomes
            // a "+N" overflow marker instead of getting chopped by the scissor.
            boolean more = i + 1 < costs.size();
            if (itemX + 16 > itemRight
                    || (more && itemX + 22 + font.width("+" + (costs.size() - i - 1)) > itemRight)) {
                guiGraphics.drawString(font, "+" + (costs.size() - i), itemX, rowY + 17,
                        withAlpha(DIM_COLOR, alpha));
                break;
            }
            S2CMilestonesPayload.Cost cost = costs.get(i);
            ItemStack stack = new ItemStack(resolveItem(cost.item()), Math.max(1, cost.count()));
            guiGraphics.renderItem(stack, itemX, rowY + 13);
            guiGraphics.renderItemDecorations(font, stack, itemX, rowY + 13, String.valueOf(cost.count()));
            itemX += 22;
        }
    }

    private static Item resolveItem(String id) {
        ResourceLocation location = ResourceLocation.tryParse(id);
        if (location == null) {
            return Items.BARRIER;
        }
        return BuiltInRegistries.ITEM.getOptional(location).orElse(Items.BARRIER);
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
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * ROW_HEIGHT / 2, 0.0D, maxScroll());
            return true;
        }
        return false;
    }

    private int contentHeight() {
        List<S2CMilestonesPayload.Entry> milestones = ClientStateCache.milestones;
        int rows = (currentTarget(milestones) != null ? 1 : 0) + (teaser(milestones) != null ? 1 : 0);
        int base = shardsHeaderHeight() + 4;
        if (rows == 0) {
            // Empty/none/complete states: header + the wrapped info text below it.
            String key = milestones.isEmpty()
                    ? "gui.eclipse.handbook.rewards.none" : "gui.eclipse.handbook.rewards.complete";
            return base + 6 + font.split(EclipseLang.tr(key), width - 8).size() * 10;
        }
        return base + rows * ROW_HEIGHT;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
