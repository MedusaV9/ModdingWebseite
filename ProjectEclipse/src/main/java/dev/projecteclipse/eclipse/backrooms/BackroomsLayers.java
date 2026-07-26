package dev.projecteclipse.eclipse.backrooms;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * The Backrooms LAYER STACK terrain function — the {@code DiscTerrainFunction} role for
 * the {@code eclipse:backrooms} dimension. Three classic backrooms levels are stacked in
 * one 64-block-tall dimension and generated PROCEDURALLY per chunk by
 * {@link BackroomsChunkGenerator} (terrain gen, not a pre-built stamp), infinite in X/Z:
 *
 * <ul>
 *   <li><b>Level 0 — the Yellow Rooms</b> (floor y={@value #Y_FLOOR}, top): the original
 *       mono-yellow maze — {@link BackroomsMaze}'s hash-driven 8×8-block cell math
 *       (bond percolation walls, highway lanes, prefab rooms, froglight panels),
 *       extended to an INFINITE cell grid. Hashed {@code DROP_SHAFT} cells open a 2×2
 *       no-clip pit through the floor (rimmed with stained concrete powder) that drops
 *       into a guaranteed water basin of the Poolrooms below.</li>
 *   <li><b>Level 1 — the Poolrooms</b> (floor y={@value #P_FLOOR_TOP}): vast echoing
 *       smooth-quartz halls on a 16×16 grid, sunken 2-deep water basins lit from below
 *       by sea lanterns. Hashed DRAIN cells open a 2×2 hole in a forced basin's floor —
 *       the water spills through it as a waterfall into the Warehouse.</li>
 *   <li><b>Level 2 — the Warehouse</b> (floor y={@value #W_BASE_TOP}, deepest): a dark
 *       12-block-tall basalt-pillar hall on the same 16×16 grid, tuff walls, hashed
 *       plank crate stacks, sparse shroomlight — the deepest and darkest level. Drain
 *       landings are 4×4 rimmed water basins (fall-safe).</li>
 * </ul>
 *
 * <p>Descent is one-way through the shafts/drains (every landing is water — no fall
 * damage); {@code /backroomsleave}, deaths and the closing sweep exit players from ANY
 * layer. Every block is a pure O(1) function of {@code (seed, x, y, z)} — the same
 * stateless-hash law the old stamped maze followed, so the generator is deterministic,
 * chunk-local and thread-safe with no global solver.</p>
 */
public final class BackroomsLayers {

    /** The three generated levels, top to bottom. */
    public enum Layer { YELLOW_ROOMS, POOLROOMS, WAREHOUSE }

    // ------------------------------------------------------------------ Y bands (0..63)

    /** Warehouse: solid base 0..{@value}, walk on {@value #W_WALK_Y}. */
    public static final int W_BASE_TOP = 8;
    public static final int W_WALK_Y = 9;
    /** Warehouse interior top (12-block hall). */
    public static final int W_AIR_TOP = 20;
    public static final int W_CEIL = 21;

    /** Pool→warehouse interstitial: {@value #W_CEIL}+1..{@value #P_BASIN_FLOOR} solid. */
    public static final int P_BASIN_FLOOR = 26;
    public static final int P_WATER_LO = 27;
    /** Poolrooms walk floor top (= basin water surface), walk on {@value #P_WALK_Y}. */
    public static final int P_FLOOR_TOP = 28;
    public static final int P_WALK_Y = 29;
    /** Poolrooms interior top (8-block hall). */
    public static final int P_AIR_TOP = 36;
    public static final int P_CEIL = 37;

    /** Yellow→pool interstitial: {@value #P_CEIL}+1..{@value #Y_FLOOR}-1 solid. */
    public static final int Y_FLOOR = 44;
    public static final int Y_WALK_Y = 45;
    /** Yellow Rooms ceiling (3-block interior). */
    public static final int Y_CEIL = 48;
    /** Double-height PILLAR_HALL ceiling (6-block interior). */
    public static final int Y_CEIL_TALL = 51;
    /** Top of generated content; the dimension is 64 tall (0..63). */
    public static final int TOP_Y = 51;

    /** Poolrooms/Warehouse cell side (blocks) — 2×2 Yellow-Rooms cells. */
    public static final int POOL_CELL = 16;

    // ------------------------------------------------------------------ hash salts

    private static final long SALT_POOL_EDGE_E = 0x0071AEA57L;
    private static final long SALT_POOL_EDGE_S = 0x0071A50D7L;
    private static final long SALT_POOL_BASIN = 0x0071BA51L;
    private static final long SALT_POOL_RECT = 0x0071AEC7L;
    private static final long SALT_POOL_DRAIN = 0x0071D1AAL;
    private static final long SALT_POOL_LANTERN = 0x007111A7L;
    private static final long SALT_WARE_EDGE_E = 0x0AA7EEA57L;
    private static final long SALT_WARE_EDGE_S = 0x0AA7E50D7L;
    private static final long SALT_WARE_CRATE = 0x0AA7EC4A7L;
    private static final long SALT_WARE_LIGHT = 0x0AA7E1167L;
    private static final long SALT_WARE_PLANK = 0x0AA7EB10CL;

    private BackroomsLayers() {}

    // ------------------------------------------------------------------ layer queries

    /** Which layer a Y coordinate belongs to (band boundaries sit in the interstitials). */
    public static Layer layerOf(int y) {
        if (y >= Y_FLOOR - 4) {
            return Layer.YELLOW_ROOMS;
        }
        return y >= P_BASIN_FLOOR - 2 ? Layer.POOLROOMS : Layer.WAREHOUSE;
    }

    /** Feet-level walk Y of a layer (teleport / spawn targets). */
    public static int walkY(Layer layer) {
        return switch (layer) {
            case YELLOW_ROOMS -> Y_WALK_Y;
            case POOLROOMS -> P_WALK_Y;
            case WAREHOUSE -> W_WALK_Y;
        };
    }

    /** Cell side length of a layer's room grid. */
    public static int cellSize(Layer layer) {
        return layer == Layer.YELLOW_ROOMS ? BackroomsMaze.CELL : POOL_CELL;
    }

    /** Walkable interior center of a layer cell. */
    public static BlockPos cellCenter(Layer layer, int cx, int cz) {
        int cell = cellSize(layer);
        int off = layer == Layer.YELLOW_ROOMS ? 3 : 8;
        return new BlockPos(cx * cell + off, walkY(layer), cz * cell + off);
    }

    /** Cell coords of a world position on a layer's grid. */
    public static int[] cellOf(Layer layer, BlockPos pos) {
        int cell = cellSize(layer);
        return new int[] {Math.floorDiv(pos.getX(), cell), Math.floorDiv(pos.getZ(), cell)};
    }

    /** Whether a POOLROOMS cell is a drain cell (hole through to the Warehouse). */
    public static boolean isDrainCell(long seed, int pcx, int pcz) {
        return BackroomsMaze.hashPercent(seed, poolKey(pcx, pcz), SALT_POOL_DRAIN) < 8;
    }

    private static long poolKey(int pcx, int pcz) {
        return ((long) pcx << 32) | (pcz & 0xFFFFFFFFL);
    }

    // ------------------------------------------------------------------ column context

    /**
     * All Y-independent facts about one world column — computed ONCE per column by the
     * chunk generator, then {@link #stateInColumn} resolves each Y (the
     * {@code DiscColumn} pattern).
     */
    public record Column(long seed, int x, int z,
            // yellow rooms
            int yLx, int yLz, BackroomsMaze.Prefab yPrefab, int yCeil,
            boolean yWallLine, boolean yWallCarved, boolean yPeep,
            boolean yHighwayRow, boolean yHighwayCol, boolean yHighway,
            boolean yShaftHole, boolean yShaftRim,
            // poolrooms
            int pLx, int pLz, boolean pWallLine, boolean pWallCarved, boolean pCornerPillar,
            boolean pBasin, boolean pFloorLantern, boolean pDrainHole,
            // warehouse
            int wLx, int wLz, boolean wWallLine, boolean wWallCarved,
            boolean wPillar, int wCrateTopY, boolean wCeilLight,
            boolean wBasinWater, boolean wBasinRim) {}

    /** Builds the column context for world column ({@code x}, {@code z}). */
    public static Column column(long seed, int x, int z) {
        // ---- yellow rooms (8×8 cells, the BackroomsMaze oracle)
        int ycx = Math.floorDiv(x, BackroomsMaze.CELL);
        int ycz = Math.floorDiv(z, BackroomsMaze.CELL);
        int yLx = x - ycx * BackroomsMaze.CELL;
        int yLz = z - ycz * BackroomsMaze.CELL;
        BackroomsMaze.Prefab yPrefab = BackroomsMaze.prefab(seed, ycx, ycz);
        int yCeil = BackroomsMaze.ceilY(seed, ycx, ycz);
        boolean yWallLine = yLx == BackroomsMaze.CELL - 1 || yLz == BackroomsMaze.CELL - 1;
        boolean yCorner = yLx == BackroomsMaze.CELL - 1 && yLz == BackroomsMaze.CELL - 1;
        boolean yWallCarved = !yCorner && (yLx == BackroomsMaze.CELL - 1
                ? BackroomsMaze.edgeOpenEast(seed, ycx, ycz)
                : yWallLine && BackroomsMaze.edgeOpenSouth(seed, ycx, ycz));
        boolean yPeep = yWallLine && !yCorner && !yWallCarved
                && BackroomsMaze.hashPercent(seed,
                        BackroomsMaze.cellKey(ycx, ycz) ^ ((long) yLx << 8) ^ yLz, 0x9EEBL) < 6;
        boolean yHighwayRow = BackroomsMaze.isHighwayRow(seed, ycz);
        boolean yHighwayCol = BackroomsMaze.isHighwayCol(seed, ycx);
        boolean yShaftCell = yPrefab == BackroomsMaze.Prefab.DROP_SHAFT;
        boolean yShaftHole = yShaftCell && yLx >= 3 && yLx <= 4 && yLz >= 3 && yLz <= 4;
        boolean yShaftRim = yShaftCell && !yShaftHole && yLx >= 2 && yLx <= 5 && yLz >= 2 && yLz <= 5;

        // ---- poolrooms (16×16 cells)
        int pcx = Math.floorDiv(x, POOL_CELL);
        int pcz = Math.floorDiv(z, POOL_CELL);
        int pLx = x - pcx * POOL_CELL;
        int pLz = z - pcz * POOL_CELL;
        long pKey = poolKey(pcx, pcz);
        boolean pWallLine = pLx == POOL_CELL - 1 || pLz == POOL_CELL - 1;
        boolean pCorner = pLx == POOL_CELL - 1 && pLz == POOL_CELL - 1;
        boolean pWallCarved = !pCorner && (pLx == POOL_CELL - 1
                ? BackroomsMaze.hashPercent(seed, pKey, SALT_POOL_EDGE_E) < 72
                : pWallLine && BackroomsMaze.hashPercent(seed, pKey, SALT_POOL_EDGE_S) < 72);
        boolean pDrainCell = isDrainCell(seed, pcx, pcz);
        boolean pDrainHole = pDrainCell && pLx >= 7 && pLx <= 8 && pLz >= 7 && pLz <= 8;
        boolean pBasin = poolBasinAt(seed, pKey, pLx, pLz)
                || (pDrainCell && pLx >= 5 && pLx <= 10 && pLz >= 5 && pLz <= 10)
                || (yShaftCell && yLx >= 2 && yLx <= 5 && yLz >= 2 && yLz <= 5);
        boolean pFloorLantern = !pBasin && !pWallLine && pLx == 7 && pLz == 7;

        // ---- warehouse (16×16 cells, grid-aligned with the poolrooms)
        boolean wWallLine = pWallLine;
        boolean wWallCarved = !pCorner && (pLx == POOL_CELL - 1
                ? BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_EDGE_E) < 85
                : wWallLine && BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_EDGE_S) < 85);
        boolean wPillar = pCorner || (!pDrainCell && pLx == 7 && pLz == 7);
        int wCrateTopY = warehouseCrateTop(seed, pKey, pLx, pLz, pDrainCell);
        boolean wCeilLight = pLx == 8 && pLz == 8
                && BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_LIGHT) < 25;
        boolean wBasinWater = pDrainCell && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean wBasinRim = pDrainCell && !wBasinWater
                && pLx >= 5 && pLx <= 10 && pLz >= 5 && pLz <= 10;

        return new Column(seed, x, z,
                yLx, yLz, yPrefab, yCeil, yWallLine, yWallCarved, yPeep,
                yHighwayRow, yHighwayCol, yHighwayRow || yHighwayCol, yShaftHole, yShaftRim,
                pLx, pLz, pWallLine, pWallCarved, pCorner,
                pBasin, pFloorLantern, pDrainHole,
                pLx, pLz, wWallLine, wWallCarved,
                wPillar, wCrateTopY, wCeilLight, wBasinWater, wBasinRim);
    }

    /** Hashed sunken basin rectangle of a pool cell (~70% of cells have one). */
    private static boolean poolBasinAt(long seed, long pKey, int pLx, int pLz) {
        if (BackroomsMaze.hashPercent(seed, pKey, SALT_POOL_BASIN) >= 70) {
            return false;
        }
        long h = BackroomsMaze.hash(seed, pKey, SALT_POOL_RECT);
        int x0 = 2 + (int) Math.floorMod(h, 3L);
        int z0 = 2 + (int) Math.floorMod(h >>> 8, 3L);
        int x1 = 12 - (int) Math.floorMod(h >>> 16, 3L);
        int z1 = 12 - (int) Math.floorMod(h >>> 24, 3L);
        return pLx >= x0 && pLx <= x1 && pLz >= z0 && pLz <= z1;
    }

    /** Top Y of a crate stack at this column ({@code Integer.MIN_VALUE} = no crate). */
    private static int warehouseCrateTop(long seed, long pKey, int pLx, int pLz, boolean drainCell) {
        if (drainCell || BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_CRATE) >= 40) {
            return Integer.MIN_VALUE;
        }
        long h = BackroomsMaze.hash(seed, pKey, SALT_WARE_CRATE ^ 0x5EEDL);
        int ox = 2 + (int) Math.floorMod(h, 9L);
        int oz = 2 + (int) Math.floorMod(h >>> 8, 9L);
        if (pLx < ox || pLx > ox + 2 || pLz < oz || pLz > oz + 2) {
            return Integer.MIN_VALUE;
        }
        int height = 2 + (int) Math.floorMod(h >>> 16, 3L); // 2..4 blocks tall
        return W_BASE_TOP + height;
    }

    // ------------------------------------------------------------------ state function

    /** Block state of the column at {@code y} — pure, deterministic, O(1). */
    public static BlockState stateInColumn(Column c, int y) {
        if (y < 0 || y > TOP_Y) {
            return Blocks.AIR.defaultBlockState();
        }
        if (y >= P_CEIL + 1) {
            return yellowState(c, y);
        }
        if (y >= W_CEIL + 1) {
            return poolState(c, y);
        }
        return warehouseState(c, y);
    }

    // ---- yellow rooms band (38..51): interstitial, floor, interior, ceiling

    private static BlockState yellowState(Column c, int y) {
        if (y < Y_FLOOR) { // 38..43 — the yellow→pool interstitial (shafts pass through)
            return c.yShaftHole() ? Blocks.AIR.defaultBlockState()
                    : Blocks.SANDSTONE.defaultBlockState();
        }
        if (y == Y_FLOOR) {
            if (c.yShaftHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            return c.yShaftRim() ? Blocks.YELLOW_CONCRETE_POWDER.defaultBlockState()
                    : Blocks.SPONGE.defaultBlockState();
        }
        // Wall-line columns: sealed walls stand to TOP_Y; carved openings read open-plan.
        if (c.yWallLine()) {
            if (c.yWallCarved()) {
                return y == Y_CEIL ? Blocks.SMOOTH_SANDSTONE.defaultBlockState()
                        : Blocks.AIR.defaultBlockState();
            }
            if (c.yPeep() && y == Y_WALK_Y + 1) {
                return Blocks.AIR.defaultBlockState(); // eye-level peep gap into pockets
            }
            if (y == Y_WALK_Y) {
                return Blocks.YELLOW_TERRACOTTA.defaultBlockState();
            }
            return BackroomsMaze.hashPercent(c.seed(), BlockPos.asLong(c.x(), y, c.z()), 0x57A1L) < 3
                    ? Blocks.YELLOW_CONCRETE_POWDER.defaultBlockState()
                    : Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState();
        }
        if (y == c.yCeil()) {
            return yellowCeiling(c);
        }
        if (y > c.yCeil()) {
            return Blocks.AIR.defaultBlockState(); // void above the ceiling plane
        }
        return yellowInterior(c, y);
    }

    /** Ceiling plane: froglight panels, hashed dead panels, smooth sandstone. */
    private static BlockState yellowCeiling(Column c) {
        boolean panelMain = c.yLz() == 3 && (c.yLx() == 2 || c.yLx() == 3);
        boolean panelHighway = c.yHighway() && c.yLz() == 1 && (c.yLx() == 2 || c.yLx() == 3);
        if (panelMain || panelHighway) {
            return Blocks.OCHRE_FROGLIGHT.defaultBlockState();
        }
        if (c.yLx() == 5 && c.yLz() == 5 && BackroomsMaze.hashPercent(c.seed(),
                BackroomsMaze.cellKey(Math.floorDiv(c.x(), BackroomsMaze.CELL),
                        Math.floorDiv(c.z(), BackroomsMaze.CELL)), 0xDEADL) < 12) {
            return Blocks.YELLOW_STAINED_GLASS.defaultBlockState(); // dead panel lookalike
        }
        return Blocks.SMOOTH_SANDSTONE.defaultBlockState();
    }

    /** Interior air column: prefab dressing + highway carpet, else air. */
    private static BlockState yellowInterior(Column c, int y) {
        switch (c.yPrefab()) {
            case OFFICE -> {
                boolean desk = (c.yLx() == 1 && c.yLz() == 2) || (c.yLx() == 5 && c.yLz() == 4);
                if (desk && y == Y_WALK_Y) {
                    return Blocks.YELLOW_TERRACOTTA.defaultBlockState();
                }
                if (desk && y == Y_WALK_Y + 1) {
                    return Blocks.CUT_SANDSTONE_SLAB.defaultBlockState();
                }
            }
            case PILLAR_HALL -> {
                if (((c.yLx() == 1 && c.yLz() == 1) || (c.yLx() == 5 && c.yLz() == 5))
                        && y < Y_CEIL_TALL) {
                    return Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState();
                }
            }
            case DEAD_END_CLOSET -> {
                if (c.yLx() == 4 && c.yLz() != 3 && c.yLz() <= 6 && y < Y_CEIL) {
                    return Blocks.YELLOW_TERRACOTTA.defaultBlockState();
                }
            }
            case LOOT_ALCOVE -> {
                if (c.yLx() == 3 && c.yLz() == 3 && y == Y_WALK_Y) {
                    return Blocks.BARREL.defaultBlockState(); // filled lazily per instance
                }
                if (c.yLx() == 4 && c.yLz() == 3 && y == Y_WALK_Y) {
                    return Blocks.YELLOW_CARPET.defaultBlockState();
                }
            }
            case CORRIDOR, WET_ROOM, DROP_SHAFT -> { /* bare shell */ }
        }
        if (y == Y_WALK_Y && !c.yShaftHole() && !c.yShaftRim()
                && ((c.yHighwayRow() && c.yLz() >= 2 && c.yLz() <= 4)
                        || (c.yHighwayCol() && c.yLx() >= 2 && c.yLx() <= 4))) {
            return Blocks.YELLOW_CARPET.defaultBlockState(); // worn walking path
        }
        return Blocks.AIR.defaultBlockState();
    }

    // ---- poolrooms band (22..37): interstitial, basin, floor, interior, ceiling

    private static BlockState poolState(Column c, int y) {
        if (y == P_CEIL) { // pool ceiling — open where a yellow shaft drops through
            return c.yShaftHole() ? Blocks.AIR.defaultBlockState()
                    : Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        if (y > P_FLOOR_TOP) { // 29..36 interior
            if (c.pWallLine() && !c.pWallCarved()) {
                return c.pCornerPillar() ? Blocks.QUARTZ_PILLAR.defaultBlockState()
                        : Blocks.SMOOTH_QUARTZ.defaultBlockState();
            }
            return Blocks.AIR.defaultBlockState();
        }
        if (y >= P_WATER_LO) { // 27..28 — floor slab / sunken water
            if (c.pBasin()) {
                return Blocks.WATER.defaultBlockState();
            }
            if (c.pFloorLantern() && y == P_FLOOR_TOP) {
                return Blocks.SEA_LANTERN.defaultBlockState(); // recessed glow tile
            }
            return Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        if (y == P_BASIN_FLOOR) { // 26 — basin floor (drains open through it)
            if (c.pDrainHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (c.pBasin() && BackroomsMaze.hashPercent(c.seed(),
                    BlockPos.asLong(c.x(), y, c.z()), SALT_POOL_LANTERN) < 8) {
                return Blocks.SEA_LANTERN.defaultBlockState(); // pool lit from below
            }
            return Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        // 22..25 — the pool→warehouse interstitial (drain shafts pass through).
        return c.pDrainHole() ? Blocks.AIR.defaultBlockState()
                : Blocks.POLISHED_DEEPSLATE.defaultBlockState();
    }

    // ---- warehouse band (0..21): base, floor basin, interior, ceiling

    private static BlockState warehouseState(Column c, int y) {
        if (y == W_CEIL) { // warehouse ceiling — open under a pool drain
            if (c.pDrainHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            return c.wCeilLight() ? Blocks.SHROOMLIGHT.defaultBlockState()
                    : Blocks.SMOOTH_BASALT.defaultBlockState();
        }
        if (y <= W_BASE_TOP) { // 0..8 — solid base
            return Blocks.TUFF.defaultBlockState();
        }
        if (y == W_WALK_Y) { // 9 — drain landing basin (fall-safe water) + rim
            if (c.wBasinWater()) {
                return Blocks.WATER.defaultBlockState();
            }
            if (c.wBasinRim()) {
                return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
            }
        }
        // 9..20 interior — pillars first: the corner pillar grid punches through walls.
        if (c.wPillar()) {
            return Blocks.POLISHED_BASALT.defaultBlockState();
        }
        if (c.wWallLine() && !c.wWallCarved()) {
            return Blocks.TUFF_BRICKS.defaultBlockState();
        }
        if (y <= c.wCrateTopY()) {
            return BackroomsMaze.hashPercent(c.seed(),
                    BlockPos.asLong(c.x(), y, c.z()), SALT_WARE_PLANK) < 50
                    ? Blocks.DARK_OAK_PLANKS.defaultBlockState()
                    : Blocks.SPRUCE_PLANKS.defaultBlockState();
        }
        return Blocks.AIR.defaultBlockState();
    }
}
