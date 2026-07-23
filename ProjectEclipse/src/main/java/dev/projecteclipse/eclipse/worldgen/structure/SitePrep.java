package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.tags.BlockTags;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.BushBlock;
import net.minecraft.world.level.block.LadderBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.core.Direction;

/**
 * Ground preparation for stamped structures (design D7 — fixes complaint #6 "structures on
 * trees"). Runtime stamping happens AFTER vanilla decoration exists, so a naive placement
 * snaps pieces to {@code WORLD_SURFACE}-style heightmaps that count logs/leaves — pieces
 * end up on canopies. {@code SitePrep} terraforms the site FIRST, against the
 * deterministic {@link DiscTerrainFunction#surfaceY} ground (a "heightmap" that by
 * construction ignores all vegetation), then re-primes the real heightmaps so the pieces
 * that self-snap at placement time ({@code ScatteredFeaturePiece}, village street logic)
 * read tree-free ground.
 *
 * <p>Two modes ({@link Mode}, compile seam §3.10):</p>
 * <ul>
 *   <li>{@link Mode#PLATEAU} — surface sites: (1) vegetation cleared column-wise over the
 *       footprint + skirt (logs/leaves/plants/snow, incl. overhanging canopies), (2) a
 *       plateau terraformed at the anchor's deterministic surface Y — terrain above is cut
 *       to air, dips below are raised with the column's own sector strata (sand in the
 *       desert, grass in the plains) — with a smoothstep skirt over
 *       {@value #SKIRT_WIDTH} blocks so the plateau reads as a natural shelf,</li>
 *   <li>{@link Mode#CAVITY} — underground sites (trial chambers, ancient city): a clean
 *       interior envelope is carved around the piece bounds, a floor pad laid, and a
 *       ladder entrance shaft raised to the surface (collared) so the site is reachable.</li>
 * </ul>
 *
 * <p>After piece placement the caller runs {@link #finish}: every touched chunk gets its
 * four decoration heightmaps re-primed and is handed to
 * {@link BudgetedBlockWriter#relightAndResend} (light rebuild + resend through the
 * existing budgeted queues — the same machinery the ring sweep uses, so big sites do not
 * spike a single tick with light math).</p>
 */
public final class SitePrep {
    /** Terraform modes (compile seam §3.10 — do not rename). */
    public enum Mode { PLATEAU, CAVITY }

    /** Extra blocks of prepared ground around the piece bounding box (design D7). */
    public static final int MARGIN = 6;
    /** Width in blocks of the smoothstep skirt blending plateau → natural terrain. */
    public static final int SKIRT_WIDTH = 12;
    /** How deep below the plateau dips are foundation-filled with sector strata. */
    private static final int FILL_DEPTH = 24;
    /** Canopy sweep height: leaves/logs are cleared this far above the target ground. */
    private static final int CANOPY_CLEAR = 32;
    /** Interior padding of a carved cavity envelope around the piece bounds. */
    private static final int CAVITY_PAD = 3;

    /** Heightmaps re-primed after terraform + placement (same set the ring sweep re-primes). */
    private static final Set<Heightmap.Types> HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR, Heightmap.Types.WORLD_SURFACE);

    private SitePrep() {}

    /**
     * The prepared ground of one site: {@link #groundY} is the terraformed target height
     * per column (the "prepared ground grid" placement refactors read instead of live
     * heightmaps), {@code touched} the chunk keys to finish. Pure lookups — safe to keep
     * across the placement call.
     */
    public static final class PreparedGround {
        private final ServerLevel level;
        private final DiscProfile profile;
        private final Mode mode;
        private final int minX;
        private final int minZ;
        private final int maxX;
        private final int maxZ;
        private final int plateauY;
        private final Set<Long> touched = new HashSet<>();
        private final List<ReadyCallback> callbacks = new ArrayList<>();
        private boolean ready;
        private Throwable failure;

        private record ReadyCallback(Runnable success, Consumer<Throwable> failure) {}

        private PreparedGround(ServerLevel level, DiscProfile profile, Mode mode,
                int minX, int minZ, int maxX, int maxZ, int plateauY) {
            this.level = level;
            this.profile = profile;
            this.mode = mode;
            this.minX = minX;
            this.minZ = minZ;
            this.maxX = maxX;
            this.maxZ = maxZ;
            this.plateauY = plateauY;
        }

        public Mode mode() {
            return this.mode;
        }

        /** The plateau height (PLATEAU) / envelope floor (CAVITY) at the anchor. */
        public int plateauY() {
            return this.plateauY;
        }

        /**
         * Terraformed ground Y of the column: the plateau inside the footprint, the
         * smoothstep-blended height in the skirt, natural deterministic ground outside.
         */
        public int groundY(int x, int z) {
            if (this.mode == Mode.CAVITY) {
                return DiscTerrainFunction.surfaceY(this.profile, x, z);
            }
            return targetY(this.profile, this.minX, this.minZ, this.maxX, this.maxZ, this.plateauY, x, z);
        }

        void touch(int blockX, int blockZ) {
            this.touched.add(ChunkPos.asLong(blockX >> 4, blockZ >> 4));
        }

        /**
         * Runs {@code success} once the tick-budgeted preparation is complete, or
         * {@code onFailure} if its resumable worker failed. Callbacks run on the server
         * thread and may safely place the structure.
         */
        public void whenReady(Runnable success, Consumer<Throwable> onFailure) {
            if (this.ready) {
                success.run();
            } else if (this.failure != null) {
                onFailure.accept(this.failure);
            } else {
                this.callbacks.add(new ReadyCallback(success, onFailure));
            }
        }

        private void complete() {
            this.ready = true;
            for (ReadyCallback callback : List.copyOf(this.callbacks)) {
                try {
                    callback.success().run();
                } catch (Throwable error) {
                    callback.failure().accept(error);
                }
            }
            this.callbacks.clear();
        }

        private void fail(Throwable error) {
            this.failure = error;
            for (ReadyCallback callback : List.copyOf(this.callbacks)) {
                callback.failure().accept(error);
            }
            this.callbacks.clear();
        }
    }

    // --- PLATEAU ---

    /**
     * Clears vegetation and terraforms a plateau for the given piece bounds (both expanded
     * by {@value #MARGIN} + {@value #SKIRT_WIDTH}), targeting {@code anchor.getY()} as the
     * plateau height. Work is queued in bounded resumable slices; register the placement
     * continuation with {@link PreparedGround#whenReady}. Heightmaps are re-primed before
     * that callback so ground-snapping pieces read the prepared ground.
     *
     * @param boundsMinX/... the XZ bounding box of the structure pieces (world coords)
     */
    public static PreparedGround preparePlateau(ServerLevel level, DiscProfile profile,
            int boundsMinX, int boundsMinZ, int boundsMaxX, int boundsMaxZ, BlockPos anchor) {
        int stage = WorldStageAccess.stage(profile);
        int minX = boundsMinX - MARGIN;
        int minZ = boundsMinZ - MARGIN;
        int maxX = boundsMaxX + MARGIN;
        int maxZ = boundsMaxZ + MARGIN;
        int plateauY = anchor.getY();
        PreparedGround prepared = new PreparedGround(level, profile, Mode.PLATEAU,
                minX, minZ, maxX, maxZ, plateauY);
        BudgetedBlockWriter.enqueue(level,
                new PlateauWork(level, profile, stage, prepared),
                () -> {
                    primeTouched(level, prepared);
                    EclipseMod.LOGGER.info(
                            "SitePrep: plateau y={} prepared for [{}..{} x {}..{}] (+skirt {}), {} chunk(s)",
                            plateauY, minX, maxX, minZ, maxZ, SKIRT_WIDTH, prepared.touched.size());
                    prepared.complete();
                },
                prepared::fail);
        return prepared;
    }

    /** Resumable plateau cursor: one vertical block probe/write is one budget operation. */
    private static final class PlateauWork implements BudgetedBlockWriter.BudgetedWork {
        private final ServerLevel level;
        private final DiscProfile profile;
        private final int stage;
        private final PreparedGround prepared;
        private final int outerMinX;
        private final int outerMinZ;
        private final int outerMaxX;
        private final int outerMaxZ;
        private final BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        private int x;
        private int z;
        private int target;
        private int y;
        private int phase;
        private DiscColumn column;
        private BlockState top;
        private BlockState filler;

        private PlateauWork(ServerLevel level, DiscProfile profile, int stage, PreparedGround prepared) {
            this.level = level;
            this.profile = profile;
            this.stage = stage;
            this.prepared = prepared;
            this.outerMinX = prepared.minX - SKIRT_WIDTH;
            this.outerMinZ = prepared.minZ - SKIRT_WIDTH;
            this.outerMaxX = prepared.maxX + SKIRT_WIDTH;
            this.outerMaxZ = prepared.maxZ + SKIRT_WIDTH;
            this.x = this.outerMinX;
            this.z = this.outerMinZ;
        }

        @Override
        public boolean run(int operationBudget) {
            int remaining = operationBudget;
            while (remaining > 0 && this.x <= this.outerMaxX) {
                if (this.phase == 0) {
                    this.column = DiscTerrainFunction.column(this.profile, this.x, this.z, this.stage);
                    if (!this.column.inside()) {
                        advanceColumn();
                        continue;
                    }
                    ensureChunk(this.level, this.prepared, this.x, this.z);
                    this.target = targetY(this.profile, this.prepared.minX, this.prepared.minZ,
                            this.prepared.maxX, this.prepared.maxZ, this.prepared.plateauY,
                            this.x, this.z);
                    int worldTop = this.level.getHeight(Heightmap.Types.WORLD_SURFACE, this.x, this.z) + 1;
                    this.y = Math.max(worldTop, this.target + CANOPY_CLEAR);
                    this.phase = 1;
                }
                if (this.phase == 1) {
                    if (this.y <= this.target) {
                        this.top = surfaceBlockOf(this.column);
                        this.filler = fillerBlockOf(this.column);
                        this.y = this.target;
                        this.phase = 2;
                        continue;
                    }
                    this.cursor.set(this.x, this.y, this.z);
                    BlockState state = this.level.getBlockState(this.cursor);
                    if (!state.isAir() && (this.y <= this.target + CANOPY_CLEAR || isVegetation(state))) {
                        setSilent(this.level, this.cursor, Blocks.AIR.defaultBlockState());
                    }
                    this.y--;
                    remaining--;
                    continue;
                }
                this.cursor.set(this.x, this.y, this.z);
                BlockState state = this.level.getBlockState(this.cursor);
                boolean solid = state.isSolidRender(this.level, this.cursor);
                if (this.y == this.target) {
                    if (!solid || !state.equals(this.top)) {
                        setSilent(this.level, this.cursor, this.top);
                    }
                } else if (!solid) {
                    setSilent(this.level, this.cursor, this.filler);
                } else if (this.y < this.target - 1) {
                    advanceColumn();
                    remaining--;
                    continue;
                }
                this.y--;
                remaining--;
                if (this.y < this.target - FILL_DEPTH) {
                    advanceColumn();
                }
            }
            return this.x > this.outerMaxX;
        }

        private void advanceColumn() {
            this.phase = 0;
            this.column = null;
            if (++this.z > this.outerMaxZ) {
                this.z = this.outerMinZ;
                this.x++;
            }
        }
    }

    // --- CAVITY ---

    /**
     * Carves a clean interior envelope ({@value #CAVITY_PAD}-block pad around the piece
     * bounds), lays a floor pad below it and raises a collared ladder shaft to the surface
     * so the underground site (trial chambers, ancient city, vaults) is reachable. Work
     * is queued in bounded resumable slices; place pieces from
     * {@link PreparedGround#whenReady}.
     */
    public static PreparedGround prepareCavity(ServerLevel level, DiscProfile profile,
            int boundsMinX, int boundsMinY, int boundsMinZ,
            int boundsMaxX, int boundsMaxY, int boundsMaxZ, BlockPos anchor) {
        int stage = WorldStageAccess.stage(profile);
        int minX = boundsMinX - CAVITY_PAD;
        int minZ = boundsMinZ - CAVITY_PAD;
        int maxX = boundsMaxX + CAVITY_PAD;
        int maxZ = boundsMaxZ + CAVITY_PAD;
        int minY = Math.max(boundsMinY - 1, profile.minY() + 12);
        int surfaceGuard = DiscTerrainFunction.surfaceY(profile, anchor.getX(), anchor.getZ()) - 10;
        int maxY = Math.min(boundsMaxY + CAVITY_PAD, surfaceGuard);
        PreparedGround prepared = new PreparedGround(level, profile, Mode.CAVITY,
                minX, minZ, maxX, maxZ, minY);
        BudgetedBlockWriter.enqueue(level,
                new CavityWork(level, profile, stage, prepared, minY, maxY),
                () -> {
                    primeTouched(level, prepared);
                    EclipseMod.LOGGER.info(
                            "SitePrep: cavity envelope carved [{}..{} x {}..{}] y {}..{} + entrance shaft, {} chunk(s)",
                            minX, maxX, minZ, maxZ, minY, maxY, prepared.touched.size());
                    prepared.complete();
                },
                prepared::fail);
        return prepared;
    }

    /** Resumable cavity-envelope, entrance-shaft and collar cursor. */
    private static final class CavityWork implements BudgetedBlockWriter.BudgetedWork {
        private static final BlockState AIR = Blocks.CAVE_AIR.defaultBlockState();
        private static final BlockState WALL = Blocks.COBBLESTONE.defaultBlockState();
        private static final BlockState LADDER = Blocks.LADDER.defaultBlockState()
                .setValue(LadderBlock.FACING, Direction.NORTH);

        private final ServerLevel level;
        private final DiscProfile profile;
        private final int stage;
        private final PreparedGround prepared;
        private final int minY;
        private final int maxY;
        private final int shaftX;
        private final int shaftZ;
        private final int surface;
        private final BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        private int x;
        private int z;
        private int y;
        private int phase;
        private int shaftStep;
        private int collarIndex;
        private DiscColumn column;

        private CavityWork(ServerLevel level, DiscProfile profile, int stage,
                PreparedGround prepared, int minY, int maxY) {
            this.level = level;
            this.profile = profile;
            this.stage = stage;
            this.prepared = prepared;
            this.minY = minY;
            this.maxY = maxY;
            this.shaftX = prepared.minX + 2;
            this.shaftZ = prepared.minZ + 2;
            this.surface = DiscTerrainFunction.surfaceY(profile, this.shaftX, this.shaftZ);
            this.x = prepared.minX;
            this.z = prepared.minZ;
        }

        @Override
        public boolean run(int operationBudget) {
            int remaining = operationBudget;
            while (remaining > 0) {
                if (this.phase == 0) {
                    if (this.x > this.prepared.maxX) {
                        this.phase = this.surface > this.maxY ? 2 : 4;
                        this.y = this.minY;
                        continue;
                    }
                    this.column = DiscTerrainFunction.column(this.profile, this.x, this.z, this.stage);
                    if (!this.column.inside()) {
                        advanceColumn();
                        continue;
                    }
                    ensureChunk(this.level, this.prepared, this.x, this.z);
                    this.cursor.set(this.x, this.minY - 1, this.z);
                    if (!this.level.getBlockState(this.cursor).isSolidRender(this.level, this.cursor)) {
                        setSilent(this.level, this.cursor, padBlockOf(this.column, this.minY));
                    }
                    this.y = this.minY;
                    this.phase = 1;
                    remaining--;
                    continue;
                }
                if (this.phase == 1) {
                    if (this.y > this.maxY) {
                        advanceColumn();
                        continue;
                    }
                    this.cursor.set(this.x, this.y++, this.z);
                    if (!this.level.getBlockState(this.cursor).isAir()) {
                        setSilent(this.level, this.cursor, AIR);
                    }
                    remaining--;
                    continue;
                }
                if (this.phase == 2) {
                    if (this.y > this.surface + 1) {
                        this.phase = 3;
                        continue;
                    }
                    runShaftStep();
                    remaining--;
                    continue;
                }
                if (this.phase == 4) {
                    return true;
                }
                if (this.collarIndex >= 16) {
                    return true;
                }
                int dx = this.collarIndex / 4 - 1;
                int dz = this.collarIndex % 4 - 1;
                this.collarIndex++;
                boolean rim = dx == -1 || dx == 2 || dz == -1 || dz == 2;
                if (!rim || FallbackBuilders.hash01(
                        this.shaftX + dx, this.surface, this.shaftZ + dz) < 0.35D) {
                    continue;
                }
                ensureChunk(this.level, this.prepared, this.shaftX + dx, this.shaftZ + dz);
                this.cursor.set(this.shaftX + dx, this.surface + 1, this.shaftZ + dz);
                if (this.level.getBlockState(this.cursor).isAir()) {
                    setSilent(this.level, this.cursor, WALL);
                }
                remaining--;
            }
            return false;
        }

        private void runShaftStep() {
            if (this.shaftStep < 4) {
                int dx = this.shaftStep / 2;
                int dz = this.shaftStep % 2;
                ensureChunk(this.level, this.prepared, this.shaftX + dx, this.shaftZ + dz);
                this.cursor.set(this.shaftX + dx, this.y, this.shaftZ + dz);
                setSilent(this.level, this.cursor, AIR);
            } else if (this.shaftStep == 4) {
                ensureChunk(this.level, this.prepared, this.shaftX, this.shaftZ + 2);
                this.cursor.set(this.shaftX, this.y, this.shaftZ + 2);
                if (!this.level.getBlockState(this.cursor).isSolidRender(this.level, this.cursor)) {
                    setSilent(this.level, this.cursor, WALL);
                }
            } else {
                this.cursor.set(this.shaftX, this.y, this.shaftZ + 1);
                setSilent(this.level, this.cursor, LADDER);
            }
            if (++this.shaftStep >= 6) {
                this.shaftStep = 0;
                this.y++;
            }
        }

        private void advanceColumn() {
            this.phase = 0;
            this.column = null;
            if (++this.z > this.prepared.maxZ) {
                this.z = this.prepared.minZ;
                this.x++;
            }
        }
    }

    // --- finish ---

    /**
     * Post-placement pass: re-primes the heightmaps of every touched chunk (placement
     * changed them again) and hands each to {@link BudgetedBlockWriter#relightAndResend}
     * (budgeted light rebuild + resend). Call once AFTER {@code placeStart} / the
     * procedural builder ran.
     */
    public static void finish(ServerLevel level, PreparedGround prepared) {
        for (long chunkKey : prepared.touched) {
            LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(level,
                    ChunkPos.getX(chunkKey), ChunkPos.getZ(chunkKey));
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
            BudgetedBlockWriter.relightAndResend(level, chunk);
        }
    }

    /** Registers extra chunks touched by the placement itself (piece bounds). */
    public static void touchBounds(PreparedGround prepared, int minX, int minZ, int maxX, int maxZ) {
        for (int cx = minX >> 4; cx <= maxX >> 4; cx++) {
            for (int cz = minZ >> 4; cz <= maxZ >> 4; cz++) {
                prepared.touched.add(ChunkPos.asLong(cx, cz));
            }
        }
    }

    /**
     * Standalone finish for self-carving builders (dungeons, mineshafts) that skip the
     * terraform phase: re-primes heightmaps and relights/resends every chunk intersecting
     * the given XZ bounds. Same budgeted machinery as {@link #finish}.
     */
    public static void finishBounds(ServerLevel level, int minX, int minZ, int maxX, int maxZ) {
        for (int cx = minX >> 4; cx <= maxX >> 4; cx++) {
            for (int cz = minZ >> 4; cz <= maxZ >> 4; cz++) {
                LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(level, cx, cz);
                Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
                BudgetedBlockWriter.relightAndResend(level, chunk);
            }
        }
    }

    // --- shared helpers ---

    /** Smoothstep-blended target ground height of a column (plateau → natural surface). */
    private static int targetY(DiscProfile profile, int minX, int minZ, int maxX, int maxZ,
            int plateauY, int x, int z) {
        int dx = Math.max(0, Math.max(minX - x, x - maxX));
        int dz = Math.max(0, Math.max(minZ - z, z - maxZ));
        int d = Math.max(dx, dz);
        if (d <= 0) {
            return plateauY;
        }
        if (d >= SKIRT_WIDTH) {
            return DiscTerrainFunction.surfaceY(profile, x, z);
        }
        double t = d / (double) SKIRT_WIDTH;
        t = t * t * (3.0D - 2.0D * t); // smoothstep
        int natural = DiscTerrainFunction.surfaceY(profile, x, z);
        return (int) Math.round(plateauY + (natural - plateauY) * t);
    }

    /**
     * Whether a state is stamped-over vegetation/cover (never terrain): logs, leaves,
     * every plant, snow layers, cobwebs — the stuff that used to hold structures up in
     * the air (complaint #6).
     */
    static boolean isVegetation(BlockState state) {
        if (state.is(BlockTags.LEAVES) || state.is(BlockTags.LOGS) || state.is(BlockTags.SAPLINGS)
                || state.is(BlockTags.FLOWERS) || state.is(BlockTags.CROPS)) {
            return true;
        }
        if (state.getBlock() instanceof BushBlock) {
            return true;
        }
        return state.is(Blocks.SNOW) || state.is(Blocks.POWDER_SNOW) || state.is(Blocks.VINE)
                || state.is(Blocks.COBWEB) || state.is(Blocks.CACTUS) || state.is(Blocks.SUGAR_CANE)
                || state.is(Blocks.BAMBOO) || state.is(Blocks.BAMBOO_SAPLING) || state.is(Blocks.PUMPKIN)
                || state.is(Blocks.MELON) || state.is(Blocks.MOSS_CARPET) || state.is(Blocks.PINK_PETALS)
                || state.is(Blocks.BEE_NEST) || state.is(Blocks.MUSHROOM_STEM)
                || state.is(Blocks.RED_MUSHROOM_BLOCK) || state.is(Blocks.BROWN_MUSHROOM_BLOCK)
                || state.is(Blocks.HANGING_ROOTS) || state.is(Blocks.SPORE_BLOSSOM)
                || state.is(Blocks.BIG_DRIPLEAF) || state.is(Blocks.BIG_DRIPLEAF_STEM)
                || state.is(Blocks.SMALL_DRIPLEAF);
    }

    /** The column's own deterministic surface block (sector palette top). */
    private static BlockState surfaceBlockOf(DiscColumn column) {
        BlockState state = DiscTerrainFunction.stateInColumn(column, column.surfaceY());
        return state.isAir() || !state.getFluidState().isEmpty()
                ? Blocks.DIRT.defaultBlockState() : state;
    }

    /** The column's sub-surface strata block (sector palette filler). */
    private static BlockState fillerBlockOf(DiscColumn column) {
        BlockState state = DiscTerrainFunction.stateInColumn(column, column.surfaceY() - 2);
        return state.isAir() || !state.getFluidState().isEmpty()
                ? Blocks.DIRT.defaultBlockState() : state;
    }

    /** Cavity floor pad block matching the depth strata (deepslate below the transition). */
    private static BlockState padBlockOf(DiscColumn column, int floorY) {
        return floorY <= column.deepslateTopY()
                ? Blocks.DEEPSLATE.defaultBlockState() : Blocks.STONE.defaultBlockState();
    }

    /** Materializes + tickets the chunk of a column once and remembers it for finish(). */
    private static void ensureChunk(ServerLevel level, PreparedGround prepared, int x, int z) {
        long key = ChunkPos.asLong(x >> 4, z >> 4);
        if (prepared.touched.add(key)) {
            BudgetedBlockWriter.loadWithTicket(level, x >> 4, z >> 4);
        }
    }

    /** Silent write: clients see the result via the finish() relight/resend, not per-block. */
    private static void setSilent(ServerLevel level, BlockPos pos, BlockState state) {
        level.setBlock(pos, state, Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
    }

    /** Immediate heightmap re-prime of all touched chunks (pieces snap against these). */
    private static void primeTouched(ServerLevel level, PreparedGround prepared) {
        for (long chunkKey : prepared.touched) {
            LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(level,
                    ChunkPos.getX(chunkKey), ChunkPos.getZ(chunkKey));
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
        }
    }
}
