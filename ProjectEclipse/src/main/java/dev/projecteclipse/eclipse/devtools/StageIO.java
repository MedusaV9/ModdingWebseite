package dev.projecteclipse.eclipse.devtools;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import javax.annotation.Nullable;

import com.mojang.serialization.Codec;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.StageRadii;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.NbtAccounter;
import net.minecraft.nbt.NbtIo;
import net.minecraft.nbt.NbtOps;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.chunk.PalettedContainer;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.storage.LevelResource;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Stage step-loader (W14, {@code docs/ideas/05_systems.md} §3): saves and re-applies
 * SNAPSHOTS of the ring annulus between stage N−1 and N radii, enabling the curated-map
 * workflow <i>load N → hand-edit terrain → save N → later load N+1</i>. Sits on top of
 * W4's {@code WorldStageService} (which owns the COMMITTED stage — loading a snapshot
 * never changes it).
 *
 * <p><b>File format</b> ({@code <world>/eclipse/stages/<n>.bin}, nether saves use
 * {@code nether_<n>.bin}; gzip-compressed NBT via {@link NbtIo} — StructureTemplate chokes
 * at millions of blocks, so this is a purpose-built compact format):</p>
 * <pre>
 * { formatVersion: 1, profile: "overworld"|"nether", stage, innerRadius, outerRadius,
 *   minSectionY, sectionCount, savedAtEpochMillis,
 *   chunks: [ { pos: long (ChunkPos.asLong),
 *               sections: [ { y: int (section Y coord), states: {palette:[...], data:[L;...]} } ],
 *               blockEntities: [ {x,y,z,id,...} ] } ] }
 * </pre>
 * {@code states} uses the exact vanilla chunk-serializer palette codec
 * ({@code PalettedContainer.codecRW}), so on-disk chunk NBT can be lifted verbatim for
 * unloaded chunks and live sections re-encode byte-identically.
 *
 * <p><b>Save</b> is synchronous (command time): every chunk whose square intersects the
 * annulus band {@code [radius(N−1) − RIM_REWRITE_MARGIN, radius(N) + RIM_NOISE_AMP]}
 * (the exact band a {@code RingGrowthService} sweep rewrites) is captured — loaded chunks
 * from the live sections, unloaded ones straight from region NBT; never-generated chunks
 * are skipped (chunkgen covers them deterministically). Whole chunks are captured, so
 * restoration is chunk-granular. <b>Load</b> applies via a tick-budgeted writer job
 * ({@value #LOAD_BUDGET_MS} ms/tick, ≤{@value #MAX_CHUNKS_PER_TICK} chunks/tick with
 * {@link BudgetedBlockWriter#relightAndResend} per finished chunk). <b>Revert</b>
 * re-applies the last-loaded snapshot (persisted per dimension in
 * {@link EclipseWorldState#getLastLoadedStage}).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StageIO {
    private static final int FORMAT_VERSION = 1;
    /** Per-tick nanoTime budget of the snapshot loader (instant-style, like a non-animated sweep). */
    private static final int LOAD_BUDGET_MS = 25;
    private static final int MAX_CHUNKS_PER_TICK = 4;

    /** The vanilla chunk-serializer block-state palette codec (raw palette + packed data). */
    private static final Codec<PalettedContainer<BlockState>> BLOCK_STATE_CODEC = PalettedContainer.codecRW(
            Block.BLOCK_STATE_REGISTRY, BlockState.CODEC, PalettedContainer.Strategy.SECTION_STATES,
            Blocks.AIR.defaultBlockState());

    /** Chunk NBT statuses BELOW {@code minecraft:noise}: no terrain stamped yet — skip on save. */
    private static final Set<String> PRE_NOISE_STATUSES = Set.of(
            "minecraft:empty", "minecraft:structure_starts", "minecraft:structure_references",
            "minecraft:biomes");

    /** One snapshot-apply job may run per disc dimension. Server-thread only. */
    private static final Map<DiscProfile, LoadJob> LOAD_JOBS = new HashMap<>();

    private StageIO() {}

    // --- public API (commands) ---

    /**
     * Whether a snapshot-apply job is currently running for the profile.
     * {@code WorldStageService} refuses stage commits/rebuilds while this is true —
     * this class already refuses to save/load during a sweep, and the exclusion must
     * hold in both directions or a commit sweep would interleave with a half-applied
     * snapshot.
     */
    public static boolean isApplying(DiscProfile profile) {
        return LOAD_JOBS.containsKey(profile);
    }

    /** The snapshot directory {@code <world>/eclipse/stages/}. */
    public static Path stagesDir(MinecraftServer server) {
        return server.getWorldPath(LevelResource.ROOT).resolve("eclipse").resolve("stages");
    }

    /** The {@code .bin} file of a profile+stage pair ({@code <n>.bin} / {@code nether_<n>.bin}). */
    public static Path stageFile(MinecraftServer server, DiscProfile profile, int stage) {
        String name = (profile == DiscProfile.NETHER ? "nether_" : "") + stage + ".bin";
        return stagesDir(server).resolve(name);
    }

    /**
     * Serializes the stage-{@code n} annulus of the profile's dimension to its {@code .bin}
     * file, synchronously. Returns a human-readable result line, or an error prefixed with
     * {@code "ERROR: "} (busy sweep, IO failure, out-of-range stage).
     */
    public static String save(ServerLevel level, DiscProfile profile, int stage) {
        if (stage < 1 || stage > WorldStageService.maxStage(profile)) {
            return "ERROR: stage out of range: " + profile.name() + " is configured for stages 1-"
                    + WorldStageService.maxStage(profile);
        }
        if (RingGrowthService.isRunning(profile) || LOAD_JOBS.containsKey(profile)) {
            return "ERROR: a terrain job is already running for " + profile.name()
                    + " — wait for it to finish (see /eclipse stage status)";
        }
        int innerRadius = innerBandRadius(profile, stage);
        int outerRadius = outerBandRadius(profile, stage);
        long startNanos = System.nanoTime();

        ListTag chunkList = new ListTag();
        int skipped = 0;
        for (ChunkPos pos : bandChunks(innerRadius, outerRadius)) {
            CompoundTag chunkTag = serializeChunk(level, pos);
            if (chunkTag == null) {
                skipped++;
            } else {
                chunkList.add(chunkTag);
            }
        }

        CompoundTag root = new CompoundTag();
        root.putInt("formatVersion", FORMAT_VERSION);
        root.putString("profile", profile.name());
        root.putInt("stage", stage);
        root.putInt("innerRadius", innerRadius);
        root.putInt("outerRadius", outerRadius);
        root.putInt("minSectionY", level.getMinSection());
        root.putInt("sectionCount", level.getSectionsCount());
        root.putLong("savedAtEpochMillis", System.currentTimeMillis());
        root.put("chunks", chunkList);

        Path file = stageFile(level.getServer(), profile, stage);
        try {
            Files.createDirectories(file.getParent());
            NbtIo.writeCompressed(root, file);
        } catch (IOException e) {
            EclipseMod.LOGGER.error("StageIO: failed to write {}", file, e);
            return "ERROR: failed to write " + file + " — see the server log";
        }
        long sizeKb;
        try {
            sizeKb = Files.size(file) / 1024;
        } catch (IOException e) {
            sizeKb = -1;
        }
        double seconds = (System.nanoTime() - startNanos) / 1.0e9D;
        String result = String.format(Locale.ROOT,
                "Saved %s stage %d annulus (r %d..%d): %d chunks (%d never-generated skipped) "
                        + "-> %s (%d KB) in %.1f s",
                profile.name(), stage, innerRadius, outerRadius, chunkList.size(), skipped,
                file.getFileName(), sizeKb, seconds);
        EclipseMod.LOGGER.info("StageIO: {}", result);
        return result;
    }

    /**
     * Starts the tick-budgeted apply job for a saved stage snapshot. Returns a feedback
     * line or an {@code "ERROR: "}-prefixed failure (missing file, busy job). On completion
     * the stage is persisted as the dimension's {@code lastLoadedStage} (revert target).
     */
    public static String load(ServerLevel level, DiscProfile profile, int stage) {
        if (RingGrowthService.isRunning(profile) || LOAD_JOBS.containsKey(profile)) {
            return "ERROR: a terrain job is already running for " + profile.name()
                    + " — wait for it to finish (see /eclipse stage status)";
        }
        Path file = stageFile(level.getServer(), profile, stage);
        if (!Files.exists(file)) {
            return "ERROR: no snapshot " + file.getFileName() + " — /eclipse stage save " + stage + " first";
        }
        CompoundTag root;
        try {
            root = NbtIo.readCompressed(file, NbtAccounter.unlimitedHeap());
        } catch (IOException e) {
            EclipseMod.LOGGER.error("StageIO: failed to read {}", file, e);
            return "ERROR: failed to read " + file + " — see the server log";
        }
        if (root.getInt("formatVersion") != FORMAT_VERSION) {
            return "ERROR: " + file.getFileName() + " has unsupported formatVersion "
                    + root.getInt("formatVersion");
        }
        if (!profile.name().equals(root.getString("profile"))) {
            return "ERROR: " + file.getFileName() + " was saved for '" + root.getString("profile")
                    + "', not " + profile.name();
        }
        LoadJob job = new LoadJob(level, profile, stage, root.getList("chunks", Tag.TAG_COMPOUND));
        LOAD_JOBS.put(profile, job);
        String result = "Applying " + profile.name() + " stage " + stage + " snapshot: "
                + job.chunks.size() + " chunks, tick-budgeted (" + LOAD_BUDGET_MS + " ms/tick) — watch the log";
        EclipseMod.LOGGER.info("StageIO: {}", result);
        return result;
    }

    /** Re-applies the profile's last-loaded snapshot, or explains why it cannot. */
    public static String revert(ServerLevel level, DiscProfile profile) {
        int lastLoaded = EclipseWorldState.get(level.getServer()).getLastLoadedStage(profile);
        if (lastLoaded < 0) {
            return "ERROR: no snapshot has been loaded for " + profile.name()
                    + " yet — nothing to revert to";
        }
        return load(level, profile, lastLoaded);
    }

    /** One status line per disc dimension: committed stage, last-loaded snapshot, in-flight jobs, files. */
    public static List<String> statusLines(MinecraftServer server) {
        List<String> lines = new ArrayList<>();
        EclipseWorldState state = EclipseWorldState.get(server);
        for (DiscProfile profile : new DiscProfile[] {DiscProfile.OVERWORLD, DiscProfile.NETHER}) {
            int committed = state.getWorldStage(profile);
            int lastLoaded = state.getLastLoadedStage(profile);
            LoadJob job = LOAD_JOBS.get(profile);
            String sweep = RingGrowthService.progressLine(profile);
            StringBuilder line = new StringBuilder(profile.name())
                    .append(": committed stage ").append(committed)
                    .append("/").append(WorldStageService.maxStage(profile))
                    .append(" (radius ").append(StageRadii.radius(profile, committed)).append(")")
                    .append(", last loaded snapshot ").append(lastLoaded < 0 ? "none" : lastLoaded);
            if (state.hasGrowthCursor() && profile.name().equals(state.getGrowthDimension())) {
                line.append(", growth cursor ").append(state.getGrowthCursor());
            }
            if (job != null) {
                line.append(" — APPLYING stage ").append(job.stage).append(": ")
                        .append(job.cursor).append("/").append(job.chunks.size()).append(" chunks");
            }
            if (sweep != null) {
                line.append(" — SWEEPING: ").append(sweep);
            }
            lines.add(line.toString());
        }
        Path dir = stagesDir(server);
        List<String> files = new ArrayList<>();
        if (Files.isDirectory(dir)) {
            try (var stream = Files.list(dir)) {
                stream.filter(path -> path.getFileName().toString().endsWith(".bin"))
                        .sorted()
                        .forEach(path -> {
                            long kb;
                            try {
                                kb = Files.size(path) / 1024;
                            } catch (IOException e) {
                                kb = -1;
                            }
                            files.add(path.getFileName() + " (" + kb + " KB)");
                        });
            } catch (IOException e) {
                EclipseMod.LOGGER.warn("StageIO: failed to list {}", dir, e);
            }
        }
        lines.add("snapshots in " + dir + ": " + (files.isEmpty() ? "none" : String.join(", ", files)));
        return lines;
    }

    // --- band geometry (mirrors the RingGrowthService rewrite band) ---

    /**
     * Inner band radius of the stage-{@code n} annulus:
     * {@code radius(n−1) − RIM_REWRITE_MARGIN}, with W4's stage-0 special case (overworld
     * stage 0 is only solid out to the main disc, r 96 — the void gap and player discs
     * beyond belong to the stage-1 annulus).
     */
    private static int innerBandRadius(DiscProfile profile, int stage) {
        int previousRadius = stage - 1 <= 0 && profile == DiscProfile.OVERWORLD
                ? DiscGeometry.MAIN_DISC_RADIUS
                : StageRadii.radius(profile, stage - 1);
        return Math.max(0, previousRadius - DiscTerrainFunction.RIM_REWRITE_MARGIN);
    }

    /** Outer band radius: {@code radius(n) + RIM_NOISE_AMP} (the rim wobble reaches past the radius). */
    private static int outerBandRadius(DiscProfile profile, int stage) {
        return StageRadii.radius(profile, stage) + DiscTerrainFunction.RIM_NOISE_AMP;
    }

    /** Every chunk whose XZ square intersects the {@code [inner, outer]} annulus around 0,0. */
    private static List<ChunkPos> bandChunks(int innerRadius, int outerRadius) {
        List<ChunkPos> chunks = new ArrayList<>();
        long innerSq = (long) innerRadius * innerRadius;
        long outerSq = (long) outerRadius * outerRadius;
        int chunkRange = (outerRadius >> 4) + 1;
        for (int cx = -chunkRange; cx <= chunkRange; cx++) {
            for (int cz = -chunkRange; cz <= chunkRange; cz++) {
                int minX = cx << 4;
                int minZ = cz << 4;
                // Nearest point of the chunk square to the origin, per axis.
                long nearX = clampToRange(0, minX, minX + 15);
                long nearZ = clampToRange(0, minZ, minZ + 15);
                long nearSq = nearX * nearX + nearZ * nearZ;
                // Farthest corner from the origin.
                long farX = Math.max(Math.abs(minX), Math.abs(minX + 15));
                long farZ = Math.max(Math.abs(minZ), Math.abs(minZ + 15));
                long farSq = farX * farX + farZ * farZ;
                if (nearSq <= outerSq && farSq >= innerSq) {
                    chunks.add(new ChunkPos(cx, cz));
                }
            }
        }
        return chunks;
    }

    private static long clampToRange(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    // --- save paths ---

    /**
     * One chunk's snapshot tag: from the live chunk when loaded, else lifted straight from
     * region NBT. {@code null} = never generated (or unreadable) — skipped, chunkgen covers.
     */
    @Nullable
    private static CompoundTag serializeChunk(ServerLevel level, ChunkPos pos) {
        LevelChunk live = level.getChunkSource().getChunkNow(pos.x, pos.z);
        if (live != null) {
            return serializeLiveChunk(level, live);
        }
        Optional<CompoundTag> diskTag;
        try {
            diskTag = level.getChunkSource().chunkMap.read(pos).join();
        } catch (RuntimeException e) {
            EclipseMod.LOGGER.warn("StageIO: failed to read chunk {} from region storage", pos, e);
            return null;
        }
        if (diskTag.isEmpty() || PRE_NOISE_STATUSES.contains(diskTag.get().getString("Status"))
                || diskTag.get().getString("Status").isEmpty()) {
            return null;
        }
        return serializeDiskChunk(level, pos, diskTag.get());
    }

    private static CompoundTag serializeLiveChunk(ServerLevel level, LevelChunk chunk) {
        CompoundTag chunkTag = new CompoundTag();
        chunkTag.putLong("pos", chunk.getPos().toLong());
        ListTag sections = new ListTag();
        for (int index = 0; index < chunk.getSectionsCount(); index++) {
            LevelChunkSection section = chunk.getSection(index);
            CompoundTag sectionTag = new CompoundTag();
            sectionTag.putInt("y", level.getSectionYFromSectionIndex(index));
            sectionTag.put("states",
                    BLOCK_STATE_CODEC.encodeStart(NbtOps.INSTANCE, section.getStates()).getOrThrow());
            sections.add(sectionTag);
        }
        chunkTag.put("sections", sections);
        ListTag blockEntities = new ListTag();
        for (BlockPos bePos : List.copyOf(chunk.getBlockEntitiesPos())) {
            CompoundTag beTag = chunk.getBlockEntityNbtForSaving(bePos, level.registryAccess());
            if (beTag != null) {
                blockEntities.add(beTag);
            }
        }
        chunkTag.put("blockEntities", blockEntities);
        return chunkTag;
    }

    /** Region NBT uses the same palette codec — lift {@code block_states} + BEs verbatim. */
    private static CompoundTag serializeDiskChunk(ServerLevel level, ChunkPos pos, CompoundTag diskTag) {
        CompoundTag chunkTag = new CompoundTag();
        chunkTag.putLong("pos", pos.toLong());
        Map<Integer, CompoundTag> statesByY = new HashMap<>();
        for (Tag entry : diskTag.getList("sections", Tag.TAG_COMPOUND)) {
            CompoundTag sectionTag = (CompoundTag) entry;
            if (sectionTag.contains("block_states")) {
                statesByY.put((int) sectionTag.getByte("Y"), sectionTag.getCompound("block_states"));
            }
        }
        ListTag sections = new ListTag();
        for (int index = 0; index < level.getSectionsCount(); index++) {
            int sectionY = level.getSectionYFromSectionIndex(index);
            CompoundTag sectionTag = new CompoundTag();
            sectionTag.putInt("y", sectionY);
            CompoundTag states = statesByY.get(sectionY);
            sectionTag.put("states", states != null ? states : airStatesTag());
            sections.add(sectionTag);
        }
        chunkTag.put("sections", sections);
        ListTag blockEntities = new ListTag();
        for (Tag entry : diskTag.getList("block_entities", Tag.TAG_COMPOUND)) {
            blockEntities.add(entry.copy());
        }
        chunkTag.put("blockEntities", blockEntities);
        return chunkTag;
    }

    /** An all-air {@code block_states} compound (palette-only, no data array). */
    private static CompoundTag airStatesTag() {
        PalettedContainer<BlockState> air = new PalettedContainer<>(Block.BLOCK_STATE_REGISTRY,
                Blocks.AIR.defaultBlockState(), PalettedContainer.Strategy.SECTION_STATES);
        return (CompoundTag) BLOCK_STATE_CODEC.encodeStart(NbtOps.INSTANCE, air).getOrThrow();
    }

    // --- the tick-budgeted apply job ---

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (LOAD_JOBS.isEmpty()) {
            return;
        }
        for (LoadJob job : List.copyOf(LOAD_JOBS.values())) {
            job.tick();
            if (job.done) {
                LOAD_JOBS.remove(job.profile, job);
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        LOAD_JOBS.clear();
    }

    private static final class LoadJob {
        final ServerLevel level;
        final DiscProfile profile;
        final int stage;
        final List<CompoundTag> chunks;
        final long startedAtNanos = System.nanoTime();
        int cursor;
        boolean done;

        LoadJob(ServerLevel level, DiscProfile profile, int stage, ListTag chunkList) {
            this.level = level;
            this.profile = profile;
            this.stage = stage;
            List<CompoundTag> parsed = new ArrayList<>(chunkList.size());
            for (Tag entry : chunkList) {
                parsed.add((CompoundTag) entry);
            }
            this.chunks = parsed;
        }

        void tick() {
            long budgetNanos = LOAD_BUDGET_MS * 1_000_000L;
            long start = System.nanoTime();
            int applied = 0;
            while (this.cursor < this.chunks.size() && applied < MAX_CHUNKS_PER_TICK
                    && System.nanoTime() - start < budgetNanos) {
                applyChunk(this.chunks.get(this.cursor));
                this.cursor++;
                applied++;
            }
            if (this.cursor % 50 < applied && this.cursor < this.chunks.size()) {
                EclipseMod.LOGGER.info("StageIO: applying {} stage {} snapshot — {}/{} chunks",
                        this.profile.name(), this.stage, this.cursor, this.chunks.size());
            }
            if (this.cursor >= this.chunks.size()) {
                this.done = true;
                EclipseWorldState.get(this.level.getServer()).setLastLoadedStage(this.profile, this.stage);
                double seconds = (System.nanoTime() - this.startedAtNanos) / 1.0e9D;
                EclipseMod.LOGGER.info(
                        "StageIO: {} stage {} snapshot applied — {} chunks in {} s (lastLoadedStage persisted)",
                        this.profile.name(), this.stage, this.chunks.size(),
                        String.format(Locale.ROOT, "%.1f", seconds));
            }
        }

        /** Rewrites one chunk's sections + block entities from the snapshot, then relight + resend. */
        private void applyChunk(CompoundTag chunkTag) {
            ChunkPos pos = new ChunkPos(chunkTag.getLong("pos"));
            LevelChunk chunk = this.level.getChunkSource().getChunkNow(pos.x, pos.z);
            if (chunk == null) {
                chunk = BudgetedBlockWriter.loadWithTicket(this.level, pos.x, pos.z);
            }

            for (Tag entry : chunkTag.getList("sections", Tag.TAG_COMPOUND)) {
                CompoundTag sectionTag = (CompoundTag) entry;
                int sectionY = sectionTag.getInt("y");
                if (sectionY < this.level.getMinSection() || sectionY >= this.level.getMaxSection()) {
                    continue;
                }
                PalettedContainer<BlockState> saved = BLOCK_STATE_CODEC
                        .parse(NbtOps.INSTANCE, sectionTag.getCompound("states"))
                        .resultOrPartial(message -> EclipseMod.LOGGER.warn(
                                "StageIO: bad section {} in chunk {}: {}", sectionY, pos, message))
                        .orElse(null);
                if (saved == null) {
                    continue;
                }
                LevelChunkSection section = chunk.getSection(this.level.getSectionIndexFromSectionY(sectionY));
                boolean savedHasBlocks = saved.maybeHas(state -> !state.isAir());
                if (!savedHasBlocks && section.hasOnlyAir()) {
                    continue;
                }
                for (int y = 0; y < 16; y++) {
                    for (int z = 0; z < 16; z++) {
                        for (int x = 0; x < 16; x++) {
                            section.setBlockState(x, y, z, saved.get(x, y, z), false);
                        }
                    }
                }
            }

            // Chunk-granular block entity restore: drop everything live, recreate from the file.
            for (BlockPos bePos : List.copyOf(chunk.getBlockEntitiesPos())) {
                chunk.removeBlockEntity(bePos);
            }
            for (Tag entry : chunkTag.getList("blockEntities", Tag.TAG_COMPOUND)) {
                CompoundTag beTag = (CompoundTag) entry;
                BlockPos bePos = new BlockPos(beTag.getInt("x"), beTag.getInt("y"), beTag.getInt("z"));
                BlockEntity blockEntity = BlockEntity.loadStatic(bePos, chunk.getBlockState(bePos),
                        beTag, this.level.registryAccess());
                if (blockEntity != null) {
                    chunk.setBlockEntity(blockEntity);
                }
            }

            Heightmap.primeHeightmaps(chunk, java.util.EnumSet.of(
                    Heightmap.Types.WORLD_SURFACE, Heightmap.Types.OCEAN_FLOOR,
                    Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES));
            BudgetedBlockWriter.relightAndResend(this.level, chunk);
        }
    }
}
