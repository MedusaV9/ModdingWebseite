package dev.projecteclipse.eclipse.economy;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.SwordItem;
import net.minecraft.world.item.Tier;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.SingletonGeoAnimatable;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * Umbral Blade (W13 shard shop, 16 shards): unchanged diamond-class {@link SwordItem}
 * gameplay — the +1-heart lifesteal on a player kill still lives in
 * {@code lives.LifecycleEvents} and keys off item identity, so subclassing is invisible
 * to it.
 *
 * <p><b>GeckoLib (POLISH3, MD4 §9):</b> a hand-3D geo item on the wand controller idiom
 * ({@code geo/item/umbral_blade.geo.json} — curved three-segment blade, glowing edge
 * planes, pommel eye, two shadow wisps). The {@code base} controller loops
 * {@code idle} (edge-glow breathing + wisp flicker); the {@code action} controller
 * holds the triggerable {@value #ANIM_FEAST} one-shot (pommel eye dilates, edge
 * flames). 3D applies to HAND contexts only: the item model
 * ({@code models/item/umbral_blade.json}) is a {@code neoforge:separate_transforms}
 * model whose gui/ground/fixed perspectives stay on the final 2D pixel icon.</p>
 *
 * <p>{@value #ANIM_FEAST} is deliberately NOT wired yet — the lifesteal moment belongs
 * to {@code LifecycleEvents} (foreign file). The owner adds one line next to the
 * existing blade-lifesteal branch (MD3 {@code triggerShatter} pattern):
 * {@code UmbralBladeItem.triggerFeast(killer);}</p>
 */
public class UmbralBladeItem extends SwordItem implements GeoItem {
    /** Asset/anim id ({@code geo/item/umbral_blade.geo.json}, {@code animation.umbral_blade.*}). */
    public static final String GEO_ID = "umbral_blade";
    /** Triggerable one-shot on the {@code action} controller: the lifesteal flourish. */
    public static final String ANIM_FEAST = "feast";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public UmbralBladeItem(Tier tier, Properties properties) {
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
        AnimationController<UmbralBladeItem> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        action.triggerableAnim(ANIM_FEAST, EclipseGeoAnimations.once(GEO_ID, ANIM_FEAST));
        controllers.add(action);
    }

    /**
     * Server-side {@value #ANIM_FEAST} one-shot on the killer's main-hand blade, synced
     * to tracking clients by {@code SingletonGeoAnimatable}. Null-safe no-op when the
     * main hand is not an umbral blade — safe to drop next to the lifesteal branch in
     * {@code LifecycleEvents} as a single line.
     */
    public static void triggerFeast(ServerPlayer player) {
        ItemStack stack = player.getMainHandItem();
        if (stack.getItem() instanceof UmbralBladeItem blade) {
            long instanceId = GeoItem.getOrAssignId(stack, player.serverLevel());
            blade.triggerAnim(player, instanceId, EclipseGeoAnimations.CONTROLLER_ACTION, ANIM_FEAST);
        }
    }
}
