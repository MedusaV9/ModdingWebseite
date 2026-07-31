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
 * {@code death}, played-and-held; contract v2: per-trigger blend-in via
 * {@link #actionTransitionTicks(String)}, default 0 = v1 hard snap). Fight/AI code
 * fires one-shots server-side via {@link #triggerAction(String)} — e.g.
 * {@code this.triggerAction("cast_blind")} — which GeckoLib syncs to clients on its own
 * channel.</p>
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
     * {@link #registerActionTriggers} / {@link #actionTransitionTicks(String)} so every
     * P6 mob keeps identical controller names (fight code and sibling workers rely on
     * them). Since contract v2 the {@code action} controller is an
     * {@link EclipseActionController} (per-trigger blend-in, default 0 = v1 behavior).
     */
    @Override
    public final void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        controllers.add(new AnimationController<>(this, EclipseGeoAnimations.CONTROLLER_BASE,
                baseTransitionTicks(), this::handleBaseState));
        AnimationController<EclipseGeoMonster> action = new EclipseActionController<>(this,
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
