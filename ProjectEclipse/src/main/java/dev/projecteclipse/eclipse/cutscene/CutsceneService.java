package dev.projecteclipse.eclipse.cutscene;

import java.util.Collection;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import dev.projecteclipse.eclipse.network.C2SCutsceneStatePayload;
import dev.projecteclipse.eclipse.network.S2CCutsceneLibraryPayload;
import dev.projecteclipse.eclipse.network.S2CCutscenePlayPayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
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

    /** One player's active playback; {@code preview} sessions have no freeze to release. */
    private record Session(String pathId, long deadlineTick, boolean preview, Group group) {}

    /** Active sessions by player UUID. Server-thread only (tick + main-thread payload handlers). */
    private static final Map<UUID, Session> SESSIONS = new HashMap<>();

    private CutsceneService() {}

    // --- library sync ---

    /** Sends the full path library to one player (login sync; see {@code EclipsePayloads}). */
    public static void syncLibraryTo(ServerPlayer player) {
        PacketDistributor.sendToPlayer(player, new S2CCutsceneLibraryPayload(CutscenePaths.rawJsonById()));
    }

    /** Re-sends the full path library to everyone (after {@code reloadpaths} / editor writes). */
    public static void syncLibraryToAll(MinecraftServer server) {
        PacketDistributor.sendToAllPlayers(new S2CCutsceneLibraryPayload(CutscenePaths.rawJsonById()));
    }

    // --- enable / disable ---

    /** Whether a path may play: its JSON {@code enabled} flag AND the per-world disabled set. */
    public static boolean isEnabled(MinecraftServer server, CutscenePath path) {
        return path.enabled() && !EclipseWorldState.get(server).isCutsceneDisabled(path.id());
    }

    // --- playback ---

    /** Plays a path for the given players (freeze + play payload). Returns watchers started. */
    public static int play(String id, Collection<ServerPlayer> players) {
        return play(id, players, null, null);
    }

    /**
     * Full play form: {@code anchor} overrides the world-anchor origin (e.g. the nearest new
     * ring edge for {@code unlock_ring}); {@code onAllFinished} runs on the server thread once
     * every watcher has ACKed, been watchdog-released, or logged out — and runs immediately
     * when the path is missing/disabled or {@code players} is empty (never softlocks a
     * caller's timeline).
     */
    public static int play(String id, Collection<ServerPlayer> players, @Nullable Vec3 anchor,
            @Nullable Runnable onAllFinished) {
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

        int watchdogTicks = path.durationTicks() + WATCHDOG_MARGIN_TICKS;
        long deadline = server.getTickCount() + watchdogTicks;
        boolean intro = id.startsWith("intro_");
        Group group = new Group(id, players.size(), onAllFinished);
        S2CCutscenePlayPayload payload =
                new S2CCutscenePlayPayload(id, path.allowSkip(), Optional.ofNullable(anchor));
        for (ServerPlayer player : players) {
            // A newer cutscene supersedes any active session (its group completes as skipped).
            completeSession(player, "superseded by '" + id + "'");
            FreezeService.freeze(player, watchdogTicks, intro, 0);
            SESSIONS.put(player.getUUID(), new Session(id, deadline, false, group));
            PacketDistributor.sendToPlayer(player, payload);
        }
        EclipseMod.LOGGER.info("CutsceneService: playing '{}' for {} player(s) "
                + "(duration {} ticks, watchdog {} ticks, allowSkip {}, anchor {})",
                id, players.size(), path.durationTicks(), watchdogTicks, path.allowSkip(), anchor);
        return players.size();
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

    /** Aborts the given players' active cutscenes: unfreeze + client stop sentinel. */
    public static int abort(Collection<ServerPlayer> players) {
        int aborted = 0;
        for (ServerPlayer player : players) {
            boolean hadSession = SESSIONS.containsKey(player.getUUID());
            completeSession(player, "aborted");
            FreezeService.unfreeze(player);
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
                completeSession(player, "client ACK " + payload.state());
                if (!session.preview()) {
                    FreezeService.unfreeze(player);
                }
            }
            case SKIP_REQUEST -> handleSkipRequest(payload.id(), player, session);
        }
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
        completeSession(player, "skip granted");
        if (!session.preview()) {
            FreezeService.unfreeze(player);
        }
        PacketDistributor.sendToPlayer(player, S2CCutscenePlayPayload.STOP);
    }

    /** Removes the player's session (if any) and counts them done in their group. */
    private static void completeSession(ServerPlayer player, String reason) {
        Session session = SESSIONS.remove(player.getUUID());
        if (session == null) {
            return;
        }
        EclipseMod.LOGGER.info("CutsceneService: session '{}' of {} complete ({})",
                session.pathId(), player.getScoreboardName(), reason);
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
            session.group().playerDone();
        }
    }

    /** Logout completes the session so group callbacks (intro, unlock growth) never hang. */
    @SubscribeEvent
    static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            completeSession(player, "logout");
        }
    }
}
