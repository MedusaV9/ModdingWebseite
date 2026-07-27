package dev.projecteclipse.eclipse.worldgen.pregen;

import java.io.IOException;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.sequence.ExpansionSequence;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.stage.GrowthPacing;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerBossEvent;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.level.TicketType;
import net.minecraft.world.BossEvent;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * F-091 — the tick-driven full-map pregeneration engine behind
 * {@code /dev preload everything} (plan PLAN-F091-092 §2). One resumable {@link Job} per
 * disc dimension walks the chunk grid in deterministic concentric rings from the origin
 * outward ({@link #chunkAtIndex}) and pushes every disc chunk to FULL status once, so
 * afterwards chunks only ever LOAD from region files — no raw chunkgen is visible during
 * the start event or later exploration, and every expansion sweep rewrites pre-existing
 * chunks through its paced animation instead of skipping never-generated ones.
 *
 * <p><b>Mechanism</b> (the proven {@code ChunkPreload}/{@code ExpansionBorderFx}
 * pattern): per target chunk, first a {@code getChunkNow} fast path (already resident),
 * then an async region-read probe ({@code chunkMap.read} — the
 * {@link RingGrowthService} skip probe) counts already-generated chunks done without
 * loading them; only genuinely missing chunks get a self-expiring
 * {@link #PREGEN_TICKET} ({@code addRegionTicket(pos, 0)}) and a {@code getChunkNow}
 * poll until promotion. <b>No ticket is ever held</b>: the TTL expires on its own
 * (long-pending targets are re-ticketed every {@value #TICKET_REFRESH_TICKS} ticks),
 * the distance manager unloads each chunk shortly after, and the unload path saves it
 * to disk. The in-flight window (config {@code pregen.maxInFlight}, default 12) bounds
 * simultaneous full chunks; issue rate is {@code pregen.issuesPerTick} (default 4).</p>
 *
 * <p><b>Guards</b>: nothing is issued while the server is above the
 * {@code pregen.msptGuard} (40 ms/tick — the sweep's MSPT doctrine), while
 * {@link RingGrowthService#isRunning} holds the chunk-load budget for its sweep, or
 * while an {@link ExpansionSequence} cinematic is live; in-flight targets still drain.
 * Progress persists in {@link PregenState} every {@value #PERSIST_EVERY_CHUNKS}
 * completions and on {@code ServerStoppingEvent}; the persisted cursor rolls back to the
 * oldest still-outstanding spiral index, so a restart re-issues (and probe-skips)
 * whatever was in flight. {@code ServerStartedEvent} resumes unfinished jobs whose
 * {@link PregenState} fingerprint still matches, and auto-starts the whole run on
 * pre-event worlds when {@code pregen.autoStart} is set (§2.4).</p>
 *
 * <p><b>Progress surface</b>: an ops-only bossbar with percent + EMA-based ETA, an
 * action bar for the issuing operator, chat milestones every 10%, and
 * {@code /dev preload status}. On completion the run flush-saves the server
 * ({@code saveEverything}) so the whole map is durably on disk before the event.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class MapPregenService {
    /** Ticket lifespan; generous so a congested worker pool never strands a target. */
    private static final int TICKET_TTL_TICKS = 600;
    /** Self-expiring request ticket (never needs a matching removeRegionTicket). */
    private static final TicketType<ChunkPos> PREGEN_TICKET = TicketType.create(
            "eclipse_pregen", Comparator.comparingLong(ChunkPos::toLong), TICKET_TTL_TICKS);
    /** Still-pending targets are re-ticketed on this cadence (refresh resets the TTL). */
    private static final int TICKET_REFRESH_TICKS = 200;
    /** Cursor/counter persistence cadence in completed chunks (§2.3 item 5). */
    private static final int PERSIST_EVERY_CHUNKS = 64;
    /** Bossbar refresh cadence (ticks). */
    private static final int BOSSBAR_UPDATE_TICKS = 20;
    /** Action-bar cadence for the issuing operator (ticks, §2.3 item 6). */
    private static final int ACTION_BAR_TICKS = 40;
    /** How long the "done" bossbar lingers before removal (ticks, §2.3 item 7). */
    private static final int DONE_HOLD_TICKS = 200;
    /** EMA smoothing per 2-second rate sample (≈30 s effective window). */
    private static final double ETA_EMA_ALPHA = 0.12D;
    /** {@code /dev preload status} warns when the world volume has less than this free. */
    private static final long DISK_WARN_BYTES = 5L * 1024L * 1024L * 1024L;

    /**
     * Chunk NBT statuses BELOW {@code minecraft:noise}: no terrain stamped yet — the
     * probe treats these as "not generated" (mirror of {@link RingGrowthService}).
     */
    private static final Set<String> PRE_NOISE_STATUSES = Set.of(
            "minecraft:empty", "minecraft:structure_starts", "minecraft:structure_references",
            "minecraft:biomes");

    /** Active jobs by disc profile. Server thread only. */
    private static final Map<DiscProfile, Job> JOBS = new HashMap<>();

    private MapPregenService() {}

    // ------------------------------------------------------------------ public API

    /** Pregen radius of "everything": the lens-shape constant safely covers every solid block. */
    public static int defaultRadius(DiscProfile profile) {
        return (int) profile.lensNormRadius(); // 480 (§2.1)
    }

    /**
     * Starts (or resumes) one dimension job. Returns a failure reason for command
     * feedback, or {@code null} on success. {@code quiet} keeps announcements ops-only
     * (the auto-start path).
     */
    @Nullable
    public static String start(MinecraftServer server, DiscProfile profile, int radiusBlocks,
            @Nullable UUID issuerId, boolean quiet) {
        if (JOBS.containsKey(profile)) {
            return "already running";
        }
        ServerLevel level = server.getLevel(WorldStageService.dimensionOf(profile));
        if (level == null) {
            return "dimension missing";
        }
        PregenState state = PregenState.get(server);
        PregenState.Entry entry = state.entry(profile);
        if (entry.done() && entry.targetRadius() >= radiusBlocks) {
            return "already complete (cancel first to re-run)";
        }
        state.beginJob(profile, radiusBlocks);
        Job job = new Job(level, profile, radiusBlocks, entry.cursor(), entry.chunksDone(),
                issuerId, quiet);
        JOBS.put(profile, job);
        EclipseMod.LOGGER.info(
                "Map pregen {}: started to r={} ({} chunks, resuming at spiral index {}, {} done)",
                profile.name(), radiusBlocks, job.totalChunks, job.cursor, job.chunksDone);
        return null;
    }

    /** Whether a pregen job (running or draining) exists for the profile. */
    public static boolean isRunning(DiscProfile profile) {
        return JOBS.containsKey(profile);
    }

    public static boolean anyRunning() {
        return !JOBS.isEmpty();
    }

    /** Pauses every job (manual {@code /dev preload pause}); returns how many. */
    public static int pauseAll() {
        int count = 0;
        for (Job job : JOBS.values()) {
            if (!job.done && !job.paused) {
                job.paused = true;
                count++;
            }
        }
        return count;
    }

    public static int resumeAll() {
        int count = 0;
        for (Job job : JOBS.values()) {
            if (job.paused) {
                job.paused = false;
                count++;
            }
        }
        return count;
    }

    /** Cancels every job and forgets its persisted progress; returns how many. */
    public static int cancelAll(MinecraftServer server) {
        int count = 0;
        for (Job job : List.copyOf(JOBS.values())) {
            job.cancelled = true;
            job.removeBossBar();
            PregenState.get(server).reset(job.profile);
            JOBS.remove(job.profile);
            EclipseMod.LOGGER.info("Map pregen {}: cancelled at {}/{} chunks",
                    job.profile.name(), job.chunksDone, job.totalChunks);
            count++;
        }
        return count;
    }

    /** Total in-flight chunk requests across all jobs ({@code /dev preload unload} report). */
    public static int inFlightCount() {
        int count = 0;
        for (Job job : JOBS.values()) {
            count += job.inFlight.size() + job.pendingProbes;
        }
        return count;
    }

    /** Human-readable per-dimension status + disk headroom ({@code /dev preload status}). */
    public static List<String> statusLines(MinecraftServer server) {
        List<String> lines = new ArrayList<>();
        PregenState state = PregenState.get(server);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            Job job = JOBS.get(profile);
            if (job != null) {
                lines.add(job.describeStatus());
                continue;
            }
            PregenState.Entry entry = state.entry(profile);
            if (entry.targetRadius() <= 0) {
                lines.add(profile.name() + ": no pregen recorded");
            } else if (entry.done()) {
                lines.add(String.format(Locale.ROOT, "%s: DONE — %,d chunks to r=%d",
                        profile.name(), entry.chunksDone(), entry.targetRadius()));
            } else {
                lines.add(String.format(Locale.ROOT,
                        "%s: interrupted at %,d chunks (r=%d) — resumes on next boot or /dev preload start",
                        profile.name(), entry.chunksDone(), entry.targetRadius()));
            }
        }
        try {
            long usable = Files.getFileStore(server.getWorldPath(LevelResource.ROOT)).getUsableSpace();
            String disk = String.format(Locale.ROOT, "disk: %.1f GB free on the world volume",
                    usable / (1024.0D * 1024.0D * 1024.0D));
            lines.add(usable < DISK_WARN_BYTES ? disk + " — WARNING: below 5 GB" : disk);
        } catch (IOException e) {
            lines.add("disk: free-space probe failed (" + e.getMessage() + ")");
        }
        return lines;
    }

    // ------------------------------------------------------------------ spiral cursor

    /** Spiral indices covering the square of chunk rings 0..{@code chunkRange} (inclusive). */
    public static long indexCount(int chunkRange) {
        return 1L + 4L * chunkRange * (chunkRange + 1L);
    }

    /**
     * Chunk of one spiral index: ring-then-perimeter order — index 0 is chunk (0, 0),
     * ring k walks north edge west→east, then east, south (east→west) and west edges.
     * Deterministic and gap-free, so a single long cursor resumes the whole walk.
     */
    public static ChunkPos chunkAtIndex(long index) {
        if (index <= 0L) {
            return new ChunkPos(0, 0);
        }
        // Rings 0..k hold (2k+1)^2 = 1 + 4k(k+1) indices; invert approximately, then fix up.
        int k = Math.max(1, (int) Math.round((Math.sqrt((double) index) - 1.0D) / 2.0D));
        while (k > 1 && 1L + 4L * (k - 1L) * k > index) {
            k--;
        }
        while (1L + 4L * k * (k + 1L) <= index) {
            k++;
        }
        long i = index - (1L + 4L * (k - 1L) * k); // 0 .. 8k-1 within ring k
        long side = 2L * k;
        if (i < side) {
            return new ChunkPos((int) (-k + i), -k);
        }
        i -= side;
        if (i < side) {
            return new ChunkPos(k, (int) (-k + i));
        }
        i -= side;
        if (i < side) {
            return new ChunkPos((int) (k - i), k);
        }
        i -= side;
        return new ChunkPos(-k, (int) (k - i));
    }

    /** Whether any block of the chunk lies within {@code radiusBlocks} of the origin. */
    public static boolean chunkTouchesDisc(int chunkX, int chunkZ, int radiusBlocks) {
        int minX = chunkX << 4;
        int minZ = chunkZ << 4;
        long nearestX = Math.max(minX, Math.min(0, minX + 15));
        long nearestZ = Math.max(minZ, Math.min(0, minZ + 15));
        return nearestX * nearestX + nearestZ * nearestZ
                <= (long) radiusBlocks * (long) radiusBlocks;
    }

    // ------------------------------------------------------------------ lifecycle

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (JOBS.isEmpty()) {
            return;
        }
        for (Job job : List.copyOf(JOBS.values())) {
            job.tick();
            if (job.finished) {
                JOBS.remove(job.profile, job);
            }
        }
    }

    /**
     * §2.4/§2.3-5: resume interrupted jobs (fingerprint already validated inside
     * {@link PregenState#get}), then auto-start the full run on pre-event worlds.
     */
    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        PregenState state = PregenState.get(server);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            PregenState.Entry entry = state.entry(profile);
            if (entry.targetRadius() > 0 && !entry.done()) {
                String failure = start(server, profile, entry.targetRadius(), null, true);
                if (failure == null) {
                    EclipseMod.LOGGER.info("Map pregen {}: auto-resumed at {}%",
                            profile.name(), percentOf(entry.chunksDone(),
                                    JOBS.get(profile).totalChunks));
                }
            }
        }
        if (!GrowthPacing.pregenAutoStart() || EclipseWorldState.get(server).isStartEventDone()) {
            return;
        }
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            PregenState.Entry entry = state.entry(profile);
            if (entry.targetRadius() <= 0 && !entry.done() && !JOBS.containsKey(profile)) {
                String failure = start(server, profile, defaultRadius(profile), null, true);
                if (failure == null) {
                    EclipseMod.LOGGER.info(
                            "Map pregen {}: auto-started (pregen.autoStart, start event pending)",
                            profile.name());
                }
            }
        }
    }

    /** Persist every in-flight job's rollback-safe cursor before the final world save. */
    @SubscribeEvent
    public static void onServerStopping(ServerStoppingEvent event) {
        for (Job job : JOBS.values()) {
            job.cancelled = true;
            if (!job.done) {
                job.persistProgress();
                EclipseMod.LOGGER.info(
                        "Map pregen {}: server stopping — cursor persisted at {}/{} chunks",
                        job.profile.name(), job.chunksDone, job.totalChunks);
            }
        }
    }

    /** In-memory reset (SavedData is per-save; bossbars die with the player list). */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        for (Job job : JOBS.values()) {
            job.removeBossBar();
        }
        JOBS.clear();
    }

    private static int percentOf(long done, long total) {
        return total <= 0L ? 100 : (int) Math.min(100L, done * 100L / total);
    }

    private static boolean hasStampedTerrain(CompoundTag chunkTag) {
        String status = chunkTag.getString("Status");
        return !status.isEmpty() && !PRE_NOISE_STATUSES.contains(status);
    }

    // ------------------------------------------------------------------ job

    private static final class Job {
        final ServerLevel level;
        final DiscProfile profile;
        final int radiusBlocks;
        final long indexCount;
        final long totalChunks;

        /** Next spiral index to consume (may run ahead of outstanding targets). */
        long cursor;
        long chunksDone;
        /** Spiral indices issued but not yet confirmed — persisted cursor = first one. */
        final TreeSet<Long> outstanding = new TreeSet<>();
        /** In-flight ticketed targets: chunk key → target (for polling/refresh). */
        final Map<Long, InFlightTarget> inFlight = new HashMap<>();
        int pendingProbes;

        boolean paused;
        boolean guardPaused;
        boolean msptStalled;
        boolean cancelled;
        /** All chunks confirmed; bossbar lingers {@link #doneHoldTicks} more ticks. */
        boolean done;
        /** Fully torn down — the tick loop removes the job. */
        boolean finished;
        int doneHoldTicks;
        long lastPersistedDone;

        @Nullable
        final UUID issuerId;
        final boolean quiet;
        @Nullable
        ServerBossEvent bossBar;
        int lastMilestone;

        double emaChunksPerSec = -1.0D;
        long lastSampleMillis;
        long doneAtLastSample;

        Job(ServerLevel level, DiscProfile profile, int radiusBlocks, long resumeCursor,
                long resumeDone, @Nullable UUID issuerId, boolean quiet) {
            this.level = level;
            this.profile = profile;
            this.radiusBlocks = radiusBlocks;
            int chunkRange = (radiusBlocks + 15) >> 4;
            this.indexCount = MapPregenService.indexCount(chunkRange);
            long total = 0L;
            for (long i = 0L; i < this.indexCount; i++) {
                ChunkPos pos = chunkAtIndex(i);
                if (chunkTouchesDisc(pos.x, pos.z, radiusBlocks)) {
                    total++;
                }
            }
            this.totalChunks = total;
            this.cursor = Math.max(0L, Math.min(resumeCursor, this.indexCount));
            this.chunksDone = Math.max(0L, Math.min(resumeDone, total));
            this.issuerId = issuerId;
            this.quiet = quiet;
            this.lastSampleMillis = System.currentTimeMillis();
            this.doneAtLastSample = this.chunksDone;
            this.lastPersistedDone = this.chunksDone;
            this.lastMilestone = percentOf(this.chunksDone, this.totalChunks) / 10;
        }

        private static final class InFlightTarget {
            final long index;
            long lastTicketGameTime;

            InFlightTarget(long index, long gameTime) {
                this.index = index;
                this.lastTicketGameTime = gameTime;
            }
        }

        void tick() {
            long gameTime = this.level.getGameTime();
            if (this.done) {
                if (--this.doneHoldTicks <= 0) {
                    removeBossBar();
                    this.finished = true;
                }
                return;
            }
            pollInFlight(gameTime);
            // §2.4 guard rails: the terrain sweep and cinematics own the chunk budget.
            boolean guard = RingGrowthService.isRunning(this.profile)
                    || ExpansionSequence.isAnyRunActive();
            if (guard != this.guardPaused) {
                this.guardPaused = guard;
                EclipseMod.LOGGER.info("Map pregen {}: {} (sweep/cutscene guard)",
                        this.profile.name(), guard ? "paused" : "resumed");
            }
            if (!this.paused && !guard) {
                // §2.3-3 MSPT guard: issue nothing while the server is struggling.
                boolean stalled = this.level.getServer().getAverageTickTimeNanos()
                        > GrowthPacing.pregenMsptGuardMs() * 1_000_000L;
                if (stalled != this.msptStalled) {
                    this.msptStalled = stalled;
                    if (stalled) {
                        EclipseMod.LOGGER.info("Map pregen {}: backing off (MSPT > {})",
                                this.profile.name(), GrowthPacing.pregenMsptGuardMs());
                    }
                }
                if (!stalled) {
                    issueRequests(gameTime);
                }
            }
            if (this.cursor >= this.indexCount && this.inFlight.isEmpty()
                    && this.pendingProbes == 0) {
                finish();
                return;
            }
            updateProgressUi(gameTime);
        }

        /** {@code getChunkNow} poll of every ticketed target + TTL refresh of old ones. */
        private void pollInFlight(long gameTime) {
            if (this.inFlight.isEmpty()) {
                return;
            }
            for (Map.Entry<Long, InFlightTarget> entry : List.copyOf(this.inFlight.entrySet())) {
                long chunkKey = entry.getKey();
                ChunkPos pos = new ChunkPos(chunkKey);
                if (this.level.getChunkSource().getChunkNow(pos.x, pos.z) != null) {
                    this.inFlight.remove(chunkKey);
                    complete(entry.getValue().index);
                    continue;
                }
                InFlightTarget target = entry.getValue();
                if (gameTime - target.lastTicketGameTime >= TICKET_REFRESH_TICKS) {
                    // Re-adding an equal ticket refreshes its TTL (DistanceManager law).
                    this.level.getChunkSource().addRegionTicket(PREGEN_TICKET, pos, 0, pos);
                    target.lastTicketGameTime = gameTime;
                }
            }
        }

        /** Tops the in-flight window up: ≤ issuesPerTick new targets per tick (§2.3-2). */
        private void issueRequests(long gameTime) {
            int issued = 0;
            int maxInFlight = GrowthPacing.pregenMaxInFlight();
            int issuesPerTick = GrowthPacing.pregenIssuesPerTick();
            while (issued < issuesPerTick
                    && this.inFlight.size() + this.pendingProbes < maxInFlight
                    && this.cursor < this.indexCount) {
                long index = this.cursor++;
                ChunkPos pos = chunkAtIndex(index);
                if (!chunkTouchesDisc(pos.x, pos.z, this.radiusBlocks)) {
                    continue; // spiral corner outside the disc — costs no slot
                }
                issued++;
                this.outstanding.add(index);
                if (this.level.getChunkSource().getChunkNow(pos.x, pos.z) != null) {
                    complete(index); // already resident (spawn chunks, players nearby)
                    continue;
                }
                // Async region probe: stored status >= minecraft:noise counts as done
                // without ever loading the chunk (re-entrant runs are nearly free).
                this.pendingProbes++;
                this.level.getChunkSource().chunkMap.read(pos).whenCompleteAsync((tag, error) -> {
                    this.pendingProbes--;
                    if (this.cancelled || this.done) {
                        return;
                    }
                    if (error == null && tag != null && tag.isPresent()
                            && hasStampedTerrain(tag.get())) {
                        complete(index);
                    } else {
                        this.level.getChunkSource().addRegionTicket(PREGEN_TICKET, pos, 0, pos);
                        this.inFlight.put(pos.toLong(),
                                new InFlightTarget(index, this.level.getGameTime()));
                    }
                }, this.level.getServer());
            }
        }

        private void complete(long index) {
            this.outstanding.remove(index);
            this.chunksDone++;
            if (this.chunksDone - this.lastPersistedDone >= PERSIST_EVERY_CHUNKS) {
                persistProgress();
            }
        }

        /**
         * Rollback-safe persistence: the stored cursor is the OLDEST outstanding spiral
         * index, so a restart re-issues everything unconfirmed (the probe then skips
         * whatever had in fact completed — at most a few dozen cheap re-probes).
         */
        void persistProgress() {
            long persistCursor = this.outstanding.isEmpty()
                    ? this.cursor : this.outstanding.first();
            PregenState.get(this.level.getServer())
                    .setProgress(this.profile, persistCursor, this.chunksDone);
            this.lastPersistedDone = this.chunksDone;
        }

        /** §2.3-7: drain finished — persist done, flush the save, linger the bossbar. */
        private void finish() {
            this.done = true;
            this.doneHoldTicks = DONE_HOLD_TICKS;
            persistProgress();
            MinecraftServer server = this.level.getServer();
            PregenState.get(server).markDone(this.profile);
            boolean lastJob = JOBS.values().stream().allMatch(job -> job.done);
            EclipseMod.LOGGER.info(
                    "Map pregen {}: COMPLETE — {} chunks to r={}{}", this.profile.name(),
                    this.chunksDone, this.radiusBlocks, lastJob ? ", flushing world save" : "");
            if (lastJob) {
                // One durable flush so the whole map is on disk before the event (§2.3-7).
                server.saveEverything(true, true, false);
            }
            Component doneLine = Component.translatable("bossbar.eclipse.pregen.done",
                    this.profile.name(), String.format(Locale.ROOT, "%,d", this.chunksDone));
            ensureBossBar().setName(doneLine);
            ensureBossBar().setProgress(1.0F);
            syncBossBarAudience();
            for (ServerPlayer player : server.getPlayerList().getPlayers()) {
                if (player.hasPermissions(2)) {
                    player.sendSystemMessage(doneLine);
                }
            }
        }

        // ---------------------------------------------------------------- progress UI

        private void updateProgressUi(long gameTime) {
            if (gameTime % BOSSBAR_UPDATE_TICKS != 0L) {
                return;
            }
            sampleRate();
            int pct = percentOf(this.chunksDone, this.totalChunks);
            String counts = String.format(Locale.ROOT, "%,d/%,d",
                    Math.min(this.chunksDone, this.totalChunks), this.totalChunks);
            Component name = this.paused || this.guardPaused
                    ? Component.translatable("bossbar.eclipse.pregen.paused",
                            this.profile.name(), pct, counts)
                    : Component.translatable("bossbar.eclipse.pregen",
                            this.profile.name(), pct, counts, formatEta());
            ServerBossEvent bar = ensureBossBar();
            bar.setName(name);
            bar.setProgress(this.totalChunks <= 0L ? 1.0F
                    : Math.min(1.0F, (float) this.chunksDone / (float) this.totalChunks));
            syncBossBarAudience();
            if (gameTime % ACTION_BAR_TICKS == 0L && this.issuerId != null) {
                ServerPlayer issuer = this.level.getServer().getPlayerList()
                        .getPlayer(this.issuerId);
                if (issuer != null) {
                    issuer.displayClientMessage(name, true);
                }
            }
            int milestone = pct / 10;
            if (milestone > this.lastMilestone) {
                this.lastMilestone = milestone;
                EclipseMod.LOGGER.info("Map pregen {}: {}% ({}) — ETA {}",
                        this.profile.name(), pct, counts, formatEta());
                for (ServerPlayer player : this.level.getServer().getPlayerList().getPlayers()) {
                    if (player.hasPermissions(2)) {
                        player.sendSystemMessage(name);
                    }
                }
            }
        }

        /** EMA of chunks/sec — the rate is bursty (void interior vs forested rim). */
        private void sampleRate() {
            long now = System.currentTimeMillis();
            double seconds = (now - this.lastSampleMillis) / 1000.0D;
            if (seconds < 1.0D) {
                return;
            }
            double rate = (this.chunksDone - this.doneAtLastSample) / seconds;
            this.emaChunksPerSec = this.emaChunksPerSec < 0.0D ? rate
                    : this.emaChunksPerSec * (1.0D - ETA_EMA_ALPHA) + rate * ETA_EMA_ALPHA;
            this.lastSampleMillis = now;
            this.doneAtLastSample = this.chunksDone;
        }

        private String formatEta() {
            long remaining = Math.max(0L, this.totalChunks - this.chunksDone);
            if (this.emaChunksPerSec <= 0.05D) {
                return "--:--";
            }
            long etaSeconds = (long) Math.ceil(remaining / this.emaChunksPerSec);
            return String.format(Locale.ROOT, "%d:%02d", etaSeconds / 60L, etaSeconds % 60L);
        }

        String describeStatus() {
            String state = this.done ? "DONE"
                    : this.paused ? "PAUSED"
                    : this.guardPaused ? "WAITING (sweep/cutscene)"
                    : this.msptStalled ? "BACKING OFF (MSPT)" : "RUNNING";
            return String.format(Locale.ROOT,
                    "%s: %s — %,d/%,d chunks (%d%%), r=%d, cursor %,d/%,d, %d in flight, "
                            + "%.1f chunks/s, ETA %s",
                    this.profile.name(), state, Math.min(this.chunksDone, this.totalChunks),
                    this.totalChunks, percentOf(this.chunksDone, this.totalChunks),
                    this.radiusBlocks, this.cursor, this.indexCount,
                    this.inFlight.size() + this.pendingProbes,
                    Math.max(0.0D, this.emaChunksPerSec), formatEta());
        }

        private ServerBossEvent ensureBossBar() {
            if (this.bossBar == null) {
                this.bossBar = new ServerBossEvent(Component.empty(),
                        BossEvent.BossBarColor.PURPLE, BossEvent.BossBarOverlay.PROGRESS);
            }
            return this.bossBar;
        }

        /** Ops-only audience, re-synced on the update cadence (join/leave safe). */
        private void syncBossBarAudience() {
            ServerBossEvent bar = ensureBossBar();
            for (ServerPlayer player : this.level.getServer().getPlayerList().getPlayers()) {
                if (player.hasPermissions(2)) {
                    bar.addPlayer(player); // set-backed: no-op when already shown
                }
            }
            for (ServerPlayer shown : List.copyOf(bar.getPlayers())) {
                if (!shown.hasPermissions(2) || shown.hasDisconnected()) {
                    bar.removePlayer(shown);
                }
            }
        }

        void removeBossBar() {
            if (this.bossBar != null) {
                this.bossBar.removeAllPlayers();
                this.bossBar = null;
            }
        }
    }
}
