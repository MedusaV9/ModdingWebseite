package dev.projecteclipse.eclipse.worldgen.stage;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import it.unimi.dsi.fastutil.longs.Long2IntOpenHashMap;
import it.unimi.dsi.fastutil.longs.LongArrayList;
import it.unimi.dsi.fastutil.longs.LongOpenHashSet;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.util.Mth;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Tick-budgeted runtime terrain sweep that rewrites the annulus between two stage radii
 * with {@link DiscTerrainFunction} output — the animated counterpart of the chunk
 * generator (byte-identical results, worker 3 contract). One job may run per disc
 * dimension; jobs tick on {@code ServerTickEvent.Post}.
 *
 * <p><b>Column set</b>: every column with {@code min(r0,r1) − RIM_REWRITE_MARGIN ≤ r ≤
 * max(r0,r1) + RIM_NOISE_AMP} (the old rim taper/crumble band must be replaced by interior
 * terrain). For transitions touching overworld stage 0 that band automatically spans the
 * void gap and the eight player discs (r 72…233). Growing writes the new stage's terrain;
 * lowering writes the SAME function at the lower stage, which yields air/void beyond the
 * new radius — ERASE mode is not a special case, only its ordering differs.</p>
 *
 * <p><b>Ordering</b>: GROW sweeps radius-then-angle (a wave racing around the
 * circumference, ring by ring outward); ERASE sweeps outer-radius-first (the disc crumbles
 * inward to the new rim); the intro FUSION (overworld 0 → 1) sweeps by distance to the
 * nearest pre-existing disc edge ({@link FusionSequence}) so bridges race toward each
 * other. Every ordering is deterministic, so the persisted growth cursor (saved every
 * {@value #CURSOR_PERSIST_INTERVAL} columns) resumes an interrupted sweep after a
 * restart.</p>
 *
 * <p><b>Chunks</b>: already-loaded chunks are rewritten in place; generated-but-unloaded
 * chunks (resolved via async region reads at job start) are loaded with a short-lived
 * ticket and rewritten; never-generated chunks are skipped — chunkgen covers them at the
 * committed stage. Writes go straight into {@link LevelChunkSection#setBlockState} (no
 * neighbor reactions); when a chunk's last column is written its heightmaps are re-primed
 * and it goes through {@link BudgetedBlockWriter#relightAndResend} (full light rebuild via
 * the task queue + resend to watching clients). At most
 * {@value #MAX_CHUNK_FINISHES_PER_TICK} chunks finish per tick.</p>
 *
 * <p><b>Budget</b>: {@code ringBlocksBudgetMs} (general.json, default 2 ms) of nanoTime per
 * tick in animate mode, plus a pacing cap that stretches a sweep towards
 * ~{@value #ANIMATE_TARGET_TICKS} ticks; instant mode uses a {@value #INSTANT_BUDGET_MS} ms
 * budget and no pacing. Animated sweeps skip ticks entirely while the server is above
 * 40 ms/tick.</p>
 *
 * <p><b>Players</b>: GROW sweeps write full-thickness terrain straight through anyone
 * standing in the rewrite band — a written column that intersects a survival player pops
 * them up to the new surface (and re-anchors an active {@link FreezeService} lock there),
 * because suffocating inside a fresh column costs permanent hearts. Erase sweeps are
 * excluded: removing terrain never buries anyone.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RingGrowthService {
    private static final int MAX_CHUNK_FINISHES_PER_TICK = 4;
    private static final int CURSOR_PERSIST_INTERVAL = 100;
    private static final int INSTANT_BUDGET_MS = 25;
    /** Animated sweeps are paced towards this duration (~75 s) unless the budget is tighter. */
    private static final int ANIMATE_TARGET_TICKS = 1500;
    private static final long MSPT_SKIP_NANOS = 40_000_000L;
    /** Leading-edge materialize FX throttle: one burst per 5 ticks ≈ 4/second. */
    private static final int FX_INTERVAL_TICKS = 5;
    private static final int STATS_LOG_INTERVAL_TICKS = 100;

    /** Chunk NBT statuses BELOW {@code minecraft:noise}: no terrain stamped yet, chunkgen covers. */
    private static final Set<String> PRE_NOISE_STATUSES = Set.of(
            "minecraft:empty", "minecraft:structure_starts", "minecraft:structure_references",
            "minecraft:biomes");

    private static final EnumSet<Heightmap.Types> HEIGHTMAPS_TO_PRIME = EnumSet.of(
            Heightmap.Types.WORLD_SURFACE, Heightmap.Types.OCEAN_FLOOR,
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES);

    private static final Map<DiscProfile, Job> JOBS = new HashMap<>();

    private RingGrowthService() {}

    /**
     * Starts (or restarts) the sweep for a committed stage transition. {@code resumeCursor}
     * &gt; 0 resumes an interrupted sweep at that column index of the deterministic ordering.
     * Called by {@link WorldStageService} only — stage persistence and the chunkgen seam
     * must already be committed.
     */
    static void start(ServerLevel level, DiscProfile profile, int fromStage, int toStage,
            boolean animate, long resumeCursor) {
        Job job = new Job(level, profile, fromStage, toStage, toStage, animate, false, resumeCursor);
        JOBS.put(profile, job);
        if (!job.isRebuild) {
            EclipseWorldState.get(level.getServer())
                    .setGrowthCursor(profile.name(), fromStage, job.cursor);
        }
    }

    /** Re-stamps the annulus of {@code stage} with the committed stage's terrain (repair tool). */
    static void startRebuild(ServerLevel level, DiscProfile profile, int stage, int committedStage) {
        JOBS.put(profile, new Job(level, profile, Math.max(0, stage - 1), stage, committedStage, false, true, 0L));
    }

    /**
     * Cancels the running job of a profile. Returns the stage the cancelled sweep started
     * from (so a superseding commit can widen its rewrite band), or {@code null} when no
     * job was running.
     */
    static Integer cancel(ServerLevel level, DiscProfile profile) {
        Job job = JOBS.remove(profile);
        if (job == null) {
            return null;
        }
        job.cancelled = true;
        EclipseMod.LOGGER.info("Ring growth superseded: {} stage {} -> {} at column {}/{}",
                profile.name(), job.fromStage, job.toStage, job.cursor, job.totalColumns());
        return job.isRebuild ? null : job.fromStage;
    }

    /** Whether a sweep (animated or instant) is currently running for the profile. */
    public static boolean isRunning(DiscProfile profile) {
        return JOBS.containsKey(profile);
    }

    /** Whether the currently running overworld sweep is the animated intro fusion (0 → 1). */
    public static boolean isRunningIntroFusion() {
        Job job = JOBS.get(DiscProfile.OVERWORLD);
        return job != null && job.animate && !job.isRebuild
                && FusionSequence.isIntroFusion(job.profile, job.fromStage, job.toStage);
    }

    /** Human-readable one-line progress for {@code /eclipse stage get}, or {@code null}. */
    public static String progressLine(DiscProfile profile) {
        Job job = JOBS.get(profile);
        return job == null ? null : job.describeProgress();
    }

    /**
     * Fraction of the running sweep's columns already written, in [0, 1] — {@code 1} when
     * no sweep is running. {@code SoftBorder.resumeGrowthLerp} uses this to re-derive the
     * mid-lerp ring radius of a sweep resumed after a restart.
     */
    public static double progressFraction(DiscProfile profile) {
        Job job = JOBS.get(profile);
        if (job == null) {
            return 1.0D;
        }
        long total = job.totalColumns();
        return total <= 0 ? 1.0D : Math.min(1.0D, (double) job.cursor / total);
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (JOBS.isEmpty()) {
            return;
        }
        for (Job job : List.copyOf(JOBS.values())) {
            job.tick();
            if (job.done) {
                JOBS.remove(job.profile, job);
            }
        }
    }

    /**
     * Restart hygiene: persist each in-flight sweep's cursor one last time (the live
     * persistence only lands every {@value #CURSOR_PERSIST_INTERVAL} columns) and drop the
     * jobs — the static map must never leak stale {@code ServerLevel} references into the
     * next world a singleplayer client opens. {@code WorldStageService.onServerStarted}
     * resumes from the persisted cursor.
     */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        for (Job job : JOBS.values()) {
            job.cancelled = true;
            if (!job.isRebuild) {
                EclipseWorldState.get(event.getServer())
                        .setGrowthCursor(job.profile.name(), job.fromStage, job.cursor);
                EclipseMod.LOGGER.info("Ring growth interrupted by server stop: {} at column {}/{}",
                        job.profile.name(), job.cursor, job.totalColumns());
            }
        }
        JOBS.clear();
    }

    // --- the job ---

    private static final class Job {
        final ServerLevel level;
        final DiscProfile profile;
        final int fromStage;
        final int toStage;
        /** Stage the terrain function is evaluated at (== toStage except for rebuilds). */
        final int evalStage;
        final boolean animate;
        final boolean isRebuild;
        final int innerRadius;
        final int outerRadius;

        /** Lowering sweep (terrain removal): outer-radius-first ordering, no entombment risk. */
        final boolean erase;
        /** Intro fusion uses distance-to-nearest-disc-edge ordering instead of ring order. */
        final boolean fusionOrdered;
        /** Band columns as packed (x << 32 | z & 0xFFFFFFFF), in sweep order. */
        final long[] columns;
        /** Unprocessed band columns per chunk (key = ChunkPos.asLong). */
        final Long2IntOpenHashMap remainingPerChunk;
        /** Chunks that must be rewritten (loaded now, or on disk with terrain stamped). */
        final LongOpenHashSet rewriteChunks = new LongOpenHashSet();
        final ArrayDeque<Long> finishQueue = new ArrayDeque<>();
        final int columnsPerTickCap;

        long cursor;
        int pendingChunkResolves;
        boolean resolving = true;
        boolean cancelled;
        boolean done;

        // Cached chunk of the previous column (ring sweeps cross chunk borders constantly).
        LevelChunk cachedChunk;
        long cachedChunkKey = Long.MIN_VALUE;
        /** Set by {@link #chunkFor} when the last call had to sync-load a chunk from disk. */
        boolean lastChunkCallLoaded;

        // Stats + throttles.
        final long startedAtNanos = System.nanoTime();
        long columnsWritten;
        long columnsSkipped;
        int chunksRewritten;
        int chunksLoadedFromDisk;
        long lastFxGameTime = Long.MIN_VALUE;
        long lastStatsGameTime;
        long lastMsptWarnGameTime = Long.MIN_VALUE;

        Job(ServerLevel level, DiscProfile profile, int fromStage, int toStage, int evalStage,
                boolean animate, boolean isRebuild, long resumeCursor) {
            this.level = level;
            this.profile = profile;
            this.fromStage = fromStage;
            this.toStage = toStage;
            this.evalStage = evalStage;
            this.animate = animate;
            this.isRebuild = isRebuild;

            int rLow = Math.min(innerRadiusOf(fromStage), innerRadiusOf(toStage));
            int rHigh = Math.max(outerRadiusOf(fromStage), outerRadiusOf(toStage));
            // A stage-0 rebuild must re-stamp the whole pre-intro footprint, not an annulus.
            this.innerRadius = isRebuild && toStage == 0
                    ? 0 : Math.max(0, rLow - DiscTerrainFunction.RIM_REWRITE_MARGIN);
            this.outerRadius = rHigh + DiscTerrainFunction.RIM_NOISE_AMP;

            this.erase = outerRadiusOf(toStage) < outerRadiusOf(fromStage);
            this.fusionOrdered = !this.erase && FusionSequence.isIntroFusion(profile, fromStage, toStage);
            this.columns = buildOrderedColumns(this.erase);
            this.cursor = Math.min(Math.max(0L, resumeCursor), this.columns.length);
            this.columnsPerTickCap = animate
                    ? Math.max(64, this.columns.length / ANIMATE_TARGET_TICKS)
                    : Integer.MAX_VALUE;

            this.remainingPerChunk = new Long2IntOpenHashMap();
            this.remainingPerChunk.defaultReturnValue(0);
            for (long packed : this.columns) {
                this.remainingPerChunk.addTo(chunkKeyOf(packed), 1);
            }
            // Resumed sweeps: columns before the cursor were already written; chunks they
            // completed were already relit before the restart (interrupted relights self-heal
            // on load via lightCorrect=false).
            for (long i = 0; i < this.cursor; i++) {
                this.remainingPerChunk.addTo(chunkKeyOf(this.columns[(int) i]), -1);
            }

            resolveChunks();
            EclipseMod.LOGGER.info(
                    "Ring growth started: {} stage {} -> {}{} ({} columns, band r {}..{}, {} chunks, {}{}{})",
                    profile.name(), fromStage, toStage, isRebuild ? " [rebuild]" : "",
                    this.columns.length, this.innerRadius, this.outerRadius,
                    this.remainingPerChunk.size(), animate ? "animated" : "instant",
                    this.fusionOrdered ? ", fusion ordering" : "",
                    this.cursor > 0 ? ", resumed at column " + this.cursor : "");
        }

        /**
         * Innermost radius that is guaranteed terrain at {@code stage}. Overworld stage 0 is
         * NOT a disc out to its outer footprint — only the main disc (r 96) is solid, then a
         * void gap, then the player-disc ring. Transitions touching stage 0 must rewrite from
         * the main-disc rim outward so the gap gets filled (grow) or re-voided (erase).
         */
        int innerRadiusOf(int stage) {
            if (stage <= 0 && this.profile == DiscProfile.OVERWORLD) {
                return DiscGeometry.MAIN_DISC_RADIUS;
            }
            return StageRadii.radius(this.profile, stage);
        }

        /** Outermost radius with any terrain at {@code stage} (player-disc ring at stage 0). */
        int outerRadiusOf(int stage) {
            if (stage <= 0 && this.profile == DiscProfile.OVERWORLD) {
                return DiscGeometry.PLAYER_DISC_RING_RADIUS + DiscGeometry.PLAYER_DISC_RADIUS;
            }
            return StageRadii.radius(this.profile, stage);
        }

        long totalColumns() {
            return this.columns.length;
        }

        /**
         * All band columns ordered for the sweep. Sort keys pack into one long
         * (order bits above a 21-bit column index) so a primitive sort suffices:
         * GROW = (radius, angle) ascending; ERASE = radius descending, angle ascending.
         */
        private long[] buildOrderedColumns(boolean erase) {
            LongArrayList list = new LongArrayList();
            long innerSq = (long) this.innerRadius * this.innerRadius;
            long outerSq = (long) this.outerRadius * this.outerRadius;
            for (int x = -this.outerRadius; x <= this.outerRadius; x++) {
                long xSq = (long) x * x;
                for (int z = -this.outerRadius; z <= this.outerRadius; z++) {
                    long distSq = xSq + (long) z * z;
                    if (distSq >= innerSq && distSq <= outerSq) {
                        list.add(pack(x, z));
                    }
                }
            }
            long[] packed = list.toLongArray();
            if (packed.length >= (1 << 21)) {
                throw new IllegalStateException("Ring growth band too large: " + packed.length + " columns");
            }
            long[] keyed = new long[packed.length];
            for (int i = 0; i < packed.length; i++) {
                keyed[i] = (orderKey(packed[i], erase) << 21) | i;
            }
            Arrays.sort(keyed);
            long[] ordered = new long[packed.length];
            for (int i = 0; i < keyed.length; i++) {
                ordered[i] = packed[(int) (keyed[i] & 0x1FFFFF)];
            }
            return ordered;
        }

        /**
         * Sort key of one column: primary 1-block band (radius for GROW, inverted radius for
         * ERASE, distance-to-nearest-disc-edge for the intro FUSION), secondary angle.
         */
        long orderKey(long packed, boolean erase) {
            int x = unpackX(packed);
            int z = unpackZ(packed);
            int ring = this.fusionOrdered
                    ? FusionSequence.distanceToNearestDiscEdge(x, z)
                    : (int) Math.sqrt((double) x * x + (double) z * z);
            if (erase) {
                ring = this.outerRadius - ring;
            }
            double angle = Math.atan2(z, x);
            int angleKey = (int) ((angle + Math.PI) / (2.0D * Math.PI) * 65535.0D) & 0xFFFF;
            return ((long) ring << 16) | angleKey;
        }

        /**
         * Kicks async region-file reads for every band chunk that is not currently loaded,
         * to find generated-but-unloaded chunks that must be rewritten (their stored status
         * is at or past {@code minecraft:noise}). The sweep starts once all reads resolve.
         */
        private void resolveChunks() {
            List<ChunkPos> toRead = new ArrayList<>();
            for (long chunkKey : this.remainingPerChunk.keySet()) {
                ChunkPos pos = new ChunkPos(chunkKey);
                if (this.level.getChunkSource().getChunkNow(pos.x, pos.z) != null) {
                    this.rewriteChunks.add(chunkKey);
                } else {
                    toRead.add(pos);
                }
            }
            this.pendingChunkResolves = toRead.size();
            if (this.pendingChunkResolves == 0) {
                this.resolving = false;
                return;
            }
            for (ChunkPos pos : toRead) {
                this.level.getChunkSource().chunkMap.read(pos).whenCompleteAsync((tag, error) -> {
                    if (error == null && tag != null && tag.isPresent()
                            && hasStampedTerrain(tag.get())) {
                        this.rewriteChunks.add(pos.toLong());
                    }
                    if (--this.pendingChunkResolves == 0) {
                        this.resolving = false;
                        EclipseMod.LOGGER.info(
                                "Ring growth {}: chunk scan done — {} of {} band chunks need rewriting",
                                this.profile.name(), this.rewriteChunks.size(), this.remainingPerChunk.size());
                    }
                }, this.level.getServer());
            }
        }

        private static boolean hasStampedTerrain(CompoundTag chunkTag) {
            String status = chunkTag.getString("Status");
            return !status.isEmpty() && !PRE_NOISE_STATUSES.contains(status);
        }

        void tick() {
            if (this.cancelled || this.done) {
                return;
            }
            if (this.resolving) {
                return;
            }
            long gameTime = this.level.getGameTime();
            if (this.animate && this.level.getServer().getAverageTickTimeNanos() > MSPT_SKIP_NANOS) {
                if (gameTime - this.lastMsptWarnGameTime >= STATS_LOG_INTERVAL_TICKS) {
                    this.lastMsptWarnGameTime = gameTime;
                    EclipseMod.LOGGER.info("Ring growth {}: paused this tick (MSPT > 40)", this.profile.name());
                }
                return;
            }

            // The cached chunk may have been unloaded between ticks — always re-resolve.
            this.cachedChunk = null;
            this.cachedChunkKey = Long.MIN_VALUE;

            long budgetNanos = (this.animate ? EclipseConfig.ringBlocksBudgetMs() : INSTANT_BUDGET_MS) * 1_000_000L;
            long start = System.nanoTime();
            int colsThisTick = 0;
            int loadsThisTick = 0;
            int maxLoads = this.animate ? 1 : 4;

            while (this.cursor < this.columns.length && colsThisTick < this.columnsPerTickCap
                    && System.nanoTime() - start < budgetNanos) {
                long packed = this.columns[(int) this.cursor];
                long chunkKey = chunkKeyOf(packed);
                if (this.rewriteChunks.contains(chunkKey)) {
                    LevelChunk chunk = chunkFor(chunkKey, loadsThisTick < maxLoads);
                    if (chunk == null) {
                        break; // unloaded on-disk chunk and no load budget left this tick
                    }
                    if (this.lastChunkCallLoaded) {
                        this.lastChunkCallLoaded = false;
                        loadsThisTick++;
                    }
                    writeColumn(chunk, unpackX(packed), unpackZ(packed), gameTime);
                    this.columnsWritten++;
                } else {
                    this.columnsSkipped++;
                }
                if (this.remainingPerChunk.addTo(chunkKey, -1) == 1
                        && this.rewriteChunks.contains(chunkKey)) {
                    this.finishQueue.add(chunkKey);
                }
                this.cursor++;
                colsThisTick++;
                if (!this.isRebuild && this.cursor % CURSOR_PERSIST_INTERVAL == 0) {
                    EclipseWorldState.get(this.level.getServer())
                            .setGrowthCursor(this.profile.name(), this.fromStage, this.cursor);
                }
            }

            int finishes = 0;
            while (finishes < MAX_CHUNK_FINISHES_PER_TICK && !this.finishQueue.isEmpty()) {
                finishChunk(this.finishQueue.poll());
                finishes++;
            }

            if (gameTime - this.lastStatsGameTime >= STATS_LOG_INTERVAL_TICKS
                    && this.cursor < this.columns.length) {
                this.lastStatsGameTime = gameTime;
                EclipseMod.LOGGER.info("Ring growth progress: {}", describeProgress());
            }

            if (this.cursor >= this.columns.length && this.finishQueue.isEmpty()) {
                complete();
            }
        }

        /** The (cached) full chunk for a chunk key, sync-loading on-disk chunks when allowed. */
        private LevelChunk chunkFor(long chunkKey, boolean mayLoad) {
            if (this.cachedChunkKey == chunkKey) {
                return this.cachedChunk;
            }
            int cx = ChunkPos.getX(chunkKey);
            int cz = ChunkPos.getZ(chunkKey);
            LevelChunk chunk = this.level.getChunkSource().getChunkNow(cx, cz);
            if (chunk == null) {
                if (!mayLoad) {
                    return null;
                }
                chunk = BudgetedBlockWriter.loadWithTicket(this.level, cx, cz);
                this.chunksLoadedFromDisk++;
                this.lastChunkCallLoaded = true;
            }
            this.cachedChunk = chunk;
            this.cachedChunkKey = chunkKey;
            return chunk;
        }

        /**
         * Rewrites one column with the terrain function's output at {@link #evalStage},
         * straight into the chunk sections (no block updates, no neighbor reactions —
         * the flag 2|16 equivalent for bulk section writes). Fires the leading-edge
         * materialize FX for columns that turn from void to solid.
         */
        private void writeColumn(LevelChunk chunk, int x, int z, long gameTime) {
            DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, this.evalStage);
            int lx = x & 15;
            int lz = z & 15;
            boolean wasVoid = this.animate && column.inside()
                    && chunk.getBlockState(new BlockPos(x, clampY(column.surfaceY()), z)).isAir();
            for (int index = 0; index < chunk.getSectionsCount(); index++) {
                LevelChunkSection section = chunk.getSection(index);
                int sectionMinY = SectionPos.sectionToBlockCoord(this.level.getSectionYFromSectionIndex(index));
                boolean columnReaches = column.inside()
                        && column.topY() >= sectionMinY && column.bottomY() <= sectionMinY + 15;
                if (!columnReaches && section.hasOnlyAir()) {
                    continue;
                }
                for (int dy = 0; dy < 16; dy++) {
                    BlockState state = DiscTerrainFunction.stateInColumn(column, sectionMinY + dy);
                    section.setBlockState(lx, dy, lz, state, false);
                }
            }
            chunk.setUnsaved(true);
            if (!this.erase && column.inside()) {
                rescueEntombedPlayers(column);
            }
            if (wasVoid && gameTime - this.lastFxGameTime >= FX_INTERVAL_TICKS) {
                this.lastFxGameTime = gameTime;
                Vec3 pos = new Vec3(x + 0.5D, column.surfaceY() + 1.5D, z + 0.5D);
                PacketDistributor.sendToPlayersNear(this.level, null, pos.x, pos.y, pos.z, 192.0D,
                        new S2CQuasarPayload(S2CQuasarPayload.MAP_EXPAND_MATERIALIZE, pos));
            }
        }

        /** Grace window after an entombment rescue so a re-anchored freeze lets the player settle. */
        private static final int RESCUE_REANCHOR_GRACE_TICKS = 10;

        /**
         * Entombment protection (GROW sweeps only): a just-written column that intersects a
         * survival/adventure player would suffocate them inside solid terrain — permanent
         * heart loss. Pops any such player up onto the new surface ({@code surfaceY + 1};
         * climbing above lava/trunk/cactus columns via the pure column data, which matches
         * the blocks just written) and, when {@link FreezeService} holds them (unlock
         * cinematics freeze watchers during animated growth), re-anchors the lock at the
         * new position so the rubber band does not drag them back underground.
         */
        private void rescueEntombedPlayers(DiscColumn column) {
            for (ServerPlayer player : this.level.players()) {
                if (Mth.floor(player.getX()) != column.x() || Mth.floor(player.getZ()) != column.z()
                        || player.isSpectator() || player.isCreative()) {
                    continue;
                }
                double feetY = player.getY();
                // The written solid band is bottomY..surfaceY; the player collider spans
                // feet..feet+1.8, so anything below that band (or clear above it) is safe.
                if (feetY < column.bottomY() - 2 || feetY >= column.surfaceY() + 1) {
                    continue;
                }
                int targetY = Math.max(column.surfaceY(), column.lavaTopY()) + 1;
                while (targetY <= column.topY()
                        && !(DiscTerrainFunction.stateInColumn(column, targetY).isAir()
                                && DiscTerrainFunction.stateInColumn(column, targetY + 1).isAir())) {
                    targetY++; // step above cover/trunk/canopy blocks in this column
                }
                player.teleportTo(this.level, player.getX(), targetY, player.getZ(),
                        player.getYRot(), player.getXRot());
                player.setDeltaMovement(Vec3.ZERO);
                player.hurtMarked = true;
                if (FreezeService.isFrozen(player)) {
                    FreezeService.reanchorWithGrace(player, RESCUE_REANCHOR_GRACE_TICKS);
                }
                EclipseMod.LOGGER.info(
                        "Ring growth: rescued {} from entombment at ({}, {}) -> y {} ({} sweep column)",
                        player.getScoreboardName(), column.x(), column.z(), targetY,
                        this.profile.name());
            }
        }

        private int clampY(int y) {
            return Math.max(this.level.getMinBuildHeight(),
                    Math.min(this.level.getMaxBuildHeight() - 1, y));
        }

        /**
         * A chunk's last band column was written: drop orphaned block entities, re-prime the
         * heightmaps, and hand the chunk to {@link BudgetedBlockWriter#relightAndResend}
         * (full light rebuild through the task queue + resend to watching clients).
         */
        private void finishChunk(long chunkKey) {
            LevelChunk chunk = chunkFor(chunkKey, true);

            long innerSq = (long) this.innerRadius * this.innerRadius;
            long outerSq = (long) this.outerRadius * this.outerRadius;
            for (BlockPos bePos : List.copyOf(chunk.getBlockEntitiesPos())) {
                long distSq = (long) bePos.getX() * bePos.getX() + (long) bePos.getZ() * bePos.getZ();
                if (distSq >= innerSq && distSq <= outerSq) {
                    chunk.removeBlockEntity(bePos);
                }
            }

            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS_TO_PRIME);
            BudgetedBlockWriter.relightAndResend(this.level, chunk);
            this.chunksRewritten++;
        }

        private void complete() {
            this.done = true;
            double seconds = (System.nanoTime() - this.startedAtNanos) / 1.0e9D;
            EclipseMod.LOGGER.info(
                    "Ring growth complete: {} stage {} -> {}{} in {} s — {} columns written, {} skipped "
                            + "(never generated), {} chunks rewritten ({} loaded from disk), {} columns/s",
                    this.profile.name(), this.fromStage, this.toStage, this.isRebuild ? " [rebuild]" : "",
                    String.format(java.util.Locale.ROOT, "%.1f", seconds),
                    this.columnsWritten, this.columnsSkipped, this.chunksRewritten, this.chunksLoadedFromDisk,
                    String.format(java.util.Locale.ROOT, "%.0f", this.columns.length / Math.max(0.05D, seconds)));
            if (!this.isRebuild) {
                WorldStageService.onSweepComplete(this.level, this.profile, this.fromStage, this.toStage);
            }
        }

        String describeProgress() {
            double pct = this.columns.length == 0 ? 100.0D : 100.0D * this.cursor / this.columns.length;
            double seconds = (System.nanoTime() - this.startedAtNanos) / 1.0e9D;
            return String.format(java.util.Locale.ROOT,
                    "%s stage %d -> %d%s: %d/%d columns (%.1f%%), %d chunks rewritten, %.0f columns/s",
                    this.profile.name(), this.fromStage, this.toStage, this.isRebuild ? " [rebuild]" : "",
                    this.cursor, this.columns.length, pct, this.chunksRewritten,
                    this.cursor / Math.max(0.05D, seconds));
        }

        // --- packing helpers ---

        private static long pack(int x, int z) {
            return ((long) x << 32) | (z & 0xFFFFFFFFL);
        }

        private static int unpackX(long packed) {
            return (int) (packed >> 32);
        }

        private static int unpackZ(long packed) {
            return (int) packed;
        }

        private static long chunkKeyOf(long packed) {
            return ChunkPos.asLong(unpackX(packed) >> 4, unpackZ(packed) >> 4);
        }
    }
}
