package dev.projecteclipse.eclipse.worldgen;

import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * Deterministic underground cave density of the disc (worker W1.2, plan v3 D4.1): the
 * widened Perlin-worm tunnels plus the new "cheese" room layer. Pure functions of block
 * coordinates and per-column context — seeded exclusively from
 * {@link FrozenParams#mapSeed()} (noise salts 6/7 carried over from the original
 * in-terrain-function worms, salt 10 for the cheese field), never from the world seed.
 *
 * <p>Layering contract with {@link DiscTerrainFunction}: the terrain function evaluates
 * {@link #carvedAt} only inside the column's cave band ({@code caveMinY..caveMaxY},
 * where {@code caveMaxY == surfaceY} — worms may daylight naturally per D4) and outside
 * the sealed mountain cavity shell. Vanilla carvers (W1.1) and the authored
 * {@link CaveEntrances} are additive on top of this layer.</p>
 */
public final class CaveDensity {
    /**
     * Worm tunnel half-band threshold (was 0.085 pre-v2; widened per D4.1 so the tunnel
     * network reads as walkable caves rather than hairline spaghetti).
     */
    public static final double WORM_THRESHOLD = 0.11D;

    /** Cheese rooms only open at least this many blocks below the local surface. */
    public static final int CHEESE_SURFACE_MARGIN = 12;

    /** Base cheese threshold; effective threshold is lowered by depth, raised near hull. */
    private static final double CHEESE_BASE_THRESHOLD = 0.62D;
    /** Max threshold relief from depth (rooms get bigger/more common deeper down). */
    private static final double CHEESE_DEPTH_BOOST_MAX = 0.10D;
    /** Threshold relief per block of depth below the {@code surfaceY − 12} start line. */
    private static final double CHEESE_DEPTH_BOOST_PER_BLOCK = 0.0009D;
    /** Blocks above the cave floor ({@code caveMinY}) over which rooms pinch closed. */
    private static final int CHEESE_FLOOR_GUARD = 8;
    /** Threshold penalty per block inside the floor guard band (seals the underside). */
    private static final double CHEESE_FLOOR_GUARD_PER_BLOCK = 0.08D;
    /** Threshold penalty at zero rim fade (fully closes rooms near the disc rim). */
    private static final double CHEESE_RIM_PENALTY = 0.6D;

    /** Lifecycle-keyed fields; rebuilt atomically when another frozen save activates. */
    private static volatile CaveNoises caveNoises;

    private record CaveNoises(long seed, SimplexNoise caveA, SimplexNoise caveB, SimplexNoise cheese) {}

    private CaveDensity() {}

    /**
     * Whether the block at (x, y, z) is carved to cave air by worms or cheese.
     *
     * @param surfaceY the column's ground surface Y
     * @param caveMinY the column's lowest cave Y (underside + 4; the bedrock seal and
     *                 stalactite fringe stay untouched below it)
     * @param rimFade  0..1 cheese amplitude: 1 in the disc interior, easing to 0 towards
     *                 the rim taper so rooms never open the crumbly knife edge
     */
    public static boolean carvedAt(int x, int y, int z, int surfaceY, int caveMinY, double rimFade) {
        return wormAt(x, y, z) || cheeseAt(x, y, z, surfaceY, caveMinY, rimFade);
    }

    /** The widened Perlin-worm tunnel test (two orthogonal band fields intersected). */
    public static boolean wormAt(int x, int y, int z) {
        CaveNoises noises = caveNoises();
        double a = noises.caveA().getValue(x / 44.0D, y / 30.0D, z / 44.0D);
        if (Math.abs(a) >= WORM_THRESHOLD) {
            return false;
        }
        double b = noises.caveB().getValue(x / 44.0D, y / 30.0D, z / 44.0D);
        return Math.abs(b) < WORM_THRESHOLD;
    }

    /**
     * The cheese room test: 3-D simplex above a threshold that eases with depth (bigger
     * caverns down deep), pinches shut within {@value #CHEESE_FLOOR_GUARD} blocks of the
     * cave floor and fades out entirely towards the rim ({@code rimFade → 0}).
     */
    public static boolean cheeseAt(int x, int y, int z, int surfaceY, int caveMinY, double rimFade) {
        if (rimFade <= 0.0D || y > surfaceY - CHEESE_SURFACE_MARGIN) {
            return false;
        }
        double threshold = CHEESE_BASE_THRESHOLD
                - Math.min(CHEESE_DEPTH_BOOST_MAX,
                        (surfaceY - CHEESE_SURFACE_MARGIN - y) * CHEESE_DEPTH_BOOST_PER_BLOCK)
                + (1.0D - rimFade) * CHEESE_RIM_PENALTY;
        int floorGuard = caveMinY + CHEESE_FLOOR_GUARD - y;
        if (floorGuard > 0) {
            threshold += floorGuard * CHEESE_FLOOR_GUARD_PER_BLOCK;
        }
        return caveNoises().cheese().getValue(x / 56.0D, y / 36.0D, z / 56.0D) > threshold;
    }

    private static CaveNoises caveNoises() {
        long seed = FrozenParams.mapSeed();
        CaveNoises cached = caveNoises;
        if (cached == null || cached.seed() != seed) {
            synchronized (CaveDensity.class) {
                cached = caveNoises;
                if (cached == null || cached.seed() != seed) {
                    cached = new CaveNoises(seed, DiscTerrainFunction.noise(6),
                            DiscTerrainFunction.noise(7), DiscTerrainFunction.noise(10));
                    caveNoises = cached;
                }
            }
        }
        return cached;
    }
}
