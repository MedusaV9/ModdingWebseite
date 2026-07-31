package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
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
 * <p>GeckoLib item (PLAN-ITEMS B3, MD3 glyph-ring pass): a rune tablet inside an
 * orbiting ring of four {@code glow_rune_*} glyph segments. The {@code base} controller
 * loops {@code animation.revive_sigil.idle} (glyph glow pulse + hover-bob + slow ring
 * orbit); the {@code action} controller holds four triggerable one-shots:</p>
 * <ul>
 *   <li>{@value #ANIM_RITUAL} — tablet spin-up + glyph over-glow when the ritual begins,
 *       fired from the confirm path below once a {@link ReviveRitual} is live;</li>
 *   <li>{@code ritual_charge_1..3} — the escalating charge loop, one file per tautness
 *       stage of the FX-WAVE-13 N9 soul thread. Each is exactly
 *       {@value #CHARGE_TICKS} ticks long so {@code ReviveRitual}'s existing 40-tick
 *       soul-thread re-send re-triggers it seamlessly, and each is a ONE-SHOT so a
 *       failed/aborted ritual simply stops re-sending and the sigil falls back to idle
 *       on its own (a looping charge would have to be cancelled explicitly);</li>
 *   <li>{@value #ANIM_SHATTER} — the sigil breaks at the successful revive.</li>
 * </ul>
 *
 * <p>The last two live in {@code ReviveRitual}, which belongs to the ceremony package
 * this wave, so they are driven through the two public helpers
 * {@link #triggerRitualCharge} / {@link #triggerShatter} — see
 * {@code docs/plans_v3/session_0730/MD3_ITEMSB_REPORT.md} §7.1 for the call sites.</p>
 */
public class ReviveSigilItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/revive_sigil.geo.json}, {@code animation.revive_sigil.*}). */
    public static final String GEO_ID = "revive_sigil";

    /** Triggerable one-shot: tablet spin-up + glyph over-glow when the ritual begins. */
    public static final String ANIM_RITUAL = "ritual";

    /** Triggerable one-shot: glyphs blast off, core implodes (successful revive). */
    public static final String ANIM_SHATTER = "shatter";

    /** Prefix of the three escalating charge loops ({@code ritual_charge_1..3}). */
    public static final String ANIM_RITUAL_CHARGE = "ritual_charge";

    /** Number of charge stages, mirroring the N9 soul thread's tautness stages. */
    public static final int CHARGE_STAGES = 3;

    /**
     * Length of one charge stage in ticks. MUST stay equal to {@code ReviveRitual}'s
     * soul-thread re-send interval: the animations are authored cyclic (t=0 and
     * t={@value #CHARGE_TICKS}/20 s hold identical poses), so a re-trigger on that exact
     * cadence is invisible. Drift either way makes the ring stutter once per re-send.
     */
    public static final int CHARGE_TICKS = 40;

    /**
     * Ticks the {@value #ANIM_RITUAL} spin-up owns exclusively. {@code ReviveRitual}
     * fires its first soul-thread send on the ritual's very first tick, and both
     * animations share the single {@code action} controller — without this guard the
     * charge would cut the spin-up off after one tick.
     */
    public static final int RITUAL_SPINUP_TICKS = 32;

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
        for (int stage = 1; stage <= CHARGE_STAGES; stage++) {
            String name = chargeAnim(stage);
            action.triggerableAnim(name, EclipseGeoAnimations.once(GEO_ID, name));
        }
        action.triggerableAnim(ANIM_SHATTER, EclipseGeoAnimations.once(GEO_ID, ANIM_SHATTER));
        controllers.add(action);
    }

    // ------------------------------------------------------------------ ritual hooks

    /** Anim name for a charge stage; stages outside 1..{@value #CHARGE_STAGES} clamp. */
    public static String chargeAnim(int stage) {
        return ANIM_RITUAL_CHARGE + "_" + Math.max(1, Math.min(CHARGE_STAGES, stage));
    }

    /**
     * Plays the charge loop for the given soul-thread tautness stage on the sigil the
     * ritualist is carrying. Call this on the ritual's soul-thread cadence (every
     * {@value #CHARGE_TICKS} ticks); {@code ticksElapsed} only exists to keep the
     * {@value #ANIM_RITUAL} spin-up from being cut off by the first send.
     */
    public static void triggerRitualCharge(ServerPlayer confirmer, int stage, int ticksElapsed) {
        if (ticksElapsed < RITUAL_SPINUP_TICKS) {
            return;
        }
        triggerOnCarried(confirmer, chargeAnim(stage));
    }

    /**
     * Plays the {@value #ANIM_SHATTER} break-up on the sigil the ritualist is carrying.
     * Fire this BEFORE the payment is consumed — a stack that shrinks to zero stops
     * rendering, so only a surviving stack (count &gt; 1) shows the beat. Same ordering
     * caveat as {@code HeraldsLureItem}'s offering trigger.
     */
    public static void triggerShatter(ServerPlayer confirmer) {
        triggerOnCarried(confirmer, ANIM_SHATTER);
    }

    /**
     * Fires an {@code action} one-shot on the first revive sigil in the player's
     * inventory. Silently does nothing when they carry none — the ritual is allowed to
     * run to its completion check without the payment in hand.
     */
    private static void triggerOnCarried(ServerPlayer player, String animName) {
        var inventory = player.getInventory();
        for (int slot = 0; slot < inventory.getContainerSize(); slot++) {
            ItemStack stack = inventory.getItem(slot);
            if (stack.getItem() instanceof ReviveSigilItem sigil) {
                sigil.triggerAnim(player, GeoItem.getOrAssignId(stack, player.serverLevel()),
                        EclipseGeoAnimations.CONTROLLER_ACTION, animName);
                return;
            }
        }
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
