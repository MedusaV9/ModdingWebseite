package dev.projecteclipse.eclipse.worldgen;

import javax.annotation.Nullable;

import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.CrossCollisionBlock;
import net.minecraft.world.level.block.PipeBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.levelgen.synth.SimplexNoise;

/**
 * Terrain-side geometry of the in-sky End disc (worker W1.2, plan v3 D12): an end-stone
 * lens of radius {@link DiscProfile#END_DISC_RADIUS} floating at
 * y ≈ {@link DiscProfile#END_DISC_SURFACE_Y} above the map center, carrying eight
 * obsidian spike pillars (heights 24–44, iron-bar cages on the two tallest), the central
 * bedrock exit-portal podium (portal basin left EMPTY — W1.8 lights the portal blocks
 * when the dragon dies and drops the egg on the pedestal) and hashed chorus fields on
 * the outer third. Requires the raised overworld build height (−176…464).
 *
 * <p>Everything is a pure function of block coordinates and
 * {@link FrozenParams#mapSeed()} (hash salt 15, noise salt 25). The terrain function
 * consults this class only while {@code FrozenParams.endDiscMaterialized()} is set;
 * W1.8's {@code EndDiscService} materializes the same columns on live chunks via the
 * budgeted writer, and chunks generated afterwards include the disc automatically.
 * End crystals are entities and belong to W1.8's {@code EndSpires}; crystal perch
 * positions are {@code (pillarX, pillarTopY() + 1, pillarZ)}.</p>
 */
public final class EndDiscGeometry {
    /** No End-disc block can exist below this Y (cheap gate for per-block queries). */
    public static final int MIN_Y = 340;

    /** Number of obsidian spike pillars. */
    public static final int PILLAR_COUNT = 8;
    /** Radius of the ring the pillar axes stand on. */
    public static final int PILLAR_RING_RADIUS = 56;
    /** Column radius of one obsidian pillar. */
    private static final double PILLAR_RADIUS = 3.2D;
    /** Iron-bar cage: ring between these radii, three blocks tall, plus a roof plate. */
    private static final double CAGE_INNER_RADIUS = 2.4D;
    private static final double CAGE_OUTER_RADIUS = 3.4D;
    private static final int CAGE_HEIGHT = 3;

    /** Podium footprint radius around the disc center. */
    private static final double PODIUM_RADIUS = 5.6D;
    /** Radius of the empty portal basin recessed into the podium deck. */
    private static final double PODIUM_BASIN_RADIUS = 2.4D;
    /** Outer radius of the raised bedrock rim ring around the basin. */
    private static final double PODIUM_RIM_RADIUS = 3.6D;
    /** Radius and height of the central egg pedestal spike. */
    private static final double PEDESTAL_RADIUS = 0.9D;
    private static final int PEDESTAL_HEIGHT = 4;

    /** Chorus fields cover the outer third: anchors between these center distances. */
    private static final double CHORUS_MIN_RADIUS = 62.0D;
    private static final double CHORUS_MAX_RADIUS = DiscProfile.END_DISC_RADIUS - 8.0D;
    /** Chance per 8×8 cell of one chorus stalk. */
    private static final double CHORUS_CHANCE = 0.30D;

    /** Lens thickness at the rim edge (center thickness is the profile constant). */
    private static final double RIM_THICKNESS = 4.0D;
    /** Amplitude of the rim wobble and (÷3) the surface undulation. */
    private static final double EDGE_WOBBLE_AMP = 6.0D;

    private static final int H_END = 15;

    private record EndLayout(long seed, SimplexNoise noise, int[] pillarTop,
            boolean[] pillarCaged) {}

    private static volatile EndLayout endLayout;

    private static final BlockState END_STONE = Blocks.END_STONE.defaultBlockState();
    private static final BlockState OBSIDIAN = Blocks.OBSIDIAN.defaultBlockState();
    private static final BlockState BEDROCK = Blocks.BEDROCK.defaultBlockState();
    private static final BlockState AIR = Blocks.AIR.defaultBlockState();
    /** Stalk segment with UP+DOWN set so pre-placed pipes render/survive as a column. */
    private static final BlockState CHORUS_STALK = Blocks.CHORUS_PLANT.defaultBlockState()
            .setValue(PipeBlock.UP, true).setValue(PipeBlock.DOWN, true);
    /** Fully-grown flower tip (age 5: decorative, never spreads — keeps the disc pure). */
    private static final BlockState CHORUS_FLOWER = Blocks.CHORUS_FLOWER.defaultBlockState()
            .setValue(BlockStateProperties.AGE_5, 5);

    private static final int[] PILLAR_X = new int[PILLAR_COUNT];
    private static final int[] PILLAR_Z = new int[PILLAR_COUNT];
    /** Highest possible Y any End-disc block can occupy (maximum-height cage roof). */
    public static final int MAX_Y =
            DiscProfile.END_DISC_SURFACE_Y + 44 + CAGE_HEIGHT + 1;

    static {
        for (int i = 0; i < PILLAR_COUNT; i++) {
            double angle = Math.toRadians(i * (360.0D / PILLAR_COUNT) + 22.5D);
            PILLAR_X[i] = DiscProfile.END_DISC_CENTER_X
                    + (int) Math.round(Math.cos(angle) * PILLAR_RING_RADIUS);
            PILLAR_Z[i] = DiscProfile.END_DISC_CENTER_Z
                    + (int) Math.round(Math.sin(angle) * PILLAR_RING_RADIUS);
        }
    }

    private EndDiscGeometry() {}

    /**
     * Returns the noise and pillar layout for the active frozen map seed. The immutable
     * snapshot is rebuilt atomically when another save activates in the same JVM.
     */
    private static EndLayout endLayout() {
        long seed = FrozenParams.mapSeed();
        EndLayout cached = endLayout;
        if (cached == null || cached.seed() != seed) {
            synchronized (EndDiscGeometry.class) {
                cached = endLayout;
                if (cached == null || cached.seed() != seed) {
                    int[] tops = new int[PILLAR_COUNT];
                    boolean[] cages = new boolean[PILLAR_COUNT];
                    for (int i = 0; i < PILLAR_COUNT; i++) {
                        long h = DiscTerrainFunction.hash(H_END, i, 77);
                        tops[i] = DiscProfile.END_DISC_SURFACE_Y
                                + 24 + (int) (DiscTerrainFunction.to01(h) * 21.0D);
                    }
                    // Iron-bar cages on the two tallest pillars (matches vanilla's caged crystals).
                    int tallest = 0;
                    for (int i = 1; i < PILLAR_COUNT; i++) {
                        if (tops[i] > tops[tallest]) {
                            tallest = i;
                        }
                    }
                    int second = tallest == 0 ? 1 : 0;
                    for (int i = 0; i < PILLAR_COUNT; i++) {
                        if (i != tallest && tops[i] > tops[second]) {
                            second = i;
                        }
                    }
                    cages[tallest] = true;
                    cages[second] = true;
                    cached = new EndLayout(seed, DiscTerrainFunction.noise(25), tops, cages);
                    endLayout = cached;
                }
            }
        }
        return cached;
    }

    /** Whether column (x, z) can carry End-disc blocks (radius + wobble margin). */
    public static boolean footprintContains(int x, int z) {
        double dx = x - DiscProfile.END_DISC_CENTER_X;
        double dz = z - DiscProfile.END_DISC_CENTER_Z;
        double reach = DiscProfile.END_DISC_RADIUS + EDGE_WOBBLE_AMP + 2.0D;
        return dx * dx + dz * dz <= reach * reach;
    }

    /** Whether (x, y, z) lies inside the End-disc envelope (coarse bounding volume). */
    public static boolean contains(int x, int y, int z) {
        return y >= MIN_Y && y <= MAX_Y && footprintContains(x, z);
    }

    /** Lens ground surface Y of column (x, z) (undulates ±2 around the profile constant). */
    public static int surfaceYAt(int x, int z) {
        return DiscProfile.END_DISC_SURFACE_Y
                + (int) Math.round(endLayout().noise().getValue(x / 40.0D, z / 40.0D) * 2.0D);
    }

    /** Crystal perch position provider for W1.8 ({@code EndSpires}). */
    public static int pillarX(int index) {
        return PILLAR_X[index];
    }

    public static int pillarZ(int index) {
        return PILLAR_Z[index];
    }

    public static int pillarTopY(int index) {
        return endLayout().pillarTop()[index];
    }

    public static boolean pillarCaged(int index) {
        return endLayout().pillarCaged()[index];
    }

    /**
     * Highest Y any End-disc block can occupy in column (x, z), or
     * {@code Integer.MIN_VALUE} outside the footprint. A cheap upper bound (may overshoot
     * by a few blocks over the podium ring) used to extend column {@code topY}.
     */
    public static int topYAt(int x, int z) {
        if (!footprintContains(x, z)) {
            return Integer.MIN_VALUE;
        }
        int sY = surfaceYAt(x, z);
        int top = sY;
        double cdx = x - DiscProfile.END_DISC_CENTER_X;
        double cdz = z - DiscProfile.END_DISC_CENTER_Z;
        if (cdx * cdx + cdz * cdz <= PODIUM_RADIUS * PODIUM_RADIUS) {
            top = Math.max(top, sY + PEDESTAL_HEIGHT);
        }
        for (int i = 0; i < PILLAR_COUNT; i++) {
            double dx = x - PILLAR_X[i];
            double dz = z - PILLAR_Z[i];
            if (dx * dx + dz * dz <= (CAGE_OUTER_RADIUS + 0.2D) * (CAGE_OUTER_RADIUS + 0.2D)) {
                top = Math.max(top, pillarTopY(i) + (pillarCaged(i) ? CAGE_HEIGHT + 1 : 0));
            }
        }
        ChorusStalk stalk = chorusAt(x, z);
        if (stalk != null) {
            top = Math.max(top, sY + stalk.height() + 1);
        }
        return top;
    }

    /**
     * The End-disc block at (x, y, z), or null where the disc contributes nothing.
     * Pure; safe on worldgen worker threads.
     */
    @Nullable
    public static BlockState stateAt(int x, int y, int z) {
        if (y < MIN_Y || y > MAX_Y) {
            return null;
        }
        double cdx = x - DiscProfile.END_DISC_CENTER_X;
        double cdz = z - DiscProfile.END_DISC_CENTER_Z;
        double distSq = cdx * cdx + cdz * cdz;
        double reach = DiscProfile.END_DISC_RADIUS + EDGE_WOBBLE_AMP + 2.0D;
        if (distSq > reach * reach) {
            return null;
        }
        double dist = Math.sqrt(distSq);
        int sY = surfaceYAt(x, z);

        // Exit-portal podium overrides (center): pedestal spike, EMPTY portal basin
        // (W1.8 fills it with minecraft:end_portal on dragon death), raised rim ring.
        if (dist <= PODIUM_RADIUS) {
            if (dist <= PEDESTAL_RADIUS && y >= sY && y <= sY + PEDESTAL_HEIGHT) {
                return BEDROCK; // egg pedestal (egg lands at sY + PEDESTAL_HEIGHT + 1)
            }
            if (y == sY) {
                return dist <= PODIUM_BASIN_RADIUS ? AIR : BEDROCK; // basin recess / deck
            }
            if (y == sY - 1) {
                return BEDROCK; // basin floor the portal blocks will sit on
            }
            if (y == sY + 1 && dist > PODIUM_BASIN_RADIUS && dist <= PODIUM_RIM_RADIUS) {
                return BEDROCK; // raised rim ring
            }
        }

        if (y > sY) {
            // Obsidian spike pillars + iron-bar cages on the two tallest.
            for (int i = 0; i < PILLAR_COUNT; i++) {
                double dx = x - PILLAR_X[i];
                double dz = z - PILLAR_Z[i];
                double pillarDistSq = dx * dx + dz * dz;
                if (pillarDistSq > (CAGE_OUTER_RADIUS + 0.2D) * (CAGE_OUTER_RADIUS + 0.2D)) {
                    continue;
                }
                if (pillarDistSq <= PILLAR_RADIUS * PILLAR_RADIUS && y <= pillarTopY(i)) {
                    return OBSIDIAN;
                }
                if (pillarCaged(i)) {
                    BlockState cage = cageState(x, y, z, i, pillarDistSq);
                    if (cage != null) {
                        return cage;
                    }
                }
            }
            // Chorus stalks on the outer third.
            ChorusStalk stalk = chorusAt(x, z);
            if (stalk != null) {
                if (y <= sY + stalk.height()) {
                    return CHORUS_STALK;
                }
                if (y == sY + stalk.height() + 1) {
                    return CHORUS_FLOWER;
                }
            }
            return null;
        }

        // Lens body: thickness tapers from the center constant to ~4 at the wobbled rim.
        double angle = Math.atan2(cdz, cdx);
        double rimRadius = DiscProfile.END_DISC_RADIUS
                + endLayout().noise().getValue(Math.cos(angle) * 5.0D, Math.sin(angle) * 5.0D)
                        * EDGE_WOBBLE_AMP;
        if (dist > rimRadius) {
            return null;
        }
        double norm = dist / rimRadius;
        double thickness = RIM_THICKNESS
                + (DiscProfile.END_DISC_THICKNESS - RIM_THICKNESS) * (1.0D - norm * norm);
        if (y >= sY - (int) thickness) {
            return END_STONE;
        }
        return null;
    }

    /** Iron-bar cage cell of pillar {@code i}, with ring-neighbour connections set. */
    @Nullable
    private static BlockState cageState(int x, int y, int z, int i, double pillarDistSq) {
        int top = pillarTopY(i);
        boolean ring = y > top && y <= top + CAGE_HEIGHT
                && pillarDistSq > CAGE_INNER_RADIUS * CAGE_INNER_RADIUS
                && pillarDistSq <= CAGE_OUTER_RADIUS * CAGE_OUTER_RADIUS;
        boolean roof = y == top + CAGE_HEIGHT + 1
                && pillarDistSq <= CAGE_OUTER_RADIUS * CAGE_OUTER_RADIUS;
        if (!ring && !roof) {
            return null;
        }
        // Section writes never run shape updates, so connect the bars analytically.
        BlockState bars = Blocks.IRON_BARS.defaultBlockState();
        bars = bars.setValue(CrossCollisionBlock.NORTH, cageMember(x, z - 1, i, ring));
        bars = bars.setValue(CrossCollisionBlock.SOUTH, cageMember(x, z + 1, i, ring));
        bars = bars.setValue(CrossCollisionBlock.WEST, cageMember(x - 1, z, i, ring));
        bars = bars.setValue(CrossCollisionBlock.EAST, cageMember(x + 1, z, i, ring));
        return bars;
    }

    /** Whether (x, z) belongs to pillar {@code i}'s cage ring (or roof plate). */
    private static boolean cageMember(int x, int z, int i, boolean ring) {
        double dx = x - PILLAR_X[i];
        double dz = z - PILLAR_Z[i];
        double distSq = dx * dx + dz * dz;
        if (distSq > CAGE_OUTER_RADIUS * CAGE_OUTER_RADIUS) {
            return false;
        }
        return !ring || distSq > CAGE_INNER_RADIUS * CAGE_INNER_RADIUS;
    }

    private record ChorusStalk(int height) {}

    /** The chorus stalk rooted exactly at column (x, z), or null. One roll per 8×8 cell. */
    @Nullable
    private static ChorusStalk chorusAt(int x, int z) {
        int cellX = Math.floorDiv(x, 8);
        int cellZ = Math.floorDiv(z, 8);
        long h = DiscTerrainFunction.hash(H_END, cellX, cellZ);
        if (DiscTerrainFunction.to01(h) >= CHORUS_CHANCE) {
            return null;
        }
        int ax = cellX * 8 + 2 + (int) ((h >>> 20) & 0xFFL) % 5; // margin-clamped anchor
        int az = cellZ * 8 + 2 + (int) ((h >>> 28) & 0xFFL) % 5;
        if (ax != x || az != z) {
            return null;
        }
        double adx = ax - DiscProfile.END_DISC_CENTER_X;
        double adz = az - DiscProfile.END_DISC_CENTER_Z;
        double anchorDistSq = adx * adx + adz * adz;
        if (anchorDistSq < CHORUS_MIN_RADIUS * CHORUS_MIN_RADIUS
                || anchorDistSq > CHORUS_MAX_RADIUS * CHORUS_MAX_RADIUS) {
            return null;
        }
        return new ChorusStalk(3 + (int) ((h >>> 36) & 3L)); // 3..6
    }
}
