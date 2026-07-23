package dev.projecteclipse.eclipse.entity.pale;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.level.ClipContext;
import net.minecraft.world.phys.HitResult;
import net.minecraft.world.phys.Vec3;

/**
 * The Pale Sentinel's "is any player looking at me?" check
 * ({@code docs/plans_v3/P6_mobs_models_builds.md} §2.3, inverse of the Gazer's
 * {@code VanishWhenSeenGoal}). A sentinel counts as OBSERVED when at least one
 * non-spectator living player within {@value #OBSERVE_RANGE} blocks satisfies BOTH:
 *
 * <ol>
 *   <li><b>FOV cone:</b> {@code player.getViewVector(1f) · normalize(sentinelEye −
 *       playerEye) ≥ }{@value #VIEW_CONE_DOT} — a deliberately wide, forgiving cone
 *       (~60° half-angle) so the freeze reliably engages whenever the sentinel is
 *       anywhere on-screen, never only at dead center.</li>
 *   <li><b>Raycast occlusion:</b> an unobstructed {@code level.clip} COLLIDER line from
 *       the player's eye to the sentinel's eye <em>or</em> to its chest (two samples, so
 *       peeking over half-walls or under leaves still counts as seeing it).</li>
 * </ol>
 *
 * <p>Cost note (plan §5): the dot product is the cheap early-out — the (expensive)
 * raycasts only run for players whose view cone already passes, i.e. at most a handful
 * per tick. Hysteresis (freeze instantly on sight, {@code UNSEEN_GRACE_TICKS} of
 * continuous non-observation before it may move again) lives in
 * {@link PaleSentinelEntity}; this class is pure per-tick sensing.</p>
 */
public final class ObservedFreezeHelper {
    /** Players beyond this range never freeze the sentinel (spec §2.3: 32 blocks). */
    public static final double OBSERVE_RANGE = 32.0D;
    /** Wide forgiving view-cone threshold (spec §2.3: dot ≥ 0.5). */
    public static final double VIEW_CONE_DOT = 0.5D;

    private ObservedFreezeHelper() {}

    /** True when any nearby non-spectator living player has the sentinel in view. */
    public static boolean isObservedByAnyPlayer(ServerLevel level, LivingEntity sentinel) {
        double rangeSqr = OBSERVE_RANGE * OBSERVE_RANGE;
        for (ServerPlayer player : level.players()) {
            if (player.isSpectator() || !player.isAlive()) {
                continue;
            }
            if (player.distanceToSqr(sentinel) > rangeSqr) {
                continue;
            }
            if (isInViewCone(player, sentinel) && hasClearSightLine(level, player, sentinel)) {
                return true;
            }
        }
        return false;
    }

    /** Cheap FOV check: sentinel eye inside the player's forgiving view cone. */
    private static boolean isInViewCone(ServerPlayer player, LivingEntity sentinel) {
        Vec3 look = player.getViewVector(1.0F).normalize();
        Vec3 toSentinel = sentinel.getEyePosition().subtract(player.getEyePosition());
        if (toSentinel.lengthSqr() < 1.0E-4D) {
            return true; // Standing inside it: definitely "looking" at it.
        }
        return look.dot(toSentinel.normalize()) >= VIEW_CONE_DOT;
    }

    /**
     * Occlusion raycast (only reached after the cone passes): clear COLLIDER line from
     * the player's eye to the sentinel's eye OR chest — either exposed part freezes it.
     */
    private static boolean hasClearSightLine(ServerLevel level, ServerPlayer player, LivingEntity sentinel) {
        Vec3 from = player.getEyePosition();
        return isClear(level, player, from, sentinel.getEyePosition())
                || isClear(level, player, from, sentinel.position().add(0.0D, sentinel.getBbHeight() * 0.5D, 0.0D));
    }

    private static boolean isClear(ServerLevel level, ServerPlayer player, Vec3 from, Vec3 to) {
        return level.clip(new ClipContext(from, to,
                ClipContext.Block.COLLIDER, ClipContext.Fluid.NONE, player)).getType() == HitResult.Type.MISS;
    }
}
