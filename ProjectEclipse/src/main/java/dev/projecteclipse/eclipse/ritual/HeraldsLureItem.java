package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.boss.HeraldEntity;
import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.progression.GoalTracker;
import dev.projecteclipse.eclipse.sequence.HeraldSummonSequence;
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
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * The Herald's Lure — summon item for the day-7 boss (spec §2.1; crafted from 4 umbral
 * shards + 1 heart fragment, {@code data/eclipse/recipe/heralds_lure.json}).
 * Sneak-right-clicking the altar with it on day {@value #HERALD_DAY}+ after dusk consumes
 * one lure and arms {@link HeraldSummonSequence} — the arrival cutscene that ends on the
 * Herald {@value HeraldEntity#SUMMON_HEIGHT} blocks above the sanctum center.
 *
 * <p>Same routing trick as {@link ReviveSigilItem}: vanilla skips block interaction while
 * sneaking with an item in hand, so this {@link #useOn} IS the sneak path. Non-sneak
 * clicks land in {@code AltarBlock#useItemOn} → milestone deposit, which special-cases the
 * lure into an action-bar hint instead of "wrong item".</p>
 *
 * <p>GeckoLib item (PLAN-ITEMS B2): obsidian shard prongs caging a heart-fragment core.
 * The {@code base} controller loops {@code animation.heralds_lure.idle} (core pulse +
 * prong counter-rotation); the {@code action} controller holds the triggerable
 * {@value #ANIM_OFFERING} one-shot (prongs open, core surges), fired below on the
 * altar-use success path right before the stack shrinks.</p>
 */
public class HeraldsLureItem extends Item implements GeoItem {
    /** First day the altar accepts the lure (the Herald is the day-7 boss; mirrors {@link FinaleRitual#FINALE_DAY}). */
    public static final int HERALD_DAY = 7;

    /** Asset/anim id ({@code geo/item/heralds_lure.geo.json}, {@code animation.heralds_lure.*}). */
    public static final String GEO_ID = "heralds_lure";

    /** Triggerable one-shot: prongs open + core surge when the altar accepts the offering. */
    public static final String ANIM_OFFERING = "offering";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public HeraldsLureItem(Properties properties) {
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
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE, 4,
                state -> state.setAndContinue(
                        EclipseGeoAnimations.loop(GEO_ID, EclipseGeoAnimations.ANIM_IDLE))));
        AnimationController<HeraldsLureItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_OFFERING, EclipseGeoAnimations.once(GEO_ID, ANIM_OFFERING));
        controllers.add(action);
    }

    // ------------------------------------------------------------------ interaction

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
        if (DayScheduler.getDay(player.server) < HERALD_DAY) {
            // An early summon would stamp heraldDefeated before day 7 and orphan the day-7 goal tick.
            actionBar(player, Component.translatable("ritual.eclipse.lure.early"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 0.8F);
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
        // F-053: an arrival already in flight has no boss to find yet, so the entity probe
        // above cannot see it — a second offering during the cutscene would burn a lure for
        // a summon the sequence refuses. Same rejection as a live Herald.
        if (heraldNearby || HeraldSummonSequence.isActive()) {
            actionBar(player, Component.translatable("ritual.eclipse.lure.already"));
            player.playNotifySound(SoundEvents.FIRE_EXTINGUISH, SoundSource.BLOCKS, 0.5F, 1.2F);
            return InteractionResult.CONSUME;
        }
        // Offering accepted: fire the one-shot before the stack shrinks so the surviving
        // stack (if any) plays it; GeckoLib syncs the trigger on its own channel.
        triggerAnim(player, GeoItem.getOrAssignId(context.getItemInHand(), serverLevel),
                EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_OFFERING);
        context.getItemInHand().shrink(1);
        // Arena floor: the sanctum dais ground sits ALTAR_ABOVE_GROUND below the altar block.
        int groundY = altarPos.getY()
                - dev.projecteclipse.eclipse.worldgen.structure.AltarSanctumBuilder.ALTAR_ABOVE_GROUND;
        // F-053: the offering opens the ARRIVAL, not the fight — HeraldSummonSequence runs
        // the announcement/column/ground-break beats and calls HeraldEntity.summon itself at
        // its spawn beat. Identical to what /dev event start herold previews.
        HeraldSummonSequence.begin(serverLevel, altarPos, groundY);
        GoalTracker.onHeraldSummoned(player.server); // day-7 "Summon the Herald at dusk" auto-tick
        actionBar(player, Component.translatable("ritual.eclipse.lure.summoned"));
        dev.projecteclipse.eclipse.EclipseMod.LOGGER.info("{} deposited a Herald's Lure at {} — arrival cutscene armed",
                player.getScoreboardName(), altarPos.toShortString());
        return InteractionResult.CONSUME;
    }

    private static void actionBar(ServerPlayer player, Component message) {
        player.displayClientMessage(message, true);
    }
}
