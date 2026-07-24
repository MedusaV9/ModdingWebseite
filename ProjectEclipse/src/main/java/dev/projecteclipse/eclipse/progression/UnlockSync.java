package dev.projecteclipse.eclipse.progression;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.core.config.EclipseConfig;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CUnlockedKeysPayload;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.server.ServerStoppedEvent;
import net.neoforged.neoforge.event.tick.ServerTickEvent;

/**
 * Server sender for {@link S2CUnlockedKeysPayload} (P3 §3.12, W11): syncs the derived
 * {@link UnlockState} key set plus the currently-locked {@link ModGate} namespaces to clients
 * so the EMI plugin can hide still-locked content ({@code client.progression.ClientUnlockCache}
 * is the receiving cache).
 *
 * <p>Send policy: one snapshot to each player on login, plus a broadcast whenever the derived
 * state changes. {@code UnlockState} has no mutation events — it is re-derived from world
 * state/config on demand (day change, altar level, Herald kill, {@code /eclipse reload} and
 * dev commands all feed it indirectly) — so change detection is a cheap 1 Hz poll of the
 * memoized snapshot ({@code RecipeGate}'s sweep-poll precedent; the derivation itself caches,
 * see {@link UnlockState#unlockedKeys}). If P4 later refactors {@code UnlockState} to push
 * change notifications, call {@link #broadcastAll(MinecraftServer)} from that hook and drop
 * the poll (§5.1 contract note).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID)
public final class UnlockSync {
    private static final int POLL_INTERVAL_TICKS = 20;
    /** Offset so the poll never lands on the ModGate (50) or PhaseInventoryLock (0) sweep ticks. */
    private static final int POLL_PHASE = 13;

    /** Last broadcast unlocked-key set; {@code null} = nothing broadcast yet. Server thread only. */
    private static Set<String> lastKeys;
    private static List<String> lastLockedNamespaces;

    private UnlockSync() {}

    /** Snapshot payload of the current unlock state (keys + locked ModGate namespaces). */
    public static S2CUnlockedKeysPayload payloadFor(MinecraftServer server) {
        Set<String> keys = UnlockState.unlockedKeys(server);
        return new S2CUnlockedKeysPayload(List.copyOf(keys), lockedNamespaces(server));
    }

    /** Sends the current snapshot to one player. */
    public static void syncTo(ServerPlayer player) {
        GatePayloads.sendUnlockedKeys(player, payloadFor(player.server));
    }

    /** Broadcasts the current snapshot to every online player. */
    public static void broadcastAll(MinecraftServer server) {
        S2CUnlockedKeysPayload payload = payloadFor(server);
        for (ServerPlayer player : server.getPlayerList().getPlayers()) {
            GatePayloads.sendUnlockedKeys(player, payload);
        }
    }

    @SubscribeEvent
    static void onPlayerLoggedIn(PlayerEvent.PlayerLoggedInEvent event) {
        if (event.getEntity() instanceof ServerPlayer player) {
            syncTo(player);
        }
    }

    @SubscribeEvent
    static void onServerTick(ServerTickEvent.Post event) {
        MinecraftServer server = event.getServer();
        if (server.getTickCount() % POLL_INTERVAL_TICKS != POLL_PHASE) {
            return;
        }
        Set<String> keys = UnlockState.unlockedKeys(server);
        List<String> locked = lockedNamespaces(server);
        if (keys.equals(lastKeys) && locked.equals(lastLockedNamespaces)) {
            return;
        }
        boolean firstPoll = lastKeys == null;
        lastKeys = keys;
        lastLockedNamespaces = locked;
        if (firstPoll) {
            return; // baseline capture at boot; login sends already covered anyone online
        }
        EclipseMod.LOGGER.info("Unlock state changed ({} keys, {} locked namespaces) — broadcasting",
                keys.size(), locked.size());
        broadcastAll(server);
    }

    /** The baseline pins the last world's state — drop it with the server. */
    @SubscribeEvent
    static void onServerStopped(ServerStoppedEvent event) {
        lastKeys = null;
        lastLockedNamespaces = null;
    }

    private static List<String> lockedNamespaces(MinecraftServer server) {
        List<String> locked = new ArrayList<>();
        for (String namespace : EclipseConfig.modGate().gatedNamespaces()) {
            if (ModGate.isNamespaceLocked(server, namespace)) {
                locked.add(namespace);
            }
        }
        return locked;
    }
}
