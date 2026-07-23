package dev.projecteclipse.eclipse.worldgen.end;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldgenState;
import dev.projecteclipse.eclipse.network.S2CShakePayload;
import dev.projecteclipse.eclipse.network.end.EndPayloads;
import dev.projecteclipse.eclipse.network.end.S2CEndCrashPayload;
import dev.projecteclipse.eclipse.progression.DayScheduler;
import dev.projecteclipse.eclipse.worldgen.DiscProfile;
import dev.projecteclipse.eclipse.worldgen.EndDiscGeometry;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import dev.projecteclipse.eclipse.worldgen.stage.WorldStageService;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.chunk.LevelChunk;
import net.minecraft.world.level.chunk.LevelChunkSection;
import net.minecraft.world.level.levelgen.Heightmap;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStartedEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Trigger, budgeted live materialization and restart-resume service for the overworld
 * End disc. The shared worldgen flag is flipped before any chunk load so chunks generated
 * during the sweep already use {@link EndDiscGeometry}; this writer then idempotently
 * applies the same pure states to every live column.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class EndDiscService {
    private static final int TRIGGER_POLL_TICKS = 20;
    private static final int FINAL_DAY = 12;
    private static final long TICK_NANOS = 2_000_000L;
    private static final int CRASH_TIMELINE_TICKS = 120;
    private static final float CRASH_SHAKE_STRENGTH = 2.0F;

    private static final Set<Heightmap.Types> HEIGHTMAPS = EnumSet.of(
            Heightmap.Types.MOTION_BLOCKING,
            Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
            Heightmap.Types.OCEAN_FLOOR,
            Heightmap.Types.WORLD_SURFACE);
    private static final Set<String> WARNED_TRIGGERS = new HashSet<>();

    private static Job activeJob;

    private EndDiscService() {}

    /**
     * Public command seam for {@code /eclipse-worldgen end materialize}. Idempotent:
     * completed and currently-running jobs are left alone.
     */
    public static boolean materialize(MinecraftServer server) {
        EndFightState fight = EndFightState.get(server);
        if (fight.materializationComplete() || activeJob != null) {
            return false;
        }
        boolean firstStart = !fight.materializationStarted();
        EclipseWorldgenState.get(server).setEndDiscMaterialized(true);
        fight.beginMaterialization();
        activeJob = new Job(server.overworld(), fight);
        if (firstStart) {
            announceCrash(server.overworld());
        } else {
            EclipseMod.LOGGER.info("Resuming End-disc materialization at cursor {}",
                    fight.materializationCursor());
        }
        return true;
    }

    public static boolean isRunning() {
        return activeJob != null;
    }

    @SubscribeEvent
    public static void onServerStarted(ServerStartedEvent event) {
        MinecraftServer server = event.getServer();
        EndFightState state = EndFightState.get(server);
        EclipseWorldgenState worldgen = EclipseWorldgenState.get(server);
        if (state.materializationStarted() && !worldgen.endDiscMaterialized()) {
            // Heal a save interrupted between the local cursor write and the shared
            // geometry-flag save; generated chunks must agree with the resumed writer.
            worldgen.setEndDiscMaterialized(true);
        }
        if (!state.materializationComplete()
                && (worldgen.endDiscMaterialized() || state.materializationStarted())) {
            materialize(server);
        }
    }

    /**
     * Polls both configured progression and the shared flag. The second path is important:
     * the dev command owned by the worldgen command worker only needs to set the flag.
     */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (activeJob != null) {
            activeJob.tick();
            return;
        }
        if (server.getTickCount() % TRIGGER_POLL_TICKS != 0) {
            return;
        }
        EndFightState fight = EndFightState.get(server);
        if (fight.materializationComplete()) {
            return;
        }
        EclipseWorldgenState worldgen = EclipseWorldgenState.get(server);
        if (worldgen.endDiscMaterialized() || triggerMatches(server, EndConfig.current().trigger())) {
            materialize(server);
        }
    }

    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        activeJob = null;
        WARNED_TRIGGERS.clear();
    }

    private static boolean triggerMatches(MinecraftServer server, String trigger) {
        if ("final_day".equals(trigger)) {
            return DayScheduler.getDay(server) >= FINAL_DAY;
        }
        if (trigger != null && trigger.startsWith("day:")) {
            return DayScheduler.getDay(server) >= threshold(trigger, "day:");
        }
        if (trigger != null && trigger.startsWith("stage:")) {
            return WorldStageService.stage(server, DiscProfile.OVERWORLD)
                    >= threshold(trigger, "stage:");
        }
        if (WARNED_TRIGGERS.add(String.valueOf(trigger))) {
            EclipseMod.LOGGER.warn(
                    "Ignoring malformed end.json trigger '{}' (expected day:N, stage:N, or final_day)",
                    trigger);
        }
        return false;
    }

    private static int threshold(String trigger, String prefix) {
        try {
            return Integer.parseInt(trigger.substring(prefix.length()));
        } catch (NumberFormatException e) {
            if (WARNED_TRIGGERS.add(trigger)) {
                EclipseMod.LOGGER.warn("Ignoring malformed end.json trigger '{}'", trigger);
            }
            return Integer.MAX_VALUE;
        }
    }

    private static void announceCrash(ServerLevel level) {
        EndConfig.Snapshot config = EndConfig.current();
        BlockPos center = new BlockPos(config.centerX(), config.surfaceY(), config.centerZ());
        EndPayloads.sendCrash(level, new S2CEndCrashPayload(
                center, config.radius(), CRASH_TIMELINE_TICKS, CRASH_SHAKE_STRENGTH));
        PacketDistributor.sendToPlayersInDimension(
                level, S2CShakePayload.shake(CRASH_SHAKE_STRENGTH, CRASH_TIMELINE_TICKS));
        level.playSound(null, center, SoundEvents.ENDER_DRAGON_GROWL,
                SoundSource.HOSTILE, 4.0F, 0.55F);
        level.playSound(null, center, SoundEvents.LIGHTNING_BOLT_THUNDER,
                SoundSource.AMBIENT, 4.0F, 0.45F);
        for (ServerPlayer player : level.players()) {
            player.playNotifySound(
                    SoundEvents.ENDER_DRAGON_GROWL, SoundSource.MASTER, 1.4F, 0.55F);
            player.playNotifySound(
                    SoundEvents.LIGHTNING_BOLT_THUNDER, SoundSource.MASTER, 1.4F, 0.45F);
        }
        level.getServer().getPlayerList().broadcastSystemMessage(
                net.minecraft.network.chat.Component.translatable("announce.eclipse.end.arrival"),
                false);
        EclipseMod.LOGGER.info("End disc arrival started at {} (r={})", center, config.radius());
    }

    /** One resumable materialization job; all methods run on the server thread. */
    private static final class Job {
        private final ServerLevel level;
        private final EndFightState state;
        private final EndConfig.Snapshot config;
        private final List<ChunkPos> chunks;
        private final List<EndSpires.BlockWrite> cityWrites;
        private final Set<Long> loadedCityChunks = new HashSet<>();
        private final long terrainOperations;
        private long cursor;

        Job(ServerLevel level, EndFightState state) {
            this.level = level;
            this.state = state;
            this.config = EndConfig.current();
            this.chunks = discChunks(this.config);
            this.cityWrites = EndSpires.miniCityWrites();
            this.terrainOperations = (long) this.chunks.size() * 256L;
            this.cursor = Math.min(state.materializationCursor(), totalOperations());
        }

        void tick() {
            long started = System.nanoTime();
            int budget = this.config.blockBudgetPerTick();
            int operations = 0;

            if (this.cursor < this.terrainOperations) {
                long chunkIndex = this.cursor / 256L;
                LevelChunk chunk = BudgetedBlockWriter.loadWithTicket(
                        this.level,
                        this.chunks.get((int) chunkIndex).x,
                        this.chunks.get((int) chunkIndex).z);
                while (this.cursor < this.terrainOperations
                        && this.cursor / 256L == chunkIndex
                        && operations < budget
                        && System.nanoTime() - started < TICK_NANOS) {
                    writeTerrainColumn(chunk, (int) (this.cursor & 255L));
                    this.cursor++;
                    operations++;
                }
                if (this.cursor / 256L != chunkIndex || this.cursor == this.terrainOperations) {
                    finishChunk(chunk);
                    this.state.setMaterializationCursor(this.cursor);
                }
                return; // at most one chunk load + finish per tick
            }

            while (this.cursor < totalOperations()
                    && operations < budget
                    && System.nanoTime() - started < TICK_NANOS) {
                int cityIndex = (int) (this.cursor - this.terrainOperations);
                EndSpires.BlockWrite write = this.cityWrites.get(cityIndex);
                int chunkX = write.pos().getX() >> 4;
                int chunkZ = write.pos().getZ() >> 4;
                if (this.loadedCityChunks.add(ChunkPos.asLong(chunkX, chunkZ))) {
                    BudgetedBlockWriter.loadWithTicket(this.level, chunkX, chunkZ);
                }
                EndSpires.placeMiniCityWrite(this.level, write, this.config);
                this.cursor++;
                operations++;
            }
            this.state.setMaterializationCursor(this.cursor);
            if (this.cursor >= totalOperations()) {
                complete();
            }
        }

        private void writeTerrainColumn(LevelChunk chunk, int localIndex) {
            int localX = localIndex & 15;
            int localZ = localIndex >>> 4;
            int x = chunk.getPos().getMinBlockX() + localX;
            int z = chunk.getPos().getMinBlockZ() + localZ;
            if (!EndDiscGeometry.footprintContains(x, z)) {
                return;
            }
            for (int y = EndDiscGeometry.MIN_Y; y <= EndDiscGeometry.MAX_Y; y++) {
                BlockState block = EndDiscGeometry.stateAt(x, y, z);
                if (block == null) {
                    continue;
                }
                LevelChunkSection section = chunk.getSection(chunk.getSectionIndex(y));
                section.setBlockState(localX, y & 15, localZ, block, false);
            }
            chunk.setUnsaved(true);
        }

        private void finishChunk(LevelChunk chunk) {
            Heightmap.primeHeightmaps(chunk, HEIGHTMAPS);
            BudgetedBlockWriter.relightAndResend(this.level, chunk);
        }

        private long totalOperations() {
            return this.terrainOperations + this.cityWrites.size();
        }

        private void complete() {
            EndSpires.spawnInitialCrystals(this.level, this.state, this.config.crystalCount());
            this.state.completeMaterialization();
            this.state.setMaterializationCursor(totalOperations());
            activeJob = null;
            EclipseMod.LOGGER.info(
                    "End disc materialized: {} chunks, {} mini-city writes, {} crystals",
                    this.chunks.size(), this.cityWrites.size(), this.config.crystalCount());
            EclipseDragonFight.begin(this.level.getServer());
        }
    }

    private static List<ChunkPos> discChunks(EndConfig.Snapshot config) {
        int margin = 8;
        int minChunkX = Math.floorDiv(config.centerX() - config.radius() - margin, 16);
        int maxChunkX = Math.floorDiv(config.centerX() + config.radius() + margin, 16);
        int minChunkZ = Math.floorDiv(config.centerZ() - config.radius() - margin, 16);
        int maxChunkZ = Math.floorDiv(config.centerZ() + config.radius() + margin, 16);
        List<ChunkPos> chunks = new ArrayList<>();
        for (int chunkX = minChunkX; chunkX <= maxChunkX; chunkX++) {
            for (int chunkZ = minChunkZ; chunkZ <= maxChunkZ; chunkZ++) {
                chunks.add(new ChunkPos(chunkX, chunkZ));
            }
        }
        return List.copyOf(chunks);
    }
}
