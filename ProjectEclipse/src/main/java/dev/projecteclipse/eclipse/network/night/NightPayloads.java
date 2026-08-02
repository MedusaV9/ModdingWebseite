package dev.projecteclipse.eclipse.network.night;

import java.util.function.Consumer;

import javax.annotation.Nullable;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.state.EclipseWorldState;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.PacketDistributor;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.handling.IPayloadContext;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * WAVE6 (F-106 A) A1 — self-registering registrar for the night-event sync payload
 * ({@code BestiaryPayloads} pattern): own MOD-bus {@link RegisterPayloadHandlersEvent}
 * subscriber under version group {@value #VERSION}, so {@code EclipsePayloads} and
 * {@code EclipseMod} stay untouched. The payload id is {@code eclipse:night/event}.
 *
 * <p>Send sites (plan §3 A1): {@code EclipseSpawner.announceNightEvent} (nightfall),
 * {@code EclipseSpawner.clearNightEvent} (dawn, event = none) and the {@link Sync}
 * login subscriber below ({@code EclipseWorldState.getActiveNightEvent()} READ-only).
 * {@link Sync#onServerTick} additionally watches for state writes that bypass both
 * spawner hooks — concretely {@code /eclipse event set none}, which clears the state
 * directly (the {@code umbral|pale} branches of the command DO call
 * {@code announceNightEvent}) — so the client can never be left rendering a stale
 * Umbral moon after an operator override. The watcher costs one saved-data lookup per
 * {@value Sync#WATCH_CADENCE_TICKS} ticks and stays silent while the explicit sends
 * keep {@link #lastSyncedEvent} current.</p>
 *
 * <p>Client dispatch uses an installable {@link Consumer} hook so this class stays
 * loadable on dedicated servers (no eager client-class references):
 * {@code client.drama.NightDreadFx} installs its consumer from its own static
 * initializer. Payloads received while no handler is installed are dropped
 * (debug-logged).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, bus = EventBusSubscriber.Bus.MOD)
public final class NightPayloads {
    private static final String VERSION = "night1";

    /** Client-side sink installed by {@code client.drama.NightDreadFx}. */
    private static volatile Consumer<S2CNightEventPayload> clientHandler;

    /**
     * Event string of the last {@link #broadcast}; {@code null} until the first watcher
     * baseline after boot. Lets {@link Sync#onServerTick} fire ONLY when a state write
     * bypassed the explicit send sites.
     */
    @Nullable
    private static volatile String lastSyncedEvent;

    private NightPayloads() {}

    @SubscribeEvent
    static void onRegisterPayloadHandlers(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar(VERSION);
        registrar.playToClient(S2CNightEventPayload.TYPE, S2CNightEventPayload.STREAM_CODEC,
                NightPayloads::handleNightEvent);
    }

    // ------------------------------------------------------------------ server send helpers

    /**
     * Broadcasts the night-event state to every online player and stamps the drift
     * marker. {@code origin} is the probe tag — {@code nightfall} or {@code dawn}
     * (the login path logs its own {@code login} line per player).
     */
    public static void broadcast(MinecraftServer server, String event, int day, String origin) {
        lastSyncedEvent = event;
        PacketDistributor.sendToAllPlayers(new S2CNightEventPayload(event, day));
        EclipseMod.LOGGER.debug("[w6a-nightsync] event={} day={} ({})", event, day, origin);
    }

    // ------------------------------------------------------------------ client dispatch

    /** Installed by {@code client.drama.NightDreadFx} on client class-load. */
    public static void setClientHandler(Consumer<S2CNightEventPayload> handler) {
        clientHandler = handler;
    }

    /** Runs on the client main thread only; no client classes referenced eagerly. */
    private static void handleNightEvent(S2CNightEventPayload payload, IPayloadContext context) {
        Consumer<S2CNightEventPayload> handler = clientHandler;
        if (handler != null) {
            handler.accept(payload);
        } else {
            EclipseMod.LOGGER.debug("Night event sync '{}' (day {}) — no client handler installed",
                    payload.event(), payload.day());
        }
    }

    // ------------------------------------------------------------------ GAME-bus half

    /**
     * Login re-send + operator-override drift watcher + world-switch reset (the
     * {@code Wave5BossFxRows.TrophyWisp} nested-subscriber shape, GAME bus).
     */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID)
    public static final class Sync {
        /** Drift-watch cadence (1 s): fast enough for a live command override review. */
        static final int WATCH_CADENCE_TICKS = 20;

        private Sync() {}

        /** Late joiners inherit the running night event (READ-only state access). */
        @SubscribeEvent
        static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
            if (!(event.getEntity() instanceof ServerPlayer player)) {
                return;
            }
            MinecraftServer server = player.getServer();
            if (server == null) {
                return;
            }
            EclipseWorldState state = EclipseWorldState.get(server);
            PacketDistributor.sendToPlayer(player,
                    new S2CNightEventPayload(state.getActiveNightEvent(), state.getNightEventDay()));
            EclipseMod.LOGGER.debug("[w6a-nightsync] event={} day={} (login)",
                    state.getActiveNightEvent(), state.getNightEventDay());
        }

        /** Re-syncs when a state write bypassed both spawner hooks (command override). */
        @SubscribeEvent
        static void onServerTick(ServerTickEvent.Post event) {
            MinecraftServer server = event.getServer();
            if (server.getTickCount() % WATCH_CADENCE_TICKS != 0) {
                return;
            }
            EclipseWorldState state = EclipseWorldState.get(server);
            String active = state.getActiveNightEvent();
            String synced = lastSyncedEvent;
            if (synced == null) {
                lastSyncedEvent = active; // boot baseline — login sends cover the players
                return;
            }
            if (!active.equals(synced)) {
                broadcast(server, active, state.getNightEventDay(),
                        EclipseWorldState.NIGHT_EVENT_NONE.equals(active) ? "dawn" : "nightfall");
            }
        }

        /** World-scoped static must not leak into the next world (singleplayer switch). */
        @SubscribeEvent
        static void onServerStopped(ServerStoppedEvent event) {
            lastSyncedEvent = null;
        }
    }
}
