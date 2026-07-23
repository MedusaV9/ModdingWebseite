package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.client.handbook.EclipseUiTheme;
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
 * Rewards page, Quiet Eclipse v3 (plans_v3 P3 §3.1): the altar milestone ladder from
 * {@code ClientStateCache.milestones} as flat raised rows. Each row shows the level, its
 * state relative to {@code ClientStateCache.altarLevel} (sated / hungering / sealed — the
 * "hungering" next milestone keeps its 2px accent edge, sated states read in
 * {@link EclipseUiTheme#GOOD}), the offering costs as real item icons and the granted
 * unlock keys as short names. The B7 fix: the list now scrolls with the shared
 * {@link TabScrollbar} + vertical content drag, so the affordance is always visible;
 * presses are only consumed while something can actually scroll (B20 rule).
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
        scrollAmount = Mth.clamp(scrollAmount, 0.0D, maxScroll());
        if (milestones.isEmpty()) {
            int textY = y + 12;
            for (var line : font.split(EclipseLang.tr("gui.eclipse.handbook.rewards.none"), width - 8)) {
                guiGraphics.drawString(font, line, x + 4, textY, withAlpha(DIM_COLOR, alpha));
                textY += 10;
            }
            return;
        }

        int altarLevel = ClientStateCache.altarLevel;
        guiGraphics.enableScissor(x, y, x + width, y + height);
        int rowY = y + 2 - (int) scrollAmount;
        for (S2CMilestonesPayload.Entry milestone : milestones) {
            if (rowY > y - ROW_HEIGHT && rowY < y + height) {
                renderRow(guiGraphics, milestone, altarLevel, rowY, alpha);
            }
            rowY += ROW_HEIGHT;
        }
        guiGraphics.disableScissor();

        scrollbar.layout(x + width, y + 2, height - 4);
        scrollbar.size(height, contentHeight());
        scrollbar.render(guiGraphics, scrollAmount, alpha);
    }

    private void renderRow(GuiGraphics guiGraphics, S2CMilestonesPayload.Entry milestone, int altarLevel,
            int rowY, float alpha) {
        boolean reached = milestone.level() <= altarLevel;
        boolean current = milestone.level() == altarLevel + 1;
        int rowWidth = width - SCROLLBAR_INSET;

        // Raised row card; the "hungering" (next) milestone keeps its accent edge.
        guiGraphics.fill(x, rowY, x + rowWidth, rowY + ROW_HEIGHT - 4,
                EclipseUiTheme.withAlpha(EclipseUiTheme.PANEL_RAISED, alpha));
        if (current) {
            guiGraphics.fill(x, rowY, x + 2, rowY + ROW_HEIGHT - 4, withAlpha(ACCENT_COLOR, alpha));
        }

        int headerColor = reached ? ACCENT_COLOR : current ? TEXT_COLOR : DIM_COLOR;
        guiGraphics.drawString(font, EclipseLang.tr("gui.eclipse.handbook.rewards.level", milestone.level()),
                x + 6, rowY + 4, withAlpha(headerColor, alpha));

        String stateKey = reached ? "gui.eclipse.handbook.rewards.reached"
                : current ? "gui.eclipse.handbook.rewards.current" : "gui.eclipse.handbook.rewards.locked";
        String state = EclipseLang.trString(stateKey);
        int stateColor = reached ? EclipseUiTheme.GOOD & 0xFFFFFF : current ? ACCENT_COLOR : DIM_COLOR;
        guiGraphics.drawString(font, state, x + rowWidth - font.width(state) - 6, rowY + 4,
                withAlpha(stateColor, alpha));

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
                    withAlpha(reached ? TEXT_COLOR : DIM_COLOR, alpha));
        }
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
        return ClientStateCache.milestones.size() * ROW_HEIGHT + 4;
    }

    private double maxScroll() {
        return Math.max(0, contentHeight() - height);
    }

    @Override
    public boolean dragging() {
        return dragging || scrollbar.dragging();
    }
}
