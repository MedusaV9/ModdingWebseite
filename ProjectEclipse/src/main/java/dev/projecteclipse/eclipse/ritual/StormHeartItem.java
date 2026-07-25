package dev.projecteclipse.eclipse.ritual;

import dev.projecteclipse.eclipse.entity.geo.EclipseGeoAnimations;
import net.minecraft.world.item.Item;
import software.bernie.geckolib.animatable.GeoItem;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * The Storm Heart as a GeckoLib item (PLAN-ITEMS B1): a slate cage around a rotating
 * white-hot core with flickering lightning-arc glow planes. Pure trophy — the single
 * {@code base} controller loops {@code animation.storm_heart.idle} (core rotation + arc
 * flickers) and there are no triggerable one-shots, so unlike {@code EclipseWandItem}
 * this class deliberately does NOT register as a synced animatable (nothing server-side
 * ever fires an anim on it). Item frames desync naturally because every stack gets its
 * own animatable instance id.
 *
 * <p>Rendering: {@code client/item/StormHeartRenderer} via
 * {@code client/item/ItemsBClientExtensions}; the item model
 * ({@code models/item/storm_heart.json}) is {@code builtin/entity}. The baked
 * {@code item.eclipse.storm_heart.lore} line stays on the registration in
 * {@code registry/EclipseItems} (V6 gap-fix precedent).</p>
 */
public class StormHeartItem extends Item implements GeoItem {
    /** Asset/anim id ({@code geo/item/storm_heart.geo.json}, {@code animation.storm_heart.*}). */
    public static final String GEO_ID = "storm_heart";

    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public StormHeartItem(Properties properties) {
        super(properties);
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
    }
}
