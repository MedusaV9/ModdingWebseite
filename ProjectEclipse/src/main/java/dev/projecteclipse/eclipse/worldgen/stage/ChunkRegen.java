package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Operator chunk-regeneration service behind {@code /dev chunk regen} (PLAN-B B16): rewrites
 * one loaded disc chunk (or a small square of them) column-by-column from
 * {@link DiscTerrainFunction} at the committed stage, replays the vanilla pipeline via
 * {@link DiscGenPipeline#runOnLiveChunk} (carve &rarr; decorate &rarr; seed animals), re-primes
 * the heightmaps and hands the chunk to {@link BudgetedBlockWriter#relightAndResend}. The
 * write loop deliberately mirrors {@code RingGrowthService.writeColumn}/{@code finishChunk}
 * (the sweep's internals are private, and B16 must not touch that file) — keep the two in
 * sync if the sweep's write contract ever changes.
 *
 * <p><b>Column set</b>: only columns whose {@link DiscColumn#inside()} is true are rewritten
 * (full 16-run section writes, so old decoration above/below the new solid span clears to
 * air); void columns beyond the rim stay untouched — never bulldoze player builds floating
 * past the disc. Block entities of rewritten columns are dropped before the replay
 * (replayed features re-create their own, e.g. monster-room spawners).</p>
 *
 * <p><b>Structure guard</b>: chunks intersecting a protection box — an authored landmark of
 * an already-stamped stage ({@link DiscMapData#landmarks}, same extents the ring sweep
 * honours) or a {@link StructurePendingRegistry} pending site — are refused unless the
 * caller passes {@code force} (the rewrite cannot re-assert unknown structure blocks, and
 * the replay would chew into the pieces). One job may run per disc profile; jobs are
 * refused while a ring-growth sweep runs in the same dimension. One chunk is in flight at
 * a time, its 256-column rewrite spread across ticks under the
 * {@value #WRITE_BUDGET_PER_TICK}-write budget (POL-S-04 — a deep-lens chunk alone is
 * ~57k section writes); finalization (replay, heightmaps, rescue, relight) runs at the
 * chunk boundary, so even a radius-2 job (25 chunks) never stalls the tick.</p>
 *
 * <p>Determinism: every rewrite is a pure function of frozen per-save data (map seed +
 * {@link DiscMapData} snapshot taken at job start) at the committed stage, byte-identical
 * to what fresh chunk generation would produce — same contract as the sweep.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ChunkRegen {
    /** Extra XZ pad (blocks) around a protected structure's extent (sweep parity). */
    private static final int STRUCTURE_PROTECTION_MARGIN = 8;
    /** Measured half-extent of a stamped village ({@code RingGrowthService} parity). */
    private static final int VILLAGE_PROTECTION_EXTENT = 64;
    /** Measured half-extent of the stamped temples ({@code RingGrowthService} parity). */
    private static final int TEMPLE_PROTECTION_EXTENT = 24;
    /** Maximum chunk radius (0 = 1 chunk, 2 = 5x5 = 25 chunks). */
    public static final int MAX_RADIUS = 2;
    /**
     * Per-tick cap on direct section writes (the review's no-10k-single-tick-writes
     * criterion): a deep-lens column is ~14 sections × 16 writes, so one tick rewrites
     * at most ~36 such columns before parking the resume cursor until the next tick.
     */
    private static final int WRITE_BUDGET_PER_TICK = 8192;

    /**
     * Same four heightmap types vanilla's FEATURES task (and the sweep's finish pass)
     * re-primes, so the final chunk state matches chunk generation.
     */
    private static final EnumSet<Heightmap.Types> HEIGHTMAPS_TO_PRIME = EnumSet.of(
            Heightmap.Types.WORLD_SURFACE, Heightmap.Types.OCEAN_FLOOR,
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES);

    /** One regen job per disc profile (mutations on the server thread only). */
    private static final Map<DiscProfile, Job> JOBS = new HashMap<>();

    private ChunkRegen() {}

    /** Why {@link #start} refused to queue a job. */
    public enum Refusal { NOT_DISC_DIMENSION, SWEEP_RUNNING, REGEN_RUNNING, ALL_PROTECTED }

    /** Progress observer; both callbacks fire on the server thread. */
    public interface Listener {
        /** One chunk finished (rewrite + replay + relight queued). */
        void onChunkDone(int chunksDone, int chunksTotal, ChunkPos pos);

        /** The whole job finished. */
        void onComplete(Result result);
    }

    /** Summary of a completed job. */
    public record Result(int chunksRegenerated, int chunksSkippedProtected, long columnsWritten,
            long elapsedMillis) {}

    /**
     * Outcome of {@link #start}: {@code refusal == null} means the job was queued and will
     * rewrite {@code targetChunks} chunks; {@code protectedChunks} counts chunks dropped
     * from the request by the structure guard (0 when {@code force}).
     */
    public record StartResult(@Nullable Refusal refusal, int targetChunks, int protectedChunks) {
        static StartResult refused(Refusal refusal, int protectedChunks) {
            return new StartResult(refusal, 0, protectedChunks);
        }
    }

    /** Whether a regen job is currently running in the level's dimension. */
    public static boolean isRunning(ServerLevel level) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        return profile != null && JOBS.containsKey(profile);
    }

    /**
     * Queues a chunk-regen job for the square of chunks within {@code radius}
     * (0..{@value #MAX_RADIUS}) of {@code center}. Server thread only. Chunks intersecting
     * a structure protection box are dropped (refusing the whole job when nothing remains)
     * unless {@code force} — forcing deliberately rewrites the structure footprint back to
     * base terrain.
     */
    public static StartResult start(ServerLevel level, ChunkPos center, int radius, boolean force,
            @Nullable Listener listener) {
        DiscProfile profile = WorldStageService.profileOf(level.dimension());
        if (profile == null) {
            return StartResult.refused(Refusal.NOT_DISC_DIMENSION, 0);
        }
        if (RingGrowthService.isRunning(profile)) {
            return StartResult.refused(Refusal.SWEEP_RUNNING, 0);
        }
        if (JOBS.containsKey(profile)) {
            return StartResult.refused(Refusal.REGEN_RUNNING, 0);
        }
        int clampedRadius = Mth.clamp(radius, 0, MAX_RADIUS);
        int committedStage = WorldStageService.stage(level.getServer(), profile);
        DiscMapData map = DiscMapData.get();
        List<ProtectedZone> zones = buildProtectedZones(profile, committedStage, map);

        List<ChunkPos> targets = new ArrayList<>();
        int skippedProtected = 0;
        for (int cx = center.x - clampedRadius; cx <= center.x + clampedRadius; cx++) {
            for (int cz = center.z - clampedRadius; cz <= center.z + clampedRadius; cz++) {
                if (!force && intersectsZone(zones, cx, cz)) {
                    skippedProtected++;
                } else {
                    targets.add(new ChunkPos(cx, cz));
                }
            }
        }
        if (targets.isEmpty()) {
            return StartResult.refused(Refusal.ALL_PROTECTED, skippedProtected);
        }
        JOBS.put(profile, new Job(level, profile, committedStage, map, targets, skippedProtected, listener));
        EclipseMod.LOGGER.info(
                "Chunk regen started: {} {} chunk(s) around [{}, {}] (radius {}, stage {}{}{})",
                profile.name(), targets.size(), center.x, center.z, clampedRadius, committedStage,
                force ? ", FORCED through structure protection" : "",
                skippedProtected > 0 ? ", " + skippedProtected + " chunk(s) skipped as protected" : "");
        return new StartResult(null, targets.size(), skippedProtected);
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (JOBS.isEmpty()) {
            return;
        }
        for (Job job : List.copyOf(JOBS.values())) {
            if (job.level.getServer() != event.getServer()) {
                continue;
            }
            job.tickBudgeted();
            if (job.isDone()) {
                JOBS.remove(job.profile, job);
                job.complete();
            }
        }
    }

    /** Statics must never leak into the next world a singleplayer client opens. */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        JOBS.clear();
    }

    // --- structure protection (sweep-parity boxes + pending sites) ---

    /**
     * XZ no-write boxes of everything the regen must not chew into: authored landmarks
     * whose stage is already stamped (extent rules mirror
     * {@code RingGrowthService.buildProtectedZones}) plus {@link StructurePendingRegistry}
     * pending sites of this dimension (their terrain prep may already have run).
     */
    private static List<ProtectedZone> buildProtectedZones(DiscProfile profile, int committedStage,
            DiscMapData map) {
        List<ProtectedZone> zones = new ArrayList<>();
        for (DiscMapData.Landmark landmark : map.landmarks(profile)) {
            if (landmark.stage() > committedStage) {
                continue;
            }
            int extent = protectionExtent(landmark) + STRUCTURE_PROTECTION_MARGIN;
            zones.add(new ProtectedZone(landmark.x() - extent, landmark.z() - extent,
                    landmark.x() + extent, landmark.z() + extent));
        }
        String dimensionName = profile == DiscProfile.NETHER ? "nether" : "overworld";
        for (StructurePendingRegistry.PendingSite site : StructurePendingRegistry.pending()) {
            if (!dimensionName.equals(site.dimension())) {
                continue;
            }
            int extent = Math.max(8, site.footprint() / 2) + STRUCTURE_PROTECTION_MARGIN;
            zones.add(new ProtectedZone(site.anchor().getX() - extent, site.anchor().getZ() - extent,
                    site.anchor().getX() + extent, site.anchor().getZ() + extent));
        }
        return zones;
    }

    /** Landmark half-extent, mirroring the sweep's measured values (see class javadoc). */
    private static int protectionExtent(DiscMapData.Landmark landmark) {
        if (landmark.id().contains("village")) {
            return VILLAGE_PROTECTION_EXTENT;
        }
        if (landmark.id().contains("temple")) {
            return TEMPLE_PROTECTION_EXTENT;
        }
        return landmark.radius();
    }

    private static boolean intersectsZone(List<ProtectedZone> zones, int chunkX, int chunkZ) {
        int minX = chunkX << 4;
        int minZ = chunkZ << 4;
        for (ProtectedZone zone : zones) {
            if (zone.overlapsBox(minX, minZ, minX + 15, minZ + 15)) {
                return true;
            }
        }
        return false;
    }

    /** Axis-aligned XZ no-write box around one protected structure. */
    private record ProtectedZone(int minX, int minZ, int maxX, int maxZ) {
        boolean overlapsBox(int boxMinX, int boxMinZ, int boxMaxX, int boxMaxZ) {
            return boxMaxX >= this.minX && boxMinX <= this.maxX
                    && boxMaxZ >= this.minZ && boxMinZ <= this.maxZ;
        }
    }

    // --- the job ---

    /** Resume state of the one chunk currently being rewritten across ticks. */
    private static final class ChunkInProgress {
        final ChunkPos pos;
        final LevelChunk chunk;
        /** Columns rewritten so far (indexed {@code (lx << 4) | lz}) — orphan-BE cleanup. */
        final boolean[] rewritten = new boolean[16 * 16];
        /** Next column index in 0..255; the per-tick budget parks it mid-chunk. */
        int columnCursor;
        /** Inside columns rewritten in this chunk (0 → skip the pipeline replay). */
        long columns;

        ChunkInProgress(ChunkPos pos, LevelChunk chunk) {
            this.pos = pos;
            this.chunk = chunk;
        }
    }

    private static final class Job {
        final ServerLevel level;
        final DiscProfile profile;
        final int committedStage;
        /** One map snapshot for the whole job — a mid-job reload must never mix map data. */
        final DiscMapData map;
        final ArrayDeque<ChunkPos> queue;
        final int totalChunks;
        final int skippedProtected;
        @Nullable
        final Listener listener;
        final long startedAtNanos = System.nanoTime();

        int chunksDone;
        long columnsWritten;
        /** The one chunk currently being rewritten across ticks, or {@code null}. */
        @Nullable
        private ChunkInProgress current;

        Job(ServerLevel level, DiscProfile profile, int committedStage, DiscMapData map,
                List<ChunkPos> targets, int skippedProtected, @Nullable Listener listener) {
            this.level = level;
            this.profile = profile;
            this.committedStage = committedStage;
            this.map = map;
            this.queue = new ArrayDeque<>(targets);
            this.totalChunks = targets.size();
            this.skippedProtected = skippedProtected;
            this.listener = listener;
        }

        boolean isDone() {
            return this.queue.isEmpty() && this.current == null;
        }

        /**
         * Advances the job under the {@value #WRITE_BUDGET_PER_TICK}-write budget: columns
         * of the in-flight chunk are rewritten until the budget is spent (the resume
         * cursor parks until the next tick) or its 256-column cursor completes —
         * finalization then runs at the chunk boundary and the next queued chunk starts
         * on a later tick (one chunk in flight at a time, POL-S-04).
         */
        void tickBudgeted() {
            if (this.current == null) {
                ChunkPos next = this.queue.poll();
                if (next == null) {
                    return;
                }
                // The WRITER_TICKET's 200-tick TTL comfortably outlasts the ~7 ticks a
                // deep-lens chunk needs under the budget.
                this.current = new ChunkInProgress(next,
                        BudgetedBlockWriter.loadWithTicket(this.level, next.x, next.z));
            }
            ChunkInProgress chunk = this.current;
            try {
                int writes = 0;
                while (chunk.columnCursor < 16 * 16 && writes < WRITE_BUDGET_PER_TICK) {
                    writes += rewriteColumn(chunk, chunk.columnCursor++);
                }
                if (chunk.columnCursor < 16 * 16) {
                    return; // budget spent — resume this chunk's cursor next tick
                }
                finishChunk(chunk);
            } catch (Exception e) {
                EclipseMod.LOGGER.error("Chunk regen failed for {} chunk {}", this.profile.name(),
                        chunk.pos, e);
            }
            this.current = null;
            this.chunksDone++;
            if (this.listener != null) {
                this.listener.onChunkDone(this.chunksDone, this.totalChunks, chunk.pos);
            }
        }

        void complete() {
            Result result = new Result(this.chunksDone, this.skippedProtected, this.columnsWritten,
                    (System.nanoTime() - this.startedAtNanos) / 1_000_000L);
            EclipseMod.LOGGER.info(
                    "Chunk regen complete: {} — {} chunk(s) rewritten ({} columns) in {} ms, {} skipped (protected)",
                    this.profile.name(), result.chunksRegenerated(), result.columnsWritten(),
                    result.elapsedMillis(), result.chunksSkippedProtected());
            if (this.listener != null) {
                this.listener.onComplete(result);
            }
        }

        /**
         * One step of the base rewrite: the inside check plus {@link #writeColumn} for the
         * column at {@code columnIndex} ({@code (lx << 4) | lz} — same order the old
         * whole-chunk loop used). Returns the number of section writes spent (0 for void
         * columns past the rim, which are never bulldozed).
         */
        private int rewriteColumn(ChunkInProgress chunk, int columnIndex) {
            int lx = columnIndex >> 4;
            int lz = columnIndex & 15;
            int x = chunk.pos.getMinBlockX() + lx;
            int z = chunk.pos.getMinBlockZ() + lz;
            DiscColumn column = DiscTerrainFunction.column(
                    this.profile, x, z, this.committedStage, this.map);
            if (!column.inside()) {
                return 0; // void column — never bulldoze builds floating past the rim
            }
            chunk.rewritten[columnIndex] = true;
            chunk.columns++;
            this.columnsWritten++;
            return writeColumn(chunk.chunk, column, lx, lz);
        }

        /**
         * Chunk finalization once the rewrite cursor completes: orphaned-block-entity
         * cleanup, pipeline replay ({@link DiscGenPipeline#runOnLiveChunk} with the
         * 3&times;3 neighbourhood ticket-loaded first), heightmap re-prime, entombment
         * rescue and relight/resend — same order the old one-shot {@code regenChunk} ran.
         */
        private void finishChunk(ChunkInProgress inProgress) {
            LevelChunk chunk = inProgress.chunk;
            // Rewritten columns' old block entities are orphans now; replayed features
            // re-create their own (e.g. monster-room spawners) after this cleanup.
            for (BlockPos bePos : List.copyOf(chunk.getBlockEntitiesPos())) {
                if (inProgress.rewritten[((bePos.getX() & 15) << 4) | (bePos.getZ() & 15)]) {
                    chunk.removeBlockEntity(bePos);
                }
            }
            chunk.setUnsaved(true);
            if (inProgress.columns > 0) {
                BudgetedBlockWriter.ensureNeighborsLoaded(this.level, inProgress.pos);
                DiscGenPipeline.runOnLiveChunk(this.level, chunk);
            }
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS_TO_PRIME);
            rescueEntombedPlayers(chunk);
            BudgetedBlockWriter.relightAndResend(this.level, chunk);
        }

        /**
         * One column straight into the chunk sections (the sweep's write pattern): every
         * section the column reaches or that has content is written over its full 16-block
         * run, so old terrain/decoration outside the new solid span clears to air; written
         * fluids get a scheduled tick (section writes fire no updates). Returns the number
         * of section writes performed (the per-tick budget currency).
         */
        private int writeColumn(LevelChunk chunk, DiscColumn column, int lx, int lz) {
            int writes = 0;
            for (int index = 0; index < chunk.getSectionsCount(); index++) {
                LevelChunkSection section = chunk.getSection(index);
                int sectionMinY = SectionPos.sectionToBlockCoord(
                        this.level.getSectionYFromSectionIndex(index));
                boolean columnReaches = column.topY() >= sectionMinY
                        && column.bottomY() <= sectionMinY + 15;
                if (!columnReaches && section.hasOnlyAir()) {
                    continue;
                }
                for (int dy = 0; dy < 16; dy++) {
                    BlockState state = DiscTerrainFunction.stateInColumn(column, sectionMinY + dy);
                    section.setBlockState(lx, dy, lz, state, false);
                    writes++;
                    FluidState fluid = state.getFluidState();
                    if (!fluid.isEmpty()) {
                        this.level.scheduleTick(new BlockPos(column.x(), sectionMinY + dy, column.z()),
                                fluid.getType(), fluid.getType().getTickDelay(this.level));
                    }
                }
            }
            return writes;
        }

        /**
         * Survival/adventure players left colliding with the fresh terrain/decoration are
         * popped onto the new motion-blocking surface ({@code RingGrowthService
         * .rescueFromReplay} pattern) — suffocating inside a regenerated column costs
         * permanent hearts. Runs after the heightmap re-prime so the lookup sees new tops.
         */
        private void rescueEntombedPlayers(LevelChunk chunk) {
            ChunkPos pos = chunk.getPos();
            for (ServerPlayer player : this.level.players()) {
                if (player.isSpectator() || player.isCreative()
                        || !player.chunkPosition().equals(pos)
                        || this.level.noCollision(player)) {
                    continue;
                }
                int x = Mth.floor(player.getX());
                int z = Mth.floor(player.getZ());
                int targetY = chunk.getHeight(Heightmap.Types.MOTION_BLOCKING, x & 15, z & 15) + 1;
                if (targetY <= player.getY()) {
                    continue; // colliding with something above the surface — not our rewrite
                }
                player.teleportTo(this.level, player.getX(), targetY, player.getZ(),
                        player.getYRot(), player.getXRot());
                player.setDeltaMovement(Vec3.ZERO);
                player.hurtMarked = true;
                EclipseMod.LOGGER.info("Chunk regen: rescued {} from entombment at ({}, {}) -> y {}",
                        player.getScoreboardName(), x, z, targetY);
            }
        }
    }
}
