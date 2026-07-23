package dev.projecteclipse.eclipse.limbo;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.cutscene.CutsceneService;
import dev.projecteclipse.eclipse.cutscene.FreezeService;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.sequence.IntroSequence;
import dev.projecteclipse.eclipse.sequence.SequencePayloads;
import dev.projecteclipse.eclipse.worldgen.DiscGeometry;
import net.minecraft.core.BlockPos;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side timeline of the {@code /start_event} opening — the LIMBO half of the intro:
 * the ghost ship keels over, the world glitches to black, and every player wakes standing
 * on their OWN disc in the overworld; from there the {@code sequence.IntroSequence} phase
 * machine (P2 R10) owns the cinematic. Command registration is the admin worker's job; it
 * just calls {@link #begin(MinecraftServer)}.
 *
 * <p>Tick timeline (driven by a {@link ServerTickEvent.Post} counter, no threads):</p>
 * <ul>
 *   <li>t=0 — broadcast {@code TILT}, keel the ghost ship's oars over (interpolated), play
 *       {@code eclipse:event.submerge} to every online player, and start the
 *       {@code intro_v3_ship} deck flyaround for everyone via {@link CutsceneService#play}
 *       (freeze + client flight; the {@code intro_*} id keeps the freeze across the coming
 *       dimension hop; players outside limbo ACK-finish instantly because the path is
 *       limbo-scoped).</li>
 *   <li>t=100 — broadcast {@code SUBMERGE} then {@code WAVES} (v1 {@code WaveOverlay}
 *       regression path, untouched), plus one {@code eclipse:cutscene_veil} Quasar burst per
 *       limbo player.</li>
 *   <li>t=120 — {@link SequencePayloads#sendPortalEnter} (18 ticks) for everyone in limbo:
 *       W8's glitch → hold-black covers everything from here — the ship path's ACK at t≈130
 *       and the dimension change both happen behind black, and the vanilla dimension screen
 *       is never the visible surface (R13).</li>
 *   <li>t=140 — teleport every player currently in Limbo onto their own disc
 *       ({@link DiscGeometry#playerDiscCenter}, surface-snapped, facing the world center):
 *       re-freeze (survives the hop) + {@link FreezeService#transport} per player, and
 *       remember each player's disc center for {@code IntroSequence}'s framing map.</li>
 *   <li>t=150 — {@link SequencePayloads#sendPortalExit} (24 ticks): the black releases onto
 *       the disc under a still-normal sky.</li>
 *   <li>t=160 — broadcast {@code EMERGE}, set {@code startEventDone}, stamp each teleported
 *       player's {@code first_overworld_join} attachment (voice-mute timer) if unset, one
 *       {@code eclipse:cutscene_veil} burst per emerged player — then hand over to
 *       {@link IntroSequence#start(MinecraftServer, Map)}: eclipse ramp, fusion flight,
 *       vortex, lightning, reveal, sunrise (the fusion itself is started by the sequence at
 *       its FLIGHT phase, no longer here).</li>
 * </ul>
 *
 * <p>The v1 {@code S2CCutscenePayload} phases and the client {@code WaveOverlay} are kept
 * untouched (regression path); the camera flight and portal glitch are layered on top, so
 * vanilla-client spectators still see the wave wash and the world.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StartEventCutscene {
    private static final int TILT_TICK = 0;
    private static final int SUBMERGE_TICK = 100;
    private static final int PORTAL_ENTER_TICK = 120;
    private static final int TELEPORT_TICK = 140;
    private static final int PORTAL_EXIT_TICK = 150;
    private static final int EMERGE_TICK = 160;

    private static final int PORTAL_ENTER_TICKS = 18;
    private static final int PORTAL_EXIT_TICKS = 24;
    /** Freeze TTL bridging the hop until IntroSequence's own ECLIPSE_ON freeze lands. */
    private static final int HOP_FREEZE_TTL_TICKS = (EMERGE_TICK - TELEPORT_TICK) + 80;
    /** Same-disc spread of overflow players (more players than discs) in blocks. */
    private static final int OVERFLOW_SPREAD_BLOCKS = 3;

    private static boolean running = false;
    private static int ticks = 0;
    private static final List<UUID> teleportedPlayers = new ArrayList<>();
    private static final Map<UUID, BlockPos> discCenters = new HashMap<>();

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
        teleportedPlayers.clear();
        discCenters.clear();
        EclipseMod.LOGGER.info("start_event cutscene beginning");
        return true;
    }

    /**
     * Restart hygiene: the timeline statics must never leak into the next world a
     * singleplayer client opens — stopping mid-cutscene would otherwise resume the tick
     * counter on a world that never played its intro. The suspended oar tilt is released
     * too, or the rowing loop would stay frozen forever after a stop mid-intro.
     */
    @SubscribeEvent
    public static void onServerStopped(ServerStoppedEvent event) {
        running = false;
        ticks = 0;
        teleportedPlayers.clear();
        discCenters.clear();
        OarAnimator.endTilt();
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
            case PORTAL_ENTER_TICK -> portalEnter(server);
            case TELEPORT_TICK -> teleportLimboPlayersToDiscs(server);
            case PORTAL_EXIT_TICK -> portalExit(server);
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
        // Camera flight on top of the v1 overlay phases. Limbo-scoped: players elsewhere
        // ACK-finish instantly and lose their freeze right away (see CameraDirector).
        CutsceneService.play("intro_v3_ship", List.copyOf(server.getPlayerList().getPlayers()));
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

    /** R13 portal-enter for everyone in limbo: glitch up, fade to black, HOLD black. */
    private static void portalEnter(MinecraftServer server) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        if (limbo == null) {
            return;
        }
        for (ServerPlayer player : limbo.players()) {
            SequencePayloads.sendPortalEnter(player, PORTAL_ENTER_TICKS);
        }
    }

    /**
     * The limbo → overworld hop, entirely behind black: each player lands on their OWN
     * disc, surface-snapped and facing the world center. The freeze is re-applied first
     * (survives-dimension-change) so a straggling ship-path ACK can never leave anyone
     * loose mid-hop, and {@link FreezeService#transport} re-anchors it at the disc.
     */
    private static void teleportLimboPlayersToDiscs(MinecraftServer server) {
        ServerLevel limbo = server.getLevel(LimboDimension.LIMBO);
        ServerLevel overworld = server.overworld();
        if (limbo == null) {
            EclipseMod.LOGGER.warn("start_event: limbo dimension missing at teleport tick; nothing to teleport");
            return;
        }
        List<ServerPlayer> inLimbo = new ArrayList<>(limbo.players());
        for (int i = 0; i < inLimbo.size(); i++) {
            ServerPlayer player = inLimbo.get(i);
            BlockPos discCenter = DiscGeometry.playerDiscCenter(i % DiscGeometry.PLAYER_DISC_COUNT);
            Vec3 spot = discSpot(overworld, discCenter, i / DiscGeometry.PLAYER_DISC_COUNT);
            float yaw = yawTowardCenter(spot);
            FreezeService.freeze(player, HOP_FREEZE_TTL_TICKS, true, 0);
            FreezeService.transport(player, overworld, spot, yaw, 10.0F);
            teleportedPlayers.add(player.getUUID());
            discCenters.put(player.getUUID(), discCenter.immutable());
        }
        EclipseMod.LOGGER.info("start_event: teleported {} player(s) from limbo onto their discs", inLimbo.size());
    }

    /** R13 portal-exit for the hopped players: release the black with a glitch tail. */
    private static void portalExit(MinecraftServer server) {
        for (UUID id : teleportedPlayers) {
            ServerPlayer player = server.getPlayerList().getPlayer(id);
            if (player != null) {
                SequencePayloads.sendPortalExit(player, PORTAL_EXIT_TICKS);
            }
        }
    }

    private static void emerge(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.EMERGE));
        OarAnimator.endTilt();
        EclipseWorldState.get(server).setStartEventDone(true);
        long now = System.currentTimeMillis();
        ServerLevel overworld = server.overworld();
        for (UUID id : teleportedPlayers) {
            ServerPlayer player = server.getPlayerList().getPlayer(id);
            if (player == null) {
                continue;
            }
            if (player.getData(EclipseAttachments.FIRST_OVERWORLD_JOIN) == 0L) {
                player.setData(EclipseAttachments.FIRST_OVERWORLD_JOIN, now);
            }
            // Players are spread across the disc ring now — scope the bursts to the dimension.
            PacketDistributor.sendToPlayersInDimension(overworld,
                    new S2CQuasarPayload(S2CQuasarPayload.CUTSCENE_VEIL, player.position()));
        }
        teleportedPlayers.clear();
        EclipseMod.LOGGER.info("start_event limbo half finished; startEventDone=true — handing over to IntroSequence");
        // R10 hand-off: eclipse ramp, fusion flight, vortex, lightning, reveal, sunrise.
        IntroSequence.start(server, dev.projecteclipse.eclipse.start.StartAssignmentService.assign(server, discCenters.keySet()));
        discCenters.clear();
    }

    /**
     * The landing spot on a disc: its center column (overflow rounds > the disc count spread
     * on a small deterministic ring), snapped to the terrain surface.
     */
    private static Vec3 discSpot(ServerLevel overworld, BlockPos discCenter, int overflowRound) {
        int x = discCenter.getX();
        int z = discCenter.getZ();
        if (overflowRound > 0) {
            // 9+ players: rounds 1+ ring the same disc centers at 3, 6, ... blocks out.
            double angle = overflowRound * 2.399963229728653D; // golden angle, deterministic
            x += (int) Math.round(Math.cos(angle) * OVERFLOW_SPREAD_BLOCKS * overflowRound);
            z += (int) Math.round(Math.sin(angle) * OVERFLOW_SPREAD_BLOCKS * overflowRound);
        }
        overworld.getChunk(x >> 4, z >> 4); // force-load before the height lookup
        int surfaceY = overworld.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES, x, z);
        if (surfaceY <= overworld.getMinBuildHeight()) {
            surfaceY = overworld.getSeaLevel(); // void column safety: never drop anyone
        }
        return new Vec3(x + 0.5D, surfaceY, z + 0.5D);
    }

    /** Yaw looking from {@code from} at the world center (discs are origin-centered). */
    private static float yawTowardCenter(Vec3 from) {
        return (float) Math.toDegrees(Math.atan2(from.x, -from.z));
    }
}
