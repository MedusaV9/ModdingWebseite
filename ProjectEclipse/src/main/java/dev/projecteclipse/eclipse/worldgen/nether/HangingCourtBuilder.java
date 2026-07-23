package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.FrozenParams;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import dev.projecteclipse.eclipse.worldgen.structure.SitePrep;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry;
import dev.projecteclipse.eclipse.worldgen.structure.StructurePendingRegistry.PendingSite;
import dev.projecteclipse.eclipse.worldgen.structure.VanillaLandmarks;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.LadderBlock;
import net.minecraft.world.level.block.LanternBlock;
import net.minecraft.world.level.block.entity.RandomizableContainerBlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.storage.loot.LootTable;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Stage-2 Nether set pieces owned by W1.7:
 *
 * <ul>
 *   <li>the procedural inverted-bastion {@value #COURT_SITE_ID}, suspended below the
 *       Nether disc by chains and reached through two ladder shafts,</li>
 *   <li>the top-side vanilla bastion-remnant pending site.</li>
 * </ul>
 *
 * <p>Both enter W1.6's two-phase registry. The Court is an async placer: its pending row
 * stays persisted until the measured block job calls completion. A hidden
 * reinforced-deepslate marker also repairs saves made by the older synchronous seam.
 * All generated writes are deterministic and safe to replay.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class HangingCourtBuilder {
    public static final String COURT_SITE_ID = "eclipse:hanging_court";
    public static final String BASTION_SITE_ID = "eclipse:bastion_remnant";

    private static final String COURT_STRUCTURE_ID = "eclipse:hanging_court";
    private static final String BASTION_STRUCTURE_ID = "minecraft:bastion_remnant";
    private static final int STAGE = 2;
    private static final int FOOTPRINT = 40;
    private static final int PLATFORM_HALF = 14;
    private static final long WRITE_BUDGET_NANOS = 3_000_000L;
    private static final int MAX_WRITES_PER_TICK = 4096;
    private static final int MAX_FINALIZE_CHUNKS_PER_TICK = 2;

    private static final ResourceKey<LootTable> LOOT = ResourceKey.create(Registries.LOOT_TABLE,
            ResourceLocation.fromNamespaceAndPath(EclipseMod.MOD_ID, "nether/hanging_court"));
    private static final Set<Heightmap.Types> HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR, Heightmap.Types.WORLD_SURFACE);

    private static boolean listenerRegistered;
    private static MinecraftServer bootstrapServer;
    private static int bootstrapTick;
    private static BuildJob active;

    private HangingCourtBuilder() {}

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        StructurePendingRegistry.registerAsyncPlacer(COURT_STRUCTURE_ID,
                (level, site, onComplete, onFailure) ->
                        schedule(level, site.anchor(), onComplete, onFailure));
        StructurePendingRegistry.registerAsyncPlacer(BASTION_STRUCTURE_ID,
                HangingCourtBuilder::placeBastion);
        if (!listenerRegistered) {
            WorldStageService.addListener(HangingCourtBuilder::onStageTerrainComplete);
            listenerRegistered = true;
        }
        // Defer backfill until the first tick so StructurePendingRegistry has loaded its
        // persisted pending/placed rows regardless of ServerStarted listener order.
        bootstrapServer = event.getServer();
        bootstrapTick = event.getServer().getTickCount() + 1;
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (bootstrapServer == server && server.getTickCount() >= bootstrapTick) {
            bootstrapServer = null;
            if (WorldStageService.stage(server, DiscProfile.NETHER) >= STAGE) {
                ServerLevel nether = server.getLevel(Level.NETHER);
                if (nether != null) {
                    enqueueStageSites(nether);
                }
            }
        }

        // If the registry says placed but the final marker is absent, the previous process
        // stopped mid-job. Deterministically replay instead of leaving a half-court forever.
        if (active == null && StructurePendingRegistry.wasPlaced(COURT_SITE_ID)
                && WorldStageService.stage(server, DiscProfile.NETHER) >= STAGE) {
            ServerLevel nether = server.getLevel(Level.NETHER);
            DiscMapData.Landmark landmark = landmark(COURT_SITE_ID);
            if (nether != null && landmark != null) {
                BlockPos anchor = courtAnchor(landmark);
                BudgetedBlockWriter.loadWithTicket(nether, anchor.getX() >> 4, anchor.getZ() >> 4);
                if (!nether.getBlockState(completionMarker(anchor)).is(Blocks.REINFORCED_DEEPSLATE)) {
                    scheduleRepair(nether, anchor);
                }
            }
        }

        BuildJob job = active;
        if (job != null && job.server == server) {
            try {
                if (job.tick()) {
                    active = null;
                }
            } catch (Throwable error) {
                active = null;
                job.fail(error);
            }
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        if (active != null && active.server == event.getServer()) {
            active = null;
        }
        if (bootstrapServer == event.getServer()) {
            bootstrapServer = null;
        }
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile == DiscProfile.NETHER && fromStage < STAGE && toStage >= STAGE) {
            enqueueStageSites(level);
        }
    }

    private static void enqueueStageSites(ServerLevel nether) {
        long gameTime = nether.getGameTime();
        DiscMapData.Landmark court = landmark(COURT_SITE_ID);
        if (court != null) {
            StructurePendingRegistry.enqueue(new PendingSite(
                    COURT_SITE_ID, COURT_STRUCTURE_ID, DiscProfile.NETHER.name(),
                    courtAnchor(court), STAGE, FOOTPRINT, gameTime));
        } else {
            EclipseMod.LOGGER.warn("No {} landmark in disc_map.json; Hanging Court skipped",
                    COURT_SITE_ID);
        }

        DiscMapData.Landmark bastion = landmark(BASTION_SITE_ID);
        if (bastion != null) {
            int y = DiscTerrainFunction.surfaceY(DiscProfile.NETHER, bastion.x(), bastion.z()) + 1;
            StructurePendingRegistry.enqueue(new PendingSite(
                    BASTION_SITE_ID, BASTION_STRUCTURE_ID, DiscProfile.NETHER.name(),
                    new BlockPos(bastion.x(), y, bastion.z()), STAGE,
                    Math.max(48, bastion.radius() * 2), gameTime));
        } else {
            EclipseMod.LOGGER.warn("No {} landmark in disc_map.json; bastion remnant skipped",
                    BASTION_SITE_ID);
        }
    }

    private static void placeBastion(ServerLevel level, PendingSite site,
            Runnable onComplete, Consumer<Throwable> onFailure) {
        if (VanillaLandmarks.placeVanillaAsync(level,
                ResourceLocation.withDefaultNamespace("bastion_remnant"),
                site.anchor(), SitePrep.Mode.PLATEAU, ignored -> onComplete.run(), onFailure) == null) {
            onFailure.accept(new IllegalStateException(
                    "minecraft:bastion_remnant refused authored site " + site.siteId()
                            + " at " + site.anchor().toShortString()));
        }
    }

    private static void schedule(ServerLevel level, BlockPos anchor,
            Runnable onComplete, Consumer<Throwable> onFailure) {
        if (level.dimension() != Level.NETHER) {
            onFailure.accept(new IllegalArgumentException(
                    "Hanging Court placer called in " + level.dimension().location()));
            return;
        }
        if (active != null && active.server == level.getServer()) {
            onFailure.accept(new IllegalStateException("A Hanging Court build is already active"));
            return;
        }
        active = new BuildJob(level, anchor, onComplete, onFailure);
        EclipseMod.LOGGER.info("Hanging Court budgeted build queued at {}", anchor.toShortString());
    }

    /** Marker-repair replay has no pending-registry row to complete. */
    private static void scheduleRepair(ServerLevel level, BlockPos anchor) {
        schedule(level, anchor, () -> {},
                error -> EclipseMod.LOGGER.error("Hanging Court repair failed", error));
    }

    private static DiscMapData.Landmark landmark(String id) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(DiscProfile.NETHER)) {
            if (id.equals(landmark.id())) {
                return landmark;
            }
        }
        return null;
    }

    private static BlockPos courtAnchor(DiscMapData.Landmark landmark) {
        int underside = DiscTerrainFunction.column(
                DiscProfile.NETHER, landmark.x(), landmark.z(), STAGE).groundBottomY();
        int floorY = Math.max(DiscProfile.NETHER.minY() + 12, underside - 18);
        return new BlockPos(landmark.x(), floorY, landmark.z());
    }

    private static BlockPos completionMarker(BlockPos anchor) {
        return anchor.below(2);
    }

    private record BlockWrite(BlockPos pos, BlockState state) {}

    private static final class BuildJob {
        private final MinecraftServer server;
        private final ServerLevel level;
        private final BlockPos anchor;
        private final List<BlockWrite> writes;
        private final List<BlockPos> chests;
        private final Runnable onComplete;
        private final Consumer<Throwable> onFailure;
        private final Set<Long> touched = new HashSet<>();
        private int cursor;
        private List<Long> finalizeChunks;
        private int finalizeCursor;
        private boolean lootApplied;

        private BuildJob(ServerLevel level, BlockPos anchor,
                Runnable onComplete, Consumer<Throwable> onFailure) {
            this.server = level.getServer();
            this.level = level;
            this.anchor = anchor;
            this.onComplete = onComplete;
            this.onFailure = onFailure;
            BuildPlan plan = buildPlan(anchor);
            this.writes = plan.writes();
            this.chests = plan.chests();
        }

        private boolean tick() {
            long deadline = System.nanoTime() + WRITE_BUDGET_NANOS;
            int count = 0;
            while (this.cursor < this.writes.size()
                    && count < MAX_WRITES_PER_TICK
                    && System.nanoTime() < deadline) {
                apply(this.writes.get(this.cursor++));
                count++;
            }
            if (this.cursor < this.writes.size()) {
                return false;
            }
            if (!this.lootApplied) {
                for (BlockPos chestPos : this.chests) {
                    if (this.level.getBlockEntity(chestPos)
                            instanceof RandomizableContainerBlockEntity chest) {
                        chest.setLootTable(LOOT, FrozenParams.mapSeed() ^ chestPos.asLong());
                    }
                }
                this.lootApplied = true;
                this.finalizeChunks = new ArrayList<>(this.touched);
            }

            int finalized = 0;
            while (this.finalizeCursor < this.finalizeChunks.size()
                    && finalized < MAX_FINALIZE_CHUNKS_PER_TICK
                    && System.nanoTime() < deadline) {
                long key = this.finalizeChunks.get(this.finalizeCursor++);
                LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(this.level,
                        ChunkPos.getX(key), ChunkPos.getZ(key));
                Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
                BudgetedBlockWriter.relightAndResend(this.level, chunk);
                finalized++;
            }
            if (this.finalizeCursor < this.finalizeChunks.size()) {
                return false;
            }
            apply(new BlockWrite(completionMarker(this.anchor),
                    Blocks.REINFORCED_DEEPSLATE.defaultBlockState()));
            EclipseMod.LOGGER.info("Hanging Court complete at {}: {} blocks across {} chunk(s)",
                    this.anchor.toShortString(), this.writes.size(), this.touched.size());
            this.onComplete.run();
            return true;
        }

        private void fail(Throwable error) {
            this.onFailure.accept(error);
        }

        private void apply(BlockWrite write) {
            BlockPos pos = write.pos();
            if (pos.getY() < this.level.getMinBuildHeight()
                    || pos.getY() >= this.level.getMaxBuildHeight()) {
                return;
            }
            long key = ChunkPos.asLong(pos.getX() >> 4, pos.getZ() >> 4);
            if (this.touched.add(key)) {
                BudgetedBlockWriter.loadWithTicket(this.level, pos.getX() >> 4, pos.getZ() >> 4);
            }
            if (!this.level.getBlockState(pos).equals(write.state())) {
                this.level.setBlock(pos, write.state(),
                        Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
            }
        }
    }

    private record BuildPlan(List<BlockWrite> writes, List<BlockPos> chests) {}

    private static BuildPlan buildPlan(BlockPos anchor) {
        List<BlockWrite> writes = new ArrayList<>();
        List<BlockPos> chests = new ArrayList<>();
        int cx = anchor.getX();
        int floorY = anchor.getY();
        int cz = anchor.getZ();
        BlockState bricks = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState cracked = Blocks.CRACKED_POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        BlockState air = Blocks.AIR.defaultBlockState();

        // Broad diamond court, chipped at deterministic edge positions.
        for (int dx = -PLATFORM_HALF; dx <= PLATFORM_HALF; dx++) {
            for (int dz = -PLATFORM_HALF; dz <= PLATFORM_HALF; dz++) {
                int taxi = Math.abs(dx) + Math.abs(dz);
                if (taxi > PLATFORM_HALF + 6
                        || (taxi > PLATFORM_HALF + 3 && hash01(cx + dx, floorY, cz + dz) < 0.28D)) {
                    continue;
                }
                BlockPos floor = new BlockPos(cx + dx, floorY, cz + dz);
                writes.add(new BlockWrite(floor.below(), Blocks.BLACKSTONE.defaultBlockState()));
                BlockState tile = hash01(cx + dx, floorY + 17, cz + dz) < 0.16D
                        ? cracked : bricks;
                if (Math.abs(dx) <= 3 && Math.abs(dz) <= 3
                        && hash01(cx + dx, floorY + 31, cz + dz) < 0.20D) {
                    tile = Blocks.GILDED_BLACKSTONE.defaultBlockState();
                }
                writes.add(new BlockWrite(floor, tile));
                for (int dy = 1; dy <= 5; dy++) {
                    writes.add(new BlockWrite(floor.above(dy), air));
                }
                if (taxi >= PLATFORM_HALF + 3
                        && hash01(cx + dx, floorY + 41, cz + dz) > 0.38D) {
                    writes.add(new BlockWrite(floor.above(), Blocks.POLISHED_BLACKSTONE_BRICK_WALL
                            .defaultBlockState()));
                }
            }
        }

        // Four hollow ruined corner towers with long inverted basalt roots.
        for (int sx : new int[] {-10, 10}) {
            for (int sz : new int[] {-10, 10}) {
                tower(writes, cx + sx, floorY, cz + sz);
                invertedRoot(writes, cx + sx, floorY - 2, cz + sz);
                chainToUnderside(writes, cx + sx, floorY + 8, cz + sz);
            }
        }

        // Broken central nave/arches; cardinal gaps keep every quadrant connected.
        for (Direction direction : Direction.Plane.HORIZONTAL) {
            Direction side = direction.getClockWise();
            for (int lateral = -7; lateral <= 7; lateral++) {
                if (Math.abs(lateral) <= 2) {
                    continue;
                }
                BlockPos wall = new BlockPos(cx, floorY, cz)
                        .relative(direction, 7).relative(side, lateral);
                for (int dy = 1; dy <= 4; dy++) {
                    if (dy == 4 && (lateral & 1) != 0) {
                        continue;
                    }
                    writes.add(new BlockWrite(wall.above(dy),
                            dy == 4 ? Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState()
                                    : bricks));
                }
            }
        }

        // Two guaranteed shafts pierce the disc and descend onto opposite court wings.
        ladderShaft(writes, cx - 8, floorY, cz);
        ladderShaft(writes, cx + 8, floorY, cz);

        // Court lighting and deterministic treasure.
        for (int sx : new int[] {-5, 5}) {
            BlockPos chain = new BlockPos(cx + sx, floorY + 5, cz);
            writes.add(new BlockWrite(chain, Blocks.CHAIN.defaultBlockState()));
            writes.add(new BlockWrite(chain.below(), Blocks.SOUL_LANTERN.defaultBlockState()
                    .setValue(LanternBlock.HANGING, true)));
        }
        BlockPos chestA = new BlockPos(cx - 5, floorY + 1, cz - 5);
        BlockPos chestB = new BlockPos(cx + 5, floorY + 1, cz + 5);
        writes.add(new BlockWrite(chestA, Blocks.CHEST.defaultBlockState()));
        writes.add(new BlockWrite(chestB, Blocks.CHEST.defaultBlockState()));
        chests.add(chestA);
        chests.add(chestB);

        return new BuildPlan(List.copyOf(writes), List.copyOf(chests));
    }

    private static void tower(List<BlockWrite> writes, int cx, int floorY, int cz) {
        BlockState air = Blocks.AIR.defaultBlockState();
        for (int dx = -3; dx <= 3; dx++) {
            for (int dz = -3; dz <= 3; dz++) {
                boolean wall = Math.abs(dx) == 3 || Math.abs(dz) == 3;
                for (int dy = 1; dy <= 7; dy++) {
                    BlockState state;
                    if (!wall) {
                        state = air;
                    } else if (dy == 7 && ((dx + dz) & 1) != 0) {
                        state = air;
                    } else {
                        state = hash01(cx + dx, floorY + dy, cz + dz) < 0.18D
                                ? Blocks.CRACKED_POLISHED_BLACKSTONE_BRICKS.defaultBlockState()
                                : Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
                    }
                    writes.add(new BlockWrite(new BlockPos(cx + dx, floorY + dy, cz + dz), state));
                }
            }
        }
    }

    private static void invertedRoot(List<BlockWrite> writes, int cx, int startY, int cz) {
        for (int depth = 0; depth < 11; depth++) {
            int radius = Math.max(0, 3 - depth / 3);
            for (int dx = -radius; dx <= radius; dx++) {
                for (int dz = -radius; dz <= radius; dz++) {
                    if (dx * dx + dz * dz <= radius * radius + 1) {
                        BlockState state = hash01(cx + dx, startY - depth, cz + dz) < 0.22D
                                ? Blocks.MAGMA_BLOCK.defaultBlockState()
                                : Blocks.BASALT.defaultBlockState();
                        writes.add(new BlockWrite(
                                new BlockPos(cx + dx, startY - depth, cz + dz), state));
                    }
                }
            }
        }
    }

    private static void chainToUnderside(List<BlockWrite> writes, int x, int startY, int z) {
        int ceiling = DiscTerrainFunction.column(DiscProfile.NETHER, x, z, STAGE).groundBottomY() - 1;
        for (int y = startY; y <= ceiling; y++) {
            writes.add(new BlockWrite(new BlockPos(x, y, z), Blocks.CHAIN.defaultBlockState()));
        }
    }

    private static void ladderShaft(List<BlockWrite> writes, int x, int floorY, int z) {
        int surface = DiscTerrainFunction.surfaceY(DiscProfile.NETHER, x, z);
        BlockState ladder = Blocks.LADDER.defaultBlockState().setValue(LadderBlock.FACING, Direction.NORTH);
        BlockState backing = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        for (int y = floorY + 1; y <= surface + 1; y++) {
            writes.add(new BlockWrite(new BlockPos(x, y, z + 1), backing));
            writes.add(new BlockWrite(new BlockPos(x, y, z), ladder));
            writes.add(new BlockWrite(new BlockPos(x, y, z - 1), Blocks.AIR.defaultBlockState()));
        }
        for (int dx = -1; dx <= 1; dx++) {
            for (int dz = -1; dz <= 1; dz++) {
                if (Math.abs(dx) == 1 || Math.abs(dz) == 1) {
                    writes.add(new BlockWrite(new BlockPos(x + dx, surface + 1, z + dz), backing));
                }
            }
        }
    }

    private static double hash01(int x, int y, int z) {
        long h = FrozenParams.mapSeed() ^ ((long) x * 341873128712L)
                ^ ((long) z * 132897987541L) ^ ((long) y * 42317861L);
        h ^= h >>> 30;
        h *= 0xBF58476D1CE4E5B9L;
        h ^= h >>> 27;
        h *= 0x94D049BB133111EBL;
        h ^= h >>> 31;
        return (h >>> 11) * 0x1.0p-53D;
    }
}
