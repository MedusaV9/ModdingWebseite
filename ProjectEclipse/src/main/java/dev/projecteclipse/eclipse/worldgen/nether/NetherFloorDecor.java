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
 * B6 (plans_v5): deterministic dressing for the nether FLOOR — the counterpart of the
 * praised ceiling ({@link NetherCeilingDecor}) and underside ({@link NetherUndersideDecor})
 * layers, so the wastes stop reading as flat empty plates. Registered through the W1.1
 * {@link DiscGenPipeline.ExtraDecor} seam (no {@code DiscGenPipeline} edit), so every
 * stamp lands on both fresh chunk generation and live ring-sweep replay.
 *
 * <p>Per sector wedge: glowstone growth mounds + short magma seams in the wastes,
 * scattered 3–8 high basalt pillars in the basalt deltas, wart-bulb patches with arched
 * bone-block ribs in crimson/warped, and fire / soul-fire patches in the soul valleys.
 * Everything derives from {@link FrozenParams#mapSeed()} cell hashes and is column-local
 * (each chunk writes only its own columns), so features crossing chunk borders assemble
 * seamlessly. Moat lips, seam-curtain bowls, lava pools and landmark pads stay
 * undressed; ground writes never break the terrain (top-block flips only, everything
 * else is {@code setIfAir}).</p>
 */
public final class NetherFloorDecor {
    private static final AtomicBoolean REGISTERED = new AtomicBoolean();

    /** Class-local hash salts (same convention as {@link NetherCeilingDecor}). */
    private static final int SALT_GROWTH = 0x4E46;      // 'NF' — glowstone growth cells
    private static final int SALT_SEAM = 0x4E4D;        // 'NM' — magma seam cells
    private static final int SALT_PILLAR = 0x4E50;      // 'NP' — basalt pillar columns
    private static final int SALT_WART = 0x4E57;        // 'NW' — wart patch cells
    private static final int SALT_WART_DROP = 0x4E58;   // 'NX' — per-column bulb dropouts
    private static final int SALT_FIRE = 0x4E42;        // 'NB' — fire patch cells
    private static final int SALT_FIRE_DROP = 0x4E45;   // 'NE' — per-column fire dropouts

    /** Glowstone growth mounds: one candidate per 20×20 cell, ~12 % of cells selected. */
    private static final int GROWTH_CELL = 20;
    private static final double GROWTH_CELL_CHANCE = 0.12D;
    /** Magma seams: short axis runs, one candidate per 16×16 cell, ~20 % selected. */
    private static final int SEAM_CELL = 16;
    private static final double SEAM_CELL_CHANCE = 0.20D;
    /** Basalt pillars: straight per-column roll (~1 pillar per ~11×11 delta ground). */
    private static final double PILLAR_CHANCE = 0.008D;
    /** Wart patches: one candidate per 18×18 crimson/warped cell, ~16 % selected. */
    private static final int WART_CELL = 18;
    private static final double WART_CELL_CHANCE = 0.16D;
    /** Fire patches: 12×12 soul-valley cells, ~18 % selected, ragged per-column fill. */
    private static final int FIRE_CELL = 12;
    private static final double FIRE_CELL_CHANCE = 0.18D;
    private static final double FIRE_COLUMN_CHANCE = 0.30D;
    /** Extra clearance past a landmark's own radius that stays undressed. */
    private static final int LANDMARK_PAD = 8;

    private static final BlockState GLOWSTONE = Blocks.GLOWSTONE.defaultBlockState();
    private static final BlockState MAGMA = Blocks.MAGMA_BLOCK.defaultBlockState();
    private static final BlockState BASALT = Blocks.BASALT.defaultBlockState();
    private static final BlockState BONE = Blocks.BONE_BLOCK.defaultBlockState();

    private NetherFloorDecor() {}

    @EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
    public static final class Setup {
        private Setup() {}

        @SubscribeEvent
        static void onCommonSetup(FMLCommonSetupEvent event) {
            event.enqueueWork(() -> {
                if (REGISTERED.compareAndSet(false, true)) {
                    DiscGenPipeline.registerExtraDecor(
                            DiscProfile.NETHER, NetherFloorDecor::decorate);
                    EclipseMod.LOGGER.info("Registered deterministic nether floor dressing");
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
                switch (map.biomeAt(DiscProfile.NETHER, x, z)) {
                    case "minecraft:nether_wastes" ->
                            decorateWastes(map, chunk, cursor, x, z, stage);
                    case "minecraft:basalt_deltas" ->
                            decorateBasalt(map, chunk, cursor, x, z, stage);
                    case "minecraft:soul_sand_valley" ->
                            decorateSoul(map, chunk, cursor, x, z, stage);
                    case "minecraft:crimson_forest" -> decorateWarts(map, chunk, cursor,
                            x, z, stage, Blocks.NETHER_WART_BLOCK.defaultBlockState());
                    case "minecraft:warped_forest" -> decorateWarts(map, chunk, cursor,
                            x, z, stage, Blocks.WARPED_WART_BLOCK.defaultBlockState());
                    default -> { }
                }
            }
        }
    }

    /**
     * Wastes: glowstone growth mounds (a 2–3 high center stack, cardinal arms, hashed
     * diagonal crumbs — the ceiling chandelier layout mirrored onto the floor) and
     * short magma seams (3–7-block axis runs whose TOP block flips to magma, reading
     * as glowing ground cracks).
     */
    private static void decorateWastes(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage) {
        int cellX = Math.floorDiv(x, GROWTH_CELL);
        int cellZ = Math.floorDiv(z, GROWTH_CELL);
        long h = hash(SALT_GROWTH, cellX, cellZ);
        if (to01(h) < GROWTH_CELL_CHANCE) {
            int span = GROWTH_CELL - 4;
            int centerX = cellX * GROWTH_CELL + 2 + (int) ((h >>> 8) & 0x7FFFFFFFL) % span;
            int centerZ = cellZ * GROWTH_CELL + 2 + (int) ((h >>> 32) & 0x7FFFFFFFL) % span;
            int dx = x - centerX;
            int dz = z - centerZ;
            if (Math.abs(dx) <= 1 && Math.abs(dz) <= 1) {
                DiscColumn col = floor(map, x, z, stage);
                if (col != null) {
                    int surface = col.surfaceY();
                    if (dx == 0 && dz == 0) {
                        int height = 2 + (int) ((h >>> 16) & 1L);           // 2..3
                        for (int i = 1; i <= height; i++) {
                            setIfAir(chunk, cursor.set(x, surface + i, z), GLOWSTONE);
                        }
                    } else if (Math.abs(dx) + Math.abs(dz) == 1) {
                        setIfAir(chunk, cursor.set(x, surface + 1, z), GLOWSTONE);
                    } else if (((h >>> (40 + (dx > 0 ? 1 : 0) + (dz > 0 ? 2 : 0))) & 1L) != 0L) {
                        setIfAir(chunk, cursor.set(x, surface + 1, z), GLOWSTONE);
                    }
                }
            }
        }

        int seamCellX = Math.floorDiv(x, SEAM_CELL);
        int seamCellZ = Math.floorDiv(z, SEAM_CELL);
        long s = hash(SALT_SEAM, seamCellX, seamCellZ);
        if (to01(s) >= SEAM_CELL_CHANCE) {
            return;
        }
        int span = SEAM_CELL - 8;
        int centerX = seamCellX * SEAM_CELL + 4 + (int) ((s >>> 8) & 0x7FFFFFFFL) % span;
        int centerZ = seamCellZ * SEAM_CELL + 4 + (int) ((s >>> 32) & 0x7FFFFFFFL) % span;
        int halfLen = 1 + (int) ((s >>> 16) % 3L);                          // run 3..7
        boolean alongX = ((s >>> 24) & 1L) == 0L;
        boolean onSeam = alongX
                ? z == centerZ && Math.abs(x - centerX) <= halfLen
                : x == centerX && Math.abs(z - centerZ) <= halfLen;
        if (!onSeam) {
            return;
        }
        DiscColumn col = floor(map, x, z, stage);
        if (col == null) {
            return;
        }
        BlockPos top = cursor.set(x, col.surfaceY(), z);
        if (!chunk.getBlockState(top).isAir()) {
            chunk.setBlockState(top, MAGMA, false);
        }
    }

    /** Basalt deltas: scattered natural basalt pillars, 3–8 blocks high. */
    private static void decorateBasalt(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage) {
        long h = hash(SALT_PILLAR, x, z);
        if (to01(h) >= PILLAR_CHANCE) {
            return;
        }
        DiscColumn col = floor(map, x, z, stage);
        if (col == null) {
            return;
        }
        int height = 3 + (int) ((h >>> 8) % 6L);                            // 3..8
        int surface = col.surfaceY();
        for (int i = 1; i <= height; i++) {
            BlockPos pos = cursor.set(x, surface + i, z);
            if (!chunk.getBlockState(pos).isAir()) {
                break; // never punch into overhangs or the roof needles
            }
            chunk.setBlockState(pos, BASALT, false);
        }
    }

    /**
     * Crimson/warped: wart-bulb patches (r ≈ 2.8, ragged via per-column dropouts) —
     * about one patch in four carries an arched bone-block rib through its center
     * (heights 3-2-1 along one axis), the buried-beast skeleton look.
     */
    private static void decorateWarts(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage, BlockState wart) {
        int cellX = Math.floorDiv(x, WART_CELL);
        int cellZ = Math.floorDiv(z, WART_CELL);
        long h = hash(SALT_WART, cellX, cellZ);
        if (to01(h) >= WART_CELL_CHANCE) {
            return;
        }
        int span = WART_CELL - 8;
        int centerX = cellX * WART_CELL + 4 + (int) ((h >>> 8) & 0x7FFFFFFFL) % span;
        int centerZ = cellZ * WART_CELL + 4 + (int) ((h >>> 32) & 0x7FFFFFFFL) % span;
        int dx = x - centerX;
        int dz = z - centerZ;
        if (dx * dx + dz * dz > 8) {
            return;
        }
        DiscColumn col = floor(map, x, z, stage);
        if (col == null) {
            return;
        }
        int surface = col.surfaceY();
        boolean rib = ((h >>> 60) & 3L) == 0L;
        boolean ribAlongX = ((h >>> 58) & 1L) == 0L;
        int ribOffset = ribAlongX ? dx : dz;
        int ribSide = ribAlongX ? dz : dx;
        if (rib && ribSide == 0 && Math.abs(ribOffset) <= 2) {
            int top = 3 - Math.abs(ribOffset);
            for (int i = 1; i <= top; i++) {
                setIfAir(chunk, cursor.set(x, surface + i, z), BONE);
            }
            return;
        }
        if (to01(hash(SALT_WART_DROP, x, z)) < 0.65D) {
            setIfAir(chunk, cursor.set(x, surface + 1, z), wart);
        }
    }

    /**
     * Soul valleys: fire patches — soul fire on soul sand/soil, regular (eternal) fire
     * on netherrack transition ground, nothing on anything else.
     */
    private static void decorateSoul(DiscMapData map, ChunkAccess chunk,
            BlockPos.MutableBlockPos cursor, int x, int z, int stage) {
        long h = hash(SALT_FIRE, Math.floorDiv(x, FIRE_CELL), Math.floorDiv(z, FIRE_CELL));
        if (to01(h) >= FIRE_CELL_CHANCE
                || to01(hash(SALT_FIRE_DROP, x, z)) >= FIRE_COLUMN_CHANCE) {
            return;
        }
        DiscColumn col = floor(map, x, z, stage);
        if (col == null) {
            return;
        }
        int surface = col.surfaceY();
        BlockState ground = chunk.getBlockState(cursor.set(x, surface, z));
        BlockState fire = null;
        if (ground.is(Blocks.SOUL_SAND) || ground.is(Blocks.SOUL_SOIL)) {
            fire = Blocks.SOUL_FIRE.defaultBlockState();
        } else if (ground.is(Blocks.NETHERRACK)) {
            fire = Blocks.FIRE.defaultBlockState();
        }
        if (fire != null) {
            setIfAir(chunk, cursor.set(x, surface + 1, z), fire);
        }
    }

    /**
     * Column probe + shared guards: only dressed columns are inside the disc, not on a
     * magma lip or seam-curtain bowl, not under a lava fill (moat channel, spring-pit
     * pool, splash bowl) and off every landmark pad.
     */
    private static DiscColumn floor(DiscMapData map, int x, int z, int stage) {
        DiscColumn col = DiscTerrainFunction.column(DiscProfile.NETHER, x, z, stage);
        if (!col.inside() || col.moatLip() || col.seamCurtain() != 0
                || col.lavaTopY() >= col.surfaceY() || nearLandmark(map, x, z)) {
            return null;
        }
        return col;
    }

    /** Whether (x, z) sits on a landmark pad (radius + {@value #LANDMARK_PAD}). */
    private static boolean nearLandmark(DiscMapData map, int x, int z) {
        for (DiscMapData.Landmark landmark : map.landmarks(DiscProfile.NETHER)) {
            double reach = landmark.radius() + LANDMARK_PAD;
            double dx = x - landmark.x();
            double dz = z - landmark.z();
            if (dx * dx + dz * dz <= reach * reach) {
                return true;
            }
        }
        return false;
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
