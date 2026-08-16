package de.sonic0810.goobymod.item;

import java.util.List;
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.food.FoodProperties;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.Level;

/**
 * Nutella-Toast: knuspriges Brot mit einer dicken Nutella-Schicht.
 * Saettigt fast wie ein Goldapfel-Fruehstueck und schenkt einen kurzen
 * Zuckerschub (Schnelligkeit I).
 */
public final class NutellaToastItem extends Item {
    /** 7 Hunger / 9.1 Saettigung — zwischen Brot (5/6.0) und Goldkarotte (6/14.4). */
    public static final FoodProperties FOOD = new FoodProperties.Builder()
            .nutrition(7)
            .saturationModifier(0.65F)
            .effect(() -> new MobEffectInstance(MobEffects.MOVEMENT_SPEED, 200, 0), 1.0F)
            .build();

    public NutellaToastItem(Properties properties) {
        super(properties.food(FOOD));
    }

    @Override
    public void appendHoverText(ItemStack stack, TooltipContext context, List<Component> tooltip,
            TooltipFlag flag) {
        tooltip.add(Component.translatable("tooltip.goobymod.nutella_toast")
                .withStyle(ChatFormatting.GRAY));
    }

    @Override
    public ItemStack finishUsingItem(ItemStack stack, Level level, LivingEntity entity) {
        // Zuckerschub-Funken beim letzten Bissen — rein kosmetisch.
        if (level instanceof net.minecraft.server.level.ServerLevel serverLevel) {
            serverLevel.sendParticles(net.minecraft.core.particles.ParticleTypes.HAPPY_VILLAGER,
                    entity.getX(), entity.getEyeY(), entity.getZ(), 4, 0.3, 0.25, 0.3, 0.01);
        }
        return super.finishUsingItem(stack, level, entity);
    }
}
