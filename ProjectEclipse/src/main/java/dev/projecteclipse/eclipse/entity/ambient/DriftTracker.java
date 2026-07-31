package dev.projecteclipse.eclipse.entity.ambient;

/**
 * Census falle F-9 — the one shared answer for tick-driven drifters
 * ({@code docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md} §7): {@code AnimationState
 * .isMoving()} never turns true for a mob that teleports itself with {@code setPos},
 * so the {@code base} controller has to read the mob's REAL per-tick position delta.
 *
 * <p>Why {@code isMoving()} cannot work here (verified against 1.21.1 + GeckoLib 4.9.2 —
 * two independent reasons, either one is fatal):</p>
 * <ol>
 *   <li>{@code ServerLevel/ClientLevel.tickNonPassenger} calls {@code setOldPosAndRot()}
 *       immediately BEFORE {@code Entity.tick()}. A drifter applies its {@code setPos}
 *       inside its own {@code tick()} override, i.e. AFTER {@code super.tick()} has
 *       already fed {@code calculateEntityAnimation} with {@code getX() - xo == 0} —
 *       {@code walkAnimation.speed} therefore stays 0 forever.</li>
 *   <li>GeckoLib additionally gates on {@code (|motion.x| + |motion.z|) / 2 >= 0.015},
 *       which the ambient drift speeds (0.025 b/t for the lantern) never reach even when
 *       the delta movement IS set.</li>
 * </ol>
 *
 * <p>The tracker is fed the delta at the END of {@code tick()} (server: after the
 * teleport; client: after the interpolation step) and holds its verdict for a few ticks:
 * the client only receives a position update every {@code updateInterval} ticks (3 for
 * most entity types), so the raw per-tick delta is 0 on the ticks in between and a naive
 * read flaps the base controller between {@code walk} and {@code idle}.</p>
 *
 * <p>HORIZONTAL delta only, deliberately: both ambient drifters ride a permanent vertical
 * sine bob (Sunmote orbit, lantern hover), which is ambience, not travel — counting it
 * would pin them to {@code walk} forever and the {@code idle} loop would be unreachable.
 * The trade-off is that an almost purely vertical drift leg reads as hovering.</p>
 */
public final class DriftTracker {
    /** Squared horizontal blocks/tick that count as travel (0.0032 b/t). */
    public static final double DEFAULT_EPSILON_SQR = 1.0E-5D;
    /** Ticks a "gliding" verdict survives without a fresh delta (client cadence is 3). */
    public static final int DEFAULT_HOLD_TICKS = 6;

    private final double epsilonSqr;
    private final int holdTicks;
    private int glideTicks;

    public DriftTracker() {
        this(DEFAULT_EPSILON_SQR, DEFAULT_HOLD_TICKS);
    }

    public DriftTracker(double epsilonSqr, int holdTicks) {
        this.epsilonSqr = epsilonSqr;
        this.holdTicks = holdTicks;
    }

    /**
     * Feeds one tick's horizontal movement — call LAST in {@code Entity.tick()}, on both
     * sides, with {@code getX() - xOld} / {@code getZ() - zOld}.
     *
     * <p>{@code xOld}, NOT {@code xo}: both are set by {@code setOldPosAndRot()} at the top
     * of the tick, but {@code absMoveTo()} additionally overwrites {@code xo} with the
     * destination, which would silently zero the delta on any tick that routes through it.
     * {@code xOld} is only touched by {@code setOldPosAndRot()} (plus a {@code tickCount == 0}
     * primer in {@code LevelRenderer}), so it stays a true start-of-tick reference.</p>
     */
    public void track(double dx, double dz) {
        if (dx * dx + dz * dz > this.epsilonSqr) {
            this.glideTicks = this.holdTicks;
        } else if (this.glideTicks > 0) {
            this.glideTicks--;
        }
    }

    /** True while the mob counts as travelling — the {@code walk} loop's condition. */
    public boolean gliding() {
        return this.glideTicks > 0;
    }
}
