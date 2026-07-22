package dev.projecteclipse.eclipse.limbo;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side timeline of the {@code /start_event} opening cutscene (command registration
 * is the admin worker's job; it should just call {@link #begin(MinecraftServer)}).
 *
 * <p>Tick timeline (driven by a {@link ServerTickEvent.Post} counter, no threads):</p>
 * <ul>
 *   <li>t=0 — broadcast {@code TILT}, keel the ghost ship's oars over (interpolated), play
 *       {@code eclipse:event.submerge} to every online player.</li>
 *   <li>t=100 — broadcast {@code SUBMERGE} then {@code WAVES}, plus one
 *       {@code eclipse:cutscene_veil} Quasar burst per limbo player (sent to limbo).</li>
 *   <li>t=140 — teleport every player currently in Limbo to the overworld shared spawn,
 *       each into a temporary carved 1x2 air pocket ~2 blocks under the surface, with
 *       upward velocity so they visually rise out of the ground.</li>
 *   <li>t=150 — refill the carved pockets with their previous blocks.</li>
 *   <li>t=160 — broadcast {@code EMERGE}, set {@code startEventDone}, stamp each teleported
 *       player's {@code first_overworld_join} attachment (voice-mute timer) if unset, and
 *       broadcast one {@code eclipse:cutscene_veil} Quasar burst per emerged player.</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StartEventCutscene {
    private static final int TILT_TICK = 0;
    private static final int SUBMERGE_TICK = 100;
    private static final int TELEPORT_TICK = 140;
    private static final int REFILL_TICK = 150;
    private static final int EMERGE_TICK = 160;

    private static final double RISE_VELOCITY = 1.2D;

    private record CarvedBlock(ServerLevel level, BlockPos pos, BlockState previous) {}

    private static boolean running = false;
    private static int ticks = 0;
    private static final List<CarvedBlock> carvedBlocks = new ArrayList<>();
    private static final List<UUID> teleportedPlayers = new ArrayList<>();

    private StartEventCutscene() {}

    /**
     * Starts the cutscene timeline on the next server tick. No-op while a run is already in
     * progress; returns whether a new run actually started.
     */
    public static boolean begin(MinecraftServer server) {
        if (running) {
            EclipseMod.LOGGER.warn("start_event cutscene already running; ignoring begin()");
            return false;
        }
        running = true;
        ticks = 0;
        carvedBlocks.clear();
        teleportedPlayers.clear();
        EclipseMod.LOGGER.info("start_event cutscene beginning");
        return true;
    }

    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (!running) {
            return;
        }
        MinecraftServer server = event.getServer();
        int t = ticks++;
        switch (t) {
            case TILT_TICK -> tilt(server);
            case SUBMERGE_TICK -> submerge(server);
            case TELEPORT_TICK -> teleportLimboPlayersToOverworld(server);
            case REFILL_TICK -> refillPockets();
            case EMERGE_TICK -> emerge(server);
            default -> { /* waiting between phases */ }
        }
        if (t >= EMERGE_TICK) {
            running = false;
        }
    }

    private static void tilt(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.TILT));
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo != null) {
            OarAnimator.beginTilt(limbo, SUBMERGE_TICK - TILT_TICK);
        }
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            online.playNotifySound(EclipseSounds.EVENT_SUBMERGE.get(), SoundSource.MASTER, 1.0F, 1.0F);
        }
    }

    /**
     * SUBMERGE + WAVES phase broadcast, plus one {@code eclipse:cutscene_veil} Quasar burst
     * (additive violet streaks) at every limbo player's position, sent to everyone in limbo.
     * The client falls back to vanilla particles if the Quasar spawn fails.
     */
    private static void submerge(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.SUBMERGE));
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.WAVES));
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo != null) {
            for (ServerPlayer player : limbo.players()) {
                PacketDistributor.sendToPlayersInDimension(limbo,
                        new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
            }
        }
    }

    private static void teleportLimboPlayersToOverworld(MinecraftServer server) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        ServerLevel overworld = server.overworld();
        if (limbo == null) {
            EclipseMod.LOGGER.warn("start_event: limbo dimension missing at teleport tick; nothing to teleport");
            return;
        }
        BlockPos spawn = overworld.getSharedSpawnPos();
        List<ServerPlayer> inLimbo = new ArrayList<>(limbo.players());
        for (int i = 0; i < inLimbo.size(); i++) {
            ServerPlayer player = inLimbo.get(i);
            BlockPos column = spawn.offset(columnOffsetX(i), 0, columnOffsetZ(i));
            risePlayerAt(player, overworld, column);
            teleportedPlayers.add(player.getUUID());
        }
        EclipseMod.LOGGER.info("start_event: teleported {} players from limbo to overworld spawn", inLimbo.size());
    }

    /**
     * Carves a temporary 1x2 air pocket whose head block is the column's top surface block
     * (player feet ~2 blocks under the open air), teleports the player into it, and launches
     * them upward. The carved blocks are restored at {@link #REFILL_TICK}.
     */
    private static void risePlayerAt(ServerPlayer player, ServerLevel overworld, BlockPos column) {
        overworld.getChunk(column.getX() >> 4, column.getZ() >> 4); // force-load before height lookup
        int surfaceY = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, column.getX(), column.getZ());
        int feetY = Math.max(surfaceY - 2, overworld.getMinBuildHeight() + 1);

        BlockPos feet = new BlockPos(column.getX(), feetY, column.getZ());
        BlockPos head = feet.above();
        carvedBlocks.add(new CarvedBlock(overworld, feet, overworld.getBlockState(feet)));
        carvedBlocks.add(new CarvedBlock(overworld, head, overworld.getBlockState(head)));
        overworld.setBlockAndUpdate(feet, Blocks.AIR.defaultBlockState());
        overworld.setBlockAndUpdate(head, Blocks.AIR.defaultBlockState());

        player.teleportTo(overworld, feet.getX() + 0.5D, feet.getY(), feet.getZ() + 0.5D,
                overworld.getSharedSpawnAngle(), 0.0F);
        player.setDeltaMovement(new Vec3(0.0D, RISE_VELOCITY, 0.0D));
        player.hurtMarked = true; // sync the velocity to the client
    }

    private static void refillPockets() {
        for (CarvedBlock carved : carvedBlocks) {
            carved.level().setBlockAndUpdate(carved.pos(), carved.previous());
        }
        carvedBlocks.clear();
    }

    private static void emerge(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.EMERGE));
        OarAnimator.endTilt();
        EclipseWorldState.get(server).setStartEventDone(true);
        long now = System.currentTimeMillis();
        for (UUID id : teleportedPlayers) {
            ServerPlayer player = server.getPlayerList().getPlayer(id);
            if (player != null && player.getData(EclipseAttachments.FIRST_OVERWORLD_JOIN) == 0L) {
                player.setData(EclipseAttachments.FIRST_OVERWORLD_JOIN, now);
            }
            if (player != null) {
                // Everyone is gathered at overworld spawn at this point, so broadcast is cheap.
                PacketDistributor.sendToAllPlayers(
                        new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
            }
        }
        teleportedPlayers.clear();
        EclipseMod.LOGGER.info("start_event cutscene finished; startEventDone=true");
    }

    /** Deterministic per-player column spread around spawn so every player gets their own pocket. */
    private static int columnOffsetX(int index) {
        return 2 * (index % 5 - 2);
    }

    private static int columnOffsetZ(int index) {
        return 2 * (index / 5 % 5 - 2);
    }
}
