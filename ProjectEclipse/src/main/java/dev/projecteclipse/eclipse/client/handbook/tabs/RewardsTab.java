package dev.projecteclipse.eclipse.client.handbook.tabs;

import java.util.List;

import dev.projecteclipse.eclipse.client.ClientStateCache;
import dev.projecteclipse.eclipse.network.S2CMilestonesPayload;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.client.resources.language.I18n;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.Mth;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.api.distmarker.OnlyIn;

/**
 * Rewards page: the altar milestone ladder from {@code ClientStateCache.milestones}
 * (synced by {@link S2CMilestonesPayload} at login and on {@code /eclipse reload}). Each
 * row shows the level, its state relative to {@code ClientStateCache.altarLevel} (sated /
 * hungering / sealed), the offering costs as real item icons
 * ({@code guiGraphics.renderItem} + count decorations) and the granted unlock keys
 * (short names via {@code gui.eclipse.handbook.rewards.key.<key>} where shipped).
 */
@OnlyIn(Dist.CLIENT)
public class RewardsTab extends HandbookTab {
    private static final int ROW_HEIGHT = 46;

    private double scrollAmount;

    @Override
    public String id() {
        return "rewards";
    }

    @Override
    public void render(GuiGraphics guiGraphics, int mouseX, int mouseY, float partialTick, float alpha) {
        if (alpha < 0.1F) {
            return;
        }
        List<S2CMilestonesPayload.Entry> milestones = ClientStateCache.milestones;
        if (milestones.isEmpty()) {
            int textY = y + 12;
            for (var line : font.split(Component.translatable("gui.eclipse.handbook.rewards.none"), width - 8)) {
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
    }

    private void renderRow(GuiGraphics guiGraphics, S2CMilestonesPayload.Entry milestone, int altarLevel,
            int rowY, float alpha) {
        boolean reached = milestone.level() <= altarLevel;
        boolean current = milestone.level() == altarLevel + 1;

        // Row backdrop; the "hungering" (next) milestone gets an accent border.
        guiGraphics.fill(x, rowY, x + width, rowY + ROW_HEIGHT - 4, withAlpha(0x1A1028, alpha * 0.75F));
        if (current) {
            guiGraphics.fill(x, rowY, x + 2, rowY + ROW_HEIGHT - 4, withAlpha(ACCENT_COLOR, alpha));
        }

        int headerColor = reached ? ACCENT_COLOR : current ? TEXT_COLOR : DIM_COLOR;
        guiGraphics.drawString(font, Component.translatable("gui.eclipse.handbook.rewards.level", milestone.level()),
                x + 6, rowY + 4, withAlpha(headerColor, alpha));

        String stateKey = reached ? "gui.eclipse.handbook.rewards.reached"
                : current ? "gui.eclipse.handbook.rewards.current" : "gui.eclipse.handbook.rewards.locked";
        Component state = Component.translatable(stateKey);
        guiGraphics.drawString(font, state, x + width - font.width(state) - 6, rowY + 4,
                withAlpha(reached ? ACCENT_COLOR : DIM_COLOR, alpha));

        // Offering costs as item icons with counts.
        guiGraphics.drawString(font, Component.translatable("gui.eclipse.handbook.rewards.cost"),
                x + 6, rowY + 17, withAlpha(DIM_COLOR, alpha));
        int itemX = x + 6 + font.width(Component.translatable("gui.eclipse.handbook.rewards.cost")) + 4;
        List<S2CMilestonesPayload.Cost> costs = milestone.costs();
        int itemRight = x + width - 6;
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

        // Granted unlock keys as short names.
        StringBuilder grants = new StringBuilder();
        for (String key : milestone.rewards()) {
            if (grants.length() > 0) {
                grants.append(", ");
            }
            String shortKey = "gui.eclipse.handbook.rewards.key." + key;
            grants.append(I18n.exists(shortKey) ? I18n.get(shortKey) : key);
        }
        if (grants.length() > 0) {
            Component line = Component.translatable("gui.eclipse.handbook.rewards.grants",
                    grants.toString());
            guiGraphics.drawString(font, font.split(line, width - 12).get(0), x + 6, rowY + 33,
                    withAlpha(reached ? TEXT_COLOR : DIM_COLOR, alpha));
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
    public boolean mouseScrolled(double mouseX, double mouseY, double scrollXDelta, double scrollYDelta) {
        if (inRect(mouseX, mouseY)) {
            scrollAmount = Mth.clamp(scrollAmount - scrollYDelta * ROW_HEIGHT / 2,
                    0.0D, Math.max(0, ClientStateCache.milestones.size() * ROW_HEIGHT + 4 - height));
            return true;
        }
        return false;
    }
}
