package de.sonic0810.goobymod.item;

import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;

/** A rare best-friend dig reward; four scraps restore a treasure map. */
public final class TornMapScrapItem extends Item {
    public TornMapScrapItem(Properties properties) {
        super(properties);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("lore.goobymod.torn_map_scrap.1").withStyle(ChatFormatting.GRAY));
        tooltip.add(Component.translatable("lore.goobymod.torn_map_scrap.2").withStyle(ChatFormatting.DARK_GRAY));
    }
}
