package dev.projecteclipse.eclipse.cutscene;

import java.nio.charset.StandardCharsets;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.C2SCutsceneReadyPayload;
import dev.projecteclipse.eclipse.network.C2SCutsceneStatePayload;
import dev.projecteclipse.eclipse.network.S2CCutsceneLibraryPayload;
import dev.projecteclipse.eclipse.network.S2CCutscenePlayPayload;
import dev.projecteclipse.eclipse.network.fx.S2CScreenFadePayload;
import dev.projecteclipse.eclipse.progression.BorderController;
import net.minecraft.core.BlockPos;
import net.minecraft.core.HolderLookup;
import net.minecraft.core.registries.Registries;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.Tag;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.level.TicketType;
import net.minecraft.world.level.ChunkPos;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.saveddata.SavedData;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Server-side cutscene orchestration ({@code docs/ideas/05_systems.md} §1): the server owns
 * WHO is watching WHAT and the freeze; the client owns the camera flight.
 *
 * <p><b>Play flow</b>: {@link #play(String, Collection)} freezes each watcher for
 * {@code durationTicks + }{@value #WATCHDOG_MARGIN_TICKS} ({@link FreezeService}) and sends a
 * compact {@link S2CCutscenePlayPayload}; the client evaluates the path (already synced as a
 * library at login) and ACKs {@code STARTED} → {@code FINISHED}/{@code SKIPPED} via
 * {@link C2SCutsceneStatePayload}. A {@code FINISHED}/{@code SKIPPED} ACK releases that
 * player's freeze immediately; the per-player session watchdog (same
 * {@code durationTicks + 100} deadline, checked every server tick) releases players whose ACK
 * never arrives (crashed client, vanilla client, packet loss) so nobody is ever stuck.
 * Sessions also complete at logout. Intro paths (id {@code intro_*}) freeze with the
 * survives-dimension-change flag so the scripted limbo → overworld teleport keeps the lock.</p>
 *
 * <p><b>Global plays</b> (P2 R12): {@link #play(String, Collection, Vec3, Runnable, PlayOptions)}
 * with {@link TeleportPolicy#GLOBAL_TELEPORT} gathers watchers who are far from the sequence
 * area or in another dimension: each is snapshotted (position, dimension, rotation — vehicles
 * are dismounted), sent a screen fade, and {@link FreezeService#transport}ed to a ring around
 * the area before the freeze lands. With {@code returnAfter} the snapshot is restored exactly
 * when the session ends — on ACK, skip, abort, or the watchdog; a player who logs out
 * mid-cutscene is moved back before vanilla saves them (same dimension) or via the persisted
 * {@link PendingReturns} data at their next login (cross-dimension), so nobody is ever
 * stranded at a sequence area. {@code PlayOptions.viewDistance} additionally routes through
 * {@link ViewDistanceService} (server bump + client push) for the duration of the group.</p>
 *
 * <p><b>Dynamic anchors</b> (P2 R12, W7's {@code "growth_front"}): when a path declares
 * {@code params.dynamicAnchor} and the caller passes no explicit anchor, the resolver
 * registered under that key ({@link #registerDynamicAnchor}) supplies the play anchor at play
 * time.</p>
 *
 * <p><b>Skip flow</b>: {@code SKIP_REQUEST} is validated against the path's {@code allowSkip}
 * and the per-world disabled set; a granted skip answers with the
 * {@link S2CCutscenePlayPayload#STOP} sentinel and completes the session server-side
 * (the client's own abort then double-ACKs {@code SKIPPED}, which is ignored).</p>
 *
 * <p><b>Disabled paths</b> ({@code enabled:false} in the JSON, or the persisted
 * {@code disabledCutscenes} set in {@link EclipseWorldState}) skip straight to the end-state
 * callback: no freeze, no payload, no softlock — server timelines (intro, unlock growth)
 * proceed as if the cutscene finished instantly.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class CutsceneService {
    /** Watchdog slack on top of a path's {@code durationTicks} (freeze TTL and session deadline). */
    public static final int WATCHDOG_MARGIN_TICKS = 100;

    /**
     * C6 chunk-preload hold cap, shared with the client ({@code CameraDirector}): a flight
     * whose chunks never arrive starts regardless after this many ticks. Freeze TTLs and
     * session deadlines budget it on top of {@code durationTicks}, and the client's
     * {@link C2SCutsceneReadyPayload} re-arms the deadline when the flight actually starts.
     */
    public static final int PRELOAD_TIMEOUT_TICKS = 100;

    /** Auto-expiring region ticket that pre-loads the columns under a camera path (C6). */
    private static final TicketType<ChunkPos> PRELOAD_TICKET = TicketType.create(
            "eclipse_cutscene_preload", Comparator.comparingLong(ChunkPos::toLong),
            PRELOAD_TIMEOUT_TICKS + 200);
    /** Whole-path arc-length fractions sampled for preload tickets (plus both endpoints). */
    private static final int PRELOAD_PATH_SAMPLES = 12;
    /** Region-ticket radius per sampled column (1 → a 3×3 of chunks per sample). */
    private static final int PRELOAD_TICKET_RADIUS = 1;
    /** Hard cap of ticketed columns per play — bounds server load on absurd operator paths. */
    private static final int PRELOAD_MAX_COLUMNS = 48;

    /**
     * Air gap (blocks) under a heightmap surface that marks it as a FLOATING SHELL rather
     * than real ground (C6 return healing — the day-12 "returned onto the End island" bug).
     */
    private static final int FLOATING_SHELL_AIR_GAP = 32;

    /** Library sync budget: entries past this many UTF-8 payload bytes are dropped. */
    private static final int MAX_LIBRARY_SYNC_BYTES = 512 * 1024;

    /** Players within this horizontal distance of the sequence area are not gathered. */
    private static final double GLOBAL_GATHER_RADIUS = 128.0D;
    /** Ring radius around the sequence area that gathered players are placed on. */
    private static final double GATHER_RING_RADIUS = 6.0D;
    /** Fade covering the outbound gather teleport (hold spans the chunk-load moment). */
    private static final S2CScreenFadePayload GATHER_FADE = new S2CScreenFadePayload(8, 30, 18, 0xFF000000);
    /** Fade covering the return teleport. */
    private static final S2CScreenFadePayload RETURN_FADE = new S2CScreenFadePayload(8, 20, 16, 0xFF000000);

    // --- play options (P2 R12, frozen for W6/W7) ---

    /** Where the watchers physically are during the cutscene. */
    public enum TeleportPolicy {
        /** Players stay wherever they are (v1 behaviour). */
        LOCAL_ONLY,
        /** Far/other-dimension players are gathered to the sequence area behind a fade. */
        GLOBAL_TELEPORT
    }

    /**
     * Options for the full play form. {@code viewDistance} is the client-push chunk count
     * routed through {@link ViewDistanceService} ({@code 0} skips the bump entirely);
     * {@code returnAfter} restores gathered players to their snapshot when the session ends.
     */
    public record PlayOptions(TeleportPolicy teleportPolicy, int viewDistance, boolean returnAfter) {
        /** v1 behaviour: nobody moves, no view-distance bump. */
        public static final PlayOptions LOCAL = new PlayOptions(TeleportPolicy.LOCAL_ONLY, 0, false);

        /** Gather far/other-dimension players, bump view distance, return everyone after. */
        public static PlayOptions global(int viewDistanceChunks) {
            return new PlayOptions(TeleportPolicy.GLOBAL_TELEPORT, viewDistanceChunks, true);
        }

        /** Gather without returning (the sequence itself repositions players afterwards). */
        public static PlayOptions globalOneWay(int viewDistanceChunks) {
            return new PlayOptions(TeleportPolicy.GLOBAL_TELEPORT, viewDistanceChunks, false);
        }
    }

    /** Server-side anchor substitution hook for {@code params.dynamicAnchor} paths. */
    @FunctionalInterface
    public interface DynamicAnchorResolver {
        /** Returns the play anchor, or {@code null} to fall back to the path's own frame. */
        @Nullable
        Vec3 resolve(MinecraftServer server, Collection<ServerPlayer> players);
    }

    /** Where a gathered player came from; restored when their session completes. */
    private record ReturnSnapshot(ResourceKey<Level> dimension, Vec3 pos, float yRot, float xRot) {}

    /** Tracks one watcher group so a completion callback fires exactly once. */
    private static final class Group {
        final String pathId;
        final @Nullable Runnable onAllFinished;
        int remaining;
        boolean done;

        Group(String pathId, int remaining, @Nullable Runnable onAllFinished) {
            this.pathId = pathId;
            this.remaining = remaining;
            this.onAllFinished = onAllFinished;
        }

        void playerDone() {
            if (!this.done && --this.remaining <= 0) {
                this.done = true;
                if (this.onAllFinished != null) {
                    this.onAllFinished.run();
                }
            }
        }
    }

    /**
     * One player's active playback; {@code preview} sessions have no freeze to release.
     * The deadline is mutable: the client's preload-ready ACK re-arms it to the flight's
     * REAL start moment (C6), so a long chunk hold never eats into the watchdog margin.
     */
    private static final class Session {
        private final String pathId;
        private final boolean preview;
        private final Group group;
        private long deadlineTick;

        Session(String pathId, long deadlineTick, boolean preview, Group group) {
            this.pathId = pathId;
            this.deadlineTick = deadlineTick;
            this.preview = preview;
            this.group = group;
        }

        String pathId() {
            return this.pathId;
        }

        long deadlineTick() {
            return this.deadlineTick;
        }

        boolean preview() {
            return this.preview;
        }

        Group group() {
            return this.group;
        }

        /** Pushes the deadline out (never pulls it in — ACKs release early anyway). */
        void rearmDeadline(long newDeadlineTick) {
            this.deadlineTick = Math.max(this.deadlineTick, newDeadlineTick);
        }
    }

    /** Active sessions by player UUID. Server-thread only (tick + main-thread payload handlers). */
    private static final Map<UUID, Session> SESSIONS = new HashMap<>();

    /**
     * Pending return snapshots of gathered players by UUID. Server-thread only. The FIRST
     * snapshot wins across chained global cutscenes — a supersede never re-snapshots, so the
     * player always returns to their true origin after the last scene of a chain.
     */
    private static final Map<UUID, ReturnSnapshot> RETURNS = new HashMap<>();

    /** Dynamic-anchor resolvers by {@code params.dynamicAnchor} key (W7 registers {@code growth_front}). */
    private static final Map<String, DynamicAnchorResolver> DYNAMIC_ANCHOR_RESOLVERS = new HashMap<>();

    private CutsceneService() {}

    // --- library sync ---

    /** Sends the full path library to one player (login sync; see {@code EclipsePayloads}). */
    public static void syncLibraryTo(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2CCutsceneLibraryPayload(cappedLibrary()));
    }

    /** Re-sends the full path library to everyone (after {@code reloadpaths} / editor writes). */
    public static void syncLibraryToAll(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutsceneLibraryPayload(cappedLibrary()));
    }

    /**
     * The raw-JSON library capped at {@value #MAX_LIBRARY_SYNC_BYTES} UTF-8 bytes (the payload
     * writes each id + document via {@code writeUtf}): excess entries are dropped with a log
     * so operator-grown files can never push the sync past the packet limit.
     */
    private static Map<String, String> cappedLibrary() {
        Map<String, String> all = CutscenePaths.rawJsonById();
        Map<String, String> capped = new LinkedHashMap<>();
        long bytes = 0;
        for (Map.Entry<String, String> entry : all.entrySet()) {
            bytes += entry.getKey().getBytes(StandardCharsets.UTF_8).length
                    + entry.getValue().getBytes(StandardCharsets.UTF_8).length;
            if (bytes > MAX_LIBRARY_SYNC_BYTES) {
                EclipseMod.LOGGER.warn("Cutscene library sync over {} bytes — dropping {} of {} paths (from '{}')",
                        MAX_LIBRARY_SYNC_BYTES, all.size() - capped.size(), all.size(), entry.getKey());
                break;
            }
            capped.put(entry.getKey(), entry.getValue());
        }
        return capped;
    }

    // --- enable / disable ---

    /** Whether a path may play: its JSON {@code enabled} flag AND the per-world disabled set. */
    public static boolean isEnabled(MinecraftServer server, CutscenePath path) {
        return path.enabled() && !EclipseWorldState.get(server).isCutsceneDisabled(path.id());
    }

    // --- dynamic anchors ---

    /**
     * Registers the resolver for one {@code params.dynamicAnchor} key. Call from static init
     * or server setup (W7: {@code "growth_front"} → nearest point of the new ring band).
     * Re-registration replaces.
     */
    public static void registerDynamicAnchor(String key, DynamicAnchorResolver resolver) {
        DYNAMIC_ANCHOR_RESOLVERS.put(key, resolver);
    }

    @Nullable
    private static Vec3 resolveDynamicAnchor(MinecraftServer server, CutscenePath path,
            Collection<ServerPlayer> players) {
        String key = path.dynamicAnchor();
        if (key == null) {
            return null;
        }
        DynamicAnchorResolver resolver = DYNAMIC_ANCHOR_RESOLVERS.get(key);
        if (resolver == null) {
            EclipseMod.LOGGER.warn("CutsceneService: path '{}' wants dynamicAnchor '{}' but no resolver is registered",
                    path.id(), key);
            return null;
        }
        Vec3 resolved = resolver.resolve(server, players);
        EclipseMod.LOGGER.info("CutsceneService: dynamicAnchor '{}' of '{}' resolved to {}",
                key, path.id(), resolved);
        return resolved;
    }

    // --- playback ---

    /** Plays a path for the given players (freeze + play payload). Returns watchers started. */
    public static int play(String id, Collection<ServerPlayer> players) {
        return play(id, players, null, null);
    }

    /** v1 full form — local play, no view-distance bump (see the PlayOptions overload). */
    public static int play(String id, Collection<ServerPlayer> players, @Nullable Vec3 anchor,
            @Nullable Runnable onAllFinished) {
        return play(id, players, anchor, onAllFinished, PlayOptions.LOCAL);
    }

    /**
     * Full play form: {@code anchor} overrides the world-anchor origin (e.g. the nearest new
     * ring edge for {@code unlock_ring}); when it is {@code null} a {@code dynamicAnchor}
     * resolver may supply it. {@code onAllFinished} runs on the server thread once every
     * watcher has ACKed, been watchdog-released, or logged out — and runs immediately when
     * the path is missing/disabled or {@code players} is empty (never softlocks a caller's
     * timeline). {@code options} adds the R12 global behaviours (gather teleport,
     * view-distance bump, return-after).
     */
    public static int play(String id, Collection<ServerPlayer> players, @Nullable Vec3 anchor,
            @Nullable Runnable onAllFinished, PlayOptions options) {
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            EclipseMod.LOGGER.warn("CutsceneService: unknown path '{}' — completing instantly", id);
            if (onAllFinished != null) {
                onAllFinished.run();
            }
            return 0;
        }
        if (players.isEmpty()) {
            EclipseMod.LOGGER.info("CutsceneService: no players to play '{}' for — completing instantly", id);
            if (onAllFinished != null) {
                onAllFinished.run();
            }
            return 0;
        }
        MinecraftServer server = players.iterator().next().server;
        if (!isEnabled(server, path)) {
            EclipseMod.LOGGER.info("CutsceneService: path '{}' is disabled — skipping straight to completion", id);
            if (onAllFinished != null) {
                onAllFinished.run();
            }
            return 0;
        }

        Vec3 playAnchor = anchor != null ? anchor : resolveDynamicAnchor(server, path, players);
        // C6: freeze TTLs + session deadlines budget the client's chunk-preload hold too;
        // the C2SCutsceneReadyPayload re-arms the deadline when the flight really starts.
        int watchdogTicks = path.durationTicks() + PRELOAD_TIMEOUT_TICKS + WATCHDOG_MARGIN_TICKS;
        long deadline = server.getTickCount() + watchdogTicks;
        boolean intro = id.startsWith("intro_");

        Runnable groupCallback = onAllFinished;
        if (options.viewDistance() > 0) {
            ViewDistanceService.begin(server, players, options.viewDistance(), watchdogTicks);
            Runnable original = onAllFinished;
            groupCallback = () -> {
                ViewDistanceService.end(server);
                if (original != null) {
                    original.run();
                }
            };
        }
        if (options.teleportPolicy() == TeleportPolicy.GLOBAL_TELEPORT) {
            gatherPlayers(server, path, players, playAnchor, options.returnAfter());
        }
        preloadPathChunks(server, path, playAnchor);

        Group group = new Group(id, players.size(), groupCallback);
        S2CCutscenePlayPayload payload =
                new S2CCutscenePlayPayload(id, path.allowSkip(), Optional.ofNullable(playAnchor));
        for (ServerPlayer player : players) {
            // A newer cutscene supersedes any active session (its group completes as skipped);
            // pending return snapshots survive the supersede so chains return to the origin.
            completeSession(player, "superseded by '" + id + "'");
            FreezeService.freeze(player, watchdogTicks, intro, 0);
            SESSIONS.put(player.getUUID(), new Session(id, deadline, false, group));
            PacketDistributor.sendToPlayer(player, payload);
        }
        EclipseMod.LOGGER.info("CutsceneService: playing '{}' for {} player(s) "
                + "(duration {} ticks, watchdog {} ticks, allowSkip {}, anchor {}, policy {}, viewDist {}, return {})",
                id, players.size(), path.durationTicks(), watchdogTicks, path.allowSkip(), playAnchor,
                options.teleportPolicy(), options.viewDistance(), options.returnAfter());
        return players.size();
    }

    /**
     * C6 chunk preload: auto-expiring region tickets along the sampled keyframe path, so
     * the server loads (and its chunk tracker sends) the flight's terrain while the
     * watching clients hold on their black veil ({@code CameraDirector}'s preload hold —
     * released by chunk arrival or the shared {@value #PRELOAD_TIMEOUT_TICKS}-tick
     * timeout). Player-anchored paths fly right next to their watcher, whose chunks are
     * loaded by definition, and need no tickets.
     */
    private static void preloadPathChunks(MinecraftServer server, CutscenePath path, @Nullable Vec3 anchor) {
        if (path.isPlayerAnchored() || path.keyframes().size() < 2) {
            return;
        }
        ServerLevel level = resolveLevel(server, path.dimension());
        if (level == null) {
            return;
        }
        Vec3 origin = anchor != null ? anchor : Vec3.ZERO;
        PathSampler sampler = PathSampler.of(path);
        Set<Long> columns = new LinkedHashSet<>();
        for (int i = 0; i <= PRELOAD_PATH_SAMPLES && columns.size() < PRELOAD_MAX_COLUMNS; i++) {
            Vec3 world = PathSampler.toWorld(
                    sampler.positionAtPathFraction(i / (double) PRELOAD_PATH_SAMPLES), origin, 0.0F);
            BlockPos pos = BlockPos.containing(world.x, world.y, world.z);
            columns.add(ChunkPos.asLong(pos.getX() >> 4, pos.getZ() >> 4));
        }
        for (long packed : columns) {
            ChunkPos pos = new ChunkPos(packed);
            level.getChunkSource().addRegionTicket(PRELOAD_TICKET, pos, PRELOAD_TICKET_RADIUS, pos);
        }
        EclipseMod.LOGGER.info("CutsceneService: preload-ticketed {} column(s) along '{}' in {}",
                columns.size(), path.id(), level.dimension().location());
    }

    /**
     * Operator preview: play payload only — no freeze, no invulnerability. The session is
     * still tracked so ACKs log and the watchdog cleans up.
     */
    public static boolean preview(String id, ServerPlayer player) {
        CutscenePath path = CutscenePaths.get(id);
        if (path == null) {
            return false;
        }
        completeSession(player, "superseded by preview '" + id + "'");
        SESSIONS.put(player.getUUID(), new Session(id,
                player.server.getTickCount() + path.durationTicks() + WATCHDOG_MARGIN_TICKS, true,
                new Group(id, 1, null)));
        PacketDistributor.sendToPlayer(player,
                new S2CCutscenePlayPayload(id, true, Optional.empty()));
        EclipseMod.LOGGER.info("CutsceneService: previewing '{}' for {} (no freeze)",
                id, player.getScoreboardName());
        return true;
    }

    /** Aborts the given players' active cutscenes: unfreeze + client stop sentinel + return. */
    public static int abort(Collection<ServerPlayer> players) {
        int aborted = 0;
        for (ServerPlayer player : players) {
            boolean hadSession = SESSIONS.containsKey(player.getUUID());
            completeSession(player, "aborted");
            FreezeService.unfreeze(player);
            restoreReturn(player, "aborted");
            if (hadSession) {
                PacketDistributor.sendToPlayer(player, S2CCutscenePlayPayload.STOP);
                aborted++;
            }
        }
        return aborted;
    }

    /** The path id the player is currently watching, or {@code null}. */
    @Nullable
    public static String activePathId(ServerPlayer player) {
        Session session = SESSIONS.get(player.getUUID());
        return session != null ? session.pathId() : null;
    }

    // --- global gather / return (P2 R12) ---

    /**
     * Teleports far/other-dimension watchers to a ring around the sequence area, behind a
     * screen fade. The area is the play anchor when present, otherwise the centroid of the
     * path's (world-anchored) keyframes; player-anchored paths have nothing to gather to.
     */
    private static void gatherPlayers(MinecraftServer server, CutscenePath path,
            Collection<ServerPlayer> players, @Nullable Vec3 anchor, boolean recordReturns) {
        if (path.isPlayerAnchored()) {
            EclipseMod.LOGGER.warn("CutsceneService: GLOBAL_TELEPORT requested for player-anchored path '{}' — nothing to gather to",
                    path.id());
            return;
        }
        ServerLevel level = resolveLevel(server, path.dimension());
        if (level == null) {
            EclipseMod.LOGGER.warn("CutsceneService: unknown dimension '{}' of path '{}' — gather skipped",
                    path.dimension(), path.id());
            return;
        }
        Vec3 area = anchor != null ? anchor : keyframeCentroid(path);
        if (area == null) {
            EclipseMod.LOGGER.warn("CutsceneService: path '{}' has no keyframes — gather skipped", path.id());
            return;
        }
        int index = 0;
        int count = Math.max(1, players.size());
        for (ServerPlayer player : players) {
            index++;
            boolean sameLevel = player.serverLevel() == level;
            if (sameLevel && player.position().multiply(1.0D, 0.0D, 1.0D)
                    .distanceTo(new Vec3(area.x, 0.0D, area.z)) <= GLOBAL_GATHER_RADIUS) {
                continue; // Close enough — they watch from where they stand.
            }
            if (recordReturns) {
                // putIfAbsent: across chained global scenes the FIRST origin wins.
                RETURNS.putIfAbsent(player.getUUID(), new ReturnSnapshot(
                        player.level().dimension(), player.position(), player.getYRot(), player.getXRot()));
            }
            PacketDistributor.sendToPlayer(player, GATHER_FADE);
            Vec3 spot = gatherSpot(level, area, index, count);
            FreezeService.transport(player, level, spot, player.getYRot(), player.getXRot());
            EclipseMod.LOGGER.info("CutsceneService: gathered {} to {} in {} for '{}'{}",
                    player.getScoreboardName(), spot, level.dimension().location(), path.id(),
                    recordReturns ? " (return pending)" : "");
        }
    }

    /**
     * A spot on the gather ring, snapped to the surface when the heightmap knows better —
     * unless that "surface" is a floating shell far above the sequence area (C6: the End
     * disc's heightmap must not host gathered players hundreds of blocks over the show).
     */
    private static Vec3 gatherSpot(ServerLevel level, Vec3 area, int index, int count) {
        double angle = (Math.PI * 2.0D * index) / count;
        double x = area.x + Math.cos(angle) * GATHER_RING_RADIUS;
        double z = area.z + Math.sin(angle) * GATHER_RING_RADIUS;
        BlockPos top = level.getHeightmapPos(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                BlockPos.containing(x, area.y, z));
        double y = top.getY() > level.getMinBuildHeight() ? top.getY() : area.y;
        if (y > area.y + 2.0D
                && isFloatingShellAbove(level, BlockPos.containing(x, 0.0D, z), top.getY() - 1, area.y)) {
            y = area.y;
        }
        return new Vec3(x, y, z);
    }

    @Nullable
    private static ServerLevel resolveLevel(MinecraftServer server, String dimensionId) {
        try {
            return server.getLevel(ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(dimensionId)));
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** Centroid of the path's keyframe positions (world-anchored paths only). */
    @Nullable
    private static Vec3 keyframeCentroid(CutscenePath path) {
        if (path.keyframes().isEmpty()) {
            return null;
        }
        double x = 0.0D;
        double y = 0.0D;
        double z = 0.0D;
        for (CutscenePath.Keyframe kf : path.keyframes()) {
            x += kf.x();
            y += kf.y();
            z += kf.z();
        }
        int n = path.keyframes().size();
        return new Vec3(x / n, y / n, z / n);
    }

    /** Restores a gathered player to their snapshot (fade + transport). No-op without one. */
    private static void restoreReturn(ServerPlayer player, String reason) {
        ReturnSnapshot snapshot = RETURNS.remove(player.getUUID());
        if (snapshot == null) {
            return;
        }
        ServerLevel level = player.server.getLevel(snapshot.dimension());
        if (level == null) {
            EclipseMod.LOGGER.warn("CutsceneService: return dimension {} of {} is gone — not restoring",
                    snapshot.dimension().location(), player.getScoreboardName());
            return;
        }
        Vec3 returnPos = validatedReturnPosition(level, snapshot.pos());
        PacketDistributor.sendToPlayer(player, RETURN_FADE);
        FreezeService.transport(player, level, returnPos, snapshot.yRot(), snapshot.xRot());
        EclipseMod.LOGGER.info("CutsceneService: returned {} to {} in {} ({})",
                player.getScoreboardName(), returnPos, snapshot.dimension().location(), reason);
    }

    /**
     * Heals stale snapshots and origins covered by terrain written during a cutscene.
     *
     * <p>A snapshot whose spot still stands FREE is returned untouched — in particular it is
     * never snapped UP just because the column's heightmap towers above it (C6: the day-12
     * "returned onto the End island" bug — the return column pierced the vortex disc, and the
     * old {@code y < surface - 2} heightmap snap hoisted players hundreds of blocks onto the
     * shell). Only a buried or below-world snapshot climbs, and it climbs to the FIRST free
     * two-block gap above itself, not to the heightmap top.</p>
     */
    private static Vec3 validatedReturnPosition(ServerLevel level, Vec3 pos) {
        BlockPos column = BlockPos.containing(pos.x, 0.0D, pos.z);
        level.getChunk(column.getX() >> 4, column.getZ() >> 4); // block + heightmap reads need it
        int minY = level.getMinBuildHeight();
        int feetY = (int) Math.floor(pos.y);
        if (pos.y >= minY && isFreeSpot(level, column.atY(feetY))) {
            return pos;
        }
        int safeY = Math.max(level.getHeight(Heightmap.Types.MOTION_BLOCKING_NO_LEAVES,
                column.getX(), column.getZ()), minY + 1);
        int start = Math.max(feetY, minY);
        int limit = Math.min(Math.max(safeY, start), level.getMaxBuildHeight() - 2);
        for (int y = start; y <= limit; y++) {
            if (isFreeSpot(level, column.atY(y))) {
                return new Vec3(pos.x, y, pos.z);
            }
        }
        return new Vec3(pos.x, safeY, pos.z);
    }

    /** Feet and head blocks free of motion-blocking collision — a player fits here. */
    private static boolean isFreeSpot(ServerLevel level, BlockPos feet) {
        return !hasCollision(level, feet) && !hasCollision(level, feet.above());
    }

    /** Whether the block at {@code pos} has any collision shape (a stand-in for the deprecated blocksMotion). */
    private static boolean hasCollision(ServerLevel level, BlockPos pos) {
        return !level.getBlockState(pos).getCollisionShape(level, pos).isEmpty();
    }

    /**
     * True when the heightmap "surface" ending at {@code surfaceY} (its top motion-blocking
     * block) is a FLOATING SHELL rather than real ground: under at most a few blocks of crust
     * yawns a drop of {@value #FLOATING_SHELL_AIR_GAP}+ blocks of air — or pure air all the
     * way down to {@code baseY}. Such shells (the vortex End disc, leftover build artifacts)
     * must never host gathered or returned players (C6).
     */
    private static boolean isFloatingShellAbove(ServerLevel level, BlockPos column, int surfaceY, double baseY) {
        final int maxShellThickness = 8;
        int floor = Math.max(level.getMinBuildHeight(), (int) Math.floor(baseY));
        int y = surfaceY;
        int thickness = 0;
        while (y >= floor && thickness < maxShellThickness && hasCollision(level, column.atY(y))) {
            y--;
            thickness++;
        }
        if (thickness >= maxShellThickness) {
            return false; // Solid that deep is terrain, not a shell.
        }
        int gap = 0;
        while (y >= floor) {
            if (hasCollision(level, column.atY(y))) {
                return gap >= FLOATING_SHELL_AIR_GAP;
            }
            gap++;
            y--;
        }
        return gap > 0; // Nothing but air between the shell and the base.
    }

    /**
     * Logout with a pending return: same-dimension snapshots are applied directly to the
     * entity — {@code PlayerLoggedOutEvent} fires before vanilla saves the player, so the
     * restored position is what hits the disk. Cross-dimension snapshots persist in
     * {@link PendingReturns} and apply at the next login (a mid-logout dimension hop is not
     * safe). Either way the player never stays stranded at the sequence area.
     */
    private static void stashReturnOnLogout(ServerPlayer player) {
        ReturnSnapshot snapshot = RETURNS.remove(player.getUUID());
        if (snapshot == null) {
            return;
        }
        if (player.level().dimension() == snapshot.dimension()) {
            Vec3 returnPos = validatedReturnPosition(player.serverLevel(), snapshot.pos());
            player.moveTo(returnPos.x, returnPos.y, returnPos.z,
                    snapshot.yRot(), snapshot.xRot());
            player.setDeltaMovement(Vec3.ZERO);
            EclipseMod.LOGGER.info("CutsceneService: {} logged out mid-cutscene — saved back at {}",
                    player.getScoreboardName(), returnPos);
        } else {
            PendingReturns.get(player.server).put(player.getUUID(), snapshot);
            EclipseMod.LOGGER.info("CutsceneService: {} logged out mid-cutscene in another dimension — return to {} {} pending next login",
                    player.getScoreboardName(), snapshot.dimension().location(), snapshot.pos());
        }
    }

    // --- client ACKs ---

    /** Handles a {@link C2SCutsceneStatePayload} on the server thread (see {@code EclipsePayloads}). */
    public static void handleClientState(C2SCutsceneStatePayload payload, ServerPlayer player) {
        Session session = SESSIONS.get(player.getUUID());
        switch (payload.state()) {
            case STARTED -> EclipseMod.LOGGER.info("CutsceneService: {} ACK STARTED '{}'",
                    player.getScoreboardName(), payload.id());
            case FINISHED, SKIPPED -> {
                if (session == null || !session.pathId().equals(payload.id())) {
                    EclipseMod.LOGGER.debug("CutsceneService: stray {} ACK '{}' from {} (no matching session)",
                            payload.state(), payload.id(), player.getScoreboardName());
                    return;
                }
                if (!session.preview()) {
                    FreezeService.unfreeze(player);
                }
                restoreReturn(player, "client ACK " + payload.state());
                completeSession(player, "client ACK " + payload.state());
            }
            case SKIP_REQUEST -> handleSkipRequest(payload.id(), player, session);
        }
    }

    /**
     * Handles a {@link C2SCutsceneReadyPayload} on the server thread (C6): the client's
     * preload hold just ended and the flight is starting NOW — re-arm the session watchdog
     * from this moment so the hold never eats into the margin. Stray ACKs (no session,
     * superseded id) are ignored; clients that never send one (vanilla, packet loss) are
     * covered by the play-time deadline, which already budgets the full preload timeout.
     */
    public static void handleClientReady(C2SCutsceneReadyPayload payload, ServerPlayer player) {
        Session session = SESSIONS.get(player.getUUID());
        if (session == null || !session.pathId().equals(payload.id())) {
            EclipseMod.LOGGER.debug("CutsceneService: stray preload-ready ACK '{}' from {} (no matching session)",
                    payload.id(), player.getScoreboardName());
            return;
        }
        CutscenePath path = CutscenePaths.get(payload.id());
        int durationTicks = path != null ? path.durationTicks() : 0;
        session.rearmDeadline(player.server.getTickCount() + durationTicks + WATCHDOG_MARGIN_TICKS);
        EclipseMod.LOGGER.info("CutsceneService: {} preload-ready for '{}' — flight starting (watchdog re-armed)",
                player.getScoreboardName(), payload.id());
    }

    /** Grants a skip only when the session matches, the path allows it, and it is not disabled. */
    private static void handleSkipRequest(String id, ServerPlayer player, @Nullable Session session) {
        if (session == null || !session.pathId().equals(id)) {
            EclipseMod.LOGGER.debug("CutsceneService: skip request for '{}' from {} without a session — ignored",
                    id, player.getScoreboardName());
            return;
        }
        CutscenePath path = CutscenePaths.get(id);
        boolean allowed = path != null && path.allowSkip() && isEnabled(player.server, path);
        if (!allowed) {
            EclipseMod.LOGGER.info("CutsceneService: denied skip of '{}' for {} (allowSkip {})",
                    id, player.getScoreboardName(), path != null && path.allowSkip());
            return;
        }
        EclipseMod.LOGGER.info("CutsceneService: granted skip of '{}' for {}", id, player.getScoreboardName());
        if (!session.preview()) {
            FreezeService.unfreeze(player);
        }
        restoreReturn(player, "skip granted");
        PacketDistributor.sendToPlayer(player, S2CCutscenePlayPayload.STOP);
        completeSession(player, "skip granted");
    }

    /** Removes the player's session (if any) and counts them done in their group. */
    private static void completeSession(ServerPlayer player, String reason) {
        Session session = SESSIONS.remove(player.getUUID());
        if (session == null) {
            return;
        }
        EclipseMod.LOGGER.info("CutsceneService: session '{}' of {} complete ({})",
                session.pathId(), player.getScoreboardName(), reason);
        // C6 belt-and-suspenders: no cutscene may end with a red border vignette armed
        // (worlds saved pre-fix persist vanilla's 15 s warningTime; see BorderController).
        BorderController.clearWarningVisuals(player.server);
        session.group().playerDone();
    }

    // --- watchdog + lifecycle ---

    /** Session watchdog: releases watchers whose ACK never arrived once the deadline passes. */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (SESSIONS.isEmpty()) {
            return;
        }
        MinecraftServer server = event.getServer();
        long now = server.getTickCount();
        Iterator<Map.Entry<UUID, Session>> iterator = SESSIONS.entrySet().iterator();
        while (iterator.hasNext()) {
            Map.Entry<UUID, Session> entry = iterator.next();
            Session session = entry.getValue();
            if (now < session.deadlineTick()) {
                continue;
            }
            iterator.remove();
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            EclipseMod.LOGGER.warn("CutsceneService: watchdog expired session '{}' of {} — force-releasing",
                    session.pathId(), player != null ? player.getScoreboardName() : entry.getKey());
            if (player != null && !session.preview()) {
                FreezeService.unfreeze(player);
            }
            if (player != null) {
                restoreReturn(player, "watchdog");
            }
            session.group().playerDone();
        }
    }

    /** Logout completes the session so group callbacks (intro, unlock growth) never hang. */
    @SubscribeEvent
    static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            completeSession(player, "logout");
            stashReturnOnLogout(player);
        }
    }

    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        SESSIONS.clear();
        RETURNS.clear();
    }

    /** Login applies any cross-dimension return that was pending from a mid-cutscene logout. */
    @SubscribeEvent
    static void onLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) {
            return;
        }
        ReturnSnapshot snapshot = PendingReturns.get(player.server).take(player.getUUID());
        if (snapshot == null) {
            return;
        }
        ServerLevel level = player.server.getLevel(snapshot.dimension());
        if (level == null) {
            EclipseMod.LOGGER.warn("CutsceneService: pending return dimension {} of {} is gone — dropping",
                    snapshot.dimension().location(), player.getScoreboardName());
            return;
        }
        Vec3 returnPos = validatedReturnPosition(level, snapshot.pos());
        PacketDistributor.sendToPlayer(player, RETURN_FADE);
        FreezeService.transport(player, level, returnPos, snapshot.yRot(), snapshot.xRot());
        EclipseMod.LOGGER.info("CutsceneService: applied pending cutscene return of {} to {} in {}",
                player.getScoreboardName(), returnPos, snapshot.dimension().location());
    }

    // --- persisted cross-dimension returns ---

    /**
     * Cross-dimension return snapshots that could not be applied during logout, persisted in
     * the overworld's data storage ({@code data/eclipse_pending_returns.dat}) so a server
     * restart between logout and re-login still returns the player exactly.
     */
    public static final class PendingReturns extends SavedData {
        static final String DATA_NAME = "eclipse_pending_returns";
        private static final String TAG_RETURNS = "returns";

        private final Map<UUID, ReturnSnapshot> pending = new HashMap<>();

        public PendingReturns() {}

        static PendingReturns get(MinecraftServer server) {
            return server.overworld().getDataStorage().computeIfAbsent(
                    new SavedData.Factory<>(PendingReturns::new, PendingReturns::load), DATA_NAME);
        }

        static PendingReturns load(CompoundTag tag, HolderLookup.Provider registries) {
            PendingReturns data = new PendingReturns();
            for (Tag entry : tag.getList(TAG_RETURNS, Tag.TAG_COMPOUND)) {
                CompoundTag ret = (CompoundTag) entry;
                try {
                    data.pending.put(ret.getUUID("player"), new ReturnSnapshot(
                            ResourceKey.create(Registries.DIMENSION, ResourceLocation.parse(ret.getString("dim"))),
                            new Vec3(ret.getDouble("x"), ret.getDouble("y"), ret.getDouble("z")),
                            ret.getFloat("yRot"), ret.getFloat("xRot")));
                } catch (RuntimeException e) {
                    EclipseMod.LOGGER.warn("Dropping malformed pending cutscene return entry", e);
                }
            }
            return data;
        }

        @Override
        public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
            ListTag list = new ListTag();
            for (Map.Entry<UUID, ReturnSnapshot> entry : this.pending.entrySet()) {
                CompoundTag ret = new CompoundTag();
                ret.putUUID("player", entry.getKey());
                ret.putString("dim", entry.getValue().dimension().location().toString());
                ret.putDouble("x", entry.getValue().pos().x);
                ret.putDouble("y", entry.getValue().pos().y);
                ret.putDouble("z", entry.getValue().pos().z);
                ret.putFloat("yRot", entry.getValue().yRot());
                ret.putFloat("xRot", entry.getValue().xRot());
                list.add(ret);
            }
            tag.put(TAG_RETURNS, list);
            return tag;
        }

        void put(UUID player, ReturnSnapshot snapshot) {
            this.pending.put(player, snapshot);
            setDirty();
        }

        @Nullable
        ReturnSnapshot take(UUID player) {
            ReturnSnapshot snapshot = this.pending.remove(player);
            if (snapshot != null) {
                setDirty();
            }
            return snapshot;
        }
    }
}
