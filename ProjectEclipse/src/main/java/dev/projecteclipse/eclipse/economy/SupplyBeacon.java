package dev.projecteclipse.eclipse.economy;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.worldgen.stage.BudgetedBlockWriter;
import net.minecraft.core.BlockPos;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.network.protocol.game.ClientboundLevelParticlesPacket;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.item.FallingBlockEntity;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * The pooled team Supply Beacon (spec §4, {@value ShardEconomy#SUPPLY_BEACON_COST} pooled
 * shards): a falling barrel crate lands {@value #MIN_DISTANCE_BLOCKS}–{@value
 * #MAX_DISTANCE_BLOCKS} blocks from the altar, pre-loaded with the curated
 * {@code eclipse:supply_crate} loot table (via {@link FallingBlockEntity#blockData} —
 * merged into the barrel block entity on landing). The landing spot is marked by an
 * {@code END_ROD} particle column (long-distance packets, refreshed every second for
 * {@value #MARKER_LIFETIME_TICKS} ticks) plus a one-shot Quasar altar-beam burst.
 * Coordinates are NEVER announced — first come, first served.
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class SupplyBeacon {
    public static final int MIN_DISTANCE_BLOCKS = 50;
    public static final int MAX_DISTANCE_BLOCKS = 100;

    private static final long MARKER_LIFETIME_TICKS = 20L * 180L;
    private static final int MARKER_REFRESH_TICKS = 20;
    private static final int COLUMN_HEIGHT_BLOCKS = 48;

    /** Marker particle receive radius — vanilla's long-distance particle cap. */
    private static final double MARKER_VISIBLE_RANGE_BLOCKS = 512.0D;

    /** Active light columns; transient — a restart simply retires old markers (the crate persists). */
    private record Marker(BlockPos surfacePos, long expiryGameTime) {}

    private static final List<Marker> MARKERS = new ArrayList<>();

    private SupplyBeacon() {}

    /**
     * Drops one supply crate at a random spot {@value #MIN_DISTANCE_BLOCKS}–{@value
     * #MAX_DISTANCE_BLOCKS} blocks from the sanctum altar (world spawn if the sanctum is
     * not built). Returns the surface position — for the LOG ONLY, never for players.
     */
    public static BlockPos drop(MinecraftServer server) {
        ServerLevel level = server.overworld();
        BlockPos altarPos = EclipseWorldState.get(server).getSanctumAltarPos();
        BlockPos center = altarPos != null ? altarPos : level.getSharedSpawnPos();
        RandomSource random = level.getRandom();

        double angle = random.nextDouble() * Math.PI * 2.0D;
        double distance = MIN_DISTANCE_BLOCKS + random.nextDouble() * (MAX_DISTANCE_BLOCKS - MIN_DISTANCE_BLOCKS);
        int x = center.getX() + (int) Math.round(Math.cos(angle) * distance);
        int z = center.getZ() + (int) Math.round(Math.sin(angle) * distance);
        // The target chunk may be unloaded (nobody nearby): getHeight would then return the
        // world floor and the crate would spawn deep underground. Ticket-load it first.
        BudgetedBlockWriter.loadWithTicket(level, x >> 4, z >> 4);
        int surfaceY = level.getHeight(Heightmap.Types.MOTION_BLOCKING, x, z);
        int spawnY = Math.min(surfaceY + 60, level.getMaxBuildHeight() - 4);

        FallingBlockEntity crate = FallingBlockEntity.fall(level,
                new BlockPos(x, spawnY, z), Blocks.BARREL.defaultBlockState());
        // Merged into the barrel's block entity NBT when the crate lands (vanilla behavior).
        CompoundTag lootData = new CompoundTag();
        lootData.putString("LootTable", "eclipse:supply_crate");
        lootData.putLong("LootTableSeed", random.nextLong());
        crate.blockData = lootData;

        BlockPos surfacePos = new BlockPos(x, surfaceY, z);
        MARKERS.add(new Marker(surfacePos, level.getGameTime() + MARKER_LIFETIME_TICKS));
        PacketDistributor.sendToPlayersInDimension(level,
                new S2CQuasarPayload(S2CQuasarPayload.ALTAR_BEAM, Vec3.atCenterOf(surfacePos.above())));
        EclipseMod.LOGGER.info("Supply beacon crate dropped {} blocks from {} at {} (coordinates stay secret in-game)",
                (int) distance, center.toShortString(), surfacePos.toShortString());
        return surfacePos;
    }

    /**
     * Refreshes every active END_ROD column once a second; long-distance so it reads from
     * up to {@value #MARKER_VISIBLE_RANGE_BLOCKS} blocks. Each column batch is built as ONE
     * {@link ClientboundLevelParticlesPacket} and fanned out through
     * {@code PlayerList.broadcast} to the overworld players in range — O(markers) packet
     * builds per refresh instead of the old per-player {@code sendParticles} loop
     * (O(markers × players) packet builds). The level-wide
     * {@code ServerLevel.sendParticles} overload is deliberately NOT used: it hard-codes
     * {@code longDistance=false}, capping visibility at 32 blocks, which would defeat the
     * marker.
     */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (MARKERS.isEmpty() || server.getTickCount() % MARKER_REFRESH_TICKS != 0) {
            return;
        }
        ServerLevel level = server.overworld();
        long now = level.getGameTime();
        Iterator<Marker> iterator = MARKERS.iterator();
        while (iterator.hasNext()) {
            Marker marker = iterator.next();
            if (now >= marker.expiryGameTime()) {
                iterator.remove();
                continue;
            }
            double x = marker.surfacePos().getX() + 0.5D;
            double z = marker.surfacePos().getZ() + 0.5D;
            for (int offset = 0; offset <= COLUMN_HEIGHT_BLOCKS; offset += 4) {
                double y = marker.surfacePos().getY() + 1.0D + offset;
                ClientboundLevelParticlesPacket packet = new ClientboundLevelParticlesPacket(
                        ParticleTypes.END_ROD, true, x, y, z, 0.15F, 1.2F, 0.15F, 0.0F, 2);
                server.getPlayerList().broadcast(null, x, y, z, MARKER_VISIBLE_RANGE_BLOCKS,
                        level.dimension(), packet);
            }
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        MARKERS.clear();
    }
}
