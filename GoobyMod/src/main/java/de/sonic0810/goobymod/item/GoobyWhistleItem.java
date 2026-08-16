package de.sonic0810.goobymod.item;

import de.sonic0810.goobymod.entity.GoobyCommand;
import de.sonic0810.goobymod.entity.GoobyEntity;
import de.sonic0810.goobymod.registry.ModSounds;
import java.util.List;
import javax.annotation.Nullable;
import net.minecraft.ChatFormatting;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.item.component.CustomData;
import net.minecraft.world.level.Level;

/** Whistle 2.0: entity commands, air-call, trick menu, and a remembered mode tooltip. */
public final class GoobyWhistleItem extends Item {
    private static final String MODE_TAG = "GoobyCommandMode";

    public GoobyWhistleItem(Properties properties) {
        super(properties);
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (!level.isClientSide) {
            GoobyEntity nearest = findNearestOwned(player);
            if (nearest == null) {
                player.displayClientMessage(Component.translatable("msg.goobymod.whistle_no_gooby"), true);
                level.playSound(null, player.blockPosition(), ModSounds.GOOBY_WHISTLE_DENIED.get(),
                        SoundSource.PLAYERS, 0.7F, 1.0F);
            } else if (player.isSecondaryUseActive()) {
                nearest.sendTrickMenu(player);
            } else {
                nearest.callToOwner(player);
                rememberMode(stack, nearest.getCommandMode());
            }
        }
        return InteractionResultHolder.sidedSuccess(stack, level.isClientSide);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        GoobyCommand mode = rememberedMode(stack);
        tooltip.add(Component.translatable("tooltip.goobymod.whistle.mode",
                Component.translatable(mode.nameTranslationKey())).withStyle(ChatFormatting.GRAY));
        tooltip.add(Component.translatable("tooltip.goobymod.whistle.air_call").withStyle(ChatFormatting.DARK_GRAY));
        tooltip.add(Component.translatable("tooltip.goobymod.whistle.trick_menu").withStyle(ChatFormatting.DARK_GRAY));
    }

    public static void rememberMode(ItemStack stack, GoobyCommand mode) {
        CustomData.update(DataComponents.CUSTOM_DATA, stack,
                tag -> tag.putByte(MODE_TAG, (byte) mode.ordinal()));
    }

    public static GoobyCommand rememberedMode(ItemStack stack) {
        CustomData data = stack.getOrDefault(DataComponents.CUSTOM_DATA, CustomData.EMPTY);
        return GoobyCommand.byId(data.copyTag().getByte(MODE_TAG));
    }

    @Nullable
    public static GoobyEntity findNearestOwned(Player player) {
        if (!(player.level() instanceof ServerLevel level)) {
            return null;
        }
        GoobyEntity nearest = null;
        double nearestDistance = Double.MAX_VALUE;
        for (var entity : level.getAllEntities()) {
            if (entity instanceof GoobyEntity gooby && !gooby.isBaby() && gooby.isOwnedBy(player)) {
                double distance = player.distanceToSqr(gooby);
                if (distance < nearestDistance) {
                    nearest = gooby;
                    nearestDistance = distance;
                }
            }
        }
        return nearest;
    }
}
