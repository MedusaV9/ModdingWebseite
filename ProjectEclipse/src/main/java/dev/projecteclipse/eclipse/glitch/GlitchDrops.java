package dev.projecteclipse.eclipse.glitch;

import java.util.Optional;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.tags.TagKey;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.item.ItemEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.enchantment.Enchantment;
import net.minecraft.world.item.enchantment.EnchantmentHelper;
import net.minecraft.world.item.enchantment.Enchantments;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.living.LivingDropsEvent;

/** Adds config-driven glitch shards to every entity in {@code #eclipse:glitched}. */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GlitchDrops {
    public static final TagKey<EntityType<?>> GLITCHED = TagKey.create(
            Registries.ENTITY_TYPE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "glitched"));

    private GlitchDrops() {}

    @SubscribeEvent
    public static void onLivingDrops(LivingDropsEvent event) {
        GlitchConfig.Data config = GlitchConfig.get();
        if (!config.dropsEnabled()
                || !event.getEntity().getType().is(GLITCHED)
                || !(event.getEntity().level() instanceof ServerLevel level)) {
            return;
        }

        RandomSource random = level.getRandom();
        if (!shouldDrop(config.dropChance(), random.nextDouble())) {
            return;
        }

        int lootingLevel = event.getSource().getEntity() instanceof ServerPlayer player
                ? lootingLevel(level, player.getMainHandItem()) : 0;
        int count = rollDropCount(random, config.dropMin(), config.dropMax(),
                lootingLevel, config.lootingBonusMax());
        if (count <= 0) {
            return;
        }

        ItemEntity shardDrop = new ItemEntity(level,
                event.getEntity().getX(),
                event.getEntity().getY(),
                event.getEntity().getZ(),
                new ItemStack(EclipseItems.GLITCH_SHARD.get(), count));
        shardDrop.setDefaultPickUpDelay();
        event.getDrops().add(shardDrop);
    }

    /** Pure chance gate for gametests. */
    public static boolean shouldDrop(double chance, double roll) {
        return chance > 0.0D && roll < Math.min(1.0D, chance);
    }

    /**
     * Rolls {@code min..max}; any Looting level raises only the configured maximum (default
     * +1), matching the R9 balance contract.
     */
    public static int rollDropCount(RandomSource random, int min, int max,
            int lootingLevel, int lootingBonusMax) {
        int safeMin = Math.max(0, min);
        int safeMax = Math.max(safeMin, max);
        if (lootingLevel > 0) {
            safeMax += Math.max(0, lootingBonusMax);
        }
        return safeMin + random.nextInt(safeMax - safeMin + 1);
    }

    private static int lootingLevel(ServerLevel level, ItemStack weapon) {
        Optional<Holder.Reference<Enchantment>> holder = level.registryAccess()
                .registryOrThrow(Registries.ENCHANTMENT)
                .getHolder(Enchantments.LOOTING);
        return holder.map(enchantment ->
                EnchantmentHelper.getItemEnchantmentLevel(enchantment, weapon)).orElse(0);
    }
}
