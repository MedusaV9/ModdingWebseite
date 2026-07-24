package dev.projecteclipse.eclipse.limbo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.RotatedPillarBlock;
import net.minecraft.world.level.block.state.BlockState;

/**
 * Procedural set dressing of the Limbo ocean around the ghost ship
 * ({@link GhostShipBuilder} pattern: deterministic static setBlock loops, no NBT files,
 * fixed layout constants + {@link DiscMapData#ECLIPSE_SEED}-derived hashes only — never
 * the world seed or {@code level.random}). Built once per world, guarded by
 * {@link EclipseWorldState#isLimboSeascapeBuilt()}, hooked from
 * {@link GhostShipBuilder#onServerStarted} right after the ship itself builds.
 *
 * <p>Everything is anchored to the same waterline Y the ship uses
 * ({@link GhostShipBuilder#waterlineY}, y=48 with the shipped datapack) and placed on a
 * 120-260 block ring around the origin so the horizon of the empty water plane reads as
 * a graveyard sea instead of a void:</p>
 *
 * <ul>
 *   <li><b>Half-sunken dark-oak wreck fragments</b> — two listing hull sections at
 *       (150, −95) and (−120, −160), a bow breaching the surface at (−170, 120) and a
 *       snapped-mast raft with black-wool sail scraps at (95, 185).</li>
 *   <li><b>Blackstone/obsidian spires</b> crested with soul fire at (205, 40),
 *       (−95, −215) and (−230, −35).</li>
 *   <li><b>A lane of soul-lantern buoys</b> (floating chain strands with a hanging
 *       lantern, every third one with a plank float) leading from the ship's bow at
 *       x≈32 out to x≈240 towards the +X horizon.</li>
 * </ul>
 *
 * <p>Submerged wreck volumes stay flooded (walls only, interiors keep their water) so
 * no block updates can trigger drain/flow cascades; the crowning soul fires stand on
 * soul soil so they are block-stable under {@code UPDATE_ALL} neighbour updates, and
 * lanterns hang beneath chains for the same reason.</p>
 */
public final class LimboSeascape {
    private static final BlockState PLANKS = Blocks.DARK_OAK_PLANKS.defaultBlockState();
    private static final BlockState LOG = Blocks.DARK_OAK_LOG.defaultBlockState();
    private static final BlockState FENCE = Blocks.DARK_OAK_FENCE.defaultBlockState();
    private static final BlockState WOOL = Blocks.BLACK_WOOL.defaultBlockState();
    private static final BlockState BLACKSTONE = Blocks.BLACKSTONE.defaultBlockState();
    private static final BlockState OBSIDIAN = Blocks.OBSIDIAN.defaultBlockState();
    private static final BlockState SOUL_SOIL = Blocks.SOUL_SOIL.defaultBlockState();
    private static final BlockState SOUL_FIRE = Blocks.SOUL_FIRE.defaultBlockState();
    private static final BlockState CHAIN = Blocks.CHAIN.defaultBlockState();
    private static final BlockState SOUL_LANTERN_HANGING = Blocks.SOUL_LANTERN.defaultBlockState()
            .setValue(LanternBlock.HANGING, true);

    /** Buoy count of the lantern lane along +X. */
    private static final int BUOY_COUNT = 9;
    /** X of the first buoy (just past the ship's bow) and spacing towards the horizon. */
    private static final int BUOY_START_X = 32;
    private static final int BUOY_SPACING = 26;

    private LimboSeascape() {}

    /** Builds the seascape once; subsequent calls are no-ops thanks to the world-state flag. */
    public static void buildIfNeeded(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (state.isLimboSeascapeBuilt()) {
            return;
        }
        int waterline = GhostShipBuilder.waterlineY(limbo);
        build(limbo, waterline);
        state.setLimboSeascapeBuilt(true);
        EclipseMod.LOGGER.info("Limbo seascape built at waterline y={} (4 wrecks, 3 spires, {} buoys)",
                waterline, BUOY_COUNT);
    }

    /** Unconditionally builds every seascape feature. Idempotent block-wise. */
    public static void build(ServerLevel limbo, int waterline) {
        listingHull(limbo, 150, -95, waterline, 0, 6);
        listingHull(limbo, -120, -160, waterline, 1, 4);
        breachingBow(limbo, -170, 120, waterline, 2);
        snappedMastRaft(limbo, 95, 185, waterline, 3);
        spire(limbo, 205, 40, waterline, 13);
        spire(limbo, -95, -215, waterline, 16);
        spire(limbo, -230, -35, waterline, 10);
        buoyLane(limbo, waterline);
    }

    /**
     * A listing hull section: keel floor at waterline−3, a broken low wall awash on one
     * side, the opposite wall heeled up to waterline+2 with vertical log ribs, closed
     * transoms at both ends and a clinging strip of deck planks on the high side. The
     * interior below the waterline stays flooded.
     */
    private static void listingHull(ServerLevel level, int cx, int cz, int w, int o, int halfLen) {
        int keelY = w - 3;
        for (int a = -halfLen; a <= halfLen; a++) {
            int hw = Math.abs(a) <= halfLen / 2 ? 3 : Math.abs(a) < halfLen ? 2 : 1;
            boolean rib = Math.floorMod(a, 3) == 0;
            for (int b = -hw; b <= hw; b++) {
                place(level, cx, cz, o, a, keelY, b, PLANKS);
            }
            for (int y = keelY + 1; y <= w - 1; y++) {
                place(level, cx, cz, o, a, y, -hw, rib ? LOG : PLANKS);
            }
            int highTop = Math.abs(a) >= halfLen - 1 ? w + 1 : w + 2;
            for (int y = keelY + 1; y <= highTop; y++) {
                place(level, cx, cz, o, a, y, hw, rib ? LOG : PLANKS);
            }
            if (Math.abs(a) == halfLen) {
                for (int b = -hw + 1; b <= hw - 1; b++) {
                    for (int y = keelY + 1; y <= w; y++) {
                        place(level, cx, cz, o, a, y, b, PLANKS);
                    }
                }
            } else if (Math.abs(a) <= halfLen - 2 && hash01(cx + a, w, cz + hw) < 0.7D) {
                place(level, cx, cz, o, a, w + 1, hw - 1, PLANKS);
            }
        }
    }

    /**
     * A bow breaching the surface: a solid two-layer plank wedge climbing from
     * waterline−3 to waterline+4 while narrowing to the stem, with a keel-spine log on
     * top and a log bowsprit (fence tip) spearing out past the prow.
     */
    private static void breachingBow(ServerLevel level, int bx, int bz, int w, int o) {
        for (int i = 0; i <= 9; i++) {
            int y = w - 3 + (i * 8) / 10;
            int hw = i < 4 ? 3 : i < 7 ? 2 : 1;
            for (int b = -hw; b <= hw; b++) {
                place(level, bx, bz, o, i, y, b, PLANKS);
                place(level, bx, bz, o, i, y - 1, b, PLANKS);
            }
            if (i >= 2) {
                place(level, bx, bz, o, i, y + 1, 0, horizontalLog(o));
            }
        }
        for (int i = 10; i <= 12; i++) {
            place(level, bx, bz, o, i, w + 5, 0, horizontalLog(o));
        }
        place(level, bx, bz, o, 13, w + 5, 0, FENCE);
    }

    /**
     * An awash raft of deck planks (hash-eaten edges) carrying a snapped mast stump: a
     * 5-block log with a short fence yard, torn black-wool sail scraps, and the toppled
     * top half of the mast lying overboard in the water.
     */
    private static void snappedMastRaft(ServerLevel level, int mx, int mz, int w, int o) {
        for (int a = -3; a <= 3; a++) {
            for (int b = -2; b <= 2; b++) {
                boolean edge = Math.abs(a) == 3 || Math.abs(b) == 2;
                if (!edge || hash01(mx + a, w, mz + b) < 0.72D) {
                    place(level, mx, mz, o, a, w, b, PLANKS);
                }
            }
        }
        for (int y = w + 1; y <= w + 5; y++) {
            place(level, mx, mz, o, 0, y, 0, LOG);
        }
        place(level, mx, mz, o, 0, w + 4, 1, FENCE);
        place(level, mx, mz, o, 0, w + 4, 2, FENCE);
        for (int y = w + 2; y <= w + 3; y++) {
            for (int b = 1; b <= 2; b++) {
                if (hash01(mx + b, y, mz) < 0.65D) {
                    place(level, mx, mz, o, 0, y, b, WOOL);
                }
            }
        }
        for (int a = 2; a <= 5; a++) {
            place(level, mx, mz, o, a, w - 1, 2, horizontalLog(o));
        }
    }

    /**
     * A blackstone/obsidian spire rising from below the waterline: diamond-footprint
     * taper (radius 2 → 1 → needle) crested with a soul-soil cap and a soul fire.
     */
    private static void spire(ServerLevel level, int sx, int sz, int w, int height) {
        int top = w + height;
        for (int y = w - 10; y <= top; y++) {
            int radius = y < w - 2 ? 2 : y <= top - 3 ? 1 : 0;
            for (int dx = -radius; dx <= radius; dx++) {
                for (int dz = -radius; dz <= radius; dz++) {
                    if (Math.abs(dx) + Math.abs(dz) > radius) {
                        continue;
                    }
                    set(level, sx + dx, y, sz + dz,
                            hash01(sx + dx, y, sz + dz) < 0.35D ? OBSIDIAN : BLACKSTONE);
                }
            }
        }
        set(level, sx, top, sz, SOUL_SOIL);
        set(level, sx, top + 1, sz, SOUL_FIRE);
    }

    /**
     * The lantern lane: {@value #BUOY_COUNT} buoys marching from the ship's bow towards
     * the +X horizon, weaving ±4 blocks off the axis. Each buoy is a floating chain
     * strand with a soul lantern hanging just above the waves (chains need no support —
     * fittingly eerie for Limbo); every third buoy gets a bobbing plank float.
     */
    private static void buoyLane(ServerLevel level, int w) {
        for (int i = 0; i < BUOY_COUNT; i++) {
            int x = BUOY_START_X + i * BUOY_SPACING;
            int z = (int) ((hash01(i, 7, i * 31) - 0.5D) * 9.0D);
            set(level, x, w + 4, z, CHAIN);
            set(level, x, w + 3, z, CHAIN);
            set(level, x, w + 2, z, CHAIN);
            set(level, x, w + 1, z, SOUL_LANTERN_HANGING);
            if (i % 3 == 0) {
                set(level, x, w, z, PLANKS);
            }
        }
    }

    // --- placement helpers ---

    /** A dark-oak log lying along the fragment's local long axis after rotation. */
    private static BlockState horizontalLog(int o) {
        return LOG.setValue(RotatedPillarBlock.AXIS, (o & 1) == 0 ? Direction.Axis.X : Direction.Axis.Z);
    }

    /** Places a block at local offset (a, b) rotated by one of four cardinal orientations. */
    private static void place(ServerLevel level, int cx, int cz, int o, int a, int y, int b,
            BlockState state) {
        int dx;
        int dz;
        switch (o & 3) {
            case 0 -> {
                dx = a;
                dz = b;
            }
            case 1 -> {
                dx = -b;
                dz = a;
            }
            case 2 -> {
                dx = -a;
                dz = -b;
            }
            default -> {
                dx = b;
                dz = -a;
            }
        }
        set(level, cx + dx, y, cz + dz, state);
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        // Force-load like FortressCoreBuilder: features sit far outside the spawn chunks.
        level.getChunk(x >> 4, z >> 4);
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_ALL);
    }

    /** Fixed-seed positional hash (0..1); mirrors the FallbackBuilders mixer, local salt. */
    private static double hash01(int x, int y, int z) {
        long h = DiscMapData.ECLIPSE_SEED ^ (x * 341873128712L + y * 132897987541L + z * 914744113L);
        h = (h ^ (h >>> 30)) * 0xBF58476D1CE4E5B9L;
        h = (h ^ (h >>> 27)) * 0x94D049BB133111EBL;
        return ((h ^ (h >>> 31)) >>> 11) * 0x1.0p-53D;
    }
}
