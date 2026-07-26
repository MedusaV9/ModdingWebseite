package dev.projecteclipse.eclipse.worldgen;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction.DiscColumn;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.RingGrowthService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.ChunkAccess;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.material.FluidState;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.level.ChunkEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Self-healing repair pass for the two disc-integrity defects the ring-growth sweep can
 * leave behind, driven lazily off chunk load with a per-tick budget.
 *
 * <h2>F-025 — void columns inside structure protection boxes</h2>
 * {@code RingGrowthService} skips every column that lies inside a stamped landmark's
 * no-write box, so a column that was VOID when the box was created (the previous stage's
 * rim taper / crumble band, or a chunk that chunkgen produced at the old stage while
 * {@code SitePrep} force-loaded the site) is never rewritten and stays a permanent hole.
 * Landmarks that sit close to a stage rim are hit hardest — in the dev save the
 * {@code eclipse:desert_temple} box at {@code (165, 99)} straddles the stage-2 rim
 * (r ≈ 210) and holds ~1.5 k void columns, i.e. exactly the "leere Chunks beim
 * Mesa/Savannen-Biome wo die Pyramide entsteht" of the report.
 *
 * <p>The root cause is fixed in the sweep itself (protection now only skips columns that
 * actually CONTAIN something — see {@link #isVoidColumn}); this service is the migration
 * for saves that already have the holes, and the safety net if a hole ever appears
 * again. It only ever ADDS blocks, and only in columns that are void from bedrock to sky
 * inside a protection box, so nothing a player or a structure built can be overwritten.</p>
 *
 * <h2>F-026 — melting ice / running water on the snow mountain</h2>
 * Delegated to {@link SnowMountainFrost#refreeze}: flowing water goes, water sources and
 * plain ice become glacier ice. Because chunk load re-runs it, ice that somehow melted
 * while the chunk was loaded is re-frozen the next time it comes back.
 *
 * <h2>Scheduling</h2>
 * {@link ChunkEvent.Load} may fire off the server thread and before the chunk is fully
 * promoted, so it only records the position; the work happens on
 * {@link ServerTickEvent.Post} against {@code getChunkNow} (stale entries are dropped),
 * at most {@value #CHUNKS_PER_TICK} chunks per tick. Repairs are suppressed while a ring
 * sweep is running for the profile — the sweep writes the same columns — and a stage
 * change re-enqueues the already-loaded protected chunks so holes never survive a growth
 * event just because the player never left the area.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class DiscRepairService {
    /** Chunks inspected per server tick. Almost all of them exit on a heightmap read. */
    private static final int CHUNKS_PER_TICK = 2;
    /** Backpressure cap — a world-gen burst must never grow the queue without bound. */
    private static final int MAX_QUEUE = 8192;
    /** Stage-change poll interval. */
    private static final int STAGE_POLL_TICKS = 20;

    /** Sweep parity ({@code RingGrowthService} / {@code ChunkRegen}): XZ pad of a box. */
    private static final int STRUCTURE_PROTECTION_MARGIN = 8;
    /** Sweep parity: measured half-extent of a stamped village. */
    private static final int VILLAGE_PROTECTION_EXTENT = 64;
    /** Sweep parity: measured half-extent of a stamped temple. */
    private static final int TEMPLE_PROTECTION_EXTENT = 24;

    private static final EnumSet<Heightmap.Types> HEIGHTMAPS_TO_PRIME = EnumSet.of(
            Heightmap.Types.WORLD_SURFACE, Heightmap.Types.OCEAN_FLOOR,
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES);

    /** The disc profiles this service repairs (both discs use the same sweep machinery). */
    private static final List<DiscProfile> PROFILES = List.of(DiscProfile.OVERWORLD, DiscProfile.NETHER);

    private static final Queue<Pending> QUEUE = new ConcurrentLinkedQueue<>();
    private static final Set<Pending> ENQUEUED = ConcurrentHashMap.newKeySet();
    private static final Map<DiscProfile, Integer> LAST_STAGE = new HashMap<>();

    private static long columnsFilled;
    private static long blocksFrozen;
    private static long chunksRepaired;

    private DiscRepairService() {}

    /** One queued chunk. Identity-keyed on the level so multi-dimension saves stay separate. */
    private record Pending(ServerLevel level, long chunkKey) {}

    // ------------------------------------------------------------------ public seam

    /**
     * Whether the column holds no block at all between the world floor and the world top.
     * Fast path: the {@code WORLD_SURFACE} heightmap answers "not void" in O(1); only
     * candidates pay the section walk, and that walk is dominated by empty-section skips.
     *
     * <p>Used by {@code RingGrowthService} to keep a structure's no-write box from
     * protecting nothing but air (F-025) — a column with no blocks has nothing worth
     * protecting, and leaving it out of the sweep is what turns it into a permanent hole.</p>
     */
    public static boolean isVoidColumn(ChunkAccess chunk, int x, int z) {
        if (chunk.getHeight(Heightmap.Types.WORLD_SURFACE, x, z) >= chunk.getMinBuildHeight()) {
            return false;
        }
        int lx = x & 15;
        int lz = z & 15;
        for (int index = 0; index < chunk.getSectionsCount(); index++) {
            LevelChunkSection section = chunk.getSection(index);
            if (section.hasOnlyAir()) {
                continue;
            }
            for (int dy = 0; dy < 16; dy++) {
                if (!section.getBlockState(lx, dy, lz).isAir()) {
                    return false;
                }
            }
        }
        return true;
    }

    // ------------------------------------------------------------------ events

    /**
     * Records the position only. The event can fire off the server thread and before the
     * chunk is promoted to a {@code LevelChunk}, so no block work may happen here.
     */
    @SubscribeEvent
    public static void onChunkLoad(ChunkEvent.Load event) {
        if (!(event.getLevel() instanceof ServerLevel level)
                || !(level.getChunkSource().getGenerator() instanceof DiscChunkGenerator)) {
            return; // not a disc dimension (nether hub, limbo, backrooms, …)
        }
        enqueue(level, event.getChunk().getPos().toLong());
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % STAGE_POLL_TICKS == 0) {
            pollStageChange(server);
        }
        for (int done = 0; done < CHUNKS_PER_TICK; done++) {
            Pending pending = QUEUE.poll();
            if (pending == null) {
                return;
            }
            ENQUEUED.remove(pending);
            if (pending.level().getServer() != server) {
                continue;
            }
            process(pending.level(), pending.chunkKey());
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        QUEUE.clear();
        ENQUEUED.clear();
        LAST_STAGE.clear();
        columnsFilled = 0L;
        blocksFrozen = 0L;
        chunksRepaired = 0L;
    }

    // ------------------------------------------------------------------ scheduling

    private static void enqueue(ServerLevel level, long chunkKey) {
        if (ENQUEUED.size() >= MAX_QUEUE) {
            return; // ENQUEUED, not QUEUE: ConcurrentLinkedQueue.size() walks the whole list
        }
        Pending pending = new Pending(level, chunkKey);
        if (ENQUEUED.add(pending)) {
            QUEUE.add(pending);
        }
    }

    /**
     * A committed stage change means the growth sweep just rewrote an annulus and skipped
     * whatever lies inside the protection boxes. Re-enqueue the loaded chunks of those
     * boxes so a player standing next to a landmark sees the repair immediately instead of
     * after a reload. Deliberately waits for the sweep to finish first.
     */
    private static void pollStageChange(MinecraftServer server) {
        for (DiscProfile profile : PROFILES) {
            int stage = WorldStageAccess.stage(profile);
            if (LAST_STAGE.getOrDefault(profile, Integer.MIN_VALUE) == stage
                    || RingGrowthService.isRunning(profile)) {
                continue;
            }
            LAST_STAGE.put(profile, stage);
            ServerLevel level = levelFor(server, profile);
            if (level == null || stage <= 0) {
                continue;
            }
            int enqueued = 0;
            for (Box box : protectionBoxes(DiscMapData.get(), profile, stage)) {
                for (int cx = box.minX() >> 4; cx <= box.maxX() >> 4; cx++) {
                    for (int cz = box.minZ() >> 4; cz <= box.maxZ() >> 4; cz++) {
                        if (level.getChunkSource().getChunkNow(cx, cz) != null) {
                            enqueue(level, ChunkPos.asLong(cx, cz));
                            enqueued++;
                        }
                    }
                }
            }
            if (enqueued > 0) {
                EclipseMod.LOGGER.info(
                        "Disc repair: stage {} committed for {}, re-checking {} loaded protected chunk(s)",
                        stage, profile.name(), enqueued);
            }
        }
    }

    /** The server level backing a disc profile, or null when it is not a disc dimension. */
    private static ServerLevel levelFor(MinecraftServer server, DiscProfile profile) {
        for (ServerLevel level : server.getAllLevels()) {
            if (level.getChunkSource().getGenerator() instanceof DiscChunkGenerator generator
                    && generator.profile() == profile) {
                return level;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ repair

    private static void process(ServerLevel level, long chunkKey) {
        if (!(level.getChunkSource().getGenerator() instanceof DiscChunkGenerator generator)) {
            return;
        }
        DiscProfile profile = generator.profile();
        if (RingGrowthService.isRunning(profile)) {
            enqueue(level, chunkKey); // retry once the sweep released the annulus
            return;
        }
        LevelChunk chunk = level.getChunkSource()
                .getChunkNow(ChunkPos.getX(chunkKey), ChunkPos.getZ(chunkKey));
        if (chunk == null) {
            return; // unloaded again between the event and this tick
        }
        int filled = fillProtectedVoidColumns(level, chunk, profile);
        int frozen = SnowMountainFrost.refreeze(level, chunk, profile);
        if (filled == 0 && frozen == 0) {
            return;
        }
        if (filled > 0) {
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS_TO_PRIME);
            BudgetedBlockWriter.relightAndResend(level, chunk);
        }
        chunk.setUnsaved(true);
        columnsFilled += filled;
        blocksFrozen += frozen;
        chunksRepaired++;
        EclipseMod.LOGGER.info(
                "Disc repair {} at {}: {} void column(s) filled, {} block(s) re-frozen "
                        + "(totals: {} columns / {} blocks / {} chunks)",
                profile.name(), chunk.getPos(), filled, frozen,
                columnsFilled, blocksFrozen, chunksRepaired);
    }

    /**
     * F-025 migration: rebuilds the columns of this chunk that are entirely void although
     * the terrain function says the committed stage covers them, restricted to the
     * landmark no-write boxes — the only place the sweep can leave a hole.
     *
     * <p>Player builds are safe by construction: {@link DiscTerrainFunction} floors every
     * non-shard column with three layers of bedrock, so a column that a player mined out
     * still reports its bedrock and can never be seen as void. "No block between the world
     * floor and the world top" only ever means "chunkgen wrote nothing here".</p>
     *
     * <p>Repaired columns get terrain, strata, caves and ores (all of which the terrain
     * function owns) but no vegetation: replaying decoration inside a protection box would
     * let features chew into the stamped structure, which is exactly what the box is for.
     * Bare ground next to a landmark beats a hole through the world.</p>
     */
    private static int fillProtectedVoidColumns(ServerLevel level, LevelChunk chunk,
            DiscProfile profile) {
        int stage = WorldStageAccess.stage(profile);
        if (stage <= 0) {
            return 0;
        }
        DiscMapData map = DiscMapData.get();
        ChunkPos pos = chunk.getPos();
        List<Box> boxes = protectionBoxes(map, profile, stage);
        boolean overlaps = false;
        for (Box box : boxes) {
            if (box.overlapsChunk(pos)) {
                overlaps = true;
                break;
            }
        }
        if (!overlaps) {
            return 0;
        }
        int filled = 0;
        for (int lx = 0; lx < 16; lx++) {
            int x = pos.getMinBlockX() + lx;
            for (int lz = 0; lz < 16; lz++) {
                int z = pos.getMinBlockZ() + lz;
                if (!inAnyBox(boxes, x, z) || !isVoidColumn(chunk, x, z)) {
                    continue;
                }
                DiscColumn column = DiscTerrainFunction.column(profile, x, z, stage, map);
                if (!column.inside()) {
                    continue; // legitimately void: beyond the rim, or a crumble hole
                }
                fillColumn(level, chunk, column);
                filled++;
            }
        }
        return filled;
    }

    /**
     * Writes the terrain function's blocks straight into the chunk sections, exactly like
     * the sweep's column rewrite. Air is skipped: the column was proven void, so this pass
     * only ever adds, and a decoration block a neighbouring feature leaked in cannot be
     * erased by it. Fluids get a scheduled tick because section writes fire no updates.
     */
    private static void fillColumn(ServerLevel level, LevelChunk chunk, DiscColumn column) {
        int lx = column.x() & 15;
        int lz = column.z() & 15;
        for (int index = 0; index < chunk.getSectionsCount(); index++) {
            int sectionMinY = SectionPos.sectionToBlockCoord(
                    level.getSectionYFromSectionIndex(index));
            if (column.topY() < sectionMinY || column.bottomY() > sectionMinY + 15) {
                continue;
            }
            LevelChunkSection section = chunk.getSection(index);
            for (int dy = 0; dy < 16; dy++) {
                int y = sectionMinY + dy;
                BlockState state = DiscTerrainFunction.stateInColumn(column, y);
                if (state.isAir()) {
                    continue;
                }
                section.setBlockState(lx, dy, lz, state, false);
                FluidState fluid = state.getFluidState();
                if (!fluid.isEmpty()) {
                    level.scheduleTick(new BlockPos(column.x(), y, column.z()),
                            fluid.getType(), fluid.getType().getTickDelay(level));
                }
            }
        }
    }

    // ------------------------------------------------------------------ protection boxes

    /** Axis-aligned XZ no-write box of one stamped landmark (sweep parity). */
    private record Box(int minX, int minZ, int maxX, int maxZ) {
        boolean contains(int x, int z) {
            return x >= this.minX && x <= this.maxX && z >= this.minZ && z <= this.maxZ;
        }

        boolean overlapsChunk(ChunkPos pos) {
            return pos.getMaxBlockX() >= this.minX && pos.getMinBlockX() <= this.maxX
                    && pos.getMaxBlockZ() >= this.minZ && pos.getMinBlockZ() <= this.maxZ;
        }
    }

    private static boolean inAnyBox(List<Box> boxes, int x, int z) {
        for (Box box : boxes) {
            if (box.contains(x, z)) {
                return true;
            }
        }
        return false;
    }

    /** The no-write boxes of every landmark stamped through {@code stage} (sweep parity). */
    private static List<Box> protectionBoxes(DiscMapData map, DiscProfile profile, int stage) {
        List<Box> boxes = new ArrayList<>();
        for (DiscMapData.Landmark landmark : map.landmarks(profile)) {
            if (landmark.stage() > stage) {
                continue;
            }
            int extent = protectionExtent(landmark) + STRUCTURE_PROTECTION_MARGIN;
            boxes.add(new Box(landmark.x() - extent, landmark.z() - extent,
                    landmark.x() + extent, landmark.z() + extent));
        }
        return boxes;
    }

    private static int protectionExtent(DiscMapData.Landmark landmark) {
        if (landmark.id().contains("village")) {
            return VILLAGE_PROTECTION_EXTENT;
        }
        if (landmark.id().contains("temple")) {
            return TEMPLE_PROTECTION_EXTENT;
        }
        return landmark.radius();
    }
}
