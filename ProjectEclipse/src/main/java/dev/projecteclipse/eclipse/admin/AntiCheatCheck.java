package dev.projecteclipse.eclipse.admin;

import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.C2SModlistPayload;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.ModList;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.fml.event.lifecycle.FMLClientSetupEvent;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;
import net.neoforged.neoforge.network.PacketDistributor;

/**
 * Modlist anti-cheat backed by the {@code config/eclipse/anticheat.json} blocklist of mod-id
 * substrings (config-maintained; see {@link EclipseConfig#antiCheat()}).
 *
 * <p>Three layers, all honest-client deterrents only (see the README's known limitations —
 * a modified client can spoof every one of them; server-side anti-xray is the real fix):</p>
 * <ul>
 *   <li><b>Client self-check</b> — {@link Client#onClientSetup} throws during
 *       {@code FMLClientSetupEvent} when a blocklisted mod is installed locally, so the
 *       game refuses to finish loading (forced crash per spec).</li>
 *   <li><b>Server modlist check</b> — clients send {@link C2SModlistPayload} on login;
 *       {@link #handleModlist} disconnects the player when any reported id matches.</li>
 *   <li><b>Timeout check</b> — {@link #onServerTick} disconnects players that never sent
 *       the payload within {@value #MODLIST_TIMEOUT_MILLIS} ms (mandatory-mod enforcement).</li>
 * </ul>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class AntiCheatCheck {
    /** How long after login a client may take to report its modlist before being kicked. */
    static final long MODLIST_TIMEOUT_MILLIS = 30_000L;
    private static final int CHECK_INTERVAL_TICKS = 20;

    /** Online players that have not reported a modlist yet: player UUID → login epoch millis. */
    private static final Map<UUID, Long> awaitingModlist = new ConcurrentHashMap<>();

    private AntiCheatCheck() {}

    /**
     * The first mod id that matches the {@code anticheat.json} blocklist (case-insensitive
     * substring match), or {@code null} when the collection is clean.
     */
    public static String findBlockedModId(Collection<String> modIds) {
        List<String> blocklist = EclipseConfig.antiCheat().blockedModIdSubstrings();
        for (String modId : modIds) {
            String lowerId = modId.toLowerCase(Locale.ROOT);
            for (String blocked : blocklist) {
                if (!blocked.isBlank() && lowerId.contains(blocked.toLowerCase(Locale.ROOT))) {
                    return modId;
                }
            }
        }
        return null;
    }

    /** The sorted ids of every mod loaded in this game instance. */
    public static List<String> loadedModIds() {
        return ModList.get().getMods().stream()
                .map(info -> info.getModId())
                .sorted()
                .toList();
    }

    /** Server handler for {@link C2SModlistPayload}; wired in {@code EclipsePayloads}. */
    public static void handleModlist(C2SModlistPayload payload, ServerPlayer player) {
        awaitingModlist.remove(player.getUUID());
        String blocked = findBlockedModId(payload.modIds());
        if (blocked != null) {
            EclipseMod.LOGGER.warn("Anti-cheat: {} reported blocklisted client mod '{}'; disconnecting",
                    player.getScoreboardName(), blocked);
            player.connection.disconnect(Component.literal(
                    "Project: Eclipse — the client mod '" + blocked + "' is not allowed on this server."));
            return;
        }
        EclipseMod.LOGGER.info("Anti-cheat: {} reported {} client mods, none blocklisted",
                player.getScoreboardName(), payload.modIds().size());
    }

    @SubscribeEvent
    public static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            awaitingModlist.put(player.getUUID(), System.currentTimeMillis());
        }
    }

    @SubscribeEvent
    public static void onPlayerLoggedOut(PlayerEvent.PlayerLoggedOutEvent event) {
        awaitingModlist.remove(event.getEntity().getUUID());
    }

    /** Kicks players whose client never reported a modlist within the timeout. */
    @SubscribeEvent
    public static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % CHECK_INTERVAL_TICKS != 0 || awaitingModlist.isEmpty()) {
            return;
        }
        long now = System.currentTimeMillis();
        for (Map.Entry<UUID, Long> entry : awaitingModlist.entrySet()) {
            if (now - entry.getValue() < MODLIST_TIMEOUT_MILLIS) {
                continue;
            }
            awaitingModlist.remove(entry.getKey());
            ServerPlayer player = server.getPlayerList().getPlayer(entry.getKey());
            if (player != null) {
                EclipseMod.LOGGER.warn("Anti-cheat: {} never reported a modlist within {} ms; disconnecting",
                        player.getScoreboardName(), MODLIST_TIMEOUT_MILLIS);
                player.connection.disconnect(Component.literal(
                        "Project: Eclipse — this server requires the Eclipse-Core client mod "
                                + "(modlist check timed out)."));
            }
        }
    }

    /** Client-side half: local blocklist crash + modlist reporting. Only classloaded on the client. */
    @EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
    public static final class Client {
        private Client() {}

        /** Forced crash during client setup when a blocklisted mod is installed locally. */
        @SubscribeEvent
        static void onClientSetup(FMLClientSetupEvent event) {
            String blocked = findBlockedModId(loadedModIds());
            if (blocked != null) {
                throw new RuntimeException("Project: Eclipse anti-cheat — the installed mod '" + blocked
                        + "' is blocklisted on Eclipse event servers. Remove it and restart the game.");
            }
            EclipseMod.LOGGER.info("Anti-cheat client self-check passed ({} mods loaded)", loadedModIds().size());
        }

        /** Reports the local modlist to the server as soon as the play connection is up. */
        @SubscribeEvent
        static void onLoggingIn(ClientPlayerNetworkEvent.LoggingIn event) {
            List<String> modIds = loadedModIds();
            PacketDistributor.sendToServer(new C2SModlistPayload(modIds));
            EclipseMod.LOGGER.info("Anti-cheat: sent modlist ({} mods) to the server", modIds.size());
        }
    }
}
