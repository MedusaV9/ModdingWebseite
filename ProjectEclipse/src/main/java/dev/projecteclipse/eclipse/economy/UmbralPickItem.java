package dev.projecteclipse.eclipse.economy;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.PickaxeItem;
import net.minecraft.world.item.Tier;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Umbral Pick (W13 shard shop, 12 shards): unchanged diamond-class {@link PickaxeItem}
 * gameplay — the +50 % break-speed buff under an open night sky still lives in
 * {@code ShardEconomy#onBreakSpeed} and keys off item identity.
 *
 * <p><b>GeckoLib (POLISH3, MD4 §9):</b> hand-3D geo
 * ({@code geo/item/umbral_pick.geo.json} — twin fore/aft prongs with dipping tips,
 * glow seams, moon gem, haft vein). {@code base} controller loops {@code idle}
 * (seam/gem breathing); the {@code action} controller holds the triggerable
 * {@value #ANIM_NIGHT_BITE} one-shot. 3D applies to HAND contexts only — the
 * {@code neoforge:separate_transforms} item model keeps gui/ground/fixed on the final
 * 2D pixel icon.</p>
 *
 * <p>{@value #ANIM_NIGHT_BITE} fires from {@link #mineBlock} (own class — no foreign
 * hook needed) exactly when the buff condition of {@code ShardEconomy} holds: night
 * plus sky access above the broken block. Throttled to the anim length so strip-mining
 * reads as a sustained sparkle instead of a packet-per-block re-trigger stutter.</p>
 */
public class UmbralPickItem extends PickaxeItem implements GeoItem {
    /** Asset/anim id ({@code geo/item/umbral_pick.geo.json}, {@code animation.umbral_pick.*}). */
    public static final String GEO_ID = "umbral_pick";
    /** Triggerable one-shot on the {@code action} controller: prong-tip sparkle. */
    public static final String ANIM_NIGHT_BITE = "night_bite";
    /** {@value #ANIM_NIGHT_BITE} is 0.5 s = 10 t; re-triggering faster only restarts it. */
    private static final int NIGHT_BITE_THROTTLE_TICKS = 10;

    /** Per-player last-trigger game time (server-side only; bounded by online players). */
    private static final Map<UUID, Long> LAST_BITE = new HashMap<>();

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public UmbralPickItem(Tier tier, Properties properties) {
        super(tier, properties);
        // Required for server-side triggerAnim() to reach tracking clients.
        SingletonGeoAnimatable.registerSyncedAnimatable(this);
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return geoCache;
    }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 4,
                state -> state.setAndContinue(
                        EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE))));
        AnimationController<UmbralPickItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_NIGHT_BITE, EclipseGeoAnimations.once(GEO_ID, ANIM_NIGHT_BITE));
        controllers.add(action);
    }

    @Override
    public boolean mineBlock(ItemStack stack, Level level, BlockState state, BlockPos pos,
            LivingEntity miner) {
        boolean result = super.mineBlock(stack, level, state, pos, miner);
        // Mirror of ShardEconomy#onBreakSpeed's buff gate — the sparkle only plays when
        // the +50% night bonus actually applied to this block.
        if (miner instanceof ServerPlayer player && level.isNight() && level.canSeeSky(pos.above())) {
            long now = level.getGameTime();
            Long last = LAST_BITE.get(player.getUUID());
            // 'now < last' guards against a fresh world with a smaller game time.
            if (last == null || now - last >= NIGHT_BITE_THROTTLE_TICKS || now < last) {
                LAST_BITE.put(player.getUUID(), now);
                long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
                triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_NIGHT_BITE);
            }
        }
        return result;
    }
}
