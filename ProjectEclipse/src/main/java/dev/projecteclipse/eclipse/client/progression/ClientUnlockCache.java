package dev.projecteclipse.eclipse.client.progression;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import dev.projecteclipse.eclipse.EclipseMod;
import dev.projecteclipse.eclipse.client.emi.EmiReindexer;
import dev.projecteclipse.eclipse.network.gate.GatePayloads;
import dev.projecteclipse.eclipse.network.gate.S2CUnlockedKeysPayload;
import dev.projecteclipse.eclipse.progression.ModGateIds;
import net.minecraft.resources.ResourceLocation;
import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

/**
 * Client cache of the server's unlock snapshot ({@link S2CUnlockedKeysPayload}, sent by
 * {@code progression.UnlockSync} on login + every unlock change). Own class per §3.12 —
 * deliberately NOT part of {@code ClientStateCache}. Frozen read API (§7.2):
 * {@link #isNamespaceLocked(String)}, {@link #isKeyUnlocked(String)} and (A16)
 * {@link #isIdLocked(ResourceLocation)} — the EMI plugin's hiding predicates consult
 * these LIVE on every EMI (re)bake.
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
    /** Raw locked {@code modgate_ids.json} globs of the last snapshot (change detection). */
    private static volatile List<String> lockedIdGlobs = List.of();
    /** The same globs compiled through {@link ModGateIds#compile} (A16 — EMI id matching). */
    private static volatile List<ModGateIds.GateRule> lockedIdRules = List.of();

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

    /**
     * Whether this exact registry id matches a currently-locked {@code modgate_ids.json}
     * glob rule per the last server snapshot (A16). The server pre-filters the synced set
     * to LOCKED rules only ({@code UnlockSync.lockedIdGlobs}), so a match means "sealed"
     * without the client needing any unlock-key knowledge — the exact counterpart of
     * {@link #isNamespaceLocked(String)} for the id-level gate.
     */
    public static boolean isIdLocked(ResourceLocation id) {
        for (ModGateIds.GateRule rule : lockedIdRules) {
            if (rule.matches(id)) {
                return true;
            }
        }
        return false;
    }

    /** Runs on the client main thread (payload handler). */
    private static void update(S2CUnlockedKeysPayload payload) {
        Set<String> newKeys = Set.copyOf(payload.keys());
        Set<String> newLocked = Set.copyOf(payload.lockedNamespaces());
        List<String> newGlobs = List.copyOf(payload.lockedIdGlobs());
        boolean changed = !newKeys.equals(unlockedKeys) || !newLocked.equals(lockedNamespaces)
                || !newGlobs.equals(lockedIdGlobs);
        unlockedKeys = newKeys;
        lockedNamespaces = newLocked;
        if (!newGlobs.equals(lockedIdGlobs)) {
            lockedIdGlobs = newGlobs;
            lockedIdRules = compileRules(newGlobs);
        }
        if (changed) {
            EclipseMod.LOGGER.debug(
                    "Unlock snapshot updated: {} keys, {} locked namespaces, {} locked id globs",
                    newKeys.size(), newLocked.size(), newGlobs.size());
            EmiReindexer.requestReload();
        }
    }

    /** Compiles synced globs with the server's own rule compiler; malformed entries drop. */
    private static List<ModGateIds.GateRule> compileRules(List<String> globs) {
        List<ModGateIds.GateRule> compiled = new ArrayList<>(globs.size());
        for (String glob : globs) {
            // The unlock key is irrelevant client-side (the server pre-filtered to locked
            // rules); a non-empty placeholder satisfies the compiler's validity contract.
            ModGateIds.GateRule rule = ModGateIds.compile(glob, "synced");
            if (rule != null) {
                compiled.add(rule);
            }
        }
        return List.copyOf(compiled);
    }

    /** Disconnect reset — unlock knowledge never leaks into the next session. */
    @SubscribeEvent
    static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
        unlockedKeys = Set.of();
        lockedNamespaces = Set.of();
        lockedIdGlobs = List.of();
        lockedIdRules = List.of();
    }
}
