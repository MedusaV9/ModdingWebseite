package de.sonic0810.goobymod.item;

import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;

/** Plain Gooby item with one localized usage hint. */
public final class GoobyTooltipItem extends Item {
    private final String tooltipKey;

    public GoobyTooltipItem(Properties properties, String tooltipKey) {
        super(properties);
        this.tooltipKey = tooltipKey;
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable(this.tooltipKey).withStyle(ChatFormatting.GRAY));
    }
}
