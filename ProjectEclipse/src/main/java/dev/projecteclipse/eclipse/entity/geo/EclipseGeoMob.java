package dev.projecteclipse.eclipse.entity.geo;

import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.PathfinderMob;
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
 * FROZEN GeckoLib base for passive/ambient ({@code PathfinderMob}-line) mobs — the
 * non-hostile mirror of {@link EclipseGeoMonster}; see that class and
 * {@code docs/plans_v3/handoff/P6_geckolib_conventions.md} for the full contract.
 *
 * <p>Subclasses implement {@link #geoId()} and optionally override
 * {@link #handleBaseState}, {@link #registerActionTriggers},
 * {@link #baseTransitionTicks} and (contract v2) {@link #actionTransitionTicks(String)}.
 * Server code fires one-shots via {@link #triggerAction(String)}.</p>
 */
public abstract class EclipseGeoMob extends PathfinderMob implements GeoEntity {
    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);
    private RawAnimation cachedIdleAnim;
    private RawAnimation cachedWalkAnim;

    protected EclipseGeoMob(EntityType<? extends EclipseGeoMob> entityType, Level level) {
        super(entityType, level);
    }

    /**
     * The entity path under the {@code eclipse} namespace (e.g. {@code "drift_lantern"}) —
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
     * {@link #registerActionTriggers} / {@link #actionTransitionTicks(String)} so every
     * P6 mob keeps identical controller names (fight code and sibling workers rely on
     * them). Since contract v2 the {@code action} controller is an
     * {@link EclipseActionController} (per-trigger blend-in, default 0 = v1 behavior).
     */
    @Override
    public final void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE,
                baseTransitionTicks(), this::handleBaseState));
        AnimationController<EclipseGeoMob> action = new EclipseActionController<>(this,
                EclipseGeoAnimations.CONTROLLER_ACTION, this::actionTransitionTicks,
                state -> PlayState.STOP);
        registerActionTriggers(action);
        controllers.add(action);
    }

    /** Transition blend ticks of the {@code base} controller (plan default: 4). */
    protected int baseTransitionTicks() {
        return 4;
    }

    /**
     * Contract v2 (POLISH2 "Action-Blend"): blend-in ticks of ONE {@code action}
     * one-shot, resolved per trigger name at trigger time. Default {@code 0} = the v1
     * hard snap, which stays MANDATORY for frame-exact/timer-beaten actions
     * (impact/windup specials, {@code death}), deliberate horror/glitch snaps, and
     * one-shots that pin bones the base loop spins via Molang — see
     * {@link EclipseActionController} for the full rule set and
     * {@code docs/plans_v3/session_0730/POLISH2_ACTIONBLEND_REPORT.md} for the
     * per-consumer measurements. Opt cosmetic follow-throughs (melee swings fired
     * after damage, rise-style flourishes) into 2–4 ticks; a blend delays the whole
     * clip by that many ticks relative to trigger-tick FX.
     */
    protected int actionTransitionTicks(String animName) {
        return 0;
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
