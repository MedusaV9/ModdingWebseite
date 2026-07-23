package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;

/**
 * The Herald's Lure — summon item for the day-7 boss (spec §2.1; crafted from 4 umbral
 * shards + 1 heart fragment, {@code data/eclipse/recipe/heralds_lure.json}).
 * Sneak-right-clicking the altar with it after dusk consumes one lure and summons the
 * Herald {@value HeraldEntity#SUMMON_HEIGHT} blocks above the sanctum center.
 *
 * <p>Same routing trick as {@link ReviveSigilItem}: vanilla skips block interaction while
 * sneaking with an item in hand, so this {@link #useOn} IS the sneak path. Non-sneak
 * clicks land in {@code AltarBlock#useItemOn} → milestone deposit, which special-cases the
 * lure into an action-bar hint instead of "wrong item".</p>
 */
public class HeraldsLureItem extends Item {
    public HeraldsLureItem(Properties properties) {
        super(properties);
    }

    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        if (!(level.getBlockEntity(context.getClickedPos()) instanceof AltarBlockEntity)) {
            return InteractionResult.PASS;
        }
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(context.getPlayer() instanceof ServerPlayer player) || !(level instanceof ServerLevel serverLevel)) {
            return InteractionResult.PASS;
        }
        if (!context.isSecondaryUseActive()) {
            // Unreachable through vanilla flow (AltarBlock consumes non-sneak clicks); kept for safety.
            actionBar(player, Component.translatable("ritual.eclipse.lure.sneak_hint"));
            return InteractionResult.CONSUME;
        }
        BlockPos altarPos = context.getClickedPos();
        if (serverLevel.isDay()) {
            actionBar(player, Component.translatable("ritual.eclipse.lure.day"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
            return InteractionResult.CONSUME;
        }
        boolean heraldNearby = !serverLevel.getEntitiesOfClass(HeraldEntity.class,
                new AABB(altarPos).inflate(64.0D)).isEmpty();
        if (heraldNearby) {
            actionBar(player, Component.translatable("ritual.eclipse.lure.already"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return InteractionResult.CONSUME;
        }
        context.getItemInHand().shrink(1);
        // Arena floor: the sanctum dais ground sits ALTAR_ABOVE_GROUND below the altar block.
        int groundY = altarPos.getY()
                - dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        HeraldEntity.summon(serverLevel, altarPos, groundY);
        GoalTracker.onHeraldSummoned(player.server); // day-7 "Summon the Herald at dusk" auto-tick
        actionBar(player, Component.translatable("ritual.eclipse.lure.summoned"));
        dev.projecteclipse.eclipse.EclipseMod.LOGGER.info("{} deposited a Herald's Lure at {} — Herald summoned",
                player.getScoreboardName(), altarPos.toShortString());
        return InteractionResult.CONSUME;
    }

    private static void actionBar(ServerPlayer player, Component message) {
        player.displayClientMessage(message, true);
    }
}
