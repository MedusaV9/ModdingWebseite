package dev.projecteclipse.eclipse.backrooms;

import net.minecraft.core.BlockPos;
import net.minecraft.util.Mth;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

/**
 * The Backrooms LAYER STACK terrain function — the {@code DiscTerrainFunction} role for
 * the {@code eclipse:backrooms} dimension. FIVE classic backrooms levels are stacked in
 * one {@value #DIM_HEIGHT}-block-tall dimension and generated PROCEDURALLY per chunk by
 * {@link BackroomsChunkGenerator} (terrain gen, not a pre-built stamp), infinite in X/Z:
 *
 * <ul>
 *   <li><b>Level 1 — the Yellow Rooms</b> (floor y={@value #Y_FLOOR}, top): the original
 *       mono-yellow maze — {@link BackroomsMaze}'s hash-driven 8×8-block cell math
 *       (bond percolation walls, highway lanes, prefab rooms, froglight panels),
 *       extended to an INFINITE cell grid. Hashed {@code DROP_SHAFT} cells open a 2×2
 *       no-clip pit through the floor (rimmed with stained concrete powder) that drops
 *       into a guaranteed water basin of the Poolrooms below.</li>
 *   <li><b>Level 2 — the Poolrooms</b> (floor y={@value #P_FLOOR_TOP}): vast echoing
 *       smooth-quartz halls on a 16×16 grid, sunken 2-deep water basins lit from below
 *       by sea lanterns. Hashed DRAIN cells open a 2×2 hole in a forced basin's floor —
 *       the water spills through it as a waterfall into the Warehouse.</li>
 *   <li><b>Level 3 — the Warehouse</b> (floor y={@value #W_BASE_TOP}): a dark 12-block
 *       tall basalt-pillar hall on the same 16×16 grid, tuff walls, hashed plank crate
 *       stacks, sparse shroomlight. Drain landings are 4×4 rimmed water basins
 *       (fall-safe); hashed HATCH cells open a rimmed 2×2 shaft through the slab floor
 *       into the Flooded Halls.</li>
 *   <li><b>Level 4 — the Flooded Halls</b> (water surface y={@value #F_WATER_Y}): a
 *       black deepslate hall standing in knee-deep dark water, hashed dry tile platforms
 *       and a column grid, walls mostly torn open, VERY rare ceiling sea lanterns.
 *       Hashed SINK cells open a 2×2 vortex through the floor — the water pours down it
 *       into The Hollow.</li>
 *   <li><b>Level 5 — The Hollow</b> (floor y={@value #H_BASE_TOP}, deepest): one single
 *       {@value #HOLLOW_INTERIOR_HEIGHT}-block-tall wall-less black hall carrying only a
 *       {@value #HOLLOW_PILLAR_SPACING}-block Säulenraster of deepslate columns, almost
 *       no light at all. Sink landings are rimmed 2-deep water basins. <b>The EXIT
 *       portal spawns here</b> ({@code BackroomsEventService.spawnExitPortal}).</li>
 * </ul>
 *
 * <p><b>Darkness law (F-042)</b>: ceiling lamps are no longer guaranteed. Every lamp on
 * every layer rolls against {@link #LAMP_PERCENT} (highways: {@link #LAMP_PERCENT_HIGHWAY}),
 * and {@link #deadZone} carves smooth value-noise DEAD ZONES — connected ~20–40 block
 * blobs in which the roll collapses to {@link #DEAD_ZONE_LAMP_PERCENT}, i.e. effectively
 * pitch black rooms. {@link BackroomsMaze#panelsForCell} asks the SAME predicates, so the
 * flicker pass can never hallucinate a panel the generator did not place.</p>
 *
 * <p>Descent is one-way through the shafts/drains/hatches/sinks (every landing is water —
 * no fall damage); {@code /backroomsleave}, deaths and the closing sweep exit players
 * from ANY layer. Every block is a pure O(1) function of {@code (seed, x, y, z)} — the
 * same stateless-hash law the old stamped maze followed, so the generator is
 * deterministic, chunk-local and thread-safe with no global solver.</p>
 */
public final class BackroomsLayers {

    /** The five generated levels, top to bottom. */
    public enum Layer {
        YELLOW_ROOMS(1), POOLROOMS(2), WAREHOUSE(3), FLOODED_HALLS(4), THE_HOLLOW(5);

        private final int level;

        Layer(int level) {
            this.level = level;
        }

        /** 1-based level number as the players/captions count them. */
        public int level() {
            return level;
        }
    }

    // ------------------------------------------------------------------ Y bands (0..111)

    /** Generated height of the dimension — MUST match {@code dimension_type/backrooms.json}. */
    public static final int DIM_HEIGHT = 112;

    /** The Hollow: solid base 0..{@value}, walk on {@value #H_WALK_Y}. */
    public static final int H_BASE_TOP = 8;
    public static final int H_WALK_Y = 9;
    /** The Hollow interior top (a {@value #HOLLOW_INTERIOR_HEIGHT}-block cathedral). */
    public static final int H_AIR_TOP = 32;
    public static final int H_CEIL = 33;
    public static final int HOLLOW_INTERIOR_HEIGHT = H_AIR_TOP - H_WALK_Y + 1;
    /** Säulenraster: one 2×2 column every {@value} blocks in X and Z. */
    public static final int HOLLOW_PILLAR_SPACING = 12;
    public static final int HOLLOW_PILLAR_THICKNESS = 2;
    /**
     * Cell side of The Hollow's (wall-less) bookkeeping grid — spawn/teleport math only.
     * Deliberately 2× {@link #HOLLOW_PILLAR_SPACING} so every cell center lands in the
     * middle of a pillar bay instead of inside a column.
     */
    public static final int HOLLOW_CELL = 2 * HOLLOW_PILLAR_SPACING;

    /**
     * Flooded Halls: solid floor slab top, the water sits one block above it. The
     * Hollow→Flooded interstitial ({@value #H_CEIL}+1..{@value #F_FLOOR}-1) is solid.
     */
    public static final int F_FLOOR = 38;
    /** Knee-deep water surface = the Flooded Halls walk plane. */
    public static final int F_WATER_Y = 39;
    public static final int F_WALK_Y = 39;
    /** Flooded Halls interior top (9-block hall). */
    public static final int F_AIR_TOP = 47;
    public static final int F_CEIL = 48;

    /** Warehouse: solid base {@value #F_CEIL}+1..{@value}, walk on {@value #W_WALK_Y}. */
    public static final int W_BASE_TOP = 61;
    public static final int W_WALK_Y = 62;
    /** Warehouse interior top (12-block hall). */
    public static final int W_AIR_TOP = 73;
    public static final int W_CEIL = 74;

    /** Pool→warehouse interstitial: {@value #W_CEIL}+1..{@value #P_BASIN_FLOOR} solid. */
    public static final int P_BASIN_FLOOR = 79;
    public static final int P_WATER_LO = 80;
    /** Poolrooms walk floor top (= basin water surface), walk on {@value #P_WALK_Y}. */
    public static final int P_FLOOR_TOP = 81;
    public static final int P_WALK_Y = 82;
    /** Poolrooms interior top (8-block hall). */
    public static final int P_AIR_TOP = 89;
    public static final int P_CEIL = 90;

    /** Yellow→pool interstitial: {@value #P_CEIL}+1..{@value #Y_FLOOR}-1 solid. */
    public static final int Y_FLOOR = 97;
    public static final int Y_WALK_Y = 98;
    /** Yellow Rooms ceiling (3-block interior). */
    public static final int Y_CEIL = 101;
    /** Double-height PILLAR_HALL ceiling (6-block interior). */
    public static final int Y_CEIL_TALL = 104;
    /** Top of generated content; the dimension is {@value #DIM_HEIGHT} tall (0..111). */
    public static final int TOP_Y = 104;

    /** Poolrooms/Warehouse/Flooded cell side (blocks) — 2×2 Yellow-Rooms cells. */
    public static final int POOL_CELL = 16;

    // ------------------------------------------------------------------ darkness tuning (F-042)

    /**
     * Share of cells that still carry their ceiling lamp — the "~40% of the old value"
     * decree (every cell used to be lit unconditionally).
     */
    public static final int LAMP_PERCENT = 40;
    /** Highway lanes stay a little more navigable than the rooms. */
    public static final int LAMP_PERCENT_HIGHWAY = 55;
    /** Inside a {@link #deadZone} the roll collapses to this — effectively pitch black. */
    public static final int DEAD_ZONE_LAMP_PERCENT = 4;
    /** Value-noise lattice of the dead zones (blobs come out ~20–40 blocks across). */
    public static final int DEAD_ZONE_LATTICE = 24;
    /**
     * Noise threshold above which a column sits inside a dead zone (0..1). Tuned against
     * the noise: {@code 0.70} leaves ~20% of every layer dark in blobs whose mean chord is
     * ~25 blocks (≈ 32 blocks across), i.e. the decreed 20–40. Lowering it merges the
     * blobs into whole unlit districts very fast.
     */
    public static final float DEAD_ZONE_THRESHOLD = 0.70F;

    /** Warehouse ceiling shroomlight share (was 25). */
    private static final int WARE_LIGHT_PERCENT = 10;
    /** Sea lanterns under a pool basin (was 8). */
    private static final int POOL_BASIN_LANTERN_PERCENT = 3;
    /** Flooded Halls ceiling lanterns — "sehr seltene Lampen". */
    private static final int FLOOD_LIGHT_PERCENT = 8;
    /** The Hollow floor lights — almost none. */
    private static final int HOLLOW_LIGHT_PERCENT = 3;

    /** Warehouse cells whose floor opens a hatch down into the Flooded Halls. */
    private static final int WARE_HATCH_PERCENT = 8;
    /** Flooded cells whose floor opens a sink down into The Hollow. */
    private static final int FLOOD_SINK_PERCENT = 8;

    // ------------------------------------------------------------------ hash salts

    private static final long SALT_POOL_EDGE_E = 0x0071AEA57L;
    private static final long SALT_POOL_EDGE_S = 0x0071A50D7L;
    private static final long SALT_POOL_BASIN = 0x0071BA51L;
    private static final long SALT_POOL_RECT = 0x0071AEC7L;
    private static final long SALT_POOL_DRAIN = 0x0071D1AAL;
    private static final long SALT_POOL_LANTERN = 0x007111A7L;
    private static final long SALT_POOL_LAMP = 0x00711A77L;
    private static final long SALT_WARE_EDGE_E = 0x0AA7EEA57L;
    private static final long SALT_WARE_EDGE_S = 0x0AA7E50D7L;
    private static final long SALT_WARE_CRATE = 0x0AA7EC4A7L;
    private static final long SALT_WARE_LIGHT = 0x0AA7E1167L;
    private static final long SALT_WARE_PLANK = 0x0AA7EB10CL;
    private static final long SALT_WARE_HATCH = 0x0AA7E4A7CL;
    private static final long SALT_FLOOD_EDGE_E = 0x0F100DEA5L;
    private static final long SALT_FLOOD_EDGE_S = 0x0F100D50DL;
    private static final long SALT_FLOOD_PLAT = 0x0F100D9147L;
    private static final long SALT_FLOOD_RECT = 0x0F100DEC71L;
    private static final long SALT_FLOOD_SINK = 0x0F100D51A7L;
    private static final long SALT_FLOOD_LIGHT = 0x0F100D1167L;
    private static final long SALT_FLOOD_TILE = 0x0F100D717EL;
    private static final long SALT_HOLLOW_LIGHT = 0x0B0110411A7L;
    private static final long SALT_HOLLOW_BAND = 0x0B01104BA7DL;
    private static final long SALT_LAMP_MAIN = 0x1AA9BA1EL;
    private static final long SALT_LAMP_HIGHWAY = 0x1AA9B417L;
    private static final long SALT_DEAD_ZONE = 0x0DEAD20E7L;

    private BackroomsLayers() {}

    // ------------------------------------------------------------------ layer queries

    /** Which layer a Y coordinate belongs to (band boundaries sit in the interstitials). */
    public static Layer layerOf(int y) {
        if (y > P_CEIL) {
            return Layer.YELLOW_ROOMS;
        }
        if (y > W_CEIL) {
            return Layer.POOLROOMS;
        }
        if (y > F_CEIL) {
            return Layer.WAREHOUSE;
        }
        return y > H_CEIL ? Layer.FLOODED_HALLS : Layer.THE_HOLLOW;
    }

    /** Feet-level walk Y of a layer (teleport / spawn targets). */
    public static int walkY(Layer layer) {
        return switch (layer) {
            case YELLOW_ROOMS -> Y_WALK_Y;
            case POOLROOMS -> P_WALK_Y;
            case WAREHOUSE -> W_WALK_Y;
            case FLOODED_HALLS -> F_WALK_Y;
            case THE_HOLLOW -> H_WALK_Y;
        };
    }

    /** Cell side length of a layer's room grid. */
    public static int cellSize(Layer layer) {
        return switch (layer) {
            case YELLOW_ROOMS -> BackroomsMaze.CELL;
            case THE_HOLLOW -> HOLLOW_CELL;
            default -> POOL_CELL;
        };
    }

    /** Walkable interior center of a layer cell. */
    public static BlockPos cellCenter(Layer layer, int cx, int cz) {
        int cell = cellSize(layer);
        int off = switch (layer) {
            case YELLOW_ROOMS -> 3;
            case THE_HOLLOW -> HOLLOW_PILLAR_SPACING / 2; // bay center, clear of the raster
            default -> 8;
        };
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

    /** Whether a WAREHOUSE cell carries a floor hatch down into the Flooded Halls. */
    public static boolean isHatchCell(long seed, int pcx, int pcz) {
        return !isDrainCell(seed, pcx, pcz)
                && BackroomsMaze.hashPercent(seed, poolKey(pcx, pcz), SALT_WARE_HATCH)
                        < WARE_HATCH_PERCENT;
    }

    /** Whether a FLOODED cell carries a sink vortex down into The Hollow. */
    public static boolean isSinkCell(long seed, int pcx, int pcz) {
        return !isHatchCell(seed, pcx, pcz)
                && BackroomsMaze.hashPercent(seed, poolKey(pcx, pcz), SALT_FLOOD_SINK)
                        < FLOOD_SINK_PERCENT;
    }

    private static long poolKey(int pcx, int pcz) {
        return ((long) pcx << 32) | (pcz & 0xFFFFFFFFL);
    }

    // ------------------------------------------------------------------ dead zones (F-042)

    /**
     * Smooth 2-D value noise over a {@value #DEAD_ZONE_LATTICE}-block lattice, 0..1.
     * Pure, O(1), seed-deterministic — the same stateless-hash law as everything else.
     */
    public static float deadZoneNoise(long seed, int x, int z) {
        int gx = Math.floorDiv(x, DEAD_ZONE_LATTICE);
        int gz = Math.floorDiv(z, DEAD_ZONE_LATTICE);
        float tx = smoothstep((x - gx * DEAD_ZONE_LATTICE) / (float) DEAD_ZONE_LATTICE);
        float tz = smoothstep((z - gz * DEAD_ZONE_LATTICE) / (float) DEAD_ZONE_LATTICE);
        float v00 = lattice(seed, gx, gz);
        float v10 = lattice(seed, gx + 1, gz);
        float v01 = lattice(seed, gx, gz + 1);
        float v11 = lattice(seed, gx + 1, gz + 1);
        return Mth.lerp(tz, Mth.lerp(tx, v00, v10), Mth.lerp(tx, v01, v11));
    }

    /**
     * Whether the column sits inside a DEAD ZONE — a connected blob (~20–40 blocks across)
     * in which lamps all but stop generating, so whole stretches of every layer are pitch
     * black instead of evenly lit.
     */
    public static boolean deadZone(long seed, int x, int z) {
        return deadZoneNoise(seed, x, z) >= DEAD_ZONE_THRESHOLD;
    }

    private static float lattice(long seed, int gx, int gz) {
        return Math.floorMod(BackroomsMaze.hash(seed, BackroomsMaze.cellKey(gx, gz),
                SALT_DEAD_ZONE), 1024L) / 1023.0F;
    }

    private static float smoothstep(float t) {
        return t * t * (3.0F - 2.0F * t);
    }

    /** Lamp roll of one cell: dead zones collapse it to {@value #DEAD_ZONE_LAMP_PERCENT}%. */
    private static boolean lampRoll(long seed, long key, long salt, boolean darkZone, int percent) {
        return BackroomsMaze.hashPercent(seed, key, salt)
                < (darkZone ? DEAD_ZONE_LAMP_PERCENT : percent);
    }

    /** Same roll, sampling the dead-zone noise at the lamp's own world column. */
    private static boolean lampRoll(long seed, long key, long salt, int worldX, int worldZ,
            int percent) {
        return lampRoll(seed, key, salt, deadZone(seed, worldX, worldZ), percent);
    }

    /**
     * Whether the Yellow-Rooms cell keeps its MAIN 2×1 ceiling strip. Public because
     * {@link BackroomsMaze#panelsForCell} must answer exactly the same question the
     * generator answered — otherwise the flicker pass would create lamps out of nothing.
     */
    public static boolean yellowLampMain(long seed, int cx, int cz) {
        int percent = BackroomsMaze.isHighwayCell(seed, cx, cz)
                ? LAMP_PERCENT_HIGHWAY : LAMP_PERCENT;
        return lampRoll(seed, BackroomsMaze.cellKey(cx, cz), SALT_LAMP_MAIN,
                cx * BackroomsMaze.CELL + 3, cz * BackroomsMaze.CELL + 3, percent);
    }

    /** Whether a HIGHWAY cell keeps its second (lane) ceiling strip. */
    public static boolean yellowLampHighway(long seed, int cx, int cz) {
        return BackroomsMaze.isHighwayCell(seed, cx, cz)
                && lampRoll(seed, BackroomsMaze.cellKey(cx, cz), SALT_LAMP_HIGHWAY,
                        cx * BackroomsMaze.CELL + 3, cz * BackroomsMaze.CELL + 1,
                        LAMP_PERCENT_HIGHWAY);
    }

    // ------------------------------------------------------------------ column context

    /**
     * The two deep levels' Y-independent facts, split out of {@link Column} so the record
     * stays readable (the generator builds exactly one of these per column too).
     */
    public record Deep(
            // flooded halls (16×16 grid, aligned with the poolrooms/warehouse)
            boolean fWallLine, boolean fWallCarved, boolean fPillar, boolean fPlatform,
            boolean fSinkHole, boolean fSinkRim, boolean fLanding, boolean fCeilLight,
            // the hollow
            boolean hPillar, boolean hBasinWater, boolean hBasinRim, boolean hFloorLight) {}

    /**
     * All Y-independent facts about one world column — computed ONCE per column by the
     * chunk generator, then {@link #stateInColumn} resolves each Y (the
     * {@code DiscColumn} pattern).
     */
    public record Column(long seed, int x, int z, boolean darkZone,
            // yellow rooms
            int yLx, int yLz, BackroomsMaze.Prefab yPrefab, int yCeil,
            boolean yWallLine, boolean yWallCarved, boolean yPeep,
            boolean yHighwayRow, boolean yHighwayCol, boolean yHighway,
            boolean yShaftHole, boolean yShaftRim, boolean yLampMain, boolean yLampHighway,
            // poolrooms
            int pLx, int pLz, boolean pWallLine, boolean pWallCarved, boolean pCornerPillar,
            boolean pBasin, boolean pFloorLantern, boolean pDrainHole,
            // warehouse
            int wLx, int wLz, boolean wWallLine, boolean wWallCarved,
            boolean wPillar, int wCrateTopY, boolean wCeilLight,
            boolean wBasinWater, boolean wBasinRim, boolean wHatchHole, boolean wHatchRim,
            // flooded halls + the hollow
            Deep deep) {}

    /** Builds the column context for world column ({@code x}, {@code z}). */
    public static Column column(long seed, int x, int z) {
        boolean darkZone = deadZone(seed, x, z);

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
        boolean yLampMain = yellowLampMain(seed, ycx, ycz);
        boolean yLampHighway = yellowLampHighway(seed, ycx, ycz);

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
        boolean pFloorLantern = !pBasin && !pWallLine && pLx == 7 && pLz == 7
                && lampRoll(seed, pKey, SALT_POOL_LAMP, darkZone, LAMP_PERCENT);

        // ---- warehouse (16×16 cells, grid-aligned with the poolrooms)
        boolean wHatchCell = isHatchCell(seed, pcx, pcz);
        boolean wWallLine = pWallLine;
        boolean wWallCarved = !pCorner && (pLx == POOL_CELL - 1
                ? BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_EDGE_E) < 85
                : wWallLine && BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_EDGE_S) < 85);
        boolean wHatchHole = wHatchCell && pLx >= 7 && pLx <= 8 && pLz >= 7 && pLz <= 8;
        boolean wHatchRim = wHatchCell && !wHatchHole
                && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean wPillar = pCorner || (!pDrainCell && !wHatchCell && pLx == 7 && pLz == 7);
        int wCrateTopY = warehouseCrateTop(seed, pKey, pLx, pLz, pDrainCell || wHatchCell);
        boolean wCeilLight = pLx == 8 && pLz == 8
                && lampRoll(seed, pKey, SALT_WARE_LIGHT, darkZone, WARE_LIGHT_PERCENT);
        boolean wBasinWater = pDrainCell && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean wBasinRim = pDrainCell && !wBasinWater
                && pLx >= 5 && pLx <= 10 && pLz >= 5 && pLz <= 10;

        // ---- flooded halls (16×16 cells, same grid) + the hollow (wall-less pillar raster)
        boolean fSinkCell = isSinkCell(seed, pcx, pcz);
        boolean fSinkHole = fSinkCell && pLx >= 7 && pLx <= 8 && pLz >= 7 && pLz <= 8;
        boolean fSinkRim = fSinkCell && !fSinkHole
                && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean fLanding = wHatchCell && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean fWallLine = pWallLine;
        boolean fWallCarved = !pCorner && (pLx == POOL_CELL - 1
                ? BackroomsMaze.hashPercent(seed, pKey, SALT_FLOOD_EDGE_E) < 80
                : fWallLine && BackroomsMaze.hashPercent(seed, pKey, SALT_FLOOD_EDGE_S) < 80);
        boolean fPillar = !fSinkCell && !wHatchCell && pCorner;
        boolean fPlatform = !fSinkHole && !fSinkRim && !fLanding && !fWallLine
                && floodPlatformAt(seed, pKey, pLx, pLz);
        boolean fCeilLight = !wHatchHole && pLx == 8 && pLz == 8
                && lampRoll(seed, pKey, SALT_FLOOD_LIGHT, darkZone, FLOOD_LIGHT_PERCENT);

        boolean hPillar = Math.floorMod(x, HOLLOW_PILLAR_SPACING) < HOLLOW_PILLAR_THICKNESS
                && Math.floorMod(z, HOLLOW_PILLAR_SPACING) < HOLLOW_PILLAR_THICKNESS;
        boolean hBasinWater = fSinkCell && pLx >= 6 && pLx <= 9 && pLz >= 6 && pLz <= 9;
        boolean hBasinRim = fSinkCell && !hBasinWater
                && pLx >= 5 && pLx <= 10 && pLz >= 5 && pLz <= 10;
        // One candidate tile per pillar bay, and only 3% of those bays light up at all.
        boolean hBayCenter = Math.floorMod(x, HOLLOW_PILLAR_SPACING) == HOLLOW_PILLAR_SPACING / 2
                && Math.floorMod(z, HOLLOW_PILLAR_SPACING) == HOLLOW_PILLAR_SPACING / 2;
        boolean hFloorLight = hBayCenter && !hPillar && !hBasinWater && !hBasinRim
                && lampRoll(seed, BackroomsMaze.cellKey(
                        Math.floorDiv(x, HOLLOW_PILLAR_SPACING),
                        Math.floorDiv(z, HOLLOW_PILLAR_SPACING)),
                        SALT_HOLLOW_LIGHT, darkZone, HOLLOW_LIGHT_PERCENT);

        Deep deep = new Deep(fWallLine, fWallCarved, fPillar, fPlatform,
                fSinkHole, fSinkRim, fLanding, fCeilLight,
                hPillar, hBasinWater, hBasinRim, hFloorLight);

        return new Column(seed, x, z, darkZone,
                yLx, yLz, yPrefab, yCeil, yWallLine, yWallCarved, yPeep,
                yHighwayRow, yHighwayCol, yHighwayRow || yHighwayCol, yShaftHole, yShaftRim,
                yLampMain, yLampHighway,
                pLx, pLz, pWallLine, pWallCarved, pCorner,
                pBasin, pFloorLantern, pDrainHole,
                pLx, pLz, wWallLine, wWallCarved,
                wPillar, wCrateTopY, wCeilLight, wBasinWater, wBasinRim, wHatchHole, wHatchRim,
                deep);
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

    /** Hashed dry tile platform of a flooded cell (~45% of cells have one). */
    private static boolean floodPlatformAt(long seed, long pKey, int pLx, int pLz) {
        if (BackroomsMaze.hashPercent(seed, pKey, SALT_FLOOD_PLAT) >= 45) {
            return false;
        }
        long h = BackroomsMaze.hash(seed, pKey, SALT_FLOOD_RECT);
        int x0 = 1 + (int) Math.floorMod(h, 6L);
        int z0 = 1 + (int) Math.floorMod(h >>> 8, 6L);
        int x1 = x0 + 2 + (int) Math.floorMod(h >>> 16, 5L);
        int z1 = z0 + 2 + (int) Math.floorMod(h >>> 24, 5L);
        return pLx >= x0 && pLx <= x1 && pLz >= z0 && pLz <= z1;
    }

    /** Top Y of a crate stack at this column ({@code Integer.MIN_VALUE} = no crate). */
    private static int warehouseCrateTop(long seed, long pKey, int pLx, int pLz, boolean pierced) {
        if (pierced || BackroomsMaze.hashPercent(seed, pKey, SALT_WARE_CRATE) >= 40) {
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
        if (y >= F_CEIL + 1) {
            return warehouseState(c, y);
        }
        if (y >= H_CEIL + 1) {
            return floodedState(c, y);
        }
        return hollowState(c, y);
    }

    // ---- yellow rooms band (91..104): interstitial, floor, interior, ceiling

    private static BlockState yellowState(Column c, int y) {
        if (y < Y_FLOOR) { // 91..96 — the yellow→pool interstitial (shafts pass through)
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

    /**
     * Ceiling plane: froglight panels ONLY where the cell won its lamp roll (F-042 — dead
     * zones and the 40% density leave most rooms with a bare, unlit ceiling), hashed dead
     * glass panels, smooth sandstone.
     */
    private static BlockState yellowCeiling(Column c) {
        boolean stripMain = c.yLz() == 3 && (c.yLx() == 2 || c.yLx() == 3);
        boolean stripHighway = c.yHighway() && c.yLz() == 1 && (c.yLx() == 2 || c.yLx() == 3);
        if ((stripMain && c.yLampMain()) || (stripHighway && c.yLampHighway())) {
            return Blocks.OCHRE_FROGLIGHT.defaultBlockState();
        }
        if (stripMain || stripHighway) {
            // The fixture is there, the tube is dead — the tell that this room went dark.
            return Blocks.YELLOW_STAINED_GLASS.defaultBlockState();
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

    // ---- poolrooms band (75..90): interstitial, basin, floor, interior, ceiling

    private static BlockState poolState(Column c, int y) {
        if (y == P_CEIL) { // pool ceiling — open where a yellow shaft drops through
            return c.yShaftHole() ? Blocks.AIR.defaultBlockState()
                    : Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        if (y > P_FLOOR_TOP) { // 82..89 interior
            if (c.pWallLine() && !c.pWallCarved()) {
                return c.pCornerPillar() ? Blocks.QUARTZ_PILLAR.defaultBlockState()
                        : Blocks.SMOOTH_QUARTZ.defaultBlockState();
            }
            return Blocks.AIR.defaultBlockState();
        }
        if (y >= P_WATER_LO) { // 80..81 — floor slab / sunken water
            if (c.pBasin()) {
                return Blocks.WATER.defaultBlockState();
            }
            if (c.pFloorLantern() && y == P_FLOOR_TOP) {
                return Blocks.SEA_LANTERN.defaultBlockState(); // recessed glow tile
            }
            return Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        if (y == P_BASIN_FLOOR) { // 79 — basin floor (drains open through it)
            if (c.pDrainHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (c.pBasin() && !c.darkZone() && BackroomsMaze.hashPercent(c.seed(),
                    BlockPos.asLong(c.x(), y, c.z()), SALT_POOL_LANTERN)
                            < POOL_BASIN_LANTERN_PERCENT) {
                return Blocks.SEA_LANTERN.defaultBlockState(); // pool lit from below
            }
            return Blocks.SMOOTH_QUARTZ.defaultBlockState();
        }
        // 75..78 — the pool→warehouse interstitial (drain shafts pass through).
        return c.pDrainHole() ? Blocks.AIR.defaultBlockState()
                : Blocks.POLISHED_DEEPSLATE.defaultBlockState();
    }

    // ---- warehouse band (49..74): base, floor basin, interior, ceiling

    private static BlockState warehouseState(Column c, int y) {
        if (y == W_CEIL) { // warehouse ceiling — open under a pool drain
            if (c.pDrainHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            return c.wCeilLight() ? Blocks.SHROOMLIGHT.defaultBlockState()
                    : Blocks.SMOOTH_BASALT.defaultBlockState();
        }
        if (y <= W_BASE_TOP) { // 49..61 — solid base; hatches punch a shaft through it
            return c.wHatchHole() ? Blocks.AIR.defaultBlockState()
                    : Blocks.TUFF.defaultBlockState();
        }
        if (y == W_WALK_Y) { // 62 — drain landing basin (fall-safe water), hatch mouth + rims
            if (c.wHatchHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (c.wHatchRim()) {
                return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
            }
            if (c.wBasinWater()) {
                return Blocks.WATER.defaultBlockState();
            }
            if (c.wBasinRim()) {
                return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
            }
        }
        // 62..73 interior — pillars first: the corner pillar grid punches through walls.
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

    // ---- flooded halls band (34..48): interstitial, floor, knee-deep water, ceiling

    /**
     * Level 4 — knee-deep black water over a deepslate slab, hashed dry tile platforms,
     * torn-open walls, a corner column grid, very rare ceiling lanterns. Warehouse hatches
     * land in a 2-deep basin here; SINK cells drop on into The Hollow and the water follows.
     */
    private static BlockState floodedState(Column c, int y) {
        Deep d = c.deep();
        if (y == F_CEIL) { // 48 — ceiling, open under a warehouse hatch
            if (c.wHatchHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            return d.fCeilLight() ? Blocks.SEA_LANTERN.defaultBlockState()
                    : Blocks.DEEPSLATE_TILES.defaultBlockState();
        }
        if (y > F_WATER_Y) { // 40..47 interior
            if (d.fSinkHole() || d.fLanding()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (d.fPillar()) {
                return Blocks.POLISHED_DEEPSLATE.defaultBlockState();
            }
            if (d.fWallLine() && !d.fWallCarved()) {
                return Blocks.DEEPSLATE_BRICKS.defaultBlockState();
            }
            return Blocks.AIR.defaultBlockState();
        }
        if (y == F_WATER_Y) { // 39 — the knee-deep water plane (= walk Y)
            if (d.fSinkHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (d.fLanding()) {
                return Blocks.WATER.defaultBlockState();
            }
            if (d.fPillar()) {
                return Blocks.POLISHED_DEEPSLATE.defaultBlockState();
            }
            if (d.fSinkRim()) {
                return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
            }
            if (d.fWallLine() && !d.fWallCarved()) {
                return Blocks.DEEPSLATE_BRICKS.defaultBlockState();
            }
            if (d.fPlatform()) {
                return Blocks.DEEPSLATE_TILES.defaultBlockState(); // dry island
            }
            return Blocks.WATER.defaultBlockState();
        }
        if (y == F_FLOOR) { // 38 — floor slab; hatch landings sink 1 deeper, sinks open
            if (d.fSinkHole()) {
                return Blocks.AIR.defaultBlockState();
            }
            if (d.fLanding()) {
                return Blocks.WATER.defaultBlockState();
            }
            return floodTile(c, y);
        }
        // 34..37 — the flooded→hollow interstitial (sink vortices pass through).
        return d.fSinkHole() ? Blocks.AIR.defaultBlockState()
                : Blocks.DEEPSLATE.defaultBlockState();
    }

    private static BlockState floodTile(Column c, int y) {
        return BackroomsMaze.hashPercent(c.seed(), BlockPos.asLong(c.x(), y, c.z()),
                SALT_FLOOD_TILE) < 30
                ? Blocks.CRACKED_DEEPSLATE_TILES.defaultBlockState()
                : Blocks.DEEPSLATE_TILES.defaultBlockState();
    }

    // ---- the hollow band (0..33): base, sink basins, pillar raster, ceiling

    /**
     * Level 5 — ONE wall-less {@value #HOLLOW_INTERIOR_HEIGHT}-block-tall black hall with
     * nothing in it but a {@value #HOLLOW_PILLAR_SPACING}-block pillar raster and, every
     * so often, a single sea lantern in the floor. This is where the EXIT portal spawns.
     */
    private static BlockState hollowState(Column c, int y) {
        Deep d = c.deep();
        if (y == H_CEIL) { // 33 — ceiling, open under a flooded sink
            return d.fSinkHole() ? Blocks.AIR.defaultBlockState()
                    : Blocks.DEEPSLATE_TILES.defaultBlockState();
        }
        if (y > H_AIR_TOP) { // nothing between the raster top and the ceiling
            return Blocks.AIR.defaultBlockState();
        }
        if (d.hBasinWater() && (y == H_BASE_TOP || y == H_WALK_Y)) {
            return Blocks.WATER.defaultBlockState(); // 2-deep, fall-safe sink landing
        }
        if (y < H_BASE_TOP) { // 0..7 — solid bedrock-ish base
            return Blocks.DEEPSLATE.defaultBlockState();
        }
        if (y == H_BASE_TOP) { // 8 — the visible floor plane
            return d.hFloorLight() ? Blocks.SEA_LANTERN.defaultBlockState()
                    : Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        }
        if (y == H_WALK_Y && d.hBasinRim()) { // 9 — the basin lip
            return Blocks.POLISHED_BLACKSTONE.defaultBlockState();
        }
        if (d.hPillar()) { // 9..32 — the Säulenraster
            return BackroomsMaze.hashPercent(c.seed(), BlockPos.asLong(c.x(), y, c.z()),
                    SALT_HOLLOW_BAND) < 6
                    ? Blocks.CHISELED_DEEPSLATE.defaultBlockState()
                    : Blocks.POLISHED_DEEPSLATE.defaultBlockState();
        }
        return Blocks.AIR.defaultBlockState();
    }
}
