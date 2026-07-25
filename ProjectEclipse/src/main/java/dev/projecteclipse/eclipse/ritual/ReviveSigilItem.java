package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * The revive sigil. Non-sneak right-clicks on the altar are handled by
 * {@link AltarBlock#useItemOn} (cycle the selected banned player); this item's
 * {@link #useOn} only fires while sneaking, because vanilla skips block
 * interaction when the player is sneaking with an item in hand — that click
 * confirms the selection and starts the {@link ReviveRitual}.
 *
 * <p>GeckoLib item (PLAN-ITEMS B3): an octagonal rune tablet whose {@code base}
 * controller loops {@code animation.revive_sigil.idle} (glyph glow pulse + hover-bob);
 * the {@code action} controller holds the triggerable {@value #ANIM_RITUAL} one-shot
 * (tablet spins up and over-glows). The trigger fires from the confirm path below once
 * a {@link ReviveRitual} is live at the altar — the ritual's success boundary
 * ({@code ReviveRitual#consumeSigil}) lives outside this item, so ritual start is the
 * owned seam that matches "the altar accepts the sigil".</p>
 */
public class ReviveSigilItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/revive_sigil.geo.json}, {@code animation.revive_sigil.*}). */
    public static final String GEO_ID = "revive_sigil";

    /** Triggerable one-shot: tablet spin-up + glyph over-glow when the ritual begins. */
    public static final String ANIM_RITUAL = "ritual";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public ReviveSigilItem(Properties properties) {
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
        AnimationController<ReviveSigilItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_RITUAL, EclipseGeoAnimations.once(GEO_ID, ANIM_RITUAL));
        controllers.add(action);
    }

    // ------------------------------------------------------------------ interaction

    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        if (!(level.getBlockEntity(context.getClickedPos()) instanceof AltarBlockEntity altar)) {
            return InteractionResult.PASS;
        }
        if (level.isClientSide) {
            return InteractionResult.SUCCESS;
        }
        if (!(context.getPlayer() instanceof ServerPlayer serverPlayer)) {
            return InteractionResult.PASS;
        }
        if (context.isSecondaryUseActive()) {
            altar.handleSigilConfirm(serverPlayer);
            if (level instanceof ServerLevel serverLevel
                    && ReviveRitual.isRunningAt(serverLevel, context.getClickedPos())) {
                // A ritual is live at this altar -> the confirm was accepted; spin the tablet up.
                triggerAnim(serverPlayer,
                        GeoItem.getOrAssignId(context.getItemInHand(), serverLevel),
                        EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_RITUAL);
            }
        } else {
            // Unreachable through vanilla flow (AltarBlock consumes non-sneak clicks); kept for safety.
            altar.handleSigilCycle(serverPlayer);
        }
        return InteractionResult.CONSUME;
    }
}
