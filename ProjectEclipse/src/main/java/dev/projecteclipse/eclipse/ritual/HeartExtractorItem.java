package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.lang.ServerLang;
import dev.projecteclipse.eclipse.core.state.LivesApi;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.network.S2CHeartBurstPayload;
import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.UseAnim;
import net.minecraft.world.level.Level;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.fml.loading.FMLEnvironment;
import net.neoforged.neoforge.network.PacketDistributor;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.constant.DataTickets;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Heart Extractor (R8): channel for roughly three seconds, then permanently tear out two
 * max hearts in exchange for four heart fragments. The finish-time guard is authoritative:
 * a player can never be reduced below one max heart even if their heart count changes while
 * channeling.
 *
 * <p><b>GeckoLib (PLAN-ITEMS A3):</b> a geo item (brass-and-glass heart-tap,
 * {@code geo/item/heart_extractor.geo.json}) on the wand controller idiom. The
 * {@code base} controller swaps between the {@code idle} loop (chamber-glow breathing)
 * and the {@value #ANIM_CHANNEL} loop — a ~3 s plunger draw matching
 * {@value #USE_DURATION_TICKS} ticks — driven by a CLIENT-side
 * {@code LivingEntity#isUsingItem} check on the rendered stack (the fully-qualified
 * {@code client/item/HeartExtractorRenderer} reference never loads on a dedicated
 * server: the predicate only runs while rendering). The {@code action} controller holds
 * the triggerable {@value #ANIM_EXTRACT} (snap-finish, fired from
 * {@link #finishUsingItem}) and {@value #ANIM_REFUSE} (shake, fired from the existing
 * {@code refuse()} path). The vanilla {@link UseAnim#SPEAR} arm pose is kept.</p>
 */
public class HeartExtractorItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/heart_extractor.geo.json}, {@code animation.heart_extractor.*}). */
    public static final String GEO_ID = "heart_extractor";
    /** Base-controller loop while the holder channels (plunger draw over ~3 s). */
    public static final String ANIM_CHANNEL = "channel";
    public static final String ANIM_EXTRACT = "extract";
    public static final String ANIM_REFUSE = "refuse";
    /**
     * Triggerable one-shot on the {@code action} controller: the draw flourish.
     * Fired CLIENT-side only, by {@code client/item/ItemsAClientExtensions} — drawing an
     * item is cosmetic, so it never travels over the wire.
     */
    public static final String ANIM_EQUIP = "equip";

    /** Hold duration in ticks (60t = 3 s). */
    public static final int USE_DURATION_TICKS = 60;
    public static final int HEART_COST = 2;
    public static final int FRAGMENT_REWARD = 4;
    public static final int MIN_REMAINING_HEARTS = 1;

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public HeartExtractorItem(Properties properties) {
        super(properties);
        // Required for server-side triggerAnim() to reach tracking clients.
        SingletonGeoAnimatable.registerSyncedAnimatable(this);
    }

    // ------------------------------------------------------------------ GeckoLib

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return geoCache;
    }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 4, state -> {
            ItemStack stack = state.getData(DataTickets.ITEMSTACK);
            if (FMLEnvironment.dist == Dist.CLIENT && stack != null
                    // Lazy fully-qualified client reference (FxPayloads pattern) — the
                    // predicate only executes while a client renders the item.
                    && dev.projecteclipse.eclipse.client.item.HeartExtractorRenderer.isClientChanneling(stack)) {
                return state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, ANIM_CHANNEL));
            }
            return state.setAndContinue(EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE));
        }));
        AnimationController<HeartExtractorItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_EXTRACT, EclipseGeoAnimations.once(GEO_ID, ANIM_EXTRACT));
        action.triggerableAnim(ANIM_REFUSE, EclipseGeoAnimations.once(GEO_ID, ANIM_REFUSE));
        action.triggerableAnim(ANIM_EQUIP, EclipseGeoAnimations.once(GEO_ID, ANIM_EQUIP));
        controllers.add(action);
    }

    /** Server-side one-shot on the {@code action} controller, synced to tracking clients. */
    private static void triggerExtractorAnim(ServerPlayer player, ItemStack stack, String animName) {
        if (stack.getItem() instanceof HeartExtractorItem extractor) {
            long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
            extractor.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, animName);
        }
    }

    /** Pure gate used by the item and revive gametests. */
    public static boolean canExtract(int hearts) {
        return hearts - HEART_COST >= MIN_REMAINING_HEARTS;
    }

    /** Pure result math; callers must check {@link #canExtract(int)} first. */
    public static int heartsAfterExtraction(int hearts) {
        return hearts - HEART_COST;
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (player instanceof ServerPlayer serverPlayer && !canExtract(LivesApi.get(serverPlayer))) {
            refuse(serverPlayer, stack);
            return InteractionResultHolder.fail(stack);
        }
        player.startUsingItem(hand);
        return InteractionResultHolder.consume(stack);
    }

    @Override
    public int getUseDuration(ItemStack stack, LivingEntity entity) {
        return USE_DURATION_TICKS;
    }

    @Override
    public UseAnim getUseAnimation(ItemStack stack) {
        return UseAnim.SPEAR;
    }

    @Override
    public ItemStack finishUsingItem(ItemStack stack, Level level, LivingEntity entity) {
        if (!(entity instanceof ServerPlayer player) || !(level instanceof ServerLevel serverLevel)) {
            return stack;
        }

        int heartsBefore = LivesApi.get(player);
        if (!canExtract(heartsBefore)) {
            // Re-check after the channel: deaths/admin changes during those three seconds must
            // never let the extractor cross the one-heart safety floor.
            refuse(player, stack);
            return stack;
        }
        triggerExtractorAnim(player, stack, ANIM_EXTRACT);

        int heartsAfter = LivesApi.add(player, -HEART_COST);
        dev.projecteclipse.eclipse.drama.WitnessedLossService.onHeartLost(player);
        ItemStack fragments = new ItemStack(EclipseItems.HEART_FRAGMENT.get(), FRAGMENT_REWARD);
        player.getInventory().add(fragments);
        if (!fragments.isEmpty()) {
            player.drop(fragments, false);
        }

        EquipmentSlot slot = player.getUsedItemHand() == InteractionHand.OFF_HAND
                ? EquipmentSlot.OFFHAND : EquipmentSlot.MAINHAND;
        stack.hurtAndBreak(1, player, slot);

        // A damage-status packet gives the red flash without applying another damage point:
        // a successful 3 -> 1 heart extraction must not immediately kill the player.
        serverLevel.broadcastEntityEvent(player, (byte) 2);
        serverLevel.playSound(null, player.blockPosition(), EclipseSounds.RITUAL_EXTRACT.get(),
                SoundSource.PLAYERS, 1.25F, 0.72F);
        serverLevel.playSound(null, player.blockPosition(), SoundEvents.WARDEN_HEARTBEAT,
                SoundSource.PLAYERS, 1.0F, 0.58F);
        serverLevel.playSound(null, player.blockPosition(), SoundEvents.PLAYER_HURT,
                SoundSource.PLAYERS, 0.9F, 0.72F);
        serverLevel.sendParticles(ParticleTypes.DAMAGE_INDICATOR,
                player.getX(), player.getY() + 1.0D, player.getZ(),
                14, 0.35D, 0.5D, 0.35D, 0.12D);
        serverLevel.sendParticles(ParticleTypes.CRIMSON_SPORE,
                player.getX(), player.getY() + 1.0D, player.getZ(),
                34, 0.45D, 0.65D, 0.45D, 0.02D);
        serverLevel.sendParticles(ParticleTypes.PORTAL,
                player.getX(), player.getY() + 1.0D, player.getZ(),
                24, 0.4D, 0.55D, 0.4D, 0.18D);

        player.addEffect(new MobEffectInstance(MobEffects.MOVEMENT_SLOWDOWN, 10 * 20, 1, false, false));
        player.addEffect(new MobEffectInstance(MobEffects.WEAKNESS, 6 * 20, 0, false, false));
        // Both torn-out hearts shatter: HeartBurstOverlay's queue staggers them 8 t apart.
        PacketDistributor.sendToPlayer(player,
                new S2CHeartBurstPayload(heartsAfter),
                new S2CHeartBurstPayload(heartsAfter + 1));
        player.displayClientMessage(
                ServerLang.tr(player, "item.eclipse.heart_extractor.used", HEART_COST, heartsAfter), true);
        EclipseMod.LOGGER.info("{} used a heart extractor ({} -> {} hearts, {} fragments)",
                player.getScoreboardName(), heartsBefore, heartsAfter, FRAGMENT_REWARD);
        return stack;
    }

    private static void refuse(ServerPlayer player, ItemStack stack) {
        triggerExtractorAnim(player, stack, ANIM_REFUSE);
        player.displayClientMessage(ServerLang.tr(player, "item.eclipse.heart_extractor.too_few"), true);
        player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.PLAYERS, 0.6F, 0.65F);
    }
}
