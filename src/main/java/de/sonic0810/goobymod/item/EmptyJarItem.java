package de.sonic0810.goobymod.item;

import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;

/** Reusable vessel for Create's Spout-based Nutella production. */
public final class EmptyJarItem extends Item {
    public EmptyJarItem(Properties properties) {
        super(properties);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("tooltip.goobymod.empty_jar").withStyle(ChatFormatting.GRAY));
        tooltip.add(Component.translatable("tooltip.goobymod.empty_jar.create")
                .withStyle(ChatFormatting.DARK_GRAY));
    }
}
