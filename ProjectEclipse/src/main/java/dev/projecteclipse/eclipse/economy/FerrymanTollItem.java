package dev.projecteclipse.eclipse.economy;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResultHolder;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Ferryman's Toll (W12 finale trophy, guaranteed Ferryman drop): still a plain trophy —
 * nothing consumes it (W13 owns its future economy uses; MD4 §9.1 verified that no
 * consume path exists yet).
 *
 * <p><b>GeckoLib (POLISH3, MD4 §9):</b> in hand the toll becomes a large spectral coin
 * ({@code geo/item/ferryman_toll.geo.json} — octagonal verdigris disc, engraved barge
 * obverse / lantern reverse, strong emissive rim, two orbiting obol glyphs).
 * {@code base} controller loops {@code idle} (tilted precession spin, per the MD3 §6.1
 * tilt/spin bone split); the {@code action} controller holds the triggerable
 * {@value #ANIM_PRESENT} one-shot — the MD4 "hand-over moment": the coin rises, levels,
 * flips to present its lantern reverse and settles back. 3D applies to HAND contexts
 * only — the {@code neoforge:separate_transforms} item model keeps gui/ground/fixed on
 * the final 2D pixel icon.</p>
 *
 * <p>{@value #ANIM_PRESENT} fires from {@link #use}: right-clicking with the toll is
 * currently a no-op (PASS), so the cosmetic gesture changes zero behavior. The consume
 * path is server-only-to-be, so the trigger is server-side
 * ({@code SingletonGeoAnimatable} syncs it to tracking clients) and throttled to the
 * anim length against held-right-click re-fires. When W13 wires a real economy use,
 * {@link #triggerPresent(ServerPlayer, ItemStack)} is the one-liner for that path.</p>
 */
public class FerrymanTollItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/ferryman_toll.geo.json}, {@code animation.ferryman_toll.*}). */
    public static final String GEO_ID = "ferryman_toll";
    /** Triggerable one-shot on the {@code action} controller: the hand-over flip. */
    public static final String ANIM_PRESENT = "present";
    /** {@value #ANIM_PRESENT} is 2.0 s = 40 t; held right-click re-fires every 4 t without this. */
    private static final int PRESENT_THROTTLE_TICKS = 40;

    /** Per-player last-trigger game time (server-side only; bounded by online players). */
    private static final Map<UUID, Long> LAST_PRESENT = new HashMap<>();

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public FerrymanTollItem(Properties properties) {
        super(properties);
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
        AnimationController<FerrymanTollItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_PRESENT, EclipseGeoAnimations.once(GEO_ID, ANIM_PRESENT));
        controllers.add(action);
    }

    @Override
    public InteractionResultHolder<ItemStack> use(Level level, Player player, InteractionHand hand) {
        ItemStack stack = player.getItemInHand(hand);
        if (player instanceof ServerPlayer serverPlayer) {
            triggerPresent(serverPlayer, stack);
        }
        // PASS keeps the toll's behavior exactly what it was (a no-op trophy) — the
        // gesture is purely cosmetic and must not eat the click from other systems.
        return InteractionResultHolder.pass(stack);
    }

    /**
     * Server-side {@value #ANIM_PRESENT} one-shot on {@code stack}, synced to tracking
     * clients and throttled to the anim length. Null-safe no-op for non-toll stacks —
     * ready for W13's real hand-over path.
     */
    public static void triggerPresent(ServerPlayer player, ItemStack stack) {
        if (!(stack.getItem() instanceof FerrymanTollItem toll)) {
            return;
        }
        long now = player.serverLevel().getGameTime();
        Long last = LAST_PRESENT.get(player.getUUID());
        // 'now < last' guards against a fresh world with a smaller game time.
        if (last != null && now - last < PRESENT_THROTTLE_TICKS && now >= last) {
            return;
        }
        LAST_PRESENT.put(player.getUUID(), now);
        long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
        toll.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_PRESENT);
    }
}
