package dev.projecteclipse.eclipse.worldgen.structure;

import dev.projecteclipse.eclipse.EclipseMod;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.AmethystClusterBlock;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;

/**
 * P6-W4 (plans_v3 §2.6): the wound the floating sanctum island was torn out of — a
 * r={@value #RADIUS} bowl carved {@value #MAX_DEPTH} deep into the flattened spawn
 * grounds, directly below the island.
 *
 * <p>Composition (all deterministic via {@link FallbackBuilders#hash01}, zero
 * {@code RandomSource}):</p>
 * <ul>
 *   <li><b>Bowl:</b> parabolic depth profile with a hash roughness bite, terraced rings
 *       exposing strata — heart (blackstone/basalt/soul-soil/crying-obsidian), mid strata
 *       (tuff/deepslate/coarse dirt), scorch ring (blackstone + soul-soil flecks) at the
 *       lip; one sub-floor deepslate/tuff layer so terrace edges read as a cut.</li>
 *   <li><b>Rubble:</b> boulder clumps (2–3 blocks) partially sunk into the bowl, sparse
 *       {@code glow_lichen} pips, and three snapped purpur pillar stumps fallen at
 *       angles — the pillars' echo, ripped off the ascending island.</li>
 *   <li><b>Rim:</b> a broken blast-rubble ring on the crater lip (r 12..13.5), with the
 *       south walk sector ({@code dz > 0, |dx| <=} {@value #WALK_SECTOR_HALF_WIDTH})
 *       kept clear so the day-1 spawn-to-bridge walk is never blocked.</li>
 * </ul>
 *
 * <p>Build order contract: runs AFTER {@link FloatingSanctumBuilder} stamped the island
 * mass (the island's airspace clear would otherwise erase the rim rubble) and BEFORE the
 * bridge/access pass (which re-stamps the trailhead cells over the crater lip).</p>
 */
public final class SanctumCrater {
    /** Bowl radius (matches plan §2.6 "r=12 bowl 4 deep"). */
    public static final int RADIUS = 12;
    /** Center depth of the bowl below the flattened ground surface. */
    public static final int MAX_DEPTH = 4;
    /** Outer radius of the broken rim-rubble ring. */
    public static final double RIM_OUTER_RADIUS = 13.5D;
    /** Half-width of the rubble-free south walk sector (spawn → bridge on foot). */
    public static final int WALK_SECTOR_HALF_WIDTH = 6;

    /** Fallen pillar stumps: {angleDeg, ringRadius, length, alongX?} — south walk avoided. */
    private static final int[][] STUMPS = {{150, 6, 4, 1}, {255, 7, 3, 0}, {25, 5, 5, 1}};
    /** Rubble boulders: {angleDeg, ringRadius, size} — south walk avoided. */
    private static final int[][] BOULDERS = {
            {15, 7, 3}, {60, 9, 2}, {150, 6, 3}, {200, 8, 2}, {250, 5, 2}, {300, 9, 3}, {340, 7, 2}};

    private SanctumCrater() {}

    /**
     * Parabolic carve depth below ground at offset (dx, dz) from the crater center —
     * 0 outside r={@value #RADIUS}. Pure geometry (no roughness), exposed for P4's
     * edge/fall-safety queries and W5's polish pass.
     */
    public static int depthAt(int dx, int dz) {
        int rr2 = dx * dx + dz * dz;
        if (rr2 > RADIUS * RADIUS) {
            return 0;
        }
        return (int) Math.round(MAX_DEPTH * (1.0D - rr2 / (double) (RADIUS * RADIUS)));
    }

    /** Carves and dresses the crater centered on (cx, cz) with ground surface {@code groundY}. */
    static void build(ServerLevel level, int cx, int cz, int groundY) {
        carveBowl(level, cx, cz, groundY);
        placeBoulders(level, cx, cz, groundY);
        placeStumps(level, cx, cz, groundY);
        placeWoundDecor(level, cx, cz, groundY);
        EclipseMod.LOGGER.info("Sanctum crater carved: center ({}, {}, {}), r={}, floor y{}..y{}",
                cx, groundY, cz, RADIUS, groundY - MAX_DEPTH, groundY);
    }

    /** Bowl carve + strata floor + sub-floor layer + rim rubble ring. */
    private static void carveBowl(ServerLevel level, int cx, int cz, int groundY) {
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int bound = (int) Math.ceil(RIM_OUTER_RADIUS);
        for (int dx = -bound; dx <= bound; dx++) {
            for (int dz = -bound; dz <= bound; dz++) {
                double rr = Math.sqrt(dx * dx + dz * dz);
                if (rr > RIM_OUTER_RADIUS) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                level.getChunk(x >> 4, z >> 4);
                if (rr <= RADIUS) {
                    int depth = roughDepth(x, z, dx, dz);
                    int floorY = groundY - depth;
                    for (int y = floorY + 1; y <= groundY; y++) {
                        cursor.set(x, y, z);
                        if (!level.getBlockState(cursor).isAir()) {
                            level.setBlock(cursor, air, 2);
                        }
                    }
                    set(level, new BlockPos(x, floorY, z), floorMix(x, z, rr));
                    if (depth > 0 && FallbackBuilders.hash01(x, 111, z) < 0.60D) {
                        set(level, new BlockPos(x, floorY - 1, z), subFloorMix(x, z));
                    }
                } else if (!inWalkSector(dx, dz) && FallbackBuilders.hash01(x, 103, z) < 0.38D) {
                    // Broken blast-rubble ring on the lip.
                    set(level, new BlockPos(x, groundY + 1, z), rubbleMix(x, groundY + 1, z));
                    if (FallbackBuilders.hash01(x, 104, z) < 0.18D) {
                        set(level, new BlockPos(x, groundY + 2, z), rubbleMix(x, groundY + 2, z));
                    }
                }
            }
        }
    }

    /** {@link #depthAt} plus a deterministic +1 "bite" on ~22% of mid-bowl columns. */
    private static int roughDepth(int x, int z, int dx, int dz) {
        int depth = depthAt(dx, dz);
        double rr2 = dx * dx + dz * dz;
        if (depth > 0 && depth < MAX_DEPTH && rr2 > 4.0D
                && FallbackBuilders.hash01(x, 101, z) < 0.22D) {
            depth++;
        }
        return depth;
    }

    /** Exposed strata by ring: heart core → mid strata → scorch ring at the lip. */
    private static BlockState floorMix(int x, int z, double rr) {
        double h = FallbackBuilders.hash01(x, 109, z);
        if (rr < 3.2D) {
            if (h < 0.10D) return Blocks.CRYING_OBSIDIAN.defaultBlockState();
            if (h < 0.18D) return Blocks.OBSIDIAN.defaultBlockState();
            if (h < 0.40D) return Blocks.BASALT.defaultBlockState();
            if (h < 0.62D) return Blocks.BLACKSTONE.defaultBlockState();
            if (h < 0.80D) return Blocks.SOUL_SOIL.defaultBlockState();
            return Blocks.BLACKSTONE.defaultBlockState();
        }
        if (rr < 9.5D) {
            if (h < 0.30D) return Blocks.TUFF.defaultBlockState();
            if (h < 0.55D) return Blocks.DEEPSLATE.defaultBlockState();
            if (h < 0.75D) return Blocks.COARSE_DIRT.defaultBlockState();
            if (h < 0.88D) return Blocks.BLACKSTONE.defaultBlockState();
            return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
        }
        // Scorch ring (plan: blackstone + soul soil flecks).
        if (h < 0.38D) return Blocks.BLACKSTONE.defaultBlockState();
        if (h < 0.58D) return Blocks.SOUL_SOIL.defaultBlockState();
        if (h < 0.75D) return Blocks.COARSE_DIRT.defaultBlockState();
        if (h < 0.88D) return Blocks.BASALT.defaultBlockState();
        return Blocks.TUFF.defaultBlockState();
    }

    private static BlockState subFloorMix(int x, int z) {
        return FallbackBuilders.hash01(x, 113, z) < 0.55D
                ? Blocks.DEEPSLATE.defaultBlockState()
                : Blocks.TUFF.defaultBlockState();
    }

    private static BlockState rubbleMix(int x, int y, int z) {
        double h = FallbackBuilders.hash01(x, y, z);
        if (h < 0.40D) return Blocks.BLACKSTONE.defaultBlockState();
        if (h < 0.70D) return Blocks.COBBLED_DEEPSLATE.defaultBlockState();
        return Blocks.TUFF.defaultBlockState();
    }

    /** The spawn→bridge approach must never be cluttered by rim rubble. */
    private static boolean inWalkSector(int dx, int dz) {
        return dz > 0 && Math.abs(dx) <= WALK_SECTOR_HALF_WIDTH;
    }

    /** Hash-carved 2–3 block boulder clumps, partially sunk, some with glow lichen. */
    private static void placeBoulders(ServerLevel level, int cx, int cz, int groundY) {
        for (int[] boulder : BOULDERS) {
            double angle = Math.toRadians(boulder[0]);
            int bx = cx + (int) Math.round(Math.cos(angle) * boulder[1]);
            int bz = cz + (int) Math.round(Math.sin(angle) * boulder[1]);
            int size = boulder[2];
            int baseY = groundY - roughDepth(bx, bz, bx - cx, bz - cz) - 1; // sunk 1 into the floor
            int topPlaced = baseY;
            for (int ox = 0; ox < size; ox++) {
                for (int oy = 0; oy < size; oy++) {
                    for (int oz = 0; oz < size; oz++) {
                        int x = bx + ox;
                        int y = baseY + oy;
                        int z = bz + oz;
                        if (FallbackBuilders.hash01(x, y, z) < 0.62D) {
                            set(level, new BlockPos(x, y, z), rubbleMix(x, y, z));
                            topPlaced = Math.max(topPlaced, y);
                        }
                    }
                }
            }
            if (FallbackBuilders.hash01(bx, 115, bz) < 0.55D) {
                BlockPos lichen = new BlockPos(bx, topPlaced + 1, bz);
                if (level.getBlockState(lichen).isAir()
                        && level.getBlockState(lichen.below()).isSolidRender(level, lichen.below())) {
                    set(level, lichen, Blocks.GLOW_LICHEN.defaultBlockState()
                            .setValue(BlockStateProperties.DOWN, true));
                }
            }
        }
    }

    /** Three snapped purpur pillar fragments lying in the bowl (the ripped-off echoes). */
    private static void placeStumps(ServerLevel level, int cx, int cz, int groundY) {
        for (int[] stump : STUMPS) {
            double angle = Math.toRadians(stump[0]);
            int sx = cx + (int) Math.round(Math.cos(angle) * stump[1]);
            int sz = cz + (int) Math.round(Math.sin(angle) * stump[1]);
            boolean alongX = stump[3] == 1;
            Direction.Axis axis = alongX ? Direction.Axis.X : Direction.Axis.Z;
            for (int i = 0; i < stump[2]; i++) {
                int x = sx + (alongX ? i : 0);
                int z = sz + (alongX ? 0 : i);
                int y = groundY - roughDepth(x, z, x - cx, z - cz) + 1;
                set(level, new BlockPos(x, y, z),
                        Blocks.PURPUR_PILLAR.defaultBlockState().setValue(RotatedPillarBlock.AXIS, axis));
                // Socket shadow: scorched floor right under the fallen shaft.
                set(level, new BlockPos(x, y - 1, z), Blocks.BLACKSTONE.defaultBlockState());
            }
            // The torn 2×2 base chunk it snapped off from, beside the fragment.
            int ox = sx - (alongX ? 1 : 0);
            int oz = sz - (alongX ? 0 : 1);
            int oy = groundY - roughDepth(ox, oz, ox - cx, oz - cz) + 1;
            set(level, new BlockPos(ox, oy, oz), Blocks.OBSIDIAN.defaultBlockState());
        }
    }

    /** Center wound veins (crying obsidian), 2 amethyst glints, sparse glow lichen. */
    private static void placeWoundDecor(ServerLevel level, int cx, int cz, int groundY) {
        // Crying-obsidian veins bleeding through the heart of the wound.
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = -2; dz <= 2; dz++) {
                double rr = Math.sqrt(dx * dx + dz * dz);
                int x = cx + dx;
                int z = cz + dz;
                if (rr < 2.5D && FallbackBuilders.hash01(x, 117, z) < 0.30D) {
                    set(level, new BlockPos(x, groundY - roughDepth(x, z, dx, dz), z),
                            Blocks.CRYING_OBSIDIAN.defaultBlockState());
                }
            }
        }
        // Two amethyst clusters glinting up out of the wound.
        placeClusterUp(level, cx, cz, 1, -1, groundY);
        placeClusterUp(level, cx, cz, -2, 1, groundY);
        // Sparse glow lichen across the mid bowl.
        for (int dx = -10; dx <= 10; dx++) {
            for (int dz = -10; dz <= 10; dz++) {
                double rr = Math.sqrt(dx * dx + dz * dz);
                if (rr < 3.0D || rr > 10.0D) {
                    continue;
                }
                int x = cx + dx;
                int z = cz + dz;
                if (FallbackBuilders.hash01(x, 119, z) < 0.05D) {
                    BlockPos pos = new BlockPos(x, groundY - roughDepth(x, z, dx, dz) + 1, z);
                    if (level.getBlockState(pos).isAir()
                            && level.getBlockState(pos.below()).isSolidRender(level, pos.below())) {
                        set(level, pos, Blocks.GLOW_LICHEN.defaultBlockState()
                                .setValue(BlockStateProperties.DOWN, true));
                    }
                }
            }
        }
    }

    private static void placeClusterUp(ServerLevel level, int cx, int cz, int dx, int dz, int groundY) {
        int x = cx + dx;
        int z = cz + dz;
        int floorY = groundY - roughDepth(x, z, dx, dz);
        BlockPos pos = new BlockPos(x, floorY + 1, z);
        set(level, pos.below(), Blocks.BLACKSTONE.defaultBlockState());
        set(level, pos, Blocks.AMETHYST_CLUSTER.defaultBlockState()
                .setValue(AmethystClusterBlock.FACING, Direction.UP));
    }

    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_ALL);
    }
}
