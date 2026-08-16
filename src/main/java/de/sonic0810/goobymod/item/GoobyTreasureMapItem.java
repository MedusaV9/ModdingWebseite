package de.sonic0810.goobymod.item;

import de.sonic0810.goobymod.GoobyAdvancements;
import de.sonic0810.goobymod.registry.ModSounds;
import de.sonic0810.goobymod.registry.ModStructureTags;
import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.MapItem;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.saveddata.maps.MapDecorationTypes;
import net.minecraft.world.level.saveddata.maps.MapItemSavedData;

/**
 * Unfinished map that resolves once, on use, to the nearest Gooby treasure
 * cache. The locate operation therefore never runs in an inventory tick.
 */
public final class GoobyTreasureMapItem extends Item {
    private static final int LOCATE_RADIUS_CHUNKS = 100;

    public GoobyTreasureMapItem(Properties properties) {
        super(properties);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("tooltip.goobymod.treasure_map")
                .withStyle(ChatFormatting.GRAY));
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack scrapsMap = player.getItemInHand(hand);
        if (!(level instanceof ServerLevel serverLevel)) {
            return InteractionResultHolder.sidedSuccess(scrapsMap, true);
        }
        BlockPos cache = serverLevel.findNearestMapStructure(
                ModStructureTags.GOOBY_TREASURE_CACHES, player.blockPosition(), LOCATE_RADIUS_CHUNKS, true);
        if (cache == null) {
            player.displayClientMessage(Component.translatable("msg.goobymod.map_no_cache"), true);
            return InteractionResultHolder.fail(scrapsMap);
        }

        ItemStack filledMap = MapItem.create(serverLevel, cache.getX(), cache.getZ(), (byte) 2, true, true);
        MapItem.renderBiomePreviewMap(serverLevel, filledMap);
        MapItemSavedData.addTargetDecoration(filledMap, cache, "+", MapDecorationTypes.RED_X);
        filledMap.set(DataComponents.CUSTOM_NAME, Component.translatable("item.goobymod.gooby_treasure_map"));
        player.playSound(ModSounds.GOOBY_MAP_RUSTLE.get(), 0.8F, 1.0F);
        if (player instanceof net.minecraft.server.level.ServerPlayer serverPlayer) {
            GoobyAdvancements.grant(serverPlayer, GoobyAdvancements.TREASURE_MAP_COMPLETE);
        }

        if (!player.getAbilities().instabuild) {
            scrapsMap.shrink(1);
        }
        if (scrapsMap.isEmpty()) {
            player.setItemInHand(hand, filledMap);
            return InteractionResultHolder.sidedSuccess(filledMap, false);
        }
        if (!player.getInventory().add(filledMap)) {
            player.drop(filledMap, false);
        }
        return InteractionResultHolder.sidedSuccess(scrapsMap, false);
    }
}
