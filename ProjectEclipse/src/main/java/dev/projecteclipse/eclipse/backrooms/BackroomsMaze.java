package dev.projecteclipse.eclipse.backrooms;

import java.util.ArrayList;
import java.util.List;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.registry.EclipseItems;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.alchemy.PotionContents;
import net.minecraft.world.item.alchemy.Potions;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BarrelBlockEntity;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Deterministic Backrooms maze (IDEAS-backrooms_finale §A1): 24×24 cells of 8×8 blocks
 * (192×192), stamped into the {@code eclipse:backrooms} void dimension at event start.
 * Pure hash-driven cell math — no global solver, O(1) per cell, identical for a given
 * {@code mazeSeed}, so a crash-restart re-stamp rebuilds the exact same maze
 * (per-instance seed law: {@code ECLIPSE_SEED ^ 0xBAC2C0035EEDL ^ instanceId}).
 *
 * <ul>
 *   <li><b>Bond percolation:</b> every shared edge between two adjacent cells opens iff
 *       {@code hash(seed, edge) % 100 < 58} — above the square-lattice threshold (0.5),
 *       so the open cluster spans the map while sealed pockets still occur (closed walls
 *       get a hashed 1-block eye-level peep gap so you can see INTO pockets).</li>
 *   <li><b>Highways:</b> rows/columns {4±j, 12, 20±j} (hash-jittered ±1, center pinned
 *       so the spawn cell always sits on a highway cross) carve straight corridors end
 *       to end — guaranteed reachability without a solver.</li>
 *   <li><b>Prefabs per cell</b> (hashed): CORRIDOR 40%, OFFICE 25%, PILLAR_HALL
 *       (double height) 12%, WET_ROOM 12%, DEAD_END_CLOSET 8%, LOOT_ALCOVE 3%.</li>
 *   <li><b>Mono-yellow palette:</b> {@code yellow_terracotta} lower course,
 *       {@code stripped_bamboo_block} upper courses, {@code sponge} floor (damp-carpet
 *       read), {@code yellow_carpet} highway path, {@code smooth_sandstone} ceiling,
 *       {@code ochre_froglight} 2×1 light strips (the flicker swap target is
 *       {@code yellow_stained_glass}), 3% {@code yellow_concrete_powder} wall stains.</li>
 * </ul>
 *
 * <p>The stamp writes EVERY block of the maze volume (air included), so re-stamping a
 * new instance over an old maze self-cleans — the {@code GhostShipBuilder} idempotence
 * law. Stamping is budgeted by cell ({@link #stampCell}) so the event service can spread
 * the ~295k set-blocks over a few dozen ticks during ANNOUNCED.</p>
 */
public final class BackroomsMaze {
    /** Cells per side (24×24). */
    public static final int CELLS = 24;
    /** Blocks per cell side (7 interior + 1 shared wall line). */
    public static final int CELL = 8;
    /** Maze footprint in blocks per side. */
    public static final int SIZE = CELLS * CELL;
    /** World X/Z of cell (0,0)'s minimum corner — centers the maze on the origin. */
    public static final int ORIGIN = -SIZE / 2;
    /** Floor slab Y (sponge). */
    public static final int FLOOR_Y = 8;
    /** First interior air Y. */
    public static final int AIR_Y = FLOOR_Y + 1;
    /** Ceiling Y of normal cells (interior height 3). */
    public static final int CEIL_Y = AIR_Y + 3;
    /** Ceiling Y of double-height PILLAR_HALL cells (interior height 6). */
    public static final int CEIL_Y_TALL = AIR_Y + 6;
    /** Top of the stamped volume (walls always seal up to here). */
    public static final int TOP_Y = CEIL_Y_TALL;
    /** Spawn cell (center; sits on the pinned center highway cross). */
    public static final int SPAWN_CELL = CELLS / 2;

    /** Per-instance seed salt (IDEAS §A1 verbatim). */
    private static final long SEED_SALT = 0xBAC2C0035EEDL;
    /** Bond-percolation open threshold, percent. */
    private static final int EDGE_OPEN_PERCENT = 58;
    /** Faulty light-panel share, percent (IDEAS §A2; halve to 3 if relight load bites). */
    private static final int FAULTY_PANEL_PERCENT = 6;
    /** Wall-stain share, percent (IDEAS §A6.7). */
    private static final int WALL_STAIN_PERCENT = 3;

    /** Cell prefab kinds, hashed per cell (IDEAS §A1 step 3). */
    public enum Prefab { CORRIDOR, OFFICE, PILLAR_HALL, WET_ROOM, DEAD_END_CLOSET, LOOT_ALCOVE }

    /** One ceiling light strip (2×1 froglight panel); {@code faulty} panels flicker. */
    public record Panel(BlockPos a, BlockPos b, boolean faulty) {}

    private BackroomsMaze() {}

    // ================================================================== seed & hashing

    /** {@code ECLIPSE_SEED ^ 0xBAC2C0035EEDL ^ instanceId} — reproducible per instance. */
    public static long mazeSeed(int instanceId) {
        return DiscMapData.ECLIPSE_SEED ^ SEED_SALT ^ (long) instanceId;
    }

    /** SplitMix64-style avalanche; the repo's stateless hash idiom. */
    private static long scramble(long x) {
        x ^= x >>> 33;
        x *= 0xFF51AFD7ED558CCDL;
        x ^= x >>> 33;
        x *= 0xC4CEB9FE1A85EC53L;
        x ^= x >>> 33;
        return x;
    }

    private static long hash(long seed, long a, long b) {
        return scramble(seed ^ scramble(a * 0x9E3779B97F4A7C15L) ^ scramble(b * 0xC2B2AE3D27D4EB4FL));
    }

    private static int hashPercent(long seed, long a, long b) {
        return (int) Math.floorMod(hash(seed, a, b), 100L);
    }

    // ================================================================== cell math

    private static long cellKey(int cx, int cz) {
        return ((long) cx << 32) | (cz & 0xFFFFFFFFL);
    }

    /** Highway rows/cols: {4±j, 12, 20±j}; the center lane is PINNED through the spawn cell. */
    private static int[] highwayLanes(long seed, boolean rows) {
        long salt = rows ? 0x11L : 0x22L;
        int j1 = (int) Math.floorMod(hash(seed, salt, 1L), 3L) - 1; // -1..1
        int j2 = (int) Math.floorMod(hash(seed, salt, 2L), 3L) - 1;
        return new int[] {4 + j1, SPAWN_CELL, 20 + j2};
    }

    /** Whether cell row {@code cz} is a highway row for this seed. */
    public static boolean isHighwayRow(long seed, int cz) {
        for (int lane : highwayLanes(seed, true)) {
            if (lane == cz) {
                return true;
            }
        }
        return false;
    }

    /** Whether cell column {@code cx} is a highway column for this seed. */
    public static boolean isHighwayCol(long seed, int cx) {
        for (int lane : highwayLanes(seed, false)) {
            if (lane == cx) {
                return true;
            }
        }
        return false;
    }

    public static boolean isHighwayCell(long seed, int cx, int cz) {
        return isHighwayRow(seed, cz) || isHighwayCol(seed, cx);
    }

    /**
     * Whether the shared edge between (cx,cz) and its +X neighbor is OPEN. Highway rows
     * force their east-west run open; otherwise bond percolation at 58%.
     */
    public static boolean edgeOpenEast(long seed, int cx, int cz) {
        if (cx < 0 || cx >= CELLS - 1 || cz < 0 || cz >= CELLS) {
            return false; // outer boundary is always sealed
        }
        if (isHighwayRow(seed, cz)) {
            return true;
        }
        return hashPercent(seed, cellKey(cx, cz), cellKey(cx + 1, cz) ^ 0xEA57L) < EDGE_OPEN_PERCENT;
    }

    /** Whether the shared edge between (cx,cz) and its +Z neighbor is OPEN. */
    public static boolean edgeOpenSouth(long seed, int cx, int cz) {
        if (cx < 0 || cx >= CELLS || cz < 0 || cz >= CELLS - 1) {
            return false;
        }
        if (isHighwayCol(seed, cx)) {
            return true;
        }
        return hashPercent(seed, cellKey(cx, cz), cellKey(cx, cz + 1) ^ 0x50D7L) < EDGE_OPEN_PERCENT;
    }

    /** Hashed prefab pick; spawn cell and highway cells read as plain corridor. */
    public static Prefab prefab(long seed, int cx, int cz) {
        if ((cx == SPAWN_CELL && cz == SPAWN_CELL) || isHighwayCell(seed, cx, cz)) {
            return Prefab.CORRIDOR;
        }
        int roll = hashPercent(seed, cellKey(cx, cz), 0x9EFAL);
        if (roll < 40) {
            return Prefab.CORRIDOR;
        } else if (roll < 65) {
            return Prefab.OFFICE;
        } else if (roll < 77) {
            return Prefab.PILLAR_HALL;
        } else if (roll < 89) {
            return Prefab.WET_ROOM;
        } else if (roll < 97) {
            return Prefab.DEAD_END_CLOSET;
        }
        return Prefab.LOOT_ALCOVE;
    }

    /** Ceiling Y of a cell (double height only for PILLAR_HALL). */
    public static int ceilY(long seed, int cx, int cz) {
        return prefab(seed, cx, cz) == Prefab.PILLAR_HALL ? CEIL_Y_TALL : CEIL_Y;
    }

    /** World min corner (block coords) of a cell. */
    public static BlockPos cellMin(int cx, int cz) {
        return new BlockPos(ORIGIN + cx * CELL, FLOOR_Y, ORIGIN + cz * CELL);
    }

    /** Interior center of a cell at floor-walk height (player teleport target). */
    public static BlockPos cellCenter(int cx, int cz) {
        return new BlockPos(ORIGIN + cx * CELL + 3, AIR_Y, ORIGIN + cz * CELL + 3);
    }

    /** Cell coords of a world position ({@code null} outside the maze). */
    @Nullable
    public static int[] cellOf(BlockPos pos) {
        int cx = Math.floorDiv(pos.getX() - ORIGIN, CELL);
        int cz = Math.floorDiv(pos.getZ() - ORIGIN, CELL);
        if (cx < 0 || cx >= CELLS || cz < 0 || cz >= CELLS) {
            return null;
        }
        return new int[] {cx, cz};
    }

    // ================================================================== panels

    /**
     * All ceiling light panels of the maze, deterministic order: one 2×1
     * {@code ochre_froglight} strip per cell at interior offsets (2..3, 3); highway cells
     * get a second strip at (2..3, 1). Faulty panels are hashed at
     * {@value #FAULTY_PANEL_PERCENT}% with same-cell adjacency rejection (no two panels
     * of one cell both faulty — photosensitivity guard, IDEAS §A2).
     */
    public static List<Panel> panels(long seed) {
        List<Panel> panels = new ArrayList<>(CELLS * CELLS + 3 * CELLS);
        for (int cz = 0; cz < CELLS; cz++) {
            for (int cx = 0; cx < CELLS; cx++) {
                int ceil = ceilY(seed, cx, cz);
                BlockPos min = cellMin(cx, cz);
                BlockPos a1 = new BlockPos(min.getX() + 2, ceil, min.getZ() + 3);
                BlockPos b1 = new BlockPos(min.getX() + 3, ceil, min.getZ() + 3);
                boolean faulty1 = hashPercent(seed, a1.asLong(), 0xF11CL) < FAULTY_PANEL_PERCENT;
                panels.add(new Panel(a1, b1, faulty1));
                if (isHighwayCell(seed, cx, cz)) {
                    BlockPos a2 = new BlockPos(min.getX() + 2, ceil, min.getZ() + 1);
                    BlockPos b2 = new BlockPos(min.getX() + 3, ceil, min.getZ() + 1);
                    boolean faulty2 = !faulty1
                            && hashPercent(seed, a2.asLong(), 0xF11CL) < FAULTY_PANEL_PERCENT;
                    panels.add(new Panel(a2, b2, faulty2));
                }
            }
        }
        return panels;
    }

    /**
     * Flicker schedule of a faulty panel (server clock): within each hashed period
     * (120–279 t) the panel is DARK for a hashed 3–6 t window — one cycle per period,
     * far under the 3-flashes/second photosensitivity ceiling.
     */
    public static boolean panelLitAt(long seed, Panel panel, long gameTime) {
        if (!panel.faulty()) {
            return true;
        }
        long h = hash(seed, panel.a().asLong(), 0x0FFL);
        long period = 120L + Math.floorMod(h, 160L);
        long phase = Math.floorMod(gameTime + Math.floorMod(h >>> 16, period), period);
        long darkLen = 3L + Math.floorMod(h >>> 32, 4L); // 3..6 t
        return phase >= darkLen;
    }

    // ================================================================== stamping

    /**
     * Stamps ONE cell (8×8 columns, floor..{@link #TOP_Y}), writing every block including
     * air — idempotent and self-cleaning over a previous instance's maze. Call for all
     * cx/cz in 0..{@value #CELLS}-1 plus {@link #stampBoundary} once; budget across ticks.
     */
    public static void stampCell(ServerLevel level, long seed, int cx, int cz) {
        BlockPos min = cellMin(cx, cz);
        Prefab prefab = prefab(seed, cx, cz);
        int ceil = ceilY(seed, cx, cz);
        boolean highway = isHighwayCell(seed, cx, cz);
        boolean openEast = edgeOpenEast(seed, cx, cz);
        boolean openSouth = edgeOpenSouth(seed, cx, cz);

        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int dx = 0; dx < CELL; dx++) {
            for (int dz = 0; dz < CELL; dz++) {
                int x = min.getX() + dx;
                int z = min.getZ() + dz;
                boolean wallLine = dx == CELL - 1 || dz == CELL - 1;
                // Floor: sponge everywhere (mottled damp-carpet read).
                set(level, cursor.set(x, FLOOR_Y, z), Blocks.SPONGE.defaultBlockState());
                if (wallLine) {
                    stampWallColumn(level, seed, cursor, x, z, dx, dz, cx, cz, openEast, openSouth);
                    continue;
                }
                // Interior air column + ceiling.
                for (int y = AIR_Y; y <= TOP_Y; y++) {
                    BlockState state;
                    if (y < ceil) {
                        state = Blocks.AIR.defaultBlockState();
                    } else if (y == ceil) {
                        state = Blocks.SMOOTH_SANDSTONE.defaultBlockState();
                    } else {
                        state = Blocks.AIR.defaultBlockState(); // void above the ceiling plane
                    }
                    set(level, cursor.set(x, y, z), state);
                }
            }
        }

        stampLights(level, seed, cx, cz);
        stampPrefab(level, seed, cx, cz, prefab);
        if (highway) {
            stampHighwayCarpet(level, seed, cx, cz);
        }
    }

    /** One wall-line column (dx==7 or dz==7): open edges carve, closed edges seal. */
    private static void stampWallColumn(ServerLevel level, long seed, BlockPos.MutableBlockPos cursor,
            int x, int z, int dx, int dz, int cx, int cz, boolean openEast, boolean openSouth) {
        boolean corner = dx == CELL - 1 && dz == CELL - 1;
        boolean carve;
        if (corner) {
            carve = false; // the pillar grid always stands
        } else if (dx == CELL - 1) {
            // East wall segment: carve fully when the edge is open (open-plan read).
            carve = openEast;
        } else {
            carve = openSouth;
        }
        if (carve) {
            for (int y = AIR_Y; y <= TOP_Y; y++) {
                set(level, cursor.set(x, y, z),
                        y < CEIL_Y ? Blocks.AIR.defaultBlockState()
                                : y == CEIL_Y ? Blocks.SMOOTH_SANDSTONE.defaultBlockState()
                                        : Blocks.AIR.defaultBlockState());
            }
            return;
        }
        // Sealed wall: terracotta lower course, bamboo "wallpaper" above, hashed stains,
        // and a rare eye-level 1-block peep gap into sealed pockets (IDEAS §A1.1 dread).
        boolean peepGap = !corner
                && hashPercent(seed, cellKey(cx, cz) ^ ((long) dx << 8) ^ dz, 0x9EEBL) < 6;
        for (int y = AIR_Y; y <= TOP_Y; y++) {
            BlockState state;
            if (peepGap && y == AIR_Y + 1) {
                state = Blocks.AIR.defaultBlockState();
            } else if (y == AIR_Y) {
                state = Blocks.YELLOW_TERRACOTTA.defaultBlockState();
            } else if (hashPercent(seed, BlockPos.asLong(x, y, z), 0x57A1L) < WALL_STAIN_PERCENT) {
                state = Blocks.YELLOW_CONCRETE_POWDER.defaultBlockState();
            } else {
                state = Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState();
            }
            set(level, cursor.set(x, y, z), state);
        }
    }

    /** Ceiling froglight strips; faulty panels stamp LIT (the flicker tick swaps live). */
    private static void stampLights(ServerLevel level, long seed, int cx, int cz) {
        int ceil = ceilY(seed, cx, cz);
        BlockPos min = cellMin(cx, cz);
        placePanel(level, min.getX() + 2, ceil, min.getZ() + 3);
        if (isHighwayCell(seed, cx, cz)) {
            placePanel(level, min.getX() + 2, ceil, min.getZ() + 1);
        }
        // A few hashed DEAD panels (unlit lookalikes) that never worked to begin with.
        if (hashPercent(seed, cellKey(cx, cz), 0xDEADL) < 12) {
            set(level, new BlockPos(min.getX() + 5, ceil, min.getZ() + 5),
                    Blocks.YELLOW_STAINED_GLASS.defaultBlockState());
        }
    }

    private static void placePanel(ServerLevel level, int x, int y, int z) {
        set(level, new BlockPos(x, y, z), Blocks.OCHRE_FROGLIGHT.defaultBlockState());
        set(level, new BlockPos(x + 1, y, z), Blocks.OCHRE_FROGLIGHT.defaultBlockState());
    }

    /** Worn walking path: 3-wide yellow carpet through highway cells. */
    private static void stampHighwayCarpet(ServerLevel level, long seed, int cx, int cz) {
        BlockPos min = cellMin(cx, cz);
        BlockState carpet = Blocks.YELLOW_CARPET.defaultBlockState();
        if (isHighwayRow(seed, cz)) {
            for (int dx = 0; dx < CELL - 1; dx++) {
                for (int dz = 2; dz <= 4; dz++) {
                    setIfAir(level, new BlockPos(min.getX() + dx, AIR_Y, min.getZ() + dz), carpet);
                }
            }
        }
        if (isHighwayCol(seed, cx)) {
            for (int dz = 0; dz < CELL - 1; dz++) {
                for (int dx = 2; dx <= 4; dx++) {
                    setIfAir(level, new BlockPos(min.getX() + dx, AIR_Y, min.getZ() + dz), carpet);
                }
            }
        }
    }

    /** Prefab dressing on top of the bare shell. */
    private static void stampPrefab(ServerLevel level, long seed, int cx, int cz, Prefab prefab) {
        BlockPos min = cellMin(cx, cz);
        switch (prefab) {
            case OFFICE -> {
                // Two desk stubs: terracotta block + sandstone slab top.
                stampDesk(level, min.offset(1, 0, 2));
                stampDesk(level, min.offset(5, 0, 4));
            }
            case PILLAR_HALL -> {
                // Double-height hall: two full bamboo pillars.
                for (int y = AIR_Y; y < CEIL_Y_TALL; y++) {
                    set(level, new BlockPos(min.getX() + 1, y, min.getZ() + 1),
                            Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState());
                    set(level, new BlockPos(min.getX() + 5, y, min.getZ() + 5),
                            Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState());
                }
            }
            case DEAD_END_CLOSET -> {
                // Inner partition with a single doorway — a closet you can get INTO.
                for (int dz = 0; dz <= 6; dz++) {
                    if (dz == 3) {
                        continue;
                    }
                    for (int y = AIR_Y; y < CEIL_Y; y++) {
                        set(level, new BlockPos(min.getX() + 4, y, min.getZ() + dz),
                                Blocks.YELLOW_TERRACOTTA.defaultBlockState());
                    }
                }
            }
            case LOOT_ALCOVE -> {
                BlockPos barrel = min.offset(3, 1, 3);
                set(level, barrel, Blocks.BARREL.defaultBlockState());
                fillLootBarrel(level, seed, barrel, cx, cz);
                setIfAir(level, barrel.offset(1, -1, 0).above(),
                        Blocks.YELLOW_CARPET.defaultBlockState());
            }
            case WET_ROOM, CORRIDOR -> {
                // WET_ROOM reads through drips (ambient tick) + the sponge floor itself.
            }
        }
    }

    private static void stampDesk(ServerLevel level, BlockPos base) {
        set(level, base.above(), Blocks.YELLOW_TERRACOTTA.defaultBlockState());
        set(level, base.above(2), Blocks.CUT_SANDSTONE_SLAB.defaultBlockState());
    }

    /**
     * LOOT_ALCOVE barrel loot (IDEAS §A5): Almond Water (re-skinned Regeneration potion —
     * the community in-joke and a mid-event heal), 1–2 glitch shards, rare wallpaper
     * trophy (yellow terracotta with a custom name). Real container = natural one-shot
     * semantics per instance (the re-stamp refills it next instance).
     */
    private static void fillLootBarrel(ServerLevel level, long seed, BlockPos pos, int cx, int cz) {
        if (!(level.getBlockEntity(pos) instanceof BarrelBlockEntity barrel)) {
            return;
        }
        barrel.clearContent();
        barrel.setItem(3, almondWater());
        int shards = 1 + hashPercent(seed, cellKey(cx, cz), 0x10071L) % 2;
        barrel.setItem(5, new ItemStack(EclipseItems.GLITCH_SHARD.get(), shards));
        if (hashPercent(seed, cellKey(cx, cz), 0x77A11L) < 20) {
            ItemStack wallpaper = new ItemStack(Blocks.STRIPPED_BAMBOO_BLOCK.asItem());
            wallpaper.set(DataComponents.CUSTOM_NAME,
                    Component.translatable("item.eclipse.yellow_wallpaper"));
            barrel.setItem(7, wallpaper);
        }
    }

    /** Almond Water — vanilla Regeneration potion aliased with the joke name. */
    public static ItemStack almondWater() {
        ItemStack stack = new ItemStack(Items.POTION);
        stack.set(DataComponents.POTION_CONTENTS, new PotionContents(Potions.REGENERATION));
        stack.set(DataComponents.CUSTOM_NAME, Component.translatable("item.eclipse.almond_water"));
        return stack;
    }

    /**
     * Perimeter ring one block OUTSIDE the cell grid (the -X/-Z sides have no wall line
     * of their own) — seals the maze so nobody walks into the void.
     */
    public static void stampBoundary(ServerLevel level) {
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        int lo = ORIGIN - 1;
        int hi = ORIGIN + SIZE - 1; // == last wall-line coordinate (dx==7 of cell 23)
        for (int i = lo; i <= hi; i++) {
            for (int y = FLOOR_Y; y <= TOP_Y; y++) {
                BlockState state = y == FLOOR_Y || y == AIR_Y
                        ? Blocks.YELLOW_TERRACOTTA.defaultBlockState()
                        : Blocks.STRIPPED_BAMBOO_BLOCK.defaultBlockState();
                set(level, cursor.set(i, y, lo), state);
                set(level, cursor.set(lo, y, i), state);
            }
            // Baseboard shadowline along the outer ring (palette: cut sandstone slab).
            setIfAir(level, new BlockPos(i, AIR_Y, lo + 1), Blocks.CUT_SANDSTONE_SLAB.defaultBlockState());
            setIfAir(level, new BlockPos(lo + 1, AIR_Y, i), Blocks.CUT_SANDSTONE_SLAB.defaultBlockState());
        }
    }

    /** Total stamp units: all cells + 1 boundary pass (progress cursor for the service). */
    public static int totalStampUnits() {
        return CELLS * CELLS + 1;
    }

    /** Stamps unit {@code index} (row-major cells, then the boundary ring). */
    public static void stampUnit(ServerLevel level, long seed, int index) {
        if (index >= CELLS * CELLS) {
            stampBoundary(level);
            return;
        }
        stampCell(level, seed, index % CELLS, index / CELLS);
    }

    // ================================================================== block helpers

    /** Flag 2 (send to clients, no neighbor updates) — cheap bulk stamping. */
    private static void set(ServerLevel level, BlockPos pos, BlockState state) {
        if (!level.getBlockState(pos).equals(state)) {
            level.setBlock(pos, state, 2);
        }
    }

    private static void setIfAir(ServerLevel level, BlockPos pos, BlockState state) {
        if (level.getBlockState(pos).isAir()) {
            level.setBlock(pos, state, 2);
        }
    }
}
