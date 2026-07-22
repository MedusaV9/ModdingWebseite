package dev.projecteclipse.eclipse.limbo;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;

/**
 * Procedurally builds the dark-oak ghost ship floating on the Limbo ocean, plus a small
 * spawn platform, the first time the Limbo level is available (guarded by
 * {@link EclipseWorldState#isGhostShipBuilt()}). Pure block loops, no NBT structure file.
 *
 * <p>The ship is ~39 blocks long (X), ~9 wide (Z) and ~14 tall, centered horizontally on
 * (0, 0). Vertically it is anchored to the actual water surface of the flat Limbo
 * generator (top water block, y=48 with the shipped datapack); if no water is found the
 * nominal spec center (0, 64, 0) is used so the builder never fails.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class GhostShipBuilder {
    /** Nominal ship center from the event spec, used as fallback when no water surface is found. */
    public static final BlockPos NOMINAL_CENTER = new BlockPos(0, 64, 0);

    /** Half length along X (bow at +X, stern at -X). Total length = 2*19 + 1 = 39. */
    public static final int HALF_LENGTH = 19;
    /** Maximum half width along Z (midship). Total width = 2*4 + 1 = 9. */
    public static final int HALF_WIDTH = 4;
    /** X offsets of the two masts. */
    public static final int[] MAST_X = {-8, 8};

    private GhostShipBuilder() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        ServerLevel limbo = event.getServer().getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            EclipseMod.LOGGER.warn("Limbo dimension {} is not loaded; ghost ship not built", LimboDimension.LIMBO.location());
            return;
        }
        buildIfNeeded(limbo);
        OarAnimator.ensureOars(limbo);
    }

    /** Column sampled for the water surface; far away from every block the builder places. */
    private static final int WATER_SAMPLE_X = 256;
    private static final int WATER_SAMPLE_Z = 256;

    /** Builds the ship once; subsequent calls are no-ops thanks to the world-state flag. */
    public static void buildIfNeeded(ServerLevel limbo) {
        EclipseWorldState state = EclipseWorldState.get(limbo.getServer());
        if (state.isGhostShipBuilt()) {
            return;
        }
        int waterline = build(limbo);
        state.setGhostShipBuilt(true);
        EclipseMod.LOGGER.info("Ghost ship built in {} at waterline y={} around x=0, z=0",
                LimboDimension.LIMBO.location(), waterline);
    }

    /**
     * The Y of the top water block of the Limbo ocean (48 with the shipped datapack), or
     * {@code NOMINAL_CENTER.getY() - 1} if the sampled column contains no water (e.g. the
     * dimension JSON was changed). Sampled far away from the ship so the result is stable
     * before and after the build.
     */
    public static int waterlineY(ServerLevel limbo) {
        // Query the chunk directly: Level.getHeight consults hasChunk(), which can still be
        // false for freshly force-loaded chunks during server start.
        ChunkAccess chunk = limbo.getChunk(WATER_SAMPLE_X >> 4, WATER_SAMPLE_Z >> 4);
        int topY = chunk.getHeight(Heightmap.Types.WORLD_SURFACE, WATER_SAMPLE_X, WATER_SAMPLE_Z); // top non-air block
        BlockPos top = new BlockPos(WATER_SAMPLE_X, topY, WATER_SAMPLE_Z);
        if (topY > limbo.getMinBuildHeight() && chunk.getBlockState(top).is(Blocks.WATER)) {
            return topY;
        }
        return NOMINAL_CENTER.getY() - 1;
    }

    /** Unconditionally builds the ship and spawn platform; returns the waterline Y used. Idempotent block-wise. */
    public static int build(ServerLevel limbo) {
        int waterline = waterlineY(limbo);
        int keelY = waterline - 2;          // hull bottom, 2 blocks of draft
        int deckY = waterline + 3;
        int railY = deckY + 1;

        BlockState planks = Blocks.DARK_OAK_PLANKS.defaultBlockState();
        BlockState log = Blocks.DARK_OAK_LOG.defaultBlockState();
        BlockState fence = Blocks.DARK_OAK_FENCE.defaultBlockState();
        BlockState wool = Blocks.BLACK_WOOL.defaultBlockState();
        BlockState air = Blocks.AIR.defaultBlockState();

        // Hull: keel floor, side walls, hollow (air) interior, solid deck.
        for (int dx = -HALF_LENGTH; dx <= HALF_LENGTH; dx++) {
            int hw = halfWidthAt(dx);
            boolean endCap = Math.abs(dx) == HALF_LENGTH;
            for (int dz = -hw; dz <= hw; dz++) {
                set(limbo, dx, keelY, dz, planks);
                for (int y = keelY + 1; y < deckY; y++) {
                    boolean isWall = dz == -hw || dz == hw || endCap;
                    set(limbo, dx, y, dz, isWall ? planks : air);
                }
                set(limbo, dx, deckY, dz, planks);
            }
            // Railing along the deck edge.
            set(limbo, dx, railY, -hw, fence);
            set(limbo, dx, railY, hw, fence);
            if (endCap) {
                for (int dz = -hw + 1; dz <= hw - 1; dz++) {
                    set(limbo, dx, railY, dz, fence);
                }
            }
        }

        // Two masts with square black-wool sails.
        for (int mastX : MAST_X) {
            for (int y = deckY + 1; y <= deckY + 9; y++) {
                set(limbo, mastX, y, 0, log);
            }
            for (int y = deckY + 3; y <= deckY + 8; y++) {
                for (int dz = -3; dz <= 3; dz++) {
                    if (dz != 0) {
                        set(limbo, mastX, y, dz, wool);
                    }
                }
            }
        }

        // Small spawn platform off the starboard side, with a walkway to the ship.
        for (int dx = -2; dx <= 2; dx++) {
            for (int dz = 10; dz <= 14; dz++) {
                set(limbo, dx, deckY, dz, planks);
            }
        }
        for (int dz = HALF_WIDTH + 1; dz <= 9; dz++) {
            for (int dx = -1; dx <= 1; dx++) {
                set(limbo, dx, deckY, dz, planks);
            }
        }
        return waterline;
    }

    /**
     * Feet-level arrival position in the middle of the spawn platform (see {@link #build}),
     * one block above the deck. Banned ghosts ({@code BanService}) and {@code /eclipse tp_limbo}
     * land here — NOT at the shared world spawn, which sits far from the ship over open
     * (drownable) ocean.
     */
    public static BlockPos platformArrivalPos(ServerLevel limbo) {
        return new BlockPos(0, waterlineY(limbo) + 4, 12);
    }

    /** Hull half width at the given X offset; tapers towards bow and stern. */
    public static int halfWidthAt(int dx) {
        int d = Math.abs(dx);
        if (d <= 12) {
            return HALF_WIDTH;
        }
        if (d <= 15) {
            return 3;
        }
        if (d <= 17) {
            return 2;
        }
        return 1;
    }

    private static void set(ServerLevel level, int x, int y, int z, BlockState state) {
        level.setBlock(new BlockPos(x, y, z), state, Block.UPDATE_ALL);
    }
}
