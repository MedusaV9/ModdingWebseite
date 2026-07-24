package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.concurrent.atomic.AtomicBoolean;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.WorldGenLevel;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;

/**
 * IDEA-17 idea 4 (W4-NETHER): glowstone chandelier fields hanging from the nether roof
 * shell. Registered through the W1.1 {@link DiscGenPipeline.ExtraDecor} seam exactly like
 * {@link NetherUndersideDecor}, so chandeliers stamp on both fresh chunk generation and
 * live ring-sweep replay.
 *
 * <p>Deterministic and column-local: every column derives the SAME chandelier layout from
 * the frozen map seed and its 24-block cell hash, so chandeliers spanning chunk borders
 * assemble seamlessly (each chunk only writes its own columns). Layout per selected cell:
 * a 2–5 block CHAIN drop from the roof underside, a glowstone diamond tier (center + four
 * cardinal arms), four diagonal single-block drops one tier lower, and a 1-in-8 chance of
 * a SHROOMLIGHT core (warm/cold mix). Field density peaks in the nether_wastes wedge; the
 * other wedges keep roughly half the fields. All writes are {@code setIfAir} — the roof
 * seal and the stalactite forests are never broken.</p>
 */
public final class NetherCeilingDecor {
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** Class-local hash salts (same convention as {@link NetherUndersideDecor}). */
    private static final int SALT_FIELD = 0x4E43;   // 'NC' — cell selection + layout bits
    private static final int SALT_WEDGE = 0x4E44;   // off-wastes density thinning

    /** Chandelier cell grid: one candidate per 24x24 cell, ~30% of cells selected. */
    private static final int CELL_SIZE = 24;
    private static final double CELL_CHANCE = 0.30D;
    /** Off-wastes wedges keep this share of their fields (density peaks in the wastes). */
    private static final double OFF_WASTES_KEEP = 0.5D;
    /** Minimum clear height under the roof so chandeliers never jam into terrain. */
    private static final int MIN_CLEARANCE = 14;

    private NetherCeilingDecor() {}

    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            event.enqueueWork(() -> {
                if (REGISTERED.compareAndSet(false, true)) {
                    DiscGenPipeline.registerExtraDecor(
                            DiscProfile.NETHER, NetherCeilingDecor::decorate);
                    EclipseMod.LOGGER.info("Registered nether ceiling chandelier fields");
                }
            });
        }
    }

    /** Chunk-local post-decoration stamp used by {@link DiscGenPipeline}. */
    public static void decorate(WorldGenLevel level, ChunkAccess chunk) {
        int stage = WorldStageAccess.stage(DiscProfile.NETHER);
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
     * Writes this column's share of the cell's chandelier (if any). Center, arm and drop
     * columns each place only blocks at their own (x, z), so chandeliers crossing a chunk
     * border complete once the neighbour decorates — no cross-chunk writes needed.
     */
    private static void decorateColumn(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage) {
        int cellX = Math.floorDiv(x, CELL_SIZE);
        int cellZ = Math.floorDiv(z, CELL_SIZE);
        long h = hash(SALT_FIELD, cellX, cellZ);
        if (to01(h) >= CELL_CHANCE) {
            return;
        }
        int span = CELL_SIZE - 4;
        int centerX = cellX * CELL_SIZE + 2 + (int) ((h >>> 8) & 0x7FFFFFFFL) % span;
        int centerZ = cellZ * CELL_SIZE + 2 + (int) ((h >>> 32) & 0x7FFFFFFFL) % span;
        int dx = x - centerX;
        int dz = z - centerZ;
        if (Math.abs(dx) > 1 || Math.abs(dz) > 1) {
            return;
        }

        // Density gate: full fields in the nether_wastes wedge, ~half elsewhere.
        if (!"minecraft:nether_wastes".equals(map.biomeAt(DiscProfile.NETHER, centerX, centerZ))
                && to01(hash(SALT_WEDGE, cellX, cellZ)) >= OFF_WASTES_KEEP) {
            return;
        }

        // Geometry comes from the CENTER column so all nine columns agree on the hang
        // height; skip cells whose roof carries a lava-fall pour or sits too close to
        // the local terrain (rim taper band, stalactite clusters count as roof here).
        DiscColumn center = DiscTerrainFunction.column(DiscProfile.NETHER, centerX, centerZ, stage);
        if (!center.inside() || center.seamCurtain() != 0
                || center.ceilingBottomY() == Integer.MAX_VALUE
                || center.ceilingBottomY() - center.surfaceY() < MIN_CLEARANCE) {
            return;
        }
        int ceilingY = center.ceilingBottomY();
        int chainLength = 2 + (int) ((h >>> 16) & 3L);          // 2..5
        int tierY = ceilingY - chainLength - 1;                  // glowstone diamond tier
        boolean shroomCore = ((h >>> 40) & 7L) == 0L;            // 1-in-8 warm core

        if (dx == 0 && dz == 0) {
            for (int i = 1; i <= chainLength; i++) {
                setIfAir(chunk, cursor.set(x, ceilingY - i, z), Blocks.CHAIN.defaultBlockState());
            }
            setIfAir(chunk, cursor.set(x, tierY, z), shroomCore
                    ? Blocks.SHROOMLIGHT.defaultBlockState()
                    : Blocks.GLOWSTONE.defaultBlockState());
        } else if (Math.abs(dx) + Math.abs(dz) == 1) {
            // Cardinal arms of the diamond tier.
            setIfAir(chunk, cursor.set(x, tierY, z), Blocks.GLOWSTONE.defaultBlockState());
        } else {
            // Diagonal single-block drops one tier lower (deterministic from cell hash:
            // each corner has its own bit, ~3 of 4 present per chandelier).
            int corner = (dx > 0 ? 1 : 0) | (dz > 0 ? 2 : 0);
            if (((h >>> (48 + corner)) & 1L) != 0L || corner == (int) ((h >>> 44) & 3L)) {
                setIfAir(chunk, cursor.set(x, tierY - 1, z), Blocks.GLOWSTONE.defaultBlockState());
            }
        }
    }

    private static void setIfAir(ChunkAccess chunk, BlockPos pos, BlockState state) {
        if (chunk.getBlockState(pos).isAir()) {
            chunk.setBlockState(pos, state, false);
        }
    }

    private static long hash(int salt, int x, int z) {
        long h = FrozenParams.mapSeed() + (long) salt * 0x9E3779B97F4A7C15L;
        h ^= (long) x * 341873128712L;
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
