package dev.projecteclipse.eclipse.client.progression;

import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.emi.EmiReindexer;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CUnlockedKeysPayload;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client cache of the server's unlock snapshot ({@link S2CUnlockedKeysPayload}, sent by
 * {@code progression.UnlockSync} on login + every unlock change). Own class per §3.12 —
 * deliberately NOT part of {@code ClientStateCache}. Frozen read API (§7.2):
 * {@link #isNamespaceLocked(String)} and {@link #isKeyUnlocked(String)} — the EMI plugin's
 * hiding predicates consult these LIVE on every EMI (re)bake.
 *
 * <p>On every snapshot that actually changes the state, {@link EmiReindexer#requestReload()}
 * asks EMI (reflection, optional-mod-safe) to rebuild its index so newly-unlocked content
 * appears without a relog. Defaults are permissive (nothing locked) so a vanilla-ish session
 * without the payload — or the brief pre-login window — never hides unlockable content;
 * the always-hidden {@code #eclipse:emi_hidden} tag is independent of this cache.</p>
 *
 * <p>Class is client-only ({@code Dist.CLIENT} subscriber): the annotation scan loads it on
 * client startup, its static init installs the {@link GatePayloads} consumer, and the logout
 * hook resets state so one server's unlocks never leak into the next session
 * ({@code ClientStateCache.DisconnectReset} pattern).</p>
 */
@EventBusSubscriber(modid = EclipseMod.MOD_ID, value = Dist.CLIENT)
public final class ClientUnlockCache {
    private static volatile Set<String> unlockedKeys = Set.of();
    private static volatile Set<String> lockedNamespaces = Set.of();

    static {
        // Payload consumer seam (GrowthPayloads pattern): installed on client class-load,
        // so GatePayloads itself never references client classes.
        GatePayloads.setClientUnlocksHandler(ClientUnlockCache::update);
    }

    private ClientUnlockCache() {}

    /** Whether the namespace is currently ModGate-locked per the last server snapshot (§7.2). */
    public static boolean isNamespaceLocked(String namespace) {
        return lockedNamespaces.contains(namespace);
    }

    /** Whether the progression gate key is unlocked per the last server snapshot (§7.2). */
    public static boolean isKeyUnlocked(String key) {
        return unlockedKeys.contains(key);
    }

    /** Runs on the client main thread (payload handler). */
    private static void update(S2CUnlockedKeysPayload payload) {
        Set<String> newKeys = Set.copyOf(payload.keys());
        Set<String> newLocked = Set.copyOf(payload.lockedNamespaces());
        boolean changed = !newKeys.equals(unlockedKeys) || !newLocked.equals(lockedNamespaces);
        unlockedKeys = newKeys;
        lockedNamespaces = newLocked;
        if (changed) {
            EclipseMod.LOGGER.debug("Unlock snapshot updated: {} keys, {} locked namespaces",
                    newKeys.size(), newLocked.size());
            EmiReindexer.requestReload();
        }
    }

    /** Disconnect reset — unlock knowledge never leaks into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        unlockedKeys = Set.of();
        lockedNamespaces = Set.of();
    }
}
