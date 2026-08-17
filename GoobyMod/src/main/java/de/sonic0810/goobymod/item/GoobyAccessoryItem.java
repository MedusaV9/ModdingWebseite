package de.sonic0810.goobymod.item;

import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;

/** Small cosmetic item with a localized usage hint. */
public final class GoobyAccessoryItem extends Item {
    private final String tooltipKey;

    public GoobyAccessoryItem(Properties properties, String tooltipKey) {
        super(properties);
        this.tooltipKey = tooltipKey;
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable(this.tooltipKey).withStyle(ChatFormatting.GRAY));
    }
}
