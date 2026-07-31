package dev.projecteclipse.eclipse.entity.geo;

import java.util.function.ToIntFunction;

import software.bernie.geckolib.animatable.GeoAnimatable;
import software.bernie.geckolib.animation.AnimationController;

/**
 * FROZEN-contract v2 {@code action} controller (POLISH2 "Action-Blend"): an
 * {@link AnimationController} that resolves its transition length <b>per triggered
 * one-shot</b> instead of using one fixed value for the whole controller.
 *
 * <p>The v1 contract pinned the shared {@code action} controller to
 * {@code transitionLength = 0} so every one-shot starts frame-exact on its trigger tick
 * — all anim-synced FX in this repo are Java-side tick timers counted from the trigger
 * (there are no GeckoLib sound/particle keyframe handlers anywhere), so beats like the
 * Fog Colossus slam impact ({@code GroundSlamGoal.IMPACT_TICK} = anim drop at 1.35 s)
 * only line up when the animation clock starts immediately. The cost was a hard
 * single-frame pose snap out of idle/walk (measured up to ~49° on the Deckhand attack,
 * MB1 report §9.3 / POLISH2 report).</p>
 *
 * <p>v2 keeps 0 as the default for every trigger and lets each consumer opt individual
 * one-shots into a short blend-in. The policy function receives the trigger name and
 * returns the transition ticks for THAT trigger; it is applied in
 * {@link #tryTriggerAnimation(String)} — the single funnel every trigger path uses
 * (server {@code triggerAnim}, the GeckoLib sync packet on clients, and client-side
 * singleton short-circuits all end in
 * {@code AnimatableManager#tryTriggerAnimation} → this method, verified against the
 * decompiled 4.9.2 jar).</p>
 *
 * <p><b>Blend semantics (verified in the decompiled 4.9.2
 * {@code AnimationController.process}/{@code adjustTick}):</b> an N-tick transition
 * lerps the bone snapshots linearly to the one-shot's t=0 pose and only THEN starts the
 * animation clock ({@code shouldResetTick} is set again on the TRANSITIONING→RUNNING
 * flip — the same fact MB1 §5.1 anchored the row loop on). A blended one-shot therefore
 * plays its ENTIRE timeline N ticks late relative to trigger-tick FX/sound. Rules:</p>
 * <ul>
 *   <li>Blend (2–4 t) ONLY cosmetic follow-through one-shots: melee swings fired after
 *       the damage ({@code doHurtTarget} pattern), rise/open/extract flourishes.</li>
 *   <li>NEVER blend one-shots that a server timer beats into mid-clip (Colossus
 *       {@code slam}, Storm Hound {@code charge_windup}/{@code lunge}), deliberate
 *       horror/glitch snaps (glitch trio, Wanderer {@code notice}), or {@code death}
 *       (scripted {@code tickDeath} windows assume the clip starts at the trigger).</li>
 *   <li>NEVER blend a one-shot whose sheet pins a bone that the base loop spins via
 *       Molang (Cultist {@code runes}, Arm-Artifact {@code ledger}): the transition
 *       lerps UNWRAPPED angles and whips such bones through up to a full revolution,
 *       which is worse than the wrap-around cut it replaces.</li>
 * </ul>
 */
public class EclipseActionController<T extends GeoAnimatable> extends AnimationController<T> {
    private final ToIntFunction<String> transitionTicksByTrigger;

    public EclipseActionController(T animatable, String name,
            ToIntFunction<String> transitionTicksByTrigger, AnimationStateHandler<T> stateHandler) {
        super(animatable, name, 0, stateHandler);
        this.transitionTicksByTrigger = transitionTicksByTrigger;
    }

    /**
     * Applies the per-trigger transition policy BEFORE delegating, so the upcoming
     * STOPPED/RUNNING→TRANSITIONING flip (in super or in the next
     * {@code handleAnimationState} pass) already sees the right length. Unknown names
     * leave the current length untouched and fail in super exactly like v1.
     */
    @Override
    public boolean tryTriggerAnimation(String animName) {
        if (this.triggerableAnimations.containsKey(animName)) {
            transitionLength(Math.max(0, this.transitionTicksByTrigger.applyAsInt(animName)));
        }
        return super.tryTriggerAnimation(animName);
    }
}
