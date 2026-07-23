package dev.projecteclipse.eclipse.enchant;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.enchantment.EnchantmentHelper;
import net.minecraft.world.item.enchantment.Enchantment;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.CropBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.BlockDropsEvent;

import java.util.Optional;

/**
 * Runtime effect for the data-driven {@code eclipse:replant} enchantment (fog-storm loot):
 * harvesting a fully-grown crop with an enchanted tool replants it in place by consuming
 * one seed item from the drops. Purely additive — without the enchantment the vanilla
 * break flow is untouched.
 */
@EventBusSubscriber(modid = "eclipse")
public final class ReplantEnchant {
    public static final ResourceKey<Enchantment> KEY =
            ResourceKey.create(Registries.ENCHANTMENT, ResourceLocation.fromNamespaceAndPath("eclipse", "replant"));

    private ReplantEnchant() {}

    @SubscribeEvent
    public static void onBlockDrops(BlockDropsEvent event) {
        if (!(event.getLevel() instanceof ServerLevel level) || !(event.getBreaker() instanceof ServerPlayer player)) {
            return;
        }
        BlockState state = event.getState();
        if (!(state.getBlock() instanceof CropBlock crop) || !crop.isMaxAge(state)) {
            return;
        }
        ItemStack tool = player.getMainHandItem();
        if (tool.isEmpty() || level(level, tool) <= 0) {
            return;
        }
        // Consume one seed item from the drops, then replant the crop at age 0.
        ItemStack seed = crop.getCloneItemStack(level, event.getPos(), state);
        if (seed.isEmpty()) {
            return;
        }
        for (ItemEntity drop : event.getDrops()) {
            ItemStack stack = drop.getItem();
            if (ItemStack.isSameItem(stack, seed) && stack.getCount() > 0) {
                stack.shrink(1);
                if (stack.isEmpty()) {
                    event.getDrops().remove(drop);
                }
                BlockPos pos = event.getPos();
                Block block = state.getBlock();
                level.getServer().execute(() -> {
                    if (level.getBlockState(pos).isAir()) {
                        level.setBlockAndUpdate(pos, block.defaultBlockState());
                    }
                });
                return;
            }
        }
    }

    private static int level(ServerLevel level, ItemStack stack) {
        Optional<Holder.Reference<Enchantment>> holder =
                level.registryAccess().registryOrThrow(Registries.ENCHANTMENT).getHolder(KEY);
        return holder.map(h -> EnchantmentHelper.getItemEnchantmentLevel(h, stack)).orElse(0);
    }
}
