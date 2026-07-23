package dev.projecteclipse.eclipse.entity.geo;

import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.level.Level;
import software.bernie.geckolib.animatable.GeoEntity;
import software.bernie.geckolib.animatable.instance.AnimatableInstanceCache;
import software.bernie.geckolib.animation.AnimatableManager;
import software.bernie.geckolib.animation.AnimationController;
import software.bernie.geckolib.animation.AnimationState;
import software.bernie.geckolib.animation.PlayState;
import software.bernie.geckolib.animation.RawAnimation;
import software.bernie.geckolib.util.GeckoLibUtil;

/**
 * FROZEN GeckoLib base for hostile ({@code Monster}-line) mobs and bosses
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.1; full contract in
 * {@code docs/plans_v3/handoff/P6_geckolib_conventions.md}). Java's single inheritance
 * forces two identical bases — this one mirrors {@link EclipseGeoMob} exactly; keep them
 * in lockstep if either ever changes (P6-W1 owns both).
 *
 * <p>The frozen shape: an {@code AnimatableInstanceCache} via
 * {@code GeckoLibUtil.createInstanceCache}, a {@code base} controller running
 * {@link #handleBaseState} (default walk/idle switch) and an {@code action} controller
 * holding the triggerable one-shots from {@link #registerActionTriggers} (default:
 * {@code death}, played-and-held). Fight/AI code fires one-shots server-side via
 * {@link #triggerAction(String)} — e.g. {@code this.triggerAction("cast_blind")} — which
 * GeckoLib syncs to clients on its own channel.</p>
 */
public abstract class EclipseGeoMonster extends Monster implements GeoEntity {
    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);
    private RawAnimation cachedIdleAnim;
    private RawAnimation cachedWalkAnim;

    protected EclipseGeoMonster(EntityType<? extends EclipseGeoMonster> entityType, Level level) {
        super(entityType, level);
    }

    /**
     * The entity path under the {@code eclipse} namespace (e.g. {@code "fog_revenant"}) —
     * keys the geo/animation/texture lookups AND the {@code animation.<id>.<name>} ids.
     */
    public abstract String geoId();

    @Override
    public final AnimatableInstanceCache getAnimatableInstanceCache() {
        return geoCache;
    }

    /**
     * Registers the frozen two-controller layout ({@code base} + {@code action}). Do NOT
     * override this — customize via {@link #handleBaseState} /
     * {@link #registerActionTriggers} so every P6 mob keeps identical controller names
     * (fight code and sibling workers rely on them).
     */
    @Override
    public final void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE,
                baseTransitionTicks(), this::handleBaseState));
        AnimationController<EclipseGeoMonster> action = new AnimationController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, 0, state -> PlayState.STOP);
        registerActionTriggers(action);
        controllers.add(action);
    }

    /** Transition blend ticks of the {@code base} controller (plan default: 4). */
    protected int baseTransitionTicks() {
        return 4;
    }

    /** {@code base} controller state machine — default: walk while moving, else idle. */
    protected PlayState handleBaseState(AnimationState<?> state) {
        return state.setAndContinue(state.isMoving() ? walkAnim() : idleAnim());
    }

    /** Cached {@code animation.<geoId>.idle} loop (override to substitute). */
    protected RawAnimation idleAnim() {
        if (cachedIdleAnim == null) {
            cachedIdleAnim = EclipseGeoAnimations.loop(geoId(), EclipseGeoAnimations.ANIM_IDLE);
        }
        return cachedIdleAnim;
    }

    /** Cached {@code animation.<geoId>.walk} loop (override to substitute). */
    protected RawAnimation walkAnim() {
        if (cachedWalkAnim == null) {
            cachedWalkAnim = EclipseGeoAnimations.loop(geoId(), EclipseGeoAnimations.ANIM_WALK);
        }
        return cachedWalkAnim;
    }

    /**
     * Registers the triggerable one-shots on the {@code action} controller. Default:
     * only {@code death} (played-and-held). Overriders should call super and add their
     * sheet's attack/special triggers.
     */
    protected void registerActionTriggers(AnimationController<?> action) {
        action.triggerableAnim(EclipseGeoAnimations.ANIM_DEATH,
                EclipseGeoAnimations.hold(geoId(), EclipseGeoAnimations.ANIM_DEATH));
    }

    /** Server-side one-shot: fires a triggerable anim on the {@code action} controller. */
    public final void triggerAction(String animName) {
        triggerAnim(EclipseGeoAnimations.CONTROLLER_ACTION, animName);
    }
}
