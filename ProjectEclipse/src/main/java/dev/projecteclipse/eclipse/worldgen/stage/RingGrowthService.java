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
import dev.projecteclipse.eclipse.network.S2CGrowthWavePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.growth.GrowthPayloads;
import dev.projecteclipse.eclipse.worldgen.DiscChunkGenerator;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.vanilla.DiscGenPipeline;
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
import net.minecraft.world.level.levelgen.GenerationStep;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Tick-budgeted runtime terrain sweep that rewrites the annulus between two stage radii
 * with {@link DiscTerrainFunction} output — the animated counterpart of the chunk
 * generator (byte-identical results, worker 3 contract; since W1.5 including the full
 * vanilla pipeline replay of design D3). One job may run per disc dimension; jobs tick on
 * {@code ServerTickEvent.Post}.
 *
 * <p><b>Column set (growth v2, design D3)</b>: band membership is decided per CHUNK, then
 * every disc column ({@code r ≤ outerRadius}) of a touched chunk is rewritten — not just
 * the band columns. A chunk is touched when it contains at least one column with
 * {@code min(r0,r1) − RIM_REWRITE_MARGIN ≤ r ≤ max(r0,r1) + RIM_NOISE_AMP} (the old rim
 * taper/crumble band must be replaced by interior terrain). The full-chunk rewrite wipes
 * ALL old decoration inside touched chunks (base fill emits air outside the column solid
 * span), so the decoration replay below can regenerate it without duplicates. Interior
 * columns rewrite to byte-identical base terrain (the terrain function is
 * stage-independent inside {@code radius − RIM_REWRITE_MARGIN}); columns beyond
 * {@code outerRadius} are void in both states and stay untouched (never bulldoze player
 * builds floating past the rim). For transitions touching overworld stage 0 the band
 * automatically spans the void gap and the eight player discs (r 72…233). Growing writes
 * the new stage's terrain; lowering writes the SAME function at the lower stage, which
 * yields air/void beyond the new radius — ERASE mode is not a special case, only its
 * ordering differs.</p>
 *
 * <p><b>Pipeline replay (design D3)</b>: when a touched chunk's last column is written,
 * the chunk re-runs the vanilla integration pipeline on the live chunk —
 * {@link DiscGenPipeline#runOnLiveChunk} (carve → decorate → seed animals) for genuine
 * GROW commits; carve → decorate WITHOUT animal seeding for rebuilds and erase sweeps —
 * so grown terrain carries real trees/features/caves and is block-identical to what fresh
 * chunk generation at the committed stage produces (same frozen seed, deterministic
 * chunk-finish order = write order). Chunks intersecting a structure protection box skip
 * the replay entirely (the caller-side guard of the {@code runOnLiveChunk} contract —
 * carving/decorating would chew into the protected pieces); never-generated chunks are
 * skipped as before (chunkgen covers them).</p>
 *
 * <p><b>Ordering</b>: GROW sweeps radius-then-angle (a wave racing around the
 * circumference, ring by ring outward); ERASE sweeps outer-radius-first (the disc crumbles
 * inward to the new rim); the intro FUSION (overworld 0 → 1) sweeps by distance to the
 * nearest pre-existing disc edge ({@link FusionSequence}) so bridges race toward each
 * other. Every ordering is deterministic, so the persisted growth cursor (saved every
 * {@value #CURSOR_PERSIST_INTERVAL} columns) resumes an interrupted sweep after a
 * restart.</p>
 *
 * <p><b>Wave payloads + reveal delay (design D11)</b>: animated sweeps broadcast
 * {@link S2CGrowthWavePayload} every {@value #FX_INTERVAL_TICKS} ticks (the wavefront
 * segment written since the previous pulse) and pace the wavefront to at most
 * {@code growth.ringsPerPulse} rings per pulse; a rewritten chunk's relight/resend is
 * held until {@code growth.revealDelayTicks} after the pulse covering its columns went
 * out, so clients never see a raw chunk pop before the animation front reaches it.
 * {@link S2CShakePayload} rumble pulses fire every {@code growth.shakeEveryRings} rings
 * of front advance (suppressed during the intro fusion — {@link FusionSequence} owns that
 * spectacle's rumble). Instant sweeps skip payloads, pacing and reveal delay entirely.
 * Knobs live in {@code worldgen_tuning.json} ({@link GrowthPacing}).</p>
 *
 * <p><b>Chunks</b>: already-loaded chunks are rewritten in place; generated-but-unloaded
 * chunks (resolved via async region reads at job start) are loaded with a short-lived
 * ticket and rewritten; never-generated chunks are skipped — chunkgen covers them at the
 * committed stage. A chunk still mid-generation on a worker thread at job start resolves
 * as not-stamped even though it may have generated with the OLD stage: such chunks get a
 * {@code getChunkNow} re-check when the sweep first reaches them and one more look in a
 * retry pass at sweep end, which re-enqueues the band columns of any that finished
 * generating in the meantime. Writes go straight into
 * {@link LevelChunkSection#setBlockState} (no neighbor reactions), scheduling a fluid
 * tick for every written fluid block so fresh river water and moat lava start flowing;
 * when a chunk's last column is written it is queued for finish (replay → heightmap
 * re-prime → {@link BudgetedBlockWriter#relightAndResend}). At most
 * {@value #MAX_CHUNK_FINISHES_PER_TICK} chunks finish per tick, bounded additionally by a
 * per-tick finish nano budget (decoration replay is the expensive part).</p>
 *
 * <p><b>Structures</b>: growth sweeps must not bulldoze landmark set-pieces stamped at an
 * earlier stage (the stage-4 village sprawls into the stage-5 band). No stamped-piece
 * record is persisted, so protection derives from the authored landmark table
 * ({@link DiscMapData#landmarks}): every landmark whose stage was already stamped when
 * the sweep starts contributes an XZ no-write box of its measured piece extent (villages
 * {@value #VILLAGE_PROTECTION_EXTENT}, temples {@value #TEMPLE_PROTECTION_EXTENT}, else
 * the authored radius) padded by {@value #STRUCTURE_PROTECTION_MARGIN} blocks; columns
 * inside a box are skipped, their block entities kept, and chunks overlapping a box skip
 * the decoration replay. Erase/downgrade sweeps rewrite everything — lowering the stage
 * is a dev tool that deliberately removes structures ({@code StructureStamper} re-stamps
 * them when the stage grows back).</p>
 *
 * <p><b>Budget</b>: {@code ringBlocksBudgetMs} (general.json, default 2 ms) of nanoTime per
 * tick in animate mode, plus a pacing cap that stretches a sweep towards
 * ~{@code growth.targetTicks} ticks ({@link GrowthPacing}); instant mode uses a
 * {@value #INSTANT_BUDGET_MS} ms budget and no pacing. Animated sweeps skip ticks entirely
 * while the server is above 40 ms/tick.</p>
 *
 * <p><b>Players</b>: GROW sweeps write full-thickness terrain straight through anyone
 * standing in the rewrite band — a written column that intersects a survival player pops
 * them up to the new surface (and re-anchors an active {@link FreezeService} lock there),
 * because suffocating inside a fresh column costs permanent hearts. The decoration replay
 * gets the same protection: a player left colliding with freshly grown feature blocks
 * (tree trunks) after a chunk's replay is popped onto the new motion-blocking surface.
 * Erase sweeps are excluded: removing terrain never buries anyone.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class RingGrowthService {
    private static final int MAX_CHUNK_FINISHES_PER_TICK = 4;
    private static final int CURSOR_PERSIST_INTERVAL = 100;
    private static final int INSTANT_BUDGET_MS = 25;
    private static final long MSPT_SKIP_NANOS = 40_000_000L;
    /**
     * Wavefront pulse cadence (design D11: payload every 5 ticks) — also the leading-edge
     * materialize FX throttle (one quasar burst per pulse interval ≈ 4/second).
     */
    private static final int FX_INTERVAL_TICKS = 5;
    private static final int STATS_LOG_INTERVAL_TICKS = 100;

    /**
     * Per-tick nano budget of the chunk-finish loop (the decoration replay is the
     * expensive part — carving the 8-neighborhood plus feature placement measures in the
     * low milliseconds per chunk). At least one finish always runs per tick so a slow
     * chunk can never stall a sweep.
     */
    private static final long FINISH_BUDGET_NANOS_ANIMATED = 12_000_000L;
    private static final long FINISH_BUDGET_NANOS_INSTANT = 25_000_000L;

    /**
     * Duration of the periodic growth rumble ({@code growth.shakeEveryRings}); strength is
     * per-player, scaled 0.08–0.5 by radial distance to the front (IDEA-14 §1).
     */
    private static final int SHAKE_TICKS = 15;

    /** Extra XZ pad (blocks) around a protected landmark's measured piece extent. */
    private static final int STRUCTURE_PROTECTION_MARGIN = 8;
    /** Measured half-extent of a stamped village (houses scatter far past the authored r=40). */
    private static final int VILLAGE_PROTECTION_EXTENT = 64;
    /** Measured half-extent of the stamped temples (slight overhang past the authored r=16). */
    private static final int TEMPLE_PROTECTION_EXTENT = 24;

    /** Chunk NBT statuses BELOW {@code minecraft:noise}: no terrain stamped yet, chunkgen covers. */
    private static final Set<String> PRE_NOISE_STATUSES = Set.of(
            "minecraft:empty", "minecraft:structure_starts", "minecraft:structure_references",
            "minecraft:biomes");

    /**
     * Heightmaps re-primed after a chunk's rewrite + replay. Deliberately the same four
     * types vanilla's FEATURES task primes (and {@link DiscGenPipeline} primes before
     * decorating), so the final state matches chunk generation.
     */
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

    /** Max chunk finishes drained synchronously at server stop (bounds shutdown work). */
    private static final int MAX_SHUTDOWN_FINISHES = 64;

    /**
     * Restart hygiene, part 1 — persist each in-flight sweep's cursor one last time (the
     * live persistence only lands every {@value #CURSOR_PERSIST_INTERVAL} columns). This
     * must happen on {@code ServerStoppingEvent}: it fires BEFORE the final world save,
     * while {@code ServerStoppedEvent} fires after it, so anything written there would
     * never reach disk. {@code WorldStageService.onServerStarted} resumes from the
     * persisted cursor.
     *
     * <p>The finish queue is in-memory, so written-but-unfinished chunks would lose their
     * pipeline replay (no trees, ever) across the restart: up to
     * {@value #MAX_SHUTDOWN_FINISHES} pending chunks are finished right here (replay runs
     * synchronously; the async relight tail self-heals on next load via
     * {@code lightCorrect=false}). A deeper backlog instead rolls the persisted cursor
     * back to the first column of the oldest still-pending chunk, so the resumed sweep
     * re-writes and re-finishes everything the drain missed — see
     * {@link Job#drainFinishQueue}.</p>
     */
    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        for (Job job : JOBS.values()) {
            job.cancelled = true;
            long persistCursor = job.drainFinishQueue(MAX_SHUTDOWN_FINISHES);
            if (!job.isRebuild) {
                EclipseWorldState.get(event.getServer())
                        .setGrowthCursor(job.profile.name(), job.fromStage, persistCursor);
                if (persistCursor < job.cursor) {
                    EclipseMod.LOGGER.warn(
                            "Ring growth {}: {} chunks still unreplayed at server stop — resume cursor rolled back {} -> {}",
                            job.profile.name(), job.finishQueue.size(), job.cursor, persistCursor);
                }
                EclipseMod.LOGGER.info("Ring growth interrupted by server stop: {} at column {}/{}",
                        job.profile.name(), persistCursor, job.totalColumns());
            } else if (!job.finishQueue.isEmpty()) {
                // Rebuilds are not resumable (no cursor persistence) — a deep backlog at
                // stop leaves those chunks base-terrain-only; the repair tool is re-runnable.
                EclipseMod.LOGGER.warn(
                        "Stage rebuild {} interrupted with {} chunks unreplayed — re-run /eclipse stage rebuild",
                        job.profile.name(), job.finishQueue.size());
            }
        }
    }

    /**
     * Restart hygiene, part 2 — drop the jobs after the final save: the static map must
     * never leak stale {@code ServerLevel} references into the next world a singleplayer
     * client opens.
     */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
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
        /** All disc columns of band chunks as packed (x << 32 | z & 0xFFFFFFFF), in sweep order. */
        final long[] columns;
        /** Unprocessed columns per chunk (key = ChunkPos.asLong). */
        final Long2IntOpenHashMap remainingPerChunk;
        /** Chunks that must be rewritten (loaded now, or on disk with terrain stamped). */
        final LongOpenHashSet rewriteChunks = new LongOpenHashSet();
        /** Not-stamped chunks the sweep passed over; re-checked once by the end retry pass. */
        final LongOpenHashSet skippedChunks = new LongOpenHashSet();
        /** Chunks that actually had a column written — only these get finished (replay + relight + resend). */
        final LongOpenHashSet touchedChunks = new LongOpenHashSet();
        /** Chunks overlapping a structure protection box: their decoration replay is skipped. */
        final LongOpenHashSet protectedChunks = new LongOpenHashSet();
        /** Chunks whose last column was written, waiting for their reveal time (FIFO = write order). */
        final ArrayDeque<PendingFinish> finishQueue = new ArrayDeque<>();
        final int columnsPerTickCap;
        /** Max order-ring advance per tick, derived from {@code growth.ringsPerPulse} (animated only). */
        final int maxRingAdvancePerTick;
        /**
         * One {@link DiscMapData} snapshot for the whole job — a {@code disc_map.json}
         * reload mid-sweep must never mix old and new map data between this job's columns.
         */
        final DiscMapData map;
        /** XZ no-write boxes of landmarks already stamped when this sweep started (growth only). */
        final List<ProtectedZone> protectedZones;
        /** Whether finished chunks replay animal seeding (genuine GROW commits only, D3/D11). */
        final boolean seedAnimals;

        long cursor;
        /** Columns of late-generated chunks re-enqueued at sweep end; null until the retry pass ran. */
        long[] retryColumns;
        long retryCursor;
        int pendingChunkResolves;
        boolean resolving = true;
        boolean cancelled;
        boolean done;

        // Cached chunk of the previous column (ring sweeps cross chunk borders constantly).
        LevelChunk cachedChunk;
        long cachedChunkKey = Long.MIN_VALUE;
        /** Set by {@link #chunkFor} when the last call had to sync-load a chunk from disk. */
        boolean lastChunkCallLoaded;

        /**
         * "Never" sentinel for game-time throttles. Deliberately NOT {@link Long#MIN_VALUE}:
         * {@code gameTime - Long.MIN_VALUE} overflows to a large NEGATIVE value, so a
         * {@code >= interval} check would never pass and the throttled action would never
         * fire (pre-W1.5 latent bug in the materialize-FX and MSPT-warn throttles).
         */
        private static final long NEVER = Long.MIN_VALUE / 2;

        // Wavefront pulse state (animated non-rebuild sweeps only).
        long lastPulseCursor;
        long lastWaveGameTime = NEVER;
        int pulseIndex;
        int lastShakeRing = Integer.MIN_VALUE;

        // Stats + throttles.
        final long startedAtNanos = System.nanoTime();
        long columnsWritten;
        long columnsSkipped;
        long columnsProtected;
        int chunksRewritten;
        int chunksLoadedFromDisk;
        int chunksReplayed;
        int chunkReplaysSkippedProtected;
        long replayNanos;
        int wavesSent;
        long lastFxGameTime = NEVER;
        long lastStatsGameTime;
        long lastMsptWarnGameTime = NEVER;

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
            // Rebuilds repair blocks, never spawn duplicates; erase sweeps remove terrain.
            this.seedAnimals = !this.erase && !isRebuild;
            this.map = DiscMapData.get();
            this.protectedZones = buildProtectedZones();
            this.columns = buildOrderedColumns(this.erase);
            this.cursor = Math.min(Math.max(0L, resumeCursor), this.columns.length);
            this.lastPulseCursor = this.cursor;
            this.columnsPerTickCap = animate
                    ? Math.max(64, this.columns.length / Math.max(100, GrowthPacing.targetTicks()))
                    : Integer.MAX_VALUE;
            this.maxRingAdvancePerTick = animate
                    ? Math.max(1, Mth.ceil((double) GrowthPacing.ringsPerPulse() / FX_INTERVAL_TICKS))
                    : Integer.MAX_VALUE;

            this.remainingPerChunk = new Long2IntOpenHashMap();
            this.remainingPerChunk.defaultReturnValue(0);
            for (long packed : this.columns) {
                this.remainingPerChunk.addTo(chunkKeyOf(packed), 1);
            }
            // Resumed sweeps: columns before the cursor were already written, and chunks
            // they completed were already replayed — onServerStopping drains the finish
            // queue or rolls the persisted cursor back, so no fully-written chunk misses
            // its replay across a CLEAN stop (interrupted async relights self-heal on
            // load via lightCorrect=false). A hard crash can still lose replays between
            // the last periodic persist and the crash; the next commit's band overlap or
            // a stage rebuild self-heals those chunks.
            for (long i = 0; i < this.cursor; i++) {
                this.remainingPerChunk.addTo(chunkKeyOf(this.columns[(int) i]), -1);
            }
            markProtectedChunks();

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
         * All columns the sweep rewrites, ordered. Chunk-granular (design D3): first every
         * band chunk is collected (any chunk whose 16×16 footprint overlaps the annulus
         * {@code innerRadius..outerRadius}), then ALL its disc columns
         * ({@code r ≤ outerRadius}) are enqueued — interior columns included, so the
         * full-chunk rewrite wipes old decoration ahead of the pipeline replay. Sort keys
         * pack into one long (order bits above a 21-bit column index) so a primitive sort
         * suffices: GROW = (radius, angle) ascending; ERASE = radius descending, angle
         * ascending; FUSION = (edge distance, angle) ascending.
         */
        private long[] buildOrderedColumns(boolean erase) {
            long innerSq = (long) this.innerRadius * this.innerRadius;
            long outerSq = (long) this.outerRadius * this.outerRadius;
            int minChunk = -this.outerRadius >> 4;
            int maxChunk = this.outerRadius >> 4;
            LongArrayList list = new LongArrayList();
            for (int cx = minChunk; cx <= maxChunk; cx++) {
                for (int cz = minChunk; cz <= maxChunk; cz++) {
                    if (!chunkOverlapsBand(cx, cz, innerSq, outerSq)) {
                        continue;
                    }
                    int baseX = cx << 4;
                    int baseZ = cz << 4;
                    for (int lx = 0; lx < 16; lx++) {
                        long xSq = (long) (baseX + lx) * (baseX + lx);
                        for (int lz = 0; lz < 16; lz++) {
                            long distSq = xSq + (long) (baseZ + lz) * (baseZ + lz);
                            if (distSq <= outerSq) {
                                list.add(pack(baseX + lx, baseZ + lz));
                            }
                        }
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

        /** Whether the chunk's 16×16 XZ footprint overlaps the {@code innerRadius..outerRadius} annulus. */
        private static boolean chunkOverlapsBand(int cx, int cz, long innerSq, long outerSq) {
            int minX = cx << 4;
            int minZ = cz << 4;
            int maxX = minX + 15;
            int maxZ = minZ + 15;
            // Nearest point of the box to the origin must be inside the outer circle …
            long nearX = minX > 0 ? minX : (maxX < 0 ? -maxX : 0);
            long nearZ = minZ > 0 ? minZ : (maxZ < 0 ? -maxZ : 0);
            if (nearX * nearX + nearZ * nearZ > outerSq) {
                return false;
            }
            // … and the farthest corner outside (or on) the inner circle.
            long farX = Math.max(Math.abs(minX), Math.abs(maxX));
            long farZ = Math.max(Math.abs(minZ), Math.abs(maxZ));
            return farX * farX + farZ * farZ >= innerSq;
        }

        /**
         * Sort key of one column: primary 1-block band (radius for GROW, inverted radius for
         * ERASE, distance-to-nearest-disc-edge for the intro FUSION), secondary angle.
         */
        long orderKey(long packed, boolean erase) {
            int ring = orderRing(packed);
            if (erase) {
                ring = this.outerRadius - ring;
            }
            int x = unpackX(packed);
            int z = unpackZ(packed);
            double angle = Math.atan2(z, x);
            int angleKey = (int) ((angle + Math.PI) / (2.0D * Math.PI) * 65535.0D) & 0xFFFF;
            return ((long) ring << 16) | angleKey;
        }

        /** The un-inverted sweep band of one column: edge distance for FUSION, else radius. */
        private int orderRing(long packed) {
            int x = unpackX(packed);
            int z = unpackZ(packed);
            return this.fusionOrdered
                    ? FusionSequence.distanceToNearestDiscEdge(x, z)
                    : (int) Math.sqrt((double) x * x + (double) z * z);
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

        /**
         * No-write boxes of the landmark set-pieces already stamped when this sweep
         * starts (see the class javadoc, <b>Structures</b>). "Already stamped" means
         * stage &le; {@link #fromStage} for growth — landmarks of stages in
         * {@code (from, to]} are stamped AFTER the sweep, onto fresh terrain — and
         * stage &le; the committed stage ({@link #evalStage}) for rebuilds, which
         * re-stamp nothing. Erase sweeps protect nothing: lowering the stage is a dev
         * tool that deliberately removes structures.
         */
        private List<ProtectedZone> buildProtectedZones() {
            if (this.erase) {
                return List.of();
            }
            int stampedThrough = this.isRebuild ? this.evalStage : this.fromStage;
            List<ProtectedZone> zones = new ArrayList<>();
            for (DiscMapData.Landmark landmark : this.map.landmarks(this.profile)) {
                if (landmark.stage() > stampedThrough) {
                    continue;
                }
                int extent = protectionExtent(landmark) + STRUCTURE_PROTECTION_MARGIN;
                zones.add(new ProtectedZone(landmark.x() - extent, landmark.z() - extent,
                        landmark.x() + extent, landmark.z() + extent));
            }
            return List.copyOf(zones);
        }

        /**
         * Precomputes the chunks whose footprint overlaps a protection box: their columns
         * inside the box are skipped by the write loop AND their pipeline replay is skipped
         * wholesale (the caller-side protected-zone guard of the
         * {@link DiscGenPipeline#runOnLiveChunk} contract — carvers/features would chew
         * into the protected pieces, and there is no way to re-assert unknown old blocks).
         */
        private void markProtectedChunks() {
            if (this.protectedZones.isEmpty()) {
                return;
            }
            for (long chunkKey : this.remainingPerChunk.keySet()) {
                int minX = ChunkPos.getX(chunkKey) << 4;
                int minZ = ChunkPos.getZ(chunkKey) << 4;
                for (ProtectedZone zone : this.protectedZones) {
                    if (zone.overlapsBox(minX, minZ, minX + 15, minZ + 15)) {
                        this.protectedChunks.add(chunkKey);
                        break;
                    }
                }
            }
        }

        /**
         * Measured footprint half-extent of a stamped landmark. The authored radius is
         * an anchor hint, not a bound — stamped village houses scatter far past r=40
         * and the temples overhang r=16 slightly; anything unrecognised falls back to
         * its authored radius.
         */
        private static int protectionExtent(DiscMapData.Landmark landmark) {
            if (landmark.id().contains("village")) {
                return VILLAGE_PROTECTION_EXTENT;
            }
            if (landmark.id().contains("temple")) {
                return TEMPLE_PROTECTION_EXTENT;
            }
            return landmark.radius();
        }

        /** Whether the column lies inside a stamped-structure no-write box (never on erase). */
        private boolean isProtectedColumn(int x, int z) {
            for (ProtectedZone zone : this.protectedZones) {
                if (zone.contains(x, z)) {
                    return true;
                }
            }
            return false;
        }

        /** Axis-aligned XZ no-write box around one already-stamped landmark. */
        private record ProtectedZone(int minX, int minZ, int maxX, int maxZ) {
            boolean contains(int x, int z) {
                return x >= this.minX && x <= this.maxX && z >= this.minZ && z <= this.maxZ;
            }

            boolean overlapsBox(int boxMinX, int boxMinZ, int boxMaxX, int boxMaxZ) {
                return boxMaxX >= this.minX && boxMinX <= this.maxX
                        && boxMaxZ >= this.minZ && boxMinZ <= this.maxZ;
            }
        }

        /** One finished chunk waiting for its reveal time (design D11 resend-after-wavefront). */
        private record PendingFinish(long chunkKey, long earliestGameTime) {}

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
            int tickStartRing = Integer.MIN_VALUE;
            // One player scan per tick, reused by every column written this tick.
            List<ServerPlayer> rescueCandidates = this.erase ? List.of() : collectRescueCandidates();

            while (colsThisTick < this.columnsPerTickCap && System.nanoTime() - start < budgetNanos) {
                boolean retryPhase = this.cursor >= this.columns.length;
                if (retryPhase) {
                    if (this.retryColumns == null) {
                        resolveRetryColumns();
                    }
                    if (this.retryCursor >= this.retryColumns.length) {
                        break;
                    }
                }
                long packed = retryPhase
                        ? this.retryColumns[(int) this.retryCursor]
                        : this.columns[(int) this.cursor];
                if (!retryPhase && this.animate) {
                    // ringsPerPulse pacing (D11): never let the visible wavefront jump more
                    // than the configured rings per pulse — inner rings hold few columns, so
                    // a pure column budget would race the front near the band start.
                    int ring = orderRing(packed);
                    int orderedRing = this.erase ? this.outerRadius - ring : ring;
                    if (tickStartRing == Integer.MIN_VALUE) {
                        tickStartRing = orderedRing;
                    } else if (orderedRing > tickStartRing + this.maxRingAdvancePerTick) {
                        break;
                    }
                }
                long chunkKey = chunkKeyOf(packed);
                int x = unpackX(packed);
                int z = unpackZ(packed);
                if (this.rewriteChunks.contains(chunkKey) || lateGeneratedChunkCheck(chunkKey)) {
                    if (isProtectedColumn(x, z)) {
                        this.columnsProtected++;
                    } else {
                        LevelChunk chunk = chunkFor(chunkKey, loadsThisTick < maxLoads);
                        if (chunk == null) {
                            break; // unloaded on-disk chunk and no load budget left this tick
                        }
                        if (this.lastChunkCallLoaded) {
                            this.lastChunkCallLoaded = false;
                            loadsThisTick++;
                        }
                        writeColumn(chunk, x, z, gameTime, rescueCandidates);
                        this.touchedChunks.add(chunkKey);
                        this.columnsWritten++;
                    }
                } else {
                    this.columnsSkipped++;
                }
                if (this.remainingPerChunk.addTo(chunkKey, -1) == 1
                        && this.touchedChunks.contains(chunkKey)) {
                    this.finishQueue.add(new PendingFinish(chunkKey, revealTime(gameTime)));
                }
                if (retryPhase) {
                    this.retryCursor++;
                } else {
                    this.cursor++;
                    if (!this.isRebuild && this.cursor % CURSOR_PERSIST_INTERVAL == 0) {
                        EclipseWorldState.get(this.level.getServer())
                                .setGrowthCursor(this.profile.name(), this.fromStage, this.cursor);
                    }
                }
                colsThisTick++;
            }

            if (this.animate && !this.isRebuild) {
                maybeEmitWavePulse(gameTime);
            }

            long finishStart = System.nanoTime();
            long finishBudget = this.animate ? FINISH_BUDGET_NANOS_ANIMATED : FINISH_BUDGET_NANOS_INSTANT;
            int finishes = 0;
            while (finishes < MAX_CHUNK_FINISHES_PER_TICK && !this.finishQueue.isEmpty()) {
                PendingFinish head = this.finishQueue.peek();
                if (head.earliestGameTime() > gameTime) {
                    break; // reveal delay: the covering wavefront payload is not old enough yet
                }
                if (finishes > 0 && System.nanoTime() - finishStart > finishBudget) {
                    break; // replay cost cap — at least one finish always runs per tick
                }
                this.finishQueue.poll();
                finishChunk(head.chunkKey());
                finishes++;
            }

            if (gameTime - this.lastStatsGameTime >= STATS_LOG_INTERVAL_TICKS
                    && this.cursor < this.columns.length) {
                this.lastStatsGameTime = gameTime;
                EclipseMod.LOGGER.info("Ring growth progress: {}", describeProgress());
            }

            if (this.cursor >= this.columns.length && this.retryColumns != null
                    && this.retryCursor >= this.retryColumns.length && this.finishQueue.isEmpty()) {
                complete();
            }
        }

        /**
         * Earliest game time a chunk written "now" may be relit + resent (design D11): the
         * wavefront payload covering it goes out with the NEXT pulse (≤ {@value
         * #FX_INTERVAL_TICKS} ticks away), plus {@code growth.revealDelayTicks} so the
         * client animation front has visibly passed. Instant sweeps reveal immediately —
         * they broadcast no wavefront.
         */
        private long revealTime(long gameTime) {
            if (!this.animate || this.isRebuild) {
                return gameTime;
            }
            return gameTime + FX_INTERVAL_TICKS + GrowthPacing.revealDelayTicks();
        }

        /**
         * Broadcasts the wavefront segment written since the previous pulse
         * ({@link S2CGrowthWavePayload}, design D11) every {@value #FX_INTERVAL_TICKS}
         * ticks, and the periodic {@link S2CShakePayload} rumble each time the front
         * advanced {@code growth.shakeEveryRings} rings. The intro fusion keeps its own
         * rumble ({@link FusionSequence}) — only the wave payload is sent there, with
         * {@code waveR} = distance-to-nearest-disc-edge (documented on the payload).
         */
        private void maybeEmitWavePulse(long gameTime) {
            if (gameTime - this.lastWaveGameTime < FX_INTERVAL_TICKS) {
                return;
            }
            long segmentEnd = Math.min(this.cursor, this.columns.length);
            if (segmentEnd <= this.lastPulseCursor) {
                return; // nothing written since the last pulse (budget-starved tick)
            }
            long first = this.columns[(int) this.lastPulseCursor];
            long last = this.columns[(int) (segmentEnd - 1)];
            int waveRing = orderRing(last);
            boolean multiRing = this.fusionOrdered || orderRing(first) != waveRing;
            float angleStart = multiRing ? (float) -Math.PI
                    : (float) Math.atan2(unpackZ(first), unpackX(first));
            float angleEnd = multiRing ? (float) Math.PI
                    : (float) Math.atan2(unpackZ(last), unpackX(last));
            GrowthPayloads.sendWave(this.level, new S2CGrowthWavePayload(
                    this.profile.name(), this.fromStage, this.toStage, this.innerRadius,
                    this.outerRadius, waveRing, angleStart, angleEnd,
                    GrowthPacing.columnRiseTicks(), this.pulseIndex));
            this.pulseIndex++;
            this.wavesSent++;
            this.lastPulseCursor = segmentEnd;
            this.lastWaveGameTime = gameTime;

            int shakeEvery = GrowthPacing.shakeEveryRings();
            if (shakeEvery > 0 && !this.fusionOrdered) {
                if (this.lastShakeRing == Integer.MIN_VALUE) {
                    this.lastShakeRing = waveRing;
                } else if (Math.abs(waveRing - this.lastShakeRing) >= shakeEvery) {
                    this.lastShakeRing = waveRing;
                    // IDEA-14 §1: the rumble ARRIVES — per-player strength scales with the
                    // player's radial distance to the front (full 0.5 within a few blocks,
                    // fading to a faint 0.08 by 128 blocks) instead of one flat global shake.
                    for (ServerPlayer player : this.level.players()) {
                        double playerR = Math.sqrt(
                                player.getX() * player.getX() + player.getZ() * player.getZ());
                        float closeness = (float) Mth.clamp(
                                1.0D - Math.abs(playerR - waveRing) / 128.0D, 0.0D, 1.0D);
                        PacketDistributor.sendToPlayer(player,
                                S2CShakePayload.shake(Mth.lerp(closeness, 0.08F, 0.5F), SHAKE_TICKS));
                    }
                }
            }
        }

        /**
         * Late-generated chunk re-check, once per chunk the first time the sweep reaches
         * it: {@link #resolveChunks} may have run while this chunk was still
         * mid-generation on a worker thread, resolving it as "not stamped" even though
         * its terrain (possibly generated against the OLD stage seam) lands moments
         * later. Chunks that are fully loaded NOW are promoted into the rewrite set;
         * the rest go to {@link #skippedChunks} for one more look in
         * {@link #resolveRetryColumns}.
         */
        private boolean lateGeneratedChunkCheck(long chunkKey) {
            if (this.skippedChunks.contains(chunkKey)) {
                return false;
            }
            if (this.level.getChunkSource().getChunkNow(
                    ChunkPos.getX(chunkKey), ChunkPos.getZ(chunkKey)) != null) {
                this.rewriteChunks.add(chunkKey);
                return true;
            }
            this.skippedChunks.add(chunkKey);
            return false;
        }

        /**
         * End-of-sweep retry pass (runs once, when the main cursor is exhausted): every
         * chunk skipped as "not stamped" gets one more {@code getChunkNow} look — any
         * that finished generating mid-sweep are promoted into the rewrite set and their
         * band columns re-enqueued, so a chunk that was mid-generation at job start is
         * no longer skipped forever. Chunks that generated AND unloaded again during the
         * sweep are still missed (rare; the next commit's band overlap self-heals them);
         * never-generated chunks stay skipped — chunkgen covers them.
         */
        private void resolveRetryColumns() {
            LongOpenHashSet lateChunks = new LongOpenHashSet();
            for (long chunkKey : this.skippedChunks) {
                if (this.level.getChunkSource().getChunkNow(
                        ChunkPos.getX(chunkKey), ChunkPos.getZ(chunkKey)) != null) {
                    lateChunks.add(chunkKey);
                }
            }
            LongArrayList retry = new LongArrayList();
            if (!lateChunks.isEmpty()) {
                for (long packed : this.columns) {
                    long chunkKey = chunkKeyOf(packed);
                    if (lateChunks.contains(chunkKey)) {
                        retry.add(packed);
                        this.remainingPerChunk.addTo(chunkKey, 1);
                    }
                }
                this.rewriteChunks.addAll(lateChunks);
                // Resumed sweeps may re-enqueue columns skipped before the restart.
                this.columnsSkipped = Math.max(0L, this.columnsSkipped - retry.size());
                EclipseMod.LOGGER.info(
                        "Ring growth {}: {} band chunks finished generating mid-sweep — re-enqueueing {} columns",
                        this.profile.name(), lateChunks.size(), retry.size());
            }
            this.retryColumns = retry.toLongArray();
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
         * the flag 2|16 equivalent for bulk section writes). Every section that has
         * content or that the new column reaches is written over its FULL 16-block run,
         * so everything outside the new solid span — old terrain, old decoration blocks,
         * canopy overhang — clears to air (the wipe half of design D3's "no duplicated
         * trees"). Every written fluid block gets a scheduled fluid tick: section writes
         * fire no updates, so fresh river water and moat lava would otherwise sit frozen
         * at channel/rim edges (the chunkgen counterpart marks generated fluid positions
         * for postprocessing). Fires the leading-edge materialize FX for columns that
         * turn from void to solid.
         */
        private void writeColumn(LevelChunk chunk, int x, int z, long gameTime,
                List<ServerPlayer> rescueCandidates) {
            DiscColumn column = DiscTerrainFunction.column(this.profile, x, z, this.evalStage, this.map);
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
                    FluidState fluid = state.getFluidState();
                    if (!fluid.isEmpty()) {
                        this.level.scheduleTick(new BlockPos(x, sectionMinY + dy, z),
                                fluid.getType(), fluid.getType().getTickDelay(this.level));
                    }
                }
            }
            chunk.setUnsaved(true);
            if (!this.erase && column.inside()) {
                rescueEntombedPlayers(column, rescueCandidates);
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
         * Survival/adventure players of this level — the rescue candidate list, collected
         * ONCE per {@link #tick} and reused by every column written that tick (positions
         * cannot change while the sweep loop runs inside one tick, and scanning the full
         * player list per written column was measurable at instant-sweep column rates).
         */
        private List<ServerPlayer> collectRescueCandidates() {
            List<ServerPlayer> candidates = new ArrayList<>();
            for (ServerPlayer player : this.level.players()) {
                if (!player.isSpectator() && !player.isCreative()) {
                    candidates.add(player);
                }
            }
            return candidates;
        }

        /**
         * Entombment protection (GROW sweeps only): a just-written column that intersects a
         * survival/adventure player would suffocate them inside solid terrain — permanent
         * heart loss. Pops any such player up onto the new surface ({@code surfaceY + 1};
         * climbing above lava columns via the pure column data, which matches the blocks
         * just written) and, when {@link FreezeService} holds them (unlock cinematics
         * freeze watchers during animated growth), re-anchors the lock at the new position
         * so the rubber band does not drag them back underground.
         */
        private void rescueEntombedPlayers(DiscColumn column, List<ServerPlayer> candidates) {
            for (ServerPlayer player : candidates) {
                if (Mth.floor(player.getX()) != column.x() || Mth.floor(player.getZ()) != column.z()) {
                    continue;
                }
                double feetY = player.getY();
                // The written solid band is bottomY..surfaceY, but hang decor and moat lava
                // carry written blocks up to topY; the collider spans feet..feet+1.8.
                if (feetY < column.bottomY() - 2 || feetY >= column.topY() + 1) {
                    continue;
                }
                if (Mth.floor(feetY) > column.surfaceY() && !intersectsWrittenBlocks(column, feetY)) {
                    continue; // above the band in an air gap (e.g. under hang decor) — safe
                }
                int targetY = Math.max(column.surfaceY(), column.lavaTopY()) + 1;
                while (targetY <= column.topY()
                        && !(DiscTerrainFunction.stateInColumn(column, targetY).isAir()
                                && DiscTerrainFunction.stateInColumn(column, targetY + 1).isAir())) {
                    targetY++; // step above cover blocks written in this column
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

        /**
         * Whether the just-written column content actually threatens a collider whose
         * feet sit at {@code feetY}: a motion-blocking block or any fluid (fresh moat
         * lava burns, channel water drowns) within feet..feet+1.8. Only consulted for
         * players ABOVE the solid band — inside it, rescue is unconditional.
         */
        private static boolean intersectsWrittenBlocks(DiscColumn column, double feetY) {
            for (int y = Mth.floor(feetY); y <= Mth.floor(feetY + 1.8D); y++) {
                BlockState state = DiscTerrainFunction.stateInColumn(column, y);
                if (state.blocksMotion() || !state.getFluidState().isEmpty()) {
                    return true;
                }
            }
            return false;
        }

        private int clampY(int y) {
            return Math.max(this.level.getMinBuildHeight(),
                    Math.min(this.level.getMaxBuildHeight() - 1, y));
        }

        /**
         * A chunk's last column was written and its reveal time arrived: drop orphaned
         * block entities (except in protected structure columns, whose blocks were never
         * rewritten — village chests must survive), replay the vanilla pipeline on the
         * live chunk (design D3), re-prime the heightmaps, rescue anyone the fresh
         * decoration grew into, and hand the chunk to
         * {@link BudgetedBlockWriter#relightAndResend} (full light rebuild through the
         * task queue + resend to watching clients).
         */
        private void finishChunk(long chunkKey) {
            LevelChunk chunk = chunkFor(chunkKey, true);

            // Every non-protected column of the chunk out to outerRadius was rewritten —
            // their old block entities are orphans now (replayed features re-create their
            // own, e.g. monster-room spawners, AFTER this cleanup).
            long outerSq = (long) this.outerRadius * this.outerRadius;
            for (BlockPos bePos : List.copyOf(chunk.getBlockEntitiesPos())) {
                long distSq = (long) bePos.getX() * bePos.getX() + (long) bePos.getZ() * bePos.getZ();
                if (distSq <= outerSq && !isProtectedColumn(bePos.getX(), bePos.getZ())) {
                    chunk.removeBlockEntity(bePos);
                }
            }

            replayPipeline(chunk, chunkKey);
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS_TO_PRIME);
            if (!this.erase) {
                rescueFromReplay(chunk);
            }
            BudgetedBlockWriter.relightAndResend(this.level, chunk);
            this.chunksRewritten++;
        }

        /**
         * Design D3 pipeline replay on one rewritten live chunk: carve → decorate → seed
         * animals via {@link DiscGenPipeline#runOnLiveChunk} for genuine GROW commits;
         * rebuild and erase sweeps run the same carve + decorate phases WITHOUT animal
         * seeding (repairs and downgrades must not duplicate livestock — the base rewrite
         * never removes entities). Chunks overlapping a structure protection box skip the
         * replay wholesale (caller-side guard of the runOnLiveChunk contract); the 3×3
         * neighbourhood is ticket-loaded first because features may write across chunk
         * borders and biome lookups read neighbours.
         */
        private void replayPipeline(LevelChunk chunk, long chunkKey) {
            if (this.protectedChunks.contains(chunkKey)) {
                this.chunkReplaysSkippedProtected++;
                return;
            }
            long replayStart = System.nanoTime();
            BudgetedBlockWriter.ensureNeighborsLoaded(this.level, chunk.getPos());
            if (this.seedAnimals) {
                DiscGenPipeline.runOnLiveChunk(this.level, chunk);
            } else {
                replayWithoutSeeding(chunk);
            }
            this.chunksReplayed++;
            this.replayNanos += System.nanoTime() - replayStart;
        }

        /**
         * The no-seed replay half: byte-identical to
         * {@link DiscGenPipeline#runOnLiveChunk}'s carve + heightmap-prime + decorate
         * sequence (same phases, same order, same skip-on-void guard), minus the animal
         * seeding — keep in sync with the pipeline if its phase order ever changes.
         */
        private void replayWithoutSeeding(LevelChunk chunk) {
            if (!(this.level.getChunkSource().getGenerator() instanceof DiscChunkGenerator generator)) {
                return;
            }
            boolean anySolid = false;
            for (LevelChunkSection section : chunk.getSections()) {
                if (!section.hasOnlyAir()) {
                    anySolid = true;
                    break;
                }
            }
            if (!anySolid) {
                return;
            }
            DiscGenPipeline.carve(generator, this.level.registryAccess(), chunk, GenerationStep.Carving.AIR);
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS_TO_PRIME);
            generator.applyBiomeDecoration(this.level, chunk, this.level.structureManager());
        }

        /**
         * Post-replay entombment protection: the decoration replay writes through
         * {@code ServerLevel.setBlock}, so a survival player standing exactly where a
         * tree trunk (or other feature block) grew is now stuck inside it. Pops any
         * player left colliding with blocks in this chunk onto the fresh
         * motion-blocking surface. Runs AFTER the final heightmap re-prime so the
         * surface lookup already sees the new canopy tops.
         */
        private void rescueFromReplay(LevelChunk chunk) {
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
                    continue; // colliding with something above the surface — not our replay
                }
                player.teleportTo(this.level, player.getX(), targetY, player.getZ(),
                        player.getYRot(), player.getXRot());
                player.setDeltaMovement(Vec3.ZERO);
                player.hurtMarked = true;
                if (FreezeService.isFrozen(player)) {
                    FreezeService.reanchorWithGrace(player, RESCUE_REANCHOR_GRACE_TICKS);
                }
                EclipseMod.LOGGER.info(
                        "Ring growth: rescued {} from replayed decoration at ({}, {}) -> y {} ({})",
                        player.getScoreboardName(), x, z, targetY, this.profile.name());
            }
        }

        /**
         * Server-stop drain (see {@link RingGrowthService#onServerStopping}): finishes up
         * to {@code max} pending chunks immediately — reveal times are ignored, the world
         * is going down and nobody sees the pop — and returns the cursor to persist.
         * When the queue drains fully that is the live cursor. A deeper backlog
         * (pathological instant-sweep stop) returns the first column index of the oldest
         * still-pending chunk instead: the resumed sweep re-writes from there, so every
         * chunk that missed its replay gets re-finished (base rewrite and replay are
         * deterministic; already-finished chunks interleaving that band are re-finished
         * too, which may re-seed their animals — the lesser evil next to permanently
         * undecorated terrain).
         */
        long drainFinishQueue(int max) {
            int drained = 0;
            while (!this.finishQueue.isEmpty() && drained < max) {
                finishChunk(this.finishQueue.poll().chunkKey());
                drained++;
            }
            if (this.finishQueue.isEmpty()) {
                return this.cursor;
            }
            LongOpenHashSet pending = new LongOpenHashSet(this.finishQueue.size());
            for (PendingFinish finish : this.finishQueue) {
                pending.add(finish.chunkKey());
            }
            long limit = Math.min(this.cursor, this.columns.length);
            for (long i = 0; i < limit; i++) {
                if (pending.contains(chunkKeyOf(this.columns[(int) i]))) {
                    return i;
                }
            }
            return this.cursor;
        }

        private void complete() {
            this.done = true;
            double seconds = (System.nanoTime() - this.startedAtNanos) / 1.0e9D;
            EclipseMod.LOGGER.info(
                    "Ring growth complete: {} stage {} -> {}{} in {} s — {} columns written, {} skipped "
                            + "(never generated), {} protected (stamped structures), {} chunks rewritten "
                            + "({} loaded from disk), {} replayed through the vanilla pipeline in {} ms "
                            + "({} skipped as protected), {} wave pulses, {} columns/s",
                    this.profile.name(), this.fromStage, this.toStage, this.isRebuild ? " [rebuild]" : "",
                    String.format(java.util.Locale.ROOT, "%.1f", seconds),
                    this.columnsWritten, this.columnsSkipped, this.columnsProtected, this.chunksRewritten,
                    this.chunksLoadedFromDisk, this.chunksReplayed,
                    this.replayNanos / 1_000_000L, this.chunkReplaysSkippedProtected, this.wavesSent,
                    String.format(java.util.Locale.ROOT, "%.0f", this.columns.length / Math.max(0.05D, seconds)));
            if (!this.isRebuild) {
                WorldStageService.onSweepComplete(this.level, this.profile, this.fromStage, this.toStage);
            }
        }

        String describeProgress() {
            double pct = this.columns.length == 0 ? 100.0D : 100.0D * this.cursor / this.columns.length;
            double seconds = (System.nanoTime() - this.startedAtNanos) / 1.0e9D;
            return String.format(java.util.Locale.ROOT,
                    "%s stage %d -> %d%s: %d/%d columns (%.1f%%), %d chunks rewritten (%d replayed), %.0f columns/s",
                    this.profile.name(), this.fromStage, this.toStage, this.isRebuild ? " [rebuild]" : "",
                    this.cursor, this.columns.length, pct, this.chunksRewritten, this.chunksReplayed,
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
