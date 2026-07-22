package dev.projecteclipse.eclipse.economy;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.hearts.HeartsService;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.UseAnim;
import net.minecraft.world.level.Level;

/**
 * Vitae Shard (spec §4, 12 shards): the only permanent-heart source besides the revive
 * ritual. Hold use for {@value #USE_DURATION_TICKS} ticks to crush it — +1 heart via
 * {@link LivesApi#add}, hard-capped at {@link HeartsService#MAX_HEARTS}. Consumption
 * plays the totem sound + burst. Players already at the cap cannot start using it.
 */
public class VitaeShardItem extends Item {
    private static final int USE_DURATION_TICKS = 32;

    public VitaeShardItem(Properties properties) {
        super(properties);
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (player instanceof ServerPlayer serverPlayer && LivesApi.get(serverPlayer) >= HeartsService.MAX_HEARTS) {
            serverPlayer.displayClientMessage(Component.translatable("item.eclipse.vitae_shard.full"), true);
            serverPlayer.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.PLAYERS, 0.5F, 0.8F);
            return InteractionResultHolder.fail(stack);
        }
        player.startUsingItem(hand);
        return InteractionResultHolder.consume(stack);
    }

    @Override
    public ItemStack finishUsingItem(ItemStack stack, Level level, LivingEntity entity) {
        if (!(entity instanceof ServerPlayer player) || !(level instanceof ServerLevel serverLevel)) {
            return stack;
        }
        if (LivesApi.get(player) >= HeartsService.MAX_HEARTS) {
            // Cap reached mid-use (e.g. a kill credited a heart) — refuse without consuming.
            player.displayClientMessage(Component.translatable("item.eclipse.vitae_shard.full"), true);
            return stack;
        }
        int hearts = LivesApi.add(player, 1);
        stack.shrink(1);
        serverLevel.playSound(null, player.blockPosition(), SoundEvents.TOTEM_USE, SoundSource.PLAYERS, 0.8F, 1.2F);
        serverLevel.sendParticles(ParticleTypes.TOTEM_OF_UNDYING,
                player.getX(), player.getY() + 1.0D, player.getZ(), 40, 0.4D, 0.6D, 0.4D, 0.25D);
        player.displayClientMessage(Component.translatable("item.eclipse.vitae_shard.used", hearts), true);
        EclipseMod.LOGGER.info("{} crushed a vitae shard ({} hearts now)", player.getScoreboardName(), hearts);
        return stack;
    }

    @Override
    public int getUseDuration(ItemStack stack, LivingEntity entity) {
        return USE_DURATION_TICKS;
    }

    @Override
    public UseAnim getUseAnimation(ItemStack stack) {
        // Raised-to-the-sky hold (the horn pose) — reads as "offering the shard upward".
        return UseAnim.TOOT_HORN;
    }
}
