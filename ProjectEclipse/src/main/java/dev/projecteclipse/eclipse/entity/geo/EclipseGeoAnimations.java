package dev.projecteclipse.eclipse.entity.geo;

import software.bernie.geckolib.animation.RawAnimation;

/**
 * FROZEN animation naming + controller constants for every GeckoLib mob in the mod
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.1/§6). Do not rename anything here —
 * every P6 worker's {@code .animation.json} files and fight code key off these:
 *
 * <ul>
 *   <li>Animation ids follow {@code animation.<entity_path>.<name>} (e.g.
 *       {@code animation.drift_lantern.idle}); build them via {@link #animId}.</li>
 *   <li>Two controllers per mob: {@value #CONTROLLER_BASE} runs the looped idle/walk
 *       state machine, {@value #CONTROLLER_ACTION} holds server-triggered one-shots
 *       (attacks, specials, death) registered via
 *       {@code AnimationController.triggerableAnim} and fired with
 *       {@code triggerAnim(CONTROLLER_ACTION, name)}.</li>
 *   <li>Minimum animation set per mob: {@value #ANIM_IDLE}, {@value #ANIM_WALK},
 *       {@value #ANIM_ATTACK}, one special, {@value #ANIM_DEATH} — names per the mob's
 *       §2.3/§2.4 design sheet.</li>
 * </ul>
 */
public final class EclipseGeoAnimations {
    /** Looping locomotion controller (idle/walk switching). */
    public static final String CONTROLLER_BASE = "base";
    /** Triggerable one-shot controller (attack/special/death). */
    public static final String CONTROLLER_ACTION = "action";

    public static final String ANIM_IDLE = "idle";
    public static final String ANIM_WALK = "walk";
    public static final String ANIM_ATTACK = "attack";
    public static final String ANIM_DEATH = "death";

    private EclipseGeoAnimations() {}

    /** {@code animation.<entityPath>.<name>} — the frozen §6 anim-id scheme. */
    public static String animId(String entityPath, String name) {
        return "animation." + entityPath + "." + name;
    }

    /** A looping raw animation (idle/walk/channel loops). */
    public static RawAnimation loop(String entityPath, String name) {
        return RawAnimation.begin().thenLoop(animId(entityPath, name));
    }

    /** A play-once raw animation (attacks, casts, flickers). */
    public static RawAnimation once(String entityPath, String name) {
        return RawAnimation.begin().thenPlay(animId(entityPath, name));
    }

    /** A play-once-and-hold raw animation (death collapses, lunge holds). */
    public static RawAnimation hold(String entityPath, String name) {
        return RawAnimation.begin().thenPlayAndHold(animId(entityPath, name));
    }
}
