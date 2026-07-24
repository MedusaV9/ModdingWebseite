package dev.projecteclipse.eclipse.worldgen.nether;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CBreachPayload;
import dev.projecteclipse.eclipse.network.S2CBreachPayload.Phase;
import dev.projecteclipse.eclipse.network.breach.BreachPayloads;
import dev.projecteclipse.eclipse.worldgen.BreachGeometry;
import dev.projecteclipse.eclipse.worldgen.DiscMapData;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.DiscTerrainFunction;
import dev.projecteclipse.eclipse.worldgen.WorldStageAccess;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Live materializer for D10's Nether breach. The Nether stage-1 completion listener starts
 * a three-part deterministic job:
 *
 * <ol>
 *   <li>build and ticket the Nether arrival/updraft chimney, including the IDEA-17
 *       ceiling bore that pierces the nether roof shell (so the glitch-drift descent
 *       passes seamlessly from the overworld funnel through the roof to the floor),</li>
 *   <li>carve {@link BreachGeometry} through the already-generated overworld disc while
 *       repainting its crimson-creep halo,</li>
 *   <li>place the overworld return pad, then persist {@code breachOpen=true}.</li>
 * </ol>
 *
 * <p>Every block mutation runs inside a measured per-tick budget. The materialization flag
 * is deliberately committed only after all writes finish: a crash mid-open leaves it false,
 * and the server-start catch-up sees Nether stage ≥ 1 and safely replays the idempotent job.
 * {@link #openNow(ServerLevel)} intentionally also replays when the flag is already true, so
 * P5's dev command can repair a damaged set-piece after directly toggling the flag.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class BreachBuilder {
    private static final long WRITE_BUDGET_NANOS = 3_000_000L;
    private static final int MAX_OPERATIONS_PER_TICK = 4096;
    private static final int MAX_FINALIZE_CHUNKS_PER_TICK = 2;
    private static final int CHIMNEY_HEIGHT = 22;
    private static final int CRATER_SCAN_MARGIN = 5;
    private static final int FALLBACK_ARRIVAL_X = 85;
    private static final int FALLBACK_ARRIVAL_Z = 85;
    /**
     * Squared radius of the IDEA-17 ceiling bore (r ≈ 3.5): wide enough that the
     * glitch-drift handoff (arrival center ± the 2-block 1:1 offset clamp) always drops
     * through open air, narrow enough to stay inside the chimney's basalt collar.
     */
    private static final int BORE_RADIUS_SQ = 12;

    private static final Set<Heightmap.Types> HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING, Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR, Heightmap.Types.WORLD_SURFACE);

    private static boolean listenerRegistered;
    private static boolean bootstrapPending;
    private static BuildJob active;

    private BreachBuilder() {}

    /**
     * Starts an idempotent live materialization/repair. The supplied level must be the
     * overworld. Returns false only when called for another dimension, the Nether is absent,
     * or this server already has a breach job in flight.
     */
    public static boolean openNow(ServerLevel overworld) {
        if (overworld.dimension() != Level.OVERWORLD) {
            EclipseMod.LOGGER.warn("BreachBuilder.openNow requires the overworld, got {}",
                    overworld.dimension().location());
            return false;
        }
        MinecraftServer server = overworld.getServer();
        ServerLevel nether = server.getLevel(Level.NETHER);
        if (nether == null) {
            EclipseMod.LOGGER.warn("Cannot open the Nether breach: minecraft:the_nether is unavailable");
            return false;
        }
        if (active != null && active.server == server) {
            return false;
        }

        active = new BuildJob(overworld, nether);
        BlockPos center = breachCenter();
        BreachPayloads.sendPhase(overworld,
                new S2CBreachPayload(Phase.QUAKE, center, BreachGeometry.CRATER_RADIUS));
        overworld.playSound(null, center, SoundEvents.LIGHTNING_BOLT_THUNDER,
                SoundSource.AMBIENT, 1.4F, 0.45F);
        overworld.playSound(null, center,
                Blocks.DEEPSLATE.defaultBlockState().getSoundType().getBreakSound(),
                SoundSource.BLOCKS, 2.0F, 0.5F);
        EclipseMod.LOGGER.info("Nether breach materialization queued at {} (repair={})",
                center.toShortString(), EclipseWorldgenState.get(server).breachOpen());
        return true;
    }

    /** True while a live materialization is in flight (the transfer service treats it as open). */
    public static boolean isOpening(MinecraftServer server) {
        return active != null && active.server == server;
    }

    /** Overworld crater center at the lip plane. */
    public static BlockPos breachCenter() {
        return new BlockPos(BreachGeometry.centerX(), BreachGeometry.lipY(), BreachGeometry.centerZ());
    }

    /** Nether arrival landmark at its deterministic surface. */
    public static BlockPos arrivalCenter() {
        DiscMapData.Landmark landmark = landmark(DiscProfile.NETHER, "eclipse:breach_arrival");
        int x = landmark != null ? landmark.x() : FALLBACK_ARRIVAL_X;
        int z = landmark != null ? landmark.z() : FALLBACK_ARRIVAL_Z;
        return new BlockPos(x, DiscTerrainFunction.surfaceY(DiscProfile.NETHER, x, z), z);
    }

    /**
     * Soul-updraft column, offset three blocks toward the disc center so it stays inside
     * the stage-1 radius and normally does not overlap the mapped descent landing.
     */
    public static BlockPos updraftCenter() {
        BlockPos arrival = arrivalCenter();
        double length = Math.max(1.0D, Math.hypot(arrival.getX(), arrival.getZ()));
        int x = arrival.getX() - (int) Math.round(arrival.getX() / length * 3.0D);
        int z = arrival.getZ() - (int) Math.round(arrival.getZ() / length * 3.0D);
        return new BlockPos(x, arrival.getY(), z);
    }

    /** Safe return pad on the inward side of the overworld crater rim. */
    public static BlockPos returnPad() {
        int cx = BreachGeometry.centerX();
        int cz = BreachGeometry.centerZ();
        double length = Math.max(1.0D, Math.hypot(cx, cz));
        double offset = BreachGeometry.CRATER_RADIUS + 6.0D;
        int x = cx - (int) Math.round(cx / length * offset);
        int z = cz - (int) Math.round(cz / length * offset);
        return new BlockPos(x, DiscTerrainFunction.surfaceY(DiscProfile.OVERWORLD, x, z), z);
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        if (!listenerRegistered) {
            WorldStageService.addListener(BreachBuilder::onStageTerrainComplete);
            listenerRegistered = true;
        }
        bootstrapPending = true;
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (bootstrapPending) {
            bootstrapPending = false;
            if (WorldStageService.stage(server, DiscProfile.NETHER) >= 1
                    && !EclipseWorldgenState.get(server).breachOpen()) {
                openNow(server.overworld());
            }
        }
        BuildJob job = active;
        if (job == null || job.server != server) {
            return;
        }
        if (server.getTickCount() % 8 == 0) {
            emitOpeningSmoke(job.overworld, server.getTickCount());
        }
        if (job.tick()) {
            active = null;
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        if (active != null && active.server == event.getServer()) {
            active = null;
        }
        bootstrapPending = false;
    }

    private static void onStageTerrainComplete(ServerLevel level, DiscProfile profile,
            int fromStage, int toStage) {
        if (profile == DiscProfile.NETHER && fromStage < 1 && toStage >= 1
                && !EclipseWorldgenState.get(level.getServer()).breachOpen()) {
            openNow(level.getServer().overworld());
        }
    }

    private static void emitOpeningSmoke(ServerLevel overworld, long tick) {
        BlockPos center = breachCenter();
        double angle = tick * 0.19D;
        for (int i = 0; i < 6; i++) {
            double a = angle + i * (Math.PI * 2.0D / 6.0D);
            double x = center.getX() + 0.5D + Math.cos(a) * (BreachGeometry.CRATER_RADIUS - 1.0D);
            double z = center.getZ() + 0.5D + Math.sin(a) * (BreachGeometry.CRATER_RADIUS - 1.0D);
            overworld.sendParticles(ParticleTypes.CAMPFIRE_COSY_SMOKE,
                    x, center.getY() + 1.2D, z, 2, 0.45D, 0.25D, 0.45D, 0.015D);
            overworld.sendParticles(ParticleTypes.ASH,
                    x, center.getY() + 2.0D, z, 3, 0.7D, 0.5D, 0.7D, 0.01D);
        }
    }

    private static DiscMapData.Landmark landmark(DiscProfile profile, String id) {
        for (DiscMapData.Landmark landmark : DiscMapData.get().landmarks(profile)) {
            if (id.equals(landmark.id())) {
                return landmark;
            }
        }
        return null;
    }

    private record BlockWrite(BlockPos pos, BlockState state) {}

    private enum JobPhase {
        CHIMNEY,
        CRATER,
        RETURN_PAD,
        FINALIZE
    }

    private static final class BuildJob {
        private final MinecraftServer server;
        private final ServerLevel overworld;
        private final ServerLevel nether;
        private final List<BlockWrite> chimneyWrites;
        private final List<BlockWrite> returnPadWrites;
        private final Set<Long> overworldTouched = new HashSet<>();
        private final Set<Long> netherTouched = new HashSet<>();

        private JobPhase phase = JobPhase.CHIMNEY;
        private int listCursor;
        private int craterX = BreachGeometry.centerX() - BreachGeometry.HALO_RADIUS;
        private int craterZ = BreachGeometry.centerZ() - BreachGeometry.HALO_RADIUS;
        private int craterY;
        private int craterSurfaceY;
        private int craterTopY;
        private boolean craterColumnReady;
        private List<Long> finalizeNether;
        private List<Long> finalizeOverworld;
        private int finalizeCursor;
        private boolean finalizingOverworld;

        private BuildJob(ServerLevel overworld, ServerLevel nether) {
            this.server = overworld.getServer();
            this.overworld = overworld;
            this.nether = nether;
            this.chimneyWrites = chimneyWrites();
            this.returnPadWrites = returnPadWrites();
        }

        /** @return true once all writes, relights, flag commit and phase broadcasts finish. */
        private boolean tick() {
            long deadline = System.nanoTime() + WRITE_BUDGET_NANOS;
            int operations = 0;
            int finalizedChunks = 0;
            while (operations < MAX_OPERATIONS_PER_TICK && System.nanoTime() < deadline) {
                switch (this.phase) {
                    case CHIMNEY -> {
                        if (this.listCursor < this.chimneyWrites.size()) {
                            apply(this.nether, this.chimneyWrites.get(this.listCursor++), this.netherTouched);
                            operations++;
                            continue;
                        }
                        this.phase = JobPhase.CRATER;
                        this.listCursor = 0;
                        BlockPos center = breachCenter();
                        BreachPayloads.sendPhase(this.overworld,
                                new S2CBreachPayload(Phase.OPEN, center, BreachGeometry.CRATER_RADIUS));
                        this.overworld.playSound(null, center, SoundEvents.GENERIC_EXPLODE.value(),
                                SoundSource.BLOCKS, 1.6F, 0.6F);
                    }
                    case CRATER -> {
                        if (stepCrater()) {
                            operations++;
                            continue;
                        }
                        this.phase = JobPhase.RETURN_PAD;
                    }
                    case RETURN_PAD -> {
                        if (this.listCursor < this.returnPadWrites.size()) {
                            apply(this.overworld, this.returnPadWrites.get(this.listCursor++),
                                    this.overworldTouched);
                            operations++;
                            continue;
                        }
                        this.finalizeNether = new ArrayList<>(this.netherTouched);
                        this.finalizeOverworld = new ArrayList<>(this.overworldTouched);
                        this.phase = JobPhase.FINALIZE;
                    }
                    case FINALIZE -> {
                        if (finalizedChunks >= MAX_FINALIZE_CHUNKS_PER_TICK) {
                            return false;
                        }
                        if (stepFinalize()) {
                            finalizedChunks++;
                            operations++;
                            continue;
                        }
                        complete();
                        return true;
                    }
                }
            }
            return false;
        }

        /** Queues one touched chunk's heightmap/light/client finish pass. */
        private boolean stepFinalize() {
            List<Long> keys = this.finalizingOverworld ? this.finalizeOverworld : this.finalizeNether;
            if (this.finalizeCursor >= keys.size()) {
                if (this.finalizingOverworld) {
                    return false;
                }
                this.finalizingOverworld = true;
                this.finalizeCursor = 0;
                keys = this.finalizeOverworld;
                if (keys.isEmpty()) {
                    return false;
                }
            }
            long key = keys.get(this.finalizeCursor++);
            ServerLevel level = this.finalizingOverworld ? this.overworld : this.nether;
            LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(level,
                    ChunkPos.getX(key), ChunkPos.getZ(key));
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
            BudgetedBlockWriter.relightAndResend(level, chunk);
            return true;
        }

        /**
         * Advances one geometry probe. Null overrides still consume budget: evaluating the
         * deterministic shape is part of the materialization cost and must not spike.
         */
        private boolean stepCrater() {
            int max = BreachGeometry.HALO_RADIUS;
            int maxX = BreachGeometry.centerX() + max;
            int maxZ = BreachGeometry.centerZ() + max;
            if (this.craterX > maxX) {
                return false;
            }
            if (!this.craterColumnReady) {
                double dx = this.craterX - BreachGeometry.centerX();
                double dz = this.craterZ - BreachGeometry.centerZ();
                if (dx * dx + dz * dz > (double) max * max) {
                    advanceColumn(maxZ);
                    return true;
                }
                touch(this.overworld, this.craterX, this.craterZ, this.overworldTouched);
                this.craterSurfaceY = DiscTerrainFunction.surfaceY(
                        DiscProfile.OVERWORLD, this.craterX, this.craterZ);
                double scanRadius = BreachGeometry.CRATER_RADIUS + CRATER_SCAN_MARGIN;
                if (dx * dx + dz * dz <= scanRadius * scanRadius) {
                    this.craterY = this.overworld.getMinBuildHeight();
                    this.craterTopY = Math.max(BreachGeometry.lipY() + 12, this.craterSurfaceY + 4);
                } else {
                    this.craterY = this.craterSurfaceY;
                    this.craterTopY = this.craterSurfaceY + 1;
                }
                this.craterColumnReady = true;
            }

            BlockState target = BreachGeometry.carveAt(this.craterX, this.craterY, this.craterZ);
            if (target == null && (this.craterY == this.craterSurfaceY
                    || this.craterY == this.craterSurfaceY + 1)) {
                target = BreachGeometry.creepAt(this.craterX, this.craterY, this.craterZ,
                        this.craterSurfaceY);
            }
            if (target != null) {
                apply(this.overworld,
                        new BlockWrite(new BlockPos(this.craterX, this.craterY, this.craterZ), target),
                        this.overworldTouched);
            }
            if (++this.craterY > this.craterTopY) {
                advanceColumn(maxZ);
            }
            return true;
        }

        private void advanceColumn(int maxZ) {
            this.craterColumnReady = false;
            this.craterZ++;
            if (this.craterZ > maxZ) {
                this.craterZ = BreachGeometry.centerZ() - BreachGeometry.HALO_RADIUS;
                this.craterX++;
            }
        }

        private void complete() {
            EclipseWorldgenState.get(this.server).setBreachOpen(true);

            BlockPos center = breachCenter();
            BreachPayloads.sendPhase(this.overworld,
                    new S2CBreachPayload(Phase.SETTLED, center, BreachGeometry.CRATER_RADIUS));
            emitOpeningSmoke(this.overworld, this.server.getTickCount());
            this.overworld.playSound(null, center,
                    Blocks.NETHERRACK.defaultBlockState().getSoundType().getBreakSound(),
                    SoundSource.BLOCKS, 1.2F, 0.75F);
            EclipseMod.LOGGER.info(
                    "Nether breach settled: {} overworld chunk(s), {} nether chunk(s) rewritten",
                    this.overworldTouched.size(), this.netherTouched.size());
        }

        private static void apply(ServerLevel level, BlockWrite write, Set<Long> touched) {
            BlockPos pos = write.pos();
            if (pos.getY() < level.getMinBuildHeight() || pos.getY() >= level.getMaxBuildHeight()) {
                return;
            }
            touch(level, pos.getX(), pos.getZ(), touched);
            if (!level.getBlockState(pos).equals(write.state())) {
                level.setBlock(pos, write.state(), Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE);
            }
        }

        private static void touch(ServerLevel level, int x, int z, Set<Long> touched) {
            long key = ChunkPos.asLong(x >> 4, z >> 4);
            if (touched.add(key)) {
                BudgetedBlockWriter.loadWithTicket(level, x >> 4, z >> 4);
            }
        }

    }

    private static List<BlockWrite> chimneyWrites() {
        List<BlockWrite> writes = new ArrayList<>();
        BlockPos center = arrivalCenter();
        int cx = center.getX();
        int cy = center.getY();
        int cz = center.getZ();
        BlockState air = Blocks.AIR.defaultBlockState();
        BlockState blackstone = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();

        // Netherrack funnel/landing and a four-block-radius basalt collar.
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > 16) {
                    continue;
                }
                // The mapped descent can land anywhere in the inner radius: keep it
                // damage-free. Magma stays a visual wall/spout accent in BreachGeometry.
                BlockState floor = d2 <= 9
                        ? Blocks.NETHERRACK.defaultBlockState() : blackstone;
                writes.add(new BlockWrite(new BlockPos(cx + dx, cy, cz + dz), floor));
                if (d2 <= 10) {
                    for (int dy = 1; dy <= CHIMNEY_HEIGHT; dy++) {
                        writes.add(new BlockWrite(new BlockPos(cx + dx, cy + dy, cz + dz), air));
                    }
                } else {
                    for (int dy = 1; dy <= CHIMNEY_HEIGHT; dy++) {
                        if (dy % 4 != 0 || d2 >= 14) {
                            writes.add(new BlockWrite(new BlockPos(cx + dx, cy + dy, cz + dz),
                                    dy % 5 == 0 ? blackstone : Blocks.BASALT.defaultBlockState()));
                        }
                    }
                }
            }
        }

        // Walkable basalt helix: four samples per vertical block, ~five turns to the top.
        for (int i = 0; i < CHIMNEY_HEIGHT * 4; i++) {
            double angle = i * (Math.PI * 2.0D / 18.0D);
            int x = cx + (int) Math.round(Math.cos(angle) * 2.7D);
            int z = cz + (int) Math.round(Math.sin(angle) * 2.7D);
            int y = cy + 1 + i / 4;
            writes.add(new BlockWrite(new BlockPos(x, y, z), Blocks.BASALT.defaultBlockState()));
            writes.add(new BlockWrite(new BlockPos(x, y, z).below(), blackstone));
        }

        // Keep the soul-updraft shaft unobstructed after the helix writes.
        BlockPos updraft = updraftCenter();
        writes.add(new BlockWrite(updraft, Blocks.SOUL_SAND.defaultBlockState()));
        for (int dy = 1; dy <= CHIMNEY_HEIGHT + 2; dy++) {
            writes.add(new BlockWrite(updraft.above(dy), air));
        }
        for (int dy = 3; dy <= CHIMNEY_HEIGHT; dy += 5) {
            writes.add(new BlockWrite(updraft.offset(1, dy, 0),
                    Blocks.CRYING_OBSIDIAN.defaultBlockState()));
        }

        // IDEA-17 ceiling bore: extend the chimney's air shaft straight up THROUGH the
        // nether roof shell (stalactites, body and the mirrored bedrock cap) to the
        // world top, so the glitch-drift descent physically passes the ceiling. The
        // mouth gets a polished-blackstone collar ring so the pierced roof reads as
        // built, not broken. Deterministic and replayed by openNow (repair-idempotent).
        int stage = WorldStageAccess.stage(DiscProfile.NETHER);
        int worldTopY = DiscProfile.NETHER.minY() + DiscProfile.NETHER.height() - 1;
        for (int dx = -4; dx <= 4; dx++) {
            for (int dz = -4; dz <= 4; dz++) {
                int d2 = dx * dx + dz * dz;
                if (d2 > 18) {
                    continue;
                }
                if (d2 <= BORE_RADIUS_SQ) {
                    for (int y = cy + CHIMNEY_HEIGHT + 1; y <= worldTopY; y++) {
                        writes.add(new BlockWrite(new BlockPos(cx + dx, y, cz + dz), air));
                    }
                } else {
                    DiscTerrainFunction.DiscColumn column = DiscTerrainFunction.column(
                            DiscProfile.NETHER, cx + dx, cz + dz, stage);
                    if (column.inside() && column.ceilingBodyY() != Integer.MAX_VALUE) {
                        for (int y = column.ceilingBottomY(); y <= column.ceilingBodyY() + 1; y++) {
                            writes.add(new BlockWrite(new BlockPos(cx + dx, y, cz + dz), blackstone));
                        }
                    }
                }
            }
        }
        return List.copyOf(writes);
    }

    private static List<BlockWrite> returnPadWrites() {
        List<BlockWrite> writes = new ArrayList<>();
        BlockPos pad = returnPad();
        BlockState floor = Blocks.POLISHED_BLACKSTONE_BRICKS.defaultBlockState();
        for (int dx = -3; dx <= 3; dx++) {
            for (int dz = -3; dz <= 3; dz++) {
                if (dx * dx + dz * dz > 12) {
                    continue;
                }
                BlockPos base = pad.offset(dx, 0, dz);
                writes.add(new BlockWrite(base,
                        (Math.abs(dx) == 3 || Math.abs(dz) == 3)
                                ? Blocks.CHISELED_POLISHED_BLACKSTONE.defaultBlockState() : floor));
                for (int dy = 1; dy <= 5; dy++) {
                    writes.add(new BlockWrite(base.above(dy), Blocks.AIR.defaultBlockState()));
                }
            }
        }
        for (int sx : new int[] {-3, 3}) {
            for (int sz : new int[] {-3, 3}) {
                BlockPos corner = pad.offset(sx, 1, sz);
                writes.add(new BlockWrite(corner, Blocks.BASALT.defaultBlockState()));
                writes.add(new BlockWrite(corner.above(), Blocks.SOUL_LANTERN.defaultBlockState()));
            }
        }
        return List.copyOf(writes);
    }
}
