package dev.projecteclipse.eclipse.worldgen;

/**
 * Holder of the per-stage disc radii. Hardcoded v2 defaults; worker 4's
 * {@code stages.json} drives {@link #set(DiscProfile, int[])} once it lands.
 *
 * <p>Overworld stage 0 is special: the value here (96) is only the MAIN disc radius —
 * the eight player discs on the r=170 ring are described by {@link DiscGeometry}.
 * From stage 1 on the world is a single fused disc of the listed radius.</p>
 *
 * <p>Reads are volatile-safe for worldgen threads; writes happen on the server thread.</p>
 */
public final class StageRadii {
    private static volatile int[] overworld = {96, 225, 300, 360, 420, 480};
    private static volatile int[] nether = {0, 80, 120, 160};

    private StageRadii() {}

    /** Disc radius for the given stage, clamped to the configured stage range. */
    public static int radius(DiscProfile profile, int stage) {
        int[] radii = radiiOf(profile);
        if (stage <= 0) {
            return radii[0];
        }
        return radii[Math.min(stage, radii.length - 1)];
    }

    /** Highest stage with a configured radius. */
    public static int maxStage(DiscProfile profile) {
        return radiiOf(profile).length - 1;
    }

    /**
     * Replaces the radius table (index = stage). Worker 4 calls this from
     * {@code WorldStageService} after loading {@code stages.json}; entry 0 must stay
     * the stage-0 value (96 overworld / 0 nether).
     */
    public static void set(DiscProfile profile, int[] radii) {
        if (radii == null || radii.length == 0) {
            throw new IllegalArgumentException("Stage radii must contain at least stage 0");
        }
        int[] copy = radii.clone();
        if (profile == DiscProfile.NETHER) {
            nether = copy;
        } else {
            overworld = copy;
        }
    }

    private static int[] radiiOf(DiscProfile profile) {
        return profile == DiscProfile.NETHER ? nether : overworld;
    }
}
