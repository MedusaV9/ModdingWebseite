package dev.projecteclipse.eclipse.worldgen;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.AmethystClusterBlock;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.MultifaceBlock;
import net.minecraft.world.level.block.PointedDripstoneBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;

/**
 * Plans_v5 B12: cave-interior dressing of the overworld disc, registered through the
 * W1.1 {@link DiscGenPipeline.ExtraDecor} seam (exact {@code NetherCeilingDecor}
 * pattern), so decor stamps on both fresh chunk generation and live ring-sweep replay:
 *
 * <ul>
 *   <li><b>Region dressing</b> keyed to {@link CaveBiomeMap}: lush pockets (moss skin +
 *       carpets, spore blossoms, glow lichen), dripstone fields (dripstone-block skin +
 *       pointed dripstone both ways), amethyst sparkle nooks in the B12 crystal region
 *       (calcite/amethyst skin, clusters, gated {@code BUDDING_AMETHYST} that cannot be
 *       harvested) and sculk skin in the deep-dark satellite pockets.</li>
 *   <li><b>Cathedral dressing</b> on {@link CaveDensity#cathedralAt} chambers: glow
 *       lichen falls under the dome, pointed-dripstone clusters and small spring
 *       lakelets recessed into the chamber floors.</li>
 *   <li><b>Fossil / ruin snippets</b>: rare 48-block cells roll either a bone-block rib
 *       cage or a collapsed brick ruin fragment onto a nearby cave floor.</li>
 * </ul>
 *
 * <p>Deterministic and column-local: every write lands at the writing column's own
 * (x, z), and every roll is a hash of {@link FrozenParams#mapSeed()} — snippets and
 * lakelets spanning chunk borders assemble seamlessly once the neighbour decorates.
 * Floor skins only ever replace natural base stone, so builders' blocks, ores and
 * structure shells are never overwritten.</p>
 */
public final class CaveDressings {
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** Class-local hash salts (decor convention, {@code NetherCeilingDecor} family). */
    private static final int SALT_DRESS = 0x4344;    // 'CD' — per-boundary dressing rolls
    private static final int SALT_SNIPPET = 0x4346;  // fossil/ruin cell selection
    private static final int SALT_LAKELET = 0x434C;  // cathedral lakelet cells

    /** Fossil/ruin snippet grid: one candidate per 48×48 cell, ~7 % of cells selected. */
    private static final int SNIPPET_CELL = 48;
    private static final double SNIPPET_CHANCE = 0.07D;
    /** Snippets apply to floor boundaries within this many blocks of their anchor Y. */
    private static final int SNIPPET_Y_WINDOW = 10;

    /** Cathedral lakelet grid: one candidate pool per 24×24 cell, 30 % of cells. */
    private static final int LAKELET_CELL = 24;
    private static final double LAKELET_CHANCE = 0.30D;
    private static final double LAKELET_RADIUS = 2.2D;

    private CaveDressings() {}

    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            event.enqueueWork(() -> {
                if (REGISTERED.compareAndSet(false, true)) {
                    DiscGenPipeline.registerExtraDecor(
                            DiscProfile.OVERWORLD, CaveDressings::decorate);
                    EclipseMod.LOGGER.info("Registered overworld cave dressings (B12)");
                }
            });
        }
    }

    /** Chunk-local post-decoration stamp used by {@link DiscGenPipeline}. */
    public static void decorate(WorldGenLevel level, ChunkAccess chunk) {
        int stage = WorldStageAccess.stage(DiscProfile.OVERWORLD);
        if (stage <= 0) {
            return;
        }
        DiscMapData map = DiscMapData.get();
        ChunkPos chunkPos = chunk.getPos();
        BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        for (int localX = 0; localX < 16; localX++) {
            int x = chunkPos.getMinBlockX() + localX;
            for (int localZ = 0; localZ < 16; localZ++) {
                int z = chunkPos.getMinBlockZ() + localZ;
                decorateColumn(map, chunk, cursor, x, z, stage);
            }
        }
    }

    /**
     * Walks this column's cave band once and dresses every air-over-solid (floor) and
     * solid-over-air (ceiling) boundary it finds. Bounds come from the same
     * {@link DiscTerrainFunction} column the carver used, so the scan never leaves the
     * cave band or enters the sealed mountain cavity shell.
     */
    private static void decorateColumn(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage) {
        DiscColumn col = DiscTerrainFunction.column(DiscProfile.OVERWORLD, x, z, stage, map);
        if (!col.inside() || col.shard() || col.caveMaxY() == Integer.MIN_VALUE) {
            return;
        }
        int yMin = Math.max(col.caveMinY(), chunk.getMinBuildHeight() + 1);
        int yMax = Math.min(col.surfaceY() - CaveBiomeMap.SURFACE_MARGIN,
                chunk.getMaxBuildHeight() - 2);
        if (yMax <= yMin) {
            return;
        }
        BlockState below = chunk.getBlockState(cursor.set(x, yMin - 1, z));
        for (int y = yMin; y <= yMax + 1; y++) {
            BlockState state = chunk.getBlockState(cursor.set(x, y, z));
            if (state.isAir() && isNaturalStone(below)) {
                dressFloor(chunk, cursor, col, x, y, z);
                // Re-read: the floor pass may have replaced this air block.
                state = chunk.getBlockState(cursor.set(x, y, z));
            } else if (!state.isAir() && below.isAir() && y - 1 >= yMin) {
                dressCeiling(chunk, cursor, col, x, y, z, state);
                state = chunk.getBlockState(cursor.set(x, y, z));
            }
            below = state;
        }
    }

    // --- floor boundaries (air at y, natural stone at y-1) ---

    private static void dressFloor(ChunkAccess chunk, BlockPos.MutableBlockPos cursor,
            DiscColumn col, int x, int y, int z) {
        if (trySnippet(chunk, cursor, x, y, z)) {
            return;
        }
        double roll = to01(hash(SALT_DRESS, x, y, z));
        if (CaveDensity.cathedralAt(x, y, z, col.surfaceY(), col.caveMinY(), col.caveFade())) {
            dressCathedralFloor(chunk, cursor, x, y, z, roll);
            return;
        }
        CaveBiomeMap.DetailRegion detail = CaveBiomeMap.detailRegionAt(x, z);
        if (detail == CaveBiomeMap.DetailRegion.CRYSTAL) {
            if (roll < 0.030D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.CALCITE.defaultBlockState());
            } else if (roll < 0.048D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.AMETHYST_BLOCK.defaultBlockState());
            } else if (roll < 0.056D) {
                // Gated sparkle: budding amethyst regrows clusters but can never be
                // harvested itself — the nook stays a place, not a farmable block.
                set(chunk, cursor.set(x, y - 1, z), Blocks.BUDDING_AMETHYST.defaultBlockState());
            } else if (roll < 0.072D) {
                set(chunk, cursor.set(x, y, z), Blocks.AMETHYST_CLUSTER.defaultBlockState()
                        .setValue(AmethystClusterBlock.FACING, Direction.UP));
            } else if (roll < 0.080D) {
                set(chunk, cursor.set(x, y, z), Blocks.MEDIUM_AMETHYST_BUD.defaultBlockState()
                        .setValue(AmethystClusterBlock.FACING, Direction.UP));
            }
            return;
        }
        if (detail == CaveBiomeMap.DetailRegion.SCULK_POCKET) {
            if (roll < 0.12D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.SCULK.defaultBlockState());
            } else if (roll < 0.15D) {
                set(chunk, cursor.set(x, y, z), Blocks.SCULK_VEIN.defaultBlockState()
                        .setValue(MultifaceBlock.getFaceProperty(Direction.DOWN), true));
            }
            return;
        }
        String region = CaveBiomeMap.regionAt(x, z);
        if ("minecraft:dripstone_caves".equals(region)) {
            if (roll < 0.050D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.DRIPSTONE_BLOCK.defaultBlockState());
            } else if (roll < 0.085D) {
                set(chunk, cursor.set(x, y, z), Blocks.POINTED_DRIPSTONE.defaultBlockState()
                        .setValue(PointedDripstoneBlock.TIP_DIRECTION, Direction.UP));
            }
        } else if ("minecraft:lush_caves".equals(region)) {
            if (roll < 0.050D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.MOSS_BLOCK.defaultBlockState());
            } else if (roll < 0.070D) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.MOSS_BLOCK.defaultBlockState());
                set(chunk, cursor.set(x, y, z), Blocks.MOSS_CARPET.defaultBlockState());
            }
        }
    }

    /** Cathedral floors: dripstone clusters, dripstone skin and recessed spring lakelets. */
    private static void dressCathedralFloor(ChunkAccess chunk, BlockPos.MutableBlockPos cursor,
            int x, int y, int z, double roll) {
        if (lakeletAt(chunk, cursor, x, y, z)) {
            return;
        }
        if (roll < 0.045D) {
            set(chunk, cursor.set(x, y - 1, z), Blocks.DRIPSTONE_BLOCK.defaultBlockState());
        } else if (roll < 0.080D) {
            set(chunk, cursor.set(x, y, z), Blocks.POINTED_DRIPSTONE.defaultBlockState()
                    .setValue(PointedDripstoneBlock.TIP_DIRECTION, Direction.UP));
        } else if (roll < 0.095D) {
            set(chunk, cursor.set(x, y - 1, z), Blocks.MOSS_BLOCK.defaultBlockState());
        }
    }

    /**
     * Recessed 1-deep spring pools on cathedral floors: hashed 24-cell centers, every
     * column within {@value #LAKELET_RADIUS} blocks sinks its own floor block to water
     * (column-local — uneven floors terrace the pool edge, which reads as natural).
     * The block under the pool must be solid so the water never falls through.
     */
    private static boolean lakeletAt(ChunkAccess chunk, BlockPos.MutableBlockPos cursor,
            int x, int y, int z) {
        int cellX = Math.floorDiv(x, LAKELET_CELL);
        int cellZ = Math.floorDiv(z, LAKELET_CELL);
        long h = hash(SALT_LAKELET, cellX, 0, cellZ);
        if (to01(h) >= LAKELET_CHANCE) {
            return false;
        }
        int span = LAKELET_CELL - 6;
        int centerX = cellX * LAKELET_CELL + 3 + (int) ((h >>> 8) & 0x7FFFL) % span;
        int centerZ = cellZ * LAKELET_CELL + 3 + (int) ((h >>> 24) & 0x7FFFL) % span;
        int dx = x - centerX;
        int dz = z - centerZ;
        if (dx * dx + dz * dz > LAKELET_RADIUS * LAKELET_RADIUS) {
            return false;
        }
        BlockState under = chunk.getBlockState(cursor.set(x, y - 2, z));
        if (under.isAir() || !isNaturalStone(chunk.getBlockState(cursor.set(x, y - 1, z)))) {
            return false;
        }
        set(chunk, cursor.set(x, y - 1, z), Blocks.WATER.defaultBlockState());
        return true;
    }

    // --- ceiling boundaries (solid at y, air at y-1) ---

    private static void dressCeiling(ChunkAccess chunk, BlockPos.MutableBlockPos cursor,
            DiscColumn col, int x, int y, int z, BlockState ceiling) {
        if (!isNaturalStone(ceiling)) {
            return;
        }
        int airY = y - 1;
        double roll = to01(hash(SALT_DRESS, x, airY, z) ^ 0x5DEECE66DL);
        if (CaveDensity.cathedralAt(x, airY, z, col.surfaceY(), col.caveMinY(), col.caveFade())) {
            // Glow-lichen falls under the dome + hanging dripstone clusters.
            if (roll < 0.12D) {
                set(chunk, cursor.set(x, airY, z), Blocks.GLOW_LICHEN.defaultBlockState()
                        .setValue(MultifaceBlock.getFaceProperty(Direction.UP), true));
            } else if (roll < 0.17D) {
                set(chunk, cursor.set(x, airY, z), Blocks.POINTED_DRIPSTONE.defaultBlockState()
                        .setValue(PointedDripstoneBlock.TIP_DIRECTION, Direction.DOWN));
            }
            return;
        }
        CaveBiomeMap.DetailRegion detail = CaveBiomeMap.detailRegionAt(x, z);
        if (detail == CaveBiomeMap.DetailRegion.CRYSTAL) {
            if (roll < 0.020D) {
                set(chunk, cursor.set(x, airY, z), Blocks.AMETHYST_CLUSTER.defaultBlockState()
                        .setValue(AmethystClusterBlock.FACING, Direction.DOWN));
            } else if (roll < 0.040D) {
                set(chunk, cursor.set(x, y, z), Blocks.AMETHYST_BLOCK.defaultBlockState());
            }
            return;
        }
        if (detail == CaveBiomeMap.DetailRegion.SCULK_POCKET) {
            if (roll < 0.040D) {
                set(chunk, cursor.set(x, airY, z), Blocks.SCULK_VEIN.defaultBlockState()
                        .setValue(MultifaceBlock.getFaceProperty(Direction.UP), true));
            }
            return;
        }
        String region = CaveBiomeMap.regionAt(x, z);
        if ("minecraft:dripstone_caves".equals(region)) {
            if (roll < 0.050D) {
                set(chunk, cursor.set(x, airY, z), Blocks.POINTED_DRIPSTONE.defaultBlockState()
                        .setValue(PointedDripstoneBlock.TIP_DIRECTION, Direction.DOWN));
            } else if (roll < 0.075D) {
                set(chunk, cursor.set(x, y, z), Blocks.DRIPSTONE_BLOCK.defaultBlockState());
            }
        } else if ("minecraft:lush_caves".equals(region)) {
            if (roll < 0.025D) {
                set(chunk, cursor.set(x, airY, z), Blocks.SPORE_BLOSSOM.defaultBlockState());
            } else if (roll < 0.080D) {
                set(chunk, cursor.set(x, airY, z), Blocks.GLOW_LICHEN.defaultBlockState()
                        .setValue(MultifaceBlock.getFaceProperty(Direction.UP), true));
            }
        }
    }

    // --- fossil / ruin snippets ---

    /**
     * Writes this column's share of the cell's fossil rib cage or ruin fragment when the
     * floor boundary at {@code y} sits inside the snippet's Y window. Patterns span a
     * 5×5 footprint; each column writes only its own blocks (chandelier discipline).
     *
     * @return {@code true} when a snippet claimed this boundary (region decor skips)
     */
    private static boolean trySnippet(ChunkAccess chunk, BlockPos.MutableBlockPos cursor,
            int x, int y, int z) {
        int cellX = Math.floorDiv(x, SNIPPET_CELL);
        int cellZ = Math.floorDiv(z, SNIPPET_CELL);
        long h = hash(SALT_SNIPPET, cellX, 0, cellZ);
        if (to01(h) >= SNIPPET_CHANCE) {
            return false;
        }
        int span = SNIPPET_CELL - 10;
        int centerX = cellX * SNIPPET_CELL + 5 + (int) ((h >>> 8) & 0x7FFFL) % span;
        int centerZ = cellZ * SNIPPET_CELL + 5 + (int) ((h >>> 24) & 0x7FFFL) % span;
        int dx = x - centerX;
        int dz = z - centerZ;
        if (Math.abs(dx) > 2 || Math.abs(dz) > 2) {
            return false;
        }
        int anchorY = -34 + (int) ((h >>> 40) & 0x3FL) % 36; // -34..1
        if (Math.abs(y - anchorY) > SNIPPET_Y_WINDOW) {
            return false;
        }
        boolean fossil = ((h >>> 46) & 1L) == 0L;
        if (fossil) {
            // Rib cage: two bone arcs along ±Z, a spine on the axis, a skull at its head.
            if (Math.abs(dz) == 2 && Math.abs(dx) <= 2) {
                int height = 3 - Math.abs(dx);
                for (int i = 0; i < height; i++) {
                    set(chunk, cursor.set(x, y + i, z), Blocks.BONE_BLOCK.defaultBlockState());
                }
            } else if (dz == 0 && dx > -2) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.BONE_BLOCK.defaultBlockState());
            } else if (dz == 0) {
                set(chunk, cursor.set(x, y, z), Blocks.SKELETON_SKULL.defaultBlockState());
            }
        } else {
            // Ruin fragment: broken brick floor, corner wall stubs, one cobweb drape.
            long detail = hash(SALT_SNIPPET, x, 1, z);
            if (Math.abs(dx) == 2 && Math.abs(dz) == 2) {
                set(chunk, cursor.set(x, y, z), Blocks.CRACKED_STONE_BRICKS.defaultBlockState());
                if ((detail & 3L) == 0L) {
                    set(chunk, cursor.set(x, y + 1, z), Blocks.MOSSY_STONE_BRICKS.defaultBlockState());
                }
            } else if (dx == 0 && dz == 0) {
                set(chunk, cursor.set(x, y - 1, z), Blocks.CHISELED_STONE_BRICKS.defaultBlockState());
                set(chunk, cursor.set(x, y + 1, z), Blocks.COBWEB.defaultBlockState());
            } else if ((detail & 7L) < 5L) {
                set(chunk, cursor.set(x, y - 1, z), (detail & 1L) == 0L
                        ? Blocks.MOSSY_STONE_BRICKS.defaultBlockState()
                        : Blocks.CRACKED_STONE_BRICKS.defaultBlockState());
            }
        }
        return true;
    }

    // --- shared helpers ---

    /** Natural base stone the floor/ceiling skins may replace (never ores or builds). */
    private static boolean isNaturalStone(BlockState state) {
        return state.is(BlockTags.BASE_STONE_OVERWORLD) || state.is(Blocks.DEEPSLATE)
                || state.is(Blocks.TUFF) || state.is(Blocks.CALCITE);
    }

    private static void set(ChunkAccess chunk, BlockPos pos, BlockState state) {
        chunk.setBlockState(pos, state, false);
    }

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
