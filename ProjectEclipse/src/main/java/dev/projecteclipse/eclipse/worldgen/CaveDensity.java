package dev.projecteclipse.eclipse.worldgen;

import javax.annotation.Nullable;

import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * Deterministic underground cave density of the disc (worker W1.2, plan v3 D4.1): the
 * widened Perlin-worm tunnels, the "cheese" room layer, and — plans_v5 B12 — the sparse
 * "cathedral" giant-cave layer. Pure functions of block coordinates and per-column
 * context — seeded exclusively from {@link FrozenParams#mapSeed()} (noise salts 6/7
 * carried over from the original in-terrain-function worms, salt 10 for the cheese
 * field, salt 34 for the cathedral wall wobble; cathedral cell rolls use the map-seed
 * hash family under salt {@value #SALT_CATHEDRAL}), never from the world seed.
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

    // --- cathedral giant-cave layer (plans_v5 B12) ---

    /** Edge length of one cathedral cell; at most one chamber rolls per 64³ cell. */
    public static final int CATHEDRAL_CELL = 64;
    /**
     * Cathedral blocks never carve at/above this Y: the disc surface sits at ~64+, so
     * chambers stay deep and can never daylight (belt; the per-cell ceiling cap below
     * is braces).
     */
    public static final int CATHEDRAL_MAX_Y = 20;
    /** Chamber ceilings ({@code cy + rY}) must stay this far under the hard Y gate. */
    private static final int CATHEDRAL_CEILING_MARGIN = 4;
    /** Share of cathedral cells that actually host a chamber (~1-in-9 — big but RARE). */
    private static final double CATHEDRAL_CELL_CHANCE = 0.11D;
    /** Horizontal semi-axis range of a chamber (blocks). */
    private static final int CATHEDRAL_R_XZ_MIN = 18;
    private static final int CATHEDRAL_R_XZ_MAX = 28;
    /** Vertical semi-axis range of a chamber (blocks). */
    private static final int CATHEDRAL_R_Y_MIN = 12;
    private static final int CATHEDRAL_R_Y_MAX = 18;
    /** Wall wobble amplitude of the large-scale simplex modulation (organic rims). */
    private static final double CATHEDRAL_WOBBLE = 0.22D;
    /** Blocks above the cave floor over which chambers pinch shut (underside stays sealed). */
    private static final int CATHEDRAL_FLOOR_GUARD = 10;
    /** Membership penalty per block inside the floor-guard band. */
    private static final double CATHEDRAL_FLOOR_GUARD_PER_BLOCK = 0.12D;
    /** Chambers need nearly full rim fade — they never open near the disc rim taper. */
    private static final double CATHEDRAL_MIN_RIM_FADE = 0.85D;
    /** Map-seed hash salt of the cathedral cell rolls (31+ free family, B12). */
    private static final int SALT_CATHEDRAL = 35;

    /** Lifecycle-keyed fields; rebuilt atomically when another frozen save activates. */
    private static volatile CaveNoises caveNoises;

    private record CaveNoises(long seed, SimplexNoise caveA, SimplexNoise caveB, SimplexNoise cheese,
            SimplexNoise cathedral) {}

    /**
     * One cathedral chamber, fully derived from its cell hash: center {@code (cx, cy,
     * cz)}, horizontal semi-axis {@code rXz} and vertical semi-axis {@code rY}. The
     * chamber ellipsoid (plus wobble) always fits inside its own 64³ cell, so membership
     * tests only ever consult the block's own cell. Exposed for {@code CaveDressings}.
     */
    public record Chamber(int cx, int cy, int cz, int rXz, int rY) {}

    private CaveDensity() {}

    /**
     * Whether the block at (x, y, z) is carved to cave air by worms, cheese or a
     * cathedral chamber.
     *
     * @param surfaceY the column's ground surface Y
     * @param caveMinY the column's lowest cave Y (underside + 4; the bedrock seal and
     *                 stalactite fringe stay untouched below it)
     * @param rimFade  0..1 cheese amplitude: 1 in the disc interior, easing to 0 towards
     *                 the rim taper so rooms never open the crumbly knife edge
     */
    public static boolean carvedAt(int x, int y, int z, int surfaceY, int caveMinY, double rimFade) {
        return wormAt(x, y, z) || cheeseAt(x, y, z, surfaceY, caveMinY, rimFade)
                || cathedralAt(x, y, z, surfaceY, caveMinY, rimFade);
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

    /**
     * The cathedral giant-cave test (plans_v5 B12): rare, hash-selected 64³ cells host
     * one large simplex-wobbled ellipsoid chamber (r up to ~{@value #CATHEDRAL_R_XZ_MAX}
     * XZ / ~{@value #CATHEDRAL_R_Y_MAX} Y). Same floor-guard/rim-fade discipline as the
     * cheese layer, plus a hard {@code y < }{@value #CATHEDRAL_MAX_Y} depth gate so a
     * chamber can never daylight.
     */
    public static boolean cathedralAt(int x, int y, int z, int surfaceY, int caveMinY, double rimFade) {
        if (rimFade < CATHEDRAL_MIN_RIM_FADE || y >= CATHEDRAL_MAX_Y
                || y > surfaceY - CHEESE_SURFACE_MARGIN || y < caveMinY) {
            return false;
        }
        Chamber chamber = chamberAt(Math.floorDiv(x, CATHEDRAL_CELL),
                Math.floorDiv(y, CATHEDRAL_CELL), Math.floorDiv(z, CATHEDRAL_CELL));
        if (chamber == null) {
            return false;
        }
        double nx = (x - chamber.cx()) / (double) chamber.rXz();
        double ny = (y - chamber.cy()) / (double) chamber.rY();
        double nz = (z - chamber.cz()) / (double) chamber.rXz();
        double d = nx * nx + ny * ny + nz * nz;
        if (d > 1.0D + CATHEDRAL_WOBBLE) {
            return false; // outside even the maximum wall wobble — skip the noise eval
        }
        double threshold = 1.0D
                + caveNoises().cathedral().getValue(x / 26.0D, y / 20.0D, z / 26.0D) * CATHEDRAL_WOBBLE;
        int floorGuard = caveMinY + CATHEDRAL_FLOOR_GUARD - y;
        if (floorGuard > 0) {
            threshold -= floorGuard * CATHEDRAL_FLOOR_GUARD_PER_BLOCK;
        }
        return d <= threshold;
    }

    /**
     * The chamber of one cathedral cell, or {@code null} when the cell rolled none (or
     * its ceiling would breach the {@value #CATHEDRAL_MAX_Y} depth gate). Pure function
     * of the frozen map seed + cell coordinates; the chamber ellipsoid always fits
     * inside its own cell (2-block margin), so cross-cell lookups are never needed.
     */
    @Nullable
    public static Chamber chamberAt(int cellX, int cellY, int cellZ) {
        long h = hash(SALT_CATHEDRAL, cellX, cellY, cellZ);
        if (to01(h) >= CATHEDRAL_CELL_CHANCE) {
            return null;
        }
        int rXz = CATHEDRAL_R_XZ_MIN
                + (int) ((h >>> 8) & 0xFFL) % (CATHEDRAL_R_XZ_MAX - CATHEDRAL_R_XZ_MIN + 1);
        int rY = CATHEDRAL_R_Y_MIN
                + (int) ((h >>> 16) & 0xFFL) % (CATHEDRAL_R_Y_MAX - CATHEDRAL_R_Y_MIN + 1);
        int spanXz = CATHEDRAL_CELL - 2 * (rXz + 2);
        int spanY = CATHEDRAL_CELL - 2 * (rY + 2);
        int cx = cellX * CATHEDRAL_CELL + rXz + 2 + (int) ((h >>> 24) & 0x7FFFL) % spanXz;
        int cy = cellY * CATHEDRAL_CELL + rY + 2 + (int) ((h >>> 40) & 0x7FFFL) % spanY;
        int cz = cellZ * CATHEDRAL_CELL + rXz + 2 + (int) ((h >>> 48) & 0x7FFFL) % spanXz;
        if (cy + rY > CATHEDRAL_MAX_Y - CATHEDRAL_CEILING_MARGIN) {
            return null; // chamber would reach too high — only deep cells qualify
        }
        return new Chamber(cx, cy, cz, rXz, rY);
    }

    private static CaveNoises caveNoises() {
        long seed = FrozenParams.mapSeed();
        CaveNoises cached = caveNoises;
        if (cached == null || cached.seed() != seed) {
            synchronized (CaveDensity.class) {
                cached = caveNoises;
                if (cached == null || cached.seed() != seed) {
                    cached = new CaveNoises(seed, DiscTerrainFunction.noise(6),
                            DiscTerrainFunction.noise(7), DiscTerrainFunction.noise(10),
                            DiscTerrainFunction.noise(34));
                    caveNoises = cached;
                }
            }
        }
        return cached;
    }

    /** Salted map-seed cell hash (same mixer family as the decor stamps). */
    private static long hash(int salt, int x, int y, int z) {
        long h = FrozenParams.mapSeed() + (long) salt * 0x9E3779B97F4A7C15L;
        h ^= (long) x * 341873128712L;
        h ^= (long) y * 986534123L;
        h ^= (long) z * 132897987541L;
        h ^= h >>> 30;
        h *= 0xBF58476D1CE4E5B9L;
        h ^= h >>> 27;
        h *= 0x94D049BB133111EBL;
        return h ^ h >>> 31;
    }

    private static double to01(long hash) {
        return (hash >>> 11) * 0x1.0p-53D;
    }
}
