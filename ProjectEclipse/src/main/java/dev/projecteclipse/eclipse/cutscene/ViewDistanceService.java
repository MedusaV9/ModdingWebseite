package dev.projecteclipse.eclipse.cutscene;

import java.util.Collection;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.network.fx.S2CViewDistancePayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppingEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server side of the cinematic view-distance bump (P2 R12): while a cinematic session is
 * active the server raises {@code PlayerList.setViewDistance(min(}{@value #MAX_SERVER_CHUNKS}{@code , current + }{@value #SERVER_BUMP_CHUNKS}{@code ))}
 * so the chunks the camera flies over are actually sent, and pushes
 * {@link S2CViewDistancePayload} to the watchers so their clients raise
 * {@code options.renderDistance} too (client side is opt-out via the
 * {@code cinematicViewDistance} toggle; see {@code cutscene.client.ViewDistanceClient}).
 *
 * <p><b>Lifecycle</b>: {@link #begin} / {@link #end} are refcounted so overlapping global
 * cutscenes never double-restore. Every {@code begin} arms a watchdog TTL — if a caller
 * forgets (or crashes before) {@code end}, the tick watchdog force-restores; a stopping
 * server restores too (belt and braces: the vanilla restart path re-reads
 * {@code server.properties} anyway). On an integrated server the host's own render-distance
 * option re-asserts itself every tick, so the server-side bump is effectively driven by the
 * client push there — both paths stay harmless.</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class ViewDistanceService {
    /** Server view distance is never raised past this (risk §7.6: memory/CPU on big maps). */
    public static final int MAX_SERVER_CHUNKS = 12;
    /** Raise amount over the configured server view distance. */
    public static final int SERVER_BUMP_CHUNKS = 4;
    /** Watchdog slack added on top of a session's requested TTL. */
    private static final int WATCHDOG_MARGIN_TICKS = 200;

    /** The pre-bump server view distance, or {@code -1} while no bump is active. */
    private static int originalViewDistance = -1;
    /** Refcount of active cinematic sessions. */
    private static int activeSessions;
    /** Force-restore deadline in remaining ticks (max over all active sessions). */
    private static int watchdogTicks;
    /** Players who received a non-zero push and still owe a restore payload. */
    private static final Set<UUID> PUSHED = new HashSet<>();

    private ViewDistanceService() {}

    /**
     * Starts one cinematic view-distance session: bumps the server view distance (first
     * session only) and pushes {@code clientChunks} to every given watcher. No-op when
     * {@code clientChunks <= 0}. Pair with exactly one {@link #end}; the watchdog covers
     * callers that never get there ({@code ttlTicks} ≈ cutscene duration).
     */
    public static void begin(MinecraftServer server, Collection<ServerPlayer> players,
            int clientChunks, int ttlTicks) {
        if (clientChunks <= 0) {
            return;
        }
        if (originalViewDistance < 0) {
            originalViewDistance = server.getPlayerList().getViewDistance();
            int bumped = Math.min(MAX_SERVER_CHUNKS, originalViewDistance + SERVER_BUMP_CHUNKS);
            if (bumped > originalViewDistance) {
                server.getPlayerList().setViewDistance(bumped);
                EclipseMod.LOGGER.info("ViewDistanceService: server view distance {} -> {} (cinematic)",
                        originalViewDistance, bumped);
            }
        }
        activeSessions++;
        watchdogTicks = Math.max(watchdogTicks, Math.max(1, ttlTicks) + WATCHDOG_MARGIN_TICKS);
        int capped = Math.min(MAX_SERVER_CHUNKS + SERVER_BUMP_CHUNKS, clientChunks);
        S2CViewDistancePayload payload = new S2CViewDistancePayload(capped);
        for (ServerPlayer player : players) {
            PUSHED.add(player.getUUID());
            net.neoforged.neoforge.network.PacketDistributor.sendToPlayer(player, payload);
        }
        EclipseMod.LOGGER.info("ViewDistanceService: session start ({} active) — pushed {} chunks to {} player(s)",
                activeSessions, capped, players.size());
    }

    /** Ends one session; the last one out restores the server + all pushed clients. */
    public static void end(MinecraftServer server) {
        if (activeSessions <= 0) {
            return;
        }
        if (--activeSessions == 0) {
            restore(server, "session end");
        }
    }

    /** Dev/emergency reset: drops every session and restores immediately. */
    public static void reset(MinecraftServer server) {
        if (activeSessions > 0 || originalViewDistance >= 0 || !PUSHED.isEmpty()) {
            restore(server, "forced reset");
        }
    }

    /** Whether a cinematic bump is currently active (dev-command display). */
    public static boolean isActive() {
        return activeSessions > 0 || originalViewDistance >= 0;
    }

    private static void restore(MinecraftServer server, String reason) {
        for (UUID id : PUSHED) {
            ServerPlayer player = server.getPlayerList().getPlayer(id);
            if (player != null) {
                net.neoforged.neoforge.network.PacketDistributor.sendToPlayer(
                        player, new S2CViewDistancePayload(0));
            }
        }
        PUSHED.clear();
        if (originalViewDistance >= 0) {
            server.getPlayerList().setViewDistance(originalViewDistance);
            EclipseMod.LOGGER.info("ViewDistanceService: server view distance restored to {} ({})",
                    originalViewDistance, reason);
            originalViewDistance = -1;
        }
        activeSessions = 0;
        watchdogTicks = 0;
    }

    /** Watchdog: a session whose owner never called {@link #end} restores anyway. */
    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        if (activeSessions <= 0) {
            return;
        }
        if (--watchdogTicks <= 0) {
            EclipseMod.LOGGER.warn("ViewDistanceService: watchdog expired with {} session(s) open — force-restoring",
                    activeSessions);
            restore(event.getServer(), "watchdog");
        }
    }

    /** A leaving player owes no restore payload anymore (their client restores on logout). */
    @SubscribeEvent
    static void onLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            PUSHED.remove(player.getUUID());
        }
    }

    /** Server stop: put the configured value back so nothing odd is saved. */
    @SubscribeEvent
    static void onServerStopping(ServerStoppingEvent event) {
        if (isActive()) {
            restore(event.getServer(), "server stopping");
        }
    }
}
