package de.sonic0810.goobymod.item;

import de.sonic0810.goobymod.block.NutellaCakeBlock;
import de.sonic0810.goobymod.registry.ModBlocks;
import de.sonic0810.goobymod.registry.ModItems;
import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;

/** Placeable Nutella jar with the special cake-preparation interaction. */
public final class NutellaItem extends BlockItem {
    public NutellaItem(Properties properties) {
        super(ModBlocks.NUTELLA_JAR.get(), properties);
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("tooltip.goobymod.nutella").withStyle(ChatFormatting.GRAY));
        tooltip.add(Component.translatable("tooltip.goobymod.nutella.cake")
                .withStyle(ChatFormatting.DARK_GRAY));
    }

    // Das Glas ist ein wiederverwendbarer Container (Create-Spout befuellt
    // leere Glaeser): Crafting-Rezepte wie der Nutella-Toast geben es zurueck.
    // Betrifft NUR das Craften — Platzieren und Kuchen-Bestreichen verbrauchen
    // das Glas weiterhin komplett.
    @Override
    public boolean hasCraftingRemainingItem(ItemStack stack) {
        return true;
    }

    @Override
    public ItemStack getCraftingRemainingItem(ItemStack stack) {
        return new ItemStack(ModItems.EMPTY_JAR.get());
    }

    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        BlockPos pos = context.getClickedPos();
        if (!level.getBlockState(pos).is(Blocks.CAKE)) {
            return super.useOn(context);
        }
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }

        level.setBlock(pos, ModBlocks.NUTELLA_CAKE.get().defaultBlockState(), 3);
        if (context.getPlayer() == null || !context.getPlayer().getAbilities().instabuild) {
            context.getItemInHand().shrink(1);
        }
        if (level instanceof ServerLevel serverLevel) {
            serverLevel.sendParticles(ParticleTypes.HEART,
                    pos.getX() + 0.5, pos.getY() + 0.65, pos.getZ() + 0.5,
                    8, 0.45, 0.2, 0.45, 0.03);
            serverLevel.playSound(null, pos, SoundEvents.HONEY_BLOCK_PLACE,
                    SoundSource.BLOCKS, 0.8F, 1.15F);
            NutellaCakeBlock.tryRitual(serverLevel, pos, context.getPlayer());
        }
        return InteractionResult.CONSUME;
    }
}
