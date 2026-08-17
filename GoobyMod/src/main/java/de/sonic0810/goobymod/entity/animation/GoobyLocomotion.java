package de.sonic0810.goobymod.entity.animation;

/**
 * Deterministic gait selection for the locomotion clips (idle / walk / run).
 *
 * <p>Input is the horizontal distance covered in the last tick, derived from
 * replicated positions, so server and client see closely matching numbers
 * (the client interpolates remote positions over a few ticks, which only
 * smooths the curve). Two guards make the raw samples safe to classify:
 *
 * <ul>
 *   <li><b>Teleport guard:</b> samples above {@link #MAX_PLAUSIBLE_SPEED} are
 *   discarded — no gait can move that fast, such deltas are teleports (or the
 *   client-side lerp of one, which spreads a jump over ~3 ticks).</li>
 *   <li><b>Smoothing:</b> an exponential moving average ({@link #SMOOTHING})
 *   filters single-tick dips and peaks from path turns and knockback, so the
 *   classified speed tracks the sustained pace, not per-tick noise.</li>
 * </ul>
 *
 * <p>Hysteresis: entering a faster gait requires a strictly higher smoothed
 * speed than leaving it, so a Gooby pacing right at a boundary never flickers
 * between two clips. {@link #update(long, double)} advances at most once per
 * game tick, which makes it safe to call from every render frame and from
 * multiple GeckoLib controllers in the same frame.
 */
public final class GoobyLocomotion {
    public enum Gait {
        IDLE,
        WALK,
        RUN;

        public boolean isMoving() {
            return this != IDLE;
        }
    }

    // Schwellen in Bloecken pro Tick (geglaettet). Gemessene Referenzwerte
    // (GameTest navigation_speeds_match_gait_thresholds, AI-isoliert,
    // MOVEMENT_SPEED 0.25): Stroll @1.0 ~0.135, Follow-Owner @1.15 ~0.178,
    // Follow-Parent @1.18 ~0.188 (alle WALK) | Zulauf @1.25 ~0.211,
    // Panik @1.4 ~0.264 (beide RUN). Das Run-Band liegt bewusst KOMPLETT in
    // der Luecke 0.188..0.211: kein realer Modifier landet im Totband, ein
    // stehengebliebener RUN-Zustand faellt auf Follow-Tempo binnen weniger
    // Ticks wieder heraus (keine Bistabilitaet), und die EMA-Glaettung haelt
    // das schmale Enter/Exit-Fenster flatterfrei.
    public static final double WALK_ENTER_SPEED = 0.04;
    public static final double WALK_EXIT_SPEED = 0.02;
    public static final double RUN_ENTER_SPEED = 0.204;
    public static final double RUN_EXIT_SPEED = 0.196;

    /**
     * Faster than any legitimate gait (panic tops out around 0.26 blocks per
     * tick, a ridden boat around 0.4): such samples are teleport artefacts and
     * are ignored instead of being fed into the average.
     */
    public static final double MAX_PLAUSIBLE_SPEED = 0.5;

    /** EMA weight per tick; roughly 90 % converged after 6 ticks. */
    public static final double SMOOTHING = 0.35;

    private Gait gait = Gait.IDLE;
    private double smoothedSpeed;
    private long lastTick = Long.MIN_VALUE;

    /** Pure selector shared by the movement controller and GameTests. */
    public static Gait selectGait(Gait previous, double smoothedBlocksPerTick) {
        return switch (previous) {
            case RUN -> smoothedBlocksPerTick <= WALK_EXIT_SPEED ? Gait.IDLE
                    : smoothedBlocksPerTick <= RUN_EXIT_SPEED ? Gait.WALK
                    : Gait.RUN;
            case WALK -> smoothedBlocksPerTick <= WALK_EXIT_SPEED ? Gait.IDLE
                    : smoothedBlocksPerTick >= RUN_ENTER_SPEED ? Gait.RUN
                    : Gait.WALK;
            case IDLE -> smoothedBlocksPerTick >= RUN_ENTER_SPEED ? Gait.RUN
                    : smoothedBlocksPerTick >= WALK_ENTER_SPEED ? Gait.WALK
                    : Gait.IDLE;
        };
    }

    /**
     * Advances the state machine once for {@code tick}. Repeated calls within
     * the same tick (render frames, several controllers) return the cached
     * gait without re-sampling, so call order does not matter.
     */
    public Gait update(long tick, double horizontalBlocksPerTick) {
        if (tick != this.lastTick) {
            this.lastTick = tick;
            if (horizontalBlocksPerTick <= MAX_PLAUSIBLE_SPEED) {
                this.smoothedSpeed += SMOOTHING * (horizontalBlocksPerTick - this.smoothedSpeed);
            }
            this.gait = selectGait(this.gait, this.smoothedSpeed);
        }
        return this.gait;
    }

    public Gait gait() {
        return this.gait;
    }
}
