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
import dev.projecteclipse.eclipse.music.MusicCues;
import dev.projecteclipse.eclipse.network.S2CCutscenePayload;
import dev.projecteclipse.eclipse.network.S2CQuasarPayload;
import dev.projecteclipse.eclipse.registry.EclipseAttachments;
import dev.projecteclipse.eclipse.registry.EclipseSounds;
import dev.projecteclipse.eclipse.sequence.IntroSequence;
import dev.projecteclipse.eclipse.sequence.SequencePayloads;
import dev.projecteclipse.eclipse.start.StartAssignmentService;
import dev.projecteclipse.eclipse.stormfx.StormRegistry;
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
 *   <li>t=80 — MUSICFADE: {@link MusicCues#fadeOut(ServerPlayer, int)} over
 *       {@value #MUSIC_FADE_TICKS} ticks, timed to reach silence exactly at the hop (see
 *       "Music" below).</li>
 *   <li>t=100 — broadcast {@code SUBMERGE} then {@code WAVES} (v1 {@code WaveOverlay}
 *       regression path, untouched), plus one {@code eclipse:cutscene_veil} Quasar burst per
 *       limbo player.</li>
 *   <li>t=120 — {@link SequencePayloads#sendPortalEnter} (18 ticks) for everyone in limbo:
 *       W8's glitch → hold-black covers everything from here — the ship path's ACK at t≈130
 *       and the dimension change both happen behind black, and the vanilla dimension screen
 *       is never the visible surface (R13). STORMFIRST: the same beat calls
 *       {@link IntroSequence#prespawnVortex} so the smoke wall is already standing over the
 *       centre island before anybody is looking at it.</li>
 *   <li>t=140 — teleport every player currently in Limbo onto their own disc
 *       (from {@link StartAssignmentService}, surface-snapped, facing the world center):
 *       re-freeze (survives the hop) + {@link FreezeService#transport} per player, and
 *       remember each player's disc center for {@code IntroSequence}'s framing map. The
 *       storm is re-synced to each hopped player a few ticks later (the client wipes its
 *       storm list on the level swap).</li>
 *   <li>t≥180, GATED — {@link SequencePayloads#sendPortalExit} (24 ticks): the black
 *       releases only once the pre-spawned vortex reports ACTIVE and the post-hop settle
 *       window has passed, with a {@value #PORTAL_EXIT_MAX_HOLD_TICKS}-tick hard cap.</li>
 *   <li>exit+10 — broadcast {@code EMERGE}, set {@code startEventDone}, stamp each
 *       teleported player's {@code first_overworld_join} attachment (voice-mute timer) if
 *       unset, one {@code eclipse:cutscene_veil} burst per emerged player — then hand over
 *       to {@link IntroSequence#start(MinecraftServer, Map)}: eclipse ramp, fusion flight,
 *       vortex, lightning, reveal, sunrise (the fusion itself is started by the sequence at
 *       its FLIGHT phase, no longer here).</li>
 * </ul>
 *
 * <p><b>STORMFIRST (F-016) — why the pre-spawn is here and not in the sequence.</b> The
 * vortex used to spawn at {@code IntroSequence} FLIGHT t=300, i.e. ~19 s after this
 * timeline's black had already released onto the disc. For those 19 s every player stared
 * straight at the bare centre island — the one thing the storm exists to hide. The storm
 * therefore now goes up at t=120, behind the portal black and BEFORE the hop, and the
 * black is held until it is opaque, so the first overworld frame anyone ever sees already
 * has the smoke wall in it.</p>
 *
 * <p><b>MUSICFADE (F-018) — why the fade starts at t=80 and not at EMERGE.</b> The music
 * playing here is the situation ladder's {@code limbo_ambience}, and the t=140 hop is a
 * DIMENSION CHANGE: {@code Minecraft.setLevel} → {@code updateScreenAndTick} →
 * {@code soundManager.stop()} → {@code SoundEngine.stopAll()} kills every channel
 * instantly, no matter what any client-side envelope wants. The old fade lived on the
 * EMERGE broadcast — 20+ ticks AFTER that wipe — so it never touched the limbo bed at all,
 * and the music just stopped dead mid-phrase. The fade is now started
 * {@value #MUSIC_FADE_TICKS} ticks before the hop and reaches zero exactly as the engine
 * wipe lands, which is the only way a fade can survive a dimension change.</p>
 *
 * <p>The v1 {@code S2CCutscenePayload} phases and the client {@code WaveOverlay} are kept
 * untouched (regression path); the camera flight and portal glitch are layered on top, so
 * vanilla-client spectators still see the wave wash and the world.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class StartEventCutscene {
    private static final int TILT_TICK = 0;
    /** MUSICFADE: fade start, chosen so the envelope hits zero exactly at {@link #TELEPORT_TICK}. */
    private static final int MUSIC_FADE_TICK = 80;
    private static final int SUBMERGE_TICK = 100;
    private static final int PORTAL_ENTER_TICK = 120;
    private static final int TELEPORT_TICK = 140;

    private static final int PORTAL_ENTER_TICKS = 18;
    private static final int PORTAL_EXIT_TICKS = 24;
    /**
     * MUSICFADE length. Must land on {@link #TELEPORT_TICK}: shorter leaves an audible gap
     * of silence in Limbo, longer means the engine wipe cuts the tail off anyway.
     */
    private static final int MUSIC_FADE_TICKS = TELEPORT_TICK - MUSIC_FADE_TICK;

    // --- STORMFIRST: the gated black release (see class doc) ---
    /**
     * Earliest black release after the hop. The client needs this long to swap levels, pull
     * the disc chunks and get the storm shells on screen; releasing sooner shows a frame of
     * bare island even though the storm is registered server-side.
     */
    private static final int PORTAL_EXIT_MIN_HOLD_TICKS = 40;
    /**
     * Hard cap on the same hold. A storm that never reports ACTIVE (registry hiccup, no
     * overworld) must never wedge players behind a black screen — the show goes on.
     */
    private static final int PORTAL_EXIT_MAX_HOLD_TICKS = 120;
    /**
     * Post-hop storm re-syncs, in ticks after {@link #TELEPORT_TICK}. {@code StormFxClient}
     * clears its storm list when the level swaps, so a payload that arrived a tick early is
     * simply lost; the registry's own dimension-change resync races that swap. These extra
     * idempotent sends cost one packet each and remove the race entirely.
     */
    private static final int[] STORM_RESYNC_OFFSETS = {5, 15};
    /** EMERGE follows the (gated) black release by this much. */
    private static final int EMERGE_AFTER_EXIT_TICKS = 10;
    /**
     * Freeze TTL bridging the hop until IntroSequence's own ECLIPSE_ON freeze lands. Covers
     * the worst-case gated hold plus EMERGE plus margin — a short TTL would drop players
     * loose behind the black while the gate waits.
     */
    private static final int HOP_FREEZE_TTL_TICKS =
            PORTAL_EXIT_MAX_HOLD_TICKS + EMERGE_AFTER_EXIT_TICKS + 80;
    /** Same-disc spread of overflow players (more players than discs) in blocks. */
    private static final int OVERFLOW_SPREAD_BLOCKS = 3;

    private static boolean running = false;
    private static int ticks = 0;
    /** Tick the (gated) portal exit fired at, or −1 while the black is still held. */
    private static int portalExitTick = -1;
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
        portalExitTick = -1;
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
        portalExitTick = -1;
        teleportedPlayers.clear();
        discCenters.clear();
        OarAnimator.endTilt();
    }

    /**
     * The timeline. Fixed beats up to the hop; from there the black release is GATED on the
     * pre-spawned storm actually standing (STORMFIRST) rather than firing on a fixed tick,
     * because the whole point is that no player ever sees the island without the storm in
     * front of it. {@link #PORTAL_EXIT_MAX_HOLD_TICKS} bounds the wait.
     */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        if (!running) {
            return;
        }
        MinecraftServer server = event.getServer();
        int t = ticks++;
        switch (t) {
            case TILT_TICK -> tilt(server);
            case MUSIC_FADE_TICK -> fadeMusicBeforeHop(server);
            case SUBMERGE_TICK -> submerge(server);
            case PORTAL_ENTER_TICK -> portalEnter(server);
            case TELEPORT_TICK -> teleportLimboPlayersToDiscs(server);
            default -> { /* waiting between phases */ }
        }
        if (t > TELEPORT_TICK && portalExitTick < 0) {
            resyncStormAfterHop(server, t - TELEPORT_TICK);
            if (blackMayRelease(t)) {
                portalExit(server);
                portalExitTick = t;
            }
        } else if (portalExitTick >= 0 && t == portalExitTick + EMERGE_AFTER_EXIT_TICKS) {
            emerge(server);
            running = false;
        }
    }

    /**
     * STORMFIRST gate: hold the black until the disc has had time to render AND the
     * pre-spawned vortex reports opaque, then release. Times out so a missing storm can
     * never wedge the intro behind a black screen.
     */
    private static boolean blackMayRelease(int t) {
        int held = t - TELEPORT_TICK;
        if (held < PORTAL_EXIT_MIN_HOLD_TICKS) {
            return false;
        }
        if (held >= PORTAL_EXIT_MAX_HOLD_TICKS) {
            EclipseMod.LOGGER.warn(
                    "start_event: storm never reported ACTIVE within {} ticks — releasing the black anyway",
                    PORTAL_EXIT_MAX_HOLD_TICKS);
            return true;
        }
        return IntroSequence.isPrespawnedVortexStanding();
    }

    /**
     * MUSICFADE (F-018): start the client-side volume envelope early enough that it reaches
     * zero exactly when the dimension hop's {@code SoundEngine.stopAll()} lands — see the
     * class doc for why a fade started any later is silently discarded.
     */
    private static void fadeMusicBeforeHop(MinecraftServer server) {
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            MusicCues.fadeOut(player, MUSIC_FADE_TICKS);
        }
        EclipseMod.LOGGER.info("start_event: music fading out over {} ticks (silent at the hop)",
                MUSIC_FADE_TICKS);
    }

    /** Re-sends the storm state to the hopped players on the {@link #STORM_RESYNC_OFFSETS} beats. */
    private static void resyncStormAfterHop(MinecraftServer server, int sinceHop) {
        for (int offset : STORM_RESYNC_OFFSETS) {
            if (offset != sinceHop) {
                continue;
            }
            for (UUID id : teleportedPlayers) {
                ServerPlayer player = server.getPlayerList().getPlayer(id);
                if (player != null) {
                    StormRegistry.syncTo(player);
                }
            }
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

    /**
     * R13 portal-enter for everyone in limbo: glitch up, fade to black, HOLD black — and,
     * STORMFIRST, stand the vortex up over the centre island NOW, while nobody can see it.
     * The pre-spawn happens even if limbo is empty: an intro whose cohort joins late still
     * wants the storm standing (a hand-off that never comes is dissipated by
     * {@link IntroSequence#discardPrespawnedVortex}).
     */
    private static void portalEnter(MinecraftServer server) {
        IntroSequence.prespawnVortex(server);
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
        if (limbo == null) {
            EclipseMod.LOGGER.warn("start_event: limbo dimension missing at teleport tick; nothing to teleport");
            return;
        }
        List<ServerPlayer> inLimbo = new ArrayList<>(limbo.players());
        Map<UUID, BlockPos> assignments = StartAssignmentService.assign(server, inLimbo);
        for (ServerPlayer player : inLimbo) {
            BlockPos discCenter = assignments.get(player.getUUID());
            if (discCenter != null) {
                transportToAssignedDisc(server, player, discCenter);
            }
        }
        EclipseMod.LOGGER.info("start_event: teleported {} player(s) from limbo onto their discs", inLimbo.size());
    }

    /**
     * Login seam used by {@link LimboGate}: once the scripted hop has happened, a joiner is
     * assigned and gathered onto that same persisted disc instead of being left in Limbo.
     */
    public static boolean gatherLateJoiner(ServerPlayer player) {
        MinecraftServer server = player.getServer();
        if (server == null || (!running && !IntroSequence.isRunning())) {
            return false;
        }
        if (running && ticks <= TELEPORT_TICK
                && !EclipseWorldState.get(server).isStartEventDone()) {
            return false; // The regular t=140 cohort snapshot will gather them.
        }
        BlockPos discCenter = StartAssignmentService.assign(server, List.of(player.getUUID()))
                .get(player.getUUID());
        if (discCenter == null) {
            return false;
        }
        SequencePayloads.sendPortalEnter(player, 4);
        transportToAssignedDisc(server, player, discCenter);
        SequencePayloads.sendPortalExit(player, PORTAL_EXIT_TICKS);
        EclipseMod.LOGGER.info("start_event: late joiner {} gathered onto assigned disc {}",
                player.getScoreboardName(), discCenter.toShortString());
        return true;
    }

    private static void transportToAssignedDisc(
            MinecraftServer server, ServerPlayer player, BlockPos discCenter) {
        UUID uuid = player.getUUID();
        int overflowRound = (int) discCenters.entrySet().stream()
                .filter(entry -> !entry.getKey().equals(uuid) && entry.getValue().equals(discCenter))
                .count();
        ServerLevel overworld = server.overworld();
        Vec3 spot = discSpot(overworld, discCenter, overflowRound);
        float yaw = yawTowardCenter(spot);
        FreezeService.freeze(player, HOP_FREEZE_TTL_TICKS, true, 0);
        FreezeService.transport(player, overworld, spot, yaw, 10.0F);
        if (!teleportedPlayers.contains(uuid)) {
            teleportedPlayers.add(uuid);
        }
        discCenters.put(uuid, discCenter.immutable());
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
        // Close the t=140→t=160 login race before committing startEventDone.
        teleportLimboPlayersToDiscs(server);
        PacketDistributor.sendToAllPlayers(new S2CCutscenePayload(S2CCutscenePayload.Phase.EMERGE));
        OarAnimator.endTilt();
        // ALTARFIX2 #1: stamp WHEN the event finished — the quest engine's arrival grace
        // (QuestEngine.ARRIVAL_GRACE_TICKS) is measured from this moment, so the players
        // the cutscene just dropped on the sanctum island cannot auto-complete the day-1
        // "touch the altar" goal simply by landing next to it.
        EclipseWorldState.get(server).setStartEventDone(true, server.overworld().getGameTime());
        // PROGFIX #3: no artifact grant here — the artifact chooses everyone only at the
        // storm-touch moment (IntroSequence APPROACH → LIGHTNING latches stormTouched).
        // A8: immediately re-sync the sidebar aggregate so eventStarted reaches every client.
        for (ServerPlayer online : server.getPlayerList().getPlayers()) {
            dev.projecteclipse.eclipse.hud.SidebarSyncService.sendNow(online);
        }
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
        EclipseMod.LOGGER.info("start_event limbo half finished; startEventDone=true — handing over to IntroSequence");
        // R10 hand-off: eclipse ramp, fusion flight, vortex, lightning, reveal, sunrise.
        IntroSequence.start(server, Map.copyOf(discCenters));
        teleportedPlayers.clear();
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
