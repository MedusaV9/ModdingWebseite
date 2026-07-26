package dev.projecteclipse.eclipse.worldgen.structure;

import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.BoundingBox;

/**
 * FIX-FLOAT — the two halves of "a stamped structure must never hang in the air", shared
 * by every {@link SitePrep.Mode#PLATEAU} site (the outpost bug was only the loudest case):
 *
 * <ol>
 *   <li><b>Seat sampling</b> ({@link #seatY}) — the plateau height is no longer read from
 *       the anchor's single column. A structure covers tens of columns and the disc's
 *       deterministic ground rolls under all of them; seating on one sample floats the
 *       build wherever that sample happened to be a local high point. The seat is the
 *       MINIMUM of a grid sampled over the whole piece footprint, so no part of the
 *       build can end up above its own ground. A single river notch or crumble hole
 *       under one corner must not sink the whole site, so the minimum is floored at
 *       {@code median - }{@value #MAX_SEAT_DROP} blocks — the notch is then closed by
 *       the plateau fill instead.</li>
 *   <li><b>Foundation fill</b> ({@link #fillFoundations}) — after the pieces are pasted,
 *       every column whose lowest structure block still hovers over the prepared ground
 *       gets that gap packed with the column's own sector strata (sand in the desert,
 *       grass/dirt in the plains — exactly what vanilla's igloo/outpost "foundation"
 *       boxes do). Only gaps up to {@value #MAX_FOUNDATION_LIFT} blocks are packed, so
 *       a watchtower's overhanging deck or a village's raised walkway keeps its air
 *       underneath — this closes seams, it does not encase builds in a plinth.</li>
 * </ol>
 *
 * <p>Both halves are pure terrain work against the deterministic
 * {@link DiscTerrainFunction} ground, and the fill runs as a resumable
 * {@link BudgetedBlockWriter} cursor like the rest of {@link SitePrep} — a mansion-sized
 * footprint can never spike a single tick.</p>
 */
public final class StructureGrounding {
    /** Grid resolution of the footprint seat sample (plus the 4 corners and the center). */
    private static final int SEAT_SAMPLES_PER_AXIS = 5;
    /**
     * How far below the footprint's median ground the seat may be pulled by its minimum.
     * Guards against a single river/crumble column dragging a whole site into a pit.
     */
    private static final int MAX_SEAT_DROP = 8;
    /** Gap (blocks) between a structure column and the ground that still gets packed. */
    private static final int MAX_FOUNDATION_LIFT = 6;
    /** How far above the prepared ground the fill looks for the column's lowest block. */
    private static final int FOUNDATION_SCAN_HEIGHT = MAX_FOUNDATION_LIFT + 1;

    private StructureGrounding() {}

    // ------------------------------------------------------------------ seat sampling

    /**
     * The deterministic seat height of a footprint: the minimum sampled ground over
     * {@code [minX..maxX] × [minZ..maxZ]} (see the class doc for the median floor).
     * {@code fallbackY} is returned when the footprint has no column inside the disc.
     */
    public static int seatY(DiscProfile profile, int minX, int minZ, int maxX, int maxZ,
            int fallbackY) {
        int stage = WorldStageAccess.stage(profile);
        int[] samples = new int[(SEAT_SAMPLES_PER_AXIS + 1) * (SEAT_SAMPLES_PER_AXIS + 1)];
        int count = 0;
        for (int ix = 0; ix <= SEAT_SAMPLES_PER_AXIS; ix++) {
            int x = minX + (int) ((long) (maxX - minX) * ix / SEAT_SAMPLES_PER_AXIS);
            for (int iz = 0; iz <= SEAT_SAMPLES_PER_AXIS; iz++) {
                int z = minZ + (int) ((long) (maxZ - minZ) * iz / SEAT_SAMPLES_PER_AXIS);
                // Void columns outside the disc rim carry no ground: sampling them would
                // pin every rim-adjacent site to the world floor.
                if (!DiscTerrainFunction.column(profile, x, z, stage).inside()) {
                    continue;
                }
                samples[count++] = DiscTerrainFunction.surfaceY(profile, x, z);
            }
        }
        if (count == 0) {
            return fallbackY;
        }
        java.util.Arrays.sort(samples, 0, count);
        int min = samples[0];
        int median = samples[count / 2];
        return Math.max(min, median - MAX_SEAT_DROP);
    }

    /**
     * The first FREE block above the deterministic ground of a column — the exact value
     * {@code DiscChunkGenerator.getBaseHeight} (and therefore
     * {@code ChunkGenerator.getFirstFreeHeight}, which jigsaw assembly seats
     * terrain-matching pieces against) answers for {@code WORLD_SURFACE_WG}. Reading it
     * straight off {@link DiscTerrainFunction} lets a re-seat undo an assembly-time snap
     * exactly, without the world state that snap was taken from still being intact.
     */
    public static int assembledGroundLineY(DiscProfile profile, int x, int z, int fallbackY) {
        DiscColumn column = DiscTerrainFunction.column(profile, x, z, WorldStageAccess.stage(profile));
        return column.inside() ? column.topY() + 1 : fallbackY;
    }

    // ------------------------------------------------------------------ foundation fill

    /**
     * Packs the gap under every column of {@code placed} whose lowest structure block
     * hovers up to {@value #MAX_FOUNDATION_LIFT} blocks over {@code prepared}'s ground,
     * then runs {@code onComplete} on the server thread. Queued as a budgeted cursor;
     * failures are reported to {@code onFailure} and leave the site placed but unpacked.
     */
    public static void fillFoundations(ServerLevel level, DiscProfile profile,
            SitePrep.PreparedGround prepared, BoundingBox placed, Runnable onComplete,
            Consumer<Throwable> onFailure) {
        BudgetedBlockWriter.enqueue(level,
                new FoundationWork(level, profile, prepared, placed),
                onComplete, onFailure);
    }

    /** Resumable per-column foundation cursor: one probe or write is one budget operation. */
    private static final class FoundationWork implements BudgetedBlockWriter.BudgetedWork {
        private final ServerLevel level;
        private final DiscProfile profile;
        private final int stage;
        private final SitePrep.PreparedGround prepared;
        private final int minX;
        private final int minZ;
        private final int maxX;
        private final int maxZ;
        private final BlockPos.MutableBlockPos cursor = new BlockPos.MutableBlockPos();
        private int x;
        private int z;
        /** Prepared ground top of the current column, and the fill cursor above it. */
        private int groundY;
        private int y;
        private BlockState filler;
        /** 0 = pick the column, 1 = find its lowest structure block, 2 = pack the gap. */
        private int phase;
        private int filled;

        private FoundationWork(ServerLevel level, DiscProfile profile,
                SitePrep.PreparedGround prepared, BoundingBox placed) {
            this.level = level;
            this.profile = profile;
            this.stage = WorldStageAccess.stage(profile);
            this.prepared = prepared;
            this.minX = placed.minX();
            this.minZ = placed.minZ();
            this.maxX = placed.maxX();
            this.maxZ = placed.maxZ();
            this.x = this.minX;
            this.z = this.minZ;
        }

        @Override
        public boolean run(int operationBudget) {
            int remaining = operationBudget;
            while (remaining > 0 && this.x <= this.maxX) {
                if (this.phase == 0) {
                    DiscColumn column = DiscTerrainFunction.column(this.profile, this.x, this.z, this.stage);
                    remaining--;
                    if (!column.inside()) {
                        advanceColumn();
                        continue;
                    }
                    this.groundY = this.prepared.groundY(this.x, this.z);
                    this.filler = fillerBlockOf(column);
                    this.y = this.groundY + 1;
                    this.phase = 1;
                    continue;
                }
                if (this.phase == 1) {
                    // Walk up from the ground to the structure's lowest block in this
                    // column. A solid block right on the ground means the column is
                    // already seated; empty air all the way means no structure here.
                    if (this.y > this.groundY + FOUNDATION_SCAN_HEIGHT) {
                        advanceColumn();
                        continue;
                    }
                    this.cursor.set(this.x, this.y, this.z);
                    if (isSeatable(this.level, this.level.getBlockState(this.cursor), this.cursor)) {
                        this.y--; // pack downward from just under the structure
                        this.phase = 2;
                        continue;
                    }
                    this.y++;
                    remaining--;
                    continue;
                }
                if (this.y <= this.groundY) {
                    advanceColumn();
                    continue;
                }
                this.cursor.set(this.x, this.y, this.z);
                BlockState state = this.level.getBlockState(this.cursor);
                if (state.isSolidRender(this.level, this.cursor)) {
                    advanceColumn(); // met solid ground (or a lower piece): the seam is closed
                    continue;
                }
                this.level.setBlock(this.cursor, this.filler,
                        Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
                this.filled++;
                this.y--;
                remaining--;
            }
            if (this.x > this.maxX) {
                if (this.filled > 0) {
                    EclipseMod.LOGGER.info("StructureGrounding: packed {} foundation block(s) under [{}..{} x {}..{}]",
                            this.filled, this.minX, this.maxX, this.minZ, this.maxZ);
                }
                return true;
            }
            return false;
        }

        private void advanceColumn() {
            this.phase = 0;
            if (++this.z > this.maxZ) {
                this.z = this.minZ;
                this.x++;
            }
        }
    }

    /**
     * Whether a block counts as the load-bearing bottom of a structure column. Only full
     * solid masonry seats a foundation — a fence post, a torch or the crop of a village
     * farm must not grow a pillar under itself.
     */
    private static boolean isSeatable(ServerLevel level, BlockState state, BlockPos pos) {
        return !state.isAir() && state.getFluidState().isEmpty() && !SitePrep.isVegetation(state)
                && state.isSolidRender(level, pos);
    }

    /** The column's own sub-surface strata block (mirrors {@code SitePrep.fillerBlockOf}). */
    private static BlockState fillerBlockOf(DiscColumn column) {
        BlockState state = DiscTerrainFunction.stateInColumn(column, column.surfaceY() - 2);
        return state.isAir() || !state.getFluidState().isEmpty()
                ? Blocks.DIRT.defaultBlockState() : state;
    }
}
