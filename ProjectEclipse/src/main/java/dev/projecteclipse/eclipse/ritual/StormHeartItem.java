package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
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
 * The Storm Heart as a GeckoLib item (PLAN-ITEMS B1, MD3 heartbeat pass): a slate cage
 * around a rotating white-hot core with flickering lightning-arc glow planes. The
 * Fog Tyrant's guaranteed progression drop ({@code FogTyrantEntity#dropCustomDeathLoot}).
 *
 * <p>The {@code base} controller loops {@code animation.storm_heart.idle}, which MD3
 * rebuilt as a LUB-DUB heartbeat on B5's dread curve
 * ({@code docs/plans_v3/session_0730/B5_DREAD_REPORT.md} §2: LUB amplitude 1.00, DUB
 * 0.70 at +0.22 s, then silence): the four {@code rib_*} shell fragments heave up and
 * splay outward on every beat, and the three {@code glow_arc_*} lightning planes now
 * fire ON the beats instead of on an unrelated flicker schedule — the trapped storm
 * discharges when the heart contracts.</p>
 *
 * <p>The {@code action} controller holds two triggerable one-shots:</p>
 * <ul>
 *   <li>{@value #ANIM_SOCKET} — pressed down into a seat: the cage compresses, the ribs
 *       clamp in, then snap out with a discharge. There is no socket MECHANIC in the
 *       codebase yet ({@code rg STORM_HEART src/main/java}: registration, renderer and
 *       the Tyrant drop, nothing else) — see {@code MD3_ITEMSB_REPORT.md} §6.2. Until one
 *       exists the anim is fired cosmetically from {@link #useOn} when the heart is
 *       pressed against ordinary stone, and {@link #triggerSocket} is the one-liner for
 *       whoever adds the real mechanic.
 *       <p><b>Deliberately NOT routed through the altar:</b> {@code AltarBlock}'s deposit
 *       lane ({@code onSneakRightClick}) cancels {@code RightClickBlock} at LOWEST for
 *       every item except the revive sigil and the herald's lure, so an altar-side
 *       {@code useOn} here would be dead code AND would sit on the gesture that offers
 *       the Tyrant's unique drop away.</p></li>
 *   <li>{@value #ANIM_AWAKEN} — held up and woken: tremble, shells swing open, core
 *       flares, arcs cascade, shells close. Fired from {@link #use}.</li>
 * </ul>
 *
 * <p>Because those one-shots are fired SERVER-side, this class now registers as a synced
 * animatable (it deliberately did not while it was a pure trophy with no triggers).
 * Item frames still desync naturally because every stack gets its own animatable
 * instance id. Rendering: {@code client/item/StormHeartRenderer} via
 * {@code client/item/ItemsBClientExtensions}; the item model
 * ({@code models/item/storm_heart.json}) is {@code builtin/entity}. The baked
 * {@code item.eclipse.storm_heart.lore} line stays on the registration in
 * {@code registry/EclipseItems} (V6 gap-fix precedent).</p>
 */
public class StormHeartItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/storm_heart.geo.json}, {@code animation.storm_heart.*}). */
    public static final String GEO_ID = "storm_heart";

    /** Triggerable one-shot: seated into a socket — cage compresses, ribs clamp then snap out. */
    public static final String ANIM_SOCKET = "socket";

    /** Triggerable one-shot: first activation — shells swing open, the core flames. */
    public static final String ANIM_AWAKEN = "awaken";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public StormHeartItem(Properties properties) {
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
        AnimationController<StormHeartItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_SOCKET, EclipseGeoAnimations.once(GEO_ID, ANIM_SOCKET));
        action.triggerableAnim(ANIM_AWAKEN, EclipseGeoAnimations.once(GEO_ID, ANIM_AWAKEN));
        controllers.add(action);
    }

    // ------------------------------------------------------------------ interaction

    /**
     * Sneak-pressing the heart against ordinary stone seats it: {@value #ANIM_SOCKET}.
     * Altars are skipped on purpose (see the class doc) and every path returns
     * {@link InteractionResult#PASS}, so this is cosmetic only — no interaction
     * behaviour changes anywhere.
     */
    @Override
    public InteractionResult useOn(UseOnContext context) {
        Level level = context.getLevel();
        if (level.isClientSide || !context.isSecondaryUseActive()
                || level.getBlockEntity(context.getClickedPos()) instanceof AltarBlockEntity) {
            return InteractionResult.PASS;
        }
        if (context.getPlayer() instanceof ServerPlayer player
                && level instanceof ServerLevel serverLevel) {
            triggerSocket(player, context.getItemInHand(), serverLevel);
        }
        return InteractionResult.PASS;
    }

    /**
     * Holding the heart up wakes it: {@value #ANIM_AWAKEN}. Cosmetic only — returns
     * {@link InteractionResultHolder#pass} so no interaction behaviour changes.
     */
    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (!level.isClientSide && player instanceof ServerPlayer serverPlayer
                && level instanceof ServerLevel serverLevel) {
            triggerAnim(serverPlayer, GeoItem.getOrAssignId(stack, serverLevel),
                    EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_AWAKEN);
        }
        return InteractionResultHolder.pass(stack);
    }

    /**
     * Plays {@value #ANIM_SOCKET} on {@code stack}. This is the hook for a future socket
     * mechanic: call it on the server the moment the heart is seated, and the cage
     * compression + rib clamp + discharge snap plays on every tracking client.
     */
    public static void triggerSocket(ServerPlayer player, ItemStack stack, ServerLevel level) {
        if (stack.getItem() instanceof StormHeartItem heart) {
            heart.triggerAnim(player, GeoItem.getOrAssignId(stack, level),
                    EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_SOCKET);
        }
    }
}
